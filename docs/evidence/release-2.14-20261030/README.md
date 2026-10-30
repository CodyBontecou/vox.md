# Vox.md 2.14 release and lifetime repricing — October 30, 2026

The owner explicitly authorized releasing iOS while Mac remains in review and applying the shared lifetime prices now, with the existing regional policy. This supersedes the earlier hold/freeze for this operation. No production purchase or restore was performed.

All 525 lifetime prices were read back from raw Apple API responses and matched the proposed product-specific point IDs and local amounts across 175 territories. US prices: Individual $49.99; Family $89.99; Family upgrade $39.99. Subscription prices were unchanged. Original manual/automatic schedules and base territories are retained as rollback evidence.

The copied proposal summary describes its historical October 29 proposal state, not current subscription availability or the result of this operation. Use `summary.json` and `*-verified-after.json` for current results.

The asc CLI `--resolved` output incorrectly resolved some raw point IDs to unrelated amounts (for example Argentina Individual reported $149.99 while Apple returned $12.99 for the same original point). Those snapshots are diagnostic only. Verification used raw API responses with included price-point attributes; current prices matched the original proposal before mutation.

Discord suppression for version 2.14 on both iOS and Mac was tested and deployed before the release. All 32 webhook tests passed, including a Vox.md-specific no-request/retry check. Central webhook source commit: `4dc3b18`; production Worker version: `5d9895dd-d9e1-4428-851f-3293bdf6d9e4`. Its health endpoint returned `ok`.

Apple accepted the release request for iOS version `805e71b5-fba0-4e6c-85e5-1df5373c51b1`, build 59 (`6aedefe1-ad65-48b8-8be6-6533a2fa6ef4`). See the release response, post-release state and Discord delivery audit files for subsequent evidence.

Final readback: iOS is **READY_FOR_DISTRIBUTION**; Mac remains **WAITING_FOR_REVIEW**. The public US lookup still returned 2.13 while propagation was pending. No release delivery row/Discord message was recorded at verification; Apple’s release webhook had not arrived. The deployed version-specific suppression remains active for both platforms, delayed webhooks, and retries.
