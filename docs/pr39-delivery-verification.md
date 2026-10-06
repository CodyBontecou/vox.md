# PR #39 follow-up verification

Worktree: `vox.md-pr39`; branch: `fix/pr39-delivery-recovery`, based on
`e36286218bc2dbaf5a3c4b7f64b2e21cf339c963`. Contributor PR #35's ancestry is
preserved. Delivery remains additive and disabled by default. No PR merge,
issue closure, startup URL-journal drain or alternative-output mode.

## Automated evidence

- Full `VoxboardShared` package suite: **1,014 passed**.
- Focused `URLDelivery|TranscriptURLDeliverer` package suite: **74 passed**.
- Full `VoxboardTests` app-hosted suite: **249 passed** on the dedicated iPhone
  17 Pro / iOS 26.5 simulator, using Xcode 26.6.
- iOS app build and Mac app build: **succeeded**, unsigned Debug configurations.
- `scripts/test-project-contracts.sh`: passes, including 26 script tests and
  131 portable contract tests. The recording-only settings assertion now
  includes the shared URL section, and the governed manifest was regenerated.
- Featureset inventory validator: passes, 338 features. URL delivery remains
  `planned`, not a shipped/release-ready claim.

HTTP regressions use intercepted transport, synthetic payloads and injected
credentials. Added red/green coverage proves 401/403 recovery, new credentials
for an originally anonymous request, immutable replay, durable no-HTTP handoff,
source/lease cancellation, discard/no resurrection, and local-sink handoff
retention while another actor owns HTTP backoff. Legacy display metadata strips
credentials/path/query/fragment and rejects empty/malformed/non-HTTP origins.

Composer-hosted tests verify draft-only recording makes no HTTP handoff, local
completion during HTTP backoff, preparation failure before note mutation,
processed-text/settings snapshots, and cancellation before delivery. Portable
source assertions are wiring checks, not runtime or real-Keychain evidence.

## Simulator UI evidence

Dedicated simulator: `Vox PR39 Recovery QA`,
`4E98C066-B344-4D73-AE25-CD8EB59A83BB`. No physical device was targeted.

Manually verified empty, pending, authentication and unknown-outcome recovery;
HTTP-only retry confirmation/cancel; destructive discard and body removal;
origin-only tombstone; light/dark appearance; Dynamic Type wrapping; off-by-
default editor, local-HTTP warning, and invalid URL save feedback. Retry now
opens a large, inline-title sheet with capture identity and deduplication warning
visible. Row actions have 44-point minimum targets and preserve child
accessibility identifiers. URL validation feedback is beside Save URL.

Synthetic fixtures intentionally included private-content/path/query/error
markers. None appeared in the checked recovery/retry AX trees. Discard removed
only the synthetic prepared body and left a sanitized tombstone. No UI Send Now,
Send Test or Retry confirmation was pressed; UI HTTP was not intercepted.
Actual HTTP execution was verified only in the mocked runtime tests above.

The unsigned simulator reports unavailable App Group capture storage. It can
exercise settings/recovery via the private Application Support journal fallback,
but cannot establish a real recording/vault/Keychain end-to-end claim.

Argent stays at **0.25.0**. Live AX and native-runner trees disagree on some
SwiftUI controls. Recorded walks therefore include geometry fallbacks and
cross-tree warnings; they are **manual diagnostic evidence, not validated
portable regression flows**. No consecutive replay-pass claim. The recordings
are 30fps and do not establish sustained 60fps or minimum-device performance.
An optional 0.27.0 update was not performed and requires informed user consent.

## Evidence and release boundary

Local logs, raw flow diagnostics, screenshots and recordings are retained under
`/private/tmp/vox-pr39-evidence/` (outside the repository). Important artifacts:
`artifacts/package-full.log`, `url-final.log`, `ios-full-tests.log`,
`mac-build.log`, `contracts.log`, `inventory.log`, `url-final-walk.mp4`,
`url-retry-final.png`, `url-dark.png`, `url-editor-validation-final.png`.
These local temporary artifacts are not a hosted CI attestation.

PR #39 must remain draft. Real Keychain entitlements/lock/account cleanup,
ATS/local-network behavior, crash/termination boundaries, signed Mac behavior,
full recording/draft/Send device coverage and release performance remain gates.
Retention/pruning, legacy host-account cleanup and any URL-instead-of-directory
product change remain separate decisions. See [delivery scope](issue-32-url-delivery.md).
