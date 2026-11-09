# iOS exploratory edge-case QA, pass 2

Tested with Argent on the booted iPhone 18 Pro Max simulator (iOS 27.0), bundle `bontecou.Voxboard`, November 7, 2026. This pass focused on editor actions, Unicode, attachments, due dates, and recording controls rather than the settings/library areas from the earlier pass. Tests used the existing Turkish demo draft with English process language overrides and screenshot unlock. No capture was submitted.

## Bug found and fixed

Attach → Link → enter `https://` → Add created an unusable link attachment. Foundation accepts this as a URL, and the app checked only the scheme. Deep-link parsing and Markdown rendering had the same gap: the new regression cases failed before the fix (8 assertions across the two suites).

[Before screenshot](../../artifacts/validation/ios-edge-qa-pass2-2026-11-07/incomplete-link-before.png) · [Failing regression output](../../artifacts/validation/ios-edge-qa-pass2-2026-11-07/link-tests-before.log)

`CaptureWebLink.isValid` now requires HTTP(S) and a nonempty host without whitespace or control characters. The composer, deep-link parser and direct composer launches, Capture URL shortcut, share URL loader, Markdown renderer, and native engine admission use it. Invalid links cannot be appended to the composer or rendered as working Markdown links. Localhost, IPv4, IPv6, Unicode domains, and mixed-script paths remain supported. Native engine admission retains its existing narrower scheme contract.

## Other checks that passed

- Pasted emoji, a combining accent, a family emoji sequence, mixed-script URL, and Markdown code fence. All text survived intact. Toggling the task after the Unicode changed the correct checkbox; task syntax inside the code fence stayed literal. Successive Undo actions restored the original draft exactly. [Evidence](../../artifacts/validation/ios-edge-qa-pass2-2026-11-07/unicode-task-toggle.png).
- Opened the due-date menu on Saturday November 7 and cancelled; the menu showed Today, Tomorrow, and This Weekend. No date was inserted.
- Empty sketches disabled Add. Drawing a line enabled Add; double tapping Add produced one attachment. Removing the sketch preserved the original draft. [Evidence](../../artifacts/validation/ios-edge-qa-pass2-2026-11-07/single-sketch-after-double-add.png).
- Switching detailed recording controls from Add to Draft to Send Immediately changed the explanation and microphone action. Returning to Add to Draft restored both; closing the controls preserved text. No recording or delivery was started.
- Photos denial left the attachment sheet usable; Link and Sketch remained accessible.

## Automated validation

Focused SwiftPM regression suites passed 30 tests, zero failures: web-link validation, deep-link parsing, Markdown rendering, and core engine admission. [Passing output](../../artifacts/validation/ios-edge-qa-pass2-2026-11-07/link-tests-after.log).

The signed Debug simulator build and hosted `testIncompleteLinkCannotChangeOrPersistComposerDraft` test passed, verifying that adding or opening a hostless URL leaves both the in-memory and stored draft intact. Total: 31 passing tests. Existing concurrency/deprecation warnings remain. The first hosted-test attempt used the app scheme, which excludes the test target; rerunning with `VoxboardTests` succeeded. [Simulator result](../../artifacts/validation/ios-edge-qa-pass2-2026-11-07/simulator-test-result.json).

Live Argent verification on the rebuilt app: adding `https://` displayed “Enter a complete http:// or https:// link.” with no attachment, and the original text remained intact. Adding `https://example.invalid/a_(b)?q=тест#é` succeeded with Foundation's percent encoding preserved. The test attachment was removed afterward. [Rejected incomplete link](../../artifacts/validation/ios-edge-qa-pass2-2026-11-07/incomplete-link-after.png) · [Accepted mixed-script link](../../artifacts/validation/ios-edge-qa-pass2-2026-11-07/valid-unicode-link-after.png).

The original draft and selected Toplantı Notları route survived the signed test build and restarts. The app is left on Capture in Turkish with no extra attachments, Add to Draft recording mode, collapsed controls, and Photos permission reset to not-yet-asked. Final launch used `-AppleLanguages (tr) -AppleLocale tr_TR -VoxScreenshotUnlocked -VoxAdaptiveNoAutofocus` and no seed flags. [Restored capture](../../artifacts/validation/ios-edge-qa-pass2-2026-11-07/restored-capture.png). `git diff --check` passed.

Physical-device behavior, audio transcription, network delivery, and successful photo/file import are outside this pass. Share-extension and shortcut validation compile with the app but were not exercised through their system UIs. This is a one-off exploratory pass with unit regression coverage, not a recorded e2e suite.
