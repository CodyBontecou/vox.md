# Android capture recovery — November 1, 2026

Scope: regression coverage for durable capture delivery, persisted SAF grant revocation,
interrupted provider mutations and safe retries. This extends ADR-0019/0023 and the
November composer/preset work; it adds no new feature rows or verification promotions.

## Recovery guarantees

- A revoked persisted tree grant enters `NEEDS_PERMISSION` while retaining request,
  prepared plan/note, resume state and the original quota reservation. Repair explicitly
  reauthorizes the same tree. Restoring access resumes the frozen plan.
- Interruptions after document creation or successful write retain `COMMITTING` and an
  active marker. Fresh Room/store/coordinator instances recover after lease expiry.
  Exact readback completes without another create/write; empty/partial/inaccessible
  documents remain `UNKNOWN_OUTCOME` across repeated retries.
- An absent candidate after a possibly issued create is ambiguous, including delayed
  visibility. Recovery neither deletes nor overwrites a partial document and never
  rerenders or changes the candidate to work around uncertainty.
- Recovery rejects an active commit marker bound to a different destination or plan. A new JVM
  regression reproduced the former bug: identical content in another vault could be
  accepted as delivery. The marker binding is now checked before reconciliation I/O.
- A cleared prior-attempt marker remains valid through re-preparation and is replaced
  atomically by the next active marker. This fixes a second reproduced bug: a safely
  abandoned attempt could become stuck because preparation rejected its cleared marker.
- Re-materialization may reuse an existing immutable plan only after exact plan and
  note comparison against the new verified drain. Conflicting bytes remain rejected.
  This fixes the third reproduced blocker: identical plans previously failed promotion
  on retry merely because their immutable directory already existed.
- Delivery proof and repeated compaction produce one quota unit, one activity event,
  one completion/tombstone and no remaining reservation. Failed or uncertain attempts
  consume zero committed quota units and preserve byte-identical prepared content.

## Executable coverage

`SafVaultCommitExecutorTest`: permission repair, delayed visibility, partial-byte
preservation, cleared-marker retry and substituted-vault rejection, plus the existing executor taxonomy.

`SafVaultCommitExecutorInstrumentationTest`: eight campaigns through the real
`com.android.externalstorage.documents` provider and system tree picker:

1. Baseline enqueue/materialize/commit/readback/compaction.
2. Persisted grant revoked before commit, then explicit reauthorization.
3. Persisted grant revoked after write at an interruption boundary.
4. Interruption after full write and before receipt persistence.
5. Interruption after document creation, with an empty ambiguous document.
6. Partial write followed by repeated reconciliation without overwrite.
7. Unavailable readback followed by recovery when access returns.
8. Cleared non-commit proof, reopened Room/store, native re-materialization and fresh commit.

Faults are deterministic wrappers around the production SAF gateway. Grant checks,
provider writes, hashes, native Rust materialization, persisted packages, Room leases
and quota are real. Boundary interruptions abort the executor and reopen its durable
state; they do not claim an OS process-kill campaign. Partial/empty documents are
repaired explicitly by the test to model delayed provider completion, never by recovery.
Physical Drive/OneDrive, OEM behavior and actual OS process-kill campaigns remain open.

## Validation

Implementation commits: `5c462d2` and `0fa3677`. Oracle fixture commit: `7cf622c`.
The oracle was generated from clean source revision
`0fa367792afcef5800298e9bf6f5fa8d383e856c`; all 14 cases remain unchanged and the
clean-tree provenance/reproduction check passes.

- Full Android CI gate passed: `check assembleDebugAndroidTest
  :app:validateDebugArtifacts :wear:validateWearDebugArtifacts releaseReadiness`.
  This includes 263 JVM tests, lint, phone/Wear debug and optimized release artifacts,
  four-ABI native packaging, SBOM and readiness checks.
- Routine data instrumentation: 22 passed, zero failures (13 Room tests, one entry
  template test and all eight real-provider recovery campaigns).
- Reinstall qualification: two phases passed with a real package uninstall/reinstall
  between them, using `apps/android/scripts/validate-reinstall-quota.py` with explicit
  `ANDROID_HOME` and `ANDROID_SERIAL` targeting the dedicated test emulator.
- Phone instrumentation: 79 discovered, 75 passed, four existing model-fixture cases
  assumption-skipped, zero failures. The skipped inference/download cases require
  separately provisioned model fixtures and remain separate qualification gates.
- Rust: all 49 workspace tests passed (27 library, 18 contract/integration, four UniFFI),
  plus formatting, strict Clippy and byte-identical Swift/Kotlin binding checks.
- Swift: 655 shared XCTest tests, 381 capture-core XCTest tests and 10 Swift Testing
  tests passed with `VOXBOARD_SHARED_CONTAINER_OVERRIDE=/tmp/vox-shared-clean-tests`.
- Project contracts passed: 65 script tests, 136 contract tests, 281 capabilities,
  197 implementation hashes and four resource mirrors. Localization freshness,
  347-feature registry coverage and whitespace checks also pass.

All device checks used the dedicated API-36 `vox-parity-checks-api36-20261101` AVD.
Install BOTH matching phone app and test APKs, then clear only the test emulator's
`md.vox.android` sandbox before the phone run: the language test requires first-launch
state, and an emulator snapshot can retain an older test APK. Run routine data tests
with the CaptureDatabase, EntryTemplateRepository and SafVaultCommitExecutor classes;
the two ReinstallAdjustment methods must instead use their host qualification driver.

The ledger retains 281 capabilities: 262 verified, ten implemented, nine inventoried;
248 apply to Android/Wear (233 verified, ten implemented, five inventoried). This
change extends source/test evidence for preset vaults, staged captures, inbox recovery
and retry accounting. It does not promote physical/cloud-provider or OS process-kill
acceptance based on deterministic boundary-interruption tests.
