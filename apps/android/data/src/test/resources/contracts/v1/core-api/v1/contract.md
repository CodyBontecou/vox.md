# Core API v1

This service contract is independently versioned from capture inputs, renderer/profile
revisions, artifact plans, persisted schemas, and wearable protocols. All records are
canonical UTF-8 JSON: lexicographically sorted object keys, two-space indentation, no
non-finite numbers or trailing spaces, and exactly one final LF. Every field is required;
explicit `null` represents supported absence; arrays are ordered and bounded; unknown
fields, enum values, profiles, operations, and versions fail closed.

M2 supports exactly operation `newNoteTextLink`, profile `apple-parity-v1`, core API 1,
contract versions 1, renderer `swift-legacy-m0`, and artifact plan 1. `buildInfo` is
informational. `expectedVersions` is an exact request, including the SHA-256 of the complete pinned
toolchain manifest consumed by the compiled core. A `readinessResult` is `ready`
only with an empty mismatch list and `sessionPermitted=true`; any mismatch returns
`incompatible`, safe bounded codes, and `sessionPermitted=false`.

`expectedArtifactDescriptors` is emitted only after sealed input and declares the exact
ordered output set before draining. `preparedChunkMetadata` binds one chunk to an
artifact/stream, zero-based contiguous sequence, bounded byte count (maximum 1 MiB and
never greater than the caller-supplied positive `maxBytes`), SHA-256, and EOF. `drainedArtifactHashes` contains exactly one ordered verified
length/hash per descriptor and is required before finalization can return an artifact
plan. These records carry no platform handles, bytes, side-effect receipts, or authority.

SHA-256 is lowercase hexadecimal over the named bytes. UUID identities use RFC 4122
UUIDv5/SHA-1 with namespace `8c7f8d7e-4f61-5d92-a94a-3b9e6cc8e415`, domain label,
NUL, and the exact canonical preimage defined by artifact-plan/v1. UUID strings are
lowercase hyphenated.

## Typed materialization failures

The owned-value UniFFI boundary appends `HeadingNotFound` after its existing error
variants, preserving their ordinal order. Its deterministic core code is
`headingNotFound`. This data-free failure is returned only after the authoritative
existing-note observation has been validated and a required `beneathHeading`
selector with `missingHeadingBehavior=fail` has no matching heading outside fenced
code. Both existing-note and rolling-note placement use this rule. Malformed UTF-8,
invalid control, failed stream verification, and unsupported selectors retain their
distinct failure categories. Create-if-missing and retry-marker idempotency are
unchanged.

The failing session becomes terminal without exposing an artifact descriptor,
prepared bytes, or an artifact plan. Error text contains no note content, heading,
path, URI, or request identity. Native recovery may derive selector context from the
immutable request, binding any durable diagnostic to that request's hash and journal
revision; the error never grants commit, replacement, or filesystem authority.
This adds no JSON field, operation, persisted journal event, or schema version. A
consumer that cannot recognize a boundary error must continue to fail closed.
