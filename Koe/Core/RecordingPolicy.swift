import Foundation

enum RecordingPolicy {
    static let minimumDuration: TimeInterval = 0.25
    static func shouldTranscribe(duration: TimeInterval) -> Bool {
        duration.isFinite && duration >= minimumDuration
    }
    static func timeout(for duration: TimeInterval) -> Duration {
        .seconds(min(60, max(10, 10 + duration * 0.5)))
    }
}
