import AppIntents
import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class RecordingActionTests: XCTestCase {
    func testStartStopAndToggleResolveAgainstCurrentRecordingState() {
        XCTAssertEqual(RecordingAction.start.command(isRecording: false), .start)
        XCTAssertEqual(RecordingAction.start.command(isRecording: true), .none)
        XCTAssertEqual(RecordingAction.stop.command(isRecording: false), .none)
        XCTAssertEqual(RecordingAction.stop.command(isRecording: true), .stop)
        XCTAssertEqual(RecordingAction.toggle.command(isRecording: false), .start)
        XCTAssertEqual(RecordingAction.toggle.command(isRecording: true), .stop)
    }

    func testBackgroundStartUsesRequestedPresetAndRequiresLiveActivity() {
        let recording = RecordingEffects()
        let result = BackgroundRecordingAction.perform(action: .start, flowID: "configured", effects: recording.effects)
        XCTAssertEqual(result, .completed)
        XCTAssertEqual(recording.events, ["start:configured", "activity"])
        XCTAssertTrue(recording.isRecording)
    }

    func testBackgroundToggleStartsWhenIdleAndStopsWhenRecording() {
        let recording = RecordingEffects()
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .toggle, flowID: "preset", effects: recording.effects), .completed)
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .toggle, flowID: "different", effects: recording.effects), .completed)
        XCTAssertEqual(recording.events, ["start:preset", "activity", "stop", "activity"])
        XCTAssertFalse(recording.isRecording)
    }

    func testStartDoesNotRestartOrChangeAnActiveRecording() {
        let recording = RecordingEffects(isRecording: true)
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .start, flowID: "different", effects: recording.effects), .completed)
        XCTAssertEqual(recording.events, ["activity"])
        XCTAssertTrue(recording.isRecording)
    }

    func testStartDoesNotDiscardExistingRecordingWhenStatusCardCannotBeShown() {
        let recording = RecordingEffects(isRecording: true, activityAllowed: false)
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .start, flowID: nil, effects: recording.effects), .openApp(action: .start))
        XCTAssertEqual(recording.events, ["activity"])
        XCTAssertTrue(recording.isRecording)
    }

    func testStopWhileIdleIsANoopWithoutFallbackOrMicrophoneActivation() {
        let recording = RecordingEffects()
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .stop, flowID: nil, effects: recording.effects), .completed)
        XCTAssertTrue(recording.events.isEmpty)
    }

    func testMissingRecorderFallsBackOnlyForStartingActions() {
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .stop, flowID: nil, effects: nil), .completed)
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .start, flowID: nil, effects: nil), .openApp(action: .start))
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .toggle, flowID: nil, effects: nil), .openApp(action: .start))
    }

    func testFailedStartRetriesStartRatherThanToggle() {
        let recording = RecordingEffects(startAllowed: false)
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .toggle, flowID: "preset", effects: recording.effects), .openApp(action: .start))
        XCTAssertEqual(recording.events, ["start:preset", "endActivity"])
        XCTAssertFalse(recording.isRecording)
    }

    func testMissingLiveActivityReleasesNewAudioSessionBeforeForegroundRetry() {
        let recording = RecordingEffects(activityAllowed: false)
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .toggle, flowID: "preset", effects: recording.effects), .openApp(action: .start))
        XCTAssertEqual(recording.events, ["start:preset", "activity", "stopListening", "endActivity"])
        XCTAssertFalse(recording.isRecording)
    }

    func testStopWithMissingLiveActivityReleasesSessionButNeverStartsAgain() {
        let recording = RecordingEffects(isRecording: true, activityAllowed: false)
        XCTAssertEqual(BackgroundRecordingAction.perform(action: .stop, flowID: nil, effects: recording.effects), .completed)
        XCTAssertEqual(recording.events, ["stop", "activity", "stopListening", "endActivity"])
        XCTAssertFalse(recording.isRecording)
    }

    func testForegroundHandoffConsumesActionOnceAndDefaultsLegacyRequestsToStart() throws {
        try withDefaults { defaults in
            XCTAssertEqual(WidgetRecordingActionSelection.consume(defaults: defaults), .start)
            for action in RecordingAction.allCases {
                WidgetRecordingActionSelection.persist(action, defaults: defaults)
                XCTAssertEqual(WidgetRecordingActionSelection.consume(defaults: defaults), action)
                XCTAssertNil(defaults.object(forKey: WidgetRecordingActionSelection.key))
                XCTAssertEqual(WidgetRecordingActionSelection.consume(defaults: defaults), .start)
            }
            defaults.set("unknown", forKey: WidgetRecordingActionSelection.key)
            XCTAssertEqual(WidgetRecordingActionSelection.consume(defaults: defaults), .start)
            XCTAssertNil(defaults.object(forKey: WidgetRecordingActionSelection.key))
        }
    }

    func testPrimaryPreservesLegacyStartAndForegroundDefaults() {
        let recording = OpenVoxboardRecordIntent()
        XCTAssertEqual(recording.recordingAction, .start)
        XCTAssertEqual(recording.delivery, .immediate)
        XCTAssertFalse(recording.attachAudio)
        XCTAssertTrue(OpenVoxboardRecordIntent.openAppWhenRun, "Older iOS retains its foreground launch default")
    }

    func testHiddenControlDispatcherPreservesExplicitPresentationChoices() {
        let recording = VoxboardRecordingControlIntent()
        XCTAssertEqual(recording.recordingAction, .start)
        XCTAssertTrue(recording.openApp)
        for action in RecordingAction.allCases {
            for openApp in [false, true] {
                let configured = VoxboardRecordingControlIntent(vox: nil, action: action, openApp: openApp)
                XCTAssertEqual(configured.recordingAction, action)
                XCTAssertEqual(configured.openApp, openApp)
            }
        }
        XCTAssertFalse(VoxboardRecordingControlIntent.isDiscoverable)
    }

    func testForegroundIntentPreservesStopAndPresetInsteadOfStarting() async throws {
        let defaults = try XCTUnwrap(AppConstants.sharedDefaults)
        let keys = [AppConstants.lockScreenQuickRecordEnabledKey, AppConstants.pendingWidgetRecordKey,
                    AppConstants.pendingWidgetRecordFlowIdKey, WidgetRecordingActionSelection.key,
                    AppConstants.pendingWidgetRecordDraftAttachAudioKey]
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, originals) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
        let preset = VoxEntity.fallback
        let recording = OpenVoxboardRecordIntent(vox: preset, action: .stop)
        let foreground = recording.foregroundIntent
        XCTAssertEqual(foreground.recordingAction, .stop)
        XCTAssertEqual(foreground.vox?.id, preset.id)
        _ = try await foreground.perform()
        XCTAssertTrue(defaults.bool(forKey: AppConstants.pendingWidgetRecordKey))
        XCTAssertEqual(defaults.string(forKey: AppConstants.pendingWidgetRecordFlowIdKey), preset.id)
        XCTAssertEqual(WidgetRecordingActionSelection.consume(defaults: defaults), .stop)

        // A subsequent legacy invocation overwrites any previous operation.
        WidgetRecordingActionSelection.persist(.stop, defaults: defaults)
        _ = try await OpenVoxboardRecordIntent(vox: preset).foregroundIntent.perform()
        XCTAssertEqual(WidgetRecordingActionSelection.consume(defaults: defaults), .start)
    }

    func testConfiguredRecordActionPublishesDraftDeliveryWithoutChangingItsAction() async throws {
        let defaults = try XCTUnwrap(AppConstants.sharedDefaults)
        let keys = [AppConstants.lockScreenQuickRecordEnabledKey, AppConstants.pendingWidgetRecordKey,
                    AppConstants.pendingWidgetRecordFlowIdKey, WidgetRecordingActionSelection.key,
                    AppConstants.pendingWidgetRecordDraftAttachAudioKey,
                    CapturePreferenceKeys.defaultRecordingResultMode]
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, originals) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
        defaults.set(CaptureRecordingMode.preset.rawValue, forKey: CapturePreferenceKeys.defaultRecordingResultMode)
        let preset = VoxEntity.fallback
        let draft = CaptureDraft(text: "Existing draft")
        for action in RecordingAction.allCases {
            for attachAudio in [false, true] {
                let intent = OpenVoxboardRecordIntent(vox: preset, action: action, delivery: .draft, attachAudio: attachAudio)
                _ = try await intent.foregroundIntent.perform()
                let request = PendingQuickRecordingRequest.consume(defaults: defaults)
                XCTAssertEqual(request.recordingAction, action)
                XCTAssertEqual(request.requestedFlowID, preset.id)
                XCTAssertEqual(request.completionMode(flowID: preset.id), .captureDraft(attachAudio: attachAudio))
                XCTAssertEqual(request.draftRequestID(in: draft), draft.requestID)
                XCTAssertEqual(defaults.string(forKey: CapturePreferenceKeys.defaultRecordingResultMode), CaptureRecordingMode.preset.rawValue)
            }
        }
        // Audio retention is a draft option; immediate delivery must clear the
        // last draft override even if a saved action retains Attach Audio=true.
        _ = try await OpenVoxboardRecordIntent(vox: preset, delivery: .immediate, attachAudio: true).foregroundIntent.perform()
        let immediate = PendingQuickRecordingRequest.consume(defaults: defaults)
        XCTAssertEqual(immediate.completionMode(flowID: preset.id), .runVox(flowID: preset.id))
        XCTAssertNil(immediate.draftRequestID(in: draft))

        defaults.set(false, forKey: AppConstants.pendingWidgetRecordKey)
        defaults.set(false, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
        _ = try await OpenVoxboardRecordIntent(vox: preset, delivery: .draft).foregroundIntent.perform()
        XCTAssertFalse(defaults.bool(forKey: AppConstants.pendingWidgetRecordKey))
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "RecordingActionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

@MainActor
private final class RecordingEffects {
    var isRecording: Bool
    let startAllowed: Bool
    let activityAllowed: Bool
    var events: [String] = []

    init(isRecording: Bool = false, startAllowed: Bool = true, activityAllowed: Bool = true) {
        self.isRecording = isRecording
        self.startAllowed = startAllowed
        self.activityAllowed = activityAllowed
    }

    var effects: BackgroundRecordingAction.Effects {
        BackgroundRecordingAction.Effects(
            isRecording: { self.isRecording },
            start: { flowID in
                self.events.append("start:\(flowID ?? "selected")")
                self.isRecording = self.startAllowed
                return self.startAllowed
            },
            stop: {
                self.events.append("stop")
                self.isRecording = false
            },
            stopListening: {
                self.events.append("stopListening")
                self.isRecording = false
            },
            ensureLiveActivity: {
                self.events.append("activity")
                return self.activityAllowed
            },
            endShortcutActivity: { self.events.append("endActivity") }
        )
    }
}
