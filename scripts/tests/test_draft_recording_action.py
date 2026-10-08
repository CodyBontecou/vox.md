"""Source registration guard; runtime delivery is covered by app-hosted tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DraftRecordingActionRegistrationTests(unittest.TestCase):
    def test_running_app_observes_published_recording_requests(self):
        app = (ROOT / "Voxboard/VoxboardApp.swift").read_text()
        self.assertIn("for: PendingQuickRecordingRequest.didPersistNotification", app)
        observer = app.split("for: PendingQuickRecordingRequest.didPersistNotification", 1)[1]
        self.assertIn("consumePendingWidgetRecordIfNeeded()", observer.split(".onOpenURL", 1)[0])

    def test_record_audio_is_the_only_recording_shortcut(self):
        provider = (ROOT / "Voxboard/VoxboardShortcutsProvider.swift").read_text()
        self.assertIn("intent: OpenVoxboardRecordIntent()", provider)
        self.assertNotIn("RecordToDraftIntent", provider)
        self.assertNotIn('shortTitle: "Record to Draft"', provider)
        self.assertFalse((ROOT / "Voxboard/RecordToDraftIntent.swift").exists())

    def test_existing_record_control_owns_draft_configuration(self):
        bundle = (ROOT / "Voxboard Widget/VoxboardWidgetBundle.swift").read_text()
        control = (ROOT / "Voxboard Widget/VoxboardRecordControl.swift").read_text()
        provider = (ROOT / "Voxboard/VoxboardRecordingControlProvider.swift").read_text()
        project = (ROOT / "Voxboard.xcodeproj/project.pbxproj").read_text()
        self.assertIn("VoxboardRecordControl()", bundle)
        self.assertNotIn("VoxboardDraftRecordingControl", bundle)
        self.assertFalse((ROOT / "Voxboard Widget/VoxboardDraftRecordingControl.swift").exists())
        self.assertIn("ControlWidgetButton(action: state.action)", control)
        self.assertIn("delivery: delivery, attachAudio: attachAudio", provider)
        self.assertIn("promptsForUserConfiguration()", control)
        self.assertIn("AppConstants.lockScreenQuickRecordEnabled", provider)
        self.assertNotIn("RecordToDraftIntent.swift", project)
        self.assertIn("PendingQuickRecordingRequest.swift,", project)

    def test_foreground_draft_intent_preserves_quick_record_safety_gate(self):
        intent = (ROOT / "Voxboard/OpenVoxboardRecordingActionIntent.swift").read_text()
        self.assertIn("static var openAppWhenRun: Bool = true", intent)
        self.assertIn(".foreground(.immediate)", intent)
        self.assertIn("guard AppConstants.lockScreenQuickRecordEnabled", intent)
        self.assertIn("draftAttachAudio: delivery == .draft ? attachAudio : nil", intent)
        self.assertNotIn("ToggleVoxboardRecordingIntent", intent)

    def test_pending_launch_starts_recorder_without_switching_or_sending_draft(self):
        view = (ROOT / "Voxboard/Views/QuickCaptureView.swift").read_text()
        start = view.index("    private func consumePendingWidgetRecordIfNeeded()")
        end = view.index("    private func handleRecorderNeedsUnlock", start)
        handler = view[start:end]
        self.assertIn("PendingQuickRecordingRequest.consume()", handler)
        self.assertIn("await viewModel.load()", handler)
        self.assertIn("viewModel.requireCaptureRouteAvailable()", handler)
        self.assertIn("persistentRecorder.startOneShotInAppSegment(", handler)
        self.assertIn("completionMode: request.completionMode(flowID: selection.flowID)", handler)
        self.assertIn("draftRequestID: request.draftRequestID(in: viewModel.draft)", handler)
        self.assertIn("origin: .quickRecord", handler)
        self.assertNotIn("selectFlow(", handler)
        self.assertNotIn("submit(", handler)
        self.assertNotIn("externallyRequestedVoiceRecordingMode", handler)

    def test_draft_event_sink_has_no_delivery_api(self):
        sink = (ROOT / "Voxboard/QuickRecordingDraftRouting.swift").read_text()
        self.assertIn("stageRecordedAudio", sink)
        self.assertIn("appendRecordedTranscript", sink)
        self.assertNotIn(".submit(", sink)
        self.assertNotIn("TranscriptFileExporter", sink)
        self.assertNotIn("TranscriptURLDeliverer", sink)


if __name__ == "__main__":
    unittest.main()
