import Foundation
import Speech

/// Uses the production recognizer against an audio fixture, without microphone or pasting.
///
///     speech-check                          # List locales Apple supports on this Mac and their model status.
///     speech-check --install en-US ja-JP    # Install models for those locales.
///     speech-check clip.aiff en-US ja-JP    # Transcribe in those locales; one locale is a fixed pass.
@main struct SpeechCheck {
    static func main() async throws {
        let service = SpeechService()
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty {
            print("SpeechTranscriber available: \(SpeechTranscriber.isAvailable)")
            let supported = LanguageCatalog.sorted(await service.supportedLocaleIDs())
            let statuses = await service.statuses(localeIDs: supported)
            for id in supported {
                print("\(id.padding(toLength: 8, withPad: " ", startingAt: 0)) \(LanguageCatalog.title(for: id, in: supported)): \(statuses[id].map { "\($0)" } ?? "unknown")")
            }
            return
        }
        if arguments[0] == "--install" {
            let ids = arguments.count > 1 ? Array(arguments.dropFirst()) : LanguageCatalog.legacyDefaultLocaleIDs
            try await service.install(localeIDs: ids)
            print("Installed: \(ids.joined(separator: ", "))")
            return
        }
        let ids = arguments.count > 1 ? Array(arguments.dropFirst()) : LanguageCatalog.legacyDefaultLocaleIDs
        let result = try await service.transcribe(url: URL(fileURLWithPath: arguments[0]), localeIDs: ids)
        print("Selected: \(result.best.languageName), confidence: \(String(describing: result.best.confidence)), score: \(result.best.selectionScore)")
        print(result.best.text)
        for alternative in result.alternatives {
            print("Alternative: \(alternative.languageName), confidence: \(String(describing: alternative.confidence)), score: \(alternative.selectionScore)")
            print(alternative.text)
        }
        print("Needs choice: \(result.isUncertain)")
    }
}
