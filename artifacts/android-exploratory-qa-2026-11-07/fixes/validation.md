# Android QA fixes — 2026-11-07

Implemented the three findings in [the exploratory report](../report.md).

| Finding | Fix | Verification |
| --- | --- | --- |
| Entry-template edits lost on rotation | Save the editor's open state, name, prefix, and suffix together. Own that state above the compact/expanded route-list branches. | State restoration and layout relocation test; real portrait → landscape → portrait rotation with all three fields retained and Save enabled. |
| Landscape composer clips text | Use a shorter header and voice controls in wide, short windows; keep the route on the header row and recording options beside Speak. Require sufficient available height before showing the draft preview. Keep recovery notices visible. | Short-window test requires at least 96 dp of editor height; real rotation shows readable text with keyboard open and closed. Existing wide-preview resize/toggle test passes. |
| Rotation clears Undo | Retain the bounded Undo list in a navigation-scoped ViewModel, avoiding large saved-state Bundles. Existing send/external-draft reset behavior is retained. | Restoration test executes Undo and checks the restored text. On the emulator, Undo remains enabled after rotation, removes the last typed character, and can undo the entire temporary draft. |

Build: `:app:assembleDebug :app:assembleDebugAndroidTest` succeeded with JDK 17.

Focused instrumentation suite: `CaptureRotationInstrumentationTest`, `ComposerPresetUiInstrumentationTest`, and `CaptureBarUiInstrumentationTest` — 13 tests passed. This includes three new regression tests plus existing preview, capture-bar, transcription, and widget checks.

Live checks used Argent on the existing API 36 Vox emulator (`emulator-5556`). APK installation used an in-place update to preserve the sandbox. The temporary template was canceled; temporary draft edits were undone. No captures were sent, and no existing notes, history, or routes were removed.

Undo survives configuration changes; it is intentionally held in memory and does not survive process death. Template edits use saved state and can survive saved-instance-state restoration.

Evidence:

- [Readable landscape editor](landscape-readable.png)
- [Readable landscape editor with keyboard](landscape-readable-with-keyboard.png)
- [Undo restored previous text after rotation](undo-restored-text-after-rotation.png)
- [Template retained in landscape](template-retained-landscape.png)
- [Template retained after returning to portrait](template-retained-portrait.png)
