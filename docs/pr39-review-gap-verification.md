# PR39 review-gap fixes

Scope: three correctness findings on `feat/pr39-exclusive-capture-target` at
`6ebef28`. Implemented and app-verified in an isolated worktree; only the 11
owned files were applied to `.derived/pr39-iphone-source-099fbfa`. Recording retry/stitch work, `main`, real recordings,
credentials, physical devices and production HTTP endpoints are outside this
pass. No commit, merge or push is part of this pass.

## Behavior and lasting regressions

- **Edited drafts after partial HTTP handoff.** Composer Send requires the exact
  saved payload before clearing a draft. An unchanged retry can finish allowance
  accounting after an earlier failure. Changed text stays in the persisted draft
  with an error; it cannot overwrite or be acknowledged by the original frozen
  request. New receipts retain a payload fingerprint after successful body
  removal. Legacy pending bodies can prove a match; body-free legacy tombstones
  without that proof fail closed. Active senders enforce the same check. Recorder
  retries keep their existing immutable-handoff behavior.
  Tests: `VoxboardTests/CaptureURLDeliveryIntegrationTests.swift` and
  `Packages/VoxboardShared/Tests/VoxboardSharedTests/URLDeliveryHandoffTests.swift`.
- **Shortcut target exclusivity.** Capture Text, Link and File Shortcuts reject
  HTTP presets before resolving their inactive directory or staging a file.
  Explicit presets, selected defaults and legacy directory overrides cannot
  bypass the guard. The error directs users to Open Quick Capture and explicit
  Send, or to a Directory preset. Direct HTTP execution from these Shortcuts is
  not implemented. Directory enqueue and inbox delivery remain supported.
  Tests: `VoxboardTests/CaptureIntentTargetTests.swift`.
- **Delivered-body recovery.** A delivered receipt whose payload remains appears
  in URL Deliveries as **Delivered · Cleanup Required**, with **Clean Up** rather
  than Retry/Discard. Cleanup uses the delivery lock, removes only that local
  payload and keeps the delivered anti-replay tombstone. Removal failures stay
  visible and can be retried. Cleanup does not read credentials, acquire an HTTP
  execution lease or POST; it refuses undelivered payloads.
  Tests: `Packages/VoxboardShared/Tests/VoxboardSharedTests/URLDeliveryCleanupTests.swift`.

Each original regression was reproduced before its fix. Temporary copied app
sources/probes were removed from the shared package before the clean full run.

## Verification

- Isolated fix checkout: **1,025 XCTest tests + 10 Swift Testing tests**, no failures.
- After integration, the feature-worktree shared suite (including the preserved
  recording retry/stitch work) passed **1,046 XCTest tests + 10 Swift Testing
  tests** with a separate scratch build directory. The app builds/hosted tests
  and contract/structure gates below used the isolated fix checkout.
- Final iOS hosted run: **36 tests** (16 composer handoff, 5 Shortcut target and
  all 15 `QuickCaptureRenderingTests`), no failures.
- Unsigned macOS app build: **BUILD SUCCEEDED**.
- Project contracts: **29 script tests + 131 contract tests**, passed.
- Capture structure gate: **14 positive/negative fixtures**, passed.
- `git diff --check`: passed.

Commands run from the checkout:

```sh
swift test --package-path Packages/VoxboardShared
scripts/test-project-contracts.sh
scripts/test-capture-view-structure.sh
# Dedicated iOS 26.5 simulator; external derived data/result bundle paths.
xcodebuild test -project Voxboard.xcodeproj -scheme VoxboardTests \
  -destination 'platform=iOS Simulator,id=32C91ABF-536E-435F-9E86-99C9DD0DA848' \
  -derivedDataPath /tmp/vox-pr39-review.s9XeBw-xcode \
  -resultBundlePath /tmp/vox-pr39-review.s9XeBw-ios-final-v2.xcresult \
  -only-testing:VoxboardTests/CaptureURLDeliveryIntegrationTests \
  -only-testing:VoxboardTests/CaptureIntentTargetTests \
  -only-testing:VoxboardTests/QuickCaptureRenderingTests \
  -parallel-testing-enabled NO -jobs 4 CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Voxboard.xcodeproj -scheme 'Voxboard Mac' \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/vox-pr39-review.s9XeBw-mac \
  -jobs 4 CODE_SIGNING_ALLOWED=NO
```

## Simulator UI acceptance

On the dedicated **Vox PR39 Review Fixes QA** simulator, seeded only a synthetic
HTTP-origin delivered receipt/body pair in the unsigned app's private fallback
journal. Capture → Settings → URL Deliveries showed the delivered cleanup status
and **Clean Up** only. Tapping it showed **No Pending Deliveries**; filesystem
checks confirmed body removal and retention of the delivered tombstone. Before
and after screenshots were visually inspected for readable text, clipping and
hit targets. The untrimmed screen recording and a complete fragment replay were
also saved. Service tests separately prove no repost, including cleanup failure
and explicit HTTP retry after cleanup.

Local evidence uses the `/tmp/vox-pr39-review.s9XeBw` prefix: `-fix-*.log`,
`-ios-final-v2.xcresult`, `-ui-delivered-{before,after}.png`, `-ui-cleanup.mp4` and
`-ui-cleanup-replay.json`. The replay fragment is under
`/tmp/vox-pr39-review.s9XeBw-ui/.argent/flows/` and is **not** a portable QA gate:
Argent's native flow projection omitted these SwiftUI controls despite exposing
them to accessibility discovery. Native ID/label lookups and scratch selector
assertions failed against a working connection. The fragment therefore retains
three discovered points (Settings `0.184,0.8635`, URL Deliveries `0.5,0.7415`,
Clean Up `0.167,0.626`) with raw accessibility outcome checks and idle gates.
Its uninterrupted replay passed without readiness warnings.

No physical-device, App Group entitlement or background-lifetime acceptance is
claimed. Simulator UI acceptance does not replace those release checks.
