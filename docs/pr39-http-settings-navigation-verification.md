# Capture HTTP endpoint warning navigation

Tapping **Enter a delivery URL.** (or another endpoint validation warning) now opens **HTTP Endpoint** for the Capture draft's selected preset and focuses its URL input. The same HTTP controls and Keychain mutation path are reused. iOS uses a native push/back; Mac uses a native navigation stack, preserving the workspace's existing paywall-only sheet contract. Unrelated errors and text-only attachment warnings are not linked to endpoint settings.

Preset identity is fixed at navigation time. Endpoint edits merge into the latest saved preset, preserving unrelated settings/other presets. A deleted preset or one switched to Directory is not recreated/overwritten. Pop refreshes Capture's profiles; iOS also publishes Watch state. URL/header/token drafts remain ephemeral with existing endpoint-bound Keychain protection. Navigation never submits a capture or clears the draft.

## Verification

- Baseline red native repro: tap the original static warning; URL field wait fails (`red-result.log`, `cause: unmet`, 5002ms).
- 45 focused app-hosted tests pass: four new endpoint editor persistence/identity cases, 14 composer HTTP cases (including three new recovery-route cases), 15 Capture rendering cases and 12 header-row cases. Initial test fixture used a copied built-in with a custom ID, which normal migration correctly retired; corrected it to a custom preset. No production migration change.
- Mac build passes. Project contracts pass (131 Python cases and governed validation); Capture structure gate passes (14 fixtures, three files under the 600-token section budget). `git diff --check` passes.
- Native simulator: selected a synthetic non-default HTTP preset with no URL; tapped the warning; verified the correct preset and automatically focused URL field by typing without a field tap; saved a valid synthetic URL and returned, observing warning removal and unchanged draft text. A separate unsaved-edit/back flow preserves the warning and draft.
- Final unsaved-edit/back flow: two consecutive full replays, each `ok: true`, 15 passed steps, no failures/skips/errors. Raw AX checks intentionally retained: Argent's UIKit runner projection omits some SwiftUI IDs and reads labels instead of text-field values. Both stable-ID and exact-label scratch selector probes for the warning failed on a known-good screen, so the ordinary flow retains one disclosed AX-frame-derived tap at `(0.4825, 0.181)`. This fixture-bound flow is not a portable strict-selector QA regression. Idle warnings were blinking editor carets; typing/value checks prove readiness.
- Video finalized: `navigation-final.mp4`, 14.67 seconds, 30fps. Entry and back frames inspected. This is interaction evidence, not sustained 60fps/release-performance evidence.
- Signed Debug physical-device build, install, and launch succeed on **iPhone 17 Pro**, `00008150-001405DA2188401C`, scheme `Voxboard`, bundle `bontecou.Voxboard`. No uninstall/reset. Hardware UI or Keychain save/reload is not claimed by deployment.

Build/test/device logs: `.derived/http-settings-checks/` in this checkout. UI artifacts: `/Users/codybontecou/dev/vox.md/.derived/pr39-http-settings-ui/`, including `replay-{1,2}.json`, `draft-{before,after}.txt`, `endpoint-focused.png`, `endpoint-large.png`, and recordings. The dedicated simulator's fixture script resets only the newly-created synthetic preset's URL; it refuses credentials and does not touch physical-device data or other simulators.

Light and large-text layouts inspected. Requested system-dark screenshots continued rendering light even after relaunch, so they do not establish dark-mode verification. Mac runtime UI, hardware visual checks, server acceptance, full release navigation/performance and native Keychain lifecycle remain separate checks. Only synthetic text and `.invalid` URLs used; no credentials or real endpoint tested.

Main remains clean. All changes remain local/uncommitted in `feat/pr39-exclusive-capture-target`; no push/merge, new goal, or Argent update.
