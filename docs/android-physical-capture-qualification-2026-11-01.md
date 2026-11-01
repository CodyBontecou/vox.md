# Android physical capture reliability and performance — November 1, 2026

Status: **In progress; the complete hardware/provider matrix is not qualified.**
The user has no Samsung device and requested proceeding with available providers;
OneDrive is not installed. A physical Pixel 7 and signed-in Google Drive are available.
These availability limits remain explicit; emulators cannot substitute for them.

## Implementation

Recording startup reconciles retained PCM before selecting the next chunk index.
A finalized chunk can be ahead of the last manifest checkpoint after process death;
reusing the old index could previously replace audio. Recovery now validates the
contiguous finalized prefix, promotes a valid checkpointed partial, derives duration
from retained sample bytes, and fails closed on missing/gapped/conflicting audio.
New chunks refuse an existing final or partial filename. Opening a second UI client
also preserves a currently active recorder instead of declaring it interrupted.
Regression tests cover the lost-index window, partial promotion, repeated recovery,
missing/gapped files, conflicting partials and second-client behavior.

Physical tests use a separate `md.vox.android.qualification` debug installation.
The existing owner app and its data are preserved. The debug control activity requires
the shell's DUMP permission and refuses a production application ID; release-artifact
validation rejects its inclusion. Recorder/model source hashes are embedded at build
time and checked against host source. A 65-minute device-side safety stop bounds an
unattended test, and host control brings the activity in front of an open folder picker.

Microphone audio stays in app-private, backup-excluded storage. The host retains only
state, durations, chunk sizes/hashes, on-device WAV-export verification, PSS/native
heap, thermal status and battery/charging metadata. Test audio is removed with the
isolated installation after checks. Model inputs are the existing public pinned corpus;
cloud writes contain only explicit synthetic text in `Vox-Qualification-20261101`.
Account names, provider tree URIs, microphone payloads/transcripts and raw system-wide
Perfetto traces are excluded from committed evidence.

## Campaign and targets

- Endurance: at least 3,600 seconds of actual microphone PCM and monotonic elapsed time in
  one uninterrupted process, at least 200 telemetry samples, no gaps over 45 seconds,
  completed manifest and verified PCM WAV header, size and hash. Imported/looped audio cannot qualify.
  The device-local sampler fsyncs metadata every 15 seconds, stops after both elapsed
  time and PCM targets are met, and survives a USB outage. A changed process, stale
  telemetry or an interrupted recording invalidates the run.
  The recording target is sampled PSS <=512 MiB and thermal status below Severe.
- Recovery: actual SIGKILL, force-stop and OS reboot, each followed by interrupted
  recovery, explicit resume and verified export. Every finalized chunk from before
  the fault must retain its exact bytes/hash after recovery and after resumed capture.
  Reboot requires a changed boot identity and credential-unlocked storage; this is
  orderly OS reboot evidence, not a power-cut test.
- Models: three production Vosk ASR requests plus three rounds of all six shared
  Qwen instruction cases. One-second app PSS/native-heap/available-memory/thermal
  samples accompany latency and correctness. The target is sampled PSS <=2 GiB,
  no low-memory state and thermal status below Severe. Critical thermal/low-memory
  feedback cancels the test; requests are bounded. This samples short ASR inputs,
  not one-hour ASR performance or all supported model/device tiers.
- Cloud: the real production repository delivers/readbacks a synthetic note through
  the selected Drive/OneDrive provider, then retries the same request without another
  document or changed bytes. The permission-repair campaign revokes only the test
  app's own tree grant and preserves the durable request before reauthorization.

Charging is recorded explicitly. A plugged-in run does not qualify battery drain.
Sampled memory peaks are not an instantaneous-allocation guarantee or leak proof.
Debug builds, instrumentation overhead, acoustic continuity, other OEMs/device tiers,
long-form ASR and sustained model stress remain limitations of these measurements.

## Reproduce

Build/install the isolated APK without clearing or replacing `md.vox.android`:

```sh
./apps/android/gradlew -p apps/android -PvoxPhysicalQualification=true :app:assembleDebug
python3 apps/android/scripts/qualify-physical-capture.py install --serial "$ANDROID_SERIAL"
```

Pregrant microphone/notification permissions only for the qualification installation.
The installer checks the APK's actual application ID and debuggable flag before adb;
it refuses an owner-app APK even if its filename looks like a qualification build.
Unlock the physical device after the reboot. The device-local hour test can continue
without USB; reconnect after completion to collect metadata. Other campaigns require
a stable connection. Run each output
into a fresh directory; no shortening flag is provided for the hour gate:

