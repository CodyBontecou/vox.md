# Signal recovery implementation — local continuation, November 8, 2026

This round continues `b485a25f` in `/private/tmp/vox-apple-signal3-20261108`, branch `fix/vox-apple-signal3-finish-20261108`. All four original QA commits remain ancestors. The shared starting checkout and its dirty/untracked source and evidence remain untouched. No root or component `AGENTS.md` was found. Contract ownership was agreed through Herdr before implementation: shared Rust/Swift/contracts/governance here; Android application, native sidecar and UI with the sibling.

## Implemented behavior

The authoritative Rust materializer now returns data-free `HeadingNotFound` (`headingNotFound`) when a required heading selector is absent. UniFFI appends variant 16, preserving the existing variant ordinals. Swift and Kotlin bindings were regenerated from the actual Rust library. Malformed UTF-8 remains a different error, fenced or wrong-level headings do not satisfy the selector, failed sessions become terminal, and no descriptor or prepared bytes escape the failure. [Service contract](../../Packages/contracts/core-api/v1/contract.md).

Android now exposes Create Heading, Use another heading, Send to Inbox, and Send to another route through explicit review and confirmation. A revision/request-hash-bound diagnostic is persisted only for the authoritative heading error. A durable replacement intent freezes a stable replacement identity, target and preserved source content before retiring the source through the existing fenced journal path. Crash recovery resumes the same decision; it never mutates or blindly resubmits a frozen request. Source assets and processing provenance remain retained. Committing/unknown writes, stale decisions, changed vaults/routes, missing permissions, ended access at admission, and auxiliary URL deliveries fail closed. Vault/route names and choices survive saved-state recreation; unavailable names disable Send. The composer draft is unchanged.

Two integration reviews added regressions: same-intent admission must re-sync an uncertain intent promotion before source retirement, and confirmation must retain the reviewed non-default source vault/route labels. The focused work also fixed uppercase `TOP` serialization where the decoder requires `top`. Numeric heading levels use selected chips and numeric labels. [Native protocol](../android/capture-recovery-sidecar.md) · [Android verification](android-explicit-recovery-2026-11-08.md).

Local source commits are `6b50da34` (shared diagnostic), `56f1eef6` (Swift consumer and strict receipt diagnostics), `cde724e2` (Android feature from `4377d800`), `5a4bd03d` (numeric chips from `0bf2759c`), and `352c7f65` (Android evidence from `65923ff5`). No commit from this continuation was published.

## Executed portable checks

| Check | Result |
| --- | --- |
| Rust workspace tests, pinned 1.97.1 | 52 passed: 27 core, 19 public integration, six UniFFI |
| Runtime crates at MSRV 1.87.0 | Same 52 tests passed |
| Rust clippy, all targets, `-D warnings` | Passed |
| Generated Swift/Kotlin binding drift and SwiftPM mirror | Byte-identical to regenerated bindings |
| Actual Swift consumer linked to host Rust | Three native sessions passed; missing-heading distinction and no prepared output |
| Focused Swift package tests | 45 passed: 17 document editor, 12 engine policy, 14 diarization-service tests, two shared scorers |
| Synthetic persistence producer/consumer fixture validation | Passed |
| Android affected host gate | 347 passed: domain 82, bridge 11, data 103, app 151; no failures/errors/skips |
| Final numeric-chip follow-up | 151 app tests, instrumentation compilation and lint passed |
| Android instrumentation | App and data Kotlin source compilation only; no execution |
| Android lint | Zero errors, 98 warnings, five hints |
| Localization audit tests | 13 passed |
| Worker-fence governance regression | Passed; deliberately rehashing a bypass does not evade rejection |
| Real local Apple instruction model | All six shared instruction cases passed |

Retained shared logs and real Apple model output are in [signal-local-recovery evidence](../../artifacts/validation/signal-local-recovery-2026-11-08/); Android logs, XML and exact final source hashes are in [Android evidence](../../artifacts/validation/android-explicit-recovery-2026-11-08/). The latter hashes were checked against the integrated source bytes. The model execution audit records the observed modified tree rather than claiming clean-source qualification.

Principal commands:

