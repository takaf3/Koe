# Koe

A native macOS menu bar dictation app for English, Japanese, and French. Hold a configurable shortcut while speaking, then release it to transcribe with Apple Speech and insert the result at your cursor. No Dock icon, account, API key, subscription, or server transcription.

<p align="center">
  <img src="docs/assets/koe-demo.gif" alt="Koe’s live waveform reacts to speech while recording, then displays Sent when dictation finishes." width="960">
</p>

<p align="center"><em>Hold to speak. Release to insert.</em></p>

## Requirements

- macOS 26 or newer on an Apple silicon Mac supported by `SpeechTranscriber`.
- Microphone access. Accessibility access enables insertion into other apps; without it, results are copied to the clipboard.
- A one-time internet connection to install Apple’s English, Japanese, and French language models. Apple manages these shared system assets and may update or evict them. Koe checks availability and never falls back to a cloud recognizer.
- Xcode 26 or newer to build. No third-party libraries are required. XcodeGen is only needed if you change `project.yml` and regenerate the checked-in Xcode project.

## Install and use

```sh
bash scripts/install.sh
```

The app is installed into `~/Applications/Koe.app`. Click the waveform in the menu bar.

1. **Auto** (Auto-detect) is selected by default and appears first. You can also select **Japanese**, **English**, or **French**. Download the language models if prompted.
2. Allow microphone access and enable Accessibility for Koe using the buttons in the menu.
3. Click the shortcut button and press your preferred combination. The default is **Control–Option–Space**. Shortcuts must include Control, Option, or Command and a regular key; modifier-only/Fn-only shortcuts are not supported. Conflicting shortcuts are rejected and the previous shortcut remains active.
4. Focus a text field in another app. **Hold the shortcut while speaking, then release it to finish.** A small floating waveform shows microphone activity and elapsed time. On release, the bar shows “Transcribing…” until insertion completes. The HUD stays 216×52 points through setup, recording, transcription, and the brief “Inserted”, “Sent”, or “Copied” confirmation. Destination details appear under **Last dictation** in the menu and in the confirmation’s tooltip. **Escape** or the bar’s × button discards the recording.

Koe records only while the shortcut is held. If you release before microphone setup or permission completes, that recording is canceled. After granting microphone permission for the first time, hold the shortcut again to speak. Repeated key-down events do not toggle the microphone.

Accidental taps under 250 ms are discarded immediately. Effectively silent audio files are rejected before speech recognition starts. A new hold supersedes an unfinished transcription, so you can retry immediately if the system recognizer stalls.

You can enable **Launch at login** from the menu. Closing the menu leaves Koe running; the power button quits it.

## Language behavior

English uses `en-US`, Japanese uses `ja-JP`, and French uses `fr-FR`. Fixed-language modes require only their selected model and perform one recognition pass. Auto-detect requires all three models; existing users need to download the French model before using Auto-detect again. Auto-detect evaluates the same audio with all three Apple models locally and compares duration-weighted acoustic confidence and recognized audio coverage. Clear results are inserted automatically. Close scores or missing confidence show all usable transcripts so you can choose.

Apple’s API takes a fixed locale; this comparison is an application heuristic, not an Apple audio-language detector. Confidence scores across locales are not calibrated. Very short, ambiguous, or mixed-language speech may need manual language selection. Auto-detect selects one primary language per recording and takes longer than a fixed mode. The app transcribes after you finish speaking, rather than displaying live words.

Japanese punctuation comes from Apple’s recognizer. It can produce question marks, but sometimes uses `。` even for direct questions. Koe applies a small offline writing-style correction to sentence endings such as `ですか`, `ますか`, and `でしょうか`, using `？` when Apple supplied a full stop or no terminal punctuation. This also applies to Japanese candidates in Auto-detect. Existing question marks, ordinary statements, quoted questions, and common acknowledgements such as `そうですか。` are preserved. This rule is deliberately limited: casual questions distinguished only by intonation (for example, `明日来る？`) still depend on Apple’s recognition. It does not infer intent or rewrite sentence wording.

## Insertion and privacy

- Recording is indicated by a red microphone in the menu bar and a compact floating waveform near the bottom center of the display. The bar stays on that display through transcription and does not take focus from your text field.
- Koe inserts into the current keyboard focus in the original app. It does not require the accessibility element to be identical to the one captured at recording start: web editors can recreate those elements or omit them entirely. If a different app becomes active, Koe copies the transcript instead. It never sends Return or submits text.
- Koe tries the accessibility selected-text API first, then uses a targeted Command–V. The fallback preserves all clipboard types and restores the old clipboard after 900 ms if nothing else has been copied. Apps that process paste slowly or expose unusual accessibility trees may require copying from **Last dictation**.
- Secure text fields are excluded when macOS exposes them as secure. Some applications expose incomplete accessibility information.
- Audio is held in a private temporary CAF file during the recording and recognition. It is deleted on completion, cancellation, errors, and normal quit. Leftover audio from a crash is removed at the next launch. No transcript history is written to disk; only the most recent transcript is retained in memory until cleared or quit. Language and shortcut preferences are saved in UserDefaults.
- Recording stops after five minutes. Recognition has a duration-based timeout of 10–60 seconds and is cancellable; timeout and no-speech notices dismiss automatically. Accessibility queries have a short timeout so an unresponsive editor cannot hold up the indicator. The app has no network client; only the explicit Apple language-model installer can initiate downloads.

## Build and test

```sh
bash scripts/build.sh
xcodebuild -project Koe.xcodeproj -scheme Koe \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath .derivedData test
```

Open `Koe.xcodeproj` in Xcode to develop. To regenerate the project after changing `project.yml`, run `xcodegen generate`.

The local build uses ad-hoc signing and is not notarized for distribution. Rebuilding may require re-enabling Koe in Privacy & Security settings. For distribution, set your signing team and Developer ID, then notarize the app.

The fixture tool exercises the same production recognizer without recording the microphone or inserting text:

```sh
mkdir -p build
xcrun swiftc -swift-version 6 -parse-as-library -o build/speech-check \
  Koe/Core/LanguageMode.swift Koe/Core/RecordingPolicy.swift Koe/Core/JapanesePunctuation.swift \
  Koe/Services/AudioClipValidator.swift Koe/Services/SpeechService.swift Tools/SpeechCheck.swift
build/speech-check                       # Inspect on-device model availability.
build/speech-check --install             # Install English, Japanese, and French models.
say -v Samantha -o build/english.aiff 'The meeting starts tomorrow morning at ten.'
say -v Kyoko -o build/japanese.aiff '明日の会議は午前十時からです。'
build/speech-check build/english.aiff automatic
build/speech-check build/japanese.aiff automatic
say -v Thomas -o build/french.aiff 'La réunion commence demain matin à dix heures.'
build/speech-check build/french.aiff french
build/speech-check build/french.aiff automatic
```

## Apple references

- [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer)
- [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber)
- [AssetInventory](https://developer.apple.com/documentation/speech/assetinventory)
- [Apple’s SpeechAnalyzer introduction](https://developer.apple.com/videos/play/wwdc2025/277/)

## License

Koe is released under the [MIT License](LICENSE).
