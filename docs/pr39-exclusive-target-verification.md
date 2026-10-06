# PR39 exclusive capture targets — verification

Verified 2026-10-06 on local branch `feat/pr39-exclusive-capture-target`, based on PR39 commit `099fbfade7514db8e8f7876d16e048256a7d318f`. Changes are local and uncommitted; nothing was pushed or merged.

## Behavior

- One native **Directory / HTTP** choice per preset. Its configuration follows immediately below the chooser. Inactive directory settings and endpoint/Keychain references remain stored.
- HTTP composer Send requires no directory, does not resolve a directory library, and never enters note/audio/attachment exporters. It has a distinct receipt without a note URL. Accepted durable handoffs use the existing Capture allowance; failed preparation releases the reservation and preserves the draft.
- Directory Send writes the note without preparing or making an HTTP request.
- HTTP rejects binary attachments without deleting the draft. Attachment-only controls are hidden on iOS and Mac. Directory location settings remain stored but do not request location for HTTP.
- iOS/Mac recording exports and Watch transcript handoffs select the same exclusive target. HTTP never falls back to files. Failed HTTP payloads remain available in URL Deliveries.
- The Share extension remains directory-only. It blocks HTTP presets instead of routing them to a remembered directory, and explains how to use Capture or select a Directory preset.

## Passed gates

| Evidence | Result |
| --- | --- |
| Full `VoxboardShared` package suite | 1,018 XCTest cases and 10 Swift Testing cases; no failures |
| iOS app-hosted tests | 37 cases; no failures (HTTP/Directory routing, allowance behavior, attachment preservation, frozen settings, image preparation, rendering, Watch location policy) |
| Capture structure gate | 14 checker fixtures; three files within the 600-token section budget |
| Project contracts | Passed, including the intentionally regenerated governed manifest |
| macOS Debug build | Succeeded |
| Signed physical-iPhone Debug build | Succeeded |
| `git diff --check` | Passed |

Build and test logs are in `.derived/target-checks/` in this checkout. Package and composer regressions were observed failing before their fixes (`watch-target-red.log`, `location-target-red.log`, `routing-regression-red.log`).

## Native UI evidence

Dedicated simulator: **Vox PR39 Exclusive Targets QA**, `D8173EE4-E66F-43E3-916A-5D30F33D1AA2`, iOS 26.5. The unsigned simulator uses the existing Debug shared-container override, scoped to `/Users/codybontecou/dev/vox.md/.derived/pr39-target-ui/container`; physical-device data was not reset.

Artifacts are in `/Users/codybontecou/dev/vox.md/.derived/pr39-target-ui/`:

- Entered and saved the synthetic endpoint `https://example.invalid/ui-target-check`, switched to Directory, then back to HTTP and inspected the retained endpoint. Directory setup and HTTP endpoint configuration were mutually exclusive.
- Inspected light, settled dark, and largest accessibility text layouts. Screenshots include `http-adjacent-final.png`, `directory-config-final.png`, `http-dark-settled-final.png`, and `http-accessibility-final.png`.
- Sent synthetic text with **zero configured directories**. The draft cleared and the UI displayed **Saved for HTTP / Restore**, with no directory setup banner. `http-send-final.png` records this result.
- The recorded `pr39-http-send-no-directory` flow completed **two consecutive full replays**, each `ok: true`, five passed steps, zero failures/skips. Results: `send-replay-1.json`, `send-replay-2.json`.
- Captured and inspected video frames for endpoint entry and target switching. Clips are 30fps, not proof of sustained 60fps or release-device performance.
- The broader target-editor recording is diagnostic, **not a passing automated regression**: Argent 0.25.0 recorded a broad native `AXScrollArea` selector for a SwiftUI navigation row; replay tapped a different row and failed the next destination wait. The live editor checks passed, but `final-replay.json` has `ok: false`. Argent was not updated without consent.

## Physical device

Updated the existing `bontecou.Voxboard` app on **iPhone 17 Pro**, UDID `00008150-001405DA2188401C`, using scheme `Voxboard` and normal signing. `devicectl` installation and launch both succeeded. There was no uninstall or intentional app-data reset.

Logs: `.derived/target-checks/device/ios-device-{build,install,launch}.log`. A later optional process inspection timed out after the device connection became unavailable; it is not evidence of an app crash and does not establish continued process survival.

## Boundaries

No real endpoint, credential, or vault content was used for tests. Package/app-hosted transports are mocked; the native UI uses the reserved `.invalid` endpoint and verifies durable handoff, not server acceptance. Hardware Keychain lock/unlock, local-network/ATS, crash-boundary recovery, complete Watch execution, Mac runtime UI, and release performance remain release gates described in `issue-32-url-delivery.md`.
