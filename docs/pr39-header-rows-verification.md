# Custom header rows

The shared iOS/Mac HTTP editor now provides paired **Header / Value** text fields, **Add Header**, individual remove controls, and **Save Headers**. At accessibility text sizes the paired fields stack vertically. Return advances from Header to Value, then dismisses the keyboard. Row identity survives additions/removals.

Header values remain ephemeral until the existing endpoint-bound Keychain save succeeds. No new plaintext preset/queue persistence, credential migration, transport behavior, or routing changes were introduced. Removing the last header leaves a blank starter row; saving that row clears custom headers without intentionally removing the bearer token. Blank placeholders do not count as unsaved credential edits. Invalid/duplicate names, unnamed values, CR/LF injection, and existing count/size restrictions fail validation. Colons inside values are preserved.

## Evidence (2026-10-06)

- 12 new `URLDeliveryHeadersDraftTests` passed: empty/load/round-trip, stable identity, removal, whitespace, colon/empty values, duplicates, unnamed values, invalid/forbidden names, CR/LF, limits, and unsaved-edit detection.
- 26 existing composer/rendering regression cases also passed (38 app-hosted tests total).
- iOS simulator and Mac builds passed. A normal signed generic iOS device build passed.
- Project contracts (131 Python tests), capture structure gate (14 fixtures / 600-token section budget), and `git diff --check` passed.
- Native simulator: edited paired fields, Return-key focus, Add Header, duplicate rejection, remove controls, light/dark and accessibility-extra-large layouts inspected. Artifacts: `/Users/codybontecou/dev/vox.md/.derived/pr39-header-ui/` (`rows-empty.png`, `duplicate-error.png`, `rows-dark.png`, `rows-large.png`, `header-row-editing.mp4`). The recorded input-controls flow completed one full replay: `controls-replay.json`, `ok: true`, 19 passed, no failures/skips. It is fixture/device-bound and does not prove credential persistence.

Logs: `.derived/header-checks/` in this checkout.

## Verification limits

Native Keychain save/reload was attempted but is **not verified**: the simulator build/instrumentation returned Security status `-34018` (missing entitlement). An isolated ad-hoc entitlement experiment failed to launch and was discarded; the original Xcode-built simulator app was reinstalled without uninstalling/resetting data and the final controls flow passed. No security fallback or production signing change was added.

The initial physical-device attempt failed because Xcode omitted the destination and CoreDevice reported error 4016 (trusted connectivity/services unavailable). On the subsequent user-requested retry, the normal signed Debug build, installation, and launch all succeeded on **iPhone 17 Pro**, `00008150-001405DA2188401C`, scheme `Voxboard`, bundle `bontecou.Voxboard`. No uninstall or app-data reset was performed. Retry logs: `.derived/header-device-retry/ios-device-{build,install,launch}.log`. The header-row build is now the latest confirmed physical-device deployment; hardware Keychain save/reload was not part of the deployment check.

Changes are local and uncommitted in `feat/pr39-exclusive-capture-target`. Main and unrelated worktrees are untouched; no push/merge or Argent update was performed. No real credentials or endpoint were used for QA. Video is a 30fps interaction capture, not a release-performance measurement.
