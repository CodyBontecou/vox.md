# iOS exploratory edge-case QA, pass 6

Tested November 8, 2026 with Argent on iPhone 18 Pro Max, iOS 27.0, bundle `bontecou.Voxboard`. This pass covered route-specific quick-action exhaustion/reset, live timestamp preferences, cancellation of route-send confirmation, and empty URL-delivery recovery.

## Results

No new reproducible bug was found. No application source changes were needed in this pass.

- Removed all 21 pinned quick actions from the Default route. The zero-action state remained usable, showed the empty-state explanation, and kept all actions available under More Actions. [Empty route actions](../../artifacts/validation/ios-edge-qa-pass6-2026-11-08/empty-route-actions.png).
- Used the route-specific Reset. It restored the inherited 21-action row and disabled Reset again. The selected Toplantı Notları route retained its separate six-action customization.
- Changed Timestamp Format from 12-hour to 24-hour and returned to Capture. The live chip changed to a leading-zero time (09:01), without adding text to the draft.
- Enabled Confirm Route Sends and tapped Send. A confirmation named Toplantı Notları. Dismissing the prompt preserved the exact original draft and route; no capture was submitted. [Confirmation](../../artifacts/validation/ios-edge-qa-pass6-2026-11-08/send-confirmation.png).
- Opened URL Deliveries with no pending receipts. Repeated toolbar refreshes and pull-to-refresh preserved the empty state, with no error or navigation failure. [Refreshed empty state](../../artifacts/validation/ios-edge-qa-pass6-2026-11-08/url-deliveries-refreshed.png).

## Final state and limits

Restored Timestamp Format to 12-hour and Confirm Route Sends to off; Review Before Adding remained off and the pinned rail remained Left. [Restored settings](../../artifacts/validation/ios-edge-qa-pass6-2026-11-08/settings-restored.png). The temporary Default-route quick-action override was removed by Reset. The original Turkish launch, exact capture draft, selected Toplantı Notları route, six custom quick actions, portrait orientation, and collapsed recording controls were verified after relaunch. No seed flags were used. [Restored Capture](../../artifacts/validation/ios-edge-qa-pass6-2026-11-08/restored-capture.png).

No recording, capture submission, permission change, or message send occurred. Pending-delivery retry/discard behavior was not exercised because the queue was empty. This pass used live Argent checks; no new automated suite was recorded and no build was required because application source was unchanged.
