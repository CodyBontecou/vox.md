# Vox Android exploratory QA, sustained pass 6

Status: complete. Two consecutive final broad sweeps over distinct scenarios found no new actionable bugs, with all confirmed fixes verified. Clean sweep count: 2.

Target: owned emulator-5556, Vox API 36 AVD. Android source only; unrelated iOS and previous QA changes preserved. No purchases, external sharing, model downloads, or real delivery were performed.

## Confirmed bugs and fixes

1. Rotation during location lookup left Capture permanently busy after its composition-owned job was canceled. The busy indicator now resets with that canceled job.
2. Pending location permission/submission decisions vanished during rotation. A screen ViewModel retains these decisions without bundling capture bodies.
3. Unsaved transcript and metadata edits vanished during recreation. A ViewModel retains the editor draft; source reloads populate untouched fields, preserve cleared/edited fields, and isolate different transcript sessions.
4. Capture and transcript detail exports lost their pending format/source while the document picker was open. Exports now freeze UTF-8 bytes in private staging files and save a small one-shot request token; cancellation and provider failures clean the snapshot.
5. Greek search changed results with query capitalization and final sigma context. Locale-independent uppercase folding after accent normalization makes the cases consistent, with Turkish/accent/German controls.
6. Pasting a valid large transcript crashed Compose with an unrepresentable text-field height (378141). Multiline editors now cap visible lines and scroll internally, retaining the full text.
7. The one-capture route dialog disappeared during rotation, losing its path and placement edits. Dialog visibility and draft fields now use saved state hoisted above the adaptive header branches. Live verification caught and corrected an incomplete first fix that only survived recreation in place.
8. Repeated Send callbacks before a new frame started two location lookups, and route controls remained available during preflight. Admission now guards synchronously and route choices stay disabled while preflight is pending.

## Evidence and checks

Original failures were reproduced before fixes. New regressions exercise restoration, source reload, cancellation, failure cleanup, duplicate actions, and large Unicode payloads.

- Final production and instrumentation APK build: successful, 6 seconds.
- TranscriptHistoryTest: 7 JVM tests, 0 failures/errors/skips.
- Final focused fixes: 16 instrumentation tests pass, 37.090 seconds, including adaptive header relocation plus restoration.
- Large Unicode transcript: 1 test passes, 10.017 seconds; 66000 UTF-16 characters per edited body survive recreation with length/hash checks.
- Native pointer/IME controls: 4 tests pass, 13.333 seconds; finger and stylus in Library and actual MainActivity.
- Final broad sweep 1: 27 pass, 85.843 seconds, no failures/skips/new findings. Capture, link admission, entry points, route validation, rail interaction, short layouts, RTL and large-text accessibility.
- Final broad sweep 2: 34 pass, 75.745 seconds, no failures/skips/new findings. Library, recording queue, fake billing and delivery, locale recreation, auto-stop, unavailable location choices, widgets, pickers and composer preferences. The initial run had 33 passes and one test-setup failure: the language test assumed onboarding. It now verifies Arabic on either starting screen without clearing app data.
- Live route check: typed QA/Rotation.md + Top, rotated portrait → landscape → portrait; dialog, path, and placement survived. Back canceled without applying; reopening showed the original empty path/preset placement. Traversal path ../escape.md disabled Apply and survived Home → relaunch; cancellation restored the untouched Capture draft. Final live Library focus/type/delete worked without ANR; query cleared, All selected and Needs attention unchecked. Activity All showed no waiting items. Returned to portrait Capture, empty Meeting Notes draft, Documents destination, no route override and keyboard hidden. App locale restored by test cleanup. Test widget IDs and preference changes cleaned by finally blocks.

## Limits and environment observations

Earlier System UI and app input ANRs remain unclassified. A sampled app main thread was idle in nativePollOnce; this does not establish a root cause. Recovery used the same AVD with snapshots disabled, preserving userdata, and only device-scoped operations. Final pointer controls and live Argent Library typing passed, but this is not proof that an intermittent ANR cannot recur. Argent occasionally returned stale accessibility trees after navigation; device-scoped service refresh restored accurate trees before further taps. No global cleanup was used.

No physical device, real network failure recovery, purchased entitlement, model inference, or actual outbound sharing was exercised in this pass. Delivery and billing regression cases use isolated fakes. This coverage does not prove all edge cases are bug-free.


## Result and artifacts

All eight confirmed bug categories are fixed and verified. The checks total 82 passing emulator instrumentation cases (16 focused, 1 large editor, 4 pointer controls, 27 + 34 broad) and 7 passing JVM search tests. Large-editor and pointer cases passed before the final route-only correction; the full relevant route/location focused suite and both broad sweeps passed after it. `git diff --check` passed.

The before-fix logs, build output, final focused/broad logs and route screenshots in this directory preserve evidence. The ignored session ledger remains at `.pi/android-qa-loop/ledger.md`. Native build ownership was released and subsequently granted to Health Android; no Vox compile remains queued. The Vox emulator and Argent services remain running.
