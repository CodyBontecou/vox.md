# Shortcut recording / invalid HTTP retry diagnosis

## Scope

Investigated the reported nine-minute Action Button / Toggle Recording session,
multiple attention-needed audio files, and ineffective Keep/Retry actions in the
HTTP-enabled checkout `feat/pr39-exclusive-capture-target`.

This patch fixes a reproduced retry failure, not an unconfirmed hardware crash.
Existing uncommitted PR39 work and `main` were preserved. No physical app was
installed, launched, reset, or changed by this investigation. No user recording
was edited, deleted, merged, or sent to a network endpoint.

## Findings

- A failed recording owns an immutable preset snapshot. If its HTTP URL was
  blank, editing the preset later did not fix the queue job: ordinary Retry
  supplied no delivery override, so the job failed with `Enter a delivery URL.`
  again. The deterministic queue test reproduced this before the fix.
- The device's saved Quick Record continuous-dictation preference was enabled.
  The recorder commits separate spans at speech pauses in this mode. This is a
  plausible explanation for separate files; it does not establish their contents,
  completeness, chronological grouping, or that a crash caused fragmentation.
- Keep Permanently works in the storage/queue regression with an invalid HTTP
  endpoint. It changes retention only: the delivery remains failed and therefore
  still needs attention. This does not prove the reported native menu interaction
  worked on the device.
- The only available Voxboard crash report was dated October 5, 2026, at 17:24
  (+0100), build 51 / 2.9 on iOS 27. Its triggered thread asserted in AppIntents.
  There was no matching October 6 report in the queried crash-log domain. Do not
  attribute the reported stop event to that older report without time correlation.
- Read-only device file listings did not expose the recording artifacts. No
  claims are made about recovery or completeness of the actual nine-minute audio.
  A local copy of preferences used to inspect recording flags was removed after
  inspection; device preferences were not changed.

## Fix

`RecordingJobQueue.retry` reads the durable job rather than relying on a stale
UI snapshot. `RecordingJobRetryDelivery` may repair an invalid saved HTTP URL
only on an explicit failed-job retry, using the same enabled preset's currently
valid HTTP settings. It preserves the job identity, original enrichment, location,
audio, and other preset policies. An explicit delivery override takes precedence.

Valid frozen endpoints, queued background work, Directory routes, deleted or
disabled presets, different preset IDs/targets, and still-invalid replacements
are not silently rerouted. Insecure local HTTP still requires saved explicit
consent. Existing Keychain-only credential persistence is unchanged. A prepared
HTTP handoff remains owned by URL Deliveries; this patch does not alter its bytes,
endpoint, retry window, or idempotency identity.

## Verification

Evidence logs are ignored local artifacts in the parent checkout's
`.derived/pr39-recording-recovery/`.

- Red: `swift test --package-path Packages/VoxboardShared --skip-update
  --disable-automatic-resolution -j 2 --filter
  'RecordingJobQueueTests.test_failedHTTPRecording'` reproduced a second failed
  attempt with the original blank URL (`retry-red.log`).
- Green: the final test calls the real `queue.retry(failed)` with no delivery
  override, injecting only preset lookup. It completes with repaired HTTP settings,
  unchanged frozen processing policy, and retained source audio
  (`retry-direct-green.log`).
- Full package suite: **1,025 XCTest cases + 10 Swift Testing cases**, no failures
  (`package-tests.log`), including retention, recovery, retry routing, valid-endpoint
  freezing, explicit overrides, and local-HTTP consent.
- Unsigned iOS Simulator and macOS app builds passed (`ios-build.log`,
  `mac-build.log`). Project contracts passed (`contracts.log`).
- `git diff --check` passed. No temporary debug instrumentation remains.

## Blocked follow-up

The exact Stop/crash and native Keep interaction were not reproduced. Next input:
approximate recording start/Stop time and whether Stop was tapped in the app,
Live Activity/Lock Screen, or shortcut; a matching crash report or redacted queue
error and recording metadata would let the hardware path be correlated. Do not
merge timestamp-near files blindly: continuous spans and duplicate fallback
journals may not have the same grouping/overlap semantics. Preserve or share the
existing audio before attempting destructive recovery.
