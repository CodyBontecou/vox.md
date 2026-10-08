import XCTest
@testable import VoxboardShared

@MainActor
final class URLDeliveryCoordinatorTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("URLCoordinator-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
    }

    func testRefreshAfterRelaunchDoesNotSendPendingWork() async {
        let sender = makeSender()
        _ = await enqueue(sender)
        let owner = URLDeliveryCoordinator(deliverer: sender)
        await owner.refresh()
        XCTAssertEqual(owner.receipts.count, 1)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testUnavailableExecutionLeaseRetainsUnattemptedDelivery() async {
        let sender = makeSender()
        let id = await enqueue(sender)
        let began = expectation(description: "Lease requested")
        let owner = URLDeliveryCoordinator(deliverer: sender, beginExecution: { _ in began.fulfill(); return nil })
        owner.dispatch(id: id)
        await fulfillment(of: [began], timeout: 2)
        await owner.cancelAll()
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        XCTAssertEqual(owner.receipts.first?.outcome, .pending)
        XCTAssertEqual(owner.receipts.first?.attempt, 0)
        XCTAssertNotNil(owner.lastError)
    }

    func testExpirationDuringLeaseAcquisitionPreventsHTTPAndEndsLeaseOnce() async {
        let sender = makeSender()
        let id = await enqueue(sender)
        let began = expectation(description: "Expired during begin")
        var ends = 0
        let owner = URLDeliveryCoordinator(deliverer: sender, beginExecution: { expired in
            expired()
            began.fulfill()
            return .init { ends += 1 }
        })
        owner.dispatch(id: id)
        await fulfillment(of: [began], timeout: 2)
        await owner.cancelAll()
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        XCTAssertEqual(ends, 1)
        XCTAssertEqual(owner.receipts.first?.attempt, 0)
    }

    func testLeaseExpirationCancelsBackoffWithoutAnotherPOST() async {
        let sleeping = expectation(description: "First POST reached backoff")
        let canceled = expectation(description: "Expiration canceled sleeper")
        let sender = makeSender(responses: [.init(statusCode: 503), .init(statusCode: 200)], sleeper: { _ in
            sleeping.fulfill()
            do { try await Task.sleep(for: .seconds(30)) }
            catch { canceled.fulfill(); throw error }
        })
        let id = await enqueue(sender, maxAttempts: 2)
        var expiration: (@MainActor @Sendable () -> Void)?
        var ends = 0
        let owner = URLDeliveryCoordinator(deliverer: sender, beginExecution: {
            expiration = $0
            return .init { ends += 1 }
        })
        owner.dispatch(id: id)
        owner.dispatch(id: id)
        await fulfillment(of: [sleeping], timeout: 2)
        expiration?()
        await fulfillment(of: [canceled], timeout: 2)
        await owner.cancelAll()
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
        XCTAssertEqual(ends, 1)
        XCTAssertTrue(owner.activeIDs.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id.uuidString.lowercased()).request.json").path))
    }

    func testDiscardRemovesPayloadAndCannotBeReenqueuedByNoteRetry() async {
        let sender = makeSender()
        let id = await enqueue(sender)
        let owner = URLDeliveryCoordinator(deliverer: sender)
        await owner.discard(id: id)
        XCTAssertTrue(owner.receipts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("\(id.uuidString.lowercased()).request.json").path))
        let replay = await sender.enqueueCapture(id: id, text: "Changed synthetic text", date: Date(), settings: settings())
        XCTAssertEqual(replay.result, .retained, "A note retry must not resurrect a discarded HTTP identity")
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    private func enqueue(_ sender: TranscriptURLDeliverer, maxAttempts: Int = 1) async -> UUID {
        let id = UUID()
        var configured = settings()
        configured.maxAttempts = maxAttempts
        let event = await sender.enqueueCapture(id: id, text: "Synthetic", date: Date(), settings: configured)
        XCTAssertEqual(event.result, .queued)
        return id
    }

    private func settings() -> CapturePresetURLDeliverySettings {
        .init(enabled: true, urlString: "https://example.invalid/ingest", maxAttempts: 1)
    }

    private func makeSender(
        responses: [StubURLProtocol.Response] = [.init(statusCode: 200)],
        sleeper: @escaping TranscriptURLDeliverer.Sleeper = { _ in }
    ) -> TranscriptURLDeliverer {
        StubURLProtocol.configure(responses: responses, error: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TranscriptURLDeliverer(session: URLSession(configuration: configuration), receiptsDirectoryURL: directory,
                                      credentialsProvider: { _ in nil }, logger: { _ in }, sleeper: sleeper)
    }
}
