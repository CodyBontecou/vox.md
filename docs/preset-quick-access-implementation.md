# Preset quick access — implementation and validation

## Status (September 8, 2026)

**Bounded implementation complete and locally verified; hardware/pre-ship QA is not complete.**
iOS/Mac emoji editors and display adoption, iOS pin/reorder settings, the pinned
capture rail, and a dedicated configurable Capture Presets widget are integrated.
Existing Quick Capture and Quick Record widgets retain their purposes. The preset
fleet stops after cycle 2; unrelated Siri and task-spacing work are separate.

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
immutable recording route, but no longer changes the composer draft. Cycle 2
corrects the iOS transcribing subtitle using the recording's immutable origin
identity, retained across stop/queue handoff and cleared with transcription state.
Unknown origin uses generic copy, never the current draft's preset name.

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

Cycle 1 hosted tests mount real SwiftUI canvas/toast/OCR/mic-hint hierarchies;
the emoji lane also ran real offscreen Mac raster comparisons. Those foundation
results alone did not exercise the new UI, system touches, or consent alerts.
Cycle 2 component/runtime evidence below adds to, rather than replaces, those
limits. Argent device interaction tools remained unavailable.

**Physical-device cold-launch and recording/keyboard/widget QA remain required
before shipping and were not authorized or run by this fleet.** Simulator tests
do not prove the device-only SwiftUI metadata boundary is safe. See
[capture-view-regression-tests.md](capture-view-regression-tests.md).

## Cycle 2 surfaces

- **iOS Settings → Capture Presets:** visible Pin/Unpin buttons and native Edit /
  draggable pinned order. Disabled pins remain editable with a hidden-until-enabled
  label. Writes read full persisted profiles; stale reorder offsets and failed
  persistence are refused visibly. Confirmed deletion deliberately prunes retired
  pins. Pinning never changes enabled/default/keyboard selection.
- **Symbols / Emoji:** native text input, preview and explicit Apply; invalid or
  partially composed input never truncates or overwrites the saved choice.
  Symbols explicitly clears emoji, retaining the symbol fallback. Mac's sheet
  stages both values until Apply; Cancel leaves the preset untouched.
- **Capture Bar (cycle 2):** stored-order icon buttons above the existing
  preset/route/send controls, horizontal overflow without a pin cap, no empty
  strip, and >=44pt targets. Selected traits use the exact draft ID. Selection
  calls the existing guarded VM API without replacing or refocusing the Markdown
  editor. iOS native menu titles include emoji because UIKit menu image slots
  cannot render Text.
- **Capture Presets widget:** AppIntentConfiguration, default Follow Capture Bar
  or six explicit ordered Custom slots per instance. The SDK exposes entity
  arrays but no guaranteed reorder editor, so named positions make order explicit.
  Small uses the first position; medium shows up to six and large up to eight
  Follow pins (Custom has six). Empty interior slots and unavailable targets never
  borrow the next preset. Query results reconstruct requested identifier order.
- **Widget snapshots:** immutable configuration/identity values, fixed slot/preset
  IDs, URLComponents-built `voxboard://capture?preset=<id>&source=widget` links.
  No global selection lookup in rendering, auto-send, or surprise recording.
  Setup/Fix states retain the expected stale ID or offer app/settings guidance.
  Successful changed name/icon/availability/profile-order or pin/seed writes
  request only `VoxboardCapturePresetsWidget`, debounced 250ms. A 15-minute
  recovery timeline is requested; actual scheduling belongs to WidgetKit.
- **Fixed-size accessibility layout:** large-type medium widgets keep all six
  positions using icons/Fix labels; large keeps readable native-scaled names;
  small uses concise text and a Settings glyph. No font squeezing or target
  reassignment. Names/repair instructions remain in accessibility when text is
  intentionally ellipsized. New copy is localization-ready English; translation
  and language-specific UI review were not part of this bounded fleet.

## Cycle 2 verification

Four isolated lanes were collected and merged serially without conflicts. No
coordinator repository edits occurred while lanes ran. Unrelated task-spacing
edits on main were left untouched until their owner committed `0cb4537`; that
clean descendant became the integration base. Its four files remain unchanged
by this fleet. No fleet fetch/push, dependency-pin, signing/provisioning, release,
account, physical-device, or Watch transport action was performed.

