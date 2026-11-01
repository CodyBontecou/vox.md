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

- Android Debug Kotlin compilation and all 237 JVM tests passed: app 65, data 75, capture-domain 59, platform-services 38.
- Seven focused API 36 emulator tests passed: real native-core preset-vault/property delivery and draft override persistence/reset; route and property Compose controls; encrypted URL body/credentials, admission gating, frozen endpoint, redirects, unknown outcomes, stable retry key, and same-endpoint credential repair. URL transport tests use an injected connection, never a live customer endpoint.
- All 26 Rust library tests and 17 non-oracle integration tests pass, including multiline/quoted-key transcript property replacement and YAML-injection preservation. The full `cargo test -p vox-core` run has one remaining failure: `swift_oracle_corpus_matches_production_sessions_and_executes_negatives` rejects the stale toolchain-manifest provenance hash. The existing generator requires a clean source commit; the fixture and its guard were not weakened or relabeled.
- All 133 existing contract/governance tests and three new property-contract tests passed. Contract manifest/mirrors, deterministic ledger conversion, 187 implementation hashes, runtime localization freshness, featureset coverage, and `git diff --check` pass. Physical providers, process-kill campaigns, visual approval and live endpoints remain release qualification.

New strings remain explicitly listed in the Android localization review inventory; no translation approval is claimed.
