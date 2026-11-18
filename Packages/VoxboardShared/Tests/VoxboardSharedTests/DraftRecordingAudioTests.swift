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
}
