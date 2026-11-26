import XCTest
@testable import VoxboardShared

final class DraftRecordingAudioTests: XCTestCase {
    func testDraftRecordingFollowsThePresetsSaveAudioSetting() {
        XCTAssertTrue(CapturePresetAudioSaveMode.alongsideTranscript.draftRecordingAttachesAudio(override: nil))
        XCTAssertTrue(CapturePresetAudioSaveMode.attachmentsFolder.draftRecordingAttachesAudio(override: nil))
        XCTAssertFalse(CapturePresetAudioSaveMode.off.draftRecordingAttachesAudio(override: nil))
    }

    func testAudioSwitchOverridesThePreset() {
        XCTAssertFalse(CapturePresetAudioSaveMode.alongsideTranscript.draftRecordingAttachesAudio(override: false))
        XCTAssertTrue(CapturePresetAudioSaveMode.off.draftRecordingAttachesAudio(override: true))
    }

    func testAudioOnlyRouteKeepsItsAudioUnlessSwitchedOff() {
        // A route with "Transcribe Recordings" off can only produce audio (#163).
        XCTAssertTrue(CapturePresetAudioSaveMode.off.draftRecordingAttachesAudio(presetTranscribes: false, override: nil))
        XCTAssertFalse(CapturePresetAudioSaveMode.off.draftRecordingAttachesAudio(presetTranscribes: true, override: nil))
        XCTAssertFalse(CapturePresetAudioSaveMode.off.draftRecordingAttachesAudio(presetTranscribes: false, override: false))
    }
}
