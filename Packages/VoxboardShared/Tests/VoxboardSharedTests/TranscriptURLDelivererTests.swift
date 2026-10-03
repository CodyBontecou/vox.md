import XCTest
@testable import VoxboardShared

final class TranscriptURLDelivererTests: XCTestCase {

    private var receiptsDirectory: URL!

    override func setUp() {
        super.setUp()
        receiptsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("URLDeliveryTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: receiptsDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: receiptsDirectory)
        StubURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Cases

    func test_disabledSettings_makesNoRequest() async {
        let deliverer = makeDeliverer(responses: [.init(statusCode: 200)])
        let settings = CapturePresetURLDeliverySettings(enabled: false, urlString: "https://example.invalid/ingest")

        let event = await deliverer.deliver(transcript: makeTranscript(), settings: settings)

        XCTAssertEqual(event.result, .disabled)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func test_success_recordsDeliveredReceiptAndStableIdempotencyKey() async {
        let transcript = makeTranscript(text: "Hello delivery")
        let deliverer = makeDeliverer(responses: [.init(statusCode: 201)])
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: "https://example.invalid/ingest")

        let event = await deliverer.deliver(transcript: transcript, settings: settings)

        XCTAssertEqual(event.result, .delivered(statusCode: 201))
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
        XCTAssertEqual(
            StubURLProtocol.capturedRequests.first?.headers["Idempotency-Key"],
            transcript.id.uuidString.lowercased()
        )
        let receipts = await deliverer.pendingReceipts()
        XCTAssertEqual(receipts.first?.outcome, .delivered)
        XCTAssertEqual(receipts.first?.id, transcript.id.uuidString.lowercased())
    }

    func test_permanent4xx_doesNotRetry() async {
        let deliverer = makeDeliverer(responses: [.init(statusCode: 403)])
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: "https://example.invalid/ingest")

        let event = await deliverer.deliver(transcript: makeTranscript(), settings: settings)

        guard case .failed(_, let retryable) = event.result else {
            return XCTFail("expected failure, got \(event.result)")
        }
        XCTAssertFalse(retryable)
        XCTAssertEqual(event.attempts, 1)
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    func test_retryAfter429_isHonouredThenSucceeds() async {
        let delays = DelayRecorder()
        let deliverer = makeDeliverer(
            responses: [
                .init(statusCode: 429, headers: ["Retry-After": "2"]),
                .init(statusCode: 200),
            ],
            delays: delays
        )
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: "https://example.invalid/ingest")

        let event = await deliverer.deliver(transcript: makeTranscript(), settings: settings)

        XCTAssertEqual(event.result, .delivered(statusCode: 200))
        XCTAssertEqual(event.attempts, 2)
        XCTAssertEqual(delays.values, [2])
    }

    func test_serverErrorsThenSuccess_retriesWithBackoff() async {
        let delays = DelayRecorder()
        let deliverer = makeDeliverer(
            responses: [
                .init(statusCode: 500),
                .init(statusCode: 503),
                .init(statusCode: 200),
            ],
            delays: delays
        )
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: "https://example.invalid/ingest")

        let event = await deliverer.deliver(transcript: makeTranscript(), settings: settings)

        XCTAssertEqual(event.result, .delivered(statusCode: 200))
        XCTAssertEqual(event.attempts, 3)
        XCTAssertEqual(delays.values.count, 2)
        XCTAssertTrue(delays.values.allSatisfy { $0 >= 1 })
    }

    func test_offlineEveryAttempt_endsRetryableWithReceiptRetained() async {
        let deliverer = makeDeliverer(error: URLError(.notConnectedToInternet))
        let settings = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest",
            maxAttempts: 3
        )

        let event = await deliverer.deliver(transcript: makeTranscript(), settings: settings)

