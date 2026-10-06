# Reversible recording stitches

In the iOS Recording Queue, choose **Review Nearby Clips** or **Stitch Recordings**. On macOS, use **Stitch Recordings** in Activity. Select at least two saved, idle recordings and confirm **Stitch**.

The result is a separate local recording in chronological order. Open **Original Clips** to inspect individual recordings, or switch to **Individual Clips** to see them in the ordinary list. **Undo Stitch** removes only the local combined recording, not its originals or previously delivered files.

## Safety and boundaries

- Nothing is stitched automatically. Suggestions use a conservative two-minute estimated gap, matching source/language/delivery context, and known continuous-session identifiers. Timestamps are hints, not evidence of non-overlapping or complete audio.
- Concatenation does not add gaps or trim overlapping speech. It normalizes the derivative to 16 kHz mono PCM WAV; original files remain byte-for-byte unchanged.
- The derivative is manual, permanently retained work with no delivery preset. Choose a preset explicitly to transcribe or deliver it.
- Original jobs keep their transcripts, delivery snapshots, IDs, phases, and errors. Stitched originals are excluded from grouped-view Retry All; individual-view Retry All and per-clip actions remain available.
- Active jobs, immediate/idle queued jobs, multi-artifact meeting jobs, missing audio, nested stitches, duplicate selections, and originals already claimed by a stitch are rejected.
- Active stitches and pending bundle-commit journals protect original audio from retention cleanup and deletion. This also applies when a full disk prevents journal reconciliation.
- Undo retains originals permanently before releasing the group. Their recording/delivery state is unchanged; users can change retention or delete them individually afterwards.
- Stitching is local, streaming, cancellable work. In-process failures roll back the derivative; durable bundle intents reconcile interrupted publication without losing provenance. No timestamp-based audio recovery or automatic retry is performed.

## Implementation

- `Packages/VoxboardShared/Sources/VoxboardShared/RecordingStitch.swift`: provenance, eligibility, proximity hints.
- `RecordingJobStore.swift`: coordinated creation, journaled publication, original retention protection, undo.
- `RecordingJobQueue.swift`: capture suspension, grouped/individual projections, explicit processing.
- `AudioFileConverter.swift`: bounded conversion/concatenation. Regression tests caught and fixed an Int16/Float32 buffer mismatch and an undrained converter tail.
- `Voxboard App Shared/RecordingStitchViews.swift`, `RecordingQueueViews.swift`, and `Voxboard Mac/MacActivityView.swift`: native selection and original access. Accessibility-size mode selection uses a scalable menu instead of a small segmented control.

## Verification

`RecordingStitchTests.swift` adds 14 regressions covering suggestion boundaries, selection validation, original byte/state preservation, relaunch, retention, undo, cancellation, copy/invalid-audio failures, mixed sample rates, interrupted publication with blocked I/O, and explicit-only derivative processing. The nine-minute streaming case verifies all **8,641,600** output frames; short positive/negative samples verify ordering and PCM fidelity.

Local evidence under `.derived/pr39-stitch-checks/` in the main checkout:

- `package-tests-final.log`: 1,039 XCTest cases plus 10 Swift Testing cases passed.
- `ios-build-final.log`, `mac-build-final.log`: unsigned Debug builds passed.
- `contracts-final.log`: project contracts, including 131 script tests, passed.
- Native simulator walkthrough: suggestion review/cancel, manual selection, stitch, app relaunch, individual view, original expansion, and undo. SHA-256 checks verified all four synthetic originals; the three-clip derivative had exactly 960,000 frames (60 seconds). Final-build normal, dark, and largest-accessibility-size screenshots and AX trees are saved there.

The recorded Argent traces are exploratory artifacts, **not portable CI regressions**: its UIKit runner omits several virtual SwiftUI controls exposed by the accessibility tree. The initial trace also retains two diagnosed failed automation steps. No clean automated replay or native macOS interaction pass is claimed.

The initial synthetic QA phase did not modify real recordings or credentials, install on a physical device, change `main`, or commit/push code. Subsequent explicitly authorized device installations are separate deployment evidence; successful installation/launch is not a physical recording-integrity pass. This feature does not diagnose the previously reported Stop crash or establish completeness of the phone's recordings.
