import XCTest
@testable import Voxboard

final class ReleaseNotesPresentationTests: XCTestCase {
    func testRecordingUpdateIsPresentedAfterUpgradingFromPreviousVersion() {
        XCTAssertTrue(VoxboardReleaseNotes.shouldPresentCurrentVersion(
            currentAppVersion: "2.10",
            latestSeenAppVersion: "2.9",
            releaseNotesEnabled: true
        ))
    }

    func testRecordingUpdateIsNotRepeatedAfterBeingSeen() {
        XCTAssertFalse(VoxboardReleaseNotes.shouldPresentCurrentVersion(
            currentAppVersion: "2.10",
            latestSeenAppVersion: "2.10",
            releaseNotesEnabled: true
        ))
    }

    func testUnseenCurrentVersionWithNotesIsPresented() {
        XCTAssertTrue(VoxboardReleaseNotes.shouldPresentCurrentVersion(
            currentAppVersion: "2.2",
            latestSeenAppVersion: nil,
            releaseNotesEnabled: true
        ))
    }

    func testSeenCurrentVersionIsNotPresented() {
        XCTAssertFalse(VoxboardReleaseNotes.shouldPresentCurrentVersion(
            currentAppVersion: "2.2",
            latestSeenAppVersion: "2.2",
            releaseNotesEnabled: true
        ))
    }

    func testVersionWithoutNotesIsNotPresented() {
        XCTAssertFalse(VoxboardReleaseNotes.shouldPresentCurrentVersion(
            currentAppVersion: "9.9.9",
            latestSeenAppVersion: nil,
            releaseNotesEnabled: true
        ))
    }

    func testDisabledReleaseNotesAreNotPresented() {
        XCTAssertFalse(VoxboardReleaseNotes.shouldPresentCurrentVersion(
            currentAppVersion: "2.2",
            latestSeenAppVersion: nil,
            releaseNotesEnabled: false
        ))
    }
}
