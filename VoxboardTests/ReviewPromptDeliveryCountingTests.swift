import Foundation
import Testing
import VoxboardShared
@testable import Voxboard

/// Review prompt counting at the composer: an in-app Send that reached its
/// destination marks a success the user saw (`lastSentReceipt`); Share Sheet,
/// widget and Shortcut captures delivered from the inbox only count.
@MainActor
struct ReviewPromptDeliveryCountingTests {
    @Test func inAppSendCountsAndMarksAVisibleSuccessWhileInboxDeliveriesOnlyCount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ReviewPromptDeliveryCounting-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reviewPrompts = ReviewPromptManager(defaults: defaults)
        let model = QuickCaptureViewModel(
            captureRootURL: root,
            defaults: defaults,
            pipeline: CapturePipeline(),
            hasPaidCaptureAccess: { true },
            reviewPrompts: reviewPrompts
        )
        await model.load()
        try await model.setUpFirstNoteFolder(folder)
        let destinationID = try #require(model.selectedDestination?.id)

        // In-app Send.
        model.draft.text = "Sent from the composer"
        await model.submit()
        let sent = try #require(model.lastSentReceipt)
        #expect(model.lastReceipt == sent)
        #expect(reviewPrompts.state.deliveredCaptureCount == 1)

        // Share Sheet capture opened through its deep link.
        let inbox = CaptureInbox(rootDirectoryURL: root)
        let shared = CaptureRequest(
            source: .shareExtension,
            destinationID: destinationID,
            payloads: [.text("Shared from Safari")]
        )
        try await inbox.enqueue(shared)
        await model.handleDeepLink(.processInboxRequest(shared.id))
        #expect(model.lastReceipt?.requestID == shared.id)
        #expect(model.lastSentReceipt == sent)
        #expect(reviewPrompts.state.deliveredCaptureCount == 2)

        // Widget capture drained when the app comes to the foreground.
        let widget = CaptureRequest(
            source: .widget,
            destinationID: destinationID,
            payloads: [.text("From the widget")]
        )
        try await inbox.enqueue(widget)
        await model.processPendingInbox()
        #expect(model.lastSentReceipt == sent)
        #expect(reviewPrompts.state.deliveredCaptureCount == 3)

        // Counting alone never asked.
        #expect(reviewPrompts.state.lastRequestedAt == nil)
    }

    @Test func failedSendDoesNotCount() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "ReviewPromptDeliveryCounting-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let reviewPrompts = ReviewPromptManager(defaults: defaults)
        let model = QuickCaptureViewModel(
            captureRootURL: root,
            defaults: defaults,
            pipeline: CapturePipeline(),
            hasPaidCaptureAccess: { true },
            reviewPrompts: reviewPrompts
        )
        await model.load()
        // No destination is set up, so Send cannot deliver.
        model.draft.text = "Nowhere to go"
        await model.submit()
        #expect(model.lastSentReceipt == nil)
        #expect(reviewPrompts.state.deliveredCaptureCount == 0)
    }
}
