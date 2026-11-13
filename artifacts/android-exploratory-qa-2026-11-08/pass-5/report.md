# Android exploratory QA — pass 5, 2026-11-08

Used Argent on the existing Vox Android emulator (`emulator-5556`, API 36). New coverage: app-scoped language transitions, Quick Settings tile cancellation, actual launcher widget placement/configuration, and Voice Auto-Stop timing/end-action controls. No emulator reboot or snapshot load was used in this pass.

## Finding: widget configuration loses unsaved edits on rotation

Reproduction:

1. Open the launcher's Widgets picker, search for Vox, and add the Capture Presets widget.
2. Open that new widget's settings.
3. Choose Custom slots and assign Meeting Notes to position 1.
4. Rotate to landscape.

Expected: Custom slots and the assignment remain selected until Save or Cancel.

Observed: the form returns to Follow Capture Bar and all unsaved positions disappear. Returning to portrait retains the reset form. The configuration had not been committed, so previously saved widget preferences were not overwritten by this reproduction.

Cause: `PresetWidgetConfigurationScreen` kept its selection in `remember(initial)`, which resets during activity recreation.

Fix: retain the source and all six positions with a saved-state saver. Empty positions and repeated route IDs are preserved. This does not commit a configuration before Save; Cancel still discards the draft.

- [Custom slot before rotation](widget-before-rotation.png)
- [Reset source after rotation, before fix](widget-after-rotation-lost.png)

## Other coverage

| Scenario | Result |
| --- | --- |
| Quick Settings & widgets → system Add Tile prompt → Back | Prompt canceled; Settings remained usable; no tile added. |
| System language → Arabic | Screen recreated with Arabic copy, right-to-left layout, and correct selected marker. |
| Arabic → Traditional Chinese on the same screen | Layout returned to left-to-right; Traditional Chinese marker and copy appeared. |
| Traditional Chinese → System | Original System selection restored. |
| Auto-stop enabled from its original Off state | Revealed original 0.75-second pause and Stop Recording action. |
| Select 0.5 seconds and Keep Listening | Both choices displayed; continuous-listening explanation appeared. |
| Rotate landscape → portrait with those settings | Timing and end action remained selected. |
| Select the upper timing boundary, 2 seconds | Displayed 2 seconds while keeping Keep Listening selected. |
| Restore auto-stop preferences | Returned to 0.75 seconds, Stop Recording, and Off. |

The auto-stop checks exercised configuration, not recognition or automatic stop behavior with live speech. No recording, capture submission, transcription, model download, or URL delivery was started.

## Verification

- Debug app and instrumentation APKs built successfully; installed with `adb install -r` to preserve existing data.
- **10 emulator tests passed**: 3 new widget saved-state regressions, 6 composer/preset UI regressions, and 1 Voice Auto-Stop UI regression. See [instrumentation log](instrumentation.log).
- **3 Voice Auto-Stop unit tests passed**. See [unit results](voice-auto-stop-unit-results.xml).
- New widget regressions cover repeated targets with empty positions, clearing an existing assignment, and canceling after state restoration without saving.
- Live Argent verification on the installed fixed app: Custom slots + Meeting Notes survived landscape → portrait; Save produced the expected first slot on the actual launcher widget.
- [Draft retained after rotation](widget-after-rotation-fixed.png)
- [Saved widget on launcher](widget-saved-on-launcher.png)
- `git diff --check` passed.

## Cleanup and limits

Removed the temporary Capture Presets widget through the launcher's Remove target; launcher confirmed “Item removed.” Restored language to System and auto-stop to Off / 750ms / Stop Recording. Left the app on an empty Capture screen in portrait with the keyboard hidden. Existing app data was preserved.

Argent's Home command intermittently timed out; opening the launcher by its explicit activity provided access without restarting the emulator. No live speech recognition was exercised in this pass.
