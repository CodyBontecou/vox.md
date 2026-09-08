# Compact task capture insertion

## Problem

The Apple Capture writer joined every entry as a paragraph (`\n\n`), including
Markdown tasks. Repeated prepends therefore produced loose checklists even when a
preset's entry prefix and suffix contained no newlines. Capture processing / Apple
Intelligence did not control this spacing.

## Writer behavior

`MarkdownDocumentEditor` now chooses spacing at the insertion boundary:

- Adjacent checkbox task lines with matching bullet and indentation use one newline.
  Unchecked and checked (`[ ]`, `[x]`, `[X]`) tasks with `-`, `*`, or `+` bullets are
  recognized. This applies to prepend, append, and insertion beneath a heading.
- An ATX heading followed by an inserted task uses one newline. The separation
  between the heading and preceding content is unchanged.
- A task prepended directly after frontmatter, or the first task in a
  frontmatter-only note, uses one newline after the YAML closing delimiter. Later
  appends preserve that compact boundary. Appending does not remove the existing
  frontmatter/body gap of an older note.
- Prose and other block boundaries retain paragraph spacing. Internal blank lines
  in existing content, capture text, and templates are not collapsed. Task-looking
  lines inside fences, comments, or raw HTML are not treated as safe trailing list
  boundaries. Complex task continuations retain the conservative block spacing.
- For a capture ending in a recognized task line, Retry Protection puts the same
  `<!-- vox-capture:<lowercase-uuid> -->` marker inline on that line. A standalone
  HTML comment would split the rendered checklist even without blank lines.
  Trailing Markdown hard-break spaces are preserved. Non-task and empty captures
  retain their existing marker placement.

Existing standalone markers remain detectable; already-applied requests are not
rewritten. This is not a cleanup/migration of previously saved blank lines or
markers. No new preset setting or persistence key is needed.

Task recognition runs **after** entry prefix/suffix rendering. Consequently both
Todo Checklist processing and an entry prefix of `- [ ] ` get the same spacing.
The processing opt-out is unchanged: raw text remains raw when processing is off.
For one task per capture without processing, use that entry prefix rather than
relying on the disabled Todo Checklist mode. Do not combine the prefix with
checklist conversion, which can create duplicate checkbox syntax.

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

- `MarkdownTaskSpacingTests`: exact output for task boundaries, frontmatter,
  headings, formatting prefixes, CRLF, hard breaks, protected Markdown contexts,
  inline and legacy marker replay, and preservation of non-task spacing.
- `CaptureTaskSpacingPipelineTests`: draft → processing/fallback → rendering →
  coordinated file writes, with processing on/off, prepend/append, repeated tasks,
  and Retry Protection on/off. No live model is required.
- Existing Markdown editor, writer, and pipeline tests continue to cover the
  surrounding behavior. These are shared-code tests, not device UI/AI validation.
