# Localized App Store screenshots (Signal redesign)

Renders the "App Store screenshots" set from the **Vox.md — App Store screenshots** Design artifact
(https://claude.ai/artifact/DxaXMyjAz58gwu9q2pCKCk) for every store locale, keeping the frame design
and swapping the text — and, where a real localized capture of the app exists, the device screen.

**Real captures** (`CAPTURE.md`): the iPhone (composer, live recording, Routes, Library), iPad (capture,
Library) and iPhone Duo (inner composer/Library, tabletop, cover capture/recording) screens are real
simulator captures of the Debug app in each language, seeded with the same notes as the frames
(`seed_samples.py` → `-VoxSeedSamples`). The Mac workspace, quick capture, Library and Activity screens are
real window captures of the Debug Mac app (`capture_mac.py`; it backs up and restores this Mac's Vox.md data,
since the Debug build shares the container, and needs Accessibility + Screen Recording permission). The voice
keyboard, Lock Screen and iPad/Duo Split View frames still use the translated Design mockups. The Mac app's
built-in demo history and activity text (e.g. "Mac navigation review") is English in every locale.

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

Product page creative assets (App Store Connect › Product Page Information › Header and Search Results) render
from `P2_Header` / `P2_Search`: `header/01-header.png` (3840×1646, 21:9; art safe area 1646×661 at 1097,493) and
`search/01-search-results.png` (3840×2560, 3:2; art safe area 2168×1030 at 836,765). The headline sits in a
`data-fit` box over the safe area; the renderer shrinks its type (to 70% at most) until every locale fits without
extra line breaks. Devices and chips outside the safe area are bleed: they're cropped away on narrow screens.
Google Fonts responses are cached in `node_modules/.cache/store-screenshots-fonts/` (headless loads were stalling).
Arabic renders right-to-left. Scripts Geist lacks (CJK, Arabic, Thai, Devanagari) fall back to the macOS system fonts.

When the design changes: re-export the changed `.dc.html` files from the artifact into `templates/`, run `--extract`,
and translate the new keys (the renderer lists any that are missing).
