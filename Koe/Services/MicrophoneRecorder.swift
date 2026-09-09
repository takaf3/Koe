import AVFoundation

@MainActor
protocol DictationRecording: AnyObject {
    var onFailure: ((String) -> Void)? { get set }
    var elapsed: TimeInterval { get }
    var level: Double { get }
    func start() throws
    func stop() -> URL?
    func cleanup()
}

@MainActor
final class MicrophoneRecorder: NSObject, AVAudioRecorderDelegate, DictationRecording {
    private var recorder: AVAudioRecorder?
    private(set) var url: URL?
    var onFailure: ((String) -> Void)?

    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("com.takaf3.Koe", isDirectory: true)
    }
    static func clearStaleRecordings() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "caf" { try? FileManager.default.removeItem(at: file) }
    }

    func start() throws {
        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let file = Self.directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        url = file
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false]
        do {
            let recorder = try AVAudioRecorder(url: file, settings: settings)
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.prepareToRecord(), recorder.record() else {
                throw NSError(domain: "Koe", code: 1, userInfo: [NSLocalizedDescriptionKey:
                    "The microphone could not start. Check the input device in System Settings → Sound."])
            }
            self.recorder = recorder
        } catch {
            cleanup()
            throw error
        }
    }

    var elapsed: TimeInterval { recorder?.currentTime ?? 0 }
    var level: Double {
        guard let recorder else { return 0 }
        recorder.updateMeters()
        return min(max((Double(recorder.averagePower(forChannel: 0)) + 55) / 55, 0), 1)
    }
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        return url
    }
    func cleanup() {
        recorder?.stop()
        recorder = nil
        if let url { try? FileManager.default.removeItem(at: url) }
        url = nil
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: (any Error)?) {
        let message = error?.localizedDescription ?? "Microphone recording failed."
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, self.recorder.map(ObjectIdentifier.init) == identifier else { return }
            onFailure?(message)
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let identifier = ObjectIdentifier(recorder)
        Task { @MainActor [weak self] in
            guard let self, self.recorder.map(ObjectIdentifier.init) == identifier else { return }
            onFailure?("The microphone stopped unexpectedly. Check your input device and try again.")
        }
    }
}
