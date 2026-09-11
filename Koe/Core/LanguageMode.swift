import Foundation

enum ModelAvailability: Sendable { case unsupported, supported, downloading, installed }

enum LanguageMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case automatic, japanese, english, french
    var id: String { rawValue }
    var title: String {
        switch self {
        case .japanese: "Japanese"
        case .english: "English"
        case .french: "French"
        case .automatic: "Auto-detect"
        }
    }
    var shortTitle: String {
        switch self {
        case .japanese: "日本語"
        case .english: "English"
        case .french: "Français"
        case .automatic: "Auto"
        }
    }
    var detail: String {
        switch self {
        case .japanese: "日本語の音声を、このMacで文字にします。"
        case .english: "Speak English. Transcription stays on this Mac."
        case .french: "Parlez français. La transcription reste sur ce Mac."
        case .automatic: "English, Japanese, or French, chosen per recording."
        }
    }
    var localeIDs: [String] {
        switch self {
        case .japanese: ["ja-JP"]
        case .english: ["en-US"]
        case .french: ["fr-FR"]
        case .automatic: ["en-US", "ja-JP", "fr-FR"]
        }
    }
}

struct TranscriptCandidate: Sendable, Equatable {
    let localeID: String
    let text: String
    let confidence: Double?
    let audioCoverage: Double

    var languageName: String {
        switch Locale(identifier: localeID).language.languageCode?.identifier {
        case "ja": "Japanese"
        case "en": "English"
        case "fr": "French"
        default: localeID
        }
    }
    var selectionScore: Double {
        // Confidence is an acoustic signal, not a calibrated language probability.
        // Coverage reduces the chance that one confident word beats a full utterance.
        (confidence ?? 0.5) * 0.85 + min(max(audioCoverage, 0), 1) * 0.15
    }
}

struct TranscriptSelection: Sendable {
    let best: TranscriptCandidate
    let alternatives: [TranscriptCandidate]
    let isUncertain: Bool
}

enum LanguageSelector {
    static func select(_ candidates: [TranscriptCandidate]) -> TranscriptSelection? {
        let usable = candidates.filter {
            $0.text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        }.sorted {
            if $0.selectionScore == $1.selectionScore { return $0.localeID < $1.localeID }
            return $0.selectionScore > $1.selectionScore
        }
        guard let best = usable.first else { return nil }
        let alternatives = Array(usable.dropFirst())
        let uncertain = alternatives.contains {
            best.confidence == nil || $0.confidence == nil || best.selectionScore - $0.selectionScore < 0.065
        }
        return TranscriptSelection(best: best, alternatives: alternatives, isUncertain: uncertain)
    }
}
