import VoxboardShared
import XCTest
@testable import Voxboard

final class RecordingCompletionModeTests: XCTestCase {
    func testCompletionModesResolveDistinctAutoStopOrigins() {
        XCTAssertEqual(
            RecordingCompletionMode.keyboardTranscription.defaultCommandOrigin,
            .keyboardExtension
        )
        XCTAssertEqual(
            RecordingCompletionMode.captureDraft(attachAudio: false).defaultCommandOrigin,
            .inAppDraft
        )
        XCTAssertEqual(
            RecordingCompletionMode.runVox(flowID: "general").defaultCommandOrigin,
            .inAppImmediate
        )
    }

    func testOnlyImmutablePresetDeliveryPermitsSelectingTheNextPresetWhileProcessing() {
        XCTAssertTrue(
            RecordingCompletionMode.captureDraft(attachAudio: false)
                .blocksCapturePresetSelectionDuringProcessing
        )
        XCTAssertTrue(
            RecordingCompletionMode.captureDraft(attachAudio: true)
                .blocksCapturePresetSelectionDuringProcessing
        )
        XCTAssertFalse(
            RecordingCompletionMode.runVox(flowID: "journal")
                .blocksCapturePresetSelectionDuringProcessing
        )
        XCTAssertTrue(
            RecordingCompletionMode.keyboardTranscription
                .blocksCapturePresetSelectionDuringProcessing
        )
    }

    func testExternalCapturePathOverridesInAppCompletionOrigin() {
        let completionMode = RecordingCompletionMode.runVox(flowID: "general")

        XCTAssertEqual(completionMode.commandOrigin(overriding: .quickRecord), .quickRecord)
        XCTAssertEqual(completionMode.commandOrigin(overriding: .watch), .watch)
    }

    func testOnlyVisibleInAppRecordingsPreviewLiveTextInComposer() {
        XCTAssertTrue(
            RecordingCompletionMode.captureDraft(attachAudio: false)
                .previewsLiveTranscriptInComposer(commandOrigin: .inAppDraft)
        )
        XCTAssertTrue(
            RecordingCompletionMode.runVox(flowID: "general")
                .previewsLiveTranscriptInComposer(commandOrigin: .inAppImmediate)
        )
        for origin in [
            RecordingCommand.Origin.keyboardExtension,
            .quickRecord,
            .liveActivity,
            .watch,
        ] {
            XCTAssertFalse(
                RecordingCompletionMode.runVox(flowID: "general")
                    .previewsLiveTranscriptInComposer(commandOrigin: origin)
            )
        }
        XCTAssertFalse(
            RecordingCompletionMode.keyboardTranscription
                .previewsLiveTranscriptInComposer(commandOrigin: .keyboardExtension)
        )
    }

    func testKeyboardCommandRunsItsExplicitPreset() {
        let command = RecordingCommand(
            requestId: "keyboard",
            action: .startSegment,
            flowId: "custom",
            origin: .keyboardExtension
        )

        XCTAssertEqual(
            RecordingCompletionMode.completionMode(
                forExternalCommand: command,
                fallbackFlowID: "general"
            ),
            .runVox(flowID: "custom")
        )
    }

    func testKeyboardCommandWithoutPresetIsTranscriptionOnly() {
        let command = RecordingCommand(
            requestId: "keyboard",
            action: .startSegment,
            origin: .keyboardExtension
        )

        XCTAssertEqual(
            RecordingCompletionMode.completionMode(
                forExternalCommand: command,
                fallbackFlowID: "general"
            ),
            .keyboardTranscription
        )
    }

    func testLegacyKeyboardCommandWithoutOriginIsTranscriptionOnly() {
        let command = RecordingCommand(
            requestId: "legacy-keyboard",
            action: .startSegment,
            flowId: "custom"
        )

        XCTAssertEqual(
            RecordingCompletionMode.completionMode(
                forExternalCommand: command,
                fallbackFlowID: "general"
            ),
            .keyboardTranscription
        )
    }

