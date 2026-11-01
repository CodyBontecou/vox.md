# Android localization parity — November 1, 2026

Coverage is implemented; human linguistic and visual release approval remains open.
The parity execution ledger and generated per-source localization ledger now record
zero missing-source fallbacks across 779 runtime phrases and 22 non-English locales.
The 557 original English fallback sources are retained in the Android supplement;
three leave the active inventory when singular/plural call sites are consolidated.
The supplement has 571 sources including added quantity forms. Existing iOS values
retain priority. File examples and technical identifiers deliberately retain syntax.

Translations were generated locally with Meta M2M100 1.2B, with explicit terminology,
billing and quantity corrections and reuse of matching iOS wording. No repository
strings were sent to an external translation service. All Android additions retain
`requires-human-review`; neither coverage nor automated tests establishes native
linguistic fidelity. In particular, long explanations and inherited iOS translations
still require native-speaker source-fidelity and UI-fit review before release.

Twelve count patterns select CLDR categories through Android ICU. Arabic zero, one,
two, few, many and other, Slavic one/few/many/other and the other supported locale
categories are explicit. Mixed string/count argument order is preserved. Wear queue
summaries use generated Android quantity resources. Six numeric formats such as HTTP
codes and heading levels are explicitly exempted. New unclassified count sources fail
closed. Removed English-only singular branches and the speaker `s` suffix cannot
bypass quantity selection.

RTL string arguments use presentation-only BidiFormatter wrapping; original URLs,
paths and stored data remain unchanged. Forward arrows mirror and Chinese and Portuguese region-only
locales resolve Hans/Hant tables. The preset rail retains the user's physical side.
Long translated statistics can wrap instead of using a fixed 48 dp width.

Regression checks cover all supported locales, Chinese regional resolution, Arabic
six-way and Russian/Polish cardinal selection, mixed-direction URLs and a clickable
RTL Back control at 200% text size. Catalog mutations reject missing locales, changed
format arguments, lost template tokens, missing plural categories, unclassified
counts and false human approval. Existing iOS wording always wins over Android drafts.

## Validation

Implementation commit: `d000ca3`. Oracle fixture commit: `7e9d459`, regenerated
from that clean implementation revision. All 14 oracle cases are unchanged;
clean-tree source/compiler provenance and fixture identity checks pass.

- Android/Wear: `check assembleDebugAndroidTest :app:validateDebugArtifacts
  :wear:validateWearDebugArtifacts releaseReadiness` passed, including lint,
  all 274 JVM tests, four-ABI phone native artifacts, debug APK validation,
  optimized phone/Wear release bundles and readiness checks.
- Phone: 88 instrumentation tests completed on the dedicated API-36 Vox emulator;
  84 passed, four inference-model-fixture tests were skipped, zero failed.
  The five new localization tests also passed independently. Arabic-Indic digit
  assertions use Egyptian Arabic (`ar-EG`); generic Arabic may legitimately use
  Western digits on this Android/CLDR version.
- Data/provider: all 22 database, entry-template and SAF tests passed. Both real
  uninstall/reinstall quota phases passed; the isolated fixture package was removed.
- Rust: all 49 workspace tests, rustfmt, strict Clippy and byte-identical
  Swift/Kotlin binding regeneration passed.
- Swift: 655 shared and 381 capture-core XCTest tests plus 10 Swift Testing tests
  passed using an isolated shared container.
- Project contracts: all 65 script and 140 contract/mutation tests passed. The
  manifest validates 193 governed files, 98 fixtures, 282 capability rows and four
  mirrors; toolchain validation binds 229 implementation hashes.
- Localization generation/freshness, the 347-entry feature inventory, registry
  coverage and whitespace checks passed.

These are automated local/emulator results. Native-speaker approval, canonical RTL
visual approval and physical OEM/Wear qualification remain open; no human or Play
release approval is inferred.

The parity ledger adds `cap.ui.localization` as implemented with automated-check evidence; acceptance remains planned
until human device/linguistic qualification. The ledger now contains 282
capabilities: 262 verified, 13 implemented and seven inventoried. Of 247 Android/Wear
applicable rows, 233 are verified, 13 implemented and one inventoried.
