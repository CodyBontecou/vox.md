import VoxboardShared
import XCTest
@testable import Voxboard

/// Hans, 2026-11-26: with the route rail on, the header stopped needing its
/// own route switcher, and the mic-plus "Record new note" button read as a
/// second Speak button. These cover the two decisions behind the fix.
@MainActor
final class CaptureRecordBarTests: XCTestCase {
    private let profiles = [
        CapturePresetProfile(id: "inbox", name: "Inbox", symbolName: "tray"),
        CapturePresetProfile(id: "work", name: "Work", symbolName: "briefcase"),
        CapturePresetProfile(id: "journal", name: "Journal", symbolName: "book"),
    ]

    func testRailReplacesHeaderPillsOnlyWhenItIsDrawn() {
        XCTAssertTrue(QuickCaptureView.routeRailReplacesHeaderPills(railShown: true, routeCount: 3))
        // The rail draws nothing for a single route, so the header keeps it.
        XCTAssertFalse(QuickCaptureView.routeRailReplacesHeaderPills(railShown: true, routeCount: 1))
        XCTAssertFalse(QuickCaptureView.routeRailReplacesHeaderPills(railShown: false, routeCount: 3))
    }

    func testHeaderKeepsOnlySelectedPillWithItsRouteTone() {
        let only = CaptureRoutePillsRow.visibleRoutes(profiles, selectedID: "work", showsOnlySelected: true)
        XCTAssertEqual(only.map(\.element.id), ["work"])
        // Same position as in the rail, so the tile keeps the rail's colour.
        XCTAssertEqual(only.map(\.offset), [1])

        let all = CaptureRoutePillsRow.visibleRoutes(profiles, selectedID: "work", showsOnlySelected: false)
        XCTAssertEqual(all.map(\.element.id), ["inbox", "work", "journal"])
    }

    func testSpeakOffersNewNoteOnlyFromAnOpenLiveNote() {
        // Live Notes with a note open: Speak's trailing icon records into a new note.
        XCTAssertTrue(QuickCaptureView.speakOffersNewNote(liveNotesEnabled: true, canRecordNewNote: true))
        // Live Notes on a blank note: Speak already records into a new note.
        XCTAssertFalse(QuickCaptureView.speakOffersNewNote(liveNotesEnabled: true, canRecordNewNote: false))
        // Without Live Notes there is no note to leave.
        XCTAssertFalse(QuickCaptureView.speakOffersNewNote(liveNotesEnabled: false, canRecordNewNote: true))
    }
}
