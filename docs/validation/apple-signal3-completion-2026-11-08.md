# Apple Signal 3.0 completion review — November 8, 2026

## Source and review scope

GitHub was inspected read-only on November 8. Main was `d944afb9dc9bde2b5dd8e00a9bb2309557e6849b`; #59 (Signal redesign), #64 (localized store screenshots), #65 (fastlane version selection), and #67/#68 (QA fixes) were merged. The pushed `fix/mobile-edge-case-qa` branch was `8a059cd578ff5ed4c825c6b290e67230d8c71b69`, four commits ahead of main:

| Commit | Purpose |
| --- | --- |
| `70330774` | Apple capture, settings, presentation, accessibility, and localization QA fixes |
| `1e1ab52b` | Android capture/export recreation fixes |
| `f884b4e5` | Governed verification hashes and localization inventory pins |
| `8a059cd5` | Swift oracle provenance regeneration |

All four commits are preserved in the review branch. Work was isolated in `/private/tmp/vox-apple-signal3-20261108`, branch `fix/vox-apple-signal3-finish-20261108`. No root or component `AGENTS.md` was found in the repository or its ancestor directories. The starting checkout, its modified fastlane report, and its untracked source, agent configuration, and QA artifacts were left untouched.

## Apple findings

The existing Apple commit implements every reproducible finding in the historical notes below. Source review found no additional unimplemented finding within those notes. The notes and evidence were copied byte-for-byte into this branch so reviewers can inspect them; all 67 relative evidence links resolve. Their simulator observations are historical evidence from prior work, not a new run under this task.

| Historical pass | Finding addressed in `70330774` |
| --- | --- |
| [Initial exploratory QA](ios-exploratory-qa-2026-11-07.md) | Visible destination validation, Obsidian search failure feedback, affected Turkish strings |
| [Pass 2](ios-edge-qa-pass2-2026-11-07.md) | Reject hostless web links across composer, entry points, rendering, and engine admission |
| [Pass 3](ios-edge-qa-pass3-2026-11-07.md) | Present template validation/save errors immediately |
| [Pass 4](ios-edge-qa-pass4-2026-11-08.md) | Refresh surface pin summaries; recognize installed Automatic fallback |
| [Pass 5](ios-edge-qa-pass5-2026-11-08.md) | Present unavailable-email feedback on Help; label settings and Capture Bar controls |
| [Pass 6](ios-edge-qa-pass6-2026-11-08.md) | No reproducible new defect found |
| [Pass 7](ios-edge-qa-pass7-2026-11-08.md) | Separate internal-link insertion validation from vault-loading errors |

The same Apple commit contains composer glyph restoration, recording-error presentation, purchase-verification feedback, and delivery-only Unicode search regressions. App-hosted tests and historical live checks remain documented in that commit and the original evidence; they were not rerun here.

## Fresh portable verification

- `swift test --package-path Packages/VoxboardShared --scratch-path /private/tmp/vox-apple-swift-build --disable-sandbox --skip-update --filter 'CaptureWebLinkTests|CaptureDeepLinkParserTests|CaptureMarkdownRendererTests|CaptureCoreEnginePolicyTests|URLDeliveryValidationTests'`: **38 passed**, zero failures (30 capture-core, 8 shared URL-delivery). Production package targets and tests compiled; existing compiler warnings remain.
- `swift run --package-path Packages/VoxboardShared --scratch-path /private/tmp/vox-apple-swift-build --skip-build VoxboardPersistenceFixtures --validate`: passed synthetic persistence validation.
- `CLANG_MODULE_CACHE_PATH=/private/tmp/vox-apple-clang-cache SWIFT_MODULECACHE_PATH=/private/tmp/vox-apple-swift-cache bash scripts/test-capture-view-structure.sh`: 14 positive/negative checker fixtures passed; three capture files passed the 600-token section budget. An initial default-cache attempt could not write the sandboxed compiler cache; directing caches to task-owned temporary paths resolved it.
- `python3 scripts/localization/audit_runtime_catalogs.py`: zero structural errors; all 2,845 main-app keys covered in every runtime locale. There are 526 source-identical entries requiring linguistic review across catalogs; structural coverage does not establish translation quality.
- `python3 docs/featureset/scripts/check_inventory.py`: all 347 inventoried features and registry coverage passed.
- `bash scripts/test-project-contracts.sh`: 90 script tests passed; M0, capability conversion, portable contracts, toolchain pins, and validation definitions passed. Contract tests: **159 passed, 1 error**; see the qualification gap below. The shell stops at that error before its final project-structure block; executing that exact embedded Python block separately passed. [Fresh logs](../../artifacts/validation/apple-signal3-completion-2026-11-08/).
- `ruby -c fastlane/Fastfile`: passed. Read-only source inspection confirms `app_version` reads the unique project `MARKETING_VERSION` (`3.0`) unless explicitly overridden. No fastlane lane was executed.
- Read-only PNG/header and translation-key inventory: 22 fastlane locales, each with six 1320×2868 iPhone PNGs and three 2752×2064 iPad PNGs (198 total); all 22 screenshot translation dictionaries contain the 272 English template keys. This establishes local artifact presence and dimensions, not visual approval or App Store Connect state.

## Qualification gap

`LocalIntelligenceEvaluationTests.test_retained_full_model_and_cross_platform_reports_are_truthful` rejects the retained full-phone/model receipt because production implementation bytes changed. At the four-commit baseline the stale inputs are `LocalSpeech.kt` and `AndroidCaptureRepository.kt`. The receipt binds a real full-phone/model run, including mandatory speech inference and production delivery/retry assertions. Updating its hashes without executing those assertions would misrepresent evidence. The validator and receipt are preserved, and this remains a review/qualification blocker until a separately authorized full model/device run produces fresh evidence. The additional Android recovery changes must also be included in that run.

No simulator, emulator, Argent, physical-device, audio/model, or app-hosted QA was performed under this task. Historical gaps include configured-mail composition and clipboard delivery, successful audio/file import, download cancellation, inaccessible/large vaults, DST transitions, network delivery, actual widgets/controls, and hardware behavior. These are coverage limits, not established failures.

No upload, submission, release, merge, production write, or deployment was performed. Git state alone does not establish installed or live product state. Task worktrees and background Herdr tabs are retained for review; no shared build process was stopped.