| Gate | Actual result |
| --- | --- |
| Project contracts | Exit 0; 10 launch-script tests, 95 contract tests; 187 governed files/98 fixtures, 271 capability records unchanged |
| Capture structure | Exit 0; 14 parser fixtures and actual concrete sections, unchanged 600-token budget |
| Normal shared package suite, locked cached dependencies, `-j 2` | Exit 0; **895 tests** (18 widget tests added here; 24 independent task-spacing tests retained) |
| Persistence executable `--validate` | Exit 0; no fixture regeneration |
| Unsigned full `VoxboardTests` on a new dedicated iOS simulator | Exit 0; **209 tests**, including all 33 new cycle-2 methods and existing launch-safety tests; app/widget/embedded Watch targets compiled |
| Unsigned `Voxboard Mac` build | Exit 0 |
| Dedicated Watch codec suite | Exit 0; **15 tests** |

Exact command arrays, source HEAD/clean status, exits, logs and result bundles
live under `/tmp/vox-md-presets-fleet-loop/cycle-2/`. `matrix.py` runs the normal
matrix, serially using the existing main caches without copying build trees;
`integrated-fixed-*` records the successful post-fix host checks. `final-*`
receipts/result bundles record the full repeat from the final documentation HEAD.
All Xcode builds disable signing and automatic package resolution. Disk remained
sufficient; no unrelated caches, processes or simulators were removed/stopped.

### Failures investigated and retained

The initial iOS compile found a missing Combine import for main-RunLoop defaults
delivery. The next full hosted run caught a real small-widget setup overflow at
accessibility5; replacing the extra Settings text line with a Settings glyph
preserves native text size and the viewport. Tests also incorrectly inferred
rows from equal cell top edges (LazyVGrid centers unequal-height cells), and
compared a busy-action draft while a prior successful switch's autosave advanced
its timestamp. The revised assertions use explicit row positions and drain that
prior autosave; all containment, order, full draft-equality and cursor/focus
checks remain. No fixtures or frozen/source contracts were weakened.

Failed logs and bundles are retained. Xcode additionally timed out collecting
verbose simulator diagnostics after 600 seconds; subsequent tests use the
supported `-collect-test-diagnostics never`. This disables sysdiagnose collection,
not tests, failure reporting, logs or retained XCTest image attachments.

### Post-cycle compact rail refinement

Following product review, the horizontal Capture Bar strip was replaced by a
compact floating stack anchored above the selected-preset control. Its default
is the physical left edge; the Capture Bar setting described below can move only
the alternatives rail to the physical right edge. Stored order rises from the
controls, keeping the highest-priority pin nearest the bottom. The selector
itself represents the selected preset, so the expanded stack shows only
alternatives rather than repeating that icon. Each alternative remains a 14pt
icon inside an independent 44pt interaction target. Overflow scrolls vertically,
while an empty stack consumes no composer width.

The selected-preset control and stack are one disclosure interaction. Fresh
installs show only the selected preset, its name, and the two-arrow control. A
tap spring-animates the borderless icon stack with a bottom-anchored scale and
fade; Reduce Motion makes the change immediate. It overlays the leading edge
without a full-height divider, so the editor's frame and Markdown layout remain
identical in both states. The choice persists
in standard app preferences under `capture.presets.quickAccess.railExpanded.v1`.
Touch-and-hold still opens the
complete native preset menu, and an empty pin list retains the menu's ordinary
tap behavior, so unpinned presets remain reachable.

A follow-up critical pass found that the preload's full-height `LazyVStack`
proposal left short alternative sets at the top of the composer even though the
scroll anchor was bottom. The scroll viewport now hugs its 44pt controls and is
itself bottom-aligned, so one or two alternatives actually rise from the
selector. It remains bounded by the composer when content overflows. Clipping is
retained vertically, and mounted hit-testing confirms that transparent space
above a short rail still reaches the Markdown editor. The selector has an
independent 44pt minimum in both dimensions, carries the selected trait, and
explains disclosure/full-menu and one-off route-reset behavior in accessibility
semantics.

The same pass made route ownership conservative by construction: only a claimed
job with an immutable Preset delivery releases next-preset selection. Draft,
keyboard, clipboard, recovery, import/capture handoff, and live work continue to
block it; Send and every non-preset route mutation remain under the broader
ownership guard.

