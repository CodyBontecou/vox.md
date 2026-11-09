# Android explicit capture replacement

This native-only protocol supplements the immutable capture package. It does not change public core JSON or delivery-journal schemas. A replacement is new, explicit delivery authority, never an edit to a queued request and never proof that anything was delivered.

## Intent authority

`noBackupFilesDir/vox-capture-recoveries/<source-request-uuid>.json` is canonical JSON v1, capped at 1 MiB. It contains an intent/replacement UUID, original request UUID and SHA-256, reviewed journal revision/state, confirmation timestamp, exact choice, canonical replacement request, and its SHA-256. One immutable intent exists per source; replacement IDs are unique across intents and existing packages/tombstones. Unknown/corrupt intent versions fail closed. Temporary files use owned `.tmp-<uuid>` names and cannot authorize delivery.

The replacement preserves capture timestamp, source, locale/timezone/calendar, payload identities and contents, invocation/recording/location provenance, pins, metadata policy, attachment folder and entry formatting. It changes only request identity, explicit note route/destination and, for heading repair, the chosen selector/create behavior. Route selection validates enabled status, exact reviewed revision and destination ID. URL-enabled target routes are unavailable in this note-only recovery. Processing and location collection are not rerun; no new URL delivery is admitted. The confirmation says that saved content/formatting are kept.

## Ordering and crash recovery

1. Review a context bound to request SHA-256 and journal revision. Keep the intent UUID and selected route revision/vault across saved-state recreation. Cancel and heading edits invoke no repository operation.
2. Require current access policy, a valid selected route and exact vault ID, and a currently valid SAF grant. Freeze an immutable capability binding before recording the intent. Access is checked again during fenced intent admission.
3. Acquire the source worker lease. Under the package root lock, validate the fence, exact source hash/revision/state and all package/asset hashes. Refuse committing/unknown frontiers, active commit markers, permission recovery resuming a committing write, or an independent non-discarded URL delivery.
4. Write the full intent to a new temporary file, flush/fsync, reopen/verify, atomically promote without replacement, and fsync its parent. Same-intent admission and replay re-sync an existing promoted intent before proceeding. Identity/choice/source conflicts never overwrite it.
5. Append the exact frozen `USER_DISCARDED` source event using the existing fenced revision-CAS journal path. A retry must match that exact event and directory-sync before acknowledging retirement. Pre-commit retirement does not delete source content. `pruneCompletedPackage` refuses the discarded source, preserving source assets and processing audit even after replacement completion.
6. Only after durable retirement, enqueue the exact replacement UUID/request and verified original assets using the ordinary durable-package API. Reopen/index failures retain the intent. Restart between retirement and enqueue replays the same bytes/UUID; existing identical packages reuse them. A completion tombstone prevents recreation/redelivery after replacement compaction.
7. Release only the retired source's outstanding quota reservation and drive the ordinary pinned-vault delivery path. Reconciliation replays intents before normal pending drains. Retry of an original follows its recorded replacement; the worker rechecks for an intent after acquiring its lease to close the admission/worker race. A revoked grant yields ordinary permission recovery, never an alternative vault.

An intent admitted before access ends is already-authorized durable work and can finish like other queued deliveries. New intent admission after access ends is rejected. No late UI callback can rebind an existing decision to another route, journal frontier or vault. An admitted decision is not canceled by dismissing its UI; replay completes it. UI success requires a real ordinary delivery result; otherwise it says recovery/delivery is waiting.

## Truthful missing-heading context

The shared Rust/UniFFI `HeadingNotFound` error is data-free and distinct from malformed UTF-8, invalid observations and generic failures. Android maps only this authoritative seal failure to a typed result. Before appending `USER_ACTION_REQUIRED`, the lease holder persists `noBackupFilesDir/vox-heading-failures/<request-uuid>.json`, binding selector, request SHA-256 and preparing revision. Repair controls require both that record and its exact next user-action journal frontier. Coarse failures, stale diagnostics, changed selectors, or another revision cannot create a heading-repair UI.

"Create Heading" freezes the original missing selector with create-if-missing. "Use another heading" uses the reviewed title/level with fail-if-missing. Both create an explicit replacement through the same transaction, leave the saved route unchanged, and never fall back to append when the selector is absent. Route log links the original and replacement, and replacement detail retains access to the original processing audit.

## Verification boundary

Portable tests execute the production intent store, package journal, fence coordinator, replacement driver, request cloning, diagnostic binding and the exact saved-state form. Faults cover intent promotion/resync, before/after source journal rename/fsync, source retirement before replacement enqueue, and enqueue result loss. Tests retain original request/assets/prepared bytes, reject asset corruption and duplicate intent identities, exercise real persisted ambiguous/permission journal states, validate stale/disabled/deleted/URL routes and changed vaults, and round-trip/cancel/stale confirmation state.

These host tests use JVM file/lease fakes. Android fsync/provider/keystore behavior and rendered UI remain runtime qualification gaps. No simulator/emulator/physical-device QA or model requalification is implied. Historical model qualification remains source-stale and must not be repinned as fresh execution.
