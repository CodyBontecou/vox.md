import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class RecordingDraftDeliveryTests: XCTestCase {
    func testAudioDeliveryReceiptSuppressesDuplicateAfterRelaunch() async throws {
        let fixture = try RecordingDraftFixture()
        defer { fixture.cleanup() }
        let deliveryID = UUID()
        let sourceURL = try fixture.makeAudio()
        let firstViewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL)
        await firstViewModel.load()

        let stagedAsset = await firstViewModel.stageRecordedAudio(
            at: sourceURL,
            deliveryID: deliveryID
        )
        let firstAsset = try XCTUnwrap(stagedAsset)
        try FileManager.default.removeItem(at: sourceURL)

        let relaunchedViewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL)
        await relaunchedViewModel.load()
        let repeatedAsset = await relaunchedViewModel.stageRecordedAudio(
            at: sourceURL,
            deliveryID: deliveryID
        )

        XCTAssertEqual(repeatedAsset, firstAsset)
        XCTAssertEqual(relaunchedViewModel.draft.additionalPayloads.count, 1)
        XCTAssertEqual(
            relaunchedViewModel.draft.stagedRecordingAudioReceipts?[
                deliveryID.uuidString.lowercased()
            ],
            firstAsset
        )
        let stagedFiles = try FileManager.default.contentsOfDirectory(
            at: fixture.stagingDirectory(for: relaunchedViewModel.draft),
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(stagedFiles.count, 1)
    }

    func testStagedRecordingUsesTheRouteAudioFilenameTemplate() async throws {
        let fixture = try RecordingDraftFixture()
        defer { fixture.cleanup() }
        let suiteName = "RecordingDraftDeliveryTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let routes = CapturePresetStore.loadFlows(defaults: defaults).map { route in
            var route = route
            route.audioFilenameTemplate = "take-{id8}"
            return route
        }
        CapturePresetStore.saveFlows(routes, defaults: defaults, widgetRefresh: .disabled)
        let deliveryID = try XCTUnwrap(UUID(uuidString: "ABCDEF12-3456-7890-ABCD-EF1234567890"))
        let viewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL, defaults: defaults)
        await viewModel.load()

        let staged = await viewModel.stageRecordedAudio(
            at: try fixture.makeAudio(),
            deliveryID: deliveryID
        )

        XCTAssertEqual(try XCTUnwrap(staged).originalFilename, "take-abcdef12.wav")
        // A second take with the same rendered name gets the stager's
        // collision suffix instead of replacing the first.
        let second = await viewModel.stageRecordedAudio(
            at: try fixture.makeAudio(),
            deliveryID: try XCTUnwrap(UUID(uuidString: "ABCDEF12-0000-0000-0000-000000000000"))
        )
        XCTAssertNotEqual(try XCTUnwrap(second).originalFilename, "take-abcdef12.wav")
    }

    func testRecordedAudioFilenameFallsBackWithoutATemplate() throws {
        let deliveryID = UUID()
        let route = CapturePreset(id: "plain", name: "Plain", symbolName: "mic")

        XCTAssertEqual(
            QuickCaptureViewModel.recordedAudioFilename(
                route: route,
                deliveryID: deliveryID,
                sourceFilename: "kept.m4a",
                sourceExtension: "m4a"
            ),
            "Recording-\(deliveryID.uuidString.lowercased()).m4a"
        )
        XCTAssertEqual(
            QuickCaptureViewModel.recordedAudioFilename(
                route: nil,
                deliveryID: deliveryID,
                sourceFilename: "kept.m4a",
                sourceExtension: "m4a"
            ),
            "Recording-\(deliveryID.uuidString.lowercased()).m4a"
        )
    }

    func testMissingReceiptAssetCannotReportFalseDeliverySuccess() async throws {
        let fixture = try RecordingDraftFixture()
        defer { fixture.cleanup() }
        let deliveryID = UUID()
        let sourceURL = try fixture.makeAudio()
        let firstViewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL)
        await firstViewModel.load()

        let stagedAsset = await firstViewModel.stageRecordedAudio(
            at: sourceURL,
            deliveryID: deliveryID
        )
        let asset = try XCTUnwrap(stagedAsset)
        try FileManager.default.removeItem(
            at: fixture.stagingDirectory(for: firstViewModel.draft)
                .appendingPathComponent(asset.relativePath)
        )
        try FileManager.default.removeItem(at: sourceURL)

        let relaunchedViewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL)
        await relaunchedViewModel.load()
        let repeatedAsset = await relaunchedViewModel.stageRecordedAudio(
            at: sourceURL,
            deliveryID: deliveryID
        )

        XCTAssertNil(repeatedAsset)
        XCTAssertNotNil(relaunchedViewModel.errorMessage)
    }

    func testMissingReceiptAssetIsReplacedWithoutDuplicatePayload() async throws {
        let fixture = try RecordingDraftFixture()
        defer { fixture.cleanup() }
        let deliveryID = UUID()
        let sourceURL = try fixture.makeAudio()
        let firstViewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL)
        await firstViewModel.load()

        let firstAssetValue = await firstViewModel.stageRecordedAudio(
            at: sourceURL,
            deliveryID: deliveryID
        )
        let firstAsset = try XCTUnwrap(firstAssetValue)
        try FileManager.default.removeItem(
            at: fixture.stagingDirectory(for: firstViewModel.draft)
                .appendingPathComponent(firstAsset.relativePath)
        )

        let relaunchedViewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL)
        await relaunchedViewModel.load()
        let replacement = await relaunchedViewModel.stageRecordedAudio(
            at: sourceURL,
            deliveryID: deliveryID
        )

        let replacementAsset = try XCTUnwrap(replacement)
        XCTAssertEqual(relaunchedViewModel.draft.additionalPayloads.count, 1)
        XCTAssertEqual(
            relaunchedViewModel.draft.stagedRecordingAudioReceipts?[
                deliveryID.uuidString.lowercased()
            ],
            replacementAsset
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.stagingDirectory(for: relaunchedViewModel.draft)
                    .appendingPathComponent(replacementAsset.relativePath).path
            )
        )
    }

    func testTranscriptDeliveryReceiptSuppressesDuplicateAfterRelaunch() async throws {
        let fixture = try RecordingDraftFixture()
        defer { fixture.cleanup() }
        let deliveryID = UUID()
        let firstViewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL)
        await firstViewModel.load()

        let firstDelivery = await firstViewModel.appendRecordedTranscript(
            "Original transcript",
            deliveryID: deliveryID
        )
        XCTAssertTrue(firstDelivery)

        let relaunchedViewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL)
        await relaunchedViewModel.load()
        let repeatedDelivery = await relaunchedViewModel.appendRecordedTranscript(
            "Duplicate transcript",
            deliveryID: deliveryID
        )
        XCTAssertTrue(repeatedDelivery)

        XCTAssertEqual(relaunchedViewModel.draft.text, "Original transcript")
        XCTAssertEqual(relaunchedViewModel.draft.appliedRecordingTranscriptIDs, [deliveryID])
    }

    func testOlderJobCannotCommitOverNewerLivePreview() async throws {
        let fixture = try RecordingDraftFixture()
        defer { fixture.cleanup() }
        let viewModel = QuickCaptureViewModel(captureRootURL: fixture.rootURL)
        await viewModel.load()
        let newerSessionID = UUID()
        let olderSessionID = UUID()
        let olderDeliveryID = UUID()

        await viewModel.updateLiveRecordedTranscript(
            sessionID: newerSessionID,
            finalizedText: "New recording preview",
            volatileText: nil
        )
        let delivered = await viewModel.appendRecordedTranscript(
            "Older completed transcript",
            sessionID: olderSessionID,
            deliveryID: olderDeliveryID
        )

        XCTAssertFalse(delivered)
        XCTAssertEqual(viewModel.draft.text, "New recording preview")
        XCTAssertFalse(
            viewModel.draft.appliedRecordingTranscriptIDs?.contains(olderDeliveryID) == true
        )
    }
}

private struct RecordingDraftFixture {
    let rootURL: URL

    init() throws {
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecordingDraftDeliveryTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func makeAudio() throws -> URL {
        let url = rootURL.appendingPathComponent("source-\(UUID().uuidString).wav")
        try Data(repeating: 4, count: 512).write(to: url, options: .atomic)
        return url
    }

    func stagingDirectory(for draft: CaptureDraft) -> URL {
        rootURL
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(draft.id.uuidString.lowercased(), isDirectory: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}
