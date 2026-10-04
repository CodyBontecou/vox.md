# Issue #32: URL delivery review notes

This branch builds on contributor PR #35. It is not a release-readiness claim.

## Destination semantics

The contributor implementation is **additive**: an enabled preset POSTs JSON in
addition to its existing destinations. A failed HTTP request does not undo a
successful local transcript/note. The issue owner's comment suggested URL +
bearer token *instead of* a directory; choosing and implementing an alternative
output mode remains a coordinated product decision. The inherited
`deliverOnFailureFallbackFile` field is retained for decode compatibility, but
has no behavior and must not be advertised as a fallback mode.

URL delivery is disabled by default, including presets written before the URL
field existed. There is no shipped endpoint or startup drain. Completing a
recording into a draft must not call the deliverer. The composer calls it only
inside explicit Send, with the exact processed request and URL settings captured
before asynchronous processing. Image/audio attachments are not uploaded.

## Credentials and validation

- Bearer tokens and **all** custom header values are saved in the Keychain, not
  preset JSON, UserDefaults, prepared requests, receipts, or diagnostic logs.
- Keychain accounts are opaque UUIDs allocated per preset, bound to an exact
  validated endpoint, not merely a shared host. The transport checks the
  Keychain record's endpoint as well as the preset reference.
- Missing, locked, corrupt, or denied credentials fail visibly before a request.
  Auth flags are not cleared just because a Keychain lookup failed.
- The editor uses explicit Save URL / Save Token / Save Headers actions. Invalid
  headers are not silently ignored; case-insensitive duplicate names, controls,
  and unsafe Host/cookie/hop-by-hop headers are rejected. Protocol JSON and
  idempotency headers remain app-owned.
- Changing an authenticated endpoint requires removing saved credentials and
  saving credentials for the new endpoint. Credentials are rechecked between
  attempts: removal/replacement during backoff cannot reuse a copied token.
- HTTPS is the default. HTTP requires a separate explicit local-only opt-in;
  host classification rejects malformed IPv4 literals. Hostnames such as
  `.local` are not a guarantee of a trusted network. Do not enable HTTP on an
  untrusted network: both text and credentials would be plaintext.
- URL user/password and secret-looking query names are rejected. Query-secret
  detection is best-effort; never put an authentication secret in a URL path or
  query. Receipt URLs contain only the origin, not the path/query.
- All redirects (including same-origin, cross-origin, and HTTPS downgrades) are
  refused. Configure the final endpoint URL instead. The production session has
  no cookie jar, URL credential storage, or response cache. Only response status
  is consumed; response bodies are not buffered without a size bound.

PR #35's legacy plaintext headers are discarded on decode and removed from
UserDefaults on a persisting preset load. Legacy credential-bearing settings
require explicit removal/re-entry, never anonymous fallback or automatic reuse
of a host-scoped token. Existing old host-scoped Keychain items are not read;
coordinated cleanup of those items and credential cleanup on preset deletion are
remaining integration seams. Existing legacy queued files are not rewritten
indiscriminately by this lane.

## Delivery state and retry

The request body remains the contributor's JSON export rendering for voice and
`{id,text,source,recorded_at}` for other text-bearing captures. A synthetic Send
Test has fixed test text, `test: true`, and a fresh identity each time.

Before the first HTTP side effect the actor writes an immutable prepared body,
URL, settings references, and digest, plus a privacy-limited receipt. Writes are
atomic with private permissions; a storage failure prevents the first request.
An advisory file lock excludes overlapping senders for the same identity, even
across actor instances. A verified delivered tombstone suppresses another POST
on recording/file-sink replay. Corrupt or legacy unproven receipts fail closed.
Successful delivery removes the separate prepared body.

Each request uses the same lowercase UUID `Idempotency-Key`. Receivers must
implement deduplication for that key: the header alone cannot promise exactly
once when a server commits just before a timeout/process death/local receipt
failure. The journal marks an in-flight request `unknownOutcome` before sending;
a missing terminal receipt cannot claim success or silently auto-replay it.

2xx is delivered; 408/429 and 5xx retry. Other statuses, redirects, and permanent
TLS/URL transport errors fail without automatic retry. Attempts are clamped to
1–5 per attempt window; backoff is 1/4/15/60 seconds plus bounded jitter, and
finite seconds-only Retry-After is capped at 300 seconds. Each attempt has a
30-second timeout. Cancellation stops further attempts, including during
backoff. Raw transport error strings are never logged or stored.

`pendingReceipts()` reports pending/retryable/ambiguous deliveries, not successful
or permanent ones. `retryPendingDelivery(id:)` is an **explicit HTTP-only retry**:
it loads the frozen prepared body/settings and grants another bounded window;
it never renders a fresh draft, reads a mutable preset, or reruns note writes.
No background drain or user-facing pending-delivery/retry UI is wired yet.
Failures stay locally inspectable. Durable delivered/failed records currently
have no automatic pruning policy.

## Remaining integration and verification gates

- Product decision: additive vs alternative destination.
- Delete a preset's Keychain account with visible failure handling before
  retiring/removing it; the outer list deletion UI is outside this lane's
  URL-section ownership. Coordinate legacy host-account cleanup too.
- Replace the reserved iOS recorder's nested detached URL task with a durable,
  cancellation-owned handoff. The hardened transport protects once invoked,
  not before a detached child has started. The Mac URL hook is awaited, which
  can delay queue finalization/note export while its bounded HTTP attempts run.
  Existing outer detached recording delivery still needs coordinated parent
  cancellation handling; package cancellation tests do not prove host wiring.
- Preserve explicit draft-vs-immediate guards when integrating issue #31. Do not
  pass a draft recording into a preset export/URL path. Exercise the full draft
  -> review -> Send workflow with synthetic inputs on a dedicated simulator,
  then the appropriate hardware matrix.
- Update the stale exact-string recording-only project contract to include the
  inherited URL section inside its existing transcript-workflow guard.
- Native Keychain entitlements/accessibility/locked-device behavior, app-hosted
  integration tests, iOS CI, and physical-device behavior are unverified here.
  Settings layout/motion/light/dark/Dynamic Type screenshots are also a remaining
  gate, not implied by package tests or an unsigned simulator compile.

Package tests use synthetic JSON, mocked Keychain/Security failures, an injected
URLProtocol, and a loopback-only Network listener for real URLSession redirects.
No real endpoint, credential, vault content, or microphone recording is used.
