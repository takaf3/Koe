import XCTest
import AppKit
@testable import Koe

final class PushToTalkTests: XCTestCase {
    func testHotkeyProducesOnePressAndOneReleaseDespiteKeyRepeat() {
        var state = HotKeyPressState()
        XCTAssertNil(state.handle(pressed: false))
        XCTAssertEqual(state.handle(pressed: true), .pressed)
        for _ in 0..<20 { XCTAssertNil(state.handle(pressed: true)) }
        XCTAssertEqual(state.handle(pressed: false), .released)
        XCTAssertNil(state.handle(pressed: false))
        XCTAssertEqual(state.handle(pressed: true), .pressed)
        state.reset()
        XCTAssertNil(state.handle(pressed: false))
    }

    @MainActor func testHoldRecordsAndReleaseFinishesExactlyOnce() async throws {
        let recorder = TestRecorder()
        let model = makeModel(recorder: recorder)
        defer { model.cancel(); model.hotKey.invalidate() }
        model.hotKey.onPress?()
        XCTAssertEqual(model.phase, .preparing)
        try await waitFor { recorder.startCount == 1 }
        XCTAssertEqual(model.phase, .recording)
        XCTAssertTrue(recorder.isRecording)
        XCTAssertTrue(model.isHoldingHotKey)
        model.hotKey.onPress?()
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(model.phase, .recording)
        model.hotKey.onRelease?()
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(model.isHoldingHotKey)
        XCTAssertEqual(model.phase, .transcribing)
        model.hotKey.onRelease?()
        XCTAssertEqual(model.phase, .transcribing)
        XCTAssertEqual(recorder.startCount, 1)
        XCTAssertEqual(recorder.stopCount, 1)
        // Cancel before the recognition task runs; this test never opens a real audio file.
    }

    @MainActor func testReleaseBeforePermissionCompletesNeverStartsMicrophone() async throws {
        let recorder = TestRecorder()
        let permission = PermissionGate()
        let model = makeModel(recorder: recorder, permission: { await permission.request() })
        defer { model.cancel(); model.hotKey.invalidate() }
        model.hotKey.onPress?()
        try await waitFor { permission.requests.count == 1 }
        model.hotKey.onRelease?()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(model.isHoldingHotKey)
        permission.requests[0].resume(returning: true)
        try await waitFor { permission.returned == 1 }
        XCTAssertEqual(recorder.startCount, 0)
        XCTAssertEqual(recorder.stopCount, 0)
        XCTAssertEqual(model.phase, .idle)
    }

    @MainActor func testNewHoldCannotBeStartedByAnOlderPermissionResponse() async throws {
        let recorder = TestRecorder()
        let permission = PermissionGate()
        let model = makeModel(recorder: recorder, permission: { await permission.request() })
        defer { model.cancel(); model.hotKey.invalidate() }
        model.hotKey.onPress?()
        try await waitFor { permission.requests.count == 1 }
        model.hotKey.onRelease?()
        model.hotKey.onPress?()
        try await waitFor { permission.requests.count == 2 }
        permission.requests[0].resume(returning: true)
        try await waitFor { permission.returned == 1 }
        XCTAssertEqual(recorder.startCount, 0)
        XCTAssertEqual(model.phase, .preparing)
        permission.requests[1].resume(returning: true)
        try await waitFor { recorder.startCount == 1 }
        XCTAssertEqual(model.phase, .recording)
        model.hotKey.onRelease?()
        XCTAssertEqual(recorder.stopCount, 1)
        XCTAssertEqual(model.phase, .transcribing)
    }

    @MainActor func testCancelWhileHeldDoesNotTranscribeOnRelease() async throws {
        let recorder = TestRecorder()
        let model = makeModel(recorder: recorder)
        defer { model.cancel(); model.hotKey.invalidate() }
        model.hotKey.onPress?()
        try await waitFor { recorder.isRecording }
        model.cancel()
        model.hotKey.onRelease?()
        XCTAssertFalse(recorder.isRecording)
        XCTAssertFalse(model.isHoldingHotKey)
        XCTAssertEqual(recorder.stopCount, 0)
        XCTAssertEqual(model.phase, .idle)
    }

    @MainActor func testDeniedPermissionCannotLeaveARecordingHeldOpen() async throws {
        let recorder = TestRecorder()
        let model = makeModel(recorder: recorder, permission: { false })
        defer { model.cancel(); model.hotKey.invalidate() }
        model.hotKey.onPress?()
        try await waitFor { model.phase == .failure }
        model.hotKey.onRelease?()
        XCTAssertEqual(model.phase, .failure)
        XCTAssertFalse(model.isHoldingHotKey)
        XCTAssertEqual(recorder.startCount, 0)
    }

