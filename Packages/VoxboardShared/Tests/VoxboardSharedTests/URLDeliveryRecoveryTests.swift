import Security
import XCTest
@testable import VoxboardShared

final class URLDeliveryRecoveryTests: XCTestCase {
    private var directory: URL!
    private let endpoint = "https://example.invalid/private/path?collection=synthetic"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("URLRecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        StubURLProtocol.reset()
        try FileManager.default.removeItem(at: directory)
    }

    func testExplicitHTTPRetryUsesOriginalBytesAndDoesNotAutomaticReplay() async throws {
        let id = UUID()
        let first = deliverer(responses: [.init(statusCode: 503)])
        var settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint, maxAttempts: 1)
        let failed = await first.deliverCapture(id: id, text: "Original synthetic capture", date: Date(timeIntervalSince1970: 1), settings: settings)
        guard case .failed(_, true) = failed.result else { return XCTFail("Expected retained failure") }
        let originalBody = try XCTUnwrap(StubURLProtocol.capturedRequests.first?.body)
        let retained = await first.pendingReceipts()
        let receipt = try XCTUnwrap(retained.first)
        XCTAssertEqual(receipt.urlString, "https://example.invalid")
        XCTAssertFalse(receipt.urlString.contains("private"))

        let restarted = deliverer(responses: [.init(statusCode: 200)])
        settings.includeCleanedText = false
        _ = await restarted.deliverCapture(id: id, text: "Changed draft must not escape", date: Date(timeIntervalSince1970: 2), settings: settings)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty, "A file-sink retry must not drain HTTP")
        let recovered = await restarted.retryPendingDelivery(id: id)
        XCTAssertEqual(recovered.result, .delivered(statusCode: 200))
        XCTAssertEqual(StubURLProtocol.capturedRequests.first?.body, originalBody)
        XCTAssertEqual(StubURLProtocol.header("Idempotency-Key", in: StubURLProtocol.capturedRequests.first), id.uuidString.lowercased())
        let pending = await restarted.pendingReceipts()
        XCTAssertTrue(pending.isEmpty)
    }

    func testSuccessfulIdentityCannotBeReroutedToANewEndpoint() async {
        let id = UUID()
        let sender = deliverer(responses: [.init(statusCode: 200), .init(statusCode: 200)])
        var settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint)
        _ = await sender.deliverCapture(id: id, text: "Synthetic", date: Date(), settings: settings)
        settings.urlString = "https://other.invalid/ingest"
        let rerouted = await sender.deliverCapture(id: id, text: "Synthetic", date: Date(), settings: settings)
        guard case .failed(_, false) = rerouted.result else { return XCTFail("Expected immutable destination failure") }
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    func testKeychainAccessFailureIsVisibleAndCannotSendAnonymously() async {
        let sender = deliverer(responses: [.init(statusCode: 200)], credentials: { _ in
            throw URLDeliveryKeychain.StorageError.unavailable(errSecInteractionNotAllowed)
        })
        let event = await sender.deliverCapture(id: UUID(), text: "Synthetic", date: Date(), settings: authenticatedSettings())
        guard case .failed(let message, false) = event.result else { return XCTFail("Expected credential failure") }
        XCTAssertTrue(message.contains("Keychain"))
        XCTAssertEqual(event.attempts, 0)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testCredentialRecordMustMatchExactEndpointNotJustHost() async {
        let sender = deliverer(responses: [.init(statusCode: 200)], credentials: { _ in
            URLDeliveryKeychain.Credentials(urlString: "https://example.invalid/different", bearerToken: "synthetic-token")
        })
        let event = await sender.deliverCapture(id: UUID(), text: "Synthetic", date: Date(), settings: authenticatedSettings())
        guard case .failed(_, false) = event.result else { return XCTFail("Expected destination-bound credential failure") }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    func testCustomAuthenticationUsesOpaqueKeychainAccountAndNeverPersistsValues() async throws {
        let settings = authenticatedSettings()
        let account = try XCTUnwrap(settings.credentialID)
        let endpoint = self.endpoint
        let sender = deliverer(responses: [.init(statusCode: 503)], credentials: { id in
            guard id == account else { throw URLDeliveryKeychain.StorageError.missingCredentials }
            return URLDeliveryKeychain.Credentials(urlString: endpoint, bearerToken: "synthetic-token",
                                                  customHeaders: ["X-API-Key": "synthetic-header-secret"])
        })
        _ = await sender.deliverCapture(id: UUID(), text: "Synthetic", date: Date(), settings: settings)
        XCTAssertEqual(StubURLProtocol.header("Authorization", in: StubURLProtocol.capturedRequests.first), "Bearer synthetic-token")
        XCTAssertEqual(StubURLProtocol.header("X-API-Key", in: StubURLProtocol.capturedRequests.first), "synthetic-header-secret")
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
            let text = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(text.contains("synthetic-token"))
            XCTAssertFalse(text.contains("synthetic-header-secret"))
        }
    }

    func testLegacyPlaintextHeaderArchiveRequiresReauthorizationWithoutRetainingSecret() throws {
        let data = Data(#"{"enabled":true,"urlString":"https://example.invalid/ingest","customHeaders":{"Authorization":"synthetic-secret"}}"#.utf8)
        let decoded = try JSONDecoder().decode(CapturePresetURLDeliverySettings.self, from: data)
        XCTAssertTrue(decoded.requiresCredentialMigration)
        XCTAssertTrue(decoded.hasCustomHeaders)
        XCTAssertTrue(decoded.customHeaders.isEmpty)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self).contains("synthetic-secret"))
    }

    func testLoadingLegacyPresetRedactsPersistedHeaderValues() throws {
        let suite = "URLDeliveryMigration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Normalize unrelated preset migrations first, so only the URL field
        // can cause this archive to be rewritten.
        let normalized = CapturePresetStore.loadFlows(defaults: defaults)
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(normalized)) as? [[String: Any]])
        var export = try XCTUnwrap(archive[0]["exportSettings"] as? [String: Any])
        export["urlDelivery"] = ["enabled": true, "urlString": endpoint,
                                 "customHeaders": ["Authorization": "synthetic-persisted-secret"]]
        archive[0]["exportSettings"] = export
        defaults.set(try JSONSerialization.data(withJSONObject: archive), forKey: CapturePresetStore.flowsKey)
        let loaded = CapturePresetStore.loadFlows(defaults: defaults)
        XCTAssertTrue(loaded[0].exportSettings.urlDelivery.requiresCredentialMigration)
        let rewritten = try XCTUnwrap(defaults.data(forKey: CapturePresetStore.flowsKey))
        XCTAssertFalse(String(decoding: rewritten, as: UTF8.self).contains("synthetic-persisted-secret"))
    }

    func testInvalidHeaderLinesAndCaseInsensitiveDuplicatesAreRejectedBeforeSending() async {
        for headers in [
            ["X-Synthetic": "secret\r\nAuthorization: injected"],
            ["Bad Name": "value"], ["Host": "other.invalid"],
            ["X-Request": "one", "x-request": "two"],
        ] {
            let sender = deliverer(responses: [.init(statusCode: 200)])
            let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint, customHeaders: headers)
            let event = await sender.deliverCapture(id: UUID(), text: "Synthetic", date: Date(), settings: settings)
            guard case .failed(_, false) = event.result else { return XCTFail("Invalid headers must fail") }
            XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        }
    }

    func testCancellationDuringBackoffStopsFurtherRequests() async {
        let sender = deliverer(responses: [.init(statusCode: 503), .init(statusCode: 200)], sleeper: { _ in throw CancellationError() })
        let event = await sender.deliverCapture(id: UUID(), text: "Synthetic", date: Date(), settings: .init(enabled: true, urlString: endpoint))
        guard case .failed = event.result else { return XCTFail("Canceled backoff must not succeed") }
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
        XCTAssertEqual(event.attempts, 1)
    }

    func testNonFiniteRetryAfterFallsBackToBoundedDelay() async {
        let delays = DelayRecorder()
        let sender = deliverer(responses: [.init(statusCode: 429, headers: ["Retry-After": "inf"]), .init(statusCode: 200)],
                               sleeper: { delays.append($0) })
        _ = await sender.deliverCapture(id: UUID(), text: "Synthetic", date: Date(), settings: .init(enabled: true, urlString: endpoint))
        XCTAssertEqual(delays.values.count, 1)
        XCTAssertTrue(delays.values.allSatisfy { $0.isFinite && $0 >= 1 && $0 <= 300 })
    }

    func testRemovingCredentialsDuringBackoffPreventsAnotherAuthenticatedPost() async {
        let endpoint = self.endpoint
        let credentials = URLDeliveryCredentialBox(.init(urlString: endpoint, bearerToken: "synthetic-token"))
        let sender = deliverer(responses: [.init(statusCode: 503), .init(statusCode: 200)],
                               credentials: { _ in credentials.value }, sleeper: { _ in credentials.remove() })
        var settings = authenticatedSettings()
        settings.hasCustomHeaders = false
        settings.maxAttempts = 2
        let result = await sender.deliverCapture(id: UUID(), text: "Synthetic", date: Date(), settings: settings)
        guard case .failed = result.result else { return XCTFail("Removed credentials must stop retries") }
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    func testDamagedDeliveredReceiptCannotSuppressADifferentIdentity() async throws {
        let id = UUID()
        let settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint)
        let sender = deliverer(responses: [.init(statusCode: 200)])
        _ = await sender.deliverCapture(id: id, text: "Synthetic", date: Date(), settings: settings)
        let receiptURL = directory.appendingPathComponent("\(id.uuidString.lowercased()).json")
        var receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any])
        receipt["id"] = UUID().uuidString.lowercased()
        try JSONSerialization.data(withJSONObject: receipt).write(to: receiptURL, options: .atomic)
        let restarted = deliverer(responses: [.init(statusCode: 200)])
        let result = await restarted.deliverCapture(id: id, text: "Synthetic", date: Date(), settings: settings)
        guard case .failed = result.result else { return XCTFail("A mismatched receipt must not claim delivered") }
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
    }

    private func authenticatedSettings() -> CapturePresetURLDeliverySettings {
        .init(enabled: true, urlString: endpoint, hasBearerToken: true, maxAttempts: 1,
              hasCustomHeaders: true, credentialID: UUID().uuidString, credentialURLString: endpoint)
    }

    private func deliverer(
        responses: [StubURLProtocol.Response],
        credentials: @escaping TranscriptURLDeliverer.CredentialsProvider = { _ in nil },
        sleeper: @escaping TranscriptURLDeliverer.Sleeper = { _ in }
    ) -> TranscriptURLDeliverer {
        StubURLProtocol.configure(responses: responses, error: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TranscriptURLDeliverer(session: URLSession(configuration: configuration), receiptsDirectoryURL: directory,
                                      credentialsProvider: credentials, logger: { _ in }, sleeper: sleeper)
    }
}

