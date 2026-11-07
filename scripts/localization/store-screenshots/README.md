# Localized App Store screenshots (Signal redesign)

Renders the "App Store screenshots" set from the **Vox.md — App Store screenshots** Design artifact
(https://claude.ai/artifact/DxaXMyjAz58gwu9q2pCKCk) for every store locale, keeping the frame design
and swapping the text — and, where a real localized capture of the app exists, the device screen.

**Real captures** (`CAPTURE.md`): the iPhone (composer, live recording, Routes, Library), iPad (capture,
Library) and iPhone Duo (inner composer/Library, tabletop, cover capture/recording) screens are real
simulator captures of the Debug app in each language, seeded with the same notes as the frames
(`seed_samples.py` → `-VoxSeedSamples`). The voice keyboard, Lock Screen, iPad/Duo Split View and Mac
frames still use the translated Design mockups. `capture_mac.py` exists but runs against the Mac app's real
sandbox container (shared bundle id), so don't use it on a machine with real Vox.md data.

Pipeline: capture (CAPTURE.md) → `normalize_captures.py` (rotates iPad/Duo-inner buffers upright into
`store-signal-captures/_ready/`) → `render.mjs` (uses a capture when present, `--mock` to ignore them).

- `templates/` — the artifact's `AS_*` store frames plus the Signal app screens they embed (`.dc.html`),
  copied verbatim except for canvas-only font URLs (Geist loads from Google Fonts instead).
- `strings/en.json` — every visible English string (keys are whitespace-normalized; `text` keeps line breaks).
- `strings/<locale>.json` — translation per key. Headlines may contain `\n` to set their own line breaks.
- `render.mjs` — headless Chrome renderer: expands the template syntax, applies translations, screenshots
  each frame at its exact size, and warns about untranslated strings or text boxes that overflow more than in English.
- `contact-sheet.py` — one review JPEG per locale in `artifacts/localization/store-signal/_sheets/`.

```bash
PUPPETEER_SKIP_DOWNLOAD=1 npm ci                                   # uses system Chrome (CHROME_PATH to override)
node scripts/localization/store-screenshots/render.mjs --extract    # after changing templates
node scripts/localization/store-screenshots/render.mjs              # all locales
node scripts/localization/store-screenshots/render.mjs --locale ja,ar-SA --only iphone
python3 scripts/localization/store-screenshots/contact-sheet.py ja
```

Output: `artifacts/localization/store-signal/<locale>/<iphone|ipad|duo-inner|duo-cover|mac>/NN-name.png`
(iPhone 1206×2622, iPad 2752×2064, Duo inner 2853×2007, Duo outer 1398×2034, Mac 2880×1800).
Arabic renders right-to-left. Scripts Geist lacks (CJK, Arabic, Thai, Devanagari) fall back to the macOS system fonts.

When the design changes: re-export the changed `.dc.html` files from the artifact into `templates/`, run `--extract`,
and translate the new keys (the renderer lists any that are missing).
