# Saved-capture location review on iOS

## Report and cause

Returning to Capture opened **Location Needed for Default** without a new Send action. The dialog was bound directly to `inboxLocationDecision != nil`, and its dismissal setter did nothing. Foreground/navigation refreshes discovered the same durable request and treated its existence as permission to present a modal again.

## Behavior

- Saved requests needing a location decision appear in a non-blocking review row above the composer (`capture_inbox_location_review`). Only tapping that row opens the choices.
- **Not Now** and backdrop dismissal close the choices without sending, discarding, changing the preset, or resolving the stored request. The row remains available after navigation and relaunch.
- **Send Without Location**, **Always Send Without Location for This Preset**, and **Cancel and Discard Capture** remain explicit actions. They use the request ID captured when the dialog opens; stale actions cannot target a different request.
- Refreshes keep the reviewed request pinned, suppress overlapping drains, and dismiss obsolete choices after external resolution. Resolving one request does not open a dialog for the next.
- Origin-time location outcomes remain frozen; recovery does not reacquire location. Immediate composer location confirmation is unchanged.

Presentation state lives separately from durable inbox work in `Voxboard App Shared/CaptureComposerViewModel.swift`. The iOS row and choices live in `Voxboard/Views/QuickCaptureView.swift`, retaining concrete `CaptureViewSection` boundaries. The row wraps at accessibility sizes; `QuickCaptureCanvas` clips the editor's placeholder to its allocated slot so it cannot overlap that row when the keyboard reduces available height. Not Now is first and has no cancel role because native popovers hide cancel-role actions.

## Verification (2026-10-06)

Evidence is under the main checkout's `.derived/pr39-location-checks/`:

- The original implementation failed the returning-to-Capture regression three times (`location-red-v3.log`).
- Final focused hosted run: **65 tests, zero failures** (`location-final-v5.log` and `.xcresult`). Seven new tests cover discovery/navigation, defer/relaunch, request pinning, explicit delivery, stale actions, external resolution, and concurrent refreshes.
- Final project contracts: **131 script tests**, passing (`contracts-final.log`), including Capture structure checks and 14 positive/negative checker fixtures.
- Final unsigned macOS build passed (`mac-build-final.log`); the hosted run also built the iOS Simulator app. `git diff --check` passed.
- Native isolated iPhone 17 Pro/iOS 26.5 walkthrough: explicit review → Not Now → Settings/back → Recent Captures/close. The row remained; choices did not reopen on return. Light/default rendering and dark/largest accessibility rendering were inspected. The final build's keyboard-visible row, choices with visible Not Now, and deferred state are saved as `final-large-*.png`.
- Synthetic pending request/payload and frozen unavailable-location outcome remained intact, with no consent override or destination write (`native-pending-check.json`).

The recorded YAML/video walkthroughs are **exploratory evidence, not a replay-verified portable regression**. Live AX checks passed, but native-runner projections omitted several SwiftUI IDs/text; traces retain raw waits/coordinate exceptions. No clean end-to-end replay or CI claim is made.

Initial QA did not install or behavior-test this fix on the physical iPhone. No real capture was sent/discarded, no app data was reset or uninstalled, and no commit or push was made. The earlier authorized stitch-feature phone installation predates this change.

## Authorized physical deployment (2026-10-06)

Following the user's explicit device-build request, the bundled `build-ios-device` helper built this feature worktree with normal Apple Development signing, installed the app as an update, and launched it successfully on the available, paired physical **iPhone 17 Pro**. Scheme/configuration/bundle: **Voxboard / Debug / bontecou.Voxboard**. Xcode: **26.6 (17F113)**.

Logs, relative to this worktree:

- `.derived/location-iphone-install/ios-device-build.log`
- `.derived/location-iphone-install/ios-device-install.log`
- `.derived/location-iphone-install/ios-device-launch.log`
- `.derived/location-iphone-install/helper.log`

No uninstall, app-data reset, implicit tests, signing workaround, or phone UI automation was performed. Build/install/launch success is not a physical-device navigation or recording-integrity pass.

## Missing origin-location result fallback (subsequent fix, 2026-10-06)

A separate delivery defect remained: `CapturePipeline.validateLocationDecision(in:)` honored Send Without Location for a recorded unavailable outcome, but unconditionally requested a decision when the saved request had no `locationOutcome` at all. This also prevented an explicit one-time Send Without Location choice from resolving such a request.

The validator now honors the request's frozen Send Without Location policy or explicit per-request override before handling either missing or unavailable outcomes. It does not acquire a later location, synthesize an origin observation, change the saved preset policy, or adopt today's preset settings. Ask/Cancel requests without an override remain blocked. No migration or new automatic retry was added; normal delivery/drain uses the existing saved policy and explicit decisions.

Five regressions cover legacy JSON with no outcome, coordinate-free delivery and empty `{location}` formatting, one-time consent with Ask unchanged, Ask/Cancel blocking, and durable inbox delivery/recovery/idempotency. Before the fix, both direct pipeline cases threw `locationDecisionRequired(nil)` and both inbox cases incorrectly remained pending (`missing-location-red.log`). After the fix, all 33 focused pipeline/inbox tests passed (`missing-location-green.log`). The full shared suite passed **1,051 XCTest + 10 Swift Testing cases**; **131 project-contract tests** and the iOS Simulator build passed (`missing-location-suite.log`, `missing-location-contracts.log`, `missing-location-ios-build.log`). Evidence is in `.derived/pr39-location-checks/` under the main checkout.

Initial verification of this subsequent fix did not install it on the physical iPhone or modify real captures. The specific real request's missing-outcome cause remains unconfirmed because device file access did not expose it.

### Authorized missing-outcome fix deployment (2026-10-06)

After a subsequent explicit device-build request, the bundled helper built this updated feature worktree with normal signing and successfully installed and launched it on the available, paired physical **iPhone 17 Pro**. Scheme/configuration/bundle: **Voxboard / Debug / bontecou.Voxboard**. The existing `.derived/location-iphone-build` device cache was reused; earlier deployment logs were preserved.

New logs, relative to this worktree:

- `.derived/missing-location-iphone-install/ios-device-build.log`
- `.derived/missing-location-iphone-install/ios-device-install.log`
- `.derived/missing-location-iphone-install/ios-device-launch.log`
- `.derived/missing-location-iphone-install/helper.log`

No uninstall, app-data reset, implicit tests, signing workaround, or phone UI automation was performed. Normal app startup still follows its configured saved-request policies; actual phone capture handling after launch was not inspected. Installation/launch success does not establish the real request's cause or a physical-device behavioral pass.
