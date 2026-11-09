# iOS exploratory edge-case QA, pass 4

Tested November 8, 2026 with Argent on the booted iPhone 18 Pro Max simulator, iOS 27.0, bundle `bontecou.Voxboard`. This pass covered Shortcuts & Control Center, surface pinning, model download/fallback/deletion, and auto-stop configuration. English process-language overrides and the existing screenshot unlock were used. No recording was started or capture submitted.

## Fixed: stale Control Center and widget summaries

After enabling a route in either pin editor and returning to Shortcuts & Control Center, the summary still said None. Reopening the pin editor showed the pin enabled. Changing the unrelated Action Button selection forced a redraw and revealed the saved names. Initial taps on row labels did not toggle the switches; the reproduction used switch gestures derived from the accessibility row frames and verified the resulting value.

The screen read UserDefaults while rendering, but changing pins did not change its observable state. It now stores and refreshes both displayed summaries on appearance, including after returning from a child editor.

[Enabled pin](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/control-center-pin-enabled.png) · [Stale parent summaries](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/pins-summary-stale.png).

On the rebuilt app, removing the last Control Center pin immediately changed its summary to None. Pinning Default and Toplantı Notları immediately displayed both names without touching another setting. Clearing those pins returned to None. Clearing the last widget pin also immediately returned its summary to None.

[Multiple pins reflected immediately](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/pins-summary-multiple-fixed.png) · [Both lists cleared](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/pins-cleared-summary-fixed.png).

## Fixed: missing-fallback warning with an installed fallback

Downloaded Tiny, then selected Make Automatic’s Fallback. The Tiny row correctly displayed Fallback and the description named Tiny, but the Automatic card still warned “Apple Speech unavailable; a downloaded fallback is required.” The warning ignored the installed fallback.

The card now states that the installed fallback is ready, with a neutral status and checkmark. When no installed fallback exists, the original warning remains. The new status has English and Turkish translations with matching model-name placeholders.

[Incorrect warning](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/installed-fallback-warning-before.png) · [Installed fallback recognized](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/installed-fallback-status-fixed.png).

Verification on the rebuilt app showed “Apple Speech unavailable; Tiny is ready as the fallback.” Deleting Tiny removed the fallback role, restored Get/Not installed, returned model storage to Zero kB, and restored the missing-fallback warning. Automatic remained selected.

[Warning restored after deletion](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/fallback-deleted-warning-restored.png).

## Other checks and limits

- Action Button selection changed to Toplantı Notları, then back to Default Route. Surface pinning did not change the active capture route.
- Tiny completed its download before the attempted Cancel tap; download completion and deletion were checked, cancellation was not established.
- Expanded auto-stop Advanced Options without its companion model installed. Capture-path controls, Pause Length, and On End of Speech remained inactive, consistent with the explanation that recordings use manual stop until the companion is downloaded. Existing values were preserved: enabled preference, all capture paths enabled, 0.75-second pause, Stop Recording. [Evidence](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/auto-stop-without-model.png).
- Native devtools reported a stale connection and were not used for evidence. Testing continued with Argent accessibility trees and gestures; no shared tool servers were restarted.

The signed Debug simulator build passed with the existing RouteQuickActionsView concurrency warning. [Build log](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/build.log). `git diff --check` and English/Turkish interpolation checks passed. These presentation fixes were verified through live failing and passing UI flows; no new unit tests or saved e2e suite were added.

Actual audio transcription, hardware Action Button use, installed system widgets/controls, download cancellation, and physical-device behavior remain outside this pass. No permissions changed. Temporary model files and pin selections were removed; Action Button returned to Default Route. The original capture draft and Toplantı Notları selection survived the signed update and restarts. The app was returned to Turkish Capture using `-AppleLanguages (tr) -AppleLocale tr_TR -VoxScreenshotUnlocked -VoxAdaptiveNoAutofocus`, without seeding flags.

[Restored Capture](../../artifacts/validation/ios-edge-qa-pass4-2026-11-08/restored-capture.png).
