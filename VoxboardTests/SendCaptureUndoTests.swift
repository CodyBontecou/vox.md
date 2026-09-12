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

    func test_audioOnlySnapshotSurvivesDeliveryCleanupAndRestoresEditableAudio() async throws {
        let rootURL = try makeTemporaryRoot()
        let viewModel = makeViewModel(rootURL: rootURL)
        await viewModel.load()
        let sourceURL = rootURL.appendingPathComponent("source-recording.m4a")
        let audioData = Data("audio undo fixture".utf8)
        try audioData.write(to: sourceURL)
        let stagedAsset = await viewModel.stageVoiceRecording(
            at: sourceURL,
            transcript: "Spoken transcript"
        )
        let asset = try XCTUnwrap(stagedAsset)
        let sentDraftID = viewModel.draft.id

        let snapshot = SentCaptureUndo.snapshot(
            draft: viewModel.draft,
            presetDisplayName: "Journal",
            stagingDirectoryURL: viewModel.sentCaptureUndoSourceDirectoryURL,
            audioCacheRootURL: viewModel.sentCaptureUndoCacheRootURL
        )

        XCTAssertTrue(snapshot.offersUndo)
        XCTAssertTrue(snapshot.restorablePayloads.isEmpty)
        XCTAssertEqual(snapshot.cachedAudioPayloads.count, 1)
        let cacheDirectoryURL = try XCTUnwrap(snapshot.audioCacheDirectoryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDirectoryURL.path))

        let store = CaptureDraftStore(rootDirectoryURL: rootURL)
        try await store.complete(draftID: sentDraftID)
        let sentAssetURL = rootURL
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(sentDraftID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(asset.relativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sentAssetURL.path))
        viewModel.draft = CaptureDraft()

        let didRestore = await SentCaptureUndo.apply(snapshot, to: viewModel)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(viewModel.draft.additionalPayloads.count, 1)
        guard case .audio(let restoredAsset, let transcript) = viewModel.draft.additionalPayloads[0] else {
            return XCTFail("Expected restored audio payload")
        }
        XCTAssertEqual(transcript, "Spoken transcript")
        let restoredURL = rootURL
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(viewModel.draft.id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(restoredAsset.relativePath)
        XCTAssertEqual(try Data(contentsOf: restoredURL), audioData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectoryURL.path))

        let persisted = try await store.load(id: viewModel.draft.id)
        XCTAssertEqual(persisted?.additionalPayloads, viewModel.draft.additionalPayloads)
    }

    func test_immediateRecordingSnapshotRestoresTranscriptAndAudioAfterSourceRemoval() async throws {
        let rootURL = try makeTemporaryRoot()
        let queueDirectoryURL = rootURL.appendingPathComponent("queue", isDirectory: true)
        try FileManager.default.createDirectory(at: queueDirectoryURL, withIntermediateDirectories: true)
        let sourceURL = queueDirectoryURL.appendingPathComponent("recording.wav")
        let audioData = Data("immediate audio undo fixture".utf8)
        try audioData.write(to: sourceURL)
        let snapshot = SentCaptureUndo.snapshot(
            requestID: UUID(),
            text: "Immediate transcript",
            recordedAudioURL: sourceURL,
            originalFilename: "Voice note.wav",
            presetDisplayName: "Journal",
            audioCacheRootURL: SentCaptureUndo.audioCacheRootURL(captureRootURL: rootURL)
        )
        let cacheDirectoryURL = try XCTUnwrap(snapshot.audioCacheDirectoryURL)
        try FileManager.default.removeItem(at: sourceURL)

        let viewModel = makeViewModel(rootURL: rootURL)
        await viewModel.load()
        let didRestore = await SentCaptureUndo.apply(snapshot, to: viewModel)

        XCTAssertTrue(didRestore)
        XCTAssertEqual(viewModel.draft.text, "Immediate transcript")
        let restoredPayload = try XCTUnwrap(viewModel.draft.additionalPayloads.first)
        guard case .audio(let restoredAsset, nil) = restoredPayload else {
            return XCTFail("Expected immediate recording audio")
        }
        XCTAssertEqual(restoredAsset.originalFilename, "Voice note.wav")
        let restoredURL = rootURL
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(viewModel.draft.id.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent(restoredAsset.relativePath)
        XCTAssertEqual(try Data(contentsOf: restoredURL), audioData)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectoryURL.path))
    }

    func test_discardCachedAudioRemovesExpiredSnapshotFiles() throws {
        let rootURL = try makeTemporaryRoot()
        let sourceURL = rootURL.appendingPathComponent("recording.m4a")
        try Data("audio".utf8).write(to: sourceURL)
        let snapshot = SentCaptureUndo.snapshot(
            requestID: UUID(),
            text: "",
            recordedAudioURL: sourceURL,
            presetDisplayName: "Journal",
            audioCacheRootURL: SentCaptureUndo.audioCacheRootURL(captureRootURL: rootURL)
        )
        let cacheDirectoryURL = try XCTUnwrap(snapshot.audioCacheDirectoryURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: cacheDirectoryURL.path))

        snapshot.discardCachedAudio()

        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectoryURL.path))
    }

    func test_missingAudioCannotCreateAudioOnlyUndoSnapshot() throws {
        let rootURL = try makeTemporaryRoot()
        let sourceDirectoryURL = rootURL.appendingPathComponent("staging", isDirectory: true)
        let asset = try CaptureAssetReference(
            relativePath: "missing.m4a",
            originalFilename: "missing.m4a",
            contentTypeIdentifier: "public.mpeg-4-audio"
        )
        let draft = CaptureDraft(additionalPayloads: [.audio(asset, transcript: nil)])

        let snapshot = SentCaptureUndo.snapshot(
            draft: draft,
            presetDisplayName: "Journal",
            stagingDirectoryURL: sourceDirectoryURL,
            audioCacheRootURL: SentCaptureUndo.audioCacheRootURL(captureRootURL: rootURL)
        )

        XCTAssertFalse(snapshot.offersUndo)
        XCTAssertTrue(snapshot.cachedAudioPayloads.isEmpty)
        XCTAssertNil(snapshot.audioCacheDirectoryURL)
    }

    func test_failedAudioRestoreRollsBackDraftAndStagedFiles() async throws {
        let rootURL = try makeTemporaryRoot()
        let sourceURL = rootURL.appendingPathComponent("recording.m4a")
        try Data("audio".utf8).write(to: sourceURL)
        let snapshot = SentCaptureUndo.snapshot(
            requestID: UUID(),
            text: "Restored transcript",
            recordedAudioURL: sourceURL,
            presetDisplayName: "Journal",
            audioCacheRootURL: SentCaptureUndo.audioCacheRootURL(captureRootURL: rootURL)
        )
        let cacheDirectoryURL = try XCTUnwrap(snapshot.audioCacheDirectoryURL)
        try FileManager.default.removeItem(at: cacheDirectoryURL.appendingPathComponent("audio-1.m4a"))
        let viewModel = makeViewModel(rootURL: rootURL)
        await viewModel.load()
        viewModel.draft.text = "Keep me"
        let originalDraft = viewModel.draft

        let didRestore = await SentCaptureUndo.apply(snapshot, to: viewModel)

        XCTAssertFalse(didRestore)
        XCTAssertEqual(viewModel.draft, originalDraft)
        let stagingURL = rootURL
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(viewModel.draft.id.uuidString.lowercased(), isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectoryURL.path))
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
