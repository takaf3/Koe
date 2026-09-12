import AVFoundation
import Speech

enum SpeechFailure: LocalizedError, Equatable {
    case unsupportedDevice, unsupportedLanguage(String), modelsMissing, noSpeech
    var errorDescription: String? {
        switch self {
        case .unsupportedDevice: "On-device transcription is unavailable on this Mac. Koe requires macOS 26 and supported Apple silicon."
        case .unsupportedLanguage(let id): "Apple’s on-device speech model for \(LanguageCatalog.languageName(for: id)) is unavailable on this Mac."
        case .modelsMissing: "Download the enabled language models in Koe before dictating offline."
        case .noSpeech: "No speech was recognized. Check your microphone and try again."
        }
    }
}

protocol SpeechProcessing: Sendable {
    /// Every locale Apple's on-device transcriber can run on this Mac, as BCP 47 identifiers.
    func supportedLocaleIDs() async -> [String]
    func statuses(localeIDs: [String]) async -> [String: ModelAvailability]
    func install(localeIDs: [String]) async throws
    /// Evaluates the recording in each locale, in order, and picks the best transcript.
    func transcribe(url: URL, localeIDs: [String]) async throws -> TranscriptSelection
}

actor SpeechService: SpeechProcessing {
    func supportedLocaleIDs() async -> [String] {
        guard SpeechTranscriber.isAvailable else { return [] }
        return await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
    }

    func statuses(localeIDs: [String]) async -> [String: ModelAvailability] {
        guard SpeechTranscriber.isAvailable else { return [:] }
        var result: [String: ModelAvailability] = [:]
        for id in localeIDs {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) else {
                result[id] = .unsupported
                continue
            }
            switch await AssetInventory.status(forModules: [SpeechTranscriber(locale: locale, preset: .transcription)]) {
            case .installed: result[id] = .installed
            case .downloading: result[id] = .downloading
            case .supported: result[id] = .supported
            default: result[id] = .unsupported
            }
        }
        return result
    }

    func install(localeIDs: [String]) async throws {
        for id in localeIDs {
            try Task.checkCancellation()
            let transcriber = try await makeTranscriber(id: id)
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        }
    }

    func transcribe(url: URL, localeIDs: [String]) async throws -> TranscriptSelection {
        guard try AudioClipValidator.containsAudio(at: url) else { throw SpeechFailure.noSpeech }
        var candidates: [TranscriptCandidate] = []
        // Sequential analysis avoids contention between Apple model instances.
        // Auto mode evaluates the same recording in every enabled language locally.
        for id in localeIDs {
            try Task.checkCancellation()
            candidates.append(try await recognize(url: url, localeID: id))
        }
        guard let selection = LanguageSelector.select(candidates) else { throw SpeechFailure.noSpeech }
        return selection
    }

    private func makeTranscriber(id: String) async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else { throw SpeechFailure.unsupportedDevice }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: id)) else {
            throw SpeechFailure.unsupportedLanguage(id)
        }
        return SpeechTranscriber(locale: locale, transcriptionOptions: [], reportingOptions: [],
                                 attributeOptions: [.transcriptionConfidence, .audioTimeRange])
    }

    private func recognize(url: URL, localeID: String) async throws -> TranscriptCandidate {
        let transcriber = try await makeTranscriber(id: localeID)
        // Never invoke the installer from dictation. No server-based fallback exists.
        guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
            throw SpeechFailure.modelsMissing
        }
        let file = try AVAudioFile(forReading: url)
        let duration = Double(file.length) / file.processingFormat.sampleRate
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let results = Task { () throws -> TranscriptCandidate in
            var text = ""
            var weightedConfidence = 0.0
            var confidenceWeight = 0.0
            var coveredDuration = 0.0
            for try await result in transcriber.results {
                try Task.checkCancellation()
                guard result.isFinal else { continue }
                text += String(result.text.characters)
                coveredDuration += max(0, result.range.duration.seconds)
                for run in result.text.runs {
                    guard let confidence = run.transcriptionConfidence, confidence.isFinite else { continue }
                    let weight = max(run.audioTimeRange?.duration.seconds ?? 0, 0.01)
                    weightedConfidence += min(max(confidence, 0), 1) * weight
                    confidenceWeight += weight
                }
            }
            return TranscriptCandidate(localeID: localeID,
                text: JapanesePunctuation.normalize(text.trimmingCharacters(in: .whitespacesAndNewlines), localeID: localeID),
                confidence: confidenceWeight > 0 ? weightedConfidence / confidenceWeight : nil,
                audioCoverage: duration > 0 ? min(coveredDuration / duration, 1) : 0)
        }
        do {
            let value = try await withTaskCancellationHandler {
                if let last = try await analyzer.analyzeSequence(from: file) {
                    try await analyzer.finalizeAndFinish(through: last)
                } else {
                    results.cancel()
                    await analyzer.cancelAndFinishNow()
                    throw SpeechFailure.noSpeech
                }
                return try await results.value
            } onCancel: {
                results.cancel()
                Task { await analyzer.cancelAndFinishNow() }
            }
            return value
        } catch {
            results.cancel()
            await analyzer.cancelAndFinishNow()
            _ = try? await results.value
            throw error
        }
    }
}
