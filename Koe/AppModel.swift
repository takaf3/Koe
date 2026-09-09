import AppKit
import AVFoundation
import Combine
import ServiceManagement
import Speech

enum DictationPhase: Equatable {
    case idle, preparing, recording, transcribing, choosing, message, failure
    var isBusy: Bool { self == .preparing || self == .recording || self == .transcribing || self == .choosing }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var mode: LanguageMode {
        didSet { defaults.set(mode.rawValue, forKey: "languageMode") }
    }
    @Published private(set) var shortcut: HotKey
    @Published var phase: DictationPhase = .idle
    @Published var message = ""
    @Published var noticeTitle = ""
    @Published var noticeSymbol = "checkmark"
    @Published var level = 0.0
    @Published var elapsed = 0.0
    @Published var levelHistory = Array(repeating: 0.0, count: 23)
    private(set) var isHoldingHotKey = false
    @Published var models: [String: ModelAvailability] = [:]
    @Published var checkingModels = true
    @Published var installing = false
    @Published var microphoneAllowed = false
    @Published var accessibilityAllowed = false
    @Published var launchAtLogin = false
    @Published var loginNeedsApproval = false
    @Published var recordingShortcut = false
    @Published var shortcutError: String?
    @Published var lastTranscript = ""
    @Published var lastLanguage = ""
    @Published var lastInsertionDetail = ""
    @Published var selection: TranscriptSelection?
    @Published var setupError: String?

    let hotKey = GlobalHotKey()
    let speech: any SpeechProcessing
    private let defaults: UserDefaults
    private let recorder: any DictationRecording
    private let microphonePermission: @MainActor () async -> Bool
    private let transcriptionTimeout: Duration?
    private let inserter = TextInserter()
    private var sessionMode: LanguageMode = .automatic
    private var target: InsertionTarget?
    private var operation: Task<Void, Never>?
    private var ticker: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var downloadTask: Task<Void, Never>?
    private var shortcutMonitor: Any?
    private var sessionID = UUID()
    var showMenu: (() -> Void)?
    var closeMenu: (() -> Void)?
    var previousApplication: NSRunningApplication?

    init(defaults: UserDefaults = .standard, startServices: Bool = true,
         recorder: (any DictationRecording)? = nil,
         speech: any SpeechProcessing = SpeechService(), transcriptionTimeout: Duration? = nil,
         microphonePermission: @escaping @MainActor () async -> Bool = {
             await AVCaptureDevice.requestAccess(for: .audio)
         }) {
        self.defaults = defaults
        self.recorder = recorder ?? MicrophoneRecorder()
        self.speech = speech
        self.transcriptionTimeout = transcriptionTimeout
        self.microphonePermission = microphonePermission
        mode = LanguageMode(rawValue: defaults.string(forKey: "languageMode") ?? "") ?? .automatic
        if let data = defaults.data(forKey: "shortcut"), let saved = try? JSONDecoder().decode(HotKey.self, from: data), saved.isValid {
            shortcut = saved
        } else { shortcut = .initial }
        hotKey.onPress = { [weak self] in self?.hotKeyPressed() }
        hotKey.onRelease = { [weak self] in self?.hotKeyReleased() }
        self.recorder.onFailure = { [weak self] message in self?.fail(message) }
        guard startServices else { return }
        MicrophoneRecorder.clearStaleRecordings()
        do { try hotKey.register(shortcut) } catch { shortcutError = error.localizedDescription }
        refreshPermissions()
        Task { await refreshModels() }
    }

    var modelsReady: Bool { mode.localeIDs.allSatisfy { models[$0] == .installed } }
    var elapsedLabel: String { String(format: "%d:%02d", Int(elapsed) / 60, Int(elapsed) % 60) }
    var statusTitle: String {
        switch phase {
        case .idle: "Ready to dictate"
        case .preparing: "Getting ready…"
        case .recording: "Listening"
        case .transcribing: "Transcribing…"
        case .choosing: "Choose the language"
        case .message, .failure: message
        }
    }

    func refreshPermissions() {
        microphoneAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        accessibilityAllowed = TextInserter.isTrusted
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func refreshModels() async {
        checkingModels = true
        models = await speech.statuses()
        checkingModels = false
    }

    func downloadModels() {
        guard !installing, !phase.isBusy else { return }
        installing = true
        setupError = nil
        let requestedMode = mode
        downloadTask = Task { [weak self] in
            guard let self else { return }
            do { try await speech.install(mode: requestedMode) }
            catch { setupError = "Language download failed: \(error.localizedDescription)" }
            installing = false
            await refreshModels()
        }
    }

    func requestMicrophone() {
        Task {
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            } else if !microphoneAllowed { TextInserter.openPrivacy("Privacy_Microphone") }
            refreshPermissions()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshPermissions()
        } catch { setupError = "Could not change launch at login: \(error.localizedDescription)"; refreshPermissions() }
    }

