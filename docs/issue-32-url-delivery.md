# Issue #32: URL delivery review notes

This draft builds on contributor PR #35. It is not a release-readiness claim.

## Destination semantics

Delivery remains **additive**, disabled by default: an enabled preset POSTs JSON
in addition to its existing destinations. An HTTP failure does not undo a
successful local transcript or note. The owner's suggestion of URL + bearer
*instead of* a directory remains a separate product decision; typed Capture
still requires a working Markdown destination. The inherited
`deliverOnFailureFallbackFile` field is decode compatibility only, not a fallback
mode.

Vox.md ships no endpoint and performs no HTTP startup drain. Draft recording
completion never enters URL delivery. Explicit composer Send freezes the exact
processed request and the submitted preset's endpoint before asynchronous
processing. Images, audio and other attachment bytes are not uploaded.

## Credentials and validation

- Tokens and all custom header values are Keychain-only. Presets, queued
  requests, receipts and logs contain account references/presence flags, not
  authentication values.
- Each preset's opaque UUID account is bound to an exact validated URL. Missing,
  locked, corrupt or mismatched accounts fail closed; a failed lookup never
  clears authentication flags or silently sends anonymously.
- iOS and Mac use the same explicit Save URL / Save Token / Save Headers / Send
  Test controls. Invalid and case-insensitively duplicate headers are rejected.
  Host, cookies and hop-by-hop headers are forbidden; JSON and idempotency
  headers remain app-owned. Static header values are not automatic HMAC signing.
- Preset deletion removes its referenced Keychain account before retirement. A
  cleanup error leaves the preset intact and presents an error. Pending HTTP
  payloads remain available for deliberate recovery/discard, not automatic
  sending. Deletion cannot recall a request already received by an endpoint.
- Changing an authenticated endpoint requires explicitly removing/re-entering
  credentials. Credentials are re-read between attempts; removal or replacement
  during backoff cannot reuse a copied token.
