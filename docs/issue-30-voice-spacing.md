# Issue #30: voice entry spacing fix

## Result

The production Capture adapter now removes whole whitespace-only lines at the
boundaries of the selected raw/cleaned transcript before entry prefix/suffix
wrapping. Spaces or tabs on those lines previously survived newline-only trimming,
separated the task marker or suffix from the spoken content, and prevented compact
list insertion. Content-line indentation, Markdown hard-break spaces, internal
paragraph breaks, and template whitespace remain preserved.

The initial tests and Discord-based variants did not reproduce the defect. The
boundary-whitespace reproduction below fails on unchanged production sources at
`d678446` and passes with this fix. The exact reporter build and note bytes remain
unavailable; this establishes and repairs a concrete production failure with the
reported spacing symptom, using synthetic input rather than private recordings.

## Failing reproduction

Start with `- [x] Older`, prefix `- [ ] `, suffix ` #inbox`, and a selected raw or
cleaned transcript with these escaped bytes:

```text
" \t\nBuy milk\n\t "
```

Before the fix, the configured exporter writes 40 UTF-8 bytes:

```text
"- [ ]  \t\nBuy milk\n\t  #inbox\n\n- [x] Older"
```

After the fix, it writes the expected 33 bytes, with no final newline:

```markdown
- [ ] Buy milk #inbox
- [x] Older
```

The regression command is:

```sh
swift test --package-path Packages/VoxboardShared --filter TranscriptVoiceSpacingTests/test_voiceWhitespaceOnlyBoundaryLinesDoNotSeparateTaskFromPrefixOrSuffix
```

The pre-fix run failed all six raw/cleaned and LF/CRLF/CR variants. The final run
passes. Either a leading `" \n"` or trailing `"\n "` independently reproduced the
failure in a temporary minimized writer test. That prototype was removed after
the fix was scoped to the voice adapter; the retained regression checks actual
destination-file bytes through the configured production exporter.

The adapter normalizes CRLF/CR to LF consistently with the existing destination
writer, then removes only whole blank boundary lines. It preserves spaces on
content lines and all internal lines. The shared Markdown writer and frozen
Swift/Rust contract profiles are unchanged. Audio payload placement, transcript
history, and standalone transcript-file export retain their existing behavior.

## Actual delivery path

The direct recording caller applies `TranscriptFlowFormatter`, then sends the
transcript through `ConfiguredTranscriptCaptureDestinationExporter` when a Capture
destination is configured. The adapter selects cleaned or raw body text and
removes blank boundary lines without adding the standalone transcript-file
heading. The pipeline renders the body and
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

Initially, all 11 tests and the neighboring suites passed in a network-free macOS harness
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

## Reporter configuration

For reporter-specific confirmation or any remaining spacing variant, obtain the exact app build, destination placement,
prefix/suffix or vault-template bytes, processing mode and scope, metadata scope,
retained-audio/embed settings, and a synthetic equivalent of the note before and
after one voice capture. Distinguish raw text from cleaned/model-produced text.
No real voice recording, private transcript, credentials, or user vault is needed.
Do not collapse user-authored paragraph breaks or template whitespace to manufacture
a passing reproduction. The synthetic failing case above is the evidence for
this production fix; it is not a recovered copy of the reporter's private input.

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

The first Discord follow-up added two byte-level tests through the configured exporter:

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

Final validation:

```sh
swift test --package-path Packages/VoxboardShared --filter TranscriptVoiceSpacingTests
swift test --package-path Packages/VoxboardShared
./scripts/test-project-contracts.sh
git diff --check
```

All 16 voice-spacing tests pass, including the failing reproduction and additional
checks for preserved indentation, hard-break spaces, internal whitespace-only
lines, and indented code. The full run passes 956 XCTest tests plus 10
Swift Testing tests (966 total). Full SwiftPM testing compiles the production
package and its pinned dependencies; it no longer uses the partial offline
harness described above. Package tests and repository contracts pass. These
checks do not exercise a microphone, live Apple Intelligence, or physical device.

Live Apple Intelligence and reporter-device confirmation remain outside this
verification. The fix is deliberately limited to blank transcript boundary lines;
prose separators, retained-audio blocks, entry metadata, and user-authored internal
paragraph/template breaks keep their existing semantics.

## Argent simulator QA — 2026-10-08

Built the unchanged app sources at `f2e1c43` with the `Voxboard` scheme, Debug,
on an iPhone 17 Pro simulator running iOS 26.5. Argent drove the model download
and Recording Queue's **Process Now** buttons. The app used its existing Debug
shared-container override and queue-screen launch argument to isolate synthetic
fixtures from other app data; no transcription service or exporter was mocked.

Apple Speech is unavailable on this simulator, so the jobs ran real Whisper Tiny
inference on two macOS `say` recordings: “Call the dentist” and “Buy milk.” The
manually seeded voice jobs retained a preset snapshot with Keep Original mode,
processing disabled, audio export off, an existing-note prepend target,
prefix `- [ ] `, and suffix ` #inbox`. Both jobs completed in one attempt and
checkpointed the destination note. Source recordings were retained in the queue
for QA; no audio payload was exported into the note.

The final file was asserted against these exact UTF-8 bytes, with no final newline:

```text
"- [ ] Bye milk. #inbox\n- [ ] call the dentist. #inbox\n- [x] Older task\n\n- [ ] Existing second task"
```

Whisper Tiny recognized “Buy milk” as “Bye milk”; the spacing assertion uses the
actual transcript. The two new tasks have one newline between them and the older
list, while the original blank line between the older tasks survives unchanged.
Assertions also checked the persisted transcript backend, completed job receipts,
exported-note paths, and attempt counts.

[Completed queue screenshot](../artifacts/issue-30-argent-qa/queue-completed.png),
[saved Markdown](../artifacts/issue-30-argent-qa/Tasks.md), and
[machine-readable result](../artifacts/issue-30-argent-qa/summary.json) record the run.

This is an app-driven transcription/export smoke test. Real ASR returned trimmed
text, so whitespace-only transcript boundary lines, cleaned-text selection, and
LF/CRLF/CR variants remain verified by the failing-then-passing package regressions
above. This run does not establish live microphone, Apple Intelligence, Watch, or
reporter-device behavior.
