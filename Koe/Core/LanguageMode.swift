import Foundation

enum ModelAvailability: Sendable { case unsupported, supported, downloading, installed }

/// Which of the user's enabled languages a recording is transcribed in.
enum LanguageMode: Hashable, Sendable {
    /// Evaluate every enabled language and pick the best transcript.
    case automatic
    /// Run a single recognition pass in one enabled locale.
    case fixed(String)

    static let automaticStorageValue = "automatic"
    private static let legacyStorageValues = ["japanese": "ja-JP", "english": "en-US", "french": "fr-FR"]

    /// Accepts the current `automatic`/locale-ID form and the pre-1.1 `japanese`/`english`/`french` names.
    init(storageValue: String?) {
        guard let storageValue, !storageValue.isEmpty, storageValue != Self.automaticStorageValue else {
            self = .automatic
            return
        }
        self = .fixed(Self.legacyStorageValues[storageValue] ?? storageValue)
    }

    var storageValue: String {
        switch self {
        case .automatic: Self.automaticStorageValue
        case .fixed(let id): id
        }
    }

    var localeID: String? {
        if case .fixed(let id) = self { return id }
        return nil
    }

    func localeIDs(enabled: [String]) -> [String] {
        switch self {
        case .automatic: enabled
        case .fixed(let id): [id]
        }
    }

    var title: String {
        switch self {
        case .automatic: "Auto-detect"
        case .fixed(let id): LanguageCatalog.languageName(for: id)
        }
    }
}

/// Names and defaults for Apple's on-device speech locales. The list of locales that
/// actually exist on a Mac comes from `SpeechTranscriber.supportedLocales` at runtime.
enum LanguageCatalog {
    static let legacyDefaultLocaleIDs = ["en-US", "ja-JP", "fr-FR"]
    /// Auto-detect runs one full recognition pass per language; beyond this many it gets noticeably slower and asks more often.
    static let recommendedAutomaticLimit = 3

    /// The locale used when a preferred language names no region Apple ships a model for.
    private static let canonicalLocaleIDs = [
        "en": "en-US", "ja": "ja-JP", "fr": "fr-FR", "de": "de-DE", "es": "es-ES",
        "it": "it-IT", "ko": "ko-KR", "pt": "pt-BR", "zh": "zh-CN", "yue": "yue-CN"
    ]
    /// Regional variants known to ship with macOS 26. Used only to keep a region the user already prefers.
    private static let knownLocaleIDs: Set<String> = [
        "de-AT", "de-CH", "de-DE", "en-AU", "en-CA", "en-GB", "en-IE", "en-IN", "en-NZ", "en-SG", "en-US", "en-ZA",
        "es-CL", "es-ES", "es-MX", "es-US", "fr-BE", "fr-CA", "fr-CH", "fr-FR", "it-CH", "it-IT", "ja-JP", "ko-KR",
        "pt-BR", "pt-PT", "yue-CN", "zh-CN", "zh-HK", "zh-TW"
    ]
    private static let english = Locale(identifier: "en_US")

    /// The user's top two preferred languages that Apple has models for, plus English.
    static func defaultLocaleIDs(preferredLanguages: [String]) -> [String] {
        var ids: [String] = []
        for tag in preferredLanguages {
            guard let id = localeID(matching: tag), !ids.contains(id) else { continue }
            ids.append(id)
            if ids.count == 2 { break }
        }
        if !ids.contains(where: { languageCode(of: $0) == "en" }) { ids.append("en-US") }
        return ids
    }

    static func localeID(matching tag: String) -> String? {
        let locale = Locale(identifier: tag)
        guard let code = locale.language.languageCode?.identifier, let canonical = canonicalLocaleIDs[code] else { return nil }
        if let region = locale.region?.identifier, knownLocaleIDs.contains("\(code)-\(region)") { return "\(code)-\(region)" }
        return canonical
    }

    static func languageCode(of localeID: String) -> String? {
        Locale(identifier: localeID).language.languageCode?.identifier
    }

    /// English language name, e.g. "Japanese".
    static func languageName(for localeID: String) -> String {
        guard let code = languageCode(of: localeID) else { return localeID }
        return english.localizedString(forLanguageCode: code) ?? localeID
    }

    /// The language's own name for itself, e.g. "日本語".
    static func nativeName(for localeID: String) -> String {
        let locale = Locale(identifier: localeID)
        guard let code = languageCode(of: localeID), let native = locale.localizedString(forLanguageCode: code) else {
            return languageName(for: localeID)
        }
        // French and Spanish write their own names in lowercase; a list of languages reads better capitalized.
        return native.prefix(1).uppercased(with: locale) + native.dropFirst()
    }

    static func regionName(for localeID: String) -> String? {
        guard let region = Locale(identifier: localeID).region?.identifier else { return nil }
        return english.localizedString(forRegionCode: region)
    }

    /// "Japanese", or "English (United Kingdom)" when the language has several regions in `catalog`.
    static func name(for localeID: String, in catalog: [String]) -> String {
        guard hasSiblingRegions(localeID, in: catalog), let region = regionName(for: localeID) else { return languageName(for: localeID) }
        return "\(languageName(for: localeID)) (\(region))"
    }

    /// "Japanese · 日本語", or "English (United Kingdom)" when the language has several regions in `catalog`.
    static func title(for localeID: String, in catalog: [String]) -> String {
        var name = name(for: localeID, in: catalog)
        let native = nativeName(for: localeID)
        if native.caseInsensitiveCompare(languageName(for: localeID)) != .orderedSame { name += " · \(native)" }
        return name
    }

    /// Segment label: "日本語", or "English (GB)" when another region of the language is enabled.
    static func shortTitle(for localeID: String, in enabled: [String]) -> String {
        let native = nativeName(for: localeID)
        guard hasSiblingRegions(localeID, in: enabled), let region = Locale(identifier: localeID).region?.identifier else { return native }
        return "\(native) (\(region))"
    }

    static func sorted(_ localeIDs: [String]) -> [String] {
        localeIDs.sorted { title(for: $0, in: localeIDs).localizedStandardCompare(title(for: $1, in: localeIDs)) == .orderedAscending }
    }

    private static func hasSiblingRegions(_ localeID: String, in ids: [String]) -> Bool {
        let code = languageCode(of: localeID)
        return ids.contains { $0 != localeID && languageCode(of: $0) == code }
    }
}

struct TranscriptCandidate: Sendable, Equatable {
    let localeID: String
    let text: String
    let confidence: Double?
    let audioCoverage: Double

    var languageName: String { LanguageCatalog.languageName(for: localeID) }
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
    /// Scores within this margin of the best are a tie the user should break. Every extra
    /// language adds another chance of a plausible wrong transcript, so the margin widens with the field.
    static func uncertaintyMargin(candidateCount: Int) -> Double {
        0.065 + 0.01 * Double(max(0, candidateCount - 2))
    }

    static func select(_ candidates: [TranscriptCandidate]) -> TranscriptSelection? {
        let usable = candidates.filter {
            $0.text.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        }.sorted {
            if $0.selectionScore == $1.selectionScore { return $0.localeID < $1.localeID }
            return $0.selectionScore > $1.selectionScore
        }
        guard let best = usable.first else { return nil }
        let alternatives = Array(usable.dropFirst())
        let margin = uncertaintyMargin(candidateCount: usable.count)
        let uncertain = alternatives.contains {
            best.confidence == nil || $0.confidence == nil || best.selectionScore - $0.selectionScore < margin
        }
        return TranscriptSelection(best: best, alternatives: alternatives, isUncertain: uncertain)
    }
}
