# Issue #30: voice entry spacing investigation

## Result

The reported unwanted blank lines were **not reproduced** on
`4f5bd7d0dd88b0c22dc13dac5e9c780da43c5991` with synthetic transcripts and temporary
files. No production formatting change is justified by the evidence gathered here.
This adds regression coverage, not a claim that the reporter's issue is fixed.

The 2026-10-08 follow-up below also failed to reproduce the defect with synthetic
variants grounded in the reporter's Discord history. Full production SwiftPM
testing is now available locally; the earlier dependency-download limitation no
longer applies to this follow-up.

## Actual delivery path

The direct recording caller applies `TranscriptFlowFormatter`, then sends the
transcript through `ConfiguredTranscriptCaptureDestinationExporter` when a Capture
destination is configured. The adapter selects cleaned or raw body text without
adding the standalone transcript-file heading. The pipeline renders the body and
entry prefix/suffix, and `CoordinatedCaptureWriter` applies
`MarkdownDocumentEditor` to the destination file.

The earlier fixes were `0cb4537` (compact checkbox boundaries) and `90fd7a3`
(compact plain bullets and heading placement). Both operate at that same writer
boundary, after entry formatting. `9983a92` had already removed standalone
transcript headings from Capture delivery. The separate `TranscriptFileExporter`
fallback has append/new-file modes, not the existing-note prepend operation.

For example, the configured voice route with prefix `- [ ] ` and suffix ` #inbox`
changes:

```markdown
---
title: Tasks
---

- [x] Older task
```

into these exact bytes, with no final newline:

```markdown
---
title: Tasks
---
- [ ] Buy milk #inbox
- [x] Older task
```

## Regression coverage

`TranscriptVoiceSpacingTests` checks actual temporary-file UTF-8 bytes through the
configured exporter, not just renderer strings. Coverage includes raw/cleaned
transcripts, repeated prepend/append, plain bullets/checkboxes, prefix/suffix,
LF/CRLF/CR, empty and boundary-only content, deterministic Todo formatting,
headings, retry markers, literal payload tokens, and intentional internal
paragraph/list/template newlines. It also compares voice bytes to typed keyboard
Capture delivery for matching inputs.

All 11 new tests and the neighboring suites passed in a network-free macOS harness
(460 tests total). The harness compiled unchanged delivery sources and the entire
Capture core with ExportKit pinned to
`17993dc0361c41145dc6429738ed369d9976e550`. It excluded inference/app targets and
extracted two unchanged data-model definitions from the FluidAudio-dependent
speaker service. Full production-package execution was blocked by FluidAudio Git
connection resets. This is not full-package, simulator, microphone, or physical-device
verification.

An isolated scratch mutation that always uses paragraph separators made the
prefix/prepend regression fail (60 actual bytes versus 59 expected). That proves
test sensitivity; it is **not** a failing reproduction on the investigated base.

## Missing reproducer

To justify a further fix, obtain the exact app build, destination placement,
prefix/suffix or vault-template bytes, processing mode and scope, metadata scope,
retained-audio/embed settings, and a synthetic equivalent of the note before and
after one voice capture. Distinguish raw text from cleaned/model-produced text.
No real voice recording, private transcript, credentials, or user vault is needed.
Do not collapse user-authored paragraph breaks or template whitespace to manufacture
a passing reproduction. Issue #30 remains unresolved for the reported configuration.

## Discord follow-up — 2026-10-08

Read the original message, its surrounding conversation, the September 8 repair
thread, and all 21 results returned by the guild's author search for `mchalkley`.
Reads used the existing isobot Discord bridge credential without exposing it.
The isobot prompt API itself reported that it has no Discord read tools. No
Discord messages were sent.

The reporter's statements establish:

- [August 11](https://discord.com/channels/1443424100759634003/1498086779536936961/1536845865715761212): a preset prepends tasks to an existing scratchpad in
  the vault. Typed phone tasks worked; Watch transcripts had a dated transcript
  heading. The [preset was named Task](https://discord.com/channels/1443424100759634003/1498086779536936961/1536850525947953182).
- [August 13](https://discord.com/channels/1443424100759634003/1498086779536936961/1537588797967966319): the earlier transcript-heading problem was confirmed
  fixed. This is separate from the September spacing report.
- [August 19](https://discord.com/channels/1443424100759634003/1498086779536936961/1539782143520145408): the reporter used `{location}` and tried
  ` Loc:{location}` as suffixes. That message does not establish that the same
  suffix or location-metadata settings were still active on September 22.
- [September 6](https://discord.com/channels/1443424100759634003/1498086779536936961/1546146654938333234): a simple task-prepend preset on iPhone and iPad
  produced unwanted blank lines above and below the entry.
- [September 6 processing comparison](https://discord.com/channels/1443424100759634003/1498086779536936961/1546234501942747136): blank lines occurred with Apple Intelligence
  both on and off; disabling it produced notes instead of tasks.
- [September 22](https://discord.com/channels/1443424100759634003/1498086779536936961/1551931246169301054): the reporter said transcribed entries still had
  blank lines after the keyboard-entry repair.

None of these messages supplies before/after note bytes, an exact current preset
export, an app build for the September report, or audio-embed settings. There are
no attachments in the reporter's indexed messages. Naming a preset Task alone
does not establish its processing mode or prefix.

Two further byte-level tests now exercise the configured exporter:

- Repeated voice, Watch, and widget task prepends with the reported location
  suffix, raw/cleaned body selection, and available/unavailable synthetic
  location outcomes. The tests explicitly use Todo Checklist mode, no prefix,
  no audio attachment, and location metadata output disabled. Those settings
  are test assumptions, not a recovered failing preset. All boundaries remain
  compact, including when the location token resolves to an empty string.
- The same three source routes with Keep Original mode and no prefix preserve
  raw prose beside the older checklist: `Buy milk\n\n- [x] Older`. This is the
  existing prose/list paragraph policy, not evidence of unintended whitespace
  around a task.

Validation against PR head `2c8adf1` plus these test/documentation changes:

```sh
swift test --package-path Packages/VoxboardShared --filter TranscriptVoiceSpacingTests
swift test --package-path Packages/VoxboardShared
./scripts/test-project-contracts.sh
git diff --check
```

All 13 voice-spacing tests pass. The full run passes 953 XCTest tests plus 10
Swift Testing tests (963 total). Full SwiftPM testing compiles the production
package and its pinned dependencies; it no longer uses the partial offline
harness described above. Package tests and repository contracts pass. These
checks do not exercise a microphone, live Apple Intelligence, or physical device.

The next required evidence is one synthetic before/after note plus the active
Task preset's route, prefix/suffix/template, processing and metadata scopes,
location-output policy, retained-audio/embed settings, and app build. A further
production fix remains unjustified without a failing reproduction.
