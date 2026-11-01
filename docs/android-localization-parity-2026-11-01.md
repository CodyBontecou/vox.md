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

Validation results will be recorded after the full checks finish.

The parity ledger adds `cap.ui.localization` as implemented with automated-check evidence; acceptance remains planned
until human device/linguistic qualification. The ledger now contains 282
capabilities: 262 verified, 13 implemented and seven inventoried. Of 247 Android/Wear
applicable rows, 233 are verified, 13 implemented and one inventoried.
