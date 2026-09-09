import XCTest
import Carbon
@testable import Koe

final class KoeTests: XCTestCase {
    func testMenuFitsSmallAndOffsetDisplays() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1440, height: 875),
            CGRect(x: 1440, y: 360, width: 800, height: 450),
            CGRect(x: -1024, y: -768, width: 1024, height: 700)
        ]
        for screen in screens {
            let content = MenuLayout.contentSize(in: screen)
            XCTAssertLessThanOrEqual(content.height + 40, screen.height)
            XCTAssertLessThanOrEqual(content.width + 32, screen.width)
            let misplaced = CGRect(x: screen.maxX - 100, y: screen.maxY - 200,
                                   width: content.width + 20, height: content.height + 24)
            let corrected = CGRect(origin: MenuLayout.constrainedOrigin(for: misplaced, in: screen), size: misplaced.size)
            XCTAssertTrue(screen.contains(corrected), "Menu must fit the menu bar's display: \(screen)")
        }
    }

    func testMenuUsesStableSizeWhenContentChanges() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 930)
        XCTAssertEqual(MenuLayout.contentSize(in: screen), CGSize(width: 370, height: 620))
        let alreadyVisible = CGRect(x: 150, y: 250, width: 390, height: 644)
        XCTAssertEqual(MenuLayout.constrainedOrigin(for: alreadyVisible, in: screen), alreadyVisible.origin)
    }

    @MainActor func testTemporaryEscapeRegistrationAndShortcutSuspension() throws {
        let key = GlobalHotKey(signature: 0x54455354)
        defer { key.invalidate() }
        try key.registerEscape()
        XCTAssertTrue(key.isRegistered)
        key.suspend()
        XCTAssertFalse(key.isRegistered)
        XCTAssertTrue(key.suspended)
        let shortcut = HotKey(keyCode: 80, modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey))
        try key.resume(shortcut)
        XCTAssertTrue(key.isRegistered)
        XCTAssertFalse(key.suspended)
    }

    func testLanguageModesAreLimitedToEnglishAndJapanese() {
        XCTAssertEqual(LanguageMode.allCases.count, 3)
        XCTAssertEqual(LanguageMode.automatic.localeIDs, ["en-US", "ja-JP"])
        XCTAssertEqual(LanguageMode.japanese.localeIDs, ["ja-JP"])
        XCTAssertEqual(LanguageMode.english.localeIDs, ["en-US"])
    }

    func testShortcutValidationRejectsTypingAndModifierOnlyKeys() {
        XCTAssertTrue(HotKey.initial.isValid)
        XCTAssertFalse(HotKey(keyCode: 0, modifiers: 0).isValid)
        XCTAssertFalse(HotKey(keyCode: 0, modifiers: UInt32(shiftKey)).isValid)
        XCTAssertFalse(HotKey(keyCode: 55, modifiers: UInt32(cmdKey)).isValid)
        XCTAssertFalse(HotKey(keyCode: 53, modifiers: UInt32(controlKey)).isValid)
        XCTAssertFalse(HotKey(keyCode: 128, modifiers: UInt32(controlKey)).isValid)
        XCTAssertFalse(HotKey(keyCode: 0, modifiers: .max).isValid)
    }

    func testShortcutPersistsWithoutLosingModifiers() throws {
        let key = HotKey(keyCode: 49, modifiers: UInt32(cmdKey | shiftKey | optionKey))
        XCTAssertEqual(try JSONDecoder().decode(HotKey.self, from: JSONEncoder().encode(key)), key)
        XCTAssertEqual(key.display, "⌥⇧⌘Space")
    }

    func testAutomaticSelectionUsesAcousticConfidence() throws {
        let english = TranscriptCandidate(localeID: "en-US", text: "Tomorrow at ten.", confidence: 0.92, audioCoverage: 0.9)
        let japanese = TranscriptCandidate(localeID: "ja-JP", text: "ともろう", confidence: 0.31, audioCoverage: 0.6)
        let result = try XCTUnwrap(LanguageSelector.select([japanese, english]))
        XCTAssertEqual(result.best, english)
        XCTAssertFalse(result.isUncertain)
    }

    func testJapaneseWinsAgainstEnglishMisrecognition() throws {
        let japanese = TranscriptCandidate(localeID: "ja-JP", text: "明日の会議は十時です。", confidence: 0.89, audioCoverage: 0.9)
        let english = TranscriptCandidate(localeID: "en-US", text: "Ashton OK.", confidence: 0.4, audioCoverage: 0.3)
        XCTAssertEqual(try XCTUnwrap(LanguageSelector.select([english, japanese])).best, japanese)
    }

    func testCloseScoresAndMissingConfidenceRequireChoice() throws {
        let a = TranscriptCandidate(localeID: "en-US", text: "Hello", confidence: 0.82, audioCoverage: 1)
        let b = TranscriptCandidate(localeID: "ja-JP", text: "ハロー", confidence: 0.80, audioCoverage: 1)
        XCTAssertTrue(try XCTUnwrap(LanguageSelector.select([a, b])).isUncertain)
        let missing = TranscriptCandidate(localeID: "ja-JP", text: "こんにちは", confidence: nil, audioCoverage: 1)
        XCTAssertTrue(try XCTUnwrap(LanguageSelector.select([a, missing])).isUncertain)
    }

    func testSilenceDoesNotProduceAnInsertion() {
        XCTAssertNil(LanguageSelector.select([]))
        XCTAssertNil(LanguageSelector.select([.init(localeID: "en-US", text: " … \n", confidence: 1, audioCoverage: 1)]))
    }

    func testNumericDictationIsPreserved() {
        XCTAssertNotNil(LanguageSelector.select([.init(localeID: "en-US", text: "123", confidence: 0.9, audioCoverage: 1)]))
    }

    func testOneUsableCandidateDoesNotAskForLanguage() throws {
        let candidate = TranscriptCandidate(localeID: "ja-JP", text: "こんにちは。", confidence: nil, audioCoverage: 1)
        let result = try XCTUnwrap(LanguageSelector.select([candidate]))
        XCTAssertEqual(result.best, candidate)
        XCTAssertNil(result.alternative)
        XCTAssertFalse(result.isUncertain)
    }
}
