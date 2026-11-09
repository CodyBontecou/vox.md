# PR 70 final qualification — November 9, 2026

## Swift inference-gate diagnosis

At `7907cf14672f9df5636e49d0451a53d9cbe94695`, the hosted Swift package test `test_nonCooperativeWorkTimesOutAndKeepsInferenceSlotUntilFinished` threw `busy` at its final admission. The exact focused test passed locally. A small standalone harness using the unchanged production gate and deadline reproduced the failure by delaying callback completion beyond the test's fixed 300 ms sleep, then demonstrated normal gate release after actual completion.

This is a test synchronization race. Production gate and deadline code remain unchanged. The test now explicitly releases cancellation-ignoring work and waits until its gate call actually returns. Prompt timeout, timeout error identity, busy rejection while expired work owns the slot, and admission after completion remain asserted. The six-test group passed, followed by 25 successful cached repetitions of the changed test. Logs, the faithful standalone harness and source hashes are retained in [the evidence directory](../../artifacts/validation/pr70-final-qualification-20261109/).

## Recovery runtime regression

A task-owned API 36 arm64 AVD, `vox-pr70-final-api36-20261109`, was created with 4 GiB RAM and an isolated data disk. Existing emulators, simulators and physical devices were not used. Whereday's heavy build slot was released before this run.

The production repository/Room integration class passed all three tests on this emulator: deleting completed history cannot resurrect a delivered replacement; background drain replays a retired source without foreground refresh, including after access ends; and a busy intent with no pending package retains background retry. The instrumentation log reports `OK (3 tests)`, with no failure or skip status codes. No source change was needed after this runtime pass.

## Source freeze and full-model execution

This source/evidence commit freezes the Swift test correction before full Android qualification. The unchanged full producer will run all phases on this exact clean source; no subset flags, stale-receipt repinning, validator weakening or inference-network fallback are authorized. Exact source/APK/model hashes and phase outputs will be retained outside the temporary worktree, then integrated as evidence-only successors. Final results and cleanup are recorded in the completion receipt rather than inferred from these preliminary checks.

No merge, store submission, release or production write is included.
