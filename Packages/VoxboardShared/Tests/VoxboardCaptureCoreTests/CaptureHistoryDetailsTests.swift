import Foundation
import XCTest
@testable import VoxboardCaptureCore

final class CaptureHistoryDetailsTests: XCTestCase {
    private let requestID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
    private let destinationID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    func test_newDetailFieldsRoundTripAndStayContentFree() throws {
        let reason = CaptureDeliveryFailureReason(
            kind: .headingNotFound,
            headingTitle: "Today",
            headingLevel: 2,
            relativeNotePath: "Tasks.md"
        )
        let record = try CaptureHistoryRecord(
            requestID: requestID,
            createdAt: Date(timeIntervalSince1970: 10),
            deliveredAt: Date(timeIntervalSince1970: 20),
            source: .app,
            outcome: .failed,
            destinationID: destinationID,
            destinationName: "Tasks",
            relativeNotePath: nil,
            attachmentCount: 0,
            failureCategory: .fileWrite,
            placementHeading: "Today",
            routeLog: [
                CaptureRouteLogStep(kind: .capture, outcome: .succeeded, at: Date(timeIntervalSince1970: 10)),
                CaptureRouteLogStep(kind: .deliver, outcome: .failed, at: Date(timeIntervalSince1970: 20), detail: "Heading not found: ## Today"),
            ],
            failureReason: reason
        )

        let data = try JSONEncoder().encode(record)
        let decoded = try JSONDecoder().decode(CaptureHistoryRecord.self, from: data)
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(decoded.failureReason?.headingMarkdown, "## Today")
        XCTAssertEqual(decoded.routeLog?.map(\.kind), [.capture, .deliver])
        XCTAssertEqual(decoded.placementHeading, "Today")
    }

    func test_legacyRecordWithoutDetailFieldsDecodes() throws {
        let json = """
        {"schemaVersion":1,"requestID":"\(requestID.uuidString)","createdAt":10,"source":"app",
         "outcome":"delivered","destinationID":"\(destinationID.uuidString)","destinationName":"Inbox",
         "attachmentCount":0}
        """
        let record = try JSONDecoder().decode(CaptureHistoryRecord.self, from: Data(json.utf8))
        XCTAssertNil(record.routeLog)
        XCTAssertNil(record.failureReason)
        XCTAssertNil(record.placementHeading)
    }

    func test_unreadableDetailFieldsDoNotHideTheRecord() throws {
        let json = """
        {"schemaVersion":1,"requestID":"\(requestID.uuidString)","createdAt":10,"source":"app",
         "outcome":"delivered","destinationID":"\(destinationID.uuidString)","destinationName":"Inbox",
         "attachmentCount":0,"routeLog":"garbage","failureReason":42}
        """
        let record = try JSONDecoder().decode(CaptureHistoryRecord.self, from: Data(json.utf8))
        XCTAssertNil(record.routeLog)
        XCTAssertNil(record.failureReason)
    }

    func test_failureReasonRejectsAbsoluteNotePath() {
        XCTAssertThrowsError(try CaptureHistoryRecord(
            requestID: requestID,
            createdAt: Date(),
            deliveredAt: nil,
            source: .app,
            outcome: .failed,
            destinationID: destinationID,
            destinationName: "Tasks",
            relativeNotePath: nil,
            attachmentCount: 0,
            failureReason: CaptureDeliveryFailureReason(kind: .other, relativeNotePath: "/Users/a/Tasks.md")
        ))
    }

    func test_headingNotFoundIsClassifiedWithItsSelector() {
        let reason = CaptureDeliveryFailureReason.classify(
            MarkdownDocumentEditorError.headingNotFound(CaptureHeadingSelector(title: "Today", level: 2)),
            relativeNotePath: "Tasks.md"
        )
        XCTAssertEqual(reason.kind, .headingNotFound)
        XCTAssertEqual(reason.headingTitle, "Today")
        XCTAssertEqual(reason.relativeNotePath, "Tasks.md")
    }