    func testPresetSnapshotRemainsImmutableWhenLivePresetChanges() {
        let original = CapturePreset(
            id: "custom",
            name: "Original",
            symbolName: "location",
            locationPolicy: CapturePresetLocationPolicy(isEnabled: true, precision: .exact)
        )
        var live = original
        let snapshot = RecordingCompletionMode.presetSnapshot(
            for: .runVox(flowID: original.id),
            lookup: { $0 == live.id ? live : nil },
            fallback: { live }
        )

        live.name = "Edited Later"
        live.locationPolicy.precision = .city

        XCTAssertEqual(snapshot, original)
        XCTAssertEqual(snapshot?.locationPolicy.precision, .exact)
        XCTAssertEqual(snapshot?.name, "Original")
        XCTAssertNil(RecordingCompletionMode.presetSnapshot(
            for: .captureDraft(attachAudio: false),
            lookup: { _ in live },
            fallback: { live }
        ))

        let draftVoicePolicy = RecordingCompletionMode.voiceProcessingConfiguration(
            for: .captureDraft(attachAudio: false),
            selectedPreset: original
        )
        live.speakerDiarizationEnabled = true
        XCTAssertEqual(
            draftVoicePolicy,
            RecordingVoiceProcessingConfiguration(
                presetID: "custom",
                speakerDiarizationEnabled: false
            )
        )
        XCTAssertNil(RecordingCompletionMode.voiceProcessingConfiguration(
            for: .keyboardTranscription,
            selectedPreset: original
        ))
    }

    func testSegmentHandoffSnapshotPreservesDraftSessionAndPresetIdentity() {
        let draftID = UUID()
        let sessionID = UUID()
        let preset = CapturePreset(id: "snapshot", name: "Snapshot", symbolName: "mic")

        let snapshot = PersistentRecorder.handoffSnapshot(
            draftRequestID: draftID,
            liveSessionID: sessionID,
            presetSnapshot: preset,
            voiceProcessingConfiguration: RecordingVoiceProcessingConfiguration(
                presetID: preset.id,
                speakerDiarizationEnabled: true
            )
        )

        XCTAssertEqual(snapshot.draftRequestID, draftID)
        XCTAssertEqual(snapshot.liveSessionID, sessionID)
        XCTAssertEqual(snapshot.presetSnapshot, preset)
        XCTAssertEqual(snapshot.voiceProcessingConfiguration?.presetID, preset.id)
        XCTAssertEqual(snapshot.voiceProcessingConfiguration?.speakerDiarizationEnabled, true)
    }

    func testNonKeyboardExternalCommandStillRunsItsPreset() {
        let command = RecordingCommand(
            requestId: "live-activity",
            action: .startSegment,
            flowId: "custom",
            origin: .liveActivity
        )

        XCTAssertEqual(
            RecordingCompletionMode.completionMode(
                forExternalCommand: command,
                fallbackFlowID: "general"
            ),
            .runVox(flowID: "custom")
        )
    }

    // MARK: - Persisted recording result mode (`capture.voice.defaultResult.v1`)

    func testAbsentPersistedResultModeDefaultsToDraft() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // Key absent (fresh installs and pre-2.8 upgrades) → "Add to Draft".
        XCTAssertEqual(
            QuickCaptureView.externallyRequestedVoiceRecordingMode(defaults: defaults),
            .draft
        )
        XCTAssertEqual(
            QuickCaptureView.completionMode(for: .draft, attachAudio: false, flowID: "general"),
            .captureDraft(attachAudio: false)
        )
    }

    func testPersistedSendImmediatelyModeFlowsIntoCompletionMode() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            CaptureRecordingMode.preset.rawValue,
            forKey: CapturePreferenceKeys.defaultRecordingResultMode
        )

        // The Shortcuts "Record a Capture" path must honor a persisted
        // "Send Immediately" choice instead of forcing the draft flow.
        let mode = QuickCaptureView.externallyRequestedVoiceRecordingMode(defaults: defaults)
        XCTAssertEqual(mode, .preset)
        XCTAssertEqual(
            QuickCaptureView.completionMode(for: mode, attachAudio: false, flowID: "general"),
            .runVox(flowID: "general")
        )
    }

    func testPersistedDraftModeFlowsIntoCompletionModeWithAttachAudio() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            CaptureRecordingMode.draft.rawValue,
            forKey: CapturePreferenceKeys.defaultRecordingResultMode
        )

        let mode = QuickCaptureView.externallyRequestedVoiceRecordingMode(defaults: defaults)
        XCTAssertEqual(mode, .draft)
        XCTAssertEqual(
            QuickCaptureView.completionMode(for: mode, attachAudio: true, flowID: "general"),
            .captureDraft(attachAudio: true)
        )
    }

    func testInvalidPersistedResultModeFallsBackToDraft() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            "unknown-mode",
            forKey: CapturePreferenceKeys.defaultRecordingResultMode
        )

        XCTAssertEqual(
            QuickCaptureView.externallyRequestedVoiceRecordingMode(defaults: defaults),
            .draft
        )
    }

    func testPersistedResultModeRoundTripsThroughRawValue() {
        // The persisted payload is the enum's String raw value, so values
        // written by the details-bar picker resolve back to the same mode.
        for mode in CaptureRecordingMode.allCases {
            XCTAssertEqual(CaptureRecordingMode(persistedRawValue: mode.rawValue), mode)
        }
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "test.recording-completion-mode.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: suiteName)), suiteName)
    }
}

