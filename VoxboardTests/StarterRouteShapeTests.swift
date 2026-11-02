import XCTest
import VoxboardShared
@testable import Voxboard

/// Starter route SHAPE against the Routes / RouteEditor boards.
final class StarterRouteShapeTests: XCTestCase {
    func testMeetingNotesWritesATimestampedEntry() {
        XCTAssertEqual(StarterRoute.meetingNotes.entryPrefix, "### {hour}:{minute} · {title}\n")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let request = CaptureRequest(
            createdAt: Date(timeIntervalSince1970: 1_704_192_120),
            source: .app,
            destinationID: UUID(),
            payloads: [.text("# Project sync\n- [ ] Review final designs")]
        )
        let prefix = CaptureEntryTemplateRenderer(calendar: calendar)
            .render(StarterRoute.meetingNotes.entryPrefix, for: request)
        XCTAssertEqual(prefix, "### 10:42 · Project sync\n")
    }

    func testOtherStarterRoutesWriteThePlainCapture() {
        for route in [StarterRoute.inbox, .tasks, .journal] {
            XCTAssertEqual(route.entryPrefix, "", "\(route)")
        }
    }

    func testInstallOrderMatchesTheRoutesBoard() {
        XCTAssertEqual(StarterRoute.installOrder, [.meetingNotes, .inbox, .journal, .tasks])
    }
}
