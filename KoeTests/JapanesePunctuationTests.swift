import XCTest
@testable import Koe

final class JapanesePunctuationTests: XCTestCase {
    func testClearJapaneseQuestionsGetQuestionMarks() {
        let cases = [
            "明日の会議は何時ですか。": "明日の会議は何時ですか？",
            "どうすればいいですか。": "どうすればいいですか？",
            "資料を送っていただけますか。": "資料を送っていただけますか？",
            "これは何でしたか。": "これは何でしたか？",
            "終わりましたか。": "終わりましたか？",
            "明日でよろしいでしょうか。": "明日でよろしいでしょうか？",
            "一緒に行きませんか。": "一緒に行きませんか？",
            "まだ届いていませんでしたか。": "まだ届いていませんでしたか？",
            "始めましょうか。": "始めましょうか？",
            "間に合うだろうか。": "間に合うだろうか？",
            "  本当ですか  ": "  本当ですか？"
        ]
        for (input, expected) in cases { XCTAssertEqual(normalize(input), expected, input) }
    }

    func testStatementsAndAmbiguousSpeechRemainUnchanged() {
        for text in ["今日は雨です。", "いつか。", "何か。", "静か。", "明日来る。", "明日来るの。",
                     "そうですか。", "そうなんですか。", "そうでしたか。", "そうだったんですか。",
                     "何時ですかと聞きました。", "来るかどうかは分かりません。", "いいですか！", "いいですか。。。"] {
            XCTAssertEqual(normalize(text), text)
        }
    }

    func testMixedSentencesAndNativeQuestionMarks() {
        XCTAssertEqual(normalize("何時ですか 。今日は雨です。行きませんか\n明日は晴れです。"),
                       "何時ですか？今日は雨です。行きませんか？\n明日は晴れです。")
        XCTAssertEqual(normalize("どうしますか ？Why? 本当ですか?"), "どうしますか？Why? 本当ですか?")
        XCTAssertEqual(normalize("終わりましたか\r\n終わりました。"), "終わりましたか？\r\n終わりました。")
    }

    func testQuotedQuestionsAndCodeRemainUnchanged() {
        for text in ["「何時ですか。」と聞かれました。", "『いいですか。』", "\"何時ですか。\"",
                     "`どうしますか。`", "（何時ですか。）", "「閉じていない引用。何時ですか。"] {
            XCTAssertEqual(normalize(text), text)
        }
        XCTAssertEqual(normalize("「Koe」は使えますか。"), "「Koe」は使えますか？")
    }

    func testEnglishAndRepeatedNormalizationPreserveText() {
        let english = "He said ですか. Are you coming?"
        XCTAssertEqual(JapanesePunctuation.normalize(english, localeID: "en-US"), english)
        let text = normalize("何時ですか。今日は雨です。どうしますか ？")
        XCTAssertEqual(normalize(text), text)
        XCTAssertEqual(normalize(""), "")
        XCTAssertEqual(normalize(" \n "), " \n ")
        XCTAssertEqual(JapanesePunctuation.normalize("何時ですか。", localeID: "ja_JP"), "何時ですか？")
    }

    private func normalize(_ text: String) -> String {
        JapanesePunctuation.normalize(text, localeID: "ja-JP")
    }
}
