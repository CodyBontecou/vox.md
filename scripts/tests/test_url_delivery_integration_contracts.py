"""Portable host-wiring checks, not substitutes for the Swift runtime tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path: str) -> str:
    return (ROOT / path).read_text()


class URLDeliveryIntegrationContracts(unittest.TestCase):
    def test_ios_http_handoff_is_durable_and_source_cancellable(self):
        recorder = source("Voxboard/PersistentRecorder.swift")
        hook = recorder.split("// Persist the additive HTTP handoff", 1)[1].split("if let captureDestinationID", 1)[0]
        self.assertIn("await URLDeliveryRuntime.coordinator.enqueueTranscript", hook)
        self.assertNotIn("Task.detached", hook)
        self.assertIn("cancellation: urlDeliveryCancellation", hook)
        self.assertIn("urlDeliveryCancellation.valueOfMainActorTask", recorder)

    def test_mac_note_export_does_not_await_network_retries(self):
        recorder = source("Voxboard Mac/MacRecorder.swift")
        hook = recorder.split("// Opt-in additive delivery", 1)[1].split("if let captureDestinationID", 1)[0]
        self.assertIn("enqueueTranscript", hook)
        self.assertNotIn(".deliver(", hook)
        self.assertIn("cancellation: urlDeliveryCancellation", hook)
        self.assertIn("urlDeliveryCancellation.runDetached", recorder)

    def test_composer_prepares_processed_snapshot_before_note_and_dispatches_after(self):
        composer = source("Voxboard App Shared/CaptureComposerViewModel.swift")
        block = composer.split("let cancellation = URLDeliveryCancellation()", 1)[1].split("lastReceipt = receipt", 1)[0]
        self.assertLess(block.index("enqueueCaptureToURLIfConfigured"), block.index("pipeline.capture("))
        self.assertLess(block.index("pipeline.capture("), block.index("dispatchCaptureURLDelivery"))
        self.assertIn("request: request, settings: submittedURLDeliverySettings", block)
        self.assertIn("onCancel: { cancellation.cancel() }", block)

    def test_both_editors_use_same_controls_and_delete_credentials_before_retirement(self):
        for path in ["Voxboard/Views/FlowSettingsView.swift", "Voxboard Mac/MacRootView.swift"]:
            text = source(path)
            self.assertIn("URLDeliverySettingsSection(settings: $flow.exportSettings.urlDelivery)", text)
            deletion = text.split("private func delete(_ flow: CapturePreset)", 1)[1].split("flows.removeAll", 1)[0]
            self.assertLess(deletion.index("deleteCredentials(for:"), deletion.index("CapturePresetStore.retirePreset("))
            self.assertIn("deletionError =", deletion)
        self.assertIn("URLDeliveryRecoveryView", source("Voxboard/Views/MetaSettingsView.swift"))

    def test_constructing_or_refreshing_http_owner_does_not_dispatch(self):
        coordinator = source("Packages/VoxboardShared/Sources/VoxboardShared/URLDeliveryCoordinator.swift")
        initializer = coordinator.split("public init(", 1)[1].split("public func enqueueCapture", 1)[0]
        self.assertNotIn("retryPendingDelivery", initializer)
        self.assertNotIn("sendQueuedDelivery", initializer)
        self.assertIn("refresh() async { receipts = await deliverer.outstandingReceipts() }", initializer)


if __name__ == "__main__":
    unittest.main()
