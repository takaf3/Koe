import Foundation

enum ModelAvailability: Sendable { case unsupported, supported, downloading, installed }

enum LanguageMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case japanese, english, automatic
    var id: String { rawValue }
    var title: String {
        switch self {
        case .japanese: "Japanese"
        case .english: "English"
        case .automatic: "Auto-detect"
        }
    }
    var shortTitle: String {
        switch self {
        case .japanese: "日本語"
        case .english: "English"
        case .automatic: "Auto"
        }
    }
    var localeIDs: [String] {
        switch self {
        case .japanese: ["ja-JP"]
        case .english: ["en-US"]
        case .automatic: ["en-US", "ja-JP"]
        }
    }
}

struct TranscriptCandidate: Sendable, Equatable {
    let localeID: String
    let text: String
    let confidence: Double?
    let audioCoverage: Double

    var languageName: String { localeID.hasPrefix("ja") ? "Japanese" : "English" }
    var selectionScore: Double {
        // Confidence is an acoustic signal, not a calibrated language probability.
        // Coverage reduces the chance that one confident word beats a full utterance.
        (confidence ?? 0.5) * 0.85 + min(max(audioCoverage, 0), 1) * 0.15
    }
}

struct TranscriptSelection: Sendable {
    let best: TranscriptCandidate
    let alternative: TranscriptCandidate?
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
        let alternative = usable.dropFirst().first
        let uncertain = alternative.map {
            best.confidence == nil || $0.confidence == nil || best.selectionScore - $0.selectionScore < 0.065
        } ?? false
        return TranscriptSelection(best: best, alternative: alternative, isUncertain: uncertain)
    }
}
