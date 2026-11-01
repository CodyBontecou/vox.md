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
- Delivery proof and repeated compaction produce one quota unit, one activity event,
  one completion/tombstone and no remaining reservation. Failed or uncertain attempts
  consume zero committed quota units and preserve byte-identical prepared content.

## Executable coverage

`SafVaultCommitExecutorTest`: permission repair, delayed visibility, partial-byte
preservation and substituted-vault rejection, plus the existing executor taxonomy.

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

Full check results and clean-commit oracle provenance will be recorded after completion.