    func hotKeyPressed() {
        guard !isHoldingHotKey, !recordingShortcut else { return }
        // A new deliberate hold supersedes an unfinished transcription, so a
        // stalled system recognizer cannot trap the user in the finishing state.
        if phase == .transcribing { cancel() }
        guard !phase.isBusy, !installing else { return }
        guard modelsReady else {
            setupError = "Download the selected language models to start dictating."
            showMenu?()
            return
        }
        isHoldingHotKey = true
        hideTask?.cancel()
        message = ""
        setupError = nil
        selection = nil
        sessionID = UUID()
        let id = sessionID
        sessionMode = mode
        let front = NSWorkspace.shared.frontmostApplication
        let destination = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? previousApplication : front
        target = InsertionTarget.capture(application: destination)
        if let element = target?.element, InsertionTarget.isSecure(element) {
            fail("Select a regular text field before dictating.")
            return
        }
        closeMenu?()
        if front?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            destination?.activate()
        }
        phase = .preparing
        operation = Task { [weak self] in
            guard let self else { return }
            guard !Task.isCancelled else { return }
            let allowed = await microphonePermission()
            guard !Task.isCancelled, sessionID == id, isHoldingHotKey else { return }
            refreshPermissions()
            guard allowed else {
                fail("Allow microphone access in System Settings → Privacy & Security → Microphone.")
                return
            }
            do {
                try recorder.start()
                phase = .recording
                elapsed = 0
                level = 0
                levelHistory = Array(repeating: 0.0, count: 23)
                startTicker(id: id)
            } catch { fail(error.localizedDescription) }
        }
    }

    func hotKeyReleased() {
        guard isHoldingHotKey else { return }
        isHoldingHotKey = false
        switch phase {
        case .recording: finishRecording()
        case .preparing: cancel()
        default: break
        }
    }

    private func startTicker(id: UUID) {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, sessionID == id, phase == .recording else { return }
                elapsed = recorder.elapsed
                level = recorder.level
                levelHistory.removeFirst()
                levelHistory.append(level)
                if elapsed >= 300 { finishRecording(); return }
                try? await Task.sleep(for: .milliseconds(75))
            }
        }
    }

    func finishRecording() {
        guard phase == .recording else { return }
        isHoldingHotKey = false
        ticker?.cancel()
        let duration = recorder.elapsed
        guard let url = recorder.stop() else { fail("The microphone recording was unavailable."); return }
        guard RecordingPolicy.shouldTranscribe(duration: duration) else { cancel(); return }
        phase = .transcribing
        level = 0
        let id = sessionID
        let requestedMode = sessionMode
        let limit = transcriptionTimeout ?? RecordingPolicy.timeout(for: duration)
        timeout = Task { [weak self] in
            try? await Task.sleep(for: limit)
            guard !Task.isCancelled, let self, sessionID == id, phase == .transcribing else { return }
            cancel()
            showMessage("Timed out. Hold the shortcut to retry.", title: "Try again", symbol: "arrow.clockwise")
        }
        operation = Task { [weak self] in
            guard let self, !Task.isCancelled else { return }
            do {
                let result = try await speech.transcribe(url: url, mode: requestedMode)
                guard !Task.isCancelled, sessionID == id else { return }
                timeout?.cancel()
                recorder.cleanup()
                selection = result
                if requestedMode == .automatic, result.isUncertain, result.alternative != nil {
                    phase = .choosing
                } else { deliver(result.best) }
            } catch {
                guard !Task.isCancelled, sessionID == id else { return }
                if (error as? SpeechFailure) == .noSpeech {
                    cancel()
                    showMessage("No speech detected", title: "No speech", symbol: "waveform.slash")
                } else { fail(error.localizedDescription) }
            }
        }
    }

    func deliver(_ candidate: TranscriptCandidate) {
        lastTranscript = candidate.text
        lastLanguage = candidate.languageName
        selection = nil
        let feedback = inserter.insert(candidate.text, target: target)
        lastInsertionDetail = feedback.detail
        showMessage(feedback.detail, title: feedback.title, symbol: feedback.symbol)
    }

    private func showMessage(_ text: String, title: String, symbol: String) {
        message = text
        noticeTitle = title
        noticeSymbol = symbol
        phase = .message
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, phase == .message else { return }
            phase = .idle
        }
    }

    func cancel() {
        isHoldingHotKey = false
        sessionID = UUID()
        operation?.cancel()
        ticker?.cancel()
        timeout?.cancel()
        hideTask?.cancel()
        recorder.cleanup()
        selection = nil
        level = 0
        phase = .idle
        // The task cancellation handler cancels its own analyzer; it cannot cancel a newer session.
    }

    private func fail(_ text: String) {
        cancel()
        message = text
        phase = .failure
    }

    func beginShortcutRecording() {
        guard !phase.isBusy else { return }
        recordingShortcut = true
        shortcutError = nil
        hotKey.suspend()
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { endShortcutRecording(); return nil }
            guard !event.isARepeat else { return nil }
            let candidate = HotKey(event: event)
            if candidate == shortcut { endShortcutRecording(); return nil }
            do {
                try hotKey.register(candidate)
                shortcut = candidate
                defaults.set(try JSONEncoder().encode(candidate), forKey: "shortcut")
                endShortcutRecording()
            } catch { shortcutError = error.localizedDescription }
            return nil
        }
    }

    func endShortcutRecording() {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        recordingShortcut = false
        do { try hotKey.resume(shortcut) } catch { shortcutError = error.localizedDescription }
    }

    func shutdown() {
        cancel()
        downloadTask?.cancel()
        endShortcutRecording()
        hotKey.invalidate()
    }
}
