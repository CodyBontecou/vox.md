import XCTest
@testable import VoxboardShared

#if os(iOS) || os(macOS)
final class VoiceAutoStopContinuousModeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearVoiceAutoStopPreferenceKeys()
    }

    override func tearDown() {
        clearVoiceAutoStopPreferenceKeys()
        super.tearDown()
    }

    // MARK: - Preference storage (default OFF preserves current behavior)

    func testContinuousModeDefaultsOffForEveryCapturePath() {
        for path in VoiceAutoStopCapturePath.allCases {
            XCTAssertFalse(
                AppConstants.voiceAutoStopContinuousModeEnabled(for: path),
                "\(path.rawValue) must default to end-of-speech stopping"
            )
        }
    }

    func testContinuousModePersistsIndependentlyPerPath() {
        AppConstants.setVoiceAutoStopContinuousModeEnabled(true, for: .inAppDraft)

        XCTAssertTrue(AppConstants.voiceAutoStopContinuousModeEnabled(for: .inAppDraft))
        XCTAssertFalse(AppConstants.voiceAutoStopContinuousModeEnabled(for: .keyboard))
        XCTAssertFalse(AppConstants.voiceAutoStopContinuousModeEnabled(for: .inAppImmediate))

        AppConstants.setVoiceAutoStopContinuousModeEnabled(false, for: .inAppDraft)
        XCTAssertFalse(AppConstants.voiceAutoStopContinuousModeEnabled(for: .inAppDraft))
    }

    // MARK: - End-of-speech action resolution

    func testEndOfSpeechActionDefaultsToEndRecording() {
        let command = makeCommand(origin: .inAppDraft)

        XCTAssertEqual(
            VoiceAutoStopPolicy.endOfSpeechAction(for: command),
            .endRecording
        )
    }

    func testEndOfSpeechActionCommitsAndContinuesWhenEnabled() {
        AppConstants.setVoiceAutoStopContinuousModeEnabled(true, for: .inAppDraft)
        let command = makeCommand(origin: .inAppDraft)

        XCTAssertEqual(
            VoiceAutoStopPolicy.endOfSpeechAction(for: command),
            .commitSegmentAndContinue
        )
    }

    func testEndOfSpeechActionIsNilWhenAutoStopIsDisabledForPath() {
        AppConstants.setVoiceAutoStopContinuousModeEnabled(true, for: .inAppImmediate)
        AppConstants.setVoiceAutoStopCapturePathEnabled(false, for: .inAppImmediate)
        let command = makeCommand(origin: .inAppImmediate)

        XCTAssertNil(VoiceAutoStopPolicy.endOfSpeechAction(for: command))
    }

    func testKeyboardPathAlwaysEndsRecording() {
        // Keyboard transcript delivery is scoped to its IPC request; there is
        // no app-owned session to continue, so the stored preference is inert.
        AppConstants.setVoiceAutoStopContinuousModeEnabled(true, for: .keyboard)
        let command = makeCommand(origin: .keyboardExtension)

        XCTAssertEqual(
            VoiceAutoStopPolicy.endOfSpeechAction(for: command),
            .endRecording
        )
    }

    func testStopCommandsResolveNoEndOfSpeechAction() {
        AppConstants.setVoiceAutoStopContinuousModeEnabled(true, for: .quickRecord)
        let stop = RecordingCommand(
            requestId: "stop",
            action: .stopSegment,
            modelId: TranscriptionBackendID.automatic,
            origin: .quickRecord
        )

        XCTAssertNil(VoiceAutoStopPolicy.endOfSpeechAction(for: stop))
    }

    // MARK: - Session guardrail

    func testContinuousSessionLimitIsTenMinutes() {
        // Documents the battery/thermal guardrail: continuous dictation keeps
        // the microphone live, so sessions are bounded at ten wall-clock
        // minutes before the recorder ends them through the standard stop
        // path. Ten minutes matches the circular buffer's rolling window
        // scale while covering a long dictation sitting.
        XCTAssertEqual(AppConstants.voiceAutoStopContinuousSessionLimit, 600)
    }

    // MARK: - Helpers

    private func makeCommand(origin: RecordingCommand.Origin) -> RecordingCommand {
        RecordingCommand(
            requestId: "request-\(origin.rawValue)",
            action: .startSegment,
            modelId: TranscriptionBackendID.automatic,
            origin: origin
        )
    }

    private func clearVoiceAutoStopPreferenceKeys() {
        for path in VoiceAutoStopCapturePath.allCases {
            AppConstants.sharedDefaults?.removeObject(
                forKey: AppConstants.voiceAutoStopCapturePathKey(for: path)
            )
            AppConstants.sharedDefaults?.removeObject(
                forKey: AppConstants.voiceAutoStopContinuousModeKey(for: path)
            )
        }
    }
}
#endif
