# PR 70 final qualification — November 9, 2026

## Swift inference-gate diagnosis

At `7907cf14672f9df5636e49d0451a53d9cbe94695`, the hosted Swift package test `test_nonCooperativeWorkTimesOutAndKeepsInferenceSlotUntilFinished` threw `busy` at its final admission. The exact focused test passed locally. A small standalone harness using the unchanged production gate and deadline reproduced the failure by delaying callback completion beyond the test's fixed 300 ms sleep, then demonstrated normal gate release after actual completion.

This is a test synchronization race. Production gate and deadline code remain unchanged. The test now explicitly releases cancellation-ignoring work and waits until its gate call actually returns. Prompt timeout, timeout error identity, busy rejection while expired work owns the slot, and admission after completion remain asserted. The six-test group passed, followed by 25 successful cached repetitions of the changed test. Logs, the faithful standalone harness and source hashes are retained in [the evidence directory](../../artifacts/validation/pr70-final-qualification-20261109/).

## Recovery runtime regression

A task-owned API 36 arm64 AVD, `vox-pr70-final-api36-20261109`, was created with 4 GiB RAM and an isolated data disk. Existing emulators, simulators and physical devices were not used. Whereday's heavy build slot was released before this run.

The production repository/Room integration class passed all three tests on this emulator: deleting completed history cannot resurrect a delivered replacement; background drain replays a retired source without foreground refresh, including after access ends; and a busy intent with no pending package retains background retry. The instrumentation log reports `OK (3 tests)`, with no failure or skip status codes. No source change was needed after this runtime pass.

## Source freeze and full-model execution

Source was frozen at clean commit `33ac5352465d409e0c25b2220228fac7977e8e40` before the unchanged full producer executed. Both the preflight and post-run checks confirm that exact commit and a clean tree. No subset flags, stale-receipt repinning, validator weakening or inference-network fallback were used.

The genuine full producer passed all 129 instrumentation tests: 123 general phone cases, two Vosk tests, two named Whisper Tiny tests, one six-case instruction benchmark, and one speaker benchmark. There were no failures or skips. All six Qwen instruction cases passed offline; production repository delivery and retry without the model were verified. Android speaker attribution error was 0. The unchanged strict validator passed the composed fresh reports against the unchanged Apple baselines; the Apple speaker error remains 0.2929927665936347 and is not refreshed by this run.

App APK SHA-256: `b4d182f0eb2ebf79fb18d90765ffaa872b3b860cb8ecaf0b717aef78bf42df7d`. Test APK SHA-256: `7b5975fcac495826cf97894663b4fa1f8ee0864b213d7e8cd11cd496f345dc2e`. All 28 receipt implementation hashes match both the frozen source commit and the final production source bytes. The fixture download log records the four exact model/audio digests.

Raw logs, preflight, reports, prior Android reports, APK/model/source hashes, the runner wrapper and checksums were retained first in `/Users/codybontecou/dev/vox.md/artifacts/validation/pr70-final-qualification-20261109`, outside the temporary source worktree, then copied into this branch. The three refreshed Android reports also replace the legacy-date canonical `local-intelligence-2026-11-01` copies used by existing consumers. Previous Android reports and both unchanged Apple baselines remain available. Source and evidence are retained independently of task-owned emulator/download/build cleanup.

These results qualify the named full-model suite and the three separate repository/Room regressions, not every SAF/provider/keystore crash mode, manual redesign UI acceptance, physical hardware or translation quality. Cleanup and final hosted-check outcomes are recorded separately after publication.

The complete local project-contract gate passed: 90 script tests, all 162 contract tests, project structure, capability conversion, validation definitions, 209 governed contract files/four mirrors and 305 implementation hashes. Its previously failing full-model receipt test now passes with the genuine fresh execution. No validator was weakened or bypassed.

Oracle regeneration used clean evidence/governance commit `baeaf18c11fc10fd1d997ee92ac4296667a5533c`. Every case output is unchanged. Committed-fixture check mode passed, followed by all 52 Rust workspace tests. The logs are retained alongside the model evidence.

## Task-owned cleanup

After source and evidence were pushed at `8b6b99b2ae098f6ef4857acaa8c7ed8c47462768`, remote identity and the clean source worktree were verified. Scoped Argent teardown found no live service for the task device. The exact owned AVD was then shut down gracefully and deleted; no process was using the removed paths. Only its registration/data, task fixture downloads, this worktree's generated app build directory and data-test APK output directory were removed. Source, retained receipts, other AVDs/devices, shared caches and Herdr tabs remain intact.

The observed filesystem free-space increase was 9,021,296,640 bytes; APFS sharing means this is not an exact attribution. The structured `cleanup.json` records exact removed paths and postconditions. Compact receipts remain both in this branch and outside temporary checkouts at the persistent evidence path above. Final hosted CI status is reported against the final pushed SHA rather than inferred from local tests.

No merge, store submission, release or production write is included.
