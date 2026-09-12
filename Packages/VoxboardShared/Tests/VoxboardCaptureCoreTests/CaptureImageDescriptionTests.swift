import XCTest
@testable import VoxboardCaptureCore

final class CaptureImageDescriptionTests: XCTestCase {
    private func asset(_ name: String = "photo.png") throws -> CaptureAssetReference {
        try CaptureAssetReference(relativePath: name, originalFilename: name, contentTypeIdentifier: "public.png")
    }

    private func profile(enabled: Bool = true) -> CapturePresetProfile {
        CapturePresetProfile(id: "images", name: "Images", symbolName: "photo", postProcessingMode: .none,
                             captureProcessingEnabled: enabled, generateImageAltText: true)
    }

    private func request(_ payloads: [CapturePayload], enabled: Bool = true) -> CaptureRequest {
        let profile = profile(enabled: enabled)
        return CaptureRequest(source: .app, destinationID: UUID(), payloads: payloads, voxProfile: profile,
                              voxProcessingState: profile.processingState(for: payloads), imageDescriptionLocaleIdentifier: "es")
    }

    func test_legacyAndExplicitDescriptionProvenance() throws {
        let image = try asset()
        let legacy = Data("""
        {"kind":"image","asset":{"relativePath":"photo.png","originalFilename":"photo.png","contentTypeIdentifier":"public.png"},"altText":"Screenshot"}
        """.utf8)
        XCTAssertEqual(try JSONDecoder().decode(CapturePayload.self, from: legacy), .image(image, altText: "Screenshot"))
        for origin in [CaptureAltTextOrigin.placeholder, .provided, .generated] {
            let payload = CapturePayload.image(image, altText: "Description", altTextOrigin: origin)
            XCTAssertEqual(try JSONDecoder().decode(CapturePayload.self, from: JSONEncoder().encode(payload)), payload)
        }
        XCTAssertFalse(CaptureAltTextOrigin.needsDescription(text: "Screenshot", origin: nil))
        XCTAssertFalse(CaptureAltTextOrigin.needsDescription(text: "", origin: .provided))
        XCTAssertFalse(CaptureAltTextOrigin.needsDescription(text: nil, origin: .provided))
        XCTAssertFalse(CaptureAltTextOrigin.needsDescription(text: "", origin: nil))
        XCTAssertTrue(CaptureAltTextOrigin.needsDescription(text: "Screenshot", origin: .placeholder))
    }

    func test_imageOnlyModePreservesTextAndAttachments() async throws {
        let image = try asset()
        let drawing = try asset("sketch.drawing")
        let original = request([.text("raw **Markdown**"), .audio(image, transcript: "raw speech"),
                                .image(image, altText: "Screenshot", altTextOrigin: .placeholder),
                                .sketch(drawing: drawing, preview: image, altText: nil)])
        let fake = ImageDescriberFixture()
        let root = URL(fileURLWithPath: "/tmp/fixture-root")
        let output = await CapturePresetRequestProcessor(textProcessor: ForbiddenTextProcessor(), imageDescriber: fake)
            .process(original, assetRootURL: root)
        XCTAssertEqual(output.payloads[0], original.payloads[0])
        XCTAssertEqual(output.payloads[1], original.payloads[1])
        XCTAssertEqual(output.payloads[2], .image(image, altText: "A useful description.", altTextOrigin: .generated))
        XCTAssertEqual(output.payloads[3], .sketch(drawing: drawing, preview: image, altText: "A useful description.", altTextOrigin: .generated))
        let calls = await fake.calls
        XCTAssertEqual(calls.map(\.locale), ["es", "es"])
        XCTAssertEqual(calls.map(\.root), [root, root])
        XCTAssertEqual(output.voxProcessingState, .applied)
    }

