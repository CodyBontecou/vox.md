# Action Button: Record Audio into a Draft

Choose **Delivery → Add to Draft** in the existing **Record Audio** action or
**Vox.md Record** control. Vox.md opens and starts a one-shot recording. When
you stop, the transcript is added to the existing Capture draft for review.
Nothing is sent to a note or other preset destination until you explicitly tap
**Send** in Capture. Enable **Attach Audio** to keep the recording in the draft.

**Send Immediately** remains the default for saved recording assignments.
Start, Stop, and Start or Stop keep their existing behavior; Stop does not
change an active recording's delivery or preset. Draft delivery opens Capture
even when Open App or Open When Run is off. This choice does not change the
composer's saved Send Immediately preference.

Saved **Toggle Recording** assignments keep their background behavior. The
separate **Record to Draft** action and control have been removed. Replace any
assignment to them with **Record Audio** or **Vox.md Record**, selecting
**Delivery → Add to Draft** and the same preset. Select **Start** to retain the
old action's start-only behavior, or **Start or Stop** to use one button for both.

## Setup

1. Complete Vox.md's microphone/model setup and enable the existing Lock Screen
   Record Button setting. Free-tier limits and microphone permission still apply.
2. In Settings → Action Button → Controls, choose **Vox.md Record**. Set Preset,
   Action (**Start or Stop** for a single button), Delivery (**Add to Draft**),
   and Attach Audio if desired. The same control supports Control Center and
   Lock Screen assignments.
3. Alternatively, create a Shortcut containing Vox.md's **Record Audio** action.
   Expand its options, choose Preset, Action, Delivery, and Attach Audio, save it,
   then assign it under Settings → Action Button → Shortcut.
4. Invoke the action, speak, and stop with the assigned toggle, the app's Stop
   control, or the Live Activity Stop control. Review/edit Capture and tap Send
   only when ready.

Record Audio remains available on iOS 17+ and the control on iOS 18+; the app's
shipped deployment target still applies. Draft delivery uses the immediate
foreground handoff. Permission, unlock, audio-session, and Live Activity checks
still apply.

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
- Record Audio preserves its chosen Action through the draft handoff. Start
  leaves an active capture untouched; Stop does not start an idle recorder.
- After publishing its complete launch request, the draft action wakes a running
  app directly. Recording does not wait for another scene activation when the
  foreground intent executes after activation. Launch/activation checks retain
  the durable fallback for requests published before the app subscribes.
- Transcription history/usage accounting remains local and unchanged. Saving
  local history or staging an attachment is not sending to a destination.

## Verification boundary

Source registration exposes one recording App Shortcut and the existing
configurable Record control for both deliveries. App and widget metadata tests
verify that the separate draft intent and configuration are absent.
App-hosted synthetic tests cover request/preset/completion routing,
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
The integrated synthetic URL-delivery regression verifies that recorded draft
text neither prepares HTTP delivery nor sends a request before explicit Send,
then sends once after review. Native loopback and keychain tests cover the URL
transport separately.
