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

Implementation checks and clean-commit oracle provenance will be recorded after the
full Android, Rust, Swift, project-contract and emulator gates finish.