final class DraftRecordingAudioDefaultTests: XCTestCase {
    func testDraftRecordingKeepsAudioWhenPresetSavesIt() {
        XCTAssertTrue(QuickCaptureView.draftRecordingAttachesAudio(
            presetAudioSaveMode: .alongsideTranscript, override: nil))
        XCTAssertTrue(QuickCaptureView.draftRecordingAttachesAudio(
            presetAudioSaveMode: .attachmentsFolder, override: nil))
        XCTAssertFalse(QuickCaptureView.draftRecordingAttachesAudio(
            presetAudioSaveMode: .off, override: nil))
    }

    func testAudioSwitchOverridesThePreset() {
        XCTAssertFalse(QuickCaptureView.draftRecordingAttachesAudio(
            presetAudioSaveMode: .alongsideTranscript, override: false))
        XCTAssertTrue(QuickCaptureView.draftRecordingAttachesAudio(
            presetAudioSaveMode: .off, override: true))
    }
}

/// Route switch "Transcribe Recordings" (#163): only route deliveries skip
/// speech-to-text; dictation modes always produce text.
final class RouteTranscriptionSwitchTests: XCTestCase {
    private func preset(transcribing: Bool) -> CapturePreset {
        var preset = CapturePreset(id: "field-audio", name: "Field Audio", symbolName: "waveform")
        preset.transcriptionEnabled = transcribing
        return preset
    }

    func test_routeWithTranscriptionOffSkipsTranscription() {
        XCTAssertFalse(PersistentRecorder.segmentTranscribes(
            completionMode: .runVox(flowID: "field-audio"),
            presetSnapshot: preset(transcribing: false)
        ))
    }

    func test_routeWithTranscriptionOnTranscribes() {
        XCTAssertTrue(PersistentRecorder.segmentTranscribes(
            completionMode: .runVox(flowID: "field-audio"),
            presetSnapshot: preset(transcribing: true)
        ))
    }

    func test_dictationModesAlwaysTranscribe() {
        for mode: RecordingCompletionMode in [.keyboardTranscription, .captureDraft(attachAudio: false)] {
            XCTAssertTrue(PersistentRecorder.segmentTranscribes(
                completionMode: mode,
                presetSnapshot: preset(transcribing: false),
                draftRoute: preset(transcribing: false)
            ), "\(mode)")
        }
    }

    func test_draftWithAttachedAudioFollowsRouteSwitch() {
        XCTAssertFalse(PersistentRecorder.segmentTranscribes(
            completionMode: .captureDraft(attachAudio: true),
            presetSnapshot: nil,
            draftRoute: preset(transcribing: false)
        ))
        XCTAssertTrue(PersistentRecorder.segmentTranscribes(
            completionMode: .captureDraft(attachAudio: true),
            presetSnapshot: nil,
            draftRoute: preset(transcribing: true)
        ))
        XCTAssertTrue(PersistentRecorder.segmentTranscribes(
            completionMode: .captureDraft(attachAudio: true),
            presetSnapshot: nil,
            draftRoute: nil
        ))
    }

    func test_draftKeepsAudioWhenRouteTranscriptionIsOff() {
        XCTAssertTrue(QuickCaptureView.draftRecordingAttachesAudio(
            presetAudioSaveMode: .off, presetTranscribes: false, override: nil))
        XCTAssertFalse(QuickCaptureView.draftRecordingAttachesAudio(
            presetAudioSaveMode: .off, presetTranscribes: true, override: nil))
        // An explicit per-take choice still wins.
        XCTAssertFalse(QuickCaptureView.draftRecordingAttachesAudio(
            presetAudioSaveMode: .off, presetTranscribes: false, override: false))
    }

    func test_audioOnlyResultIsEmpty() {
        XCTAssertEqual(PersistentRecorder.audioOnlyResult(modelId: "m", language: "en").text, "")
    }

    func test_missingSnapshotOrModeTranscribes() {
        XCTAssertTrue(PersistentRecorder.segmentTranscribes(completionMode: .runVox(flowID: "x"), presetSnapshot: nil))
        XCTAssertTrue(PersistentRecorder.segmentTranscribes(completionMode: nil, presetSnapshot: preset(transcribing: false)))
    }
}
