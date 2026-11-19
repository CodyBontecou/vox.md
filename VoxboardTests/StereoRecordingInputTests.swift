import AVFoundation
import UIKit
import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class StereoRecordingInputTests: XCTestCase {
    typealias Candidate = StereoRecordingInput.DataSourceCandidate

    func testPrefersFrontThenBackStereoSource() {
        let sources = [
            Candidate(orientation: .bottom, supportsStereo: false),
            Candidate(orientation: .back, supportsStereo: true),
            Candidate(orientation: .front, supportsStereo: true),
        ]
        XCTAssertEqual(StereoRecordingInput.preferredStereoSourceIndex(in: sources), 2)
        XCTAssertEqual(StereoRecordingInput.preferredStereoSourceIndex(in: Array(sources.prefix(2))), 1)
        XCTAssertEqual(
            StereoRecordingInput.preferredStereoSourceIndex(in: [
                Candidate(orientation: .bottom, supportsStereo: false),
                Candidate(orientation: nil, supportsStereo: true),
            ]),
            1
        )
    }

    func testNoStereoPolarPatternFallsBackToMono() {
        XCTAssertNil(StereoRecordingInput.preferredStereoSourceIndex(in: []))
        XCTAssertNil(StereoRecordingInput.preferredStereoSourceIndex(in: [
            Candidate(orientation: .front, supportsStereo: false),
            Candidate(orientation: .bottom, supportsStereo: false),
        ]))
    }

    func testOnlyTheBuiltInMicRouteRecordsStereo() {
        XCTAssertTrue(StereoRecordingInput.routeAllowsStereo([.builtInMic]))
        for port: AVAudioSession.Port in [.bluetoothHFP, .headsetMic, .usbAudio, .carAudio, .lineIn] {
            XCTAssertFalse(StereoRecordingInput.routeAllowsStereo([port]), port.rawValue)
        }
        XCTAssertFalse(StereoRecordingInput.routeAllowsStereo([]))
    }

    func testInputOrientationFollowsTheInterface() {
        XCTAssertEqual(StereoRecordingInput.stereoOrientation(for: .portrait), .portrait)
        XCTAssertEqual(StereoRecordingInput.stereoOrientation(for: .portraitUpsideDown), .portraitUpsideDown)
        XCTAssertEqual(StereoRecordingInput.stereoOrientation(for: .landscapeLeft), .landscapeLeft)
        XCTAssertEqual(StereoRecordingInput.stereoOrientation(for: .landscapeRight), .landscapeRight)
        XCTAssertEqual(StereoRecordingInput.stereoOrientation(for: .unknown), .portrait)
    }

    func testNotRequestedNeverTouchesTheSession() {
        XCTAssertEqual(StereoRecordingInput.configure(requested: false), .notRequested)
    }

    // MARK: - Which recordings may use stereo

    func testKeyboardAndContinuousDictationStayMono() {
        let ending: (RecordingCommand) -> VoiceAutoStopEndOfSpeechAction? = { _ in .endRecording }
        let continuing: (RecordingCommand) -> VoiceAutoStopEndOfSpeechAction? = { _ in .commitSegmentAndContinue }
        let off: (RecordingCommand) -> VoiceAutoStopEndOfSpeechAction? = { _ in nil }

        XCTAssertFalse(PersistentRecorder.oneShotMayKeepAudio(
            completionMode: .keyboardTranscription, flowId: nil, origin: nil, endOfSpeechAction: off
        ))
        XCTAssertFalse(PersistentRecorder.oneShotMayKeepAudio(
            completionMode: .runVox(flowID: "flow"), flowId: "flow", origin: .quickRecord,
            endOfSpeechAction: continuing
        ))
        XCTAssertTrue(PersistentRecorder.oneShotMayKeepAudio(
            completionMode: .runVox(flowID: "flow"), flowId: "flow", origin: .quickRecord,
            endOfSpeechAction: ending
        ))
        XCTAssertTrue(PersistentRecorder.oneShotMayKeepAudio(
            completionMode: nil, flowId: "flow", origin: nil, endOfSpeechAction: off
        ))
    }

    // MARK: - Tap scratch buffer

    func testScratchInterleavesDuplicatesMonoAndGrows() {
        let scratch = StereoInterleaveScratch(initialFrames: 2)
        let left: [Float] = [1, 2, 3]
        let right: [Float] = [-1, -2, -3]
        left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                let out = scratch.interleave(left: l.baseAddress!, right: r.baseAddress!, frames: 3)
                XCTAssertEqual(Array(out), [1, -1, 2, -2, 3, -3])
                // A mono buffer after a route change fills both sides.
                let mono = scratch.interleave(left: l.baseAddress!, right: l.baseAddress!, frames: 2)
                XCTAssertEqual(Array(mono), [1, 1, 2, 2])
                XCTAssertTrue(scratch.interleave(left: l.baseAddress!, right: r.baseAddress!, frames: 0).isEmpty)
            }
        }
    }
}
