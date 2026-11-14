# Live Notes full model qualification (2026-11-14)

Full Android model gate rerun for PR #79 (Live Notes), because Live Notes changes
three evaluation-pinned sources (`VoxApplication.kt`, `CaptureRepository.kt`,
`AndroidCaptureRepository.kt`).

- Source: `e932bcea`, clean tree (recorded in `model-output/receipt.json`).
- Producer: `apps/android/scripts/validate-local-intelligence.py`, full phone suite
  (no `--only-*` flags), pinned fixtures by exact SHA-256.
- Device: emulator `vox-parity-checks-api36-20261101` (Pixel 7 profile, API 36,
  arm64-v8a), RAM set to 4096 MB (MemTotal 4014920 kB, same as the 2026-11-09 run)
  because the instruction model requires 3 GB. Gboard stylus handwriting disabled
  (`settings put secure stylus_handwriting_enabled 0`) after its first-run stylus
  tutorial overlay intercepted injected input.
- Result: general phone 127/127, local speech 2, named speech model 2, pinned
  instruction model offline 1, real-speech speaker attribution 1. Strict validation
  passed against the retained Apple reports (`strict-validation.log`).

The reports and receipt are copied into `artifacts/validation/local-intelligence-2026-11-01/`,
which `validate-intelligence-evaluations.py` reads.
