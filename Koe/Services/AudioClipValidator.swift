import AVFoundation

enum AudioClipValidator {
    static func containsAudio(at url: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        guard RecordingPolicy.shouldTranscribe(duration: duration) else { return false }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else { return false }
        // Reject effectively digital silence, without using an aggressive gate
        // that could discard soft speech. Background noise is left to Apple Speech.
        let threshold: Float = 0.0001 // -80 dBFS
        while file.framePosition < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { break }
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) where abs(channels[channel][frame]) > threshold {
                    return true
                }
            }
        }
        return false
    }
}
