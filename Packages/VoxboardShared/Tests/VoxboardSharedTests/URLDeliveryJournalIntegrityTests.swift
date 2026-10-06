import XCTest
@testable import VoxboardShared

final class URLDeliveryJournalIntegrityTests: XCTestCase {
    private var directory: URL!
    private let endpoint = "https://example.invalid/private/path?collection=synthetic"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("URLJournalIntegrity-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try FileManager.default.removeItem(at: directory)
    }

    func testComposerHandoffRejectsDiscardedIdentity() async throws {
        let sender = makeSender()
        let id = UUID()
        let date = Date(timeIntervalSince1970: 1)
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint, maxAttempts: 1)
        let queued = await sender.enqueueCapture(id: id, text: "Unsent draft", date: date, settings: settings, requireMatchingPayload: true)
        XCTAssertEqual(queued.result, .queued)
        try await sender.discardDelivery(id: id)

        let repeated = await sender.enqueueCapture(id: id, text: "Unsent draft", date: date, settings: settings, requireMatchingPayload: true)
        guard case .failed(let message, _) = repeated.result else {
            return XCTFail("A discarded handoff must not acknowledge the composer's draft: \(repeated.result)")
        }
        XCTAssertTrue(message.contains("discarded"))
        let receipts = await sender.receipts()
        XCTAssertEqual(receipts.first?.outcome, .discarded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestURL(id).path))
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testInterruptedEnqueueIsVisibleAndCanBeDiscardedWithoutSending() async throws {
        let sender = makeSender()
        let id = UUID()
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint, maxAttempts: 1)
        _ = await sender.enqueueCapture(id: id, text: "Interrupted handoff", date: Date(timeIntervalSince1970: 1), settings: settings)
        // Model termination between the prepared-body write and receipt write.
        try FileManager.default.removeItem(at: receiptURL(id))

        let restarted = makeSender()
        let outstanding = await restarted.outstandingReceipts()
        let recovered = try XCTUnwrap(outstanding.first)
        XCTAssertEqual(recovered.id, id.uuidString.lowercased())
        XCTAssertEqual(recovered.origin, "https://example.invalid")
        XCTAssertFalse(recovered.urlString.contains("private"))
        XCTAssertEqual(recovered.outcome, .unknownOutcome)
        XCTAssertTrue(FileManager.default.fileExists(atPath: requestURL(id).path))
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty, "Opening recovery must not send")

        let automatic = await restarted.sendQueuedDelivery(id: id)
        guard case .failed = automatic.result else { return XCTFail("An incomplete handoff requires explicit Retry") }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        try await restarted.discardDelivery(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestURL(id).path))
        let remaining = await restarted.outstandingReceipts()
        XCTAssertTrue(remaining.isEmpty)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testInterruptedEnqueueCanExplicitlyRetryItsOriginalBody() async throws {
        let sender = makeSender()
        let id = UUID()
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint, maxAttempts: 1)
        _ = await sender.enqueueCapture(id: id, text: "Original interrupted content", date: Date(timeIntervalSince1970: 1), settings: settings)
        try FileManager.default.removeItem(at: receiptURL(id))

        let restarted = makeSender()
        _ = await restarted.outstandingReceipts()
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        let retried = await restarted.retryPendingDelivery(id: id)
        XCTAssertEqual(retried.result, .delivered(statusCode: 200))
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
        let body = try XCTUnwrap(StubURLProtocol.capturedRequests.first?.body)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["text"] as? String, "Original interrupted content")
        XCTAssertEqual(payload["id"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(StubURLProtocol.header("Idempotency-Key", in: StubURLProtocol.capturedRequests.first), id.uuidString.lowercased())
    }

    func testCorruptInterruptedBodyIsDiscardableButCannotBeSent() async throws {
        let sender = makeSender()
        let id = UUID()
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint, maxAttempts: 1)
        _ = await sender.enqueueCapture(id: id, text: "Interrupted content", date: Date(), settings: settings)
        try FileManager.default.removeItem(at: receiptURL(id))
        try Data("Corrupt prepared body".utf8).write(to: requestURL(id), options: .atomic)

        let restarted = makeSender()
        let outstanding = await restarted.outstandingReceipts()
        XCTAssertEqual(outstanding.first?.id, id.uuidString.lowercased())
        XCTAssertNil(outstanding.first?.origin)
        let retried = await restarted.retryPendingDelivery(id: id)
        guard case .failed = retried.result else { return XCTFail("A corrupt body must fail closed") }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        try await restarted.discardDelivery(id: id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestURL(id).path))
        let remaining = await restarted.outstandingReceipts()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testCanceledExplicitRetryPreservesPreviousAttemptEvidence() async throws {
        let id = UUID()
        let endpoint = self.endpoint
        let credentials = URLDeliveryKeychain.Credentials(urlString: endpoint, bearerToken: "synthetic-token")
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint, hasBearerToken: true,
            maxAttempts: 1, credentialID: UUID().uuidString, credentialURLString: endpoint)
        let sender = makeSender(responses: [.init(statusCode: 503)], credentials: { _ in credentials })
        _ = await sender.enqueueCapture(id: id, text: "Previously attempted content", date: Date(timeIntervalSince1970: 1), settings: settings)
        _ = await sender.sendQueuedDelivery(id: id)
        let before = await sender.outstandingReceipts()
        let originalReceipt = try XCTUnwrap(before.first)
        XCTAssertEqual(originalReceipt.attempt, 1)
        XCTAssertEqual(originalReceipt.outcome, .retryable)

        let retrying = makeSender(credentials: { _ in
            // Cancel after send's entry check, while it prepares the request.
            withUnsafeCurrentTask { $0?.cancel() }
            return credentials
        })
        let retry = Task { await retrying.retryPendingDelivery(id: id) }
        let result = await retry.value
        guard case .failed = result.result else { return XCTFail("Canceled Retry must not succeed") }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        let after = await retrying.outstandingReceipts()
        XCTAssertEqual(after.first, originalReceipt, "A canceled Retry cannot relabel old work as never attempted")
        XCTAssertEqual(result.attempts, originalReceipt.attempt)

        let restarted = makeSender(credentials: { _ in credentials })
        let automatic = await restarted.sendQueuedDelivery(id: id)
        guard case .failed = automatic.result else { return XCTFail("Previously attempted work still requires explicit Retry") }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    private func requestURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).request.json")
    }

    private func receiptURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).json")
    }

    private func makeSender(
        responses: [StubURLProtocol.Response] = [.init(statusCode: 200)],
        credentials: @escaping TranscriptURLDeliverer.CredentialsProvider = { _ in nil }
    ) -> TranscriptURLDeliverer {
        StubURLProtocol.configure(responses: responses, error: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TranscriptURLDeliverer(session: URLSession(configuration: configuration), receiptsDirectoryURL: directory,
                                      credentialsProvider: credentials, logger: { _ in }, sleeper: { _ in })
    }
}
