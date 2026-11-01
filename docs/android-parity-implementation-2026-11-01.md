# Android parity implementation — 2026-11-01

Scope: the four high-priority capture gaps identified against iOS at `304fcb6`.

| Capability | Implementation | Verification status |
|---|---|---|
| `cap.delivery.url` | Explicit HTTPS opt-in, bearer/custom headers, Keystore AES-GCM secrets, durable independent outbox, frozen credentials/endpoint, same-endpoint credential repair, stable idempotency key, redirect refusal, content-free receipts, explicit retry/discard and ambiguous-outcome warning | Implemented; production endpoint/account and device fault qualification pending |
| `cap.destination.preset-vault` | Independent SAF tree per preset; legacy presets use default destination; new captures bind an opaque native capability before enqueue; pending captures do not follow later global/preset edits | Implemented; provider/revoked-grant device qualification pending |
| `cap.route.invocation-override` | Current-draft note path and prepend/append override, persisted across relaunch, validated relative paths, reset on successful durable enqueue; presets remain unchanged | Implemented; device UI/relaunch qualification pending |
| `cap.metadata.transcript-property` | Voice-only named property, optional transcript body, JSON-quoted YAML string, replacement of prior scalar/multiline values without changing other properties/body, frozen before shared materialization | Implemented; renderer regression coverage; full device delivery qualification pending |

## Behavioral boundaries

- URL delivery is a separate sink. Its encrypted body and frozen credentials are staged before local capture admission. A worker sends only after durable local admission and quota reservation; note delivery and URL outcomes recover independently.
- A send is marked `SENDING` before network I/O. After process interruption it becomes `UNKNOWN`, requiring explicit user retry; no blind automatic replay. All retries retain the same idempotency key. Servers must honor that key to guarantee deduplication.
- This implementation accepts HTTPS endpoints without query strings. API secrets belong in the bearer token or custom headers. iOS's explicitly approved local cleartext HTTP option is not implemented; this row must not be promoted to full parity while that difference remains unapproved.
- Endpoints and headers are immutable encrypted credential records. Editing a preset creates a new record; pending deliveries retain the prior record. Captured audio/files are never uploaded.
- Native vault bindings remain outside Rust JSON. Only the opaque vault ID is hash-bound in `destinationPolicy.capabilityReference`. Historical requests using `synthetic-vault-capability` retain their legacy default-destination behavior.
- Existing-note property mutation uses the existing hash-observation/readback/ambiguous-commit safeguards. Dictated text is data, including embedded YAML delimiters and quotes.
- The optional `metadataPolicy.transcriptProperty` contract preserves old JSON bytes when absent and requires the updated Rust runtime when present. Android native libraries must be rebuilt from source.

## Validation

Validation results are recorded here as checks complete. New rows remain `implemented`, with device acceptance `planned`, until retained device/provider evidence justifies `verified`.

### Checks completed

- The full Android CI command passes: `check assembleDebugAndroidTest :app:validateDebugArtifacts :wear:validateWearDebugArtifacts releaseReadiness`. This includes 248 JVM tests (app 65, data 75, capture-domain 59, platform-services 38, core-bridge 11), lint, four-ABI native builds, phone/Wear debug artifacts, optimized release bundles, SBOM and visual-evidence integrity checks.
- Seven focused API 36 emulator tests passed: real native-core preset-vault/property delivery and draft override persistence/reset; route and property Compose controls; encrypted URL body/credentials, admission gating, frozen endpoint, redirects, unknown outcomes, stable retry key, and same-endpoint credential repair. URL transport tests use an injected connection, never a live customer endpoint.
- `cargo test --workspace --locked` now passes all 48 Rust tests, including the formerly blocked Swift-oracle test. `cargo fmt --all -- --check`, strict Clippy (`--workspace --all-targets --locked -- -D warnings`), and byte-identical Swift/Kotlin binding regeneration pass.
- The full project contract gate passes: 65 script tests, 136 contract/governance tests, M0 ledger validation, contract mirrors, deterministic ledger conversion, 187 implementation hashes and project structural checks. Runtime localization freshness, featureset coverage and `git diff --check` pass.
- The complete routine phone instrumentation run passes on fresh `vox-parity-checks-api36-20261101` (API 36): 71 discovered, 67 passed, four existing model-qualification cases assumption-skipped because their separately staged fixtures were absent, zero failures. The skipped cases are real offline model transcription, frozen-Wear real-speech routing, requested-model offline transcription, and requested-model download/install qualification. The seven new parity tests all execute and pass. The earlier shared AVD became unresponsive; the fresh Vox-only AVD completed the run in 120 seconds.
- The full Swift package suite passes: 655 shared XCTest cases, 381 capture-core XCTest cases and 10 Swift Testing cases. On this Mac, run with `VOXBOARD_SHARED_CONTAINER_OVERRIDE=/tmp/vox-shared-clean-tests swift test --package-path Packages/VoxboardShared` so tests use writable isolated storage instead of the unavailable normal App Group lock location. The isolated preset repro fails without this override and passes with it; no production persistence behavior was changed.
- The legacy M0 validator now accepts `implemented` rows with planned acceptance. Three regression tests preserve the rule that only fully verified acceptance may support `verified` capability status.

### Clean-commit oracle provenance

Implementation commit: `0e9a46e`. Ledger-validator follow-up and oracle source revision: `9d514438ed40df9e123777ed410201e83a2fb945`. The existing generator produced the candidate outside the repository, and fixture commit `964c79a` records it. All 14 cases are byte-for-byte unchanged; only source revision and toolchain-manifest hash changed. The clean-tree generator check reproduces the committed fixture successfully.

Physical providers, process-kill campaigns, visual approval and live endpoints remain release qualification.

New strings remain explicitly listed in the Android localization review inventory; no translation approval is claimed.
