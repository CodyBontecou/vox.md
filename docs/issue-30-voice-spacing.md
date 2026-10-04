# Issue #30: voice entry spacing investigation

## Result

The reported unwanted blank lines were **not reproduced** on
`4f5bd7d0dd88b0c22dc13dac5e9c780da43c5991` with synthetic transcripts and temporary
files. No production formatting change is justified by the evidence gathered here.
This adds regression coverage, not a claim that the reporter's issue is fixed.

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
