import XCTest
@testable import VoxboardShared

/// Synthetic inputs only; all HTTP is intercepted by the package's URLProtocol stub.
final class URLDeliveryHardeningTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("URLDeliveryHardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try FileManager.default.removeItem(at: directory)
    }

    func testCustomHeaderValuesAreNotStoredInPresetJSON() throws {
        let settings = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest",
            customHeaders: ["Authorization": "HMAC synthetic-secret", "X-API-Key": "synthetic-api-key"]
        )
        let data = try JSONEncoder().encode(settings)
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("synthetic-secret"))
        XCTAssertFalse(json.contains("synthetic-api-key"))
    }

    func testUnconfirmedLocalHTTPDoesNotSend() async {
        let deliverer = makeDeliverer()
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: "http://127.0.0.1:8080/ingest")
        let event = await deliverer.deliver(transcript: transcript(), settings: settings)
        assertFailed(event)
        XCTAssertEqual(event.attempts, 0)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testCancelledTransportDoesNotRetry() async {
        let deliverer = makeDeliverer(error: URLError(.cancelled))
        let event = await deliverer.deliver(transcript: transcript(), settings: settings())
        assertFailed(event)
        XCTAssertEqual(event.attempts, 1)
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    func testAutomaticAttemptsAreBoundedEvenForMalformedSettings() async {
        let deliverer = makeDeliverer(error: URLError(.timedOut))
        var settings = settings()
        settings.maxAttempts = 100
        let event = await deliverer.deliver(transcript: transcript(), settings: settings)
        assertFailed(event)
        XCTAssertLessThanOrEqual(event.attempts, 5)
        XCTAssertLessThanOrEqual(StubURLProtocol.capturedRequests.count, 5)
    }

    func testReceiptStorageFailurePreventsNetworkSideEffect() async throws {
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        try Data("synthetic".utf8).write(to: blockingFile)
        let deliverer = makeDeliverer(directory: blockingFile)
        let event = await deliverer.deliver(transcript: transcript(), settings: settings())
        assertFailed(event)
        XCTAssertEqual(event.attempts, 0)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testDeliveredIdentityIsNotPostedAgainAfterRecreatingDeliverer() async {
        let transcript = transcript()
        let first = makeDeliverer()
        let firstEvent = await first.deliver(transcript: transcript, settings: settings())
        XCTAssertEqual(firstEvent.result, .delivered(statusCode: 200))
        let restarted = makeDeliverer()
        let replay = await restarted.deliver(transcript: transcript, settings: settings())
        XCTAssertEqual(replay.result, .delivered(statusCode: 200))
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testTransportDiagnosticsAndReceiptsDoNotCopyArbitraryErrorDescriptions() async throws {
        let logs = LogRecorder()
        let error = NSError(domain: "SyntheticTransport", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Failure at https://example.invalid/private?secret=synthetic-secret"
        ])
        let deliverer = makeDeliverer(error: error, logs: logs)
        var settings = settings()
        settings.maxAttempts = 1
        let event = await deliverer.deliver(transcript: transcript(), settings: settings)
        assertFailed(event)
        XCTAssertFalse(logs.values.joined().contains("synthetic-secret"))
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("synthetic-secret"))
        }
    }

    func testDisabledSendTestDoesNotSend() async {
        let deliverer = makeDeliverer()
        var settings = settings()
        settings.enabled = false
        let event = await deliverer.sendTest(settings: settings)
        XCTAssertEqual(event.result, .disabled)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testOversizedCaptureDoesNotSend() async {
        let deliverer = makeDeliverer()
        let event = await deliverer.deliverCapture(
            id: UUID(), text: String(repeating: "x", count: URLDeliveryValidator.maxBodyBytes + 1),
            date: Date(timeIntervalSince1970: 1_700_000_000), settings: settings()
        )
        assertFailed(event)
        XCTAssertEqual(event.attempts, 0)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testInvalidLocalLiteralIsNotClassifiedAsLocal() {
        XCTAssertFalse(URLDeliveryValidator.isLocalHost("10.example.0.0.1"))
        XCTAssertFalse(URLDeliveryValidator.isLocalHost("10..0.0.1"))
        XCTAssertFalse(URLDeliveryValidator.isLocalHost("10.0.0.1."))
    }

    private func settings() -> CapturePresetURLDeliverySettings {
        CapturePresetURLDeliverySettings(enabled: true, urlString: "https://example.invalid/ingest")
    }

    private func transcript() -> Transcript {
        Transcript(id: UUID(), text: "Synthetic delivery", date: Date(timeIntervalSince1970: 1_700_000_000),
                   duration: 1, modelUsed: "synthetic", language: "en")
    }

    private func assertFailed(_ event: URLDeliveryEvent, file: StaticString = #filePath, line: UInt = #line) {
        guard case .failed = event.result else {
            return XCTFail("Expected a URL failure, got \(event.result)", file: file, line: line)
        }
    }

    private func makeDeliverer(
        directory: URL? = nil, error: Error? = nil, logs: LogRecorder = LogRecorder()
    ) -> TranscriptURLDeliverer {
        StubURLProtocol.configure(responses: [.init(statusCode: 200)], error: error)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TranscriptURLDeliverer(
            session: URLSession(configuration: configuration), receiptsDirectoryURL: directory ?? self.directory,
            tokenProvider: { _ in nil }, logger: { logs.append($0) }, sleeper: { _ in }
        )
    }
}