    func testIndicatorHasVisibleStableBoundsThroughoutDictation() {
        let frame = CGRect(x: -1024, y: 120, width: 1024, height: 680)
        let preparing = OverlayLayout.frame(for: .preparing, in: frame)
        let recording = OverlayLayout.frame(for: .recording, in: frame)
        let transcribing = OverlayLayout.frame(for: .transcribing, in: frame)
        XCTAssertEqual(preparing, recording)
        XCTAssertEqual(recording, transcribing)
        XCTAssertEqual(recording, OverlayLayout.frame(for: .message, in: frame))
        XCTAssertEqual(recording.size, CGSize(width: 216, height: 52))
        for phase: DictationPhase in [.preparing, .recording, .transcribing, .choosing, .failure, .message] {
            let panel = OverlayLayout.frame(for: phase, in: frame)
            XCTAssertTrue(frame.contains(panel))
            XCTAssertEqual(panel.midX, frame.midX)
        }
    }

    @MainActor func testNativeIndicatorAppearsWithoutTakingKeyboardFocus() async throws {
        guard !NSScreen.screens.isEmpty else { throw XCTSkip("A display is required for the native panel check.") }
        let model = makeModel(recorder: TestRecorder())
        let overlay = OverlayController(model: model)
        defer { model.cancel(); overlay.update(phase: .idle); model.hotKey.invalidate() }
        model.phase = .recording
        overlay.update(phase: .recording)
        let panel = try XCTUnwrap(NSApplication.shared.windows.compactMap { $0 as? DictationPanel }.last)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertEqual(panel.frame.size, OverlayLayout.size(for: .recording))
        let recordingFrame = panel.frame
        for level in [0.0, 0.5, 1.0] {
            model.levelHistory = Array(repeating: level, count: 23)
            try await Task.sleep(for: .milliseconds(20))
            panel.contentView?.layoutSubtreeIfNeeded()
            XCTAssertEqual(panel.frame, recordingFrame)
        }
        model.phase = .transcribing
        overlay.update(phase: .transcribing)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, recordingFrame)
        model.noticeTitle = "Sent"
        model.message = "Sent to an application with a very long name that must not resize the HUD"
        model.phase = .message
        overlay.update(phase: .message)
        try await Task.sleep(for: .milliseconds(20))
        panel.contentView?.layoutSubtreeIfNeeded()
        XCTAssertTrue(panel.isVisible)
        XCTAssertEqual(panel.frame, recordingFrame)
        XCTAssertEqual(panel.contentView?.frame.size, recordingFrame.size)
        overlay.update(phase: .idle)
        XCTAssertFalse(panel.isVisible)
    }

    @MainActor private func makeModel(recorder: TestRecorder,
                                     permission: @escaping @MainActor () async -> Bool = { true }) -> AppModel {
        // An isolated suite keeps the installed app's language choices out of the test.
        let model = AppModel(defaults: UserDefaults(suiteName: "KoeTests.pushToTalk.\(UUID().uuidString)")!,
                             startServices: false, preferredLanguages: ["ja-JP", "en-US"],
                             recorder: recorder, microphonePermission: permission)
        model.models = ["en-US": .installed, "ja-JP": .installed, "fr-FR": .installed]
        return model
    }

    @MainActor private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !condition() {
            if ContinuousClock.now >= deadline { throw WaitFailure.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    private enum WaitFailure: Error { case timedOut }
}

@MainActor private final class PermissionGate {
    var requests: [CheckedContinuation<Bool, Never>] = []
    var returned = 0
    func request() async -> Bool {
        let granted = await withCheckedContinuation { requests.append($0) }
        returned += 1
        return granted
    }
}

@MainActor private final class TestRecorder: DictationRecording {
    var onFailure: ((String) -> Void)?
    var elapsed: TimeInterval = 1
    var level = 0.5
    var startCount = 0
    var stopCount = 0
    var isRecording = false
    func start() throws { startCount += 1; isRecording = true }
    func stop() -> URL? {
        stopCount += 1
        isRecording = false
        return URL(fileURLWithPath: "/tmp/koe-unit-test-not-a-real-recording.caf")
    }
    func cleanup() { isRecording = false }
}
