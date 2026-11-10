# iOS exploratory edge-case QA, pass 5

Tested November 8, 2026 with Argent on the iPhone 18 Pro Max simulator, iOS 27.0, bundle `bontecou.Voxboard`. New areas covered: audio-import cancellation, recording-controls help, Stats refresh/rotation, Help & feedback, and accessibility of Capture Bar/settings switches.

## Fixed: feedback had no response without an email handler

Settings → Help & feedback → Send Feedback did nothing when the simulator could neither present a configured mail composer nor open a mailto URL. The view ignored the URL-opening result. [Before](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/feedback-no-response-before.png).

It now checks the result and shows Email Unavailable with the support address and a Copy Email Address action. Failure to construct the URL follows the same fallback. English and Turkish strings were added. Feedback presentation belongs to the pushed Help page: verification caught that attaching the alert to Settings deferred it until returning there. The existing mail-composer sheet was also moved to Help so its presenter matches the invoking screen.

On the final signed build, Send Feedback immediately displayed the alert over Help. Repeated attempts worked, and both OK and Copy Email Address dismissed the alert. No email was sent. [Fixed alert](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/feedback-alert-fixed.png).

The copy action writes the support address through the platform pasteboard API. End-to-end paste verification was inconclusive: the simulator's synchronized clipboard supplied unrelated host clipboard content during the longer test, and a shorter repeat did not expose the Paste menu. The configured-mail composer and physical-device clipboard path were not exercised.

## Fixed: unnamed accessibility switches

Capture Bar visibility toggles appeared as unlabeled buttons with only a 0/1 value. Reorder controls used symbol names such as Reorder Photo rather than the action name. Several Settings switches, including Haptic Feedback and Live Activity Monitor, were also unlabeled. [Capture Bar before](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/capture-bar-before.png).

Visibility toggles now expose their localized action titles. Decorative action icons are accessibility-hidden, which also makes reorder controls use names such as Reorder Add Media and Reorder Scan Document. The shared Settings toggle row now exposes its title and explanatory hint.

The rebuilt app's Argent tree showed named switches and reorder controls. Add Media toggled from 1 to 0 and back to 1; the original preference was restored. Haptic Feedback and Live Activity Monitor exposed their names. Evidence is structural rather than a pixel comparison: [Capture Bar tree](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/capture-bar-accessibility-fixed.txt), [Settings tree](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/settings-accessibility-fixed.txt), [Capture Bar screenshot](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/capture-bar-labeled-fixed.png). VoiceOver speech output itself was not tested.

## Checks that passed

- Opened and cancelled audio import repeatedly. No error appeared, no attachment or recording was added, and the capture draft remained intact. No audio/video file was selected.
- Recording Controls help showed the Audio, Import Audio, and Keyboard Listening explanations. Dismissing it returned to the existing draft.
- Stats showed 0 recordings, 10 captures, 0 seconds, and 0 attachments. Pull-to-refresh preserved the totals and source counts. Landscape and portrait transitions preserved them and kept the page scrollable. [Portrait](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/stats-portrait.png) · [Landscape](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/stats-landscape.png).

## Validation and final state

The final signed Debug simulator build passed. [Build result](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/build-result.json). `git diff --check` and English/Turkish interpolation checks passed. These UI changes were verified with live failing/passing Argent flows and accessibility trees; no new unit tests or recorded e2e suite were added.

No capture was submitted, recording started, permission changed, or message sent. Audio import remained unverified beyond cancellation. Add Media visibility was restored, portrait orientation restored, recording controls collapsed, and the original draft and Toplantı Notları route preserved. Final launch returned to Turkish Capture with `-AppleLanguages (tr) -AppleLocale tr_TR -VoxScreenshotUnlocked -VoxAdaptiveNoAutofocus` and no seed flags.

[Restored Capture](../../artifacts/validation/ios-edge-qa-pass5-2026-11-08/restored-capture.png).
