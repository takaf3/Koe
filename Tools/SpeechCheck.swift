import Foundation
import Speech

/// Uses the production recognizer against an audio fixture, without microphone or pasting.
@main struct SpeechCheck {
    static func main() async throws {
        let service = SpeechService()
        if CommandLine.arguments.count == 1 {
            print("SpeechTranscriber available: \(SpeechTranscriber.isAvailable)")
            for (id, status) in await service.statuses().sorted(by: { $0.key < $1.key }) { print("\(id): \(status)") }
            return
        }
        if CommandLine.arguments[1] == "--install" {
            try await service.install(mode: .automatic)
            print("English and Japanese assets installed.")
            return
        }
        let mode = CommandLine.arguments.count > 2 ? LanguageMode(rawValue: CommandLine.arguments[2]) ?? .automatic : .automatic
        let result = try await service.transcribe(url: URL(fileURLWithPath: CommandLine.arguments[1]), mode: mode)
        print("Selected: \(result.best.languageName), confidence: \(String(describing: result.best.confidence)), score: \(result.best.selectionScore)")
        print(result.best.text)
        if let alternative = result.alternative {
            print("Alternative: \(alternative.languageName), confidence: \(String(describing: alternative.confidence)), score: \(alternative.selectionScore)")
            print(alternative.text)
        }
        print("Needs choice: \(result.isUncertain)")
    }
}