```sh
rustup run 1.97.1 cargo test --manifest-path Packages/vox-core-rust/Cargo.toml --offline --locked --workspace
rustup run 1.87.0 cargo test --manifest-path Packages/vox-core-rust/Cargo.toml --offline --locked -p vox-core -p vox-core-uniffi --target-dir /private/tmp/vox-heading-msrv
rustup run 1.97.1 cargo clippy --manifest-path Packages/vox-core-rust/Cargo.toml --offline --locked --workspace --all-targets -- -D warnings
CARGO_NET_OFFLINE=true bash Packages/vox-core-rust/scripts/check-bindings.sh
VOX_M2_ENABLE_NATIVE_HOST=1 swift run --package-path Packages/VoxboardShared --disable-sandbox --skip-update -Xlinker /private/tmp/vox-apple-signal3-20261108/Packages/vox-core-rust/target/debug/libvox_core_uniffi.a VoxboardM2MaterializationEvidence --verify-heading-not-found
swift test --package-path Packages/VoxboardShared --disable-sandbox --skip-update --filter 'MarkdownDocumentEditorTests|IntelligenceEvaluationTests|SpeakerDiarizationTests|CaptureCoreEnginePolicyTests'
swift run --package-path Packages/VoxboardShared --skip-build VoxboardPersistenceFixtures --validate
Packages/VoxboardShared/.build/debug/VoxboardIntelligenceEvaluation evaluations/local-intelligence/v1/corpus.json /private/tmp/vox-apple-instruction-local.json
python3 apps/android/scripts/validate-intelligence-evaluations.py --corpus-only
python3 apps/android/scripts/generate-runtime-localizations.py --check
python3 Packages/contracts/scripts/validate.py
python3 Packages/contracts/scripts/validate_toolchain.py
bash scripts/test-project-contracts.sh
```

The final contract suite passed 161 of 162 tests; its sole error is the preserved stale-model qualification failure. The complete result is retained in `final-contracts.log`. The script stops at that failure; its embedded final project-structure Python block is executed separately and recorded. A green scorer or corpus-only check is not inference qualification.

## Governance and localization

The final toolchain inventory binds 303 implementation paths, including the shared error producer, Swift host consumer, new Android transaction/diagnostic/UI sources and tests, and the native protocol document. The recovery lease gate accounts for six root-lock sites and separately requires the current-worker predicate around intent admission; a rehashed bypass regression preserves its semantic enforcement.

The regenerated Android lookup inventory contains 1,023 distinct UI phrases: 453 Apple-catalog, five aliases and 565 Android-catalog; 3,039 lookup-source literals; zero missing, incomplete, dynamic or fallback entries. Twenty-two new phrases have 22-locale agent-authored overrides. `humanApproved` remains false and `reviewStatus` remains `requires-human-review`. Coverage/format checks do not establish linguistic quality.

Contract resources are regenerated from the actual combined sources and must remain byte-identical in all four mirrors. Oracle regeneration used clean final combined source commit `94bba3958bcc9282f3454c441aa4b53889654d29`; check-mode verification passed. The tracked fixture and retained final oracle logs identify that source. Every case output is unchanged; provenance fields were compared separately. The first post-pin Rust check correctly rejected the old oracle toolchain hash (`final-rust-before-oracle.log`); the complete Rust suite then passed all 52 tests after oracle regeneration, with its final result retained in `final-rust.log`.

## Exact model qualification diagnosis

[Structured audit](../../artifacts/validation/signal-local-recovery-2026-11-08/qualification-drift.json) and [exact source diff](../../artifacts/validation/signal-local-recovery-2026-11-08/qualification-source-diff.patch) compare the retained receipt with its real source commit `68db4cb8e1cd90aee8657df95ad4716f84f49d2c` and the integrated source. Every recorded implementation hash matches that historical commit. Six evaluated inputs now differ: Rust core, `LocalSpeech.kt`, `CaptureRepository.kt`, `VoxApplication.kt`, `AndroidCaptureRepository.kt`, and the evaluation validator. The earlier speech change closes rejected imported streams; repository changes add validation, access/discard and now recovery behavior. The validator now names the exact mismatched files while preserving strict rejection.

All four declared Android model/fixture pins still match the receipt; actual installed Android model bytes were not inspected. The fresh Apple instruction subset passed six real FoundationModels cases on this Mac. Its system-managed model weight revision is not exposed by the API. Neither those results nor the scorer/unit tests renew the Android full-phone/model receipt.

The actual full qualification runner invokes `adb shell am instrument`, requires an explicitly selected emulator, executes mandatory speech inference and production delivery/retry assertions, and records a clean implementation commit. This task authorizes none of that device execution. The old receipt and strict failing check remain intact; no hashes, pass status, skips or historical results were repinned to imply a new run.

## Remaining limits and cleanup

Heading recovery and Inbox/other-route replacement now have local implementation and portable regression evidence. Actual Android filesystem/provider/keystore crash behavior, rendered UI/recreation, and full-model qualification remain runtime checks requiring separate authorization. Translation quality still needs human review. The historical Apple UI findings remain fixed and their original evidence is preserved; no new mobile UI QA was run.

No push, PR creation/update, remote branch mutation, hosted CI trigger, merge, upload, publication, store submission or production write occurred in this continuation. No simulator, emulator, Argent or physical-device QA ran. Build slots were coordinated and released through Herdr. Worktrees, local commits, compiler caches and background tabs remain open for review; no shared server, Metro or unrelated build was stopped.
