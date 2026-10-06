import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CaptureURLDeliveryIntegrationTests: XCTestCase {
    func testHTTPOnlySendDoesNotRequireDirectory() async throws {
        let accounting = ComposerHTTPAccounting()
        let fixture = try await makeFixture(refuseLease: true, directoryConfigured: false, accounting: accounting)
        fixture.model.draft.text = "Synthetic HTTP-only capture"
        let requestID = fixture.model.draft.requestID
        XCTAssertNil(fixture.model.selectedDestination)
        XCTAssertTrue(fixture.model.canSubmit)
        await fixture.model.submit()
        XCTAssertNil(fixture.model.errorMessage)
        XCTAssertEqual(fixture.model.lastReceipt?.requestID, requestID)
        XCTAssertEqual(fixture.model.draft.text, "")
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.vault.path).isEmpty)
        await fixture.owner.refresh()
        XCTAssertEqual(fixture.owner.receipts.first?.outcome, .pending)
        let counts = await accounting.counts()
        XCTAssertEqual(counts.reserved, 1)
        XCTAssertEqual(counts.committed, 1)
        XCTAssertEqual(counts.released, 0)
    }

    func testHTTPCompletionDoesNotReadOrWriteDirectoryHistory() async throws {
        let fixture = try await makeFixture(refuseLease: true, directoryConfigured: false)
        fixture.model.draft.text = "Synthetic independent HTTP handoff"
        try Data("Corrupt directory library".utf8).write(
            to: fixture.root.appendingPathComponent(AppConstants.captureLibraryFilename)
        )
        await fixture.model.submit()
        XCTAssertNil(fixture.model.errorMessage)
        XCTAssertEqual(fixture.model.draft.text, "")
        XCTAssertNotNil(fixture.model.lastReceipt)
        XCTAssertTrue(fixture.model.historyRecords.isEmpty)
    }

    func testHTTPQuotaRefusalPreservesDraftWithoutHandoff() async throws {
        let accounting = ComposerHTTPAccounting(refusesQuota: true)
        let fixture = try await makeFixture(refuseLease: true, accounting: accounting)
        fixture.model.draft.text = "Synthetic quota-limited capture"
        let requestID = fixture.model.draft.requestID
        await fixture.model.submit()
        XCTAssertTrue(fixture.model.needsCaptureUnlock)
        XCTAssertEqual(fixture.model.draft.requestID, requestID)
        XCTAssertEqual(fixture.model.draft.text, "Synthetic quota-limited capture")
        XCTAssertNil(fixture.model.lastReceipt)
        await fixture.owner.refresh()
        XCTAssertTrue(fixture.owner.receipts.isEmpty)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
    }

    func testHTTPPreparationFailureReleasesAllowanceReservation() async throws {
        let accounting = ComposerHTTPAccounting()
        let fixture = try await makeFixture(brokenJournal: true, accounting: accounting)
        fixture.model.draft.text = "Synthetic recoverable handoff"
        await fixture.model.submit()
        let counts = await accounting.counts()
        XCTAssertEqual(counts.reserved, 1)
        XCTAssertEqual(counts.committed, 0)
        XCTAssertEqual(counts.released, 1)
        XCTAssertEqual(fixture.model.draft.text, "Synthetic recoverable handoff")
        XCTAssertTrue(fixture.model.historyRecords.isEmpty)
    }

    func testEditedDraftSurvivesFailureAfterHTTPHandoff() async throws {
        let accounting = ComposerHTTPAccounting(failsFirstCommit: true)
        let fixture = try await makeFixture(refuseLease: true, accounting: accounting)
        fixture.model.draft.text = "Original synthetic capture"
        let requestID = fixture.model.draft.requestID
        await fixture.model.submit()
        XCTAssertNotNil(fixture.model.errorMessage)
        XCTAssertEqual(fixture.model.draft.text, "Original synthetic capture")
        await fixture.owner.refresh()
        XCTAssertEqual(fixture.owner.receipts.first?.id, requestID.uuidString.lowercased())

        fixture.model.draft.text = "Edited synthetic capture"
        await fixture.model.saveDraftNow()
        await fixture.model.submit()
        XCTAssertEqual(fixture.model.draft.text, "Edited synthetic capture")
        XCTAssertEqual(fixture.model.draft.requestID, requestID)
        XCTAssertNil(fixture.model.lastReceipt)
        XCTAssertNotNil(fixture.model.errorMessage)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
        let saved = try await CaptureDraftStore(rootDirectoryURL: fixture.root).load(id: fixture.model.draft.id)
        XCTAssertEqual(saved?.text, "Edited synthetic capture")
        let counts = await accounting.counts()
        XCTAssertEqual(counts.committed, 0)
    }

    func testDiscardedHTTPHandoffPreservesDraftOnSend() async throws {
        let accounting = ComposerHTTPAccounting(failsFirstCommit: true)
        let fixture = try await makeFixture(refuseLease: true, accounting: accounting)
        fixture.model.draft.text = "Unsent synthetic capture"
        let draftID = fixture.model.draft.id
        let requestID = fixture.model.draft.requestID
        await fixture.model.submit()
        XCTAssertNotNil(fixture.model.errorMessage)
        XCTAssertEqual(fixture.model.draft.text, "Unsent synthetic capture")

        await fixture.owner.discard(id: requestID)
        await fixture.model.submit()
        XCTAssertEqual(fixture.model.draft.id, draftID)
        XCTAssertEqual(fixture.model.draft.requestID, requestID)
        XCTAssertEqual(fixture.model.draft.text, "Unsent synthetic capture")
        XCTAssertNil(fixture.model.lastReceipt)
        XCTAssertNotNil(fixture.model.errorMessage)
        let saved = try await CaptureDraftStore(rootDirectoryURL: fixture.root).load(id: draftID)
        XCTAssertEqual(saved?.text, "Unsent synthetic capture")
        let counts = await accounting.counts()
        XCTAssertEqual(counts.committed, 0)
        XCTAssertTrue(fixture.owner.receipts.isEmpty)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
    }

    func testUnchangedDraftCanCompleteAfterHTTPAccountingFailure() async throws {
        let accounting = ComposerHTTPAccounting(failsFirstCommit: true)
        let fixture = try await makeFixture(refuseLease: true, accounting: accounting)
        fixture.model.draft.text = "Unchanged synthetic capture"
        let requestID = fixture.model.draft.requestID
        await fixture.model.submit()
        XCTAssertNotNil(fixture.model.errorMessage)
        await fixture.model.submit()
        XCTAssertNil(fixture.model.errorMessage)
        XCTAssertEqual(fixture.model.draft.text, "")
        XCTAssertEqual(fixture.model.lastReceipt?.requestID, requestID)
        await fixture.owner.refresh()
        XCTAssertEqual(fixture.owner.receipts.count, 1)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
        let counts = await accounting.counts()
        XCTAssertEqual(counts.committed, 1)
    }

    func testMissingHTTPURLRecoveryUsesExplicitDraftPresetNotDefault() async throws {
        let fixture = try await makeFixture()
        var selected = fixture.preset
        selected.exportSettings.urlDelivery.urlString = ""
        var other = selected
        other.id = "other-http-preset"
        other.name = "Other HTTP"
        CapturePresetStore.saveFlows([selected, other], defaults: fixture.defaults, widgetRefresh: .disabled)
        CapturePresetProfileStore.selectCaptureProfile(id: other.id, defaults: fixture.defaults)
        fixture.model.refreshVoxProfiles()
        fixture.model.draft.text = "Keep this draft"
        fixture.model.draft.voxID = selected.id
        let requestID = fixture.model.draft.requestID
        XCTAssertNotNil(fixture.model.httpDestinationIssue)
        XCTAssertEqual(fixture.model.httpEndpointSettingsPresetID, selected.id)
        XCTAssertEqual(fixture.model.draft.text, "Keep this draft")
        XCTAssertEqual(fixture.model.draft.requestID, requestID)

        selected.exportSettings.urlDelivery.urlString = "https://example.invalid/configured"
        CapturePresetStore.saveFlows([selected, other], defaults: fixture.defaults, widgetRefresh: .disabled)
        fixture.model.refreshVoxProfiles()
        XCTAssertNil(fixture.model.httpEndpointSettingsPresetID)
        XCTAssertNil(fixture.model.httpDestinationIssue)
        XCTAssertTrue(fixture.model.canSubmit)
        XCTAssertEqual(fixture.model.draft.voxID, selected.id)
    }

    func testInvalidHTTPURLOffersEndpointRecovery() async throws {
        let fixture = try await makeFixture()
        var preset = fixture.preset
        preset.exportSettings.urlDelivery.urlString = "not a delivery URL"
        CapturePresetStore.saveFlows([preset], defaults: fixture.defaults, widgetRefresh: .disabled)
        fixture.model.refreshVoxProfiles()
        XCTAssertEqual(fixture.model.httpEndpointSettingsPresetID, preset.id)
    }

    func testDirectoryAndStalePresetDoNotOfferHTTPRecovery() async throws {
        let fixture = try await makeFixture(httpTarget: false)
        XCTAssertNil(fixture.model.httpEndpointSettingsPresetID)
        fixture.model.draft.voxID = "missing-preset"
        XCTAssertNil(fixture.model.httpEndpointSettingsPresetID)
    }

    func testDirectoryOnlySendWritesNoteWithoutHTTP() async throws {
        let fixture = try await makeFixture(httpTarget: false)
        fixture.model.draft.text = "Synthetic directory-only capture"
        XCTAssertTrue(fixture.model.canSubmit)
        await fixture.model.submit()
        XCTAssertNil(fixture.model.errorMessage)
        let noteURL = try XCTUnwrap(fixture.model.lastReceipt?.noteURL)
        XCTAssertTrue(try String(contentsOf: noteURL, encoding: .utf8).contains("Synthetic directory-only capture"))
        await fixture.owner.refresh()
        XCTAssertTrue(fixture.owner.receipts.isEmpty)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
    }

    func testHTTPAttachmentAttemptPreservesDraftAndStagedFile() async throws {
        let fixture = try await makeFixture(refuseLease: true)
        fixture.model.draft.text = "Do not lose my attachment"
        let source = fixture.root.appendingPathComponent("synthetic.txt")
        try Data("Synthetic attachment".utf8).write(to: source)
        let staged = await fixture.model.stageFile(at: source, contentTypeIdentifier: "public.plain-text")
        let payload = try XCTUnwrap(staged)
        XCTAssertFalse(fixture.model.canSubmit)
        XCTAssertNil(fixture.model.httpEndpointSettingsPresetID)
        await fixture.model.submit()
        XCTAssertNotNil(fixture.model.errorMessage)
        XCTAssertNil(fixture.model.lastReceipt)
        XCTAssertEqual(fixture.model.draft.additionalPayloads, [payload])
        XCTAssertEqual(fixture.model.draft.text, "Do not lose my attachment")
        await fixture.owner.refresh()
        XCTAssertTrue(fixture.owner.receipts.isEmpty)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
    }

    func testDraftEditingDoesNotPrepareOrPOST() async throws {
        let fixture = try await makeFixture()
        _ = await fixture.model.appendRecognizedText("Synthetic draft only")
        await fixture.owner.refresh()
        XCTAssertTrue(fixture.owner.receipts.isEmpty)
        XCTAssertEqual(ComposerHTTPProtocol.requestCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.vault.appendingPathComponent("Inbox.md").path))
    }

    func testHTTPHandoffCompletesWithoutNoteWhileBackoffRemainsOwned() async throws {
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
        XCTAssertNil(receipt.noteURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.vault.appendingPathComponent("Inbox.md").path))
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
        changed.deliveryTarget = .directory
        changed.exportSettings.urlDelivery.urlString = "https://example.invalid/changed"
        CapturePresetStore.saveFlows([changed], defaults: fixture.defaults, widgetRefresh: .disabled)
        await processor.release()
        await submission.value
        await fixture.owner.cancelAll()
        XCTAssertNil(fixture.model.errorMessage)
        let receipt = try XCTUnwrap(fixture.model.lastReceipt)
        XCTAssertNil(receipt.noteURL)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.vault.path).isEmpty)
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
        refuseLease: Bool = false, directoryConfigured: Bool = true, httpTarget: Bool = true,
        sleeper: @escaping TranscriptURLDeliverer.Sleeper = { _ in },
        accounting: any CaptureDeliveryAccounting = UnmeteredCaptureDeliveryAccounting()
    ) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ComposerURL-\(UUID().uuidString)")
        let vault = root.appendingPathComponent("vault")
        let journal = root.appendingPathComponent("http-journal")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        if brokenJournal { try Data("Not a directory".utf8).write(to: journal) }
        let destination = CaptureDestination(name: "Synthetic", rootBookmark: try vault.bookmarkData(), rootName: "Synthetic Vault",
                                             noteTarget: .existingNote(relativePath: "Inbox.md"), retryProtectionEnabled: true)
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: directoryConfigured ? [destination] : [],
                                         defaultDestinationID: directoryConfigured ? destination.id : nil))
        let suite = "ComposerURL-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        var preset = CapturePresetStore.makeCustomFlow()
        preset.name = "Synthetic HTTP"
        preset.captureDestinationID = directoryConfigured ? destination.id : nil
        preset.postProcessingMode = processor == nil ? .none : .clean
        preset.captureProcessingEnabled = true
        preset.exportSettings.urlDelivery = .init(enabled: httpTarget, urlString: "https://example.invalid/ingest", maxAttempts: 2)
        CapturePresetStore.saveFlows([preset], defaults: defaults, widgetRefresh: .disabled)
        ComposerHTTPProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ComposerHTTPProtocol.self]
        let sender = TranscriptURLDeliverer(session: URLSession(configuration: configuration), receiptsDirectoryURL: journal,
                                            credentialsProvider: { _ in nil }, logger: { _ in }, sleeper: sleeper)
        let owner = URLDeliveryCoordinator(deliverer: sender, beginExecution: { _ in refuseLease ? nil : .init() })
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline(),
            requestProcessor: CapturePresetRequestProcessor(textProcessor: processor), urlDeliveryCoordinator: owner,
            httpDeliveryAccounting: accounting)
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

