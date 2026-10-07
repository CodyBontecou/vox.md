import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CaptureURLDeliveryIntegrationTests: XCTestCase {
    func testDraftEditingDoesNotPrepareOrPOST() async throws {
        let fixture = try await makeFixture()
        _ = await fixture.model.appendRecognizedText("Synthetic draft only")
        await fixture.owner.refresh()
        XCTAssertTrue(fixture.owner.receipts.isEmpty)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.vault.appendingPathComponent("Inbox.md").path))
    }

    func testSendCompletesLocalNoteWhileHTTPBackoffRemainsOwned() async throws {
        let sleeping = expectation(description: "HTTP is waiting in backoff")
        let submitted = expectation(description: "Composer completed without waiting for HTTP")
        let fixture = try await makeFixture(sleeper: { _ in
            sleeping.fulfill()
            try await Task.sleep(for: .seconds(30))
        })
        fixture.model.draft.text = "Synthetic local note"
        let requestID = fixture.model.draft.requestID
        let submission = Task { await fixture.model.submit(); submitted.fulfill() }
        await fulfillment(of: [submitted, sleeping], timeout: 5)
        submission.cancel()
        await fixture.owner.cancelAll()
        await submission.value
        XCTAssertFalse(fixture.model.isSubmitting)
        XCTAssertNil(fixture.model.errorMessage)
        let receipt = try XCTUnwrap(fixture.model.lastReceipt)
        XCTAssertTrue(try String(contentsOf: receipt.noteURL, encoding: .utf8).contains("Synthetic local note"))
        XCTAssertEqual(fixture.model.draft.text, "")
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 1)
        XCTAssertEqual(fixture.owner.receipts.first?.id, requestID.uuidString.lowercased())
    }

    func testPreparationFailurePreservesDraftBeforeNoteMutation() async throws {
        let fixture = try await makeFixture(brokenJournal: true)
        fixture.model.draft.text = "Synthetic preserved draft"
        let draftID = fixture.model.draft.id
        await fixture.model.submit()
        XCTAssertNil(fixture.model.lastReceipt)
        XCTAssertNotNil(fixture.model.errorMessage)
        XCTAssertEqual(fixture.model.draft.id, draftID)
        XCTAssertEqual(fixture.model.draft.text, "Synthetic preserved draft")
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.vault.appendingPathComponent("Inbox.md").path))
        let saved = try await CaptureDraftStore(rootDirectoryURL: fixture.root).load(id: draftID)
        XCTAssertEqual(saved?.text, "Synthetic preserved draft")
    }

    func testProcessedTextAndDestinationSnapshotAreFrozenDuringSend() async throws {
        let entered = expectation(description: "Processor entered")
        let processor = PausedComposerTextProcessor(onEnter: { entered.fulfill() })
        let fixture = try await makeFixture(processor: processor, refuseLease: true)
        fixture.model.draft.text = "Raw synthetic draft"
        let requestID = fixture.model.draft.requestID
        let submission = Task { await fixture.model.submit() }
        await fulfillment(of: [entered], timeout: 5)
        var changed = fixture.preset
        changed.exportSettings.urlDelivery.urlString = "https://example.invalid/changed"
        CapturePresetStore.saveFlows([changed], defaults: fixture.defaults, widgetRefresh: .disabled)
        await processor.release()
        await submission.value
        await fixture.owner.cancelAll()
        XCTAssertNil(fixture.model.errorMessage)
        let receipt = try XCTUnwrap(fixture.model.lastReceipt)
        XCTAssertTrue(try String(contentsOf: receipt.noteURL, encoding: .utf8).contains("Processed synthetic text"))
        let prepared = try preparedObject(id: requestID, directory: fixture.journal)
        XCTAssertEqual(prepared["url"] as? String, "https://example.invalid/ingest")
        let encodedBody = try XCTUnwrap(prepared["body"] as? String)
        let body = try XCTUnwrap(Data(base64Encoded: encodedBody))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(payload["text"] as? String, "Processed synthetic text")
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
    }

    func testCancelDuringProcessingDoesNotPrepareOrSendHTTP() async throws {
        let entered = expectation(description: "Processor entered")
        let processor = PausedComposerTextProcessor(onEnter: { entered.fulfill() })
        let fixture = try await makeFixture(processor: processor)
        fixture.model.draft.text = "Synthetic canceled draft"
        let submission = Task { await fixture.model.submit() }
        await fulfillment(of: [entered], timeout: 5)
        submission.cancel()
        await processor.release()
        await submission.value
        await fixture.owner.refresh()
        XCTAssertEqual(fixture.model.draft.text, "Synthetic canceled draft")
        XCTAssertNil(fixture.model.lastReceipt)
        XCTAssertTrue(fixture.owner.receipts.isEmpty)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.vault.appendingPathComponent("Inbox.md").path))
    }

    func testHTTPOnlyRetryAfterNoteSuccessDoesNotRepeatLocalDelivery() async throws {
        let fixture = try await makeFixture(maxAttempts: 1, responseStatuses: [503, 200])
        fixture.model.draft.text = "Synthetic partial delivery"
        let id = fixture.model.draft.requestID
        await fixture.model.submit()
        // Wait for the dispatched attempt to finish without requesting a retry.
        for _ in 0..<500 {
            if fixture.owner.activeIDs.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(fixture.owner.activeIDs.isEmpty)
        let noteURL = try XCTUnwrap(fixture.model.lastReceipt?.noteURL)
        let original = try Data(contentsOf: noteURL)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 1)
        XCTAssertEqual(fixture.owner.receipts.first?.outcome, .retryable)
        await fixture.owner.retry(id: id)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 2)
        XCTAssertTrue(fixture.owner.receipts.isEmpty)
        XCTAssertEqual(try Data(contentsOf: noteURL), original)
        XCTAssertEqual(fixture.model.draft.text, "")
    }

    func testNativeKeychainRoundTripAndDeletionForSyntheticAccount() throws {
        let id = UUID().uuidString
        defer { try? URLDeliveryKeychain.deleteCredentials(forID: id) }
        let credentials = URLDeliveryKeychain.Credentials(urlString: "https://example.invalid/synthetic",
            bearerToken: "synthetic-test-token", customHeaders: ["X-Test": "synthetic-test-header"])
        try URLDeliveryKeychain.saveCredentials(credentials, forID: id)
        XCTAssertEqual(try URLDeliveryKeychain.credentials(forID: id), credentials)
        let replacement = URLDeliveryKeychain.Credentials(urlString: credentials.urlString, bearerToken: "synthetic-replacement")
        try URLDeliveryKeychain.saveCredentials(replacement, forID: id)
        XCTAssertEqual(try URLDeliveryKeychain.credentials(forID: id), replacement)
        try URLDeliveryKeychain.deleteCredentials(forID: id)
        XCTAssertNil(try URLDeliveryKeychain.credentials(forID: id))
    }

    private struct Fixture {
        let model: QuickCaptureViewModel
        let owner: URLDeliveryCoordinator
        let root: URL
        let vault: URL
        let journal: URL
        let preset: CapturePreset
        let defaults: UserDefaults
    }

    private func makeFixture(
        processor: (any CapturePresetTextProcessing)? = nil, brokenJournal: Bool = false,
        refuseLease: Bool = false, maxAttempts: Int = 2, responseStatuses: [Int] = [503], sleeper: @escaping TranscriptURLDeliverer.Sleeper = { _ in }
    ) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ComposerURL-\(UUID().uuidString)")
        let vault = root.appendingPathComponent("vault")
        let journal = root.appendingPathComponent("http-journal")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        if brokenJournal { try Data("Not a directory".utf8).write(to: journal) }
        let destination = CaptureDestination(name: "Synthetic", rootBookmark: try vault.bookmarkData(), rootName: "Synthetic Vault",
                                             noteTarget: .existingNote(relativePath: "Inbox.md"), retryProtectionEnabled: true)
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let suite = "ComposerURL-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        var preset = CapturePresetStore.makeCustomFlow()
        preset.name = "Synthetic HTTP"
        preset.captureDestinationID = destination.id
        preset.postProcessingMode = processor == nil ? .none : .clean
        preset.captureProcessingEnabled = true
        preset.exportSettings.urlDelivery = .init(enabled: true, urlString: "https://example.invalid/ingest", maxAttempts: maxAttempts)
        CapturePresetStore.saveFlows([preset], defaults: defaults, widgetRefresh: .disabled)
        ComposerHTTPProtocol.reset(statuses: responseStatuses)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComposerHTTPProtocol.self]
        let sender = TranscriptURLDeliverer(session: URLSession(configuration: configuration), receiptsDirectoryURL: journal,
                                            credentialsProvider: { _ in nil }, logger: { _ in }, sleeper: sleeper)
        let owner = URLDeliveryCoordinator(deliverer: sender, beginExecution: { _ in refuseLease ? nil : .init() })
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline(),
            requestProcessor: CapturePresetRequestProcessor(textProcessor: processor), urlDeliveryCoordinator: owner)
        addTeardownBlock {
            await owner.cancelAll()
            defaults.removePersistentDomain(forName: suite)
            ComposerHTTPProtocol.reset()
            try? FileManager.default.removeItem(at: root)
        }
        await model.load()
        model.draft.voxID = preset.id
        return Fixture(model: model, owner: owner, root: root, vault: vault, journal: journal, preset: preset, defaults: defaults)
    }

    private func preparedObject(id: UUID, directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("\(id.uuidString.lowercased()).request.json"))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

private actor PausedComposerTextProcessor: CapturePresetTextProcessing {
    let onEnter: @Sendable () -> Void
    private var continuation: CheckedContinuation<Void, Never>?
    init(onEnter: @escaping @Sendable () -> Void) { self.onEnter = onEnter }
    func process(text: String, profile: CapturePresetProfile) async throws -> CapturePresetTextProcessingResult {
        await withCheckedContinuation { continuation in self.continuation = continuation; onEnter() }
        try Task.checkCancellation()
        return .init(text: "Processed synthetic text")
    }
    func release() { continuation?.resume(); continuation = nil }
}

nonisolated private final class ComposerHTTPProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var statuses = [503]
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset(statuses: [Int] = [503]) { lock.lock(); defer { lock.unlock() }; count = 0; self.statuses = statuses }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let status = Self.statuses[min(Self.count, Self.statuses.count - 1)]
        Self.count += 1
        Self.lock.unlock()
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