        guard case .failed(_, let retryable) = event.result else {
            return XCTFail("expected failure, got \(event.result)")
        }
        XCTAssertTrue(retryable)
        XCTAssertEqual(event.attempts, 3)
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 3)
        let receipts = await deliverer.pendingReceipts()
        XCTAssertEqual(receipts.first?.outcome, .retryable)
    }

    func test_bearerToken_presentOnlyWhenConfigured() async {
        let withToken = makeDeliverer(responses: [.init(statusCode: 200)], token: "s3cret-token")
        let settings = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest",
            hasBearerToken: true
        )
        _ = await withToken.deliver(transcript: makeTranscript(), settings: settings)
        XCTAssertEqual(
            StubURLProtocol.capturedRequests.first?.headers["Authorization"],
            "Bearer s3cret-token"
        )

        StubURLProtocol.reset()
        let withoutToken = makeDeliverer(responses: [.init(statusCode: 200)], token: nil)
        _ = await withoutToken.deliver(transcript: makeTranscript(), settings: settings)
        XCTAssertNil(StubURLProtocol.capturedRequests.first?.headers["Authorization"])
    }

    func test_customHeaders_areAppliedButProtocolHeadersAndBearerWin() async {
        let deliverer = makeDeliverer(responses: [.init(statusCode: 200)], token: "tok")
        let transcript = makeTranscript()
        var settings = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest",
            hasBearerToken: true
        )
        settings.customHeaders = [
            "X-Signature": "abc123",
            "Content-Type": "text/plain",
            "Idempotency-Key": "spoofed",
            "Authorization": "Bearer spoofed",
        ]

        _ = await deliverer.deliver(transcript: transcript, settings: settings)

        let request = StubURLProtocol.capturedRequests.first
        XCTAssertEqual(StubURLProtocol.header("X-Signature", in: request), "abc123")
        XCTAssertEqual(StubURLProtocol.header("Content-Type", in: request), "application/json; charset=utf-8")
        XCTAssertEqual(StubURLProtocol.header("Idempotency-Key", in: request), transcript.id.uuidString.lowercased())
        XCTAssertEqual(StubURLProtocol.header("Authorization", in: request), "Bearer tok")
    }

    func test_customAuthorization_isUsedWhenNoBearerTokenConfigured() async {
        let deliverer = makeDeliverer(responses: [.init(statusCode: 200)], token: nil)
        var settings = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest",
            hasBearerToken: false
        )
        settings.customHeaders = ["Authorization": "HMAC abc"]

        _ = await deliverer.deliver(transcript: makeTranscript(), settings: settings)

        XCTAssertEqual(
            StubURLProtocol.header("Authorization", in: StubURLProtocol.capturedRequests.first),
            "HMAC abc"
        )
    }

    func test_customHeaderSecrets_areNeverLogged() async {
        let logs = LogRecorder()
        let deliverer = makeDeliverer(
            responses: [.init(statusCode: 500), .init(statusCode: 200)],
            logs: logs
        )
        var settings = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest"
        )
        settings.customHeaders = ["X-Signature": "top-secret-signature"]

        _ = await deliverer.deliver(transcript: makeTranscript(), settings: settings)

        XCTAssertFalse(logs.values.joined(separator: "\n").contains("top-secret-signature"))
    }

    func test_diagnostics_neverContainTokenOrTranscriptBody() async {
        let logs = LogRecorder()
        let token = "super-secret-token"
        let transcript = makeTranscript(text: "Sensitive spoken words")
        let deliverer = makeDeliverer(
            responses: [.init(statusCode: 500), .init(statusCode: 200)],
            token: token,
            logs: logs
        )
        let settings = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest",
            hasBearerToken: true
        )

        _ = await deliverer.deliver(transcript: transcript, settings: settings)

        let joined = logs.values.joined(separator: "\n")
        XCTAssertFalse(joined.contains(token))
        XCTAssertFalse(joined.contains("Sensitive spoken words"))
        XCTAssertFalse(joined.contains("\"text\""))
    }

    func test_body_matchesJSONFileExportAndDropsCleanedTextWhenDisabled() async throws {
        let transcript = makeTranscript(text: "Raw text", cleanedText: "Cleaned text")
        let deliverer = makeDeliverer(responses: [.init(statusCode: 200), .init(statusCode: 200)])

        let withCleaned = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest",
            includeCleanedText: true
        )
        _ = await deliverer.deliver(transcript: transcript, settings: withCleaned)
        let delivered = try XCTUnwrap(StubURLProtocol.capturedRequests.first?.body)
        let decoded = try JSONDecoder().decode(Transcript.self, from: delivered)
        XCTAssertEqual(decoded.id, transcript.id)
        XCTAssertEqual(decoded.text, "Raw text")
        XCTAssertEqual(decoded.cleanedText, "Cleaned text")
        XCTAssertEqual(decoded.modelUsed, transcript.modelUsed)
        XCTAssertEqual(decoded.language, transcript.language)
        XCTAssertEqual(decoded.duration, transcript.duration, accuracy: 0.0001)

        let withoutCleaned = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest",
            includeCleanedText: false
        )
        _ = await deliverer.deliver(transcript: transcript, settings: withoutCleaned)
        let raw = try XCTUnwrap(StubURLProtocol.capturedRequests.last?.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        XCTAssertNil(object["cleanedText"])
        XCTAssertEqual(object["text"] as? String, "Raw text")
    }

    func test_sendTest_postsFixedSyntheticPayload() async throws {
        let deliverer = makeDeliverer(responses: [.init(statusCode: 200)])
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: "https://example.invalid/ingest")

        let event = await deliverer.sendTest(settings: settings)

        XCTAssertEqual(event.result, .delivered(statusCode: 200))
        let body = try XCTUnwrap(StubURLProtocol.capturedRequests.first?.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, "voxboard-test")
        XCTAssertEqual(object["test"] as? Bool, true)
        XCTAssertEqual(StubURLProtocol.capturedRequests.first?.headers["Idempotency-Key"], "voxboard-test")
    }

    func test_deliverCapture_postsGenericBodyWithUniqueId() async throws {
        let deliverer = makeDeliverer(responses: [.init(statusCode: 200)])
        let id = UUID()
        let settings = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest"
        )

        let event = await deliverer.deliverCapture(
            id: id,
            text: "Typed note",
            date: Date(timeIntervalSince1970: 1_700_000_000),
            settings: settings
        )

        XCTAssertEqual(event.result, .delivered(statusCode: 200))
        let body = try XCTUnwrap(StubURLProtocol.capturedRequests.first?.body)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(object["id"] as? String, id.uuidString.lowercased())
        XCTAssertEqual(object["text"] as? String, "Typed note")
        XCTAssertEqual(object["source"] as? String, "vox")
        XCTAssertNotNil(object["recorded_at"] as? String)
        XCTAssertEqual(
            StubURLProtocol.header("Idempotency-Key", in: StubURLProtocol.capturedRequests.first),
            id.uuidString.lowercased()
        )
    }

    func test_captureRequest_urlDeliveryText_joinsTextBearingPayloads() {
        let request = CaptureRequest(
            source: .app,
            destinationID: UUID(),
            payloads: [
                .text("First"),
                .url(URL(string: "https://example.com/x")!, title: nil),
                .text("Second"),
            ]
        )
        XCTAssertEqual(request.urlDeliveryText, "First\n\nhttps://example.com/x\n\nSecond")

        let imageOnly = CaptureRequest(
            source: .app,
            destinationID: UUID(),
            payloads: [.text("   ")]
        )
        XCTAssertEqual(imageOnly.urlDeliveryText, "")
    }

    func test_settingsRoundTrip_andLegacyJSONDecodesDisabled() throws {
        var settings = CapturePresetExportSettings()
        settings.urlDelivery = CapturePresetURLDeliverySettings(
            enabled: true,
            urlString: "https://example.invalid/ingest",
            hasBearerToken: true,
            customHeaders: ["X-Signature": "abc"],
            maxAttempts: 7,
            includeCleanedText: false
        )
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(CapturePresetExportSettings.self, from: data)
        XCTAssertEqual(decoded.urlDelivery, settings.urlDelivery)

        // Simulate an archive written before the field existed.
        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacyObject.removeValue(forKey: "urlDelivery")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)
        let legacy = try JSONDecoder().decode(CapturePresetExportSettings.self, from: legacyData)
        XCTAssertFalse(legacy.urlDelivery.enabled)
        XCTAssertEqual(legacy.urlDelivery.urlString, "")
        XCTAssertEqual(legacy.urlDelivery.maxAttempts, 5)
        XCTAssertEqual(legacy.urlDelivery.customHeaders, [:])
    }

    // MARK: - Helpers

    private func makeTranscript(
        text: String = "Hello world",
        cleanedText: String? = nil
    ) -> Transcript {
        Transcript(
            id: UUID(),
            text: text,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 12.5,
            modelUsed: "base",
            language: "en",
            cleanedText: cleanedText
        )
    }

    private func makeDeliverer(
        responses: [StubURLProtocol.Response] = [],
        error: Error? = nil,
        token: String? = nil,
        delays: DelayRecorder = DelayRecorder(),
        logs: LogRecorder = LogRecorder()
    ) -> TranscriptURLDeliverer {
        StubURLProtocol.configure(responses: responses, error: error)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return TranscriptURLDeliverer(
            session: session,
            receiptsDirectoryURL: receiptsDirectory,
            tokenProvider: { _ in token },
            logger: { logs.append($0) },
            sleeper: { delays.append($0) }
        )
    }
}

