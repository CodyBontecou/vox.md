# Android exploratory QA — pass 4, 2026-11-08

Argent on the existing Vox Android emulator (`emulator-5556`, API 36). New coverage: local model ZIP admission, orientation changes while Android document pickers cover the app, and WAV export from Recording Queue. Also audited the related Library export callback and model import resource ownership.

## Live findings

### Model import silently disappears after picker rotation

Control: import a 138-byte QA ZIP containing only `qa-only.txt` for German Vosk. The app returns “The archive is not a compatible Vosk model.” No model is installed.

Reproduction: choose Import ZIP for Spanish; while Downloads is open rotate once to landscape; select the same QA ZIP. Keyboard Tab → Down → Enter was used to activate the selected file because Argent landscape coordinate taps were unreliable. The app returns to Models, but Spanish remains Not Installed with no validation error. Returning to portrait shows the earlier German error and no Spanish result.

Rotating to landscape and back to portrait entirely within the picker did *not* reproduce the loss: the underlying app's final configuration was unchanged. Returning a result while still in landscape did reproduce it.

Cause: the pending model ID used `remember`, so host recreation discarded the callback's target.

- [Normal invalid-model feedback](model-import-control-error.png)
- [Interrupted Spanish import silently lost](model-import-rotation-silently-lost.png)

### Interrupted audio export creates an empty WAV document

Created and canceled one five-second QA recording (`5ccb66d8`, three durable chunks). Queue → Export Audio → Downloads. Focus the default filename, rotate the Save picker to landscape, then Tab → Enter to Save. The app returns to Queue without success or failure feedback. The selected output `vox-recording-5ccb66d8.wav` exists with size **0 bytes**.

The durable source recording remains intact. This is loss of an export operation, not deletion of the source audio.

Cause: the pending recording object also used `remember`; the callback had no recording ID after recreation and skipped the write.

- [Queue returned without export result](audio-export-returned-without-result.png)

## Fixes

- Added a saved pending-document request that preserves a small target ID across recreation and consumes it once, including canceled results.
- Models and Recording Queue now use that state for their pending model and recording IDs. Audio export provider exceptions become failure feedback.
- Related source audit: Library export kept pending Markdown only in memory. It now stages the snapshot privately and saves only a UUID reference, avoiding large text in Android's saved-state Bundle. Completion, cancellation, and failed writes remove the snapshot; abandoned snapshots expire on a later staging operation after 24 hours.
- Related source audit: model import rejected unknown, busy, or already-installed targets without always closing the supplied input stream. All early rejection branches now close it.

## Additional checks

| Scenario | Result |
| --- | --- |
| Normal invalid ZIP import | Explicit compatibility error; no model installed. |
| Picker rotated twice back to original orientation | Import still reached validation. |
| Picker rotated once before returning a result | Exposed the two pending-target bugs above. |
| Keyboard activation of file picker controls | Selected the ZIP and saved the output without relying on landscape coordinate taps. |
| Source recording after failed export | Still present with five-second duration and three chunks. |

## Verification

- Final debug app and instrumentation APK builds passed. [Build log](build.log).
- All **18 instrumentation tests passed**: 5 new picker/resource tests, 4 Recording Queue tests, 4 route edge-case tests, and 5 Library/history tests. [Instrumentation log](instrumentation.log).
- The new tests deliver an ActivityResultRegistry result after saved-state restoration, check cancellation and independent request slots, restore a large Markdown snapshot through a 36-character UUID, remove canceled/failed snapshots, and verify rejected model streams close without reading.
- `git diff --check` passed.

Live post-fix checks:

1. Recorded and canceled a new seven-second QA session (`62726f74`, four chunks). Exported it while rotating the Save picker to landscape. Queue showed “Audio exported as WAV.” The generated file was **221,740 bytes**, with a valid mono 16-bit 16 kHz WAV header and **110,848 frames / 6.928 seconds**. Only metadata was retained as evidence; the audio file was removed.
2. Imported the same invalid ZIP for Spanish while returning the picker result in landscape. After returning to portrait and reopening Models, Spanish showed “The archive is not a compatible Vosk model.” The request now reached validation rather than silently disappearing. An extra Enter during navigation activated Back after the result, so the final state was inspected by reopening Models.

- [Successful WAV export after picker rotation](audio-export-after-rotation-fixed.png)
- [Verified WAV metadata](verified-wav.json)
- [Spanish import validation after picker rotation](model-import-after-picker-rotation-fixed.png)

Library snapshot restoration was verified through instrumentation; no real user Library contents were exported in the live pass.

## Environment incident and final state

During final APK reinstallation, the emulator stopped responding to ADB. A device-scoped reconnect left it offline. A boot attempt collided with the old process; that VM was then shut down gracefully and booted through Argent without `-wipe-data`. **Argent restored an older AVD checkpoint**, which rolled back the emulator's local state: Vox returned to onboarding, Documents was empty, and the earlier `5ccb66d8` QA recording was absent. This was a recovery mistake; the pre-recovery local emulator state was not recovered. Source files and saved evidence in the repository were unaffected.

Completed onboarding again using Documents and the default starter routes, then performed the post-fix checks above. A later UI-discovery stall recovered after refreshing device services without another reboot. Stale accessibility trees and unreliable landscape taps were treated as tooling limitations rather than app findings.

Deleted only the new seven-second QA recording through its confirmation dialog; Queue showed “No Recordings Yet”. Removed the exact disposable ZIP and WAV paths from the live post-recovery filesystem. No captures were sent, no model was downloaded or installed from the invalid ZIP, and no URL delivery or transcription was triggered. Portrait orientation restored. The emulator and Argent services remain available. Future recovery should avoid loading an old snapshot when preserving current emulator state is required.
