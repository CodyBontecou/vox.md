import XCTest
@testable import VoxboardShared

/// Synthetic transport and credentials; no real Keychain or external HTTP.
final class URLDeliveryAuthorizationRecoveryTests: XCTestCase {
    func testExplicitRetryCanRecoverAfter401AndCredentialCorrection() async throws {
        for status in [401, 403] {
            let directory = makeDirectory()
            defer { cleanup(directory) }
            let endpoint = "https://example.invalid/ingest"
            let account = UUID().uuidString
            let credentials = AuthorizationRecoveryCredentialBox(.init(urlString: endpoint, bearerToken: "synthetic-expired"))
            let sender = makeSender(directory: directory, credentialsProvider: { _ in credentials.value })
            let settings = authenticatedSettings(endpoint: endpoint, account: account)
            let id = UUID()
            StubURLProtocol.configure(responses: [.init(statusCode: status)], error: nil)
            let failed = await sender.deliverCapture(id: id, text: "Synthetic text", date: Date(), settings: settings)
            guard case .failed = failed.result else { return XCTFail("Expected initial auth failure") }
            let receipts = await sender.outstandingReceipts()
            XCTAssertEqual(receipts.first?.outcome, .needsAuthentication)
            credentials.value = .init(urlString: endpoint, bearerToken: "synthetic-corrected")
            StubURLProtocol.configure(responses: [.init(statusCode: 200)], error: nil)
            let retried = await sender.retryPendingDelivery(id: id)
            XCTAssertEqual(retried.result, .delivered(statusCode: 200), "Explicit retry after corrected auth should recover")
            XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1, "Manual retry should reach the endpoint once")
        }
    }

    func testExplicitAuthorizationRecoversAnonymous401WithoutChangingBodyOrIdentity() async throws {
        let directory = makeDirectory()
        defer { cleanup(directory) }
        let endpoint = "https://example.invalid/ingest"
        let account = UUID().uuidString
        let sender = makeSender(directory: directory, credentialsProvider: { id in
            id == account ? .init(urlString: endpoint, bearerToken: "synthetic-corrected") : nil
        })
        let id = UUID()
        StubURLProtocol.configure(responses: [.init(statusCode: 401)], error: nil)
        _ = await sender.deliverCapture(id: id, text: "Original synthetic text", date: Date(),
                                       settings: .init(enabled: true, urlString: endpoint, maxAttempts: 1))
        let original = try XCTUnwrap(StubURLProtocol.capturedRequests.first)
        StubURLProtocol.configure(responses: [.init(statusCode: 200)], error: nil)
        let recovered = await sender.retryPendingDelivery(id: id, authorization: authenticatedSettings(endpoint: endpoint, account: account))
        XCTAssertEqual(recovered.result, .delivered(statusCode: 200))
        let retry = try XCTUnwrap(StubURLProtocol.capturedRequests.first)
        XCTAssertEqual(retry.body, original.body)
        XCTAssertEqual(retry.url, original.url)
        XCTAssertEqual(retry.headers["Idempotency-Key"], original.headers["Idempotency-Key"])
        XCTAssertEqual(retry.headers["Authorization"], "Bearer synthetic-corrected")
    }

    func testExplicitAuthorizationCannotRetargetPayloadAndLeavesJournalUnchanged() async throws {
        let directory = makeDirectory()
        defer { cleanup(directory) }
        let endpoint = "https://example.invalid/ingest"
        let sender = makeSender(directory: directory, credentialsProvider: { _ in nil })
        let id = UUID()
        _ = await sender.enqueueCapture(id: id, text: "Synthetic", date: Date(), settings: .init(enabled: true, urlString: endpoint))
        let preparedURL = requestURL(id, in: directory)
        let before = try Data(contentsOf: preparedURL)
        StubURLProtocol.configure(responses: [.init(statusCode: 200)], error: nil)
        let rejected = await sender.retryPendingDelivery(id: id, authorization:
            authenticatedSettings(endpoint: "https://example.invalid/other-path", account: UUID().uuidString))
        guard case .failed = rejected.result else { return XCTFail("Frozen endpoints cannot change") }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        XCTAssertEqual(try Data(contentsOf: preparedURL), before)
        let receipts = await sender.outstandingReceipts()
        XCTAssertFalse(try XCTUnwrap(receipts.first).matchesDestination(.init(enabled: true, urlString: "https://example.invalid/other-path")))
        XCTAssertTrue(try XCTUnwrap(receipts.first).matchesDestination(.init(enabled: true, urlString: endpoint)))
    }

    func testUnavailableReplacementCredentialsFailClosedAndLeaveJournalUnchanged() async throws {
        let directory = makeDirectory()
        defer { cleanup(directory) }
        let endpoint = "https://example.invalid/ingest"
        let sender = makeSender(directory: directory, credentialsProvider: { _ in nil })
        let id = UUID()
        _ = await sender.enqueueCapture(id: id, text: "Synthetic", date: Date(), settings: .init(enabled: true, urlString: endpoint))
        let preparedURL = requestURL(id, in: directory)
        let before = try Data(contentsOf: preparedURL)
        let rejected = await sender.retryPendingDelivery(id: id, authorization: authenticatedSettings(endpoint: endpoint, account: UUID().uuidString))
        guard case .failed = rejected.result else { return XCTFail("Missing credentials must not downgrade to anonymous") }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        XCTAssertEqual(try Data(contentsOf: preparedURL), before)
    }

    func testLocalSinkRetryDoesNotResetOrReplayFailedHTTP() async throws {
        let directory = makeDirectory()
        defer { cleanup(directory) }
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: "https://example.invalid/ingest", maxAttempts: 1)
        let sender = makeSender(directory: directory, credentialsProvider: { _ in nil })
        let id = UUID()
        StubURLProtocol.configure(responses: [.init(statusCode: 503), .init(statusCode: 200)], error: nil)
        _ = await sender.deliverCapture(id: id, text: "Original", date: Date(), settings: settings)
        let before = try Data(contentsOf: requestURL(id, in: directory))
        let retained = await sender.enqueueCapture(id: id, text: "Changed by another sink", date: Date(), settings: settings)
        XCTAssertEqual(retained.result, .retained)
        XCTAssertEqual(try Data(contentsOf: requestURL(id, in: directory)), before)
        let receipts = await sender.outstandingReceipts()
        XCTAssertEqual(receipts.first?.outcome, .retryable)
        XCTAssertEqual(receipts.first?.attempt, 1)
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    private func authenticatedSettings(endpoint: String, account: String) -> CapturePresetURLDeliverySettings {
        .init(enabled: true, urlString: endpoint, hasBearerToken: true, maxAttempts: 1,
              credentialID: account, credentialURLString: endpoint)
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("URLAuthRecovery-\(UUID().uuidString)")
    }

    private func cleanup(_ directory: URL) {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: directory)
    }

    private func requestURL(_ id: UUID, in directory: URL) -> URL {
        directory.appendingPathComponent("\(id.uuidString.lowercased()).request.json")
    }

    private func makeSender(directory: URL, credentialsProvider: @escaping TranscriptURLDeliverer.CredentialsProvider) -> TranscriptURLDeliverer {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TranscriptURLDeliverer(session: URLSession(configuration: configuration), receiptsDirectoryURL: directory,
                                      credentialsProvider: credentialsProvider, logger: { _ in }, sleeper: { _ in })
    }
}

private final class AuthorizationRecoveryCredentialBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: URLDeliveryKeychain.Credentials
    init(_ credentials: URLDeliveryKeychain.Credentials) { storage = credentials }
    var value: URLDeliveryKeychain.Credentials {
        get { lock.lock(); defer { lock.unlock() }; return storage }
        set { lock.lock(); defer { lock.unlock() }; storage = newValue }
    }
}
