import XCTest
@testable import Voxboard
import VoxboardShared

/// Issue #164: audio recorded from the note screen (capture composer) is named
/// with the delivering Route's Audio Filename Template, rendered by the same
/// `CapturePresetAudioFilename` the exporters use.
@MainActor
final class CaptureComposerAudioFilenameTemplateTests: XCTestCase {
    func test_timestampTemplateNamesStagedRecording() async throws {
        let fixture = try await makeFixture(template: "{timestamp}")
        let asset = try await stage(in: fixture, deliveryID: UUID())

        XCTAssertNotNil(
            asset.relativePath.range(
                of: #"^\d{4}-\d{2}-\d{2}-\d{6}\.m4a$"#,
                options: .regularExpression
            ),
            asset.relativePath
        )
        XCTAssertEqual(asset.originalFilename, asset.relativePath)
    }

    func test_emptyTemplateKeepsLegacyRecordingName() async throws {
        let fixture = try await makeFixture(template: "")
        let deliveryID = UUID()
        let asset = try await stage(in: fixture, deliveryID: deliveryID)

        XCTAssertEqual(asset.relativePath, "Recording-\(deliveryID.uuidString.lowercased()).m4a")
    }

    func test_whitespaceTemplateKeepsLegacyRecordingName() async throws {
        let fixture = try await makeFixture(template: "   ")
        let deliveryID = UUID()
        let asset = try await stage(in: fixture, deliveryID: deliveryID)

        XCTAssertEqual(asset.relativePath, "Recording-\(deliveryID.uuidString.lowercased()).m4a")
    }

    func test_tokensRenderLikeExporters() async throws {
        let template = "{preset}_{id}_{id8}_{original}"
        let fixture = try await makeFixture(template: template)
        let deliveryID = UUID()
        let sourceURL = try fixture.makeAudio(named: "take one.m4a")
        let staged = await fixture.model.stageRecordedAudio(at: sourceURL, deliveryID: deliveryID)
        let asset = try XCTUnwrap(staged, fixture.model.errorMessage ?? "staging failed")

        let expected = try XCTUnwrap(CapturePresetAudioFilename.preferredFilename(
            template: template,
            context: CapturePresetAudioFilenameContext(
                identifier: deliveryID.uuidString,
                createdAt: Date(),
                presetName: "Synthetic Notes",
                originalFilename: "take one.m4a"
            ),
            sourceExtension: "m4a"
        ))
        XCTAssertEqual(asset.relativePath, expected)
        XCTAssertTrue(asset.relativePath.hasPrefix("Synthetic-Notes_\(deliveryID.uuidString.lowercased())_"))
    }

    func test_sameRenderedNameDoesNotOverwriteAndNoteLinksSavedFile() async throws {
        let fixture = try await makeFixture(template: "{preset}")

        let firstAsset = try await stage(in: fixture, deliveryID: UUID(), bytes: 1)
        XCTAssertEqual(firstAsset.relativePath, "Synthetic-Notes.m4a")
        fixture.model.draft.text = "First capture"
        await fixture.model.submit()
        let firstReceipt = try XCTUnwrap(fixture.model.lastReceipt, fixture.model.errorMessage ?? "first send failed")

        fixture.model.draft.voxID = fixture.presetID
        _ = try await stage(in: fixture, deliveryID: UUID(), bytes: 2)
        fixture.model.draft.text = "Second capture"
        await fixture.model.submit()
        let secondReceipt = try XCTUnwrap(fixture.model.lastReceipt, fixture.model.errorMessage ?? "second send failed")

        let firstAudio = try XCTUnwrap(firstReceipt.attachmentURLs.first)
        let secondAudio = try XCTUnwrap(secondReceipt.attachmentURLs.first)
        XCTAssertEqual(firstAudio.lastPathComponent, "Synthetic-Notes.m4a")
        XCTAssertNotEqual(firstAudio.standardizedFileURL, secondAudio.standardizedFileURL)
        XCTAssertTrue(secondAudio.lastPathComponent.hasPrefix("Synthetic-Notes"))
        XCTAssertEqual(try Data(contentsOf: firstAudio), Data(repeating: 1, count: 512))
        XCTAssertEqual(try Data(contentsOf: secondAudio), Data(repeating: 2, count: 512))

        let firstNote = try String(contentsOf: firstReceipt.noteURL, encoding: .utf8)
        let secondNote = try String(contentsOf: secondReceipt.noteURL, encoding: .utf8)
        XCTAssertTrue(firstNote.contains(firstAudio.lastPathComponent), firstNote)
        XCTAssertTrue(secondNote.contains(secondAudio.lastPathComponent), secondNote)
    }

    // MARK: - Fixture

    private struct Fixture {
        let model: QuickCaptureViewModel
        let root: URL
        let presetID: String

        func makeAudio(named name: String = "source.m4a", bytes: UInt8 = 4) throws -> URL {
            let folder = root.appendingPathComponent("sources-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try Data(repeating: bytes, count: 512).write(to: url, options: .atomic)
            return url
        }
    }

    private func stage(
        in fixture: Fixture,
        deliveryID: UUID,
        bytes: UInt8 = 4
    ) async throws -> CaptureAssetReference {
        let sourceURL = try fixture.makeAudio(bytes: bytes)
        let staged = await fixture.model.stageRecordedAudio(at: sourceURL, deliveryID: deliveryID)
        return try XCTUnwrap(staged, fixture.model.errorMessage ?? "staging failed")
    }

    private func makeFixture(template: String) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ComposerAudioFilename-\(UUID().uuidString)")
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let destination = CaptureDestination(
            name: "Synthetic", rootBookmark: try vault.bookmarkData(), rootName: "Synthetic Vault",
            noteTarget: .newNote(pathTemplate: "{date}.md")
        )
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let suite = "ComposerAudioFilename-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        var preset = CapturePresetStore.makeCustomFlow()
        preset.name = "Synthetic Notes"
        preset.captureDestinationID = destination.id
        preset.postProcessingMode = .none
        preset.audioFilenameTemplate = template
        CapturePresetStore.saveFlows([preset], defaults: defaults, widgetRefresh: .disabled)
        let model = QuickCaptureViewModel(
            captureRootURL: root, defaults: defaults, pipeline: CapturePipeline(),
            hasPaidCaptureAccess: { true }
        )
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        await model.load()
        model.draft.voxID = preset.id
        return Fixture(model: model, root: root, presetID: preset.id)
    }
}
