# Android composer and preset parity — November 2026

Scope: saved-audio naming, top/bottom heading insertion, configurable preset widgets,
wide-window draft preview, physical rail side and explicit timestamp format selection.

The six new ledger rows remain `implemented` with device acceptance `planned` until
retained release qualification is complete. Unit/emulator results are recorded below;
they do not imply human visual or cloud-provider approval.

- Audio filenames accept `{timestamp}`, `{date}`, `{time}`, `{YR}`, `{id}`, `{id8}`,
  `{preset}` and `{original}`. A blank template preserves legacy naming. The encoded
  extension wins; names are sanitized/bounded. Capture assets freeze their final names
  before enqueue, preserve staged originals on failure and never overwrite a collision.
  Configured transcript exports and Wear Recording Only use the same renderer.
- Heading position defaults to Top for old snapshots. Bottom inserts before the next
  heading of equal or higher rank, retaining nested headings and ignoring fenced code.
  The optional contract field is omitted for Top to preserve historical canonical bytes.
- The preset widget is separate from the existing Capture/Record widget. Each instance
  follows enabled pins or preserves six explicit positions, including empties, repeats,
  disabled and deleted targets. Small sizes show the first position. Taps open Capture,
  never send/record, and require confirmation before changing a nonempty draft's preset.
- Draft preview is opt-in at widths of at least 760 dp and font scale below 1.5. It
  renders local text, never fetches Markdown images/links, displays route/attachments,
  supports copying and preserves the primary editor through resize/show/hide changes.
- Rail side means physical left/right, including RTL. Timestamp formats match iOS:
  `h:mm a yyyy-MM-dd` and `HH:mm yyyy-MM-dd`, with legacy boolean preference migration.

## Validation

The implementation is committed as `ba83d48`. The Swift oracle was regenerated from
that clean source revision and committed as `1904ece`; its cases are unchanged and
its source/compiler provenance check passes.

- Android CI task set passed: `check assembleDebugAndroidTest
  :app:validateDebugArtifacts :wear:validateWearDebugArtifacts releaseReadiness`.
  This includes lint, 256 JVM tests, four-ABI phone native artifacts, phone/Wear debug
  artifacts, release bundles and readiness validation.
- Rust: all 49 workspace tests passed (27 library, 18 contract/integration, four
  UniFFI), plus formatting, strict Clippy and byte-identical Swift/Kotlin bindings.
- Swift package: 655 shared XCTest tests, 381 capture-core XCTest tests and 10 Swift
  Testing tests passed. Host tests used an isolated shared container via
  `VOXBOARD_SHARED_CONTAINER_OVERRIDE=/tmp/vox-shared-clean-tests`.
- Project contracts: 65 script tests and 136 contract tests passed, including
  deterministic capability conversion, 197 implementation hashes, schema mirrors,
  localization audit and validation definitions. Feature inventory: 347 entries;
  registry coverage and whitespace checks pass.
- Phone instrumentation: all 79 tests completed on the dedicated API-36 Vox AVD:
  75 passed, four model-fixture-gated tests skipped, zero failures. Run from a clean
  app sandbox (`adb -s <test-emulator> shell pm clear md.vox.android`) before
  instrumentation: the language test requires first-launch destination state.
  The suite covers the new preview/resize, RTL setting selection, preference
  persistence, widget configuration/RemoteViews, SAF heading-bottom insertion,
  recording snapshot round trip, frozen filename context and export collision checks.

The ledger now contains 281 capabilities: 262 verified, ten implemented and nine
inventoried. Of 248 Android/Wear-applicable rows, 233 are verified, ten implemented
and five inventoried. These six additions remain implemented with acceptance planned;
physical/provider, launcher/OEM, accessibility and human visual qualification are
still required for release claims. Android translation/plural review also remains
open: the generated audit explicitly retains 554 catalog-missing English fallbacks.