    func test_processImagePayloadsCanPrepareDraftPreviewWithoutFullRequest() async throws {
        let image = try asset()
        let supplied = try asset("supplied.png")
        let fake = ImageDescriberFixture(output: "Visible draft label.")
        let root = URL(fileURLWithPath: "/tmp/draft-preview-root")
        let payloads: [CapturePayload] = [
            .text("raw **Markdown**"),
            .image(image, altText: nil),
            .image(supplied, altText: "Supplied caption", altTextOrigin: .provided)
        ]

        let output = await CapturePresetRequestProcessor(textProcessor: ForbiddenTextProcessor(), imageDescriber: fake)
            .processImagePayloads(payloads, profile: profile(), assetRootURL: root, localeIdentifier: "fr")

        XCTAssertEqual(output[0], payloads[0])
        XCTAssertEqual(output[1], .image(image, altText: "Visible draft label.", altTextOrigin: .generated))
        XCTAssertEqual(output[2], payloads[2])
        let calls = await fake.calls
        XCTAssertEqual(calls.map(\.locale), ["fr"])
        XCTAssertEqual(calls.map(\.root), [root])
    }

    func test_masterGateAndSavedDescriptionsAvoidAllImageCalls() async throws {
        let image = try asset()
        let fake = ImageDescriberFixture()
        let processor = CapturePresetRequestProcessor(imageDescriber: fake)
        let off = request([.image(image, altText: nil)], enabled: false)
        let offOutput = await processor.process(off, assetRootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(offOutput, off)
        let supplied = request([.image(image, altText: "My caption", altTextOrigin: .provided),
                                .image(image, altText: "", altTextOrigin: .provided),
                                .image(image, altText: "Saved description", altTextOrigin: .generated),
                                .image(image, altText: "Legacy caption")])
        let suppliedOutput = await processor.process(supplied, assetRootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(suppliedOutput, supplied)
        let calls = await fake.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func test_failuresAndInvalidOutputPreserveOriginalLabel() async throws {
        let original = request([.image(try asset(), altText: "Screenshot", altTextOrigin: .placeholder)])
        for fake in [ImageDescriberFixture(fails: true), ImageDescriberFixture(output: nil),
                     ImageDescriberFixture(output: String(repeating: "x", count: 301)),
                     ImageDescriberFixture(output: "First\nSecond")] {
            let output = await CapturePresetRequestProcessor(imageDescriber: fake)
                .process(original, assetRootURL: URL(fileURLWithPath: "/tmp"))
            XCTAssertEqual(output.payloads, original.payloads)
            XCTAssertEqual(output.voxProcessingState, .applied)
        }
    }

    func test_missingAssetContextOrDescriberFallsBackWithoutReading() async throws {
        let original = request([.image(try asset(), altText: nil)])
        let fake = ImageDescriberFixture()
        let output = await CapturePresetRequestProcessor(imageDescriber: fake).process(original)
        XCTAssertEqual(output.payloads, original.payloads)
        XCTAssertEqual(output.voxProcessingState, .applied)
        let calls = await fake.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func test_totalBudgetAndLateCompletionCannotChangePreparedResult() async throws {
        let original = request(try (0..<10).map { .image(try asset("photo-\($0).png"), altText: nil) })
        let fake = ImageDescriberFixture(delay: 0.2)
        let processor = CapturePresetRequestProcessor(imageDescriber: fake, imageTimeout: 0.04, imageStageTimeout: 0.06)
        let start = ProcessInfo.processInfo.systemUptime
        let output = await processor.process(original, assetRootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.18)
        XCTAssertEqual(output.payloads, original.payloads)
        let saved = try JSONEncoder().encode(output)
        try await Task.sleep(nanoseconds: 260_000_000)
        let calls = await fake.calls
        XCTAssertLessThanOrEqual(calls.count, 2)
        let reloaded = try JSONDecoder().decode(CaptureRequest.self, from: saved)
        let retry = await processor.process(reloaded, assetRootURL: URL(fileURLWithPath: "/tmp"))
        XCTAssertEqual(retry, output)
        let retryCalls = await fake.calls
        XCTAssertEqual(retryCalls.count, calls.count)
    }

    func test_cancellationLeavesOriginalPendingRequest() async throws {
        let original = request([.image(try asset(), altText: nil)])
        let fake = ImageDescriberFixture(delay: 0.2)
        let task = Task { await CapturePresetRequestProcessor(imageDescriber: fake)
            .process(original, assetRootURL: URL(fileURLWithPath: "/tmp")) }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        let result = await task.value
        XCTAssertEqual(result, original)
        XCTAssertEqual(result.voxProcessingState, .pending)
    }

    func test_preparedRequestRetainsLocaleAndImagePolicy() throws {
        let original = request([.image(try asset(), altText: nil)])
        let reloaded = try JSONDecoder().decode(CaptureRequest.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(reloaded.imageDescriptionLocaleIdentifier, "es")
        XCTAssertEqual(reloaded.voxProfile?.generateImageAltText, true)
        let legacyProfile = try JSONDecoder().decode(CapturePresetProfile.self, from: Data("{\"id\":\"old\",\"name\":\"Old\"}".utf8))
        XCTAssertFalse(legacyProfile.generateImageAltText)
    }

    func test_generatedMarkdownUsesAltSyntaxAndEscapesPath() throws {
        let image = try asset("photo [1] (a)#%.png")
        let destination = CaptureDestination(name: "Inbox", rootBookmark: Data(), rootName: "Vault",
                                             noteTarget: .existingNote(relativePath: "Inbox.md"), attachmentsFolderName: "My Assets")
        let generated = request([.image(image, altText: "A [blue] box.", altTextOrigin: .generated)])
        let markdown = try CaptureMarkdownRenderer().render(generated, for: destination)
        XCTAssertEqual(markdown, "![A \\[blue\\] box.](My%20Assets/photo%20%5B1%5D%20%28a%29%23%25.png)")
        let fallback = request([.image(image, altText: "Screenshot", altTextOrigin: .placeholder)])
        XCTAssertTrue(try CaptureMarkdownRenderer().render(fallback, for: destination).hasPrefix("![["))
        let literal = request([.image(try asset(), altText: "A *star*, `code`, and &copy;.", altTextOrigin: .generated)])
        XCTAssertEqual(try CaptureMarkdownRenderer().render(literal, for: destination),
                       "![A \\*star\\*, \\`code\\`, and &amp;copy;.](My%20Assets/photo.png)")
    }

    func test_secureReaderPreservesBytesAndRejectsSymlinksAndOversize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bytes = Data([1, 2, 3])
        try bytes.write(to: root.appendingPathComponent("photo.png"))
        XCTAssertEqual(try CaptureImageAssetReader.read(asset: asset(), rootURL: root), bytes)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link.png").path,
                                                  withDestinationPath: root.appendingPathComponent("photo.png").path)
        XCTAssertThrowsError(try CaptureImageAssetReader.read(asset: asset("link.png"), rootURL: root))
        XCTAssertThrowsError(try SecureCaptureFileIO.read(relativePath: "photo.png", rootURL: root, maximumByteCount: 2))
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("photo.png")), bytes)
    }
}

private actor ImageDescriberFixture: CaptureImageDescribing {
    struct Call { let root: URL; let locale: String }
    var calls: [Call] = []
    let output: String?
    let delay: TimeInterval
    let fails: Bool

    init(output: String? = "A useful description.", delay: TimeInterval = 0, fails: Bool = false) {
        self.output = output; self.delay = delay; self.fails = fails
    }

    func describe(asset: CaptureAssetReference, assetRootURL: URL, localeIdentifier: String) async throws -> String? {
        calls.append(Call(root: assetRootURL, locale: localeIdentifier))
        if delay > 0 {
            // Deliberately ignores cancellation, but always finishes to avoid leaking test work.
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { continuation.resume() }
            }
        }
        if fails { throw CaptureProcessingTimeout() }
        return output
    }
}

private struct ForbiddenTextProcessor: CapturePresetTextProcessing {
    func process(text: String, profile: CapturePresetProfile) async throws -> CapturePresetTextProcessingResult {
        XCTFail("Image-only processing must not rewrite text")
        return CapturePresetTextProcessingResult(text: "wrong")
    }
}
