# Vox.md Google Play graphics — Vercel-inspired direction

This set keeps the existing app icon and turns its visual language into a
storefront system: near-black surfaces, Geist typography, a precise grid,
high-contrast white type, and one restrained orange signal accent.

## Deliverables

- `feature-graphic-1024x500.png` — Google Play feature graphic
- `screenshots/01-capture-now.png` — quick capture hero
- `screenshots/02-one-tap-right-place.png` — Capture Presets
- `screenshots/03-private-voice.png` — private voice recording
- `screenshots/04-plain-markdown.png` — open Markdown history
- `screenshots/05-local-models.png` — local transcription models
- `screenshots-contact-sheet.png` — review sheet; not for upload

The screenshots are 1080 × 1920 PNGs. App UI comes from the committed Android
goldens so the marketing images show real product screens.

## Suggested alt text

- Feature graphic: `Vox.md turns local voice and text captures into Markdown.`
- Screenshot 1: `Quick Capture editor writing tasks and meeting notes in Markdown.`
- Screenshot 2: `Capture Presets route notes to an inbox, journal, tasks, or meetings.`
- Screenshot 3: `Private voice recording with audio saved and transcribed on device.`
- Screenshot 4: `Capture history showing sent, retryable, and transcribed notes.`
- Screenshot 5: `Local transcription choices including Android speech and downloadable models.`

## Regenerate

From the repository root:

```sh
node scripts/app-store-images/generate-play-store.mjs
```

The abstract background in `source/` was generated from the app icon as a
style reference. Final copy, typography, cropping, and screenshot composition
are deterministic in the generator.
