# Validation on 9 September 2026

Environment: macOS 26.6.2, Xcode 26.6, Apple silicon. The app uses the macOS 26 public Speech framework APIs and no third-party dependencies.

- Xcode Debug build passed.
- Xcode Release build passed and the resulting app passed strict code-signature verification.
- Thirty-two XCTest cases cover supported language modes, persisted shortcut encoding, shortcut validation, actual Carbon Escape registration and suspension/resumption, English/Japanese confidence selection, ambiguity handling, missing confidence, numeric dictation, empty/silent candidate rejection, menu bounds, push-to-talk press/release handling, key repeat, permission races, cancellation while held, and indicator visibility. Recovery checks use real short/silent/quiet audio files and a recognizer that deliberately ignores cancellation. Insertion-policy checks cover the same foreground app, different apps, missing targets, permissions, and secure fields. Japanese punctuation checks cover direct questions, statements, acknowledgements, existing question marks, quotes/code, line breaks, and unchanged English text.
- A production-engine English fixture synthesized with the native Samantha voice was transcribed as: “Please move the meeting to tomorrow morning at 10. I will send the notes after lunch.” Auto-detect selected English (confidence 0.933 versus 0.557 for the Japanese model).
- A production-engine Japanese fixture synthesized with the native Kyoko voice was transcribed as: “明日の会議は午前 10時に変更してください。昼ごはんの後で資料を送ります。” Auto-detect selected Japanese (confidence 0.964 versus 0.206 for the English model).
- The same fixtures passed in their respective fixed-language modes.
- Both automatic-mode fixtures passed under `sandbox-exec` with `(deny network*)`. This blocks networking for the test process, while Apple’s shared system speech service remains outside that sandbox. The production recognizer checks for already-installed assets and never calls a network speech API or installer during recognition.
- Both language assets were installed through Apple’s `AssetInventory` API.
- The built bundle declares `LSUIElement = true`; the executable also selects the accessory activation policy.
- The menu, recording overlay, and ambiguous-language chooser were rendered from the production SwiftUI views and visually inspected offscreen.
- Recording, transcribing, sent, and copied HUD renders all retain the same 216×52-point capsule. The native panel regression includes microphone-level changes and a completion message with a long destination name, allowing SwiftUI to update before checking the bounds.
- A Kyoko fixture with `どうすればいいですか。` reproduced the question-punctuation issue in the unmodified Apple output. With the local punctuation pass, it produces `どうすればいいですか？`. The same mixed question/statement fixture retains `今日は雨です。`, and both Japanese and Auto-detect paths were exercised. A separate fixture with explicit question intonation already produced native `？` before the correction. These synthetic examples do not establish performance across natural accents or ambiguous questions.
- Push-to-talk lifecycle tests use an injected recorder and permission gate so timing cases are tested without recording the microphone or inserting text. A native NSPanel test checks that the recording indicator is visible, cannot take keyboard focus, keeps its bounds on release, and hides on cancellation.

The menu uses the status item's display, explicit content bounds, and a stable scrollable viewport. The installed menu was visually inspected through native UI automation. Automated live insertion verification was inconclusive because the test tool focused an accessibility element without making its application the foreground app; the insertion guard correctly declined to paste. Cross-application insertion, shortcut editing, and launch at login require the interactive acceptance checks below. Synthetic voice fixtures establish the engine integration, not general accuracy for natural speech or mixed-language utterances.

## French support validation on 11 September 2026

- All 37 XCTest cases passed, including French preference persistence, model readiness, three-language selection, missing confidence in the third candidate, and preservation of French accents and punctuation.
- The Release build passed strict code-signature verification.
- Apple’s `fr-FR` model was installed through the production installer. A Thomas voice fixture produced “La réunion commence demain matin à 10h. Je vous enverrai les notes après le déjeuner” in both French and Auto-detect modes. Auto-detect selected French without requiring a choice (confidence 0.996 versus 0.280 for Japanese and 0.262 for English).
- English and Japanese synthesized fixtures also selected their expected languages in the updated three-model Auto-detect mode, without requiring a choice (winning confidence 0.916 and 0.952 respectively). All three models reported installed afterward.
- The production menu and scrollable three-language chooser were rendered offscreen and visually inspected. All four language segments and all three sample transcripts fit.
- These checks use synthesized speech; natural French dictation and insertion remain part of the interactive acceptance check.

## Selectable languages validation on 12 September 2026

- All 48 XCTest cases passed, including a fresh install surviving a mode change and restart without legacy migration, automatic model download for added languages (queued while another download runs), legacy `japanese`/`english`/`french` preference migration, fresh-install defaults derived from the system’s preferred languages, adding and removing languages with mode fallback, restoring a saved fixed language that was not in the enabled list, the Auto-detect warning past three languages, region-aware names for two variants of one language, readiness messages for unavailable and downloading models, and the widened uncertainty margin.
- `speech-check` listed all 30 locales Apple ships on this Mac (ten languages) with their model status. A Kyoko fixture selected Japanese over English (confidence 0.998 versus 0.337) with `en-US ja-JP` enabled. A Samantha fixture selected English with `en-US ja-JP fr-FR` enabled without requiring a choice (0.905 versus 0.743 for French and 0.678 for Japanese); the French model’s relatively high confidence on English speech is the related-language effect described in the README. The same fixture in fixed `ja-JP` mode produced a single pass.
- The production menu was rendered offscreen with three languages (segmented picker) and with six (pop-up picker, Auto-detect warning, one language pending download, one unavailable) and visually inspected.
- These checks use synthesized speech; dictation in the newly listed languages remains part of the interactive acceptance check.

## Interactive acceptance check

1. Open `~/Applications/Koe.app`; verify the waveform appears in the menu bar and no Dock icon appears.
2. Allow microphone access, then enable Koe in Accessibility. Reopen the menu to refresh permission status.
3. Focus a disposable text document. Hold the shortcut, speak, and release to insert. Repeat in each enabled language and verify that Return is not sent. The waveform should remain visible while held, followed by a transcribing indicator after release.
4. Repeat with Auto-detect. A close result should offer all usable transcripts. Add a fourth language and confirm the warning appears; remove the language selected in the picker and confirm the picker returns to Auto.
5. Record and press Escape; verify the overlay closes without insertion. Record again to ensure cancellation did not leave the microphone running.
6. Change the shortcut, then verify the previous shortcut no longer starts Koe and the new one records while held and finishes on release. Escape out of shortcut recording and verify the saved shortcut still works.
7. Switch to another application during recognition; verify the result is copied rather than inserted there. Within the original app, verify insertion follows the currently focused field even if its web editor recreated the accessibility node.
8. Verify the clipboard is preserved during the Command–V fallback and that a new user copy is not overwritten.
9. Test without network access after models are ready. Enable launch at login, sign out/in when convenient, and verify a single menu bar instance launches.
10. Tap the shortcut briefly: the indicator should dismiss immediately without transcribing. Try a silent clip, then start a fresh hold during a stalled transcription and verify recording can begin immediately.

Offscreen view rendering can be reproduced without microphone access:

```sh
xcrun swiftc -swift-version 6 -parse-as-library -o build/render-preview \
  Koe/AppModel.swift Koe/Core/*.swift Koe/Services/*.swift Koe/UI/*.swift Tools/RenderPreview.swift
build/render-preview
```
