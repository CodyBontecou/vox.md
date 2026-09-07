import XCTest
@testable import VoxboardShared

final class CaptureImageDeliveryTests: XCTestCase {
    func test_failedDeliveryRetriesPersistedDescriptionAndOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data([1, 2, 3, 4])
        try bytes.write(to: root.appendingPathComponent("photo.png"))
        let asset = try CaptureAssetReference(relativePath: "photo.png", originalFilename: "photo.png", contentTypeIdentifier: "public.png")
        let destination = CaptureDestination(name: "Inbox", rootBookmark: try vault.bookmarkData(), rootName: "Vault",
                                             noteTarget: .existingNote(relativePath: "Inbox.md"))
        let profile = CapturePresetProfile(id: "images", name: "Images", symbolName: "photo", postProcessingMode: .none,
                                           captureProcessingEnabled: true, generateImageAltText: true)
        let request = CaptureRequest(source: .shareExtension, destinationID: destination.id,
                                     payloads: [.image(asset, altText: "Screenshot", altTextOrigin: .placeholder)],
                                     voxProfile: profile, voxProcessingState: .pending, imageDescriptionLocaleIdentifier: "es")
        let coordinator = ProcessLocalCaptureFileCoordinator.shared
        let inbox = CaptureInbox(rootDirectoryURL: root, coordinator: coordinator)
        try await inbox.enqueue(request)
        let firstDescriber = DeliveryImageFixture()
        let pipeline = CapturePipeline(writer: CoordinatedCaptureWriter(coordinator: coordinator))
        let failed = await CaptureInboxDeliveryService.drain(captureRootURL: root, defaults: nil, pipeline: pipeline,
            requestProcessor: CapturePresetRequestProcessor(imageDescriber: firstDescriber), coordinator: coordinator)
        XCTAssertEqual(failed.failedRequestIDs, [request.id])
        let savedRequest = try await inbox.request(requestID: request.id, states: [.failed])
        let saved = try XCTUnwrap(savedRequest)
        XCTAssertEqual(saved.voxProcessingState, .applied)
        XCTAssertEqual(saved.payloads, [.image(asset, altText: "Un cuadrado azul.", altTextOrigin: .generated)])
        let firstCalls = await firstDescriber.calls
        XCTAssertEqual(firstCalls, ["es"])
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(CaptureLibraryStore.defaultFilename), coordinator: coordinator)
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let replacement = DeliveryImageFixture()
        let delivered = await CaptureInboxDeliveryService.drain(captureRootURL: root, retryFailed: true, defaults: nil, pipeline: pipeline,
            requestProcessor: CapturePresetRequestProcessor(imageDescriber: replacement), coordinator: coordinator)
        XCTAssertEqual(delivered.receipts.map(\.requestID), [request.id])
        let replacementCalls = await replacement.calls
        XCTAssertTrue(replacementCalls.isEmpty)
        let attachment = try XCTUnwrap(delivered.receipts.first?.attachmentURLs.first)
        XCTAssertEqual(try Data(contentsOf: attachment), bytes)
        let markdown = try String(contentsOf: vault.appendingPathComponent("Inbox.md"), encoding: .utf8)
        XCTAssertTrue(markdown.contains("![Un cuadrado azul.]"))
        let again = await CaptureInboxDeliveryService.drain(captureRootURL: root, retryFailed: true, defaults: nil, pipeline: pipeline, coordinator: coordinator)
        XCTAssertTrue(again.receipts.isEmpty)
        XCTAssertEqual(try String(contentsOf: vault.appendingPathComponent("Inbox.md"), encoding: .utf8), markdown)
    }

    func test_cancelledDrainReturnsUnpreparedCaptureToPending() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let asset = try CaptureAssetReference(relativePath: "photo.png", originalFilename: "photo.png", contentTypeIdentifier: "public.png")
        let profile = CapturePresetProfile(id: "images", name: "Images", symbolName: "photo", postProcessingMode: .none,
                                           captureProcessingEnabled: true, generateImageAltText: true)
        let request = CaptureRequest(source: .app, destinationID: UUID(), payloads: [.image(asset, altText: nil)],
                                     voxProfile: profile, voxProcessingState: .pending)
        let inbox = CaptureInbox(rootDirectoryURL: root, coordinator: ProcessLocalCaptureFileCoordinator.shared)
        try await inbox.enqueue(request)
        let describer = DeliveryImageFixture(delay: true)
        let task = Task { await CaptureInboxDeliveryService.drain(captureRootURL: root, defaults: nil,
            requestProcessor: CapturePresetRequestProcessor(imageDescriber: describer), coordinator: ProcessLocalCaptureFileCoordinator.shared) }
        while await describer.calls.isEmpty { try await Task.sleep(nanoseconds: 1_000_000) }
        task.cancel()
        let result = await task.value
        XCTAssertTrue(result.failedRequestIDs.isEmpty)
        XCTAssertTrue(result.receipts.isEmpty)
        let pending = try await inbox.request(requestID: request.id, states: [.pending])
        XCTAssertEqual(pending, request)
    }
}

private actor DeliveryImageFixture: CaptureImageDescribing {
    var calls: [String] = []
    let delay: Bool
    init(delay: Bool = false) { self.delay = delay }
    func describe(asset: CaptureAssetReference, assetRootURL: URL, localeIdentifier: String) async throws -> String? {
        calls.append(localeIdentifier)
        if delay { try await Task.sleep(nanoseconds: 5_000_000_000) }
        else { XCTAssertEqual(try CaptureImageAssetReader.read(asset: asset, rootURL: assetRootURL), Data([1, 2, 3, 4])) }
        return "Un cuadrado azul."
    }
}
