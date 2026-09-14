# Android visual parity evidence

Status: **captured, not yet human-approved**

`visual-parity-manifest.json` is the authority for every retained screenshot and motion clip, its dimensions, capture metadata, exact byte count where applicable, SHA-256, comparison method, and known limitations. `./gradlew validateVisualParityEvidence` fails when an artifact changes, disappears, gains an unsafe path, appears outside the closed PNG/MP4 inventories, or claims approval without the corresponding policy change.

## Deterministic stories

The debug-only `md.vox.android.VisualStoryActivity` renders production Compose surfaces with fixed content and identifiers:

1. `01-quick-capture`
2. `02-history`
3. `03-settings`
4. `04-models`
5. `05-capture-presets`
6. `06-app-language`
7. `07-live-recording`
8. `08-vault-repair`
9. `09-history-empty`
10. `10-history-folder-repair`
11. `11-recording-paused`
12. `12-recording-failed`
13. `13-upgrade-pending`
14. `14-upgrade-active`
15. `15-loading`
16. `16-upgrade-quota-reached`
17. `17-upgrade-offline`
18. `18-recording-quota-reached`
19. `19-recording-interrupted`
20. `20-history-unknown-outcome`
21. `21-history-permanent-failure`

It is exported only from the debug manifest. The release manifest does not contain the activity.

## Retained matrix

- API 35 phone: all seven stories in dark, light, 200% text, and Arabic RTL
- API 35 phone: all seven recovery/empty/recording/purchase state stories in dark, light, 200% text, and Arabic RTL
- API 35 phone: all seven loading/offline/quota/interruption/terminal-failure resilience stories in dark, light, 200% text, and Arabic RTL
- API 35 Pixel Tablet profile: all seven stories in dark landscape
- API 35 7.6-inch foldable profile: all seven stories while opened, Quick Capture and live recording while half-opened, and Quick Capture while closed
- API 35 phone: Quick Capture constrained to the upper 1080×1187 split-screen pane with Android Settings in the lower pane
- API 35 Pixel Tablet profile: Quick Capture, Settings, and live recording in a 776×1380 freeform window, plus Settings after an explicit resize to 1760×1050
- API 35 phone motion: fresh-install vault setup through the system document-tree picker into the production composer, plus composer → Settings → Models → back → History navigation
- Canonical iOS comparison: Quick Capture, Settings, Models, and Capture Presets

The phone, state, and windowing files were captured at scale 1.0 through Argent. Argent's simulator server exited before becoming ready on the original headless tablet and foldable sweep, so those earlier screenshots use Android's lossless `screencap` path; that fallback is recorded in the manifest. The later tablet freeform run used Argent successfully and records exact task bounds for every capture.

The state contact sheets live under `goldens/states/`; the resilience contact sheets live under `goldens/resilience/`. Together they expose loading, folder repair, empty history, paused/failed/interrupted recording, quota and offline billing, ambiguous/permanent provider outcomes, and pending/active entitlement surfaces. The 200% text sweeps are paired with instrumentation that scrolls to and exercises the recovery, quota, offline, interrupted-recording, History, and purchase controls; a static screenshot is not treated as proof that below-fold controls are reachable. Focused accessibility instrumentation also verifies polite TalkBack announcement semantics on 11 state changes and labeled, clickable, scroll-reachable Switch Access targets with at least 48 dp accessibility touch bounds across 12 recovery surfaces. Actual human TalkBack and Switch Access traversal remains an approval gate.

The two H.264 production motion clips live under `motion/`. Argent captured them at 1080×2400 and 30 fps with touch indicators, then removed static dead time. Sampled-frame inspection confirmed the intended routes and did not reveal clipping, theme flashes, or broken intermediate states. Their exact files and flow metadata are hash-bound, but `reviewStatus` remains `unreviewed` until a human completes full-speed and frame-by-frame review; these two paths are not a substitute for the complete interaction matrix.

## Reproducing one story

Build and install the debug application, then launch an exact story:

```sh
cd apps/android
ANDROID_HOME=/path/to/android-sdk ./gradlew :app:assembleDebug
adb -s emulator-5556 install -r app/build/outputs/apk/debug/app-debug.apk
adb -s emulator-5556 shell am start -W \
  -n md.vox.android/.VisualStoryActivity \
  --es story 01-quick-capture \
  --ez dark true
```

Capture at the device's full native resolution. A recapture is a reviewed evidence update: regenerate the affected contact sheet and diagnostic diff, update the manifest hashes, dimensions, byte counts, and timing metadata, run the focused visual instrumentation tests, and run `validateVisualParityEvidence`.

Direct iOS-to-Android pixel comparison is expected to report a dimension mismatch because the source images are 1206×2622 and the phone captures are 1080×2400. The normalized diffs are diagnostic only. They help reveal missing content, hierarchy changes, clipping, typography, and control placement; they do not establish pixel identity or product approval.