```sh
python3 apps/android/scripts/qualify-physical-capture.py record-device --serial "$ANDROID_SERIAL"
# After at least 61 minutes:
python3 apps/android/scripts/qualify-physical-capture.py collect-device --serial "$ANDROID_SERIAL" --output /tmp/vox-physical-hour
python3 apps/android/scripts/qualify-physical-capture.py sigkill --serial "$ANDROID_SERIAL" --output /tmp/vox-physical-kill
python3 apps/android/scripts/qualify-physical-capture.py force-stop --serial "$ANDROID_SERIAL" --output /tmp/vox-physical-force-stop
python3 apps/android/scripts/qualify-physical-capture.py reboot --serial "$ANDROID_SERIAL" --output /tmp/vox-physical-reboot
python3 apps/android/scripts/qualify-physical-capture.py models --serial "$ANDROID_SERIAL" --output /tmp/vox-physical-models
```

The model command needs the exact pinned public fixtures in
`apps/android/app/build/qualification-fixtures`, as staged by the existing full local
intelligence gate. Choose only the dedicated cloud test folder with `choose-provider`,
then run `provider-capture`, `provider-retry` and `provider-revoke`; reauthorize the same
folder before retrying the pending request. The app stores the URI privately.

`artifacts/validation/android-physical-capture-2026-11-01/matrix.json` is the evidence
index. `validatePhysicalCaptureEvidence` checks truthful partial evidence and hashes;
the separate `physicalCaptureReadiness` task requires every hardware/provider case.
An unavailable device/account never becomes a passed case or a verified ledger row.

## Results

The first Pixel attempt lost USB telemetry after 152 seconds. Reconnection allowed
the private recording to be stopped and its WAV to be verified; it does not qualify
the hour gate. The second host-sampled attempt lost USB after approximately 34 minutes
(135 samples); it also remains incomplete. Stop/final-state verification awaits
reconnection; the installed debug harness has a 65-minute device safety stop. A fresh
device-local campaign is required; neither interrupted attempt is promoted.

A 60-second physical
Perfetto sample reported no UI hangs and RSS 235.1→238.4 MiB; its 3.3 MiB warm-up growth
is not a confirmed leak. Kernel/context-switch frames are physical Linux frames;
the analyzer's generic emulator classification is disregarded. The raw trace remains
temporary; the repository retains only its digest and content-free summary.

The autonomous sampler passed a short emulator smoke check: telemetry advanced,
manual stopping correctly produced an incomplete result, and finalized PCM WAV
header/export verification passed. This is harness validation, not physical evidence.
The disposable emulator and its qualification installation were stopped/removed;
the disconnected Pixel's private test audio still needs verified cleanup. The owner
application has not been replaced or cleared.

## Automated regression results

The final Android CI command passed `check assembleDebugAndroidTest
:app:validateDebugArtifacts :wear:validateWearDebugArtifacts releaseReadiness`,
including lint, reviewed debug components, backup rules, four-ABI ELF checks,
optimized phone/Wear bundles and the unchanged 342-component SBOM. Results:

- 291 JVM tests, zero failures.
- 90 phone/model tests, zero skips, including all four mandatory real-model cases;
  the retained receipt records clean source `5aea785` and current production hashes.
- 22 ordinary data instrumentation tests, plus both dedicated quota phases across
  an actual fixture-package uninstall/reinstall boundary.
- Shared Swift: 655 + 381 XCTest tests and 12 Swift Testing tests.
- Rust: 49 workspace tests; formatting, strict Clippy and binding reproducibility.
- 65 script tests and 158 contract tests. The final run kept generated mirrors stable.
- Swift oracle: regenerated from clean `db43c26`, committed as `b5da62e`; all 14
  cases unchanged and the subsequent clean-source provenance check passed.
- Localization generation, intelligence evidence, ledger inventory and 277 governed
  implementation hashes validate. No parity status was promoted.

The initial combined data invocation incorrectly included two reinstall-only methods;
the final ordinary run excludes that class and the dedicated harness executes both
methods with the required uninstall. One contract run raced a mirror refresh; its
stable final rerun passed. Debug provider-grant lint was fixed and the full CI command
rerun successfully.

`validatePhysicalCaptureEvidence` passes the truthful incomplete matrix (0/14 full
physical cases). `physicalCaptureReadiness` correctly fails because the required
hardware/provider evidence remains incomplete. Pixel reconnection is required for
verified stop/cleanup, a fresh hour recording, actual fault/reboot recovery, model
memory/thermal runs and Drive delivery/retry. Samsung and OneDrive remain unavailable.
Existing implemented rows retain their pending broader physical/provider acceptance;
no capability is promoted from these partial results.
