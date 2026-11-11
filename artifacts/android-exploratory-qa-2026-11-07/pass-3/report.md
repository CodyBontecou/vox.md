# Android exploratory QA — pass 3

Used Argent on the existing Vox Android emulator (`emulator-5556`, API 36). Focus: Library search with unusual pasted input, unsaved route configuration, invalid nested destination paths, and the sketch dialog. The two live findings below were reproduced before modifying the app.

## Findings and fixes

### Unsaved route edits disappear after rotation

Reproduction: Settings → Routes → New; paste `QA odd route 🧪 עברית` into Name; dismiss the keyboard; rotate to landscape. Once the screen settles, the name becomes empty and Done is disabled. No route was saved.

Expected: configuration changes preserve the draft and the current nested page.

Cause: `CapturePresetEditorScreen` kept its draft in `remember`, while its page used `rememberSaveable`. The form could therefore return to a nested page with reset settings.

Fix: save and restore the complete raw editor draft using a Bundle saver. This includes stable new-route ID, all 50 editor fields, optional vault references, structured location fields, URL credential references, and transcript export settings. Incomplete metadata and invalid paths remain editable rather than being normalized away during restoration. The saver stores credential references only; bearer tokens and full secret endpoints are not part of the route draft.

- [Before rotation](route-before-rotation.png)
- [After rotation: original data loss](route-after-rotation-lost.png)

### Invalid paths appear saveable, then fail with a generic error

Reproduction: New route named `QA deep route`; open Deliver; replace Folder with `../escape`; return to the overview. Done remains enabled. Tapping it produces “Check the preset name, folder, filename, and metadata fields.”

Expected: identify the invalid destination before attempting to save.

The repository already rejected unsafe paths, so no path traversal or outside-folder write occurred. The UI only checked that Folder was nonempty and the filename ended in `.md`.

Fix: use shared path validation for both form admission and repository persistence. Folder, existing note path, filename template, and attachments folder now follow the repository's existing safety and length/depth rules. Invalid inputs receive field error styling, the relevant step is marked incomplete, and Done remains disabled. Correcting the field restores Done. Unicode paths and empty attachment folders remain supported.

- [Original generic save error](unsafe-folder-generic-save-error.png)

### Related text-limit mismatch found in source review

The Capture prompt field admitted 4,096 characters while the repository limited it to 512. Aligned input to 512 and added an editor-level length check for restored drafts. A regression test pastes 700 characters and verifies the saved callback receives 512. This was found through source review and tested with instrumentation, rather than recorded as a separate live pre-fix reproduction.

## Other coverage

| Scenario | Observed result |
| --- | --- |
| Library search containing `[.*`, emoji, Hebrew, newline and tab | No crash or regex interpretation; no matching captures. |
| Clear the unusual search | Both original Library rows reappeared. |
| Route name mixing Latin, emoji, and Hebrew | Displayed in the form and summary; no layout crash. |
| Back from Deliver | Returned to route overview, retaining the invalid field for correction. |
| Back from unsaved new route | Discarded the temporary route; original four routes remained. |
| Empty sketch | Undo, Clear, and Add Sketch disabled; Cancel available. |
| Rotate empty sketch to landscape | Dialog and buttons stayed visible; no unexpected attachment created. |
| Cancel sketch | Returned to empty Capture without attachments. |

## Verification

- Debug app and instrumentation APK builds passed. [Build log](build.log).
- 3 JVM path-admission tests passed: traversal, depth/length bounds, separators, Markdown names, Unicode, and empty attachment folders. [JUnit results](path-tests.xml).
- 16 Android instrumentation tests passed: 4 new route edge-case tests plus the existing link/recording, rotation, and composer/preset regression coverage. [Instrumentation log](instrumentation.log).
- The route tests restore a form after editing identity and nested delivery settings, verify invalid paths disable Done until corrected, check a 700-character prompt, and round-trip raw invalid drafts plus nested settings.
- `git diff --check` passed.

Live Argent checks on the installed build confirmed the original rotation path now retains the mixed-language name and keeps Done enabled. An invalid folder is marked red; it survives landscape → portrait rotation on the Deliver page. Returning to the overview retains the name and disables Done.

- [Name preserved in landscape](route-after-rotation-fixed.png)
- [Invalid folder marked at the field](unsafe-folder-marked-fixed.png)
- [Nested invalid edit retained after rotation](nested-invalid-draft-after-rotation-fixed.png)
- [Done disabled for invalid route](invalid-route-done-disabled-fixed.png)

An initial test run had one ambiguous test selector matching three “Name” nodes. The selector was narrowed to the editable field; the final unchanged suite passed all 16 tests. No application failure was inferred from that test-authoring error.

## Final state and limits

Discarded the temporary unsaved route; no new route was committed. Empty Capture restored in portrait with no link or file attachments. The existing routes, notes, history, and destination were preserved. No captures, URL deliveries, audio transcription, or file exports were triggered. The sketch canvas itself was not drawn on: Argent's element tree exposed its buttons but no targetable canvas frame. Empty-state and rotation checks are the extent of sketch coverage.

Some Argent actions returned stale accessibility trees. Device-scoped service refreshes recovered current trees before further coordinate-based actions. The emulator and Argent services remain running. This was live exploratory QA with Compose/JVM regression tests, not a saved Argent E2E replay or a physical-device audit.
