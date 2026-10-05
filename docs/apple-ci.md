# Apple CI simulator policy

The iOS app-hosted suite runs on an available iPhone whose runtime matches the
selected Xcode's iOS Simulator SDK **major/minor version**. With Xcode 26.6 this
means iOS 26.5. Runtime/device availability is read from `simctl` JSON rather than
from the first phone in its human-readable listing. The selector logs the SDK,
runtime version and device UDID, and fails rather than silently falling back to
an older runtime or a newer beta. A missing runtime must be installed on the
runner. The baseline requires iOS 26.4 or newer.

Run the selector and its portable regression tests with:

```sh
python3 scripts/select-ios-test-simulator.py
python3 -m unittest discover -s scripts/tests -p test_ci_ios_simulator.py
```

The tests execute the workflow's actual selection step with a fake `xcrun`, so
restoring the old first-device selection also breaks the regression tests. They
run in the existing repository-contracts job, including on Linux.

## Why not the first installed runtime?

[Apple CI run 37069143803](https://github.com/CodyBontecou/vox.md/actions/runs/37069143803)
selected iOS 26.2 despite using Xcode 26.6. Its 13 failed tests were process
crashes, not failed assertions. The 14 retained crash reports show the same path:

```text
TaskLocal::StopLookupScope::~StopLookupScope
swift_task_deinitOnExecutorImpl
swift_task_deinitOnExecutorMainActorBackDeploy
<main-actor class>.__deallocating_deinit
```

This matches [Swift issue #88036](https://github.com/swiftlang/swift/issues/88036)
and [the upstream runtime fix](https://github.com/swiftlang/swift/commit/29245e4ef29d7cd039c31918993f7d25aae8382b).
Without a Swift task, the old runtime allocates a task-local marker from the task
allocator and later passes it to `free`. The fix uses `malloc` for that allocation.
XCTest's synchronous execution and SwiftUI teardown can hit this path; audio
fixtures and WatchConnectivity are not required.

The matching minimal reproduction is:

```swift
enum ReproLocal {
    @TaskLocal static var marker: Int = 0
}

final class Session {}

@main
struct Repro {
    static func main() {
        ReproLocal.$marker.withValue(1) {
            withExtendedLifetime(Session()) {}
        }
        print("PASS: synchronous deallocation inside a task-local scope")
    }
}
```

Compile it with the same isolation/language/deployment settings as the app:

```sh
xcrun --sdk iphonesimulator swiftc \
  -parse-as-library -swift-version 5 -default-isolation MainActor \
  -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -target arm64-apple-ios17.6-simulator repro.swift -o repro
xcrun simctl spawn <simulator-udid> "$PWD/repro"
```

## Local verification (2026-10-05)

Using PR #34 head `4600bded54ea725dbc22461f5437bcd7ae38193d` and Xcode 26.6
(`17F113`, Swift 6.3.3):

- The standalone reproduction aborts in all three runs on iOS 26.2 (`23C52`,
  the downloadable release-candidate runtime). Its crash frames match CI's
  stable iOS 26.2 (`23C54`) reports.
- The identical binary passes on iOS 26.5 (`23F77`). Removing default main-actor
  isolation also makes it pass on 26.2; removing the task-local binding makes
  the original reproduction pass on 26.2.
- The existing
  `ContinuousDictationSessionTests.testDefaultSessionLimitMatchesDocumentedGuardrail`
  independently aborts on 26.2 with the same runtime stack, and passes on 26.5.
- All 246 iOS app-hosted tests, including the five Toggle Recording registration
  tests, pass in two full runs on 26.5 without failure retries or skipped tests.
- All 15 simulator-selection regression tests pass, as do the repository
  contracts (25 script tests and 131 contract tests) and capture-view structure
  guard.

The retry workaround is removed: `-retry-tests-on-failure` does not reliably
rerun a test whose host process aborts. This policy changes the CI baseline,
**not** the app's deployment target, recording engine, or supported-OS behavior.
It does not fix Apple's older installed runtime or establish physical-device
Action Button behavior. Older-OS compatibility remains a separate verification
surface; do not treat a green current-runtime suite as proof of that coverage.
A fresh GitHub Actions run of the patch is still required.
