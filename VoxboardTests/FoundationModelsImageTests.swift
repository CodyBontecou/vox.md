import FoundationModels
import ImageIO
import UIKit
import UniformTypeIdentifiers
import VoxboardShared
import XCTest
@testable import Voxboard

final class FoundationModelsImageTests: XCTestCase {
    @MainActor
    func test_previewHonorsRotationAndBoundsWithoutChangingOriginal() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let original = UIGraphicsImageRenderer(size: CGSize(width: 2400, height: 1200), format: format).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2400, height: 1200))
        }
        let bytes = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(bytes, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(original.cgImage), [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = bytes as Data
        let preview = try CaptureImagePreview.decode(source)
        XCTAssertEqual(preview.width, 768)
        XCTAssertEqual(preview.height, 1536)
        XCTAssertEqual(source, bytes as Data)
        XCTAssertThrowsError(try CaptureImagePreview.decode(Data("corrupt image".utf8)))
    }

    #if compiler(>=6.4)
    @available(iOS 27, *)
    func test_newModelErrorsMapToTerminalOutcomes() {
        XCTAssertEqual(FoundationModelsBackend.normalizedError(LanguageModelError.contextSizeExceeded(
            .init(contextSize: 4096, tokenCount: 5000, debugDescription: "Synthetic"))), .inputTooLarge)
        XCTAssertEqual(FoundationModelsBackend.normalizedError(LanguageModelError.guardrailViolation(
            .init(debugDescription: "Synthetic"))), .refusal)
        XCTAssertEqual(FoundationModelsBackend.normalizedError(LanguageModelError.rateLimited(
            .init(resetDate: nil, debugDescription: "Synthetic"))), .busy)
    }

    @MainActor
    func test_availableOS27ImageCaptureDeliversAltTextAndOriginalBytes() async throws {
        guard ProcessInfo.processInfo.environment["VOX_RUN_MODEL_EVALUATIONS"] == "1" else {
            throw XCTSkip("Opt in with VOX_RUN_MODEL_EVALUATIONS=1 on an OS 27 device")
        }
        guard #available(iOS 27, *), SystemLanguageModel.default.isAvailable,
              SystemLanguageModel.default.capabilities.contains(.vision) else {
            throw XCTSkip("An available OS 27 model with vision is required")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = CaptureDestination(name: "Synthetic QA", rootBookmark: try vault.bookmarkData(),
                                             rootName: "QA", noteTarget: .existingNote(relativePath: "Image QA.md"))
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let savedPresets = AppConstants.sharedDefaults?.data(forKey: CapturePresetStore.flowsKey)
        let suite = "ImageCaptureQA." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline(),
            requestProcessor: CapturePresetRequestProcessor(imageDescriber: FoundationModelsImageDescriber()))
        await model.load()
        let profile = CapturePresetProfile(id: "synthetic-qa", name: "Synthetic QA", symbolName: "photo",
            postProcessingMode: .none, captureProcessingEnabled: true, generateImageAltText: true,
            captureDestinationID: destination.id)
        model.voxProfiles = [profile]
        model.draft.voxID = profile.id
        let text = "Keep **this Markdown** and https://example.com/a?b=1 exactly."
        model.draft.text = text
        let data = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 64, y: 64, width: 128, height: 128))
        }
        await model.stageImage(data: data, filename: "blue square.png", contentTypeIdentifier: UTType.png.identifier,
                               altText: "Screenshot", altTextOrigin: .placeholder)
        let started = ProcessInfo.processInfo.systemUptime
        await model.submit()
        XCTAssertNil(model.errorMessage)
        let receipt = try XCTUnwrap(model.lastReceipt)
        let markdown = try String(contentsOf: receipt.noteURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains(text), markdown)
        XCTAssertTrue(markdown.localizedCaseInsensitiveContains("blue"), markdown)
        XCTAssertTrue(markdown.contains("!["), markdown)
        XCTAssertFalse(markdown.contains("![["), markdown)
        XCTAssertEqual(receipt.attachmentURLs.count, 1)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(receipt.attachmentURLs.first)), data)
        XCTAssertFalse(model.isSubmitting)
        XCTAssertFalse(model.isDescribingImages)
        XCTAssertTrue(model.draft.text.isEmpty)
        XCTAssertTrue(model.draft.additionalPayloads.isEmpty)
        XCTAssertEqual(AppConstants.sharedDefaults?.data(forKey: CapturePresetStore.flowsKey), savedPresets)
        let evidence = XCTAttachment(string: "Synthetic capture delivery:\n\(markdown)\nSeconds: \(ProcessInfo.processInfo.systemUptime - started)")
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    func test_availableOS27ModelDescribesSyntheticImage() async throws {
        guard ProcessInfo.processInfo.environment["VOX_RUN_MODEL_EVALUATIONS"] == "1" else {
            throw XCTSkip("Opt in with VOX_RUN_MODEL_EVALUATIONS=1 on an OS 27 device with installed model assets")
        }
        guard #available(iOS 27, *), SystemLanguageModel.default.isAvailable,
              SystemLanguageModel.default.capabilities.contains(.vision) else {
            throw XCTSkip("An available OS 27 system model with vision support is required for image inference")
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = UIGraphicsImageRenderer(size: CGSize(width: 256, height: 256)).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 64, y: 64, width: 128, height: 128))
        }
        try data.write(to: root.appendingPathComponent("square.png"))
        let asset = try CaptureAssetReference(relativePath: "square.png", originalFilename: "square.png", contentTypeIdentifier: UTType.png.identifier)
        if ProcessInfo.processInfo.environment["VOX_DIAGNOSE_IMAGE_MODEL"] == "1" {
            let image = try CaptureImagePreview.decode(data)
            let prompt = Prompt { "Describe this image in one sentence."; Attachment(image) }
            for kind in ["text tokens", "image tokens", "image response"] {
                do {
                    let result = try await withCaptureProcessingDeadline(timeout: 30) {
                        switch kind {
                        case "text tokens": return String(try await SystemLanguageModel.default.tokenCount(for: Prompt("Describe this image.")))
                        case "image tokens": return String(try await SystemLanguageModel.default.tokenCount(for: prompt))
                        default: return try await LanguageModelSession(model: SystemLanguageModel.default).respond(to: prompt).content
                        }
                    }
                    print("SYNTHETIC IMAGE QA \(kind): \(result)")
                } catch { print("SYNTHETIC IMAGE QA \(kind): \(String(reflecting: error))") }
            }
        }
        let started = ProcessInfo.processInfo.systemUptime
        let description = try await withCaptureProcessingDeadline(timeout: 30) {
            try await FoundationModelsImageDescriber().describe(asset: asset, assetRootURL: root, localeIdentifier: "en")
        }
        XCTAssertNotNil(CaptureImageDescription.validated(description))
        XCTAssertTrue(description?.localizedCaseInsensitiveContains("blue") == true)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("square.png")), data)
        let evidence = XCTAttachment(string: "Synthetic blue square: \(description ?? "nil")\nSeconds: \(ProcessInfo.processInfo.systemUptime - started)")
        evidence.lifetime = .keepAlways
        add(evidence)
    }
    #endif
}
