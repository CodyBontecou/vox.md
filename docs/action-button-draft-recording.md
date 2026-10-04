# Action Button: Record to Draft

**Record to Draft** is a separate preset-aware quick action. It opens Vox.md and
starts a one-shot recording automatically, without another tap on Start. When
you stop, the transcript is added to the existing Capture draft for review.
Nothing is sent to a note or other preset destination until you explicitly tap
**Send** in Capture.

This is not **Record with Preset**, which retains immediate delivery, or
**Toggle Recording**, which retains its background start/stop behavior. Existing
assignments and wrapper Shortcuts keep their intent identities and behavior.
Record to Draft is a foreground action, not a new background toggle. Running it
while another capture owns the recorder does not stop or replace that capture.

## Setup

1. Complete Vox.md's microphone/model setup and enable the existing Lock Screen
   Record Button setting. Free-tier limits and microphone permission still apply.
2. On supported systems, look in Settings → Action Button → Controls for
   **Vox.md Record to Draft**, then configure its Capture Preset. The same control
   is registered for Control Center/Lock Screen controls.
3. Alternatively, assign the **Record to Draft** App Shortcut. To configure the
   optional **Attach Audio** parameter, create a Shortcut containing Vox.md's
   **Record to Draft** action, choose a Preset, enable Attach Audio if desired,
   and assign that Shortcut to the Action Button. The control uses transcript-only
   draft delivery; the configurable Shortcut can retain audio too.
4. Invoke the action. Vox.md opens and requests recording immediately. Stop using
   the app's existing Stop control, or the existing Live Activity Stop control
   when an activity is available. Open Capture to review/edit and tap Send only
   when ready.

The intent has the same iOS 17 foreground availability annotation as the legacy
record intent; the control is iOS 18+. The shipped app's deployment target still
applies. The iOS 26 foreground mode is explicitly immediate. No OS-availability,
permission, unlock, audio-session, or Live Activity checks are bypassed.

## Preset and draft behavior

- An enabled explicitly requested preset is resolved at recording start. A
  missing, removed, or disabled preset falls back to the durable selected preset,
  as the legacy quick-record path does.
- The recorder snapshots that preset's voice-processing configuration at start.
  Later preset edits do not change queued/retried transcription or speaker
  identification. It does **not** snapshot the preset as an immediate delivery
  destination: completion is always `.captureDraft`.
- The open draft's text, attachments, selected preset/destination, and request ID
  are preserved. The action's Preset chooses voice processing; the reviewed
  draft's route remains the route used by its eventual explicit Send.
- The action ignores (and does not change) the composer's persisted “Send
  Immediately” preference. Attach Audio defaults off, independently of that
  preference.
- Transcripts/audio use the existing durable recording receipts, so retry does
  not append duplicates. Stop handoff/recovery persists draft delivery, the
  target draft request ID, and the immutable voice-processing configuration.
  A replaced/mismatched draft is rejected rather than silently receiving or
  immediately exporting the recording; its recording job remains retryable.
- A new legacy immediate action or legacy widget URL clears the draft override.
  A malformed draft attachment override fails closed to transcript-only draft
  delivery, never immediate delivery.
- Transcription history/usage accounting remains local and unchanged. Saving
  local history or staging an attachment is not sending to a destination.

## Verification boundary

Source registration includes both an App Shortcut and a distinct configurable
ControlWidget. App-hosted synthetic tests cover request/preset/completion routing,
immutable recovery/retry metadata, cold-load draft identity, existing content and
attachments, idempotent delivery, and the real recorder's queued `.captureDraft`
transcription path without note export, followed by an explicit Send that writes
both preserved and newly recorded attachments to a synthetic note. These tests do not activate a microphone,
use a downloaded ASR model, or send transcript data to a network service.

Registration and extracted intent metadata do **not** prove physical Action
Button picker exposure. Before release, hardware QA must cover fresh/upgraded
installs, picker/configuration persistence, cold/warm invocation, locked/unlocked
behavior, microphone denial/free limits, one-shot teardown, Live Activity Stop,
and real transcription with the chosen preset. Device authentication/foreground
launch behavior and any iOS-specific picker caching are still hardware gates.
After integration with URL delivery, verify with synthetic data and a loopback
endpoint that draft recording makes no HTTP request before explicit Send.