Current-checkout verification passed the 14-fixture capture structure gate, the
project contract suite (10 launch-script and 95 contract tests), 61 focused
shared-package tests, and 56 unsigned iOS simulator tests across launch safety,
rail semantics, capture rendering, and completion-mode policy. Mounted
screenshots cover compact and expanded disclosure states, fixed editor geometry,
vertical overflow, dark mode, large text, Reduce Motion, RTL mirroring,
empty/single-pin updates, and retained editor identity, first responder, focus,
and selection.
The authoritative result bundle is
`/private/tmp/vox-md-hans-feedback-fleet-loop/cycle-1/rail-final-ios-j2-v3.xcresult`;
its 20 exported PNGs are beside it under `rail-final-ios-j2-v3-attachments`.
The simulator's Reduce Motion preference was enabled for that rendering matrix
(the attachment names record `reduceMotion=true`) and restored afterward. The
complete cycle-2 matrix above predates these layout refinements and was not
relabeled as a current full-suite run.

### Hans follow-up: rail side, timestamp format, and recording help

Capture Bar settings now persist two choices independently of quick-action order
and rail disclosure state:

- `capture.presets.quickAccess.railSide.v1` stores exact `left` / `right` values,
  defaulting defensively to Left when absent or unknown. This is a physical
  thumb-reach preference: Left remains screen-left and Right remains screen-right
  in both LTR and RTL. Only the floating alternatives rail moves; the selected
  preset/menu and Send keep their established layout and semantics. The rail's
  children continue to inherit the user's semantic direction.
- `capture.toolbar.timestampFormat.v1` stores exact `12-hour` / `24-hour` values,
  defaulting defensively to 12-hour when absent or unknown. Insert Timestamp now
  passes that explicit choice to `CaptureInsertionFormatter`; output remains
  `h:mm a yyyy-MM-dd` by default and becomes `HH:mm yyyy-MM-dd` in 24-hour mode.
  The existing calendar, locale, and time-zone dependencies are retained, and
  date/due-date formatting is unchanged.

The recording-details panel keeps its compact Audio toggle, Import Audio icon,
and Keyboard Listening icon. Each now has behavior-specific help and
accessibility hints. A 44-point Recording control help affordance opens a native,
vertically scrollable sheet rather than placing explanatory paragraphs in the
keyboard-visible controls. The sheet explains that Audio retains the new
recording while the transcript can still be added when off; Import Audio chooses
and processes an existing audio/video file into the current Capture flow; and
Keyboard Listening controls the persistent Vox.md keyboard session, not an
attachment mode. At widths or text sizes where its title does not fit, the
standard info glyph remains visible with the complete accessibility label/hint.

Scoped preference, deterministic timestamp-consumer, rail rendering/geometry/
focus/hit-testing, and recording-help tests accompany this follow-up. Retained
hosted variants cover both physical sides in LTR and RTL, compact and expanded
states, more-than-five overflow, empty/single pins, dark mode, Dynamic Type, and
Reduce Motion. Exact current-checkout commands, exits, failed-attempt ledger, and
result-bundle/PNG paths are recorded in the cycle-2 Capture lane report; the
coordinator repeats the complete integrated matrix after serial merge.

### Runtime evidence versus manual gates

- Hosted tests execute actual native emoji field events, settings actions with
  real isolated preferences, and mounted Symbols/Emoji/pinned-section variants.
- Actual rail/canvas/Markdown UITextView mounts preserve UIView identity, selected
  range, first responder, text and attachments across a callback-driven switch,
  same-ID no-op and busy rejection. Before/after images were inspected. Other
  mounts cover keyboard-sized space, dark mode, RTL, overflow and >=44pt targets.
  **This is not a real tap or an on-screen system keyboard interaction pass.**
- Widget tests mount **78 iOS variants** through accessibility5, checking actual
  label/glyph/tile containment and fixed-position reading order. Inspected failed
  and corrected images corroborate the small-widget fix. Mac lane additionally
  executed 100 offscreen actual-source editor/native-control assertions; widget
  lane rendered 72 offscreen Mac variants. Neither is a full-app/widget-host pass.
- Argent list-devices and screenshot-diff tools were unavailable. Saved XCTest /
  offscreen images were inspected, not falsely reported as an automated Argent
  visual diff, real VoiceOver run or hardware result.

Before shipping, explicitly authorize/run the physical-device cold-launch gate
and recording/keyboard/widget QA. Also check full-app pin taps while typing,
actual native drag/reopen persistence, emoji keyboard/Character Viewer marked
text, VoiceOver names/selected traits, native menu emoji, widget configuration /
slot clearing / refresh timing, stale links and the iOS/Mac conflicting-draft
consent alerts. These manual gates remain open; they are not additional fleet
feature lanes or grounds to manufacture a third cycle.
