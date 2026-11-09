# PR 70 recovery persistence corrections — 2026-11-09

Implemented on reviewed head `8c82c249fff024cc3c9087ea8382c327f74958f8` in the existing Signal worktree. The original shared checkout was left untouched. Initial validation performed no commit, push, GitHub write, device execution or production action. The user subsequently authorized committing and pushing these corrections to PR 70.

## Behavior

- Replacement replay and duplicate submit/retry use the permanent verified quota/terminal tombstone. Deleting the separate Library completion row cannot recreate a delivered replacement or make a duplicate retry appear unavailable.
- Foreground refresh and the background drain share package reconciliation and recovery-intent replay before selecting pending packages. Intent replay can enqueue a replacement even when the original is already discarded. Busy leases and uncertain persistence retain a background retry opportunity when there is no pending replacement package yet.
- No persisted schema, public core API, model behavior, or entitlement admission policy changed.

## Verification

The portable regression loop temporarily restored the old package-only reconciliation behavior and then automatically restored the fix. All three new JVM regressions failed under the old behavior: interruption before enqueue, occupied source lease, and enqueue persistence failure. The final production helper passed those tests.

```sh
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home \
ANDROID_HOME=/Users/codybontecou/Library/Android/sdk \
./gradlew --offline --no-daemon --max-workers=2 \
  :data:testDebugUnitTest :data:compileDebugAndroidTestKotlin
```

Executed from `apps/android`: 106 data JVM tests passed, zero failures/errors/skips. The separate focused `:app:testDebugUnitTest --tests md.vox.android.CaptureDrainWorkerTest` passed its one retry-policy test. Three new repository/Room integration tests compiled: deleted completion history plus replay/retry; background restart after retirement without foreground refresh, including ended access; and a busy intent with an empty pending-package queue. These integration tests were **not executed**. Portable tests use JVM filesystem/lease fakes and do not qualify actual Android fsync/Room/provider behavior.

Logs and focused JUnit XML are retained in [the evidence directory](../../artifacts/validation/pr70-recovery-persistence-fixes-2026-11-09/).

The portable contract validator passed (208 governed files, 98 fixtures, four mirrors), and the toolchain validator passed (305 governed implementation paths). The complete contract suite ran 162 tests: 161 passed, with its sole error being the expected stale-model-receipt rejection described below. `git diff --check` passed. The final integration-test isolation wrapper was compiled successfully after the data JVM run; it changes only test database isolation.

## Evidence boundaries

Implementation inventory hashes and the portable contract manifest are refreshed to these actual source bytes. The full model gate correctly rejects the retained receipt because `AndroidCaptureRepository.kt` changed. Historical model receipts and pass flags remain unchanged; no new qualification is claimed. The initial oracle check correctly refused the uncommitted tree. Publication follows the clean-source commit and oracle-regeneration sequence; model qualification remains outstanding and must not be bypassed by editing receipt or provenance fields.
