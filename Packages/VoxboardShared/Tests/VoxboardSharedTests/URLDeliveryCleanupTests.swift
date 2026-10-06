import XCTest
@testable import VoxboardShared

final class URLDeliveryCleanupTests: XCTestCase {
    func testRelaunchExposesDeliveredPayloadLeftBeforeCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("URLCleanup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()
        let sender = TranscriptURLDeliverer(receiptsDirectoryURL: directory, logger: { _ in })
        let event = await sender.enqueueCapture(id: id, text: "Synthetic accepted content", date: Date(), settings: settings)
        XCTAssertEqual(event.result, .queued)
        let receipts = await sender.receipts()
        let pending = try XCTUnwrap(receipts.first)
        // The receipt/body pair at the server-success/local-cleanup crash boundary.
        let delivered = URLDeliveryReceipt(id: pending.id, urlString: pending.urlString, attempt: 1,
            outcome: .delivered, statusCode: 200, message: "Delivered", date: Date(),
            destinationFingerprint: pending.destinationFingerprint, payloadFingerprint: pending.payloadFingerprint)
        try JSONEncoder().encode(delivered).write(to: directory.appendingPathComponent("\(pending.id).json"), options: .atomic)
        let restarted = TranscriptURLDeliverer(receiptsDirectoryURL: directory, credentialsProvider: { _ in
            XCTFail("Delivered cleanup must not read credentials")
            return nil
        }, logger: { _ in })
        let outstanding = await restarted.outstandingReceipts()
        XCTAssertEqual(outstanding.map(\.id), [id.uuidString.lowercased()])
        XCTAssertEqual(outstanding.first?.outcome, .delivered)
        try await restarted.cleanupDeliveredPayload(id: id)
        try await restarted.cleanupDeliveredPayload(id: id)
        let afterCleanup = await restarted.outstandingReceipts()
        XCTAssertTrue(afterCleanup.isEmpty)
        let tombstones = await restarted.receipts()
        XCTAssertEqual(tombstones.first?.outcome, .delivered)
    }

    @MainActor
    func testCleanupFailureStaysVisibleAndRetryNeverPosts() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("URLCleanup-\(UUID())")
        defer {
            StubURLProtocol.reset()
            try? FileManager.default.removeItem(at: directory)
        }
        StubURLProtocol.configure(responses: [.init(statusCode: 200)], error: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let removal = CleanupRemovalFailures(remaining: 2)
        let sender = TranscriptURLDeliverer(session: URLSession(configuration: configuration),
            receiptsDirectoryURL: directory, credentialsProvider: { _ in nil }, logger: { _ in },
            removePayload: { try removal.remove($0) })
        let id = UUID()
        _ = await sender.enqueueCapture(id: id, text: "Synthetic cleanup failure", date: Date(), settings: settings)
        let sent = await sender.sendQueuedDelivery(id: id)
        XCTAssertEqual(sent.result, .delivered(statusCode: 200))
        let owner = URLDeliveryCoordinator(deliverer: sender, beginExecution: { _ in
            XCTFail("Local cleanup must not acquire an HTTP execution lease")
            return nil
        })
        await owner.refresh()
        XCTAssertEqual(owner.receipts.first?.outcome, .delivered)
        await owner.cleanup(id: id)
        XCTAssertNotNil(owner.lastError)
        XCTAssertEqual(owner.receipts.first?.outcome, .delivered)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id.uuidString.lowercased()).request.json").path))
        await owner.cleanup(id: id)
        XCTAssertNil(owner.lastError)
        XCTAssertTrue(owner.receipts.isEmpty)
        let receipts = await sender.receipts()
        XCTAssertEqual(receipts.first?.outcome, .delivered)
        let replay = await sender.retryPendingDelivery(id: id)
        XCTAssertEqual(replay.result, .delivered(statusCode: 200))
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    func testCleanupCannotRemoveAnUndeliveredPayload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("URLCleanup-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let sender = TranscriptURLDeliverer(receiptsDirectoryURL: directory, logger: { _ in })
        let id = UUID()
        _ = await sender.enqueueCapture(id: id, text: "Synthetic pending content", date: Date(), settings: settings)
        do {
            try await sender.cleanupDeliveredPayload(id: id)
            XCTFail("Undelivered content requires explicit Discard, not Clean Up")
        } catch {}
        let outstanding = await sender.outstandingReceipts()
        XCTAssertEqual(outstanding.first?.outcome, .pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id.uuidString.lowercased()).request.json").path))
    }

    private var settings: CapturePresetURLDeliverySettings {
        .init(enabled: true, urlString: "https://example.invalid/cleanup", maxAttempts: 1)
    }
}

private final class CleanupRemovalFailures: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    init(remaining: Int) { self.remaining = remaining }
    func remove(_ url: URL) throws {
        lock.lock()
        let shouldFail = remaining > 0
        if shouldFail { remaining -= 1 }
        lock.unlock()
        if shouldFail { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.removeItem(at: url)
    }
}
