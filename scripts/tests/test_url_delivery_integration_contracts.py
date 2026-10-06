"""Portable host-wiring checks, not substitutes for the Swift runtime tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def source(path: str) -> str:
    return (ROOT / path).read_text()


class URLDeliveryIntegrationContracts(unittest.TestCase):
    def test_ios_http_handoff_is_durable_and_source_cancellable(self):
        recorder = source("Voxboard/PersistentRecorder.swift")
        hook = recorder.split("// Persist the HTTP-only handoff", 1)[1].split("if let captureDestinationID", 1)[0]
        self.assertIn("await URLDeliveryRuntime.coordinator.enqueueTranscript", hook)
        self.assertNotIn("Task.detached", hook)
        self.assertIn("cancellation: urlDeliveryCancellation", hook)
        self.assertIn("return .delivered", hook)
        self.assertIn("urlDeliveryCancellation.valueOfMainActorTask", recorder)

    def test_mac_note_export_does_not_await_network_retries(self):
        recorder = source("Voxboard Mac/MacRecorder.swift")
        hook = recorder.split("// HTTP is an alternative to directory delivery", 1)[1].split("if let captureDestinationID", 1)[0]
        self.assertIn("enqueueTranscript", hook)
        self.assertNotIn(".deliver(", hook)
        self.assertIn("cancellation: urlDeliveryCancellation", hook)
        self.assertIn("return true", hook)
        self.assertIn("urlDeliveryCancellation.runDetached", recorder)

    def test_composer_http_branch_returns_before_directory_lookup_or_pipeline(self):
        composer = source("Voxboard App Shared/CaptureComposerViewModel.swift")
        block = composer.split("if sendsToHTTP, let settings", 1)[1].split("let library = try await libraryStore.load()", 1)[0]
        self.assertIn("enqueueHTTPCapture(request: request, settings: settings)", block)
        self.assertIn("dispatchCaptureURLDelivery", block)
        self.assertIn("return .http(requestID: request.id)", block)
        self.assertNotIn("pipeline.capture(", block)
        self.assertNotIn("resolveRootURL", block)
        self.assertIn("onCancel: { cancellation.cancel() }", block)

    def test_watch_http_handoff_precedes_directory_resolution(self):
        pipeline = source("Voxboard/WatchRecordingPipeline.swift")
        block = pipeline.split("if flow.deliveryTarget == .http", 1)[1].split("guard let captureRootURL", 1)[0]
        self.assertIn("urlDeliveryCoordinator.enqueueTranscript", block)
        self.assertIn("urlDeliveryCoordinator.dispatch", block)
        self.assertIn("onCancel: { cancellation.cancel() }", block)
        self.assertIn("return", block)
        self.assertNotIn("ConfiguredTranscriptCaptureDestinationExporter", block)

    def test_share_extension_does_not_route_http_to_remembered_directory(self):
        share = source("Voxboard Share Extension/ShareViewController.swift")
        submit = share.split("func submit() async", 1)[1].split("func retryUnavailableLocation", 1)[0]
        self.assertLess(submit.index("guard !usesHTTPDestination"), submit.index("CaptureInbox("))
        resolver = share.split("private func resolvedDestinationID", 1)[1].split("private func openQueuedCapture", 1)[0]
        self.assertIn("deliveryTarget == .http", resolver)
        self.assertLess(resolver.index("return nil"), resolver.index("CapturePresetRouteResolver"))

    def test_both_editors_use_same_controls_and_delete_credentials_before_retirement(self):
        for path in ["Voxboard/Views/FlowSettingsView.swift", "Voxboard Mac/MacRootView.swift"]:
            text = source(path)
            self.assertIn("CapturePresetTargetSection(flow: $flow)", text)
            self.assertIn("flow.deliveryTarget == .http", text)
            self.assertIn("URLDeliverySettingsSection(settings: $flow.exportSettings.urlDelivery)", text)
            deletion = text.split("private func delete(_ flow: CapturePreset)", 1)[1].split("flows.removeAll", 1)[0]
            self.assertLess(deletion.index("deleteCredentials(forID:"), deletion.index("CapturePresetStore.retirePreset("))
            self.assertIn("deletionError =", deletion)
        self.assertIn("URLDeliveryRecoveryView", source("Voxboard/Views/MetaSettingsView.swift"))

    def test_missing_endpoint_warning_opens_the_same_editor_on_both_hosts(self):
        for path in ["Voxboard/Views/QuickCaptureView.swift", "Voxboard Mac/MacCaptureWorkspaceView.swift"]:
            text = source(path)
            self.assertIn('accessibilityIdentifier("capture_http_endpoint_settings")', text)
            self.assertIn("viewModel.httpEndpointSettingsPresetID", text)
            self.assertIn("message == viewModel.httpDestinationIssue", text)
            self.assertIn("CaptureHTTPEndpointSettingsView(presetID: route.presetID)", text)
        editor = source("Voxboard App Shared/CaptureHTTPEndpointSettingsView.swift")
        self.assertIn("URLDeliverySettingsSection(settings: $model.settings, focusEndpointOnAppear: true)", editor)
        self.assertNotIn("Keychain.save", editor)

    def test_constructing_or_refreshing_http_owner_does_not_dispatch(self):
        coordinator = source("Packages/VoxboardShared/Sources/VoxboardShared/URLDeliveryCoordinator.swift")
        initializer = coordinator.split("public init(", 1)[1].split("public func enqueueCapture", 1)[0]
        self.assertNotIn("retryPendingDelivery", initializer)
        self.assertNotIn("sendQueuedDelivery", initializer)
        self.assertIn("refresh() async { receipts = await deliverer.outstandingReceipts() }", initializer)


if __name__ == "__main__":
    unittest.main()