final class URLDeliveryKeychainTests: XCTestCase {
    func testMissingItemAndDeniedAccessHaveDifferentOutcomes() throws {
        let missing = store(loadStatus: errSecItemNotFound)
        XCTAssertNil(try missing.load(id: UUID().uuidString))
        let denied = store(loadStatus: errSecInteractionNotAllowed)
        XCTAssertThrowsError(try denied.load(id: UUID().uuidString)) {
            XCTAssertEqual($0 as? URLDeliveryKeychain.StorageError, .unavailable(errSecInteractionNotAllowed))
        }
    }

    func testFailedTokenSaveAndRemovalThrowInsteadOfReportingSuccess() {
        let denied = store(loadStatus: errSecItemNotFound, writeStatus: errSecAuthFailed)
        XCTAssertThrowsError(try denied.save(.init(urlString: "https://example.invalid", bearerToken: "synthetic"), id: UUID().uuidString))
        XCTAssertThrowsError(try denied.delete(id: UUID().uuidString))
    }

    func testCorruptStoredCredentialCannotDecodeAsAnonymous() {
        let corrupt = store(loadStatus: errSecSuccess, data: Data("not credentials".utf8))
        XCTAssertThrowsError(try corrupt.load(id: UUID().uuidString)) {
            XCTAssertEqual($0 as? URLDeliveryKeychain.StorageError, .invalidData)
        }
    }

    private func store(loadStatus: OSStatus, writeStatus: OSStatus = errSecSuccess, data: Data? = nil) -> URLDeliveryKeychain.Store {
        .init(client: .init(load: { _ in (loadStatus, data) }, update: { _, _ in writeStatus },
                           add: { _, _ in writeStatus }, delete: { _ in writeStatus }))
    }
}
