import Foundation

/// A conservative, local writing-style correction, not an intonation detector.
/// Apple sometimes ends even explicit Japanese questions with a full stop.
enum JapanesePunctuation {
    private static let questionEndings = [
        "ですか", "ますか", "でしたか", "ましたか", "でしょうか",
        "ませんか", "ませんでしたか", "ましょうか", "だろうか"
    ]
    // These can be acknowledgements with falling intonation; leave that decision to Apple.
    private static let acknowledgements: Set<String> = [
        "そうですか", "そうでしたか", "そうなんですか", "そうだったんですか"
    ]
    private static let pairedQuotes: [Character: Character] = [
        "「": "」", "『": "』", "“": "”", "‘": "’", "（": "）", "(": ")", "[": "]"
    ]
    private static let boundaries: Set<Character> = ["。", "?", "？", "!", "！", "\n", "\r", "\r\n"]

    static func normalize(_ text: String, localeID: String) -> String {
        guard Locale(identifier: localeID).language.languageCode?.identifier == "ja" else { return text }
        let characters = Array(text)
        var output = ""
        var sentence = ""
        var closingQuotes: [Character] = []
        for (index, character) in characters.enumerated() {
            if character == closingQuotes.last {
                closingQuotes.removeLast()
            } else if character == "\"" || character == "`" {
                closingQuotes.append(character)
            } else if let closing = pairedQuotes[character] {
                closingQuotes.append(closing)
            }
            if closingQuotes.isEmpty, boundaries.contains(character) {
                let repeatedPeriod = character == "。" && index + 1 < characters.count && characters[index + 1] == "。"
                output += finish(sentence, punctuation: character, allowCorrection: !repeatedPeriod)
                sentence = ""
            } else {
                sentence.append(character)
            }
        }
        output += closingQuotes.isEmpty ? finish(sentence, punctuation: nil) : sentence
        return output
    }

    private static func finish(_ sentence: String, punctuation: Character?, allowCorrection: Bool = true) -> String {
        let trimmed = sentence.trimmingCharacters(in: .whitespaces)
        let body = String(sentence.dropLast(sentence.reversed().prefix(while: { $0.isWhitespace }).count))
        let suffix = punctuation.map(String.init) ?? ""
        // Preserve Apple’s existing question mark, removing its occasional preceding space.
        if punctuation == "?" || punctuation == "？" { return body + suffix }
        let canEndQuestion = punctuation == nil || punctuation == "。" || punctuation?.isNewline == true
        guard allowCorrection, canEndQuestion, !acknowledgements.contains(trimmed),
              questionEndings.contains(where: trimmed.hasSuffix) else { return sentence + suffix }
        // Quoted text and code are accumulated as part of the surrounding sentence,
        // so a question inside quotation marks never matches an outside sentence ending.
        return body + "？" + (punctuation?.isNewline == true ? suffix : "")
    }
}
