import XCTest
@testable import Voxboard

@MainActor
final class RecordingInputValidationTests: XCTestCase {
    func testZeroFilledInputIsAnInputFailureNotNoSpeech() {
        XCTAssertEqual(
            RecordingInputValidation.failure(maxAmplitude: 0, isInputMuted: false),
            .unavailable
        )
        XCTAssertFalse(RecordingInputValidation.Failure.unavailable.message.localizedCaseInsensitiveContains("no speech"))
    }

    func testMutedSilentInputHasAnActionableMuteError() {
        XCTAssertEqual(
            RecordingInputValidation.failure(maxAmplitude: 0, isInputMuted: true),
            .muted
        )
    }

    func testQuietNonzeroInputIsNotReportedAsDisconnected() {
        for peak: Float in [0.000_001, 0.004_999] {
            XCTAssertEqual(
                RecordingInputValidation.failure(maxAmplitude: peak, isInputMuted: false),
                .tooQuiet
            )
        }
    }

    func testUsableAudioIsKeptEvenIfMutedBeforeStopping() {
        for peak: Float in [0.005, 0.1, 1] {
            for isMuted in [false, true] {
                XCTAssertNil(RecordingInputValidation.failure(maxAmplitude: peak, isInputMuted: isMuted))
            }
        }
    }

    func testInvalidLevelsAreInputFailures() {
        for peak: Float in [.nan, .infinity, -1] {
            XCTAssertEqual(
                RecordingInputValidation.failure(maxAmplitude: peak, isInputMuted: false),
                .unavailable
            )
        }
    }
}
