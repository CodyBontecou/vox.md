import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CaptureImagePreparationTests: XCTestCase {
    func test_stageImageGeneratesAltTextImmediatelyAndSendReusesIt() async throws {
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
        let draftID = model.draft.id

        await model.stageImage(data: bytes, filename: "photo.png", contentTypeIdentifier: "public.png")

        let usedRoot = await describer.firstRoot
        XCTAssertEqual(usedRoot?.standardizedFileURL, root.appendingPathComponent("staging/\(draftID.uuidString.lowercased())").standardizedFileURL)
        let asset = try CaptureAssetReference(
            relativePath: "photo.png",
            originalFilename: "photo.png",
            contentTypeIdentifier: "public.png",
            byteCount: 3
        )
        XCTAssertEqual(model.draft.additionalPayloads, [
            .image(asset, altText: "Visible before send.", altTextOrigin: .generated)
        ])
        let store = CaptureDraftStore(rootDirectoryURL: root)
        let persisted = try await store.load(id: draftID)
        XCTAssertEqual(persisted?.additionalPayloads, model.draft.additionalPayloads)
        XCTAssertTrue(model.canSubmit)
        XCTAssertFalse(model.isDescribingImages)

        await model.submit()

        XCTAssertNil(model.errorMessage)
        let receipt = try XCTUnwrap(model.lastReceipt)
        let markdown = try String(contentsOf: receipt.noteURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("![Visible before send.]"), markdown)
        let rootCount = await describer.rootCount
        XCTAssertEqual(rootCount, 1, "Send should reuse the generated draft alt text instead of describing again")
        XCTAssertEqual(AppConstants.sharedDefaults?.data(forKey: CapturePresetStore.flowsKey), savedPresets)
    }
}

private actor PreparationImageFixture: CaptureImageDescribing {
    var roots: [URL] = []
    var firstRoot: URL? { roots.first }
    var rootCount: Int { roots.count }

    func describe(asset: CaptureAssetReference, assetRootURL: URL, localeIdentifier: String) async throws -> String? {
        roots.append(assetRootURL)
        XCTAssertEqual(try CaptureImageAssetReader.read(asset: asset, rootURL: assetRootURL), Data([1, 2, 3]))
        return "Visible before send."
    }
}
