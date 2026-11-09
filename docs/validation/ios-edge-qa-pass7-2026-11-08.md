# iOS exploratory edge-case QA, pass 7

Tested November 8, 2026 with Argent on iPhone 18 Pro Max, iOS 27.0, bundle `bontecou.Voxboard`. New coverage focused on internal-link validation recovery and filename searching, plus deeper due-time adjustments across midnight.

## Fixed: invalid custom internal link hides the vault list

Open Internal link, enter `../escape.md` in Write my own, and tap Insert. The formatter correctly rejects traversal, but the picker replaced every valid vault note with “The wiki-link target is not safe.” Clearing all input left the notes hidden; reopening the sheet was required to recover. [Before, after clearing input](../../artifacts/validation/ios-edge-qa-pass7-2026-11-08/invalid-link-hides-vault-before.png).

`CaptureInternalLinkPicker` reused the vault-loading error state for insertion validation. It now keeps a separate insertion error and displays it in a dismissible alert. Vault-loading errors retain their existing presentation. No validation rules were relaxed, and the existing localized Error/OK strings are reused.

On the signed rebuilt app, the same traversal input immediately showed the alert. Dismissing it preserved both the rejected input and the vault list. Selecting the Unicode-named `Inbox/Sam’in kitap önerileri-2.md` then inserted the correct extensionless wiki link without reopening the picker. Undo restored the exact original capture draft.

[Validation alert](../../artifacts/validation/ios-edge-qa-pass7-2026-11-08/invalid-link-alert-fixed.png) · [Vault notes still available](../../artifacts/validation/ios-edge-qa-pass7-2026-11-08/vault-list-preserved-fixed.png) · [Successful note insertion](../../artifacts/validation/ios-edge-qa-pass7-2026-11-08/unicode-note-inserted.png).

## Other checks that passed

- Searching `INBOX` matched the three notes in Inbox regardless of case. Replacing it with `.*[]../` produced zero results, treating punctuation literally. Clearing and closing search restored all seven notes. Cancelling preserved the draft.
- Selected Tomorrow (November 9), enabled Time, and applied fifteen +1h adjustments from 9:12 AM. Both calendar selection and insertion label advanced to November 10 at 12:12 AM. Applying −15m returned to November 9 at 11:57 PM. Choosing Today preserved 11:57 PM while moving the date to November 8. Disabling Time removed the time from the label. Cancellation inserted nothing. [Midnight rollover](../../artifacts/validation/ios-edge-qa-pass7-2026-11-08/due-time-crosses-midnight.png).

## Validation and final state

Signed Debug simulator build passed with three existing actor-isolation warnings outside the changed picker. [Build result](../../artifacts/validation/ios-edge-qa-pass7-2026-11-08/build-result.json). `git diff --check` passed. The UI-state fix was verified through the original failing and passing live Argent path, including a successful insertion after rejection and undo; no new unit test or recorded e2e suite was added.

No capture was submitted, file written by delivery, recording started, permission changed, or message sent. No global settings changed. Original draft, selected Toplantı Notları route, six custom quick actions, collapsed controls, and Turkish UI were verified after relaunch without seed flags. [Restored Capture](../../artifacts/validation/ios-edge-qa-pass7-2026-11-08/restored-capture.png).

This pass did not cover inaccessible-vault errors, large-vault indexing, time-zone/DST transitions, or physical devices.
