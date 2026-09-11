# Vox.md Mac-native redesign

Date: 2026-09-10

This directory records the fresh-install Mac UI and the first visual exploration for a Mac-first redesign. The source screenshots are preserved as copies; the originals remain unchanged in iCloud.

## Directory structure

- `01-current-ui/` — full-resolution source screenshots, renamed into workflow order.
- `02-concepts/` — initial generated concept images.
- `03-implementation/` — deterministic screenshots captured from the rebuilt Mac app.
- `PROMPTS.md` — the exact prompt set used for the concepts.

## Current UI inventory

| File | Screen or state |
| --- | --- |
| `01-destination-setup.png` | Destination setup form |
| `02-capture-inspector-open.png` | Capture with route inspector |
| `03-capture-main.png` | Main Capture workspace |
| `04-recording-queue.png` | Recording Queue |
| `05-recording-queue-settings-menu.png` | Queue policy menu open |
| `06-history-empty.png` | Empty History split view |
| `07-transcription-models.png` | Model management |
| `08-capture-preset-default.png` | Default preset editor |
| `09-entry-templates-empty.png` | Empty template library |

All nine source screenshots are 3024 × 1900 pixels.

## First concept set

| File | Question explored |
| --- | --- |
| `01-capture-workspace.png` | Can Capture feel like a focused Mac document window? |
| `02-activity-workspace.png` | Can Queue and History become one legible desktop workflow? |
| `03-first-run-setup.png` | Can a fresh install begin ready and calm instead of warning-first? |

These are directional mockups rather than pixel specifications. The implementation translates their hierarchy into native SwiftUI and AppKit controls, system materials, toolbars, inspectors, lists, and keyboard commands.

## Implemented direction

- The main window now has three workspaces: Capture, Activity, and Library.
- Capture uses a full document canvas, a unified toolbar, and a standard trailing details inspector.
- Activity unifies durable recording jobs and completed capture history while preserving retry, recovery, copy, reveal, and delete actions.
- Global configuration lives in the standard Settings window.
- First run guides the user through selecting a notes folder, installing a transcription model, granting microphone access, and checking the Quick Capture shortcut.

## Implementation previews

| File | Screen |
| --- | --- |
| `03-implementation/01-capture-window.png` | Capture canvas with native toolbar and details inspector |
| `03-implementation/02-activity-window.png` | Unified searchable Activity workspace |
| `03-implementation/03-first-run-window.png` | Fresh-install setup assistant |

## Design thesis

- Keep the main sidebar for peer workspaces: Capture, Activity, and Library.
- Move global configuration to the standard Settings window opened with Command–Comma.
- Use a unified title-bar toolbar for frequent contextual commands.
- Use a standard trailing inspector for the current capture or selection.
- Replace oversized cards and touch spacing with compact Mac lists, tables, form grids, and hairline separators.
- Use the shipped app icon as the brand mark and its orange (`#FD9011`) as the only app-authored chromatic family.
- Use black content on the bright icon orange for prominent actions; use the deeper accessible orange (`#B45F0A`) where AppKit supplies white selection labels.
- Keep the rest of the interface black, white, and neutral grey; express success and failure with symbols and labels as well as orange emphasis.
- Make first-run setup resolve the destination, transcription model, microphone access, and quick-capture shortcut before opening the workspace.

## Repository implications

The Mac target is already SwiftUI/AppKit and the underlying capture architecture is reusable. The redesign can retain the existing view model, durable drafts, recording pipeline, history, presets, model management, sandbox bookmarks, deep links, and termination handling while replacing the presentation shell. The highest-risk implementation areas are the large concentrated view files and source-contract tests that currently assert the existing navigation hierarchy.
