import Foundation
import XCTest
@testable import VoxboardCaptureCore

final class CaptureRouteTodaySnapshotTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func test_firstLineStripsMarkdownMarkersAndCapsLength() {
        XCTAssertEqual(CaptureRouteTodaySnapshot.firstLine(of: "\n- [ ] Book flights for Lisbon\nsecond"), "Book flights for Lisbon")
        XCTAssertEqual(CaptureRouteTodaySnapshot.firstLine(of: "### Design sync\n- notes"), "Design sync")
        // Same rules as the `{title}` token.
        XCTAssertEqual(CaptureRouteTodaySnapshot.firstLine(of: "1. Ship it"), "Ship it")
        XCTAssertEqual(
            CaptureRouteTodaySnapshot.firstLine(of: "1. Ship it"),
            CaptureEntryTemplateRenderer.displayTitle("1. Ship it")
        )
        XCTAssertNil(CaptureRouteTodaySnapshot.firstLine(of: "  \n\n"))
        let long = String(repeating: "a", count: 200)
        let capped = CaptureRouteTodaySnapshot.firstLine(of: long)
        XCTAssertEqual(capped?.count, CaptureRouteTodaySnapshot.maximumLineLength)
        XCTAssertEqual(capped?.last, "…")
    }

    func test_recordKeepsNewestItemsCountsRetriesOnceAndResetsDaily() {
        let morning = Date(timeIntervalSince1970: 1_793_520_000) // 2026-11-01 08:00 UTC
        var snapshot = CaptureRouteTodaySnapshot(day: "2026-10-31")
        let ids = (0..<5).map { _ in UUID() }
        for (index, id) in ids.enumerated() {
            snapshot.record(requestID: id, routeID: "tasks", text: "Item \(index)", at: morning, calendar: calendar)
        }
        snapshot.record(requestID: ids[4], routeID: "tasks", text: "Item 4 retried", at: morning, calendar: calendar)

        let route = snapshot.route("tasks", now: morning, calendar: calendar)
        XCTAssertEqual(snapshot.day, "2026-11-01")
        XCTAssertEqual(route?.count, 5)
        XCTAssertEqual(route?.items.map(\.firstLine), ["Item 4 retried", "Item 3", "Item 2"])

        let tomorrow = morning.addingTimeInterval(86_400)
        XCTAssertNil(snapshot.route("tasks", now: tomorrow, calendar: calendar))
        snapshot.record(requestID: UUID(), routeID: "journal", text: "New day", at: tomorrow, calendar: calendar)
        XCTAssertNil(snapshot.routes["tasks"])
        XCTAssertEqual(snapshot.route("journal", now: tomorrow, calendar: calendar)?.count, 1)
    }

    func test_routeCountIsCapped() {
        let now = Date()
        var snapshot = CaptureRouteTodaySnapshot(day: CaptureRouteTodaySnapshot.dayKey(for: now))
        for index in 0..<(CaptureRouteTodaySnapshot.maximumRoutes + 4) {
            snapshot.record(requestID: UUID(), routeID: "route-\(index)", text: "x", at: now.addingTimeInterval(Double(index)))
        }
        XCTAssertEqual(snapshot.routes.count, CaptureRouteTodaySnapshot.maximumRoutes)
        XCTAssertNotNil(snapshot.routes["route-\(CaptureRouteTodaySnapshot.maximumRoutes + 3)"])
        XCTAssertNil(snapshot.routes["route-0"])
    }

    func test_historyStoreWritesSnapshotOnDeliveryAndRemovesItOnClear() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureRouteTodaySnapshotTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let historyURL = folder.appendingPathComponent("capture-history-v1.json")
        let store = CaptureHistoryStore(fileURL: historyURL, coordinator: ProcessLocalCaptureFileCoordinator.shared)
        let requestID = UUID()
        let record = try CaptureHistoryRecord(
            requestID: requestID,
            createdAt: Date(),
            deliveredAt: Date(),
            source: .app,
            outcome: .delivered,
            destinationID: UUID(),
            destinationName: "Tasks",
            voxID: "tasks",
            voxName: "Tasks",
            relativeNotePath: "Tasks.md",
            attachmentCount: 0
        )
        try await store.upsert(record, content: CaptureLibraryContent(requestID: requestID, text: "Book flights for Lisbon\nand hotels"))

        let snapshot = try XCTUnwrap(CaptureRouteTodaySnapshot.load(historyFileURL: historyURL))
        XCTAssertEqual(snapshot.route("tasks")?.items.map(\.firstLine), ["Book flights for Lisbon"])

        try await store.remove(requestIDs: [requestID])
        XCTAssertNil(CaptureRouteTodaySnapshot.load(historyFileURL: historyURL)?.route("tasks"))

        try await store.upsert(record, content: CaptureLibraryContent(requestID: requestID, text: "Again"))
        try await store.clear()
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.routeTodaySnapshotURL.path))
    }
}
