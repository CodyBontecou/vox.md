# Cycle 1 audio filename core report

## Result

Implemented normal per-`CapturePreset` generated-audio naming in the Swift package on `goal/hans-c1-audio-naming-core`, based on `ff078d8a323d886211ea33869e1ce45c9a6ba614`.

Implementation commits:

- `55a6b76 feat(capture): name generated audio per preset`
- `7445d6f test(capture): isolate named recording delivery`

No iOS, Mac, Watch app, Xcode project, fixture, generated-source, dependency-lock, signing, or provisioning files were changed.

## Implemented

- Added `CapturePreset.audioFilenameTemplate`.
  - New and legacy presets default to `""`.
  - Empty values are omitted when encoded.
  - The field round-trips independently from `watchRecordingSettings.filenameTemplate`.
- Added `CapturePresetAudioFilename` and an explicit identity/date/preset/original/calendar/locale/time-zone context.
  - Supports `{timestamp}`, `{date}`, `{time}`, `{YR}`, `{id}`, `{id8}`, `{preset}`, and `{original}`.
  - A user-typed extension is removed; the actual copied or encoded extension is applied and sanitized.
  - Separators, traversal input, and controls cannot create another path component.
  - Normal rendering preserves complete extended grapheme clusters and bounds the base name to 180 UTF-8 bytes.
  - Empty/unsafe output uses a deterministic contextual fallback.
  - Unknown tokens deliberately remain literal and pass through normal filename sanitization.
- Extracted the existing Watch Recording Only token rendering into the shared implementation while retaining its default template, `.m4a` reservation behavior, and historical scalar-level sanitization (including its established ZWJ result).
- Applied normal preset naming before staging for:
  - unified Capture transcript plus retained audio;
  - recording-only audio routed through normal Capture delivery.
- Added optional, source-compatible filename-context seams to the legacy direct audio exporter and checkpointed delivery API. Existing callers that do not supply context retain transcript-derived automatic names exactly.
- Reused durable pending/failed `CaptureInbox` requests on configured retries. The claimed persisted request, staged relative path, collision suffix, and bytes are reused rather than creating a second staged name.
- Left arbitrary user-selected media naming untouched.

## Collision and retry policy

The implementation keeps existing conventions rather than adding a new namespace:

- `CaptureAssetStager` and direct legacy export continue to choose `-2`, `-3`, and so on.
- The chosen staged filename is part of the request persisted before destination delivery.
- Pending/failed retry loads that exact request and its staged asset.
- Existing valid direct-export checkpoints win over re-rendering, so a changed context cannot invent a second attachment.
- Conversion still prefers `.m4a`; conversion failure re-renders with and copies the real source extension.

## Verification

All CPU-heavy commands used the required thermal guard, locked dependency resolution, `-j 2`, and the isolated scratch path `/private/tmp/vox-md-hans-feedback-fleet-loop/cycle-1/audio-swiftpm`. Disk stayed above the 12 GiB floor.

| Check | Result | Evidence |
|---|---:|---|
| Focused renderer tests (`CapturePresetAudioFilenameTests`) | PASS, 8 tests | `/private/tmp/vox-md-hans-feedback-fleet-loop/cycle-1/audio-focused-renderer-rerun.log` |
| Focused model/Watch/checkpoint/configured-pipeline tests | PASS, 87 tests | `/private/tmp/vox-md-hans-feedback-fleet-loop/cycle-1/audio-focused-pipelines.log` |
| Persistence fixture validation | PASS | `/private/tmp/vox-md-hans-feedback-fleet-loop/cycle-1/audio-persistence-validate.log` |
| Full `VoxboardShared` SwiftPM suite | PASS, 913 XCTest + 10 Swift Testing tests | `/private/tmp/vox-md-hans-feedback-fleet-loop/cycle-1/audio-full-swift-test-rerun.log` |
| `git diff --check` | PASS | local command output |

Persistence command:

```sh
swift run --package-path Packages/VoxboardShared \
  --scratch-path /private/tmp/vox-md-hans-feedback-fleet-loop/cycle-1/audio-swiftpm \
  --skip-update --disable-automatic-resolution -j 2 \
  VoxboardPersistenceFixtures --validate
```

Full-suite command:

```sh
swift test --package-path Packages/VoxboardShared \
  --scratch-path /private/tmp/vox-md-hans-feedback-fleet-loop/cycle-1/audio-swiftpm \
  --skip-update --disable-automatic-resolution -j 2
```

The first full-suite attempt exposed one new test using the process-global metered app pipeline: after preceding tests consumed its shared allowance, that test received no attachment (2 assertions failed). The test was corrected to inject an isolated pipeline, its focused rerun passed, and the complete clean-commit suite then passed. No production behavior was weakened to address the test isolation issue.

## Integration notes

- Cycle-2 iOS/Mac preset settings can bind directly to `CapturePreset.audioFilenameTemplate`; no migration is needed.
- Unified Capture APIs synthesize context from their stable request/transcript identity when no explicit context is supplied.
- Platform direct voice-note call sites were intentionally not edited in this core lane. When those owned files are updated, pass a recording-time `CapturePresetAudioFilenameContext` through `CheckpointedAudioDelivery.deliver` to opt into the new template. Omitting it preserves legacy naming.
- Watch Recording Only continues to use `watchRecordingSettings.filenameTemplate`; do not point that UI at the new normal field.
- App-hosted unsigned iOS/Mac/Watch builds remain coordinator/integration verification; this package-only lane did not alter or invoke platform call sites.
