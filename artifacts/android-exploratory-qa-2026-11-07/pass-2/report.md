# Android exploratory QA — pass 2, 2026-11-07

Used Argent on the existing Vox emulator (`emulator-5556`, API 36), with the fixes from the preceding QA pass installed. Focus: link attachments, durable drafts, duplicate file attachments, and recording interruptions. No application source was edited or rebuilt during this pass.

## 1. P1 — A malformed link prevents subsequent draft edits from being saved

Reproduction:

1. Type `QA durable base` in Capture. Restart the app and verify that the text survives; this establishes a saved baseline.
2. Open Add media → Link. Paste `https://` and tap Add.
3. The dialog accepts the value despite its missing host. The composer displays the link and enables Send, but shows “The current draft could not be saved locally.”
4. Append ` UNSAVED EDIT` to the text. Verify the composer contains `QA durable base UNSAVED EDIT`.
5. Restart the app.

Expected: malformed input is rejected at the link field, and unrelated text edits remain durable.

Observed: after restart the composer contains only `QA durable base`; the appended text and link are gone. The earlier saved baseline survives, but text entered while the invalid link was attached does not. The link acceptance/save failure reproduced twice; the restart/data-loss path was demonstrated once with a baseline already verified across restart.

Evidence:

- [Add enabled for a hostless URL](link-empty-host-enabled.png)
- [Link attached while draft save fails](link-invalid-draft-error.png)
- [Appended text before restart](link-draft-before-restart.png)
- [Appended text lost after restart](link-draft-after-restart-data-lost.png)

Source evidence: `CaptureScreen.kt:2908` checks only `startsWith("https://")` / `startsWith("http://")`. `AndroidCaptureRepository.kt:173` validates the URL before persisting the draft; its `isHttpURL` helper at line 1824 requires a host. `CaptureViewModel.kt:96` updates in-memory text before attempting persistence, then reports a generic notice on failure. These boundaries explain why an invalid attachment leaves later text edits non-durable. Do not relax the repository validation; align entry validation and preserve text durability on failure.

Related validation observation: pasting `HTTPS://example.com/qa` leaves Add disabled. The link field and repository both compare schemes case-sensitively, while the attachment sheet recognized that clipboard value as a copied link. [Screenshot](link-uppercase-rejected.png). This is recorded as related inconsistent link handling rather than another occurrence of data loss.

## 2. P2 — Live recording controls disappear in landscape

Reproduction:

1. Start a voice recording from Capture.
2. Pause it and press Home.
3. Rotate to landscape and launch Vox again.
4. Dismiss the keyboard with Android Back.

Expected: Cancel, Stop, and Resume remain visible and usable in the recording screen.

Observed: the timer, waveform, and Add to Draft / Send Immediately selector remain visible, but Cancel, Stop, and Resume are not drawn on-screen. Dismissing the keyboard does not restore them. A fresh device-scoped element-tree session reports the same state, so this was not just an earlier stale discovery tree.

Returning to portrait restores the controls. Resume works and the timer advances. Rotating the actively recording screen back to landscape reproduces the same missing-control layout, including Pause instead of Resume. A workaround is to return to portrait.

Evidence:

- [Paused landscape recording, keyboard dismissed](recording-landscape-controls-missing.png)
- [Active landscape recording with controls missing](recording-active-landscape-controls-missing.png)
- [Controls restored in portrait](recording-portrait-controls-and-keyboard.png)

Source lead: the normal, non-tabletop branch in `LiveRecordingScreen.kt:87` uses a vertically stacked header, timer, waveform, result selector, and 96 dp stop-control row, with fixed padding and no short-height layout. The prior composer-height fix does not apply to this separate recording screen.

Related focus observation: the Gboard floating stylus toolbar remains over the full-screen recording and reappears after rotation. The covered Capture editor still requests focus in `CaptureScreen.kt:809`. The landscape controls remain missing even after dismissing this toolbar, so the layout failure is independent of keyboard occlusion.

## Other coverage

| Scenario | Result |
| --- | --- |
| Pause → Home → rotate → foreground | Session stayed paused at 0:11. |
| Return to portrait → Resume | Timer advanced and status returned to Recording. |
| Cancel test recording | Returned to Capture; canceled audio was retained in Recording Queue for recovery. |
| Delete the canceled QA recording | Confirmation appeared; confirming removed this session and queue showed No Recordings Yet. |
| Attach a local Markdown file | A 95-byte attachment appeared and Send became enabled without text. |
| Attach the same file twice | Second attachment received a distinct `-2.md` filename. |
| Remove first duplicate | Second attachment remained independently removable. |
| Remove last attachment | Composer returned to an empty draft with Send disabled. |
| Save ordinary text → restart | Ordinary draft text survived, establishing the control case for finding 1. |
| Final cleanup → restart | Empty draft remained empty; no link or file attachment returned. |

## Final state and limits

Portrait orientation restored. Temporary text and link/file attachments removed. Only the 34-second QA recording created in this pass was deleted; the queue was then empty. No captures were sent or URL deliveries triggered, and no existing notes, routes, templates, or history were deleted. The file used for attachment testing was selected through the system picker and its source was not edited or deleted.

The emulator and Argent services remain running. Initial launch/ADB timeouts and occasional stale element trees required connection recovery; these tooling failures are excluded from the app findings. This was live exploratory QA, not a saved automated regression suite or a hardware audio-quality test. The two findings remain unfixed by this pass.

## Fix follow-up

Both findings were subsequently fixed. See [implementation and verification evidence](fixes/validation.md), including 18 JVM tests, 17 emulator instrumentation tests, and live Argent screenshots.
