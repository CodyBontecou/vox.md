# Thoughtful design — local preview evidence

Read `docs/thoughtful-onboarding-paywall.md` for scope, design decisions and remaining QA. No App Store submission/release, live-price mutation, website deployment or in-app What's New update occurred for this redesign.

## Start here

- `final/welcome-light.png`, `final/privacy-light.png`: shared introduction renders.
- `final/paywall-individual-review.png`, `final/paywall-family-review.png`: current compact plan selector, frozen US lifetime price fixture, one CTA.
- `final/paywall-dark.png`, `final/welcome-dark.png`, `final/privacy-dark.png`: inspected dark treatments.
- `final/paywall-large-type.png`, `final/welcome-large-type.png`: accessibility-largest renders. The paywall checkout now scrolls inline at accessibility sizes rather than occupying most of the viewport as a fixed footer.
- `final/manifest.json`: latest six-test XCTest attachment provenance. Friendly-name aliases above are the current design; earlier UUID files and sibling folders document iterations, not additional final variants.
- `verification/ios-tests.log`: latest focused iOS run, six tests, zero failures.
- `verification/mac-build.log`: successful full Mac app build.
- Native shared Mac intro pages were additionally observed in an isolated preview app (620×812, separate bundle, no real app data or StoreKit); the app was closed. This is not full Mac paywall/purchase verification.

## Motion and automation caveat

`native-flow.mov`, `motion-contact-sheet.jpg` and `navigation-motion-detail.jpg` preserve the live simulator walkthrough and inspected motion frames. The long recording contains intentional observation pauses; it is not an FPS benchmark.

`native-walkthrough.yaml` is a captured XCTest-host-specific **diagnostic fragment**, not portable CI QA. Its initial replay (`native-replay-result.json`) completed 30 actions/checks with 11 native-tree/coordinate warnings. The final-source replay (`final-native-replay-result.json`) completed 20 actions/checks and then correctly failed the history search value assertion because the field never gained keyboard focus. The failure screenshot is `replay-search-focus-failure.png`. The recording and earlier replay prove that live search can work, but this last run is not green. Strengthen destination identity and keyboard/focus readiness, and restore proper instrumentation, before claiming a reliable automated regression scenario. No assertions were removed to manufacture a pass.

The app is owned by XCTest during the local StoreKit fixture, so restarting via Argent would destroy that fixture. Raw accessibility waits worked, while the separate injected runner tree was unavailable; recorded coordinate taps therefore carry explicit warnings. Do not treat their green dispatch statuses alone as behavioral verification. No purchase was tapped during the walkthrough; the free tracker stayed locked and the interactive XCTest host itself passed.

Earlier failed/setup-only takes are retained as `first-pass-navigation-failure.yaml`, `second-pass-setup-only.yaml` and `onboarding-paywall.mov`. They are not passing evidence. Temporary preview sentinels were removed. `simulator-permission-cleanup.json` records restoring only the test app's microphone permission to not-yet-asked after test setup; no credentials were entered or device-wide permissions changed.

## Provenance and remaining release work

`research/` contains public App Store reference URLs/contact sheet; the provided Kevin Ngo site was inspected in the browser. No third-party illustration was copied into the app. The in-app note/branch artwork is original SwiftUI vector drawing.

Visual fixtures use the unchanged, frozen US lifetime amounts ($19.99/$39.99/$19.99); production prices still come from Apple. The bundled future-target StoreKit catalog was not repriced by this UI task.

Owner design feedback, full device/locale/accessibility matrix, Mac purchase interaction QA, signed sandbox/TestFlight checks, robust automated replay and release-build performance/Reduce Motion checks remain before shipping/replacing review builds. Current App Store reviews were left untouched.
