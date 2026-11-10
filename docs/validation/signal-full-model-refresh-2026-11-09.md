# Signal full-model qualification refresh — 2026-11-09

Fresh full Android qualification executed on clean committed source `83e474ac516d1e361a2f66023238a9e21d10262f`, with explicit isolated emulator authorization. The unchanged full producer exited 0. No subset flags, source changes, validator exceptions, or recycled model receipts were used.

## Execution and results

Task-owned API 36 arm64 AVD `vox-full-model-83e474ac-20261109`, serial `emulator-5554`, 4 GB RAM. App and test APK assembly passed (156 tasks, 2m26s). The producer ran `apps/android/scripts/validate-local-intelligence.py --fixtures <external>/fixtures --output <external>/output` with explicit `ANDROID_HOME` and the owned `ANDROID_SERIAL`.

- General phone: 123 tests; Vosk: 2; named Whisper Tiny: 2; live instruction: 1; live speaker: 1. Total 129 instrumentation tests, no failures or skips.
- Pinned real Qwen model: all six shared instruction cases passed offline; production repository delivery and retry without model both verified.
- Real speaker benchmark: two speakers, duration-weighted attribution error 0.
- Strict unchanged report validator passed against fresh Android reports and unchanged Apple baseline. Historical Apple speaker error remains 0.2929927665936347; this run does not refresh Apple qualification.
- App SHA-256: `ebe7a431ab15b888d0ca17a79c2dfee9e8e67999833a84625e98064927ec8744`.
- Test APK SHA-256: `7b5975fcac495826cf97894663b4fa1f8ee0864b213d7e8cd11cd496f345dc2e`.

The receipt records the actual source revision, clean-tree preflight, all 28 implementation hashes, four pinned model fixture digests, APK hashes, device identity and mandatory phase counts. Integration independently verified the APK/fixture bytes and composed report validation before updating retained evidence.

## Retention and limits

Raw outputs, preflight/build/download/producer logs, prior Android reports and checksums are retained in `artifacts/validation/local-intelligence-2026-11-09/`. The three current Android report files also replace the legacy-date canonical `local-intelligence-2026-11-01/` copies because existing consumers use that path. Both Apple reference reports are unchanged. Previous Android reports remain under `previous-android/`.

External task-owned storage and APKs remain at `/private/tmp/vox-model-qa-83e474ac-20261109` and `/private/tmp/vox-full-model-83e474ac-20261109`; shared checkouts and other devices were not used. No manual redesign UI acceptance, physical-device qualification, release, store upload or production action is claimed. Translation review remains machine/agent-authored, not human-approved.

Initial PR 70 at source `83e474ac` completed 8 successful and 3 failed checks. All three failed solely on the stale retained Android receipt; Android foundation compilation was therefore not reached. Fresh evidence resolves that reproduced precondition locally. Final hosted check verdicts must be read from the PR at its final evidence/oracle successor SHA; they are not inferred from this runtime pass.
