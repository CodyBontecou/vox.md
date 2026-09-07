# Capture UI metadata and launch regression gates

## Failure and boundary

The September 6, 2026 device crash (`Voxboard-2026-09-06-214639.ips`) was a
main-thread stack overflow in Swift's runtime metadata demangler, called from
`QuickCaptureView.captureContent`. Simulator app-hosted tests passed on that
checkout. A passing simulator run is not evidence that a physical-device runtime
will resolve the same types safely; it does not mean simulators are universally
immune to metadata/stack problems.

Splitting a builder into another `private var ...: some View` is not a reliable
metadata boundary. Opaque return types can still be resolved recursively. A
`Section<Content: View>` wrapper can propagate that type just as easily.

`CaptureViewSection` is **non-generic**, stores `AnyView`, and exposes `AnyView` as
its body. Its *initializer* is generic, but the stored/returned type is not.
`QuickCaptureView` owns state, bindings, and effects; its UI helpers return this
concrete section type. Each section's builder is resolved locally instead of
being combined with every ancestor. Erasure is centralized here, rather than
sprinkled at call sites where a new caller can accidentally omit it.

`QuickCaptureCanvas`, `QuickCaptureOCRProgress`, and `QuickCaptureSentToast` are
small presentation-only Views. The canvas's slots are concrete sections, not
view generics; adding Undo to a slot cannot change the canvas's metadata type.
Recording details and modal/lifecycle modifier chains are separate bounded
sections. Existing state ownership, persistence, action callbacks and keyboard
safe-area placement remain in the coordinator. Overlay z-order is specified on
the canvas's outer siblings, outside erased wrappers.

When adding UI:

- Return `CaptureViewSection { ... }` from coordinator UI helpers; do not add
  `some View` chains or raw `AnyView(...)` call-site patches there.
- Prefer a small, separately testable nominal View for presentation-only content.
  Keep its inputs to values, bindings, actions or concrete sections.
- Split oversized builders into sections; do not raise the budget merely to
  accommodate another feature. Business logic belongs outside the builder.
- Do not change `CaptureViewSection` or canvas slots into `Content: View`
  generics. That removes the protection even if the visual hierarchy is identical.

## 1. Structural gate (Apple CI, no signing/device)

```sh
./scripts/test-capture-view-structure.sh
```

Uses SwiftSyntax/SwiftParser bundled with the selected Xcode (no package fetch).
It parses the actual source, including extensions; comments and strings cannot
satisfy or defeat the checks. Malformed Swift fails closed. It checks:

- Coordinator UI helpers/body do not return `some View` or `AnyView`.
- Raw erasure stays in `CaptureViewSection`; the section and canvas stay non-generic.
- View builders stay below 600 syntax tokens per section.

The 600-token limit is an **engineering budget, not a measured iOS crash
threshold**. It limits local growth; it cannot prove arbitrary SwiftUI metadata
will never overflow. Fourteen positive/negative parser fixtures cover guard
regressions, including opaque helpers in extensions, lost/generic boundaries,
oversized sections, invalid Swift, and comments/string literals.

Apple CI's `ios-tests` job runs the gate before building. A source-level failure
is deterministic and cannot be hidden by simulator test retries.

## 2. Rendering tests (existing VoxboardTests suite)

```sh
xcodebuild test -project Voxboard.xcodeproj -scheme VoxboardTests \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath /tmp/vox-capture-tests \
  -only-testing:VoxboardTests/QuickCaptureRenderingTests
```

`QuickCaptureRenderingTests` checks the coordinator/section's compiled body
boundaries and a generous canvas body-name budget. More importantly, it mounts
real `UIHostingController` hierarchies and lets SwiftUI render: optional canvas
sections appear/disappear, the editor retains its UIView identity during updates,
controls remain below the editor, and the real OCR and sent-toast bodies render
with Undo both absent and present. Merely constructing a SwiftUI value would not
exercise its body metadata. The slot tests use deterministic UIView probes, not
recordings, vault writes, or real watch transfers.

These tests run in the existing Apple CI app-hosted suite. They are not a claim
of full-app end-to-end QA or proof of hardware launch safety.

### One-time microphone hold tip

`CaptureMicHoldHintTests` covers the stable completion key, survival across
preference reload/toolbar reset, and arrow placement on compact, wide, and
mirrored layouts. The rendering suite also mounts the actual anchored bubble in
keyboard-sized space with light/dark, large-text, and RTL variants, retaining
screenshots in the test result bundle.

The tip uses `capture.voice.micHoldHintDismissed.v1` in standard app preferences.
It is completed only by the bubble's × or a successful reveal of recording
controls (long-press or the VoiceOver custom action). Ordinary taps, blocked
holds, backgrounding, and temporary recording/media/modal activity do not
complete it. Do not reset this preference on navigation, toolbar reset, or app
updates; clearing app data is a new onboarding state.

On a disposable simulator/fresh install, verify both completion paths separately:

1. Finish release notes. `capture_mic_hold_hint` appears above
   `capture_voice_recording`, with a bouncing arrow aligned to the mic.
2. Show/hide the keyboard, change text size, and test dark mode/RTL. The bubble
   must stay on screen, above the mic; its × has a 44-point hit target. Reduce
   Motion leaves the arrow still. The overlay must not intercept mic presses.
3. Hold the mic for at least 0.45 seconds. `capture_recording_details` appears;
   the hint disappears without starting a recording. Close the details and
   cold-relaunch: the hint must remain absent.
4. In a separate fresh preference state, tap `capture_mic_hold_hint_dismiss`.
   The hint disappears without opening details or recording. Cold-relaunch and
   visit Settings/Capture: it must remain absent.

These interaction checks are separate from the unit-hosted rendering tests,
which do not exercise real touches or the full system accessibility tree.

## 3. Physical-device cold-launch gate (local, explicit device)

Save your work in Vox.md, connect/pair your iPhone, enable Developer Mode, and keep
it unlocked. The command **installs the checkout over Vox.md and terminates the
app between launches**. It never uninstalls or resets your app data. Ordinary app
startup effects (e.g. a user-enabled auto-listen preference) still apply.

```sh
xcrun devicectl list devices
./scripts/test-ios-capture-launch.py --device '<device UUID>'
```

The script builds the current checkout in Debug, installs it, and performs three
cold launches without a debugger, XCTest injection, or a console attached. It
reads devicectl JSON and watches the **exact launched PID and executable** for
20 seconds on every launch. A launch-success message alone is never a pass. A
missing process, stale/replaced PID, locked/disconnected phone, command timeout,
missing/malformed JSON, failed build or install yields a nonzero exit. No retries
turn a crash into green. JSON receipts, build logs, and a summary (HEAD + dirty
flag) are retained in the printed temporary `vox-capture-launch-*` directory.

Options: `--configuration Release` for a second release-configuration pass,
`--seconds 30` for a longer observation window, `--launches 5` for more cold
starts, `--derived-data <path>` for a dedicated cache, and
`--allow-provisioning-updates` only if profile updates are intended.

This gate checks **process survival**, not foreground visibility, first-render
completion, or responsiveness. A hung process can still pass it. Pair it with the
rendering suite and manual recording/Undo QA. An unlocked physical device is
required: cloud simulator CI must not silently label a skip as hardware success.
To automate on a dedicated device runner, use the same explicit-device command
as a required local/pre-release gate, without adding signing secrets to PR jobs.

The gate's fail-closed behavior is itself tested without hardware:

```sh
python3 -m unittest discover -s scripts/tests -v
```

Those tests also run in `test-project-contracts.sh` on portable CI runners.
