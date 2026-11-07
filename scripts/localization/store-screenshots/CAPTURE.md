# Capturing real localized app screens (iOS simulators)

The store frames (`render.mjs`) use a real app capture wherever one exists in
`artifacts/localization/store-signal-captures/_ready/<locale>/<device>/<name>.png`, and the
translated Design mockup otherwise. This runbook produces the raw captures; then run
`normalize_captures.py` (rotates iPad/Duo-inner buffers upright) and `render.mjs`.

Drive simulators with the argent MCP tools only. Debug build:
`build/DerivedData-iOS/Build/Products/Debug-iphonesimulator/Voxboard.app`, bundle id `bontecou.Voxboard`.
Status bars are overridden to 9:41 (`xcrun simctl status_bar <udid> override --time 9:41 --batteryState charged --batteryLevel 100`).

| Device | Simulator | UDID |
|---|---|---|
| iphone | iPhone 18 Pro Max (6.9″, 1320×2868) | 3C7896BD-51AB-4F86-9492-C5A293392FFC |
| ipad | VoxAdaptive-iPad13, rotated LandscapeLeft | 435DC1FA-A227-4D2E-88E0-1E3E6D949CE6 |
| duo | VoxAdaptive-Duo (foldable) | 20A0F884-7272-4657-B488-A5EE8B5E84E2 |

## Launch arguments

Every launch: `-AppleLanguages (<lang>) -AppleLocale <locale> --disable-release-notes
--localization-screenshot <story> -VoxScreenshotUnlocked -VoxAdaptiveSeedDemo -VoxAdaptiveSeedLibrary
-VoxAdaptiveNoAutofocus [extra]`.

The **first launch of each locale** also gets `-VoxScreenshotReset -VoxSeedSamples <json>`:
the reset wipes the app group (drafts, library, routes — reinstalling does NOT clear it) and the
seed then creates the localized routes, draft and library from
`strings/seed/<locale>.json` (pass the file's JSON as one compact string, unescaped; the app reads
the raw argument). Later launches of the same locale reuse that state, so they omit both flags.
Never pass `-VoxScreenshotReset` on a Library launch: reset + seed in one launch races the view.

| Locale | -AppleLanguages | -AppleLocale |
|---|---|---|
| en-US | (en) | en_US |
| ar-SA | (ar) | ar_SA@calendar=gregorian |
| de-DE | (de) | de_DE |
| es-ES | (es) | es_ES |
| es-MX | (es-MX) | es_MX |
| fr-FR | (fr) | fr_FR |
| fr-CA | (fr-CA) | fr_CA |
| hi | (hi) | hi_IN |
| id | (id) | id_ID |
| it | (it) | it_IT |
| ja | (ja) | ja_JP |
| ko | (ko) | ko_KR |
| nl-NL | (nl) | nl_NL |
| pl | (pl) | pl_PL |
| pt-BR | (pt-BR) | pt_BR |
| ru | (ru) | ru_RU |
| th | (th) | th_TH@calendar=gregorian |
| tr | (tr) | tr_TR |
| uk | (uk) | uk_UA |
| vi | (vi) | vi_VN |
| zh-Hans | (zh-Hans) | zh_CN |
| zh-Hant | (zh-Hant) | zh_TW |

## Screens (in this order per locale)

Run every step strictly one after another — tool calls sent together run concurrently, and a
screenshot taken alongside its waits catches the launch transition.

Each: `launch-app` → `await-ui-element` exists {identifier: WAIT} (25 s) → if SEED is set,
`await-ui-element` exists {text: SEED} (15 s) → `await-screen-idle` (10 s, minStableMs 1500) →
`screenshot` scale 1.0, includeImageInContext false, no rotation → copy the reported "Saved:" PNG
to `artifacts/localization/store-signal-captures/<locale>/<device>/<name>.png`.

SEED values come from the locale's seed JSON: `draft1` = first line of `draft` without "# ";
`recs1` = first line of `bookRecs`.

**iphone**

| name | story | extra | first? | WAIT | SEED |
|---|---|---|---|---|---|
| main | 01-quick-capture | | reset+seed | quick_capture_submit | draft1 |
| live | 02-live-recording | `-VoxSeedSamples <json>` (live text) | | capture_recording_pause_toggle | |
| routes | 05-capture-presets | | | capture_preset_add | |
| library | 02-history | | | chevron.left | recs1 |

**ipad** (landscape)

| name | story | extra | first? | WAIT | SEED |
|---|---|---|---|---|---|
| capture | 01-quick-capture | | reset+seed | adaptive_route_inspector | draft1 |
| library | 01-quick-capture | `-VoxAdaptiveSection library` | | sidebar_library | recs1 |

**duo** (fold before launching)

| name | posture | story | extra | first? | WAIT | SEED |
|---|---|---|---|---|---|---|
| inner-capture | open | 01-quick-capture | | reset+seed | adaptive_route_inspector | draft1 |
| inner-library | open | 01-quick-capture | `-VoxAdaptiveSection library` | | library_new_capture | recs1 |
| tabletop | half-open | 02-live-recording | `-VoxSeedSamples <json>` | | capture_tabletop_recording | |
| cover-capture | closed | 01-quick-capture | | | quick_capture_submit | draft1 |
| cover-recording | closed | 02-live-recording | `-VoxSeedSamples <json>` | | capture_recording_pause_toggle | |

`02-live-recording` reads its transcript lines (`liveFinalized`, `liveVolatile`) from the seed JSON,
so pass `-VoxSeedSamples` there too (without the reset).
