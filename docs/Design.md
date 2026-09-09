# Koe interface

Koe is a quiet native utility for switching between English and Japanese dictation. The main surface is a 360-point menu bar popover. Recording gets a compact, nonactivating panel above the bottom edge of the active display.

Use system appearance and SF Pro: 22-point semibold app name, 13-point body, and 11-point supporting text. Semantic window, label, and separator colors adapt to dark mode. Reference light palette: window #F5F5F7, text #1D1D1F, secondary #6E6E73, separator #D2D2D7, accent blue #007AFF, recording red #FF453A. One blue microphone tile identifies Koe; motion is confined to the input meter while recording and respects reduced motion.

```
 [mic] Koe                         [quit]
       Dictation on your Mac

 [ Japanese | English | Auto-detect ]
 English and Japanese, chosen per recording.

 [       Hold to dictate       ⌃⌥Space ]
 Keep the shortcut held. Release to insert.
 ──────────────────────────────────────
 Shortcut                     [⌃⌥Space]
 Launch at login                   [  ]
 ──────────────────────────────────────
 Offline languages
 English                       Ready
 Japanese                      Download
 [Download language models]

 Microphone                     Allow
 Insert into other apps         Enable

 [Last transcript, when available]
```

The native grouped settings support this brief better than a separate app window or a decorative dashboard. Text stays left aligned; settings and status values align on the right. An ambiguous automatic result offers both actual transcripts before insertion.

The push-to-talk indicator is a 216 × 52-point dark capsule with a small cancel control, a microphone-driven waveform, and elapsed time. The waveform conveys recording activity without a second red dot or an instruction line. It appears during setup, stays visible while the shortcut is held, and switches to “Transcribing…” on release. Preparing, recording, transcribing, and completion notices use the same explicit window bounds, with no window-size animation. Completion uses a single short label (“Inserted”, “Sent”, or “Copied”); full destination details remain accessible in a tooltip and under Last dictation in the menu. The panel never takes keyboard focus. Error and language-choice panels use only the extra room their content needs.
