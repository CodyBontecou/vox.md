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

    // MARK: - Stereo must be confirmed by the route

    func testStereoCountsOnlyWhenTheRouteReportsIt() {
        let front = NSNumber(value: 1)
        let back = NSNumber(value: 2)
        XCTAssertTrue(StereoRecordingInput.stereoApplied(
            selectedDataSourceID: front, selectedPattern: .stereo, requestedDataSourceID: front
        ))
        // Pattern not (yet) applied, wrong source, or nothing reported: mono.
        XCTAssertFalse(StereoRecordingInput.stereoApplied(
            selectedDataSourceID: front, selectedPattern: .omnidirectional, requestedDataSourceID: front
        ))
        XCTAssertFalse(StereoRecordingInput.stereoApplied(
            selectedDataSourceID: back, selectedPattern: .stereo, requestedDataSourceID: front
        ))
        XCTAssertFalse(StereoRecordingInput.stereoApplied(
            selectedDataSourceID: nil, selectedPattern: nil, requestedDataSourceID: front
        ))
        XCTAssertFalse(StereoRecordingInput.hasStereoSelection)
    }

    func testDualMonoFramesAfterARouteChangeAreCounted() {
        let scratch = StereoInterleaveScratch(initialFrames: 4)
        let mono: [Float] = [0.1, 0.2, 0.3]
        let right: [Float] = [-0.1, -0.2, -0.3]
        mono.withUnsafeBufferPointer { m in
            right.withUnsafeBufferPointer { r in
                _ = scratch.interleave(left: m.baseAddress!, right: r.baseAddress!, frames: 3)
                XCTAssertEqual(scratch.takeDuplicatedFrameCount(), 0, "True stereo is not counted")
                let out = scratch.duplicateMono(m.baseAddress!, frames: 3)
                XCTAssertEqual(Array(out), [0.1, 0.1, 0.2, 0.2, 0.3, 0.3])
                _ = scratch.duplicateMono(m.baseAddress!, frames: 2)
                XCTAssertEqual(scratch.takeDuplicatedFrameCount(), 5)
                XCTAssertEqual(scratch.takeDuplicatedFrameCount(), 0, "Reading resets the count")
            }
        }
    }

    // MARK: - The input node decides stereo vs mono

    func testInputNodeChannelsDecideTheKeptLayout() {
        typealias Input = StereoRecordingInput
        let confirmed = Input.Outcome.stereo(dataSource: "Front", routeConfirmed: true)
        let late = Input.Outcome.stereo(dataSource: "Front", routeConfirmed: false)
        // Configured stereo + a 2-channel node: stereo, even if the route
        // reported the pattern late.
        XCTAssertEqual(Input.keptChannelCount(outcome: confirmed, inputNodeChannels: 2), 2)
        XCTAssertEqual(Input.keptChannelCount(outcome: late, inputNodeChannels: 2), 2)
        // Configured but the node still delivers one channel: mono.
        XCTAssertEqual(Input.keptChannelCount(outcome: confirmed, inputNodeChannels: 1), 1)
        // A 2-channel interface that was not set up for stereo (USB, line in,
        // or Stereo off) keeps today's mono path.
        XCTAssertEqual(Input.keptChannelCount(outcome: .notRequested, inputNodeChannels: 2), 1)
        XCTAssertEqual(
            Input.keptChannelCount(outcome: .unavailable(reason: "input route [usbAudio]"), inputNodeChannels: 2), 1
        )
    }
}