private actor ComposerHTTPAccounting: CaptureDeliveryAccounting {
    let refusesQuota: Bool
    private var reserved = 0
    private var committed = 0
    private var released = 0
    private var failsFirstCommit: Bool
    init(refusesQuota: Bool = false, failsFirstCommit: Bool = false) {
        self.refusesQuota = refusesQuota
        self.failsFirstCommit = failsFirstCommit
    }
    func reserve(for request: CaptureRequest) async throws -> CaptureDeliveryReservation {
        if refusesQuota { throw CaptureDeliveryQuotaError.limitReached(limit: 10) }
        reserved += 1
        return .reserved(requestID: request.id, token: UUID())
    }
    func commit(_ reservation: CaptureDeliveryReservation) async throws {
        if failsFirstCommit {
            failsFirstCommit = false
            throw CaptureDeliveryUsageStoreError.storageUnavailable
        }
        committed += 1
    }
    func release(_ reservation: CaptureDeliveryReservation) async { released += 1 }
    func counts() -> (reserved: Int, committed: Int, released: Int) { (reserved, committed, released) }
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
    static var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    static func reset() { lock.lock(); defer { lock.unlock() }; count = 0 }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self.count += 1; Self.lock.unlock()
        guard let url = request.url, let response = HTTPURLResponse(url: url, statusCode: 503, httpVersion: "HTTP/1.1", headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
