# Issue #22: iOS CI allocator investigation

Status: **CI test-host runtime isolation implemented; not an application allocator fix.**
Old-runtime reproduction and a fresh full hosted-CI run remain open.

## Retained evidence

[Apple CI run 37069143803](https://github.com/CodyBontecou/vox.md/actions/runs/37069143803),
job `111044175046`, attempt 1, tested PR #34 head
`4600bded54ea725dbc22461f5437bcd7ae38193d` on 2026-10-02.
The downloaded diagnostics artifact has SHA-256
`f1f3a0a45b0888b94438e86bd276eb6b3533763226a48cd20ae21c26ddb3ea04`.

- Toolchain: Xcode 26.6 (`17F113`), Swift 6.3.3, iOS **26.5 SDK**.
- Executed simulator, from the xcresult: iPhone 17 Pro, iOS **26.2 (`23C54`)**.
  The workflow selected the first matching device across available runtime versions.
- xcresult: 233 passing tests, 13 failing tests, zero skips. Fourteen `.ips`
  reports survived, including a repeated crash after host relaunch.
- Thirteen malloc messages identify `0x262552740`; one identifies `0x262552760`.
  The message is “pointer being freed was not allocated,” not proof of a double-free.
- The original quote-cache victim passed in this run. The first abort occurred
  while releasing `AudioFilenamePresetState` in the audio-filename settings test.

All 14 triggered-thread stacks share these freeing frames:

```text
___BUG_IN_CLIENT_OF_LIBMALLOC_POINTER_BEING_FREED_WAS_NOT_ALLOCATED
swift::TaskLocal::StopLookupScope::~StopLookupScope()
swift_task_deinitOnExecutorImpl(...)
swift_task_deinitOnExecutorMainActorBackDeploy
<isolated object's __deallocating_deinit>
```

The released objects were `AudioFilenamePresetState` (1),
`CapturePresetEmojiNativeInputState` (1), `ContinuousDictationSession` (5),
`MarkdownComposerController` (1), `PresetRenderingState` (4), and
`QuickCaptureViewModel` (2). Deferred UI teardown sometimes freed an earlier
suite's helper during the next test. The current test's name is not a causal frame.

## Attribution and limits

Swift upstream commit
[`29245e4ef29d7cd039c31918993f7d25aae8382b`](https://github.com/swiftlang/swift/commit/29245e4ef29d7cd039c31918993f7d25aae8382b)
fixes `TaskLocal::MarkerItem::create` to use `malloc` when no Swift task exists.
Before the patch it used `_swift_task_alloc_specific` even without a task,
while marker destruction used `free` in that case. Isolated deinit's
`StopLookupScope` uses that marker. This is a specific upstream allocation/free
mismatch consistent with every retained freeing stack, rather than an inferred
corruption of orphan audio or quote-cache bytes. The patch is present in the
`swift-6.3.3-RELEASE` source.

This investigation did **not** capture the original allocation with LLDB or
reproduce the allocator abort locally. The available local simulator is iOS
26.5 (`23F77`); iOS 26.2 is not installed. Source-tag membership alone does not
attest the Swift runtime inside an OS image. Nor do these newer crash reports
retrospectively establish the freeing frames of older failures whose reports
were lost. No production WatchConnectivity, audio, or quote service was changed.

## Change and regression surfaces

`scripts/select-issue22-ios-test-simulator.py` requires an available iPhone
simulator matching the selected Xcode SDK version. It fails with a retained
inventory if that runtime is missing; it never silently falls back to an older
runtime or a newer beta. This isolates CI on the pinned toolchain's runtime
without changing dependency versions, app deployment targets, or the tests run.
It is a **runtime mitigation**, not a fix to affected OS runtimes or app users.

`Issue22AllocatorDeinitTests` exercises isolated deinit with a bound task-local
value both inside a Swift task and in a task-free main-thread callback. Each
probe releases 64 objects, checks that destruction completed, checks that deinit
cannot read the caller's task-local binding, and checks that the caller's binding
survives. A third probe reaches the production `ContinuousDictationSession`
deinit from the same task-free context. These probes run normally in the
app-hosted target; there is no OS skip or quarantine.

Diagnostics now retain the source revision, host/toolchain versions, runtime
inventory/selected destination, xcresult summary (including the executed OS),
and test tree. Crash collection is limited to this invocation's `Voxboard-*.ips`
reports. Artifact names contain both run ID and attempt so a passing rerun cannot
replace a failing attempt's evidence. PR #34's separate App Intents metadata
retention must remain alongside these paths when integrating.

## Verification, 2026-10-04

Local toolchain: Xcode 26.6 (`17F113`), Swift 6.3.3
(`swiftlang-6.3.3.1.3`), macOS 26.5.1 (`25F80`), dedicated iOS 26.5 simulator.
Source: base `4f5bd7d0dd88b0c22dc13dac5e9c780da43c5991` plus the new probes.

1. A targeted app-hosted invocation of
   `ContinuousDictationSessionTests/testDefaultSessionLimitMatchesDocumentedGuardrail`
   passed before any fix. This is not a local red allocator reproduction.
2. Context-controlled probes plus all tests in the persistence-fixture,
   audio-filename, emoji-editor, continuous-dictation, and Quick Capture rendering
   suites: **54 tests × 3 iterations = 162 executions, zero failures/skips**.
   No retry-on-failure flag was used; no allocator message or unexpected relaunch
   appeared. Both task-free assertions and all 576 probe destructions passed.
3. The original selector was executed against a synthetic registry with iOS 26.2
   first and 26.5 second. The SDK-matching assertion failed. The new selector and
   workflow wiring pass the same policy regression. The old crash collector also
   failed a synthetic stale/unrelated-report exclusion regression.
4. Eleven Python selector/retention tests, project contracts (21 script tests and
   131 contract tests), and capture structure (14 positive/negative fixtures,
   three production files) passed. Heavy commands used the fleet build gate.

The two local allocator approaches are green on the available newer runtime.
No third speculative production change was attempted. Passing newer-runtime
probes is not proof that the old-runtime bug has been eliminated.

## Remaining gates

- Run the probes on the failing iOS 26.2 image with the same toolchain, preferably
  under LLDB at `malloc_error_break`, retaining the allocation/free frames and
  actual task context. The old-runtime failure prediction has not been executed.
- Execute fresh full Apple CI on the integrated changes. SDK-matched runtime
  availability on the hosted image has not been established by this local run.
- If the signature occurs on the SDK-matched runtime, retain that attempt and
  investigate it before adding a workaround. Do not label assertion retries as
  process-crash coverage.
- No physical-device installation, microphone capture, or hardware QA was done.
  Application behavior on affected older OS runtimes remains outside this CI
  mitigation. Do not mass-change actor-isolated deinits to hide the issue.
