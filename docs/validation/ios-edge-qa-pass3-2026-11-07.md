# iOS exploratory edge-case QA, pass 3

Tested with Argent on the booted iPhone 18 Pro Max simulator (iOS 27.0), bundle `bontecou.Voxboard`, November 7, 2026. This pass covered capture destination overrides, route metadata, and reusable entry templates. English process-language overrides and the existing screenshot unlock were used for testing. No capture was submitted or recording started.

## Bug fixed: template validation hidden behind the keyboard and preview

Reproduction: Settings → Routes → Entry Templates → Add Entry Template. Leave Name empty, enter a multiline prefix containing YAML, emoji, `{date}`, and `{location}`, then tap Save while the prefix editor is focused.

Save correctly rejected the missing name, but rendered its error at the end of the form, below the keyboard and location preview. The initial visible screen gave no feedback. Scrolling revealed the error below the keyboard boundary. [Before](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/template-save-hidden-error.png).

`CaptureEntryTemplateEditorView` now presents validation and save errors in a dismissible alert, using the existing localized Error and OK strings. The entered name, prefix, and suffix remain intact. The prior destination-editor fix in the same file was preserved.

Verification on the rebuilt app repeated the exact input and showed “Enter a template name.” immediately in a modal alert. Dismissal preserved the prefix. A whitespace-only name showed the alert again; correcting it to `QA-Corrected` saved successfully. [Fixed alert](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/template-save-alert-fixed.png) · [Corrected save](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/template-corrected-save.png).

## Other checks that passed

- Opening Choose another note in this vault, then cancelling the Files picker, preserved the selected route, note target, and original capture draft.
- A temporary route preserved four metadata fields after closing and reopening: Unicode/emoji, quoted spaces, a list, and a URL containing additional colons and a Cyrillic query. The editor reordered keys without changing their values. [Reopened metadata](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/metadata-reopened.png).
- A template named `  QA 🧪 Template : []  ` saved with surrounding whitespace trimmed. Double tapping Save created one template. [Evidence](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/single-template-after-double-save.png).
- Reopening that template preserved its multiline prefix, YAML delimiters, emoji, tokens, and trailing newline. Typing `CANCEL-ME`, cancelling, and reopening restored the original saved prefix. [Evidence](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/template-cancel-preserved.png).
- The saved template, temporary route, selected original route, and original draft survived installing and launching the signed updated build.
- Deleting both test templates restored the empty template library. Deleting the temporary route restored the original five routes and keyboard/Watch summaries. [Empty templates](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/templates-removed.png) · [Restored routes](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/routes-restored.png).

## Validation and scope

The signed Debug simulator build passed. [Build result](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/build-result.json). Existing concurrency/deprecation warnings remain. `git diff --check` passed. This small presentation fix was validated with the failing and passing live Argent flow; no new unit tests or recorded e2e suite were added.

This pass did not establish successful alternate-note selection, template import, file delivery, audio/model execution, or physical-device behavior. No permissions were changed. The temporary route and templates were removed, the original draft remained intact, and the app was restored to Turkish Capture with the route rail collapsed. Final launch uses `-AppleLanguages (tr) -AppleLocale tr_TR -VoxScreenshotUnlocked -VoxAdaptiveNoAutofocus`, with no seed flags.

[Final restored capture](../../artifacts/validation/ios-edge-qa-pass3-2026-11-07/restored-capture.png).
