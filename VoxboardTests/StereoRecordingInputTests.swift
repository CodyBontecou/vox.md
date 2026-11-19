import AVFoundation
import UIKit
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
}
