import XCTest
@testable import VoxboardShared

final class URLDeliveryHandoffTests: XCTestCase {
    private var directory: URL!
    private let endpoint = "https://example.invalid/ingest"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("URLHandoff-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    func testCaptureHandoffIsDurableBeforeAnyHTTPAndSurvivesRestart() async throws {
        let id = UUID()
        let sender = makeSender()
        let queued = await sender.enqueueCapture(id: id, text: "Original synthetic capture", date: Date(timeIntervalSince1970: 1), settings: settings())
        XCTAssertEqual(queued.result, .queued)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty, "Local completion must not wait for any HTTP side effect")
        let pending = await sender.pendingReceipts()
        XCTAssertEqual(pending.first?.outcome, .pending)
        XCTAssertEqual(pending.first?.attempt, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: requestURL(id).path))

        let restarted = makeSender()
        let sent = await restarted.sendQueuedDelivery(id: id)
        XCTAssertEqual(sent.result, .delivered(statusCode: 200))
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
        let body = try XCTUnwrap(StubURLProtocol.capturedRequests.first?.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["text"] as? String, "Original synthetic capture")
        XCTAssertFalse(FileManager.default.fileExists(atPath: requestURL(id).path))
    }

    func testTranscriptHandoffAlsoMakesNoRequest() async {
        let sender = makeSender()
        let transcript = Transcript(id: UUID(), text: "Synthetic voice", date: Date(), duration: 1, modelUsed: "synthetic", language: "en")
        let queued = await sender.enqueueTranscript(transcript, settings: settings())
        XCTAssertEqual(queued.result, .queued)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testRepeatedHandoffKeepsFrozenBody() async throws {
        let sender = makeSender()
        let id = UUID()
        _ = await sender.enqueueCapture(id: id, text: "Original", date: Date(timeIntervalSince1970: 1), settings: settings())
        _ = await sender.enqueueCapture(id: id, text: "Changed", date: Date(timeIntervalSince1970: 2), settings: settings())
        _ = await sender.sendQueuedDelivery(id: id)
        let body = try XCTUnwrap(StubURLProtocol.capturedRequests.first?.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["text"] as? String, "Original")
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    func testQueuedDispatcherCannotAutomaticallyReplayAnAttemptedFailure() async {
        let sender = makeSender(responses: [.init(statusCode: 503), .init(statusCode: 200)])
        let id = UUID()
        _ = await sender.enqueueCapture(id: id, text: "Synthetic", date: Date(), settings: settings())
        _ = await sender.sendQueuedDelivery(id: id)
        let replay = await sender.sendQueuedDelivery(id: id)
        guard case .failed = replay.result else { return XCTFail("Attempted failures require explicit Retry") }
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    func testUnavailableCredentialsDoNotLosePreparedCapture() async {
        let sender = makeSender()
        let id = UUID()
        var configured = settings()
        configured.hasBearerToken = true
        configured.credentialID = UUID().uuidString
        configured.credentialURLString = endpoint
        let queued = await sender.enqueueCapture(id: id, text: "Synthetic", date: Date(), settings: configured)
        XCTAssertEqual(queued.result, .queued)
        let sent = await sender.sendQueuedDelivery(id: id)
        guard case .failed = sent.result else { return XCTFail("Missing credentials must fail closed") }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: requestURL(id).path))
    }

    func testAnotherActorCanRetainHandoffWithoutWaitingForActiveHTTPBackoff() async {
        let sleeping = expectation(description: "Sender in HTTP backoff")
        StubURLProtocol.configure(responses: [.init(statusCode: 503), .init(statusCode: 200)], error: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let sender = TranscriptURLDeliverer(session: URLSession(configuration: configuration), receiptsDirectoryURL: directory,
            credentialsProvider: { _ in nil }, logger: { _ in }, sleeper: { _ in
                sleeping.fulfill()
                try await Task.sleep(for: .seconds(30))
            })
        let id = UUID()
        var configured = settings()
        configured.maxAttempts = 2
        _ = await sender.enqueueCapture(id: id, text: "Original", date: Date(), settings: configured)
        let sending = Task { await sender.sendQueuedDelivery(id: id) }
        await fulfillment(of: [sleeping], timeout: 2)
        // No HTTP occurs through this separate, read-only handoff facade.
        let restarted = TranscriptURLDeliverer(receiptsDirectoryURL: directory, logger: { _ in })
        let retained = await restarted.enqueueCapture(id: id, text: "Local sink retry", date: Date(), settings: configured)
        XCTAssertEqual(retained.result, .retained, "A network lock must not block an already-durable local-sink retry")
        var wrongEndpoint = configured
        wrongEndpoint.urlString = "https://other.example.invalid/ingest"
        let rejected = await restarted.enqueueCapture(id: id, text: "Synthetic", date: Date(), settings: wrongEndpoint)
        guard case .failed = rejected.result else { sending.cancel(); _ = await sending.value; return XCTFail("Destination cannot change") }
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
        sending.cancel()
        _ = await sending.value
        XCTAssertTrue(FileManager.default.fileExists(atPath: requestURL(id).path))
    }

    private func settings() -> CapturePresetURLDeliverySettings {
        .init(enabled: true, urlString: endpoint, maxAttempts: 1)
    }

    private func requestURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).request.json")
    }

    private func makeSender(responses: [StubURLProtocol.Response] = [.init(statusCode: 200)]) -> TranscriptURLDeliverer {
        StubURLProtocol.configure(responses: responses, error: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TranscriptURLDeliverer(session: URLSession(configuration: configuration), receiptsDirectoryURL: directory,
                                      credentialsProvider: { _ in nil }, logger: { _ in }, sleeper: { _ in })
    }
}
