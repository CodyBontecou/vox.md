# Android QA pass 2 — fixes verified

Implemented both findings from [the exploratory report](../report.md).

## Link admission and draft durability

A shared `CaptureWebLink` validator now requires a complete HTTP(S) URL with a host, trims whitespace, and normalizes scheme case. The link dialog, clipboard insertion, external capture entry, repository writes, and stored draft reads use it. Repository validation remains strict. The ViewModel retains the last valid link (or no link) when given invalid input, allowing subsequent text edits to reach durable storage.

Live Argent verification on `emulator-5556` (API 36): `https://` leaves Add disabled; `  HTTPS://example.com/qa  ` is accepted as `https://example.com/qa`. Attached that link, entered `QA fixed draft`, restarted the app, and verified both text and normalized link survived without a save error.

- [Hostless link rejected](hostless-link-disabled.png)
- [Text and normalized link after restart](normalized-link-and-text-after-restart.png)

## Landscape recording

Short landscape windows now use two columns: timer/waveform on the left and transcript/result/actions on the right. The covered Capture editor clears focus and hides the keyboard during active or paused recording.

Live Argent verification: started recording while the editor keyboard was open; keyboard disappeared. Rotated active recording to landscape and verified Cancel, Stop, and Pause visible. Paused in portrait, rotated again, and verified Cancel, Stop, and Resume visible with no keyboard overlay.

- [Active landscape recording](active-landscape-controls.png)
- [Paused landscape recording](paused-landscape-controls.png)

Argent landscape taps did not dispatch reliably, including after refreshing device services. Therefore live evidence establishes visibility; the Compose instrumentation test establishes control callbacks and vertical bounds at 900 × 360 dp. It exercises Pause, Resume, Stop, and Cancel. This limitation is excluded from the app findings.

## Automated verification

- Debug app and instrumentation APK build: passed. [Build log](build.log).
- `CaptureWebLinkTest`: 2 JVM tests passed.
- `ExternalCaptureRequestTest`: 16 JVM tests passed.
- 17 Android instrumentation tests passed, including 3 new link/durability/landscape tests and existing rotation, Capture Bar, preset, and transcript coverage. [Instrumentation log](instrumentation.log).
- `git diff --check`: passed.

The durability regression uses the actual repository, verifies direct invalid saves still fail, then supplies an invalid link through the ViewModel and reloads persisted text and the prior valid link. It restores the original draft afterward.

## Cleanup and limits

Removed temporary QA text and link. Canceled the 42-second QA recording and deleted only that session (`b997784a`); the queue reported “Recording deleted” and “No Recordings Yet”. Portrait orientation restored. No captures were sent and no URL deliveries triggered. Existing notes, history, routes, and templates were preserved. Emulator services remain running.

The emulator briefly displayed “Process system is not responding” during cleanup; it recovered. Tooling also returned stale accessibility trees, requiring device-scoped service refreshes. No hardware audio-quality or network-delivery claims are made.
