import XCTest
import VoxboardShared
@testable import Voxboard

final class QuickCapturePresetRecordingDisplayTests: XCTestCase {
    func testQuickRecordUsesOriginNameAndIdentityEvenAfterPresetRenameOrDraftChange() throws {
        var origin = CapturePreset(id: "quick-record", name: "Origin Journal", symbolName: "book", emoji: "📓")
        let display = try XCTUnwrap(RecordingCompletionMode.runVox(flowID: origin.id)
            .originDisplay(presetSnapshot: origin))
        origin.name = "Renamed later"
        let unrelatedDraftPreset = CapturePreset(id: "draft", name: "Draft Inbox", symbolName: "tray")
        XCTAssertEqual(display, .preset(id: "quick-record", name: "Origin Journal"))
        XCTAssertEqual(display.transcribingSubtitle, String(localized: "Running \("Origin Journal")"))
        XCTAssertNotEqual(display, RecordingCompletionMode.runVox(flowID: unrelatedDraftPreset.id)
            .originDisplay(presetSnapshot: unrelatedDraftPreset))
        XCTAssertNotEqual(display, RecordingCompletionMode.runVox(flowID: origin.id)
            .originDisplay(presetSnapshot: origin))
    }

    func testDraftAndKeyboardModesCannotInheritAStalePresetLabel() {
        let stale = CapturePreset(id: "old", name: "Previous run", symbolName: "waveform")
        for attachAudio in [false, true] {
            let display = RecordingCompletionMode.captureDraft(attachAudio: attachAudio)
                .originDisplay(presetSnapshot: stale)
            XCTAssertEqual(display, .draft)
            XCTAssertEqual(display?.transcribingSubtitle, String(localized: "Adding transcript to this Capture"))
        }
        XCTAssertNil(RecordingCompletionMode.keyboardTranscription.originDisplay(presetSnapshot: stale))
    }

    func testMissingSnapshotNamesNoCurrentOrRequestedPreset() throws {
        let display = try XCTUnwrap(RecordingCompletionMode.runVox(flowID: "not-a-display-name")
            .originDisplay(presetSnapshot: nil))
        XCTAssertEqual(display, .preset(id: nil, name: nil))
        XCTAssertEqual(display.transcribingSubtitle, String(localized: "Running Capture Preset"))
        XCTAssertEqual(QuickCapturePresetRecordingDisplay.preset(id: "id", name: " \n").transcribingSubtitle,
                       String(localized: "Running Capture Preset"))
    }

    func testQueuedDeliveryProjectsItsSnapshotRatherThanTheRequestedIDOrLastMode() throws {
        let delivered = CapturePreset(id: "actual", name: "Archived origin", symbolName: "archivebox")
        let mode = try XCTUnwrap(RecordingCompletionMode(jobDelivery: .preset(delivered)))
        XCTAssertEqual(mode.originDisplay(presetSnapshot: delivered),
                       .preset(id: "actual", name: "Archived origin"))
        // Even legacy delivery fallback is labeled from the snapshot actually
        // chosen by the recorder, not from an unavailable requested ID.
        XCTAssertEqual(RecordingCompletionMode.runVox(flowID: "retired")
            .originDisplay(presetSnapshot: delivered), mode.originDisplay(presetSnapshot: delivered))
    }
}