// MARK: - Test doubles

final class DelayRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TimeInterval] = []

    var values: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ value: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }
}

final class LogRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var values: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    func append(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }
}

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response {
        let statusCode: Int
        var headers: [String: String] = [:]
        var body: Data = Data()
    }

    struct CapturedRequest {
        let url: URL?
        let headers: [String: String]
        let body: Data?
    }

    private static let lock = NSLock()
    private static var responses: [Response] = []
    private static var failure: Error?
    private static var requests: [CapturedRequest] = []

    static var capturedRequests: [CapturedRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    static func header(_ name: String, in request: CapturedRequest?) -> String? {
        request?.headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    static func configure(responses: [Response], error: Error?) {
        lock.lock(); defer { lock.unlock() }
        Self.responses = responses
        self.failure = error
        requests = []
    }

    static func reset() {
        configure(responses: [], error: nil)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let captured = CapturedRequest(
            url: request.url,
            headers: request.allHTTPHeaderFields ?? [:],
            body: Self.body(of: request)
        )
        Self.lock.lock()
        Self.requests.append(captured)
        let failure = Self.failure
        let response = Self.responses.isEmpty ? nil : Self.responses.removeFirst()
        Self.lock.unlock()

        if let failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        guard let response, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let http = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        if !response.body.isEmpty {
            client?.urlProtocol(self, didLoad: response.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
