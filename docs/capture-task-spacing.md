# Compact task capture insertion

## Problem

The Apple Capture writer joined every entry as a paragraph (`\n\n`), including
Markdown tasks. Repeated prepends therefore produced loose checklists even when a
preset's entry prefix and suffix contained no newlines. Capture processing / Apple
Intelligence did not control this spacing.

## Writer behavior

`MarkdownDocumentEditor` now chooses spacing at the insertion boundary:

- Adjacent list items with a matching marker and indentation use one newline.
Checkbox tasks (`- [ ]`, `- [x]`, `- [X]`) and plain bullets (`- item`) with
`-`, `*`, or `+` are both recognized, but a checkbox item and a plain bullet
are different list shapes and keep paragraph spacing. Checked and unchecked
statuses share one list. This applies to prepend, append, and insertion beneath
a heading.
- An ATX heading followed by an inserted list item (task or plain bullet) uses
one newline. The separation between the heading and preceding content is
unchanged.
- A task or plain-bullet list prepended directly after frontmatter, or starting
a frontmatter-only note, uses one newline after the YAML closing delimiter.
Later appends preserve that compact boundary. Appending does not remove the
existing frontmatter/body gap of an older note.
- Prose and other block boundaries retain paragraph spacing. Internal blank lines
in existing content, capture text, and templates are not collapsed. List-looking
lines inside fences, comments, or raw HTML are not treated as safe trailing list
boundaries. Bare bullets without content (`-`) are not compact boundaries.
Complex task continuations retain the conservative block spacing.
- For a capture ending in a recognized list item (task or plain bullet), Retry
Protection puts the same `<!-- vox-capture:<lowercase-uuid> -->` marker inline
on that line. A standalone HTML comment would split the rendered list even
without blank lines. Trailing Markdown hard-break spaces are preserved.
Non-list and empty captures retain their existing marker placement.

Beneath-heading placement additionally carries a position: `top` (the original
behavior — directly beneath the heading, above existing section content) or
`bottom` (appended at the end of the heading's section, before the next heading
of the same or higher level outside code fences; deeper headings stay inside the
section). `bottom` with a missing heading and `create` behavior is equivalent to
`top`: the new heading is created at the end of the note with the capture
directly beneath it. The position is persisted as `headingPosition` on
`CapturePlacement.beneathHeading`; legacy payloads without the field decode as
`top`, so no migration is needed.

Existing standalone markers remain detectable; already-applied requests are not
rewritten. This is not a cleanup/migration of previously saved blank lines or
markers. The beneath-heading position is the one new preset setting and persistence
key (`headingPosition`, additive, decodes as `top` when absent); no other new
persistence key is needed.

Task and list recognition runs **after** entry prefix/suffix rendering. Consequently both
Todo Checklist processing and an entry prefix of `- [ ] ` get the same spacing, and a
plain `- ` prefix now also joins tightly with an existing plain-bullet list — a
user-requested change so daily-note `## Notes` sections keep tight bullets without
checkbox syntax. The processing opt-out is unchanged: raw text remains raw when
processing is off. For one task per capture without processing, use the `- [ ] `
entry prefix rather than relying on the disabled Todo Checklist mode. Do not combine
the prefix with checklist conversion, which can create duplicate checkbox syntax.

## Compatibility boundary

This is a separate, user-requested change to the legacy Apple writer, not a
revision of the M1-frozen v1 contract fixtures or a claim of Rust/Android parity.
The pinned behavior in ADR-0002 / ADR-0004 and its fixture mirrors remains frozen.
The current M2 new-note text/link subset has neither existing-note insertion nor
retry markers/frontmatter and is unaffected. Before promoting the remaining
existing-note operations to the shared core, this behavior needs an explicitly
versioned renderer profile and exact cross-language fixtures; do not silently
rebaseline v1 output or already-prepared jobs.

## Verification

- `MarkdownTaskSpacingTests`: exact output for task and plain-bullet boundaries,
  frontmatter, headings, formatting prefixes, CRLF, hard breaks, protected Markdown
  contexts, inline and legacy marker replay, preservation of non-list spacing, and
  both beneath-heading positions (top/bottom, section end, deeper headings, fences,
  missing-heading create).
- `CaptureModelCodableTests`: legacy `beneathHeading` payloads without
  `headingPosition` decode as `top`; both positions round-trip through the
  production codec.
- `CaptureTaskSpacingPipelineTests`: draft → processing/fallback → rendering →
  coordinated file writes, with processing on/off, prepend/append, repeated tasks,
  and Retry Protection on/off. No live model is required.
- Existing Markdown editor, writer, and pipeline tests continue to cover the
  surrounding behavior. These are shared-code tests, not device UI/AI validation.
