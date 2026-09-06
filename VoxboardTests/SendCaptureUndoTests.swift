import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class SendCaptureUndoTests: XCTestCase {
    private func makeAsset(filename: String) throws -> CaptureAssetReference {
        try CaptureAssetReference(
            relativePath: "staging/\(filename)",
            originalFilename: filename,
            contentTypeIdentifier: "public.jpeg"
        )
    }

    private func makeViewModel(rootURL: URL) -> QuickCaptureViewModel {
        QuickCaptureViewModel(captureRootURL: rootURL)
    }

    private func makeTemporaryRoot() throws -> URL {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SendCaptureUndoTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: rootURL) }
        return rootURL
    }

    func test_preferenceKeyIsStableAndDefaultsOff() throws {
        XCTAssertEqual(
            CapturePreferenceKeys.confirmPresetSend,
            "capture.voice.confirmPresetSend.v1"
        )
        let suiteName = "SendCaptureUndoTests-\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock { suite.removePersistentDomain(forName: suiteName) }
        XCTAssertFalse(suite.bool(forKey: CapturePreferenceKeys.confirmPresetSend))
    }

    func test_snapshotKeepsValuePayloadsAndCountsEverythingSent() throws {
        let imageAsset = try makeAsset(filename: "photo.jpg")
        var draft = CaptureDraft()
        draft.text = "Sent note text"
        draft.additionalPayloads = [
            .text("inline text"),
            .url(URL(string: "https://example.com")!, title: "Example"),
            .image(imageAsset, altText: "A photo"),
        ]

        let snapshot = SentCaptureUndo.snapshot(draft: draft, presetDisplayName: "Journal")

        XCTAssertEqual(snapshot.requestID, draft.requestID)
        XCTAssertEqual(snapshot.text, "Sent note text")
        XCTAssertEqual(snapshot.presetDisplayName, "Journal")
        XCTAssertEqual(snapshot.sentAttachmentCount, 3)
        XCTAssertEqual(snapshot.restorablePayloads, [
            .text("inline text"),
            .url(URL(string: "https://example.com")!, title: "Example"),
        ])
        XCTAssertTrue(snapshot.offersUndo)
    }

    func test_snapshotOfEmptyDraftOffersNoUndo() {
        let snapshot = SentCaptureUndo.snapshot(draft: CaptureDraft(), presetDisplayName: "Journal")
        XCTAssertFalse(snapshot.offersUndo)
    }

    func test_applyRestoresTextAndValuePayloadsIntoFreshDraft() async throws {
        let rootURL = try makeTemporaryRoot()
        let viewModel = makeViewModel(rootURL: rootURL)
        await viewModel.load()

        let snapshot = SentCaptureUndoSnapshot(
            requestID: UUID(),
            text: "Restored note",
            restorablePayloads: [.text("inline text")],
            sentAttachmentCount: 1,
            presetDisplayName: "Journal"
        )

        let didRestore = await SentCaptureUndo.apply(snapshot, to: viewModel)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(viewModel.draft.text, "Restored note")
        XCTAssertEqual(viewModel.draft.additionalPayloads, [.text("inline text")])

        let store = CaptureDraftStore(rootDirectoryURL: rootURL)
        let persisted = try await store.load(id: viewModel.draft.id)
        XCTAssertEqual(persisted?.text, "Restored note")
        XCTAssertEqual(persisted?.additionalPayloads, [.text("inline text")])
    }

    func test_applyAppendsWithoutDiscardingPostSendEdits() async throws {
        let rootURL = try makeTemporaryRoot()
        let viewModel = makeViewModel(rootURL: rootURL)
        await viewModel.load()
        viewModel.draft.text = "Typed after sending"

        let snapshot = SentCaptureUndoSnapshot(
            requestID: UUID(),
            text: "Restored note",
            restorablePayloads: [],
            sentAttachmentCount: 0,
            presetDisplayName: "Journal"
        )

        let didRestore = await SentCaptureUndo.apply(snapshot, to: viewModel)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(viewModel.draft.text, "Typed after sending\n\nRestored note")
    }

    func test_applyRefusesSnapshotWithoutRestorableContent() async throws {
        let rootURL = try makeTemporaryRoot()
        let viewModel = makeViewModel(rootURL: rootURL)
        await viewModel.load()

        let snapshot = SentCaptureUndoSnapshot(
            requestID: UUID(),
            text: "   \n",
            restorablePayloads: [],
            sentAttachmentCount: 2,
            presetDisplayName: "Journal"
        )

        let didRestore = await SentCaptureUndo.apply(snapshot, to: viewModel)

        XCTAssertFalse(didRestore)
        XCTAssertTrue(viewModel.draft.text.isEmpty)
    }

    func test_restorablePayloadClassification() throws {
        let asset = try makeAsset(filename: "clip.m4a")
        XCTAssertTrue(CapturePayload.text("hi").isRestorableAfterSend)
        XCTAssertTrue(CapturePayload.url(URL(string: "https://example.com")!, title: nil).isRestorableAfterSend)
        XCTAssertFalse(CapturePayload.audio(asset, transcript: nil).isRestorableAfterSend)
        XCTAssertFalse(CapturePayload.retainedAudio(asset, embedPlacement: .none).isRestorableAfterSend)
        XCTAssertFalse(CapturePayload.image(asset, altText: nil).isRestorableAfterSend)
        XCTAssertFalse(CapturePayload.file(asset).isRestorableAfterSend)
        XCTAssertFalse(CapturePayload.scannedDocument(pages: [asset], pdf: nil, extractedText: nil).isRestorableAfterSend)
        XCTAssertFalse(CapturePayload.sketch(drawing: asset, preview: asset, altText: nil).isRestorableAfterSend)
    }
}
