# Adaptive iPhone capture layout

The original Vox.md writing surface and three persistent bottom bars remain the
primary interface on both Duo displays. Colors, editor spacing, preset selector,
History and Settings buttons, recording gesture, Send control, and the complete
customizable Markdown tool row retain their existing presentation. There is no
capture desk, rounded editor card, replacement header, or automatic History pane.

A preview icon appears only when the current layout has at least 760 points of
width and uses a standard Dynamic Type size. It explicitly opens a side-by-side
draft preview, off by default. Narrow layouts always show the text editor with
all three bottom bars; there is no preview icon, replacement view, or sheet.
Folding hides preview; unfolding restores it if it was enabled. The same editor
remains mounted so draft text, selection, and undo history survive resizing.

The preview renders headings, inline Markdown, bullets, checkboxes and quotes,
and displays the resolved destination when configured. It does not request
remote images or run processing. It is a draft preview rather than exact output
from preset formatting or processing. Copy preserves the original Markdown.

## Validation

Run `scripts/test-capture-view-structure.sh` and
`VoxboardTests/QuickCaptureRenderingTests`. Resize coverage mounts the real editor
and checks identity, selection, text, and preview visibility. Preview rendering
coverage checks long content, accessibility text, RTL and dark mode. Xcode 27.1
build and launch were verified on the iPhone Duo simulator / iOS 27.1.

Debug localization screenshot mode skips purchase onboarding without granting
purchase access. Physical-device recording and fold-during-recording QA remain.

Apple guidance: [Prepare for iPhone Duo](https://developer.apple.com/iphone-duo/prepare/).
