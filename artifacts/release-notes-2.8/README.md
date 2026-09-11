# Vox.md 2.8 release-note captures

Captured with Argent 0.24.0 from the current `main` build at
`f4abbcb7820de66777c3d0706427731f1d1a4d13` on the iPhone 17 Pro iOS 27
simulator (`1CF95DBC-EBCE-4698-B2FA-DD411B6ED2A4`). The app shown is Vox.md
2.8 (1), built locally with Xcode 27 beta.

Every recording was explicitly stopped. The clips contain synthetic demo text,
have visible touch indicators, no Argent watermark, and no audio track.

## Notelet-ready exports

Use the files in [`notelet/`](notelet/). They are focal 720×720 crops so
Notelet's square, aspect-fill player will not cut off the demonstrated controls.
All are H.264 Main, 30 fps, `yuv420p`, BT.709 limited range, silent, and
fast-start encoded.

| File | Length | Demonstrates | Suggested Notelet title |
| --- | ---: | --- | --- |
| `01-preset-quick-access-square.mp4` | 7.77 s | Pinned presets, emoji identities, one-tap switching, and rail fallback | **Switch workflows in one tap** |
| `02-task-send-undo-square.mp4` | 8.50 s | Compact Markdown task insertion, Send, five-second Undo, and draft restoration | **Send now. Undo if you need to.** |
| `03-capture-bar-options-square.mp4` | 8.70 s | Left/right preset rail, 12/24-hour timestamps, review, and send confirmation | **Make the Capture Bar yours** |
| `04-recording-controls-square.mp4` | 9.07 s | Expanded voice controls, Add to Draft/Send Immediately, Audio, and control help | **Recording controls, explained** |
| `05-image-alt-text-square.mp4` | 5.27 s | On-device Apple Intelligence processing and optional image alt text | **Private descriptions for images** |
| `06-audio-filename-template-square.mp4` | 6.10 s | Per-preset audio filename tokens and the live filename example | **Name saved audio your way** |

A concise 2.8 Notelet sequence would use clips **01, 02, and 05**, followed by
the existing text list. Clips 03, 04, and 06 are ready if a more complete tour
is preferred.

Suggested descriptions:

- **01:** “Pin your favorite Capture Presets, give them an emoji, and switch workflows without leaving Capture.”
- **02:** “Task presets insert compact Markdown checkboxes. After Send, Undo restores the capture for five seconds.”
- **03:** “Choose the preset rail side, timestamp clock, review behavior, and whether preset sends need confirmation.”
- **04:** “Choose what stopping a recording does, keep audio when needed, and open contextual help right from Capture.”
- **05:** “Optionally describe photos, screenshots, and sketches on device while preserving any descriptions already present.”
- **06:** “Give each preset its own audio filename template with date, time, preset, and capture ID tokens.”

## Source material

- [`videos/`](videos/) contains the uncropped 1206×2622 Argent recordings.
- [`screenshots/`](screenshots/) contains setup and reference frames.
- [`contact-sheets/`](contact-sheets/) contains reviews of the portrait captures.
- [`contact-sheets/notelet/`](contact-sheets/notelet/) contains reviews of the
  final square exports.
- [`logs/`](logs/) contains the successful stop result for each recording.

Rebuild the square exports with:

```sh
./artifacts/release-notes-2.8/make-notelet-assets.sh
```

The dynamic crops in clips 03 and 04 follow the active control or sheet instead
of shrinking the entire portrait screen into Notelet's square frame.

## Simulator limitation

Apple Speech was unavailable in this simulator. Vox.md correctly preserved test
recordings in its durable queue, but these assets do not claim to demonstrate a
successful live transcript or continuous-dictation result. Those flows still
need a real-device capture if release media must show actual speech processing.
