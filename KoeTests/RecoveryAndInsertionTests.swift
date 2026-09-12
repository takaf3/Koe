import XCTest
import AVFoundation
@testable import Koe

final class RecoveryAndInsertionTests: XCTestCase {
    func testKeyboardFocusDoesNotDependOnASavedAccessibilityNode() {
        // Missing/replaced AX nodes must not prevent the normal keyboard-paste path.
        XCTAssertEqual(InsertionPolicy.decision(trusted: true, targetPID: 123, foregroundPID: 123,
                                                targetTerminated: false, secureField: false), .insert)
    }

    func testInsertionStillRejectsDifferentAppsAndSecureFields() {
        XCTAssertEqual(InsertionPolicy.decision(trusted: true, targetPID: 123, foregroundPID: 456,
                                                targetTerminated: false, secureField: false), .differentApplication)
        XCTAssertEqual(InsertionPolicy.decision(trusted: true, targetPID: 123, foregroundPID: 123,
                                                targetTerminated: false, secureField: true), .secureField)
        XCTAssertEqual(InsertionPolicy.decision(trusted: false, targetPID: 123, foregroundPID: 123,
                                                targetTerminated: false, secureField: false), .needsAccessibility)
        XCTAssertEqual(InsertionPolicy.decision(trusted: true, targetPID: nil, foregroundPID: 123,
                                                targetTerminated: false, secureField: false), .noTarget)
        XCTAssertEqual(InsertionPolicy.decision(trusted: true, targetPID: 123, foregroundPID: 123,
                                                targetTerminated: true, secureField: false), .targetClosed)
    }

    func testClipValidationRejectsBriefAndSilentFilesButKeepsQuietAudio() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let short = try makeAudio(in: directory, name: "short", duration: 0.1, amplitude: 0.2)
        let silent = try makeAudio(in: directory, name: "silent", duration: 1, amplitude: 0)
        let quiet = try makeAudio(in: directory, name: "quiet", duration: 1, amplitude: 0.0002)
        XCTAssertFalse(try AudioClipValidator.containsAudio(at: short))
        XCTAssertFalse(try AudioClipValidator.containsAudio(at: silent))
        XCTAssertTrue(try AudioClipValidator.containsAudio(at: quiet))
    }

    func testRealSpeechServiceRejectsSilenceBeforeStartingRecognition() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try makeAudio(in: directory, name: "silent", duration: 1, amplitude: 0)
        do {
            _ = try await SpeechService().transcribe(url: url, localeIDs: ["en-US", "ja-JP"])
            XCTFail("Silence should not produce a transcript")
        } catch { XCTAssertEqual(error as? SpeechFailure, .noSpeech) }
    }

    @MainActor func testAccidentalTapDismissesWithoutInvokingSpeech() async throws {
        let recorder = RecoveryRecorder()
        recorder.elapsed = 0.08
        let speech = SuspendedSpeech()
        let model = makeModel(recorder: recorder, speech: speech)
        defer { model.cancel(); model.hotKey.invalidate() }
        model.hotKeyPressed()
        try await waitFor { recorder.isRecording }
        model.hotKeyReleased()
        XCTAssertEqual(model.phase, .idle)
        XCTAssertFalse(recorder.isRecording)
        let calls = await speech.callCount
        XCTAssertEqual(calls, 0)
    }

    @MainActor func testWatchdogUnsticksEvenANonCooperativeRecognizer() async throws {
        let recorder = RecoveryRecorder()
        let speech = SuspendedSpeech()
        let model = makeModel(recorder: recorder, speech: speech, timeout: .milliseconds(80))
        defer { model.cancel(); model.hotKey.invalidate() }
        model.hotKeyPressed()
        try await waitFor { recorder.isRecording }
        model.hotKeyReleased()
        try await waitFor { await speech.callCount == 1 }
        try await waitFor { model.phase == .message }
        XCTAssertTrue(model.message.hasPrefix("Timed out"))
        XCTAssertFalse(model.phase.isBusy)
        await speech.resolveAll()
        XCTAssertEqual(model.phase, .message)
        XCTAssertTrue(model.lastTranscript.isEmpty)
    }

    @MainActor func testNewHoldRecoversAndLateOldResultsCannotInterruptIt() async throws {
        let recorder = RecoveryRecorder()
        let speech = SuspendedSpeech()
        let model = makeModel(recorder: recorder, speech: speech)
        defer { model.cancel(); model.hotKey.invalidate() }
        model.hotKeyPressed()
        try await waitFor { recorder.isRecording }
        model.hotKeyReleased()
        try await waitFor { await speech.callCount == 1 }
        model.hotKeyPressed()
        try await waitFor { recorder.startCount == 2 }
        XCTAssertEqual(model.phase, .recording)
        await speech.resolveAll()
        try await waitFor { await speech.returnedCount == 1 }
        XCTAssertEqual(model.phase, .recording)
        XCTAssertTrue(model.isHoldingHotKey)
        XCTAssertTrue(model.lastTranscript.isEmpty)
    }

    private func makeAudio(in directory: URL, name: String, duration: Double, amplitude: Float) throws -> URL {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let count = AVAudioFrameCount(duration * 16000)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count))
        buffer.frameLength = count
        for frame in 0..<Int(count) { buffer.floatChannelData![0][frame] = amplitude }
        let url = directory.appendingPathComponent(name).appendingPathExtension("caf")
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return url
    }

    @MainActor private func makeModel(recorder: RecoveryRecorder, speech: SuspendedSpeech,
                                     timeout: Duration? = nil) -> AppModel {
        let model = AppModel(defaults: UserDefaults(suiteName: "KoeTests.recovery.\(UUID().uuidString)")!, startServices: false,
                             preferredLanguages: ["ja-JP", "en-US"], recorder: recorder, speech: speech,
                             transcriptionTimeout: timeout, microphonePermission: { true })
        model.models = ["en-US": .installed, "ja-JP": .installed, "fr-FR": .installed]
        return model
    }

    @MainActor private func waitFor(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while !(await condition()) {
            if ContinuousClock.now >= deadline { throw WaitFailure.timedOut }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
    private enum WaitFailure: Error { case timedOut }
}

@MainActor private final class RecoveryRecorder: DictationRecording {
    var onFailure: ((String) -> Void)?
    var elapsed: TimeInterval = 1
    var level = 0.5
    var startCount = 0
    var isRecording = false
    func start() throws { startCount += 1; isRecording = true }
    func stop() -> URL? { isRecording = false; return URL(fileURLWithPath: "/tmp/koe-test-audio.caf") }
    func cleanup() { isRecording = false }
}

private actor SuspendedSpeech: SpeechProcessing {
    var callCount = 0
    var returnedCount = 0
    private var continuations: [CheckedContinuation<TranscriptSelection, any Error>] = []
    func supportedLocaleIDs() -> [String] { ["en-US", "ja-JP", "fr-FR"] }
    func statuses(localeIDs: [String]) -> [String: ModelAvailability] { ["en-US": .installed, "ja-JP": .installed, "fr-FR": .installed] }
    func install(localeIDs: [String]) {}
    func transcribe(url: URL, localeIDs: [String]) async throws -> TranscriptSelection {
        callCount += 1
        defer { returnedCount += 1 }
        return try await withCheckedThrowingContinuation { continuations.append($0) }
    }
    func resolveAll() {
        for continuation in continuations { continuation.resume(throwing: SpeechFailure.noSpeech) }
        continuations.removeAll()
    }
}