    func test_withDeliveryDetailsBuildsRouteLog() throws {
        let request = CaptureRequest(
            id: requestID,
            createdAt: Date(timeIntervalSince1970: 5),
            source: .keyboard,
            destinationID: destinationID,
            payloads: [.text("hello")]
        )
        let record = try CaptureHistoryRecord(
            requestID: requestID,
            createdAt: request.createdAt,
            deliveredAt: Date(timeIntervalSince1970: 9),
            source: .keyboard,
            outcome: .delivered,
            destinationID: destinationID,
            destinationName: "Meetings",
            relativeNotePath: "Meetings/2026-11-01.md",
            attachmentCount: 0
        ).withDeliveryDetails(
            request: request,
            placement: .beneathHeading(
                CaptureHeadingSelector(title: "Notes", level: 2),
                missingHeadingBehavior: .create,
                headingPosition: .top
            )
        )
        XCTAssertEqual(record.placementHeading, "Notes")
        XCTAssertEqual(record.routeLog?.map(\.kind), [.capture, .process, .shape, .deliver])
        XCTAssertEqual(record.routeLog?.last?.outcome, .succeeded)
        XCTAssertEqual(record.routeLog?.last?.detail, "Meetings/2026-11-01.md")
        XCTAssertEqual(record.routeLog?.first?.at, request.createdAt)
        XCTAssertNil(record.failureReason)
    }

    func test_libraryContentPersistsBesideHistoryAndIsPrunedWithIt() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureHistoryDetailsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CaptureHistoryStore(
            fileURL: folder.appendingPathComponent("capture-history-v1.json"),
            coordinator: ProcessLocalCaptureFileCoordinator.shared
        )
        let otherID = UUID()
        for id in [requestID, otherID] {
            try await store.upsert(
                CaptureHistoryRecord(
                    requestID: id,
                    createdAt: Date(),
                    deliveredAt: Date(),
                    source: .app,
                    outcome: .delivered,
                    destinationID: destinationID,
                    destinationName: "Meetings",
                    relativeNotePath: "Meetings/a.md",
                    attachmentCount: 1
                ),
                content: CaptureLibraryContent(
                    requestID: id,
                    renderedMarkdown: "## Notes\n- [ ] Review",
                    text: "Review",
                    audioRelativePath: "Attachments/2026-11-01-1042.m4a"
                )
            )
        }

        let content = await store.content(requestID: requestID)
        XCTAssertEqual(content?.renderedMarkdown, "## Notes\n- [ ] Review")
        XCTAssertEqual(content?.audioFilename, "2026-11-01-1042.m4a")
        let allCount = await store.allContent().count
        XCTAssertEqual(allCount, 2)

        // History JSON itself never carries the content.
        let historyJSON = try String(contentsOf: store.fileURL, encoding: .utf8)
        XCTAssertFalse(historyJSON.contains("Review"))

        try await store.remove(requestIDs: [requestID])
        let removed = await store.content(requestID: requestID)
        let kept = await store.content(requestID: otherID)
        XCTAssertNil(removed)
        XCTAssertNotNil(kept)

        try await store.clear()
        let afterClear = await store.allContent()
        XCTAssertTrue(afterClear.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.contentFileURL.path))
    }

    func test_plainTextJoinsTextualPayloads() {
        let request = CaptureRequest(
            source: .app,
            destinationID: destinationID,
            payloads: [.text(" First "), .url(URL(string: "https://example.com")!, title: "Example")]
        )
        XCTAssertEqual(
            CaptureLibraryContent.plainText(of: request),
            "First\n\n[Example](https://example.com)"
        )
    }

    func test_reviseFailedRequestAppliesOverrideAndReturnsToPending() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureInboxRevise-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = CaptureInbox(rootDirectoryURL: root, coordinator: ProcessLocalCaptureFileCoordinator.shared)
        let request = CaptureRequest(
            id: requestID,
            source: .shareExtension,
            destinationID: destinationID,
            payloads: [.text("- [ ] Renew passport")]
        )
        try await inbox.enqueue(request)
        _ = try await inbox.claim(requestID: requestID)
        try await inbox.fail(requestID: requestID)
        let failedIDs = try await inbox.failedRequests().map(\.id)
        XCTAssertEqual(failedIDs, [requestID])

        let heading = CaptureHeadingSelector(title: "Today", level: 2)
        let revised = try await inbox.reviseFailedRequest(requestID: requestID) {
            $0.placementOverride = .beneathHeading(heading, missingHeadingBehavior: .create, headingPosition: .top)
        }
        XCTAssertTrue(revised)
        let state = try await inbox.state(of: requestID)
        XCTAssertEqual(state, .pending)
        let pending = try await inbox.request(requestID: requestID, states: [.pending])
        XCTAssertEqual(
            pending?.placementOverride,
            .beneathHeading(heading, missingHeadingBehavior: .create, headingPosition: .top)
        )
        let revisedAgain = try await inbox.reviseFailedRequest(requestID: requestID) { _ in }
        XCTAssertFalse(revisedAgain)
    }
}
