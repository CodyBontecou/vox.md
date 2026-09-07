# iOS 27 iPhone QA — September 7, 2026

Tested on a cabled iPhone 17 Pro running iOS 27.0 beta (24A5430a), built with Xcode 27 beta 6 (27A5252f). Apple Intelligence and the system model's vision capability were available. Argent CLI 0.24.0 drove the physical phone through its XCTest runner.

## Findings and fixes

1. **Image requests failed before generation.** `SystemLanguageModel.tokenCount(for:)` rejected a prompt containing a CGImage with “Unable to tokenize prompt,” while `LanguageModelSession.respond(to:)` described that same image successfully. The image adapter now lets generation enforce its context limit and retains the single bounded image, fixed instructions, 512-token response limit, 300-character validation, and existing processing deadlines. Text requests retain their full token preflight.
2. **Preset edits were lost on app restart.** The preset list's `onChange` did not reliably persist edits made while its navigation destination covered it. Edits now save through the binding setter. Reopening the app retained the image preference and Keep Original mode.
3. **Hardware test fixtures needed stronger isolation.** A temporary capture library initially cleared the real app's Default and Watch route associations. Both associations were restored to the matching existing routes in the phone's library. The fixture's generated note lived in a temporary test vault. The composer now accepts an injected preferences store and pipeline; capture fixtures use their own preferences and unmetered pipeline and assert that the app's saved preset data is unchanged. The temporary recovery test was removed.

## Hardware results

The final focused XCTest run passed **5 tests, 0 failures, 0 skips**:

- Real Foundation Models image description.
- Real image staging, processing, Markdown rendering, and file delivery through `QuickCaptureViewModel.submit()`.
- Capture cancellation retains its draft and staging context.
- Rotated-image preview sizing, original-byte preservation, and corrupt-image rejection.
- iOS 27 error normalization.

The final synthetic image produced “A solid blue square against a white background.” in **1.05 seconds**. A separate full capture completed in **3.69 seconds** and exported:

```markdown
Keep **this Markdown** and https://example.com/a?b=1 exactly.

![A solid blue rectangle against a white background.](attachments/blue%20square.png)
```

The test verified identical original image bytes, unchanged accompanying Markdown, a successful receipt, cleared submitted draft, and reset progress state. These are single synthetic observations, not a general quality or performance benchmark.

The final iOS app/test build and Mac app build both succeeded. Local XCTest evidence: `/tmp/vox-intelligence-device27-final.xcresult`.

## Argent UI coverage

The final uninterrupted replay passed **61 checks/actions, 0 failures, 0 skipped, 0 errors**. Persisted preferences were read back after the final app restart to verify Clean Prose, both Default processing switches off, and the original Default/Watch route IDs. Capture was left open with an empty draft. Local replay evidence: `/tmp/vox-argent-settings-verified.ndjson`.

The recorded flow checks the independent image opt-in, Keep Original compatibility, persistence across app restart, the master gate blocking image-toggle changes, and restoration to the initial Clean Prose mode with both processing switches off. It leaves the app on Capture. The Default route is Vox Notes / Bottom; the Watch route is preserved.

Replay from the repository root against an unlocked, connected phone:

```sh
argent flow run ios27-image-settings-qa --device <iPhone-UDID> --platform ios
```

During authoring, scrolling could leave a switch beneath the system/navigation bars even though Argent reported a nonzero frame. The final flow changes both switches before scrolling to the Mode picker.

The flow assumes the English UI, Default selected, Clean Prose, and both processing switches off. It changes only those processing settings. The screen-idle checks may report the small moving region in the status bar or text caret; destination identity and toggle-value checks establish the actual outcomes.

## Remaining release coverage

No offline-radio test, peak-memory profile, broad real-photo/dense-screenshot/sketch quality review, non-English model evaluation, Mac UI review, or Obsidian/VoiceOver integration review was performed in this run. The image feature remains opt-in and uses only the on-device system model.
