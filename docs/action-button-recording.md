# Action Button background recording investigation

Refs https://github.com/CodyBontecou/vox.md/issues/33

## Evidence and implementation boundary

The report on Vox.md 2.8 (2), iOS 27 confirms that a regular Shortcut containing
Toggle Recording can start/stop without foregrounding Vox.md. This lane cannot
replay it: no iPhone, signing setup, or device access is available. The reported
OS/version is not a claim about the CI simulator or this branch's build.

The source at base `4f5bd7d0dd88b0c22dc13dac5e9c780da43c5991` omits Toggle
Recording from `VoxboardShortcutsProvider`; `VoxboardRecordControl` uses the
foreground `OpenVoxboardRecordIntent`. Those are deterministic registration gaps,
not proof of a background-engine defect. No recording engine or persistence
format is replaced here.

Apple documents [WidgetKit controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system)
as system entry points for Control Center, Lock Screen, and Action Button. They
must be listed in the widget bundle. [AppIntentControlConfiguration](https://developer.apple.com/documentation/widgetkit/appintentcontrolconfiguration)
provides user-editable parameters via its value provider. A control **button** can
execute an AppIntent; a ControlWidgetToggle instead requires SetValueIntent. We
use a button to invoke the existing start/stop intent, not a new state-setting
recording engine dependent on stale extension state.

The new `VoxboardToggleRecordingControl` has a separate stable kind, shares the
existing Preset configuration/query, and passes its resolved preset to
`ToggleVoxboardRecordingIntent`. It is available only on iOS 26+. The existing
foreground control and all intent/entity/parameter identifiers are retained.
The same toggle declaration is compiled in both app and widget; a widget-only
compilation flag excludes app-recorder implementation references. Its defensive
extension path uses the existing foreground fallback rather than reporting
success without recording.

The toggle adopts the current [LiveActivityIntent](https://developer.apple.com/documentation/appintents/liveactivityintent)
protocol (Apple's documented replacement for the deprecated
[LiveActivityStartingIntent](https://developer.apple.com/documentation/appintents/liveactivitystartingintent)).
Apple documents app-process execution without opening the app for Live Activity
controls. Existing background/dynamic-foreground modes remain unchanged.
[AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent)
requires a Live Activity for the duration of recording; existing failure handling
and fallback remain in place. [Runtime behavior](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)
is system-dependent, so device routing must still be verified. The iOS 27-only
`allowedExecutionTargets` API is not introduced into the Xcode 26 build.

Toggle is also an availability-gated curated App Shortcut (nine total, preserving
the previous eight), using [AppShortcutsBuilder](https://developer.apple.com/documentation/appintents/appshortcutsbuilder)'s
limited-availability support. An App Shortcut alone is not evidence of exposure
in the Action Button Controls picker.

## Automated regression surface

`ToggleRecordingRegistrationTests` is in the synchronized `VoxboardTests` target,
run by Apple CI's `ios-tests` job. It exercises the actual control provider and
intent: configured preset forwarding, nil/deleted/disabled preset fallback,
safety-setting no-op, background modes, and preservation of foreground behavior.
It also reads **built** app/embedded-widget App Intents metadata to assert that
the toggle and legacy App Shortcuts are registered and the widget carries the
same toggle/configuration identities. These are not Swift-source grep assertions.
CI retains extracted metadata alongside simulator logs/results for diagnosis.

Existing `WidgetRecordingFlowSelectionTests` cover legacy requested/durable
preset behavior; `ShortcutRecordingLiveActivityGatingTests` cover independent
Live Activity settings. Microphone/Live Activity behavior is not simulated by
these registration tests.

## Physical QA required before considering the issue complete

All rows below are **not run in this lane**. Use a signed build on an Action
Button-capable iPhone running iOS 26 and the reported iOS 27 where available.
Record device/OS/build, chosen preset ID, actual visible picker label, foreground
app before/after, and Live Activity result. Do not uninstall a user's app to
simulate a fresh install; use a dedicated QA device with disposable data.

| Installation | Process state | Lock state | Required result/evidence |
| --- | --- | --- | --- |
| Fresh | Warm/backgrounded | Unlocked, another app open | Direct control visible; selected preset used; press starts, next press stops without app switch; Live Activity Stop works |
| Upgrade from 2.8 (2) | Warm/backgrounded | Unlocked | Same as above; legacy Record assignment still opens app, wrapper Shortcut still toggles; replacing assignment preserves chosen preset |
| Fresh and upgrade | Cold/not running | Unlocked | Capture actual launch routing and start/stop behavior; document any foreground fallback instead of claiming cold support |
| Fresh and upgrade | Warm and cold | Locked | Capture authentication prompt, recording indicator, Live Activity, Stop behavior, and preset/delivery access; document supported/unsupported states explicitly |
| Fresh and upgrade | Warm | Unlocked/locked | Microphone denied, Live Activities denied/off, recording safety setting off, free-tier limit, stale/disabled preset: safe no-op or existing foreground fallback; no orphan audio session |
| Existing installation on older supported iOS | Warm/cold | Unlocked/locked | New toggle entry absent; foreground Record assignments still work |

Use two different enabled presets to distinguish the configured control preset
from the app's currently selected preset. Preserve local captures, drafts,
presets, destinations, and recording-result settings. This issue does not alter
issue #31's draft-delivery request. Setup and wrapper-workaround guidance is in
README and website docs. No release notes/version bump, release, deployment, or
issue closing is performed; future release notes should be added only once the
shipped version and device-supported behavior are known.
