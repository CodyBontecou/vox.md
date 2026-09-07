import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CaptureImagePreparationTests: XCTestCase {
    func test_cancelledSendKeepsDraftAndUsesItsStagingRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = CaptureDestination(name: "Inbox", rootBookmark: try vault.bookmarkData(), rootName: "Vault",
                                             noteTarget: .existingNote(relativePath: "Inbox.md"))
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let describer = PreparationImageFixture()
        let savedPresets = AppConstants.sharedDefaults?.data(forKey: CapturePresetStore.flowsKey)
        let suite = "ImageCaptureQA." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline(),
            requestProcessor: CapturePresetRequestProcessor(imageDescriber: describer))
        await model.load()
        let profile = CapturePresetProfile(id: "images", name: "Images", symbolName: "photo", postProcessingMode: .none,
                                           captureProcessingEnabled: true, generateImageAltText: true, captureDestinationID: destination.id)
        model.voxProfiles = [profile]
        model.draft.voxID = profile.id
        let bytes = Data([1, 2, 3])
        await model.stageImage(data: bytes, filename: "photo.png", contentTypeIdentifier: "public.png")
        XCTAssertTrue(model.canSubmit)
        let draftID = model.draft.id
        let submit = Task { await model.submit() }
        for _ in 0..<100 {
            if await describer.root != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let usedRoot = await describer.root
        XCTAssertEqual(usedRoot?.standardizedFileURL, root.appendingPathComponent("staging/\(draftID.uuidString.lowercased())").standardizedFileURL)
        XCTAssertTrue(model.isDescribingImages)
        submit.cancel()
        await submit.value
        XCTAssertFalse(model.isSubmitting)
        XCTAssertFalse(model.isDescribingImages)
        XCTAssertNil(model.lastReceipt)
        XCTAssertNil(model.errorMessage)
        let store = CaptureDraftStore(rootDirectoryURL: root)
        let persisted = try await store.load(id: draftID)
        XCTAssertEqual(persisted?.additionalPayloads, model.draft.additionalPayloads)
        XCTAssertFalse(FileManager.default.fileExists(atPath: vault.appendingPathComponent("Inbox.md").path))
        XCTAssertEqual(AppConstants.sharedDefaults?.data(forKey: CapturePresetStore.flowsKey), savedPresets)
    }
}

private actor PreparationImageFixture: CaptureImageDescribing {
    var root: URL?
    func describe(asset: CaptureAssetReference, assetRootURL: URL, localeIdentifier: String) async throws -> String? {
        root = assetRootURL
        XCTAssertEqual(try CaptureImageAssetReader.read(asset: asset, rootURL: assetRootURL), Data([1, 2, 3]))
        try await Task.sleep(nanoseconds: 10_000_000_000)
        return "Unused late description."
    }
}
