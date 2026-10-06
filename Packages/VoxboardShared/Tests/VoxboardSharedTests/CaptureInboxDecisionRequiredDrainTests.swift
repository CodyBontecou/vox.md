import XCTest
@testable import VoxboardShared

/// Location-decision semantics of the shared drain: a capture whose Preset
/// requires a location decision must stay pending with its processed payload
/// preserved — never failed — and be reported in `decisionsRequired`.
final class CaptureInboxDecisionRequiredDrainTests: XCTestCase {
    func test_drainKeepsLocationDecisionRequestPendingWithoutFailing() async throws {
        let captureRoot = try temporaryFolder("decision-capture")
        let destinationRoot = try temporaryFolder("decision-destination")
        defer {
            try? FileManager.default.removeItem(at: captureRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }
        let destination = CaptureDestination(
            name: "Inbox",
            rootBookmark: try destinationRoot.bookmarkData(),
            rootName: "Vault",
            noteTarget: .existingNote(relativePath: "Inbox.md")
        )
        try await CaptureLibraryStore(
            fileURL: captureRoot.appendingPathComponent(CaptureLibraryStore.defaultFilename),
            coordinator: ProcessLocalCaptureFileCoordinator.shared
        ).save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let profile = CapturePresetProfile(
            id: "location-preset",
            name: "Location Preset",
            symbolName: "mappin",
            locationPolicy: CapturePresetLocationPolicy(isEnabled: true, unavailableBehavior: .ask)
        )
        // Enabled location policy with no resolved outcome → the pipeline
        // throws locationDecisionRequired before any delivery work.
        let request = CaptureRequest(
            source: .voice,
            destinationID: destination.id,
            payloads: [.text("decision pending")],
            voxProfile: profile
        )
        let inbox = CaptureInbox(
            rootDirectoryURL: captureRoot,
            coordinator: ProcessLocalCaptureFileCoordinator.shared
        )
        try await inbox.enqueue(request)

        let result = await CaptureInboxDeliveryService.drain(
            captureRootURL: captureRoot,
            defaults: nil,
            pipeline: CapturePipeline(
                writer: CoordinatedCaptureWriter(coordinator: ProcessLocalCaptureFileCoordinator.shared)
            ),
            coordinator: ProcessLocalCaptureFileCoordinator.shared
        )

        XCTAssertEqual(result.decisionsRequired.map(\.requestID), [request.id])
        XCTAssertEqual(result.decisionsRequired.first?.presetID, "location-preset")
        XCTAssertEqual(result.failedRequestIDs, [])
        XCTAssertEqual(result.receipts, [])
        let finalState = try await inbox.state(of: request.id)
        XCTAssertEqual(finalState, .pending)
        // A decision is not a delivery failure: no failed history record.
        let history = try await CaptureHistoryStore(
            fileURL: captureRoot.appendingPathComponent(AppConstants.captureHistoryFilename),
            coordinator: ProcessLocalCaptureFileCoordinator.shared
        ).list()
        XCTAssertEqual(history.count, 0)
        // The destination note was never touched.
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destinationRoot.appendingPathComponent("Inbox.md").path)
        )
    }

    func test_drainHonorsSendWithoutLocationPolicyWithMissingOutcome() async throws {
        let f = try await missingLocationFixture(behavior: .sendWithoutLocation)

        let result = await drain(captureRoot: f.captureRoot)

        XCTAssertNil(result.setupError)
        XCTAssertNil(result.latestFailureDescription)
        XCTAssertEqual(result.decisionsRequired, [])
        XCTAssertEqual(result.failedRequestIDs, [])
        XCTAssertEqual(result.receipts.map(\.requestID), [f.request.id])
        let state = try await f.inbox.state(of: f.request.id)
        XCTAssertEqual(state, .completed)
        let markdown = try String(contentsOf: f.destinationRoot.appendingPathComponent("Inbox.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("Saved capture without an origin location"))
        XCTAssertFalse(markdown.contains("locations:"))
    }

    func test_drainResumesMissingOutcomeAfterExplicitSendWithoutLocation() async throws {
        let f = try await missingLocationFixture(behavior: .ask)
        let before = await drain(captureRoot: f.captureRoot)
        XCTAssertEqual(before.decisionsRequired.map(\.requestID), [f.request.id])
        XCTAssertEqual(before.receipts, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.destinationRoot.appendingPathComponent("Inbox.md").path))

        let applied = try await f.inbox.sendWithoutLocation(requestID: f.request.id)
        XCTAssertTrue(applied)
        let saved = try await f.inbox.request(requestID: f.request.id, states: [.pending])
        let reviewed = try XCTUnwrap(saved)
        XCTAssertNil(reviewed.locationOutcome, "An explicit decision must not invent a location observation")
        XCTAssertEqual(reviewed.voxProfile, f.request.voxProfile)
        XCTAssertEqual(reviewed.payloads, f.request.payloads)
        XCTAssertEqual(reviewed.locationDecisionOverride, .sendWithoutLocation)

        let after = await drain(captureRoot: f.captureRoot)
        XCTAssertNil(after.setupError)
        XCTAssertNil(after.latestFailureDescription)
        XCTAssertEqual(after.decisionsRequired, [])
        XCTAssertEqual(after.failedRequestIDs, [])
        XCTAssertEqual(after.receipts.map(\.requestID), [f.request.id])
        let state = try await f.inbox.state(of: f.request.id)
        XCTAssertEqual(state, .completed)
        let note = f.destinationRoot.appendingPathComponent("Inbox.md")
        let delivered = try Data(contentsOf: note)
        XCTAssertFalse(String(decoding: delivered, as: UTF8.self).contains("locations:"))

        let repeated = await drain(captureRoot: f.captureRoot)
        XCTAssertEqual(repeated.receipts, [])
        XCTAssertEqual(repeated.decisionsRequired, [])
        XCTAssertEqual(try Data(contentsOf: note), delivered, "Recovery must not deliver the same capture twice")
    }

    private func missingLocationFixture(behavior: CaptureLocationUnavailableBehavior) async throws -> (
        captureRoot: URL, destinationRoot: URL, inbox: CaptureInbox, request: CaptureRequest
    ) {
        let captureRoot = try temporaryFolder("missing-capture")
        let destinationRoot = try temporaryFolder("missing-destination")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: captureRoot)
            try? FileManager.default.removeItem(at: destinationRoot)
        }
        let destination = CaptureDestination(
            name: "Synthetic Inbox",
            rootBookmark: try destinationRoot.bookmarkData(),
            rootName: "Vault",
            noteTarget: .existingNote(relativePath: "Inbox.md")
        )
        try await CaptureLibraryStore(
            fileURL: captureRoot.appendingPathComponent(CaptureLibraryStore.defaultFilename),
            coordinator: ProcessLocalCaptureFileCoordinator.shared
        ).save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let request = CaptureRequest(
            source: .voice,
            destinationID: destination.id,
            payloads: [.text("Saved capture without an origin location")],
            voxProfile: CapturePresetProfile(
                id: "location-preset", name: "Location Preset", symbolName: "mappin",
                locationPolicy: CapturePresetLocationPolicy(isEnabled: true, unavailableBehavior: behavior)
            )
        )
        let inbox = CaptureInbox(
            rootDirectoryURL: captureRoot,
            coordinator: ProcessLocalCaptureFileCoordinator.shared
        )
        try await inbox.enqueue(request)
        return (captureRoot, destinationRoot, inbox, request)
    }

    private func drain(captureRoot: URL) async -> CaptureInboxDeliveryResult {
        await CaptureInboxDeliveryService.drain(
            captureRootURL: captureRoot,
            defaults: nil,
            pipeline: CapturePipeline(
                writer: CoordinatedCaptureWriter(coordinator: ProcessLocalCaptureFileCoordinator.shared)
            ),
            coordinator: ProcessLocalCaptureFileCoordinator.shared
        )
    }

    private func temporaryFolder(_ name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CaptureInboxDecisionRequiredDrainTests-\(name)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
