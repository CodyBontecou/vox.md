"""Source registration guard; runtime delivery is covered by app-hosted tests."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


class DraftRecordingActionRegistrationTests(unittest.TestCase):
    def test_draft_action_is_separate_from_legacy_immediate_action(self):
        provider = (ROOT / "Voxboard/VoxboardShortcutsProvider.swift").read_text()
        self.assertIn("intent: OpenVoxboardRecordIntent()", provider)
        self.assertIn("intent: RecordToDraftIntent()", provider)
        self.assertIn('shortTitle: "Record to Draft"', provider)

    def test_draft_control_is_additive_and_configurable(self):
        bundle = (ROOT / "Voxboard Widget/VoxboardWidgetBundle.swift").read_text()
        control = (ROOT / "Voxboard Widget/VoxboardDraftRecordingControl.swift").read_text()
        project = (ROOT / "Voxboard.xcodeproj/project.pbxproj").read_text()
        self.assertIn("VoxboardRecordControl()", bundle)
        self.assertIn("VoxboardDraftRecordingControl()", bundle)
        self.assertIn("RecordToDraftIntent(vox: state.vox)", control)
        self.assertIn("promptsForUserConfiguration()", control)
        self.assertIn("AppConstants.lockScreenQuickRecordEnabled", control)
        self.assertIn("RecordToDraftIntent.swift,", project)
        self.assertIn("PendingQuickRecordingRequest.swift,", project)

    def test_foreground_draft_intent_preserves_quick_record_safety_gate(self):
        intent = (ROOT / "Voxboard/RecordToDraftIntent.swift").read_text()
        self.assertIn("static var openAppWhenRun: Bool = true", intent)
        self.assertIn(".foreground(.immediate)", intent)
        self.assertIn("guard AppConstants.lockScreenQuickRecordEnabled", intent)
        self.assertIn("draftAttachAudio: attachAudio", intent)
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
