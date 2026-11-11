# Android exploratory QA — 2026-11-07

Follow-up: all three findings have been implemented and verified. See [fix validation and screenshots](fixes/validation.md).

Tested the existing installation of `md.vox.android` on `emulator-5556` (`vox-parity-checks-api36-20261101`, Android API 36) using Argent 0.32.0. Repository HEAD: `ca42bbcd`; the installed binary was not rebuilt, so source pointers below are diagnostic leads rather than proof of its exact revision.

## Findings

### 1. P2 — Entry-template edits disappear after rotation

1. Open Settings → Routes → New Entry Template.
2. Enter `QA Rotation Repro` as the name and `prefix-before-rotation` as the prefix.
3. Rotate to landscape, then return to portrait.

Expected: the open editor and its unsaved fields survive the configuration change.

Observed: landscape shows the route list/detail placeholder instead of the template dialog. Returning to portrait restores an empty New Entry Template dialog with Save disabled. Reproduced twice, first with a long multilingual Markdown prefix and then with the short ASCII values above. No Save or Cancel was pressed during either rotation cycle.

Evidence: [filled template](template-before-rotation.png), [empty dialog after rotation](template-empty-after-rotation.png).

Source lead: `apps/android/app/src/main/kotlin/md/vox/android/CapturePresetScreens.kt:723` stores name, prefix, and suffix using `remember(template?.id)`, while the dialog's owning selection uses `rememberSaveable` at line 327. The fields are not restored with the dialog.

### 2. P2 — Landscape capture editor clips even a short draft

1. Open Capture and type `QA short draft`.
2. Rotate to landscape.
3. Dismiss the keyboard with Android Back.

Expected: readable draft text and usable editing space; if the draft preview is enabled and supported, its contents should be visible.

Observed: only a clipped sliver of the text is visible above the quick-action bar. The rest of the available screen is occupied by controls or blank space. The Hide draft preview control is visible, but no preview content appears. The draft itself remains intact when returning to portrait. Reproduced with both a 14-character draft and a roughly 1.3 KB multilingual Markdown draft.

The element tree reports `capture-editor` at `(0.170, 0.418, 0.482, 0.106)` with the keyboard dismissed, and height `0.065` while it is present. The screenshots show the clipping directly. This is not a claim that landscape tapping or the preview toggle is broken; Argent's landscape interactions were inconclusive.

Evidence: [short draft in landscape](capture-short-landscape-clipped.png), [long draft in landscape](capture-landscape-clipped.png).

Source leads: `CaptureScreen.kt` around the `CaptureWorkspace` call (line 1129), and `CaptureComposerOptions.kt:99` onward. Investigate available height and the editor/preview composition under a wide but short viewport.

### 3. P2 — Rotation clears the capture Undo history

1. In portrait Capture, type a change and verify Undo is enabled.
2. Rotate to landscape without leaving Capture or sending the draft.
3. Return to portrait.

Expected: a configuration change preserves the ability to undo the last text edit.

Observed: text survives, but Undo changes to disabled “Nothing to undo.” Isolated after an earlier navigation test by appending `_UNDO_CHECK`, collecting a fresh tree showing enabled Undo, and rotating directly. Reproduced again with the short draft.

Evidence: [Undo enabled before rotation](undo-enabled-before-rotation.png), [Undo disabled after rotation](undo-disabled-after-rotation.png). Fresh element trees corroborated both states.

Source lead: `apps/android/app/src/main/kotlin/md/vox/android/CaptureScreen.kt:394` keeps `undoStack` in `remember { mutableStateListOf<TextFieldValue>() }`, so activity recreation discards it.

## Other checks

| Area | Input / interruption | Observed result |
| --- | --- | --- |
| Entry templates | Whitespace-only name | Save stayed disabled. |
| Entry templates | Pasted YAML/Markdown, emoji, Japanese, Arabic, unknown token, long unbroken text | Paste succeeded; dialog expanded and remained scrollable. Persistence through Save was not tested. |
| New route | `capture-{id}.md/../escape.txt` filename | Done became disabled and Deliver was marked invalid. The route was discarded. No filesystem traversal was attempted. |
| Recording queue | Empty queue, open Import Audio or Video, cancel system picker | Returned to empty queue without a phantom recording or error. |
| Library | Pasted punctuation, regex/SQL-like characters, Unicode, newline and `../../` | Returned zero matches without a crash; clearing query restored the original two entries. |
| Library | Open Clear Library confirmation and Cancel | Both original history markers remained. No clearing was performed. |
| Capture | Long multilingual Markdown, long unbroken word, Home → launch app | Draft text survived backgrounding and foregrounding. |
| Capture | Rotate long and short drafts | Draft text survived; layout and Undo defects are listed above. |
| Due date | Open on empty draft, inspect Today/Tomorrow/This Weekend, cancel | Dates matched the emulator date; cancel left the draft empty. |
| Sketch | Open empty sketch dialog, cancel | Add Sketch was disabled while empty; cancel left no attachment. Drawing was not tested because the drawing surface had no targetable element in the tree. |
| Quick Settings | Open tile-add system prompt, Android Back | Returned to Settings. Tile installation was not tested. |

## Tooling limitations and final state

Argent sometimes returned an element tree from an earlier screen while the screenshot showed the current screen. A wait could incorrectly report that stale tree as settled. Device-scoped transport/native-devtools resets restored fresh discovery. These are tooling observations, excluded from the app bug count. Landscape preview-toggle taps produced no dependable result and are not reported as an app failure.

No application source was changed, no captures were sent, no routes/templates were saved, and no existing notes or history were deleted. Temporary draft text and the search query were cleared, portrait orientation restored, and the original two Library entries verified. The emulator and final Argent services remain available. This was live exploratory QA, not a saved automated regression suite; no build, JVM tests, hardware audio tests, or network delivery tests were run.