- HTTPS is the default. Local HTTP requires a separate warning/opt-in; it sends
  text and credentials without encryption. `.local` or a private IP is not proof
  that a network is trusted. Both apps declare a local-network purpose and only
  the local ATS allowance (`NSAllowsLocalNetworking`); public HTTP stays rejected
  by validation. Real local-network permission prompts still require device
  verification. See [Apple's local-network guidance](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy).
- URL user/password and secret-looking query names are rejected. Query detection
  is best-effort: do not put secrets in a URL path or query. Receipts and recovery
  UI show the origin only, never the path/query or raw transport errors.
- All redirects are refused, including same-origin and HTTPS downgrades. The
  production session has no cookie jar, URL credential storage or response
  cache. Response bodies are not buffered without a bound.

PR #35's legacy plaintext preset headers are discarded on decode. Credential-
bearing legacy settings require explicit migration, never host-scoped token
reuse or anonymous fallback. Explicit Remove Saved Credentials or preset deletion
removes the exact old host account for a legacy bearer-token preset; modern
accounts and unrelated hosts are untouched. Migration blocks endpoint edits until
cleanup, so the original host reference is retained. Keychain errors keep the
preset and its migration flags intact.

Validated job, bundle-intent and handoff snapshots atomically redact legacy
headers on read. Redaction retains capture identity, phase and unknown metadata,
marks reauthorization required, and applies private file permissions. Malformed
or future-schema archives are preserved without rewriting; arbitrary files are
never swept. A failed job-redaction write blocks processing rather than silently
leaving authentication values on disk.

## Durable handoff and task ownership

`enqueueCapture` / `enqueueTranscript` verify and atomically persist the prepared
body, digest, exact endpoint, settings references and a receipt **without a
Keychain lookup or HTTP request**. The composer does this inside explicit Send,
before the note mutation. Preparation failure preserves the draft/recording job
for recovery rather than completing and losing the HTTP intent.

Only a successful durable enqueue is dispatched to `URLDeliveryCoordinator`.
The iOS recorder has no nested detached HTTP task. Composer completion and Mac
note export do not await endpoint retry latency. The task registry coalesces
identities and owns cancellation. On iOS an exactly-once finite background lease
cancels its sender on expiry; an unavailable lease leaves the unattempted handoff
locally inspectable. This is not a background `URLSession` transfer.

`URLDeliveryCancellation` bridges source cancellation, including cancellation
before an asynchronous task factory/HTTP registration. Cancellation while the
source is performing local delivery/handoff cancels that task and HTTP backoff.
Normal local completion transfers HTTP ownership without canceling it.
Explicit Cancel Send and Discard use the same registry. Discard cancels and
awaits the sender before removing the body and retaining a content-free
anti-replay tombstone. A failed payload cleanup remains visible for another
Discard attempt.

An advisory file lock excludes overlapping sends/discards across actor
instances. Existing failed/ambiguous HTTP work is retained, not automatically
reset/reposted by a note/audio retry. A verified delivered tombstone suppresses
another POST; successful delivery removes its separate prepared body. Corrupt
or unproven legacy state fails closed.

## HTTP-only recovery

Open **Settings → URL Deliveries** on iOS, or **Capture Presets → Deliver to URL →
URL Deliveries** on Mac. Merely opening or refreshing recovery never sends.
Unattempted payloads offer Send Now; attempted/authentication/permanent failures
require deliberate Retry. Discard removes local HTTP content without changing
notes, audio or an endpoint's existing copy.

401/403 stop the automatic attempt window and remain recoverable. Retry can use
the original saved account after correcting it, or explicitly select a current
preset's credentials for the **exact same endpoint**. This also recovers an
original anonymous 401 or a replaced account. Only credential references/flags
may change; body, endpoint, capture identity and Idempotency-Key stay frozen. A
missing/locked/wrong-endpoint replacement does not modify the journal or POST.

Each attempt uses the same lowercase UUID `Idempotency-Key`. The receiver must
implement deduplication: the header alone cannot guarantee exactly once after a
server commit followed by timeout, process death or local receipt failure. The
journal records `unknownOutcome` before HTTP, and Retry warns that the endpoint
may already have received the capture.

2xx succeeds; 408/429 and 5xx retry. Other statuses, redirects and permanent
TLS/URL errors stop automatic retry but can be retried deliberately after fixing
the cause. Attempt windows are clamped to 1–5, with bounded backoff/jitter and a
seconds-only Retry-After capped at 300 seconds. Individual requests time out at
30 seconds. Cancellation stops subsequent attempts and preserves recovery
state; it cannot undo a committed remote request.

`outstandingReceipts()` includes permanent/authentication failures. Delivered
and fully discarded tombstones are hidden from recovery. Records currently have
no automatic pruning policy, and outstanding bodies remain stored until success
or explicit discard.

## Verification and remaining gates

Synthetic package regressions cover authorization recovery (401 and 403),
anonymous reauthorization, immutable endpoint/body/identity, durable no-HTTP
handoff, restart recovery, source/lease cancellation and discard. App-hosted
composer tests cover draft-before-Send, slow HTTP versus local completion,
preparation failure, processed/settings snapshots and cancellation. Portable
source checks protect both host hooks, credential cleanup ordering and shared
controls. These are not substitutes for device evidence.

Still required before release:

- Agree additive versus alternative destination semantics and release scope.
- Real Keychain entitlements, lock/unlock, account replacement/deletion, local-
  network/ATS and termination/crash-boundary acceptance on appropriate hardware.
- Full real recording/draft/Send and HTTP-only recovery device matrix, including
  iOS background limits and Mac signing/sandbox behavior.
- Lowest-supported-device/release-build motion/performance evidence; simulator
  screenshots or a 30fps recording do not prove sustained 60fps.
- A retention/pruning decision. Pending payloads currently remain until success
  or explicit Discard; content-free anti-replay tombstones are retained indefinitely
  to prevent duplicate POSTs from old recording/note retries.

No PR is merged, issue closed or endpoint/credential/vault content taken from a
real user for these tests. Mocked transports/Security clients and synthetic local fixtures do not validate
production credentials or physical-device behavior. App-hosted tests additionally
exercise native Security.framework save/read/replace/delete with a fresh synthetic
UUID account and production URLSession delivery to an in-process loopback listener.
The simulator host is ad hoc signed because an unsigned host cannot access its
Keychain identity; CI uses the same signing mode, without certificates or profiles.
