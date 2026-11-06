import XCTest
@testable import VoxboardShared

final class CaptureInboxVaultHoldTests: XCTestCase {
    func test_holdQueuesUnreachableCaptureWithAttachmentsAndDrainsAfterRegrant() async throws {
        let captureRoot = try temporaryFolder("capture")
        let destinationRoot = try temporaryFolder("destination")
        let draftStaging = try temporaryFolder("draft-staging")
        defer {
            for url in [captureRoot, destinationRoot, draftStaging] {
                try? FileManager.default.removeItem(at: url)
            }
        }
        let coordinator = ProcessLocalCaptureFileCoordinator.shared
        let destination = CaptureDestination(
            name: "Meeting Notes",
            rootBookmark: try destinationRoot.bookmarkData(),
            rootName: "Vault",
            noteTarget: .existingNote(relativePath: "Meetings.md")
        )
        try await CaptureLibraryStore(
            fileURL: captureRoot.appendingPathComponent(CaptureLibraryStore.defaultFilename),
            coordinator: coordinator
        ).save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))

        // A composer draft with a staged attachment, relative to its staging folder.
        try FileManager.default.createDirectory(
            at: draftStaging.appendingPathComponent("files"),
            withIntermediateDirectories: true
        )
        try Data("whiteboard".utf8).write(to: draftStaging.appendingPathComponent("files/board.txt"))
        let asset = try CaptureAssetReference(
            relativePath: "files/board.txt",
            originalFilename: "board.txt",
            contentTypeIdentifier: "public.plain-text"
        )
        let request = CaptureRequest(
            source: .app,
            destinationID: destination.id,
            payloads: [.text("Held while the vault was away"), .file(asset)]
        )

        let heldID = try await CaptureInboxVaultHold.hold(
            request,
            stagedAssetRootURL: draftStaging,
            destinationName: destination.name,
            captureRootURL: captureRoot,
            defaults: nil,
            coordinator: coordinator
        )

        // Queued (failed, waiting for access) with the vaultUnreachable reason.
        let inbox = CaptureInbox(rootDirectoryURL: captureRoot, coordinator: coordinator)
        XCTAssertEqual(heldID, request.id)
        let heldState = try await inbox.state(of: request.id)
        XCTAssertEqual(heldState, .failed)
        let history = CaptureHistoryStore(
            fileURL: captureRoot.appendingPathComponent(AppConstants.captureHistoryFilename),
            coordinator: coordinator
        )
        let failedRecord = try await history.list().first
        XCTAssertEqual(failedRecord?.outcome, .failed)
        XCTAssertEqual(failedRecord?.failureReason?.kind, .vaultUnreachable)

        // The attachment survives the draft's staging folder being removed.
        try FileManager.default.removeItem(at: draftStaging)
        let heldRequest = try await inbox.request(requestID: request.id, states: [.failed])
        guard case .file(let heldAsset)? = heldRequest?.payloads.last else {
            return XCTFail("Missing held attachment")
        }
        XCTAssertTrue(heldAsset.relativePath.hasPrefix("inbox-staging/\(request.id.uuidString.lowercased())/"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: captureRoot.appendingPathComponent(heldAsset.relativePath).path
        ))

        // Re-grant: failed captures return to the queue and the drain delivers them.
        _ = try await inbox.retryAllFailed()
        let result = await CaptureInboxDeliveryService.drain(
            captureRootURL: captureRoot,
            defaults: nil,
            pipeline: CapturePipeline(writer: CoordinatedCaptureWriter(coordinator: coordinator)),
            coordinator: coordinator
        )
        XCTAssertEqual(result.receipts.map(\.requestID), [request.id])
        XCTAssertEqual(result.receipts.first?.attachmentURLs.count, 1)
        let deliveredState = try await inbox.state(of: request.id)
        XCTAssertEqual(deliveredState, .completed)
        let markdown = try String(
            contentsOf: destinationRoot.appendingPathComponent("Meetings.md"),
            encoding: .utf8
        )
        XCTAssertTrue(markdown.contains("Held while the vault was away"))
        let deliveredRecord = try await history.list().first { $0.requestID == request.id }
        XCTAssertEqual(deliveredRecord?.outcome, .delivered)
    }

    private func temporaryFolder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureInboxVaultHoldTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
