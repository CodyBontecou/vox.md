# Action Button background recording investigation

Refs https://github.com/CodyBontecou/vox.md/issues/33

## Configurable recording action (work in progress)

**Not ready to use or release.** Unit/model and built-metadata checks pass, but
native Action binding still fails. On the iOS 26.5 simulator, a fresh action
correctly saves `recordingAction=stop` yet the handler receives **Start**, including
after saving, restarting Shortcuts, and reopening. Renaming the parameter did not
fix decoding. Do not execute this action on a normal build or rely on Stop.
Diagnostics used a compile-time no-effect build with microphone activation blocked;
no audio was recorded. See `build/configurable-recording/native-switch/QA.md`.

The primary now uses Shortcuts' native **Open When Run** and iOS 26
`systemContext.currentMode`; fresh simulator and physical iOS27 beta editors have
one switch. After USB/developer-trust recovery, a compile-time no-audio probe on
the actual iPhone 17 Pro decoded **Stop/background** with the switch OFF and
**Stop/foreground** with it ON. Saved Stop/OFF also decoded Stop after a cold
Shortcuts restart (Vox.md remained warm). This does not resolve the separate
iOS26.5 simulator failure or verify recording/foreground handoff. See
`build/configurable-recording/iphone/native-switch/QA.md` for receipts and limits.
The owned test shortcut and all probes were removed; the normal build was
restored without executing its recording intent. Controls retain explicit
**Open App** through hidden `VoxboardRecordingControlIntent`. Original `vox`,
intent/entity identities, control kinds and defaults are preserved. No releases
or version bumps have been made.

A subsequent authorized no-audio **Start or Stop** probe on the same phone
observed three primary Shortcut entries and four presses of the existing Action
Button control. Both decoded Toggle/background correctly; the control's saved
Open App was independently observed OFF without editing it. Seven triggers
produced seven guarded receipts with expected simulated alternation and one warm
recorder identity. Effects were compiled out and the real recorder stayed idle,
so this did **not** reproduce or fix the reported intermittent stop/restart cycle,
or exclude delivery/state changes during real recording. Source/normal build
were restored and the owned shortcut removed. See
`build/configurable-recording/background-toggle/probe/QA.md`. Task remains blocked.

With separate real-audio authorization, a bounded diagnostic then exercised two
Action Button start/stop pairs and one Shortcut pair on that phone. All reached
an active recording at Stop and ended microphone input; six triggers produced
six completed entries. Continuous voice-pause detection armed, but no end-of-speech
callback occurred. ASR and destination delivery were blocked, and Stop discarded
test audio before normal processing. These passes do not reproduce the reported
intermittent failure or verify the omitted speech/processing lifecycle. Normal
source/build were restored; findings in
`build/configurable-recording/background-toggle/audio-probe/QA.md`.

**Record Audio** is now the primary recording App Intent and the only curated
recording App Shortcut. It reuses `OpenVoxboardRecordIntent`, its `vox` parameter,
and the existing `VoxboardRecordControl` kind/configuration identity. New
parameter **Action** offers Start, Stop, and Start or Stop. The native **Open When
Run** switch defaults on; missing Action defaults to Start. These are intended
legacy defaults, not saved-assignment upgrade proof. The control's new fields are
optional so an installed foreground control retains Start/Open App on and an
installed background control retains Start or Stop/Open App off. Explicit choices
override either kind's defaults.

On iOS 26+, the same intent adopts `AudioRecordingIntent`/`LiveActivityIntent`
through an availability-gated conformance and declares both background and
immediate-foreground modes. An internal, undiscoverable
`OpenVoxboardRecordingActionIntent` handles foreground execution and the existing
preset/flag handoff. `RecordingIntentExecution` shares safety/fallback behavior
with controls and the legacy toggle. The primary exports no custom Open App field;
built app/widget metadata asserts this and the native simulator/physical editors agree.
The switch's native execution-mode routing is observed, but the full production
recording cycle and actual foreground handoff are not verified.
On iOS 18.2–25 execution always chains to the foreground helper. The compile-time
legacy `openAppWhenRun = true` is retained for older-iOS foreground launching;
current metadata exports supportedModes=3 and openAppWhenRun=true.
On iOS 17.6–18.1, the already-foreground app queues the same handoff without using
an iOS 18.2-only result overload. Do not add `ForegroundContinuableIntent` to the
primary action: even an old-OS-only conformance is exported as a system protocol
by the current metadata extractor and can reintroduce the duplicate system switch.
Both primary and compatibility wrapper must explicitly declare `OpensIntent` in
`perform()`'s return constraint. Real execution logged “Did not declare OpensIntent
but provided one” without that constraint; built metadata now asserts outputFlags=1.
An unexpected old-OS extension execution reports that Vox.md must be opened,
rather than pretending it recorded. Modern results use the type-erased
`result(opensIntent:)` overload; completed/no-op results use a fresh `result()`.
Do not construct a typed foreground result and clear its deprecated `opensIntent`
property: on iOS 26.5 the actual payload is type-erased, so that property neither
reports nor clears the foreground action. The isolated diagnostic exposed this
SDK behavior and the implementation no longer uses that deprecated field.

`ToggleVoxboardRecordingIntent` remains as a hidden compatibility wrapper with
its original background start/stop defaults. Its curated shortcut is removed.
The request-scoped Live Activity Start/Stop intents also stay executable with their
original identities but are hidden from the Shortcuts action library.
The old background control kind remains registered as **Vox.md Record (Legacy
Background)**: WidgetKit offers no public hide modifier for a registered control
kind, so removing the duplicate from the picker would risk installed assignments.
New assignments should use the configurable **Vox.md Record** control.

Start and Stop are idempotent, and Stop never falls back to starting a new
recording. A failed background start retries **Start**, not **Start or Stop**;
a newly activated session is released before retrying if its required Live
Activity cannot be presented. A foreground Stop bypasses composer/route loading
and leaves the active preset/completion mode untouched. A delayed foreground
Start rechecks recording state after loading the route, avoiding a second start
if another trigger began recording in the meantime. Widget deep links explicitly
reset the pending action to Start so a stale Stop cannot affect a new widget run.

`RecordingActionTests` covers transitions, preset forwarding, idempotency,
missing recorder, start/Live Activity failures, Stop cleanup, one-shot foreground
handoffs, and saved Record defaults. `ToggleRecordingRegistrationTests` covers
both controls' defaults/explicit choices, preset fallbacks, safety-setting no-ops,
one curated recording shortcut, and actual built app/widget metadata (including
protocols, parameters, serialized defaults, and foreground/background modes).
These tests do not prove real system execution or saved-assignment upgrade
routing. Physical-device QA remains required before release.

The sections below record the original issue #33 investigation and its historical
implementation. For new setup instructions, use the current README. In addition
to the device matrix below, verify all three Actions with Shortcuts' Open When Run
and controls' Open App on/off, only after safe binding proof; Start
while already recording must preserve audio/preset, Stop while idle must not
activate the microphone, and a denied Live Activity must not make Stop restart.
Verify upgraded saved Record/Toggle shortcuts and both control kinds without
recreating their assignments, and exercise the foreground fallback on older iOS.

## Evidence and implementation boundary (original investigation)

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
