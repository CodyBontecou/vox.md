# Preset quick access — implementation and validation

## Status (September 7, 2026)

**Foundation implemented and locally verified; user-facing quick access is not complete.**
The remaining work is the iOS/Mac emoji editors and display adoption, pin/reorder
settings, iOS capture row, and dedicated configurable preset widget. Existing
Quick Capture and Quick Record widgets retain their purposes.

### Identity

`CapturePreset`, `CapturePresetProfile`, and `CapturePresetReference` carry optional
`emoji`, retaining `symbolName`, stable IDs, and legacy storage keys. Missing/null
emoji decodes nil; nil is omitted on encode. Persistence is lossless, including
choices an older Unicode runtime cannot recognize.

Use `CapturePresetEmoji.normalized(_:)` at editor/display boundaries. It accepts
one complete emoji grapheme after edge whitespace trimming, including flags,
keycaps, skin tones, and ZWJ families; it never truncates Unicode scalars. This is
structural validation, not an emoji catalog or a glyph-availability guarantee.
`CapturePresetIconView(symbolName:emoji:)` renders emoji text or the retained SF
Symbol (blank symbol falls back to `waveform`). It is decorative; the enclosing
control supplies the preset name and selection accessibility. Watch transport
and system-image-required surfaces retain their existing symbol fallback.

### Ordered pins

`CapturePresetQuickAccessStore` stores only ordered stable IDs under the shared
App Group key `capture.presets.quickAccess.orderedIDs.v1`. It never changes preset
enabled/default/keyboard/capture-selection preferences.

- An absent preference seeds once from the first five unique enabled profiles.
  Manual writes have no five-item limit and usage never changes ordering.
- Missing/unreadable authoritative profiles defer initialization. A successfully
  read empty/all-disabled set seeds explicit `[]`, which never reseeds itself.
- Explicit empty survives reloads. Malformed storage fails closed until a
  deliberate valid write; reads do not repair it or invent a default.
- Resolution deduplicates stable-first and returns only existing enabled profiles
  in saved order. Disabled pins are hidden without losing their saved placement.
  Deliberate writes with the **full** current profile set prune deleted IDs while
  retaining disabled ones. Do not supply an enabled-only subset to a write.
- `CapturePresetQuickAccessPreferences` is an injectable main-actor observable
  wrapper. Hosts must reload on appearance/foregrounding and after preset or
  externally observed defaults edits. Widget callers use the read-only resolver;
  they do not seed. UserDefaults readback is not an instant cross-process or
  durable-flush guarantee.

### Selection and launch safety

Same-ID `CaptureDraft.selectVox` is a full no-op. A different ID keeps content,
assets, draft/request IDs and recording receipts while clearing one-off routing
and the previous preset/location snapshot. Explicit “Use Preset defaults” remains
separate. Mac draft selection no longer changes the global recording/keyboard
preset.

`QuickCaptureViewModel.selectVox(_:) -> Bool` reports only real changes.
`canChangeCaptureRoute` guards preset/route controls and external launch/start
paths. App-installed live recorder readers, shared media state, and request
operation tokens cover recording, transcription/import, send/location/image work,
and asynchronous permission/start boundaries without a view-only observation
race. Existing queue/recording snapshot and lease behavior is unchanged.

An explicit different widget preset asks before rerouting a nonempty draft.
The complete incoming source/text/URL/input/route value stays pending until
acceptance. Cancel leaves it unapplied; acceptance revalidates current
availability, draft/request/route/privacy identity and ownership and applies once.
Typing and attachments added while deciding are retained. Empty/same-ID launches
remain one tap. Stale explicit presets do not silently select another preset;
busy launches are rejected rather than queued to reroute later.

The legacy immediate Quick Record path still uses its existing independent
immutable recording route, but no longer changes the composer draft. Its iOS
transcribing subtitle still derives its name from the draft preset; the capture
UI follow-up should display the recording origin's name without rerouting the
draft to fix the label.

## Cycle 1 verification

Toolchain: Xcode 26.6 (17F113), Swift 6.3.3. Checks ran serially from clean local
commits, without updating dependency pins, signing/provisioning requests, pushes,
release actions or physical-device interaction. Existing caches were reused, not
copied. Unrelated caches/processes/simulators were not removed or stopped.

| Gate | Actual result |
| --- | --- |
| `./scripts/test-project-contracts.sh` | Exit 0; 10 launch-gate unit tests, 95 contract tests, 187 governed files/98 fixtures and project contracts passed |
| `./scripts/test-capture-view-structure.sh` | Exit 0; 14 parser fixtures and actual capture boundaries, unchanged 600-token budget |
| `swift test --package-path Packages/VoxboardShared --skip-update --disable-automatic-resolution -j 2` | Exit 0; 853 tests, including all new identity/pin/queue-ownership tests (baseline 782) |
| `swift run --package-path Packages/VoxboardShared --skip-update --disable-automatic-resolution -j 2 VoxboardPersistenceFixtures --validate` | Exit 0; committed fixture validation, no regeneration |
| Unsigned `xcodebuild test`, scheme `VoxboardTests`, dedicated iOS 26.5 simulator | Exit 0; 176 tests, including 21 launch-safety tests and 5 `QuickCaptureRenderingTests`; app/widget/keyboard/share/embedded Watch targets compiled |
| Unsigned `xcodebuild build`, scheme `Voxboard Mac`, macOS destination | Exit 0 |
| Unsigned `xcodebuild test`, scheme `Voxboard Watch Tests`, dedicated watchOS 26.5 simulator | Exit 0; 15 codec/fixture tests |
| Preservation against base `234dd57` | No persistence/portable fixture, Watch transport, dependency pin, Rust/Android implementation or toolchain changes |

Exact argument arrays, source HEAD/clean status, exits, full logs, lane reports
and result bundles are retained locally under
`/tmp/vox-md-presets-fleet-loop/cycle-1/`. Xcode commands used
`-disableAutomaticPackageResolution -onlyUsePackageVersionsFromResolvedFile`,
`-jobs 2`, `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, empty signing
identity/team, and serial simulator testing. The iOS and Watch result bundles
are `integrated-ios.xcresult` and `integrated-watch.xcresult`.

### Investigated failures, not hidden skips

The clean base already failed portable gates: two recent persisted keys lacked
inventory mappings, and the already-tracked zero-audio diagnostic document was
absent from the governed manifest. These were narrowly reconciled. All 271
portable capability records and fixture bytes are unchanged; only inventory
metadata/provenance and exact manifest attestations changed. The native launch
source gate now requires a complete validated handoff, guarded route setters and
exactly the ID-bound Mac consent alert, while rejecting piecemeal mutations and
unrelated accessory-tool modals. Failed attempts remain in the local receipts.

### Evidence limits and pre-ship gates

Hosted tests mount real SwiftUI canvas/toast/OCR/mic-hint hierarchies; the emoji
lane also ran real offscreen Mac raster comparisons. This is not full-app
interaction, widget-host configuration/refresh, real VoiceOver, or a demonstration
of cursor/keyboard preservation when tapping the forthcoming row. New consent
alert interaction across iOS/Mac windows still needs UI validation. Argent device
interaction tools were unavailable in this session; no interactive visual pass
is claimed. Remaining UI lanes must add their own mounted rendering and
keyboard-sized/large-text/RTL evidence and report tool limitations honestly.

**Physical-device cold-launch and recording/keyboard/widget QA remain required
before shipping and were not authorized or run by this fleet.** Simulator tests
do not prove the device-only SwiftUI metadata boundary is safe. See
[capture-view-regression-tests.md](capture-view-regression-tests.md).
