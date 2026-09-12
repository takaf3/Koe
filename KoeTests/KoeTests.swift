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

    func testLanguageModeStorageMigratesLegacyNames() {
        XCTAssertEqual(LanguageMode(storageValue: nil), .automatic)
        XCTAssertEqual(LanguageMode(storageValue: "automatic"), .automatic)
        XCTAssertEqual(LanguageMode(storageValue: "japanese"), .fixed("ja-JP"))
        XCTAssertEqual(LanguageMode(storageValue: "english"), .fixed("en-US"))
        XCTAssertEqual(LanguageMode(storageValue: "french"), .fixed("fr-FR"))
        XCTAssertEqual(LanguageMode(storageValue: "de-DE"), .fixed("de-DE"))
        XCTAssertEqual(LanguageMode.fixed("ko-KR").storageValue, "ko-KR")
        XCTAssertEqual(LanguageMode.automatic.localeIDs(enabled: ["ja-JP", "en-US"]), ["ja-JP", "en-US"])
        XCTAssertEqual(LanguageMode.fixed("ja-JP").localeIDs(enabled: ["ja-JP", "en-US"]), ["ja-JP"])
    }

    func testDefaultLanguagesFollowSystemPreferencesPlusEnglish() {
        XCTAssertEqual(LanguageCatalog.defaultLocaleIDs(preferredLanguages: ["ja-JP", "en-JP"]), ["ja-JP", "en-US"])
        XCTAssertEqual(LanguageCatalog.defaultLocaleIDs(preferredLanguages: ["en-GB"]), ["en-GB"])
        XCTAssertEqual(LanguageCatalog.defaultLocaleIDs(preferredLanguages: ["de-DE", "fr-CH", "it-IT"]), ["de-DE", "fr-CH", "en-US"])
        XCTAssertEqual(LanguageCatalog.defaultLocaleIDs(preferredLanguages: ["zh-Hant-TW", "zh-Hans-CN"]), ["zh-TW", "zh-CN", "en-US"])
        XCTAssertEqual(LanguageCatalog.defaultLocaleIDs(preferredLanguages: ["sv-SE"]), ["en-US"])
        XCTAssertEqual(LanguageCatalog.defaultLocaleIDs(preferredLanguages: []), ["en-US"])
        XCTAssertEqual(LanguageCatalog.localeID(matching: "es"), "es-ES")
        XCTAssertEqual(LanguageCatalog.localeID(matching: "es-AR"), "es-ES")
        XCTAssertEqual(LanguageCatalog.localeID(matching: "es-MX"), "es-MX")
    }

    func testLanguageTitlesDistinguishRegionsOnlyWhenNeeded() {
        let catalog = ["en-US", "en-GB", "ja-JP", "fr-FR"]
        XCTAssertEqual(LanguageCatalog.title(for: "ja-JP", in: catalog), "Japanese · 日本語")
        XCTAssertEqual(LanguageCatalog.title(for: "fr-FR", in: catalog), "French · Français")
        XCTAssertEqual(LanguageCatalog.title(for: "en-US", in: catalog), "English (United States)")
        XCTAssertEqual(LanguageCatalog.title(for: "en-GB", in: catalog), "English (United Kingdom)")
        XCTAssertEqual(LanguageCatalog.title(for: "en-US", in: ["en-US", "ja-JP"]), "English")
        XCTAssertEqual(LanguageCatalog.shortTitle(for: "ja-JP", in: ["ja-JP", "en-US"]), "日本語")
        XCTAssertEqual(LanguageCatalog.shortTitle(for: "en-GB", in: ["en-US", "en-GB"]), "English (GB)")
        XCTAssertEqual(LanguageCatalog.sorted(["ja-JP", "en-US", "fr-FR"]), ["en-US", "fr-FR", "ja-JP"])
    }

    @MainActor func testFreshInstallDefaultsToPreferredLanguagesAndAutoDetect() throws {
        let suite = "KoeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, startServices: false, preferredLanguages: ["ja-JP", "en-JP"])
        defer { model.hotKey.invalidate() }
        XCTAssertEqual(model.mode, .automatic)
        XCTAssertEqual(model.enabledLocaleIDs, ["ja-JP", "en-US"])
        XCTAssertEqual(model.activeLocaleIDs, ["ja-JP", "en-US"])
        XCTAssertEqual(defaults.stringArray(forKey: "enabledLanguages"), ["ja-JP", "en-US"], "The resolved defaults are persisted")
    }

    @MainActor func testFreshInstallSurvivesAModeChangeAndRestartWithoutLegacyMigration() throws {
        let suite = "KoeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, startServices: false, preferredLanguages: ["de-DE"])
        defer { model.hotKey.invalidate() }
        XCTAssertEqual(model.enabledLocaleIDs, ["de-DE", "en-US"])
        model.mode = .fixed("de-DE")
        model.mode = .automatic
        let restarted = AppModel(defaults: defaults, startServices: false, preferredLanguages: ["de-DE"])
        defer { restarted.hotKey.invalidate() }
        XCTAssertEqual(restarted.enabledLocaleIDs, ["de-DE", "en-US"], "A saved mode alone must not trigger the legacy English/Japanese/French migration")
        XCTAssertEqual(restarted.mode, .automatic)
    }

    @MainActor func testUpgradeFromFixedLanguagesKeepsAllThreeAndTheSavedMode() throws {
        let suite = "KoeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("french", forKey: "languageMode")
        let model = AppModel(defaults: defaults, startServices: false, preferredLanguages: ["ko-KR"])
        defer { model.hotKey.invalidate() }
        XCTAssertEqual(model.mode, .fixed("fr-FR"))
        XCTAssertEqual(model.enabledLocaleIDs, ["en-US", "ja-JP", "fr-FR"])
        XCTAssertEqual(defaults.string(forKey: "languageMode"), "french", "Untouched preferences stay in their old form")
        model.mode = .automatic
        XCTAssertEqual(defaults.string(forKey: "languageMode"), "automatic")
    }

    @MainActor func testEnablingAndRemovingLanguagesPersistsAndKeepsAValidMode() throws {
        let suite = "KoeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults, startServices: false, preferredLanguages: ["en-US"])
        defer { model.hotKey.invalidate() }
        XCTAssertEqual(model.enabledLocaleIDs, ["en-US"])
        model.disableLanguage("en-US")
        XCTAssertEqual(model.enabledLocaleIDs, ["en-US"], "The last language cannot be removed")
        model.enableLanguage("de-DE")
        model.enableLanguage("de-DE")
        model.enableLanguage("ja-JP")
        XCTAssertEqual(model.enabledLocaleIDs, ["en-US", "de-DE", "ja-JP"])
        model.mode = .fixed("de-DE")
        model.models = ["en-US": .installed, "ja-JP": .installed, "de-DE": .supported]
        XCTAssertFalse(model.modelsReady)
        XCTAssertEqual(model.downloadableLocaleIDs, ["de-DE"])
        model.disableLanguage("de-DE")
        XCTAssertEqual(model.mode, .automatic, "Removing the fixed language falls back to Auto-detect")
        XCTAssertEqual(model.enabledLocaleIDs, ["en-US", "ja-JP"])
        XCTAssertNil(model.models["de-DE"])
        XCTAssertTrue(model.modelsReady)
        let restored = AppModel(defaults: defaults, startServices: false, preferredLanguages: ["ko-KR"])
        defer { restored.hotKey.invalidate() }
        XCTAssertEqual(restored.enabledLocaleIDs, ["en-US", "ja-JP"])
        XCTAssertEqual(restored.mode, .automatic)
    }

    @MainActor func testSavedFixedLanguageIsRestoredEvenIfItWasNotEnabled() throws {
        let suite = "KoeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["en-US"], forKey: "enabledLanguages")
        defaults.set("ko-KR", forKey: "languageMode")
        let model = AppModel(defaults: defaults, startServices: false, preferredLanguages: [])
        defer { model.hotKey.invalidate() }
        XCTAssertEqual(model.mode, .fixed("ko-KR"))
        XCTAssertEqual(model.enabledLocaleIDs, ["en-US", "ko-KR"])
        XCTAssertEqual(model.activeLocaleIDs, ["ko-KR"])
    }

    @MainActor func testAutomaticWarningAppearsPastThreeLanguages() throws {
        let suite = "KoeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["en-US", "ja-JP", "fr-FR"], forKey: "enabledLanguages")
        let model = AppModel(defaults: defaults, startServices: false, preferredLanguages: [])
        defer { model.hotKey.invalidate() }
        XCTAssertNil(model.automaticWarning)
        XCTAssertEqual(model.modeDetail, "English, Japanese, and French, chosen per recording.")
        model.enableLanguage("de-DE")
        XCTAssertNotNil(model.automaticWarning)
        model.mode = .fixed("de-DE")
        XCTAssertNil(model.automaticWarning)
        XCTAssertEqual(model.modeDetail, "Speak German. Transcription stays on this Mac.")
    }

    @MainActor func testRegionalVariantsAreNamedApartAndDuplicatesAreDroppedOnLoad() throws {
        let suite = "KoeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["en-US", "en-GB", "en-US"], forKey: "enabledLanguages")
        let model = AppModel(defaults: defaults, startServices: false, preferredLanguages: [])
        defer { model.hotKey.invalidate() }
        XCTAssertEqual(model.enabledLocaleIDs, ["en-US", "en-GB"])
        XCTAssertEqual(defaults.stringArray(forKey: "enabledLanguages"), ["en-US", "en-GB"], "The repaired list is written back")
        XCTAssertEqual(model.modeDetail, "English (United States) and English (United Kingdom), chosen per recording.")
        model.mode = .fixed("en-GB")
        XCTAssertEqual(model.modeDetail, "Speak English (United Kingdom). Transcription stays on this Mac.")
        XCTAssertEqual(LanguageCatalog.name(for: "ja-JP", in: ["ja-JP", "en-US"]), "Japanese")
    }

    @MainActor func testReadinessProblemExplainsUnavailableAndDownloadingModels() throws {
        let suite = "KoeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["en-US", "ko-KR"], forKey: "enabledLanguages")
        let model = AppModel(defaults: defaults, startServices: false, preferredLanguages: [])
        defer { model.hotKey.invalidate() }
        model.models = ["en-US": .installed, "ko-KR": .unsupported]
        XCTAssertEqual(model.readinessProblem, "Korean is unavailable on this Mac. Remove it or pick another language.")
        XCTAssertTrue(model.downloadableLocaleIDs.isEmpty)
        model.mode = .fixed("en-US")
        XCTAssertNil(model.readinessProblem)
        model.mode = .automatic
        model.models["ko-KR"] = .downloading
        XCTAssertEqual(model.readinessProblem, "Language models are still downloading.")
        model.models["ko-KR"] = .supported
        XCTAssertEqual(model.readinessProblem, "Download the enabled language models to start dictating.")
        XCTAssertEqual(model.downloadableLocaleIDs, ["ko-KR"])
        model.models["ko-KR"] = .installed
        XCTAssertNil(model.readinessProblem)
    }

    @MainActor func testAddingLanguagesDownloadsTheirModelsEvenWhileADownloadIsRunning() async throws {
        let suite = "KoeTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let speech = InstallingSpeech()
        let model = AppModel(defaults: defaults, startServices: false, preferredLanguages: ["en-US"], speech: speech)
        defer { model.hotKey.invalidate() }
        await model.refreshModels()
        XCTAssertEqual(model.models, ["en-US": .installed])
        model.enableLanguage("de-DE")
        model.enableLanguage("ko-KR")
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while model.models["de-DE"] != .installed || model.models["ko-KR"] != .installed || model.installing {
            XCTAssertLessThan(ContinuousClock.now, deadline, "Both added languages should finish installing")
            try await Task.sleep(for: .milliseconds(5))
        }
        let installed = await speech.installed
        XCTAssertEqual(installed, ["de-DE", "ko-KR"])
        XCTAssertTrue(model.downloadableLocaleIDs.isEmpty)
        XCTAssertNil(model.setupError)
    }

    func testUncertaintyMarginWidensWithMoreLanguages() throws {
        XCTAssertEqual(LanguageSelector.uncertaintyMargin(candidateCount: 1), 0.065)
        XCTAssertEqual(LanguageSelector.uncertaintyMargin(candidateCount: 2), 0.065)
        XCTAssertEqual(LanguageSelector.uncertaintyMargin(candidateCount: 4), 0.085, accuracy: 1e-9)
        // A 0.07 score gap is decisive between two languages but a tie among four.
        let best = TranscriptCandidate(localeID: "en-US", text: "Hello", confidence: 0.90, audioCoverage: 1)
        let runnerUp = TranscriptCandidate(localeID: "de-DE", text: "Hallo", confidence: 0.82, audioCoverage: 1)
        let far = TranscriptCandidate(localeID: "ja-JP", text: "ハロー", confidence: 0.3, audioCoverage: 1)
        let farther = TranscriptCandidate(localeID: "fr-FR", text: "Allô", confidence: 0.2, audioCoverage: 1)
        XCTAssertFalse(try XCTUnwrap(LanguageSelector.select([best, runnerUp])).isUncertain)
        XCTAssertTrue(try XCTUnwrap(LanguageSelector.select([best, runnerUp, far, farther])).isUncertain)
    }

    func testFrenchWinsAgainstOtherLanguagesAndKeepsAlternatives() throws {
        let french = TranscriptCandidate(localeID: "fr-FR", text: "La réunion est à dix heures.", confidence: 0.94, audioCoverage: 0.95)
        let english = TranscriptCandidate(localeID: "en-US", text: "The reunion.", confidence: 0.4, audioCoverage: 0.5)
        let japanese = TranscriptCandidate(localeID: "ja-JP", text: "十時", confidence: 0.3, audioCoverage: 0.2)
        let result = try XCTUnwrap(LanguageSelector.select([english, french, japanese]))
        XCTAssertEqual(result.best, french)
        XCTAssertEqual(result.best.languageName, "French")
        XCTAssertEqual(result.alternatives, [english, japanese])
        XCTAssertFalse(result.isUncertain)
    }

    func testThreeWayAmbiguityKeepsFrenchAvailable() throws {
        let english = TranscriptCandidate(localeID: "en-US", text: "Hello", confidence: 0.82, audioCoverage: 1)
        let japanese = TranscriptCandidate(localeID: "ja-JP", text: "ハロー", confidence: 0.80, audioCoverage: 1)
        let french = TranscriptCandidate(localeID: "fr-FR", text: "Allô", confidence: 0.79, audioCoverage: 1)
        let result = try XCTUnwrap(LanguageSelector.select([french, japanese, english]))
        XCTAssertTrue(result.isUncertain)
        XCTAssertEqual(result.alternatives, [japanese, french])
    }

    func testMissingConfidenceInThirdLanguageRequiresChoice() throws {
        let english = TranscriptCandidate(localeID: "en-US", text: "Hello", confidence: 0.92, audioCoverage: 1)
        let japanese = TranscriptCandidate(localeID: "ja-JP", text: "ハロー", confidence: 0.7, audioCoverage: 1)
        let french = TranscriptCandidate(localeID: "fr-FR", text: "Allô", confidence: nil, audioCoverage: 1)
        let result = try XCTUnwrap(LanguageSelector.select([english, japanese, french]))
        XCTAssertTrue(result.isUncertain)
        XCTAssertEqual(result.alternatives.last, french)
    }

    func testFrenchTextAndLocaleVariantsArePreserved() throws {
        let text = "À Noël, l’élève goûte une crème brûlée. Est-ce prêt ?"
        for localeID in ["fr-FR", "fr_FR", "fr-CA"] {
            let candidate = TranscriptCandidate(localeID: localeID, text: text, confidence: nil, audioCoverage: 1)
            let result = try XCTUnwrap(LanguageSelector.select([candidate]))
            XCTAssertEqual(result.best.languageName, "French")
            XCTAssertEqual(result.best.text, text)
            XCTAssertFalse(result.isUncertain)
            XCTAssertEqual(JapanesePunctuation.normalize(text, localeID: localeID), text)
        }
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
        XCTAssertTrue(result.alternatives.isEmpty)
        XCTAssertFalse(result.isUncertain)
    }
}

/// Reports every locale as downloadable until `install` is called for it.
private actor InstallingSpeech: SpeechProcessing {
    private(set) var installed: [String] = []
    func supportedLocaleIDs() -> [String] { ["en-US", "de-DE", "ko-KR"] }
    func statuses(localeIDs: [String]) -> [String: ModelAvailability] {
        Dictionary(uniqueKeysWithValues: localeIDs.map { ($0, $0 == "en-US" || installed.contains($0) ? .installed : .supported) })
    }
    func install(localeIDs: [String]) async throws {
        try await Task.sleep(for: .milliseconds(20))
        installed += localeIDs
    }
    func transcribe(url: URL, localeIDs: [String]) async throws -> TranscriptSelection { throw SpeechFailure.noSpeech }
}
