# Action Button background recording investigation

Refs https://github.com/CodyBontecou/vox.md/issues/33

## Evidence and implementation boundary

The report on Vox.md 2.8 (2), iOS 27 confirms that a regular Shortcut containing
Toggle Recording can start/stop without foregrounding Vox.md. This lane did not
replay it: physical-device installation, permission changes, and microphone
recordings are not authorized. The reported OS/version is not a claim about the
CI simulator or this branch's build.

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
controls. Existing background/dynamic-foreground modes remain unchanged;
Apple's [supportedModes contract](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
specifies that this combination prefers the background.
[AudioRecordingIntent](https://developer.apple.com/documentation/appintents/audiorecordingintent)
requires a Live Activity for the duration of recording. Its protocol is available
from iOS 18, but this change preserves the existing intent's iOS 26 gate and
older-system foreground path rather than claiming broader runtime support.
[Runtime behavior](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)
is system-dependent, so device routing must still be verified. The iOS 27-only
`allowedExecutionTargets` API is not introduced into the Xcode 26 build.
These declarations were checked against Xcode 26.6 (17F113), the iOS 26.5 SDK,
and Apple's current documentation on 2026-10-04.

The stop path now checks Live Activity availability just as the start path does.
The recorder may retain microphone capture during background processing after a
segment is finalized. If the card cannot be reused or recreated, Stop tears down
that remaining audio session before returning. It does **not** chain to Record:
a Stop request must not start a replacement recording. The existing start-failure
foreground fallback is unchanged.

The current activity controller requests `.transient` for shortcut recording.
Apple's [Activity.request style contract](https://developer.apple.com/documentation/activitykit/activity/request(attributes:content:pushtype:style:))
says a transient activity can end when the device locks, the extended Dynamic
Island collapses, or the person performs other tasks outside it. Background
creation itself is authorized by `LiveActivityIntent`; this contract does not
require transient style. No activity-controller lifecycle change is made here.
QA must record what happens on those dismissals and must not assume that a
successful activity request proves recording or Stop remains available later.

Toggle is also an availability-gated curated App Shortcut (nine total, preserving
the previous eight), using [AppShortcutsBuilder](https://developer.apple.com/documentation/appintents/appshortcutsbuilder)'s
limited-availability support. Keep the gated declaration **after** the legacy
shortcuts: with it first, Xcode 26.6 extracted iOS 26 availability for all eight
subsequent legacy shortcuts as well. Moving only that declaration to the end
restores their iOS 17 availability and keeps Toggle gated to iOS 26. A built
metadata regression covers each legacy entry's supported-OS availability.
An App Shortcut alone is not evidence of exposure in the Action Button Controls
picker.

## Automated regression surface

`ToggleRecordingRegistrationTests` is in the synchronized `VoxboardTests` target,
run by Apple CI's `ios-tests` job. It exercises the actual control provider and
intent: configured preset forwarding, nil/deleted/disabled preset fallback,
safety-setting no-op, the exact background-preferred modes, and preservation of
foreground behavior. Two stop-path tests inject synthetic audio/ActivityKit
operations into the method called by `perform()`: failed activity presentation
must release capture after finalizing the segment; successful presentation must
preserve the existing background-processing session. They do not record audio,
request permissions, exercise queued delivery, or establish OS runtime behavior.
It also reads **built** app/embedded-widget App Intents metadata to assert that
the toggle and legacy App Shortcuts are registered with their independent OS
availability and the widget carries the same toggle/configuration identities. These are not Swift-source grep assertions.
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
| Fresh and upgrade | Warm/backgrounded | Lock during recording; collapse/dismiss the Dynamic Island | Record whether the transient activity ends, whether capture stops safely or continues, whether either Stop entry point remains usable, and whether finalized audio is preserved; no orphan microphone session |
| Fresh and upgrade | Warm | Unlocked/locked | Microphone denied, Live Activities denied/off, recording safety setting off, free-tier limit, stale/disabled preset: safe no-op or existing foreground fallback; no orphan audio session |
| Existing installation on older supported iOS | Warm/cold | Unlocked/locked | New toggle entry absent; foreground Record assignments still work |

Use two different enabled presets to distinguish the configured control preset
from the app's currently selected preset. Preserve local captures, drafts,
presets, destinations, and recording-result settings. This issue does not alter
issue #31's draft-delivery request. Setup and wrapper-workaround guidance is in
README and website docs. No release notes/version bump, release, deployment, or
issue closing is performed; future release notes should be added only once the
shipped version and device-supported behavior are known.
