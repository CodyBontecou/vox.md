import AppIntents
import Combine
import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class DraftRecordingActionTests: XCTestCase {
    func testPublishedRequestWakesAnAlreadyActiveConsumerWithoutAnotherActivation() throws {
        let defaults = try makeDefaults()
        let notificationCenter = NotificationCenter()
        var receivedRequests: [PendingQuickRecordingRequest] = []
        let subscription = notificationCenter.publisher(
            for: PendingQuickRecordingRequest.didPersistNotification
        ).sink { _ in
            guard defaults.bool(forKey: AppConstants.pendingWidgetRecordKey) else { return }
            defaults.set(false, forKey: AppConstants.pendingWidgetRecordKey)
            receivedRequests.append(PendingQuickRecordingRequest.consume(defaults: defaults))
        }
        defer { subscription.cancel() }

        let request = PendingQuickRecordingRequest(requestedFlowID: "journal", draftAttachAudio: true)
        request.persist(defaults: defaults, notificationCenter: notificationCenter)
        // A redundant wake-up must not replay the consumed request.
        notificationCenter.post(name: PendingQuickRecordingRequest.didPersistNotification, object: nil)

        XCTAssertEqual(receivedRequests, [request], "An active consumer must wake after the complete request is published")
        XCTAssertFalse(defaults.bool(forKey: AppConstants.pendingWidgetRecordKey), "A later activation must not replay the request")
        XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordFlowIdKey))
        XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey))
    }

    func testDraftPolicySurvivesLaunchEvenWhenDefaultIsSendImmediately() throws {
        let defaults = try makeDefaults()
        defaults.set(CaptureRecordingMode.preset.rawValue, forKey: CapturePreferenceKeys.defaultRecordingResultMode)
        PendingQuickRecordingRequest(requestedFlowID: "journal", draftAttachAudio: false)
            .persist(defaults: defaults)

        XCTAssertTrue(defaults.bool(forKey: AppConstants.pendingWidgetRecordKey))
        let request = PendingQuickRecordingRequest.consume(defaults: defaults)
        XCTAssertEqual(request.requestedFlowID, "journal")
        XCTAssertEqual(request.completionMode(flowID: "journal"), .captureDraft(attachAudio: false))
        XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey))
        XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordFlowIdKey))
        let draft = CaptureDraft(text: "Keep this draft")
        XCTAssertEqual(request.draftRequestID(in: draft), draft.requestID)
    }

    func testOptionalAudioAttachmentAndLegacyImmediatePolicyStayDistinct() throws {
        let defaults = try makeDefaults()
        PendingQuickRecordingRequest(requestedFlowID: "journal", draftAttachAudio: true)
            .persist(defaults: defaults)
        let draftRequest = PendingQuickRecordingRequest.consume(defaults: defaults)
        XCTAssertEqual(draftRequest.completionMode(flowID: "journal"), .captureDraft(attachAudio: true))

        PendingQuickRecordingRequest(requestedFlowID: "journal", draftAttachAudio: nil)
            .persist(defaults: defaults)
        let legacyRequest = PendingQuickRecordingRequest.consume(defaults: defaults)
        XCTAssertEqual(legacyRequest.completionMode(flowID: "journal"), .runVox(flowID: "journal"))
        XCTAssertNil(legacyRequest.draftRequestID(in: CaptureDraft()))
    }

    func testDraftStartReplacesStaleStopOrToggleWithoutStoppingAnActiveCapture() throws {
        let defaults = try makeDefaults()
        for staleAction in [RecordingAction.stop, .toggle] {
            WidgetRecordingActionSelection.persist(staleAction, defaults: defaults)
            PendingQuickRecordingRequest(requestedFlowID: "journal", draftAttachAudio: false)
                .persist(defaults: defaults, notificationCenter: NotificationCenter())
            let request = PendingQuickRecordingRequest.consume(defaults: defaults)
            XCTAssertEqual(request.recordingAction, .start)
            XCTAssertEqual(request.recordingAction.command(isRecording: false), .start)
            XCTAssertEqual(request.recordingAction.command(isRecording: true), .none)
            XCTAssertEqual(request.completionMode(flowID: "journal"), .captureDraft(attachAudio: false))
            XCTAssertNil(defaults.object(forKey: WidgetRecordingActionSelection.key))
        }
    }

    func testImmediateHandoffClearsDraftPolicyAndPreservesEachConfiguredAction() throws {
        let defaults = try makeDefaults()
        for action in RecordingAction.allCases {
            PendingQuickRecordingRequest(requestedFlowID: "draft", draftAttachAudio: true)
                .persist(defaults: defaults, notificationCenter: NotificationCenter())
            PendingQuickRecordingRequest(requestedFlowID: "immediate", draftAttachAudio: nil, recordingAction: action)
                .persist(defaults: defaults, notificationCenter: NotificationCenter())
            let request = PendingQuickRecordingRequest.consume(defaults: defaults)
            XCTAssertEqual(request.recordingAction, action)
            XCTAssertEqual(request.completionMode(flowID: "immediate"), .runVox(flowID: "immediate"))
            XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey))
        }
    }

    func testMalformedDraftOverrideCannotFallBackToImmediateDelivery() throws {
        let defaults = try makeDefaults()
        defaults.set("invalid-attachment-policy", forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey)
        let request = PendingQuickRecordingRequest.consume(defaults: defaults)
        XCTAssertEqual(request.completionMode(flowID: "journal"), .captureDraft(attachAudio: false))
    }

    func testDraftActionUsesRequestedEnabledPresetForVoicePolicyOnly() throws {
        let defaults = try makeDefaults()
        let (selected, requested) = makePresets()
        CapturePresetStore.saveFlows([selected, requested], defaults: defaults)
        CapturePresetStore.selectFlow(id: selected.id, defaults: defaults)
        let selection = WidgetRecordingFlowSelection.resolve(requestedFlowID: requested.id, defaults: defaults)
        let request = PendingQuickRecordingRequest(requestedFlowID: requested.id, draftAttachAudio: false)
        let mode = request.completionMode(flowID: selection.flowID)
        let configuration = RecordingCompletionMode.voiceProcessingConfiguration(
            for: mode,
            selectedPreset: selection.explicitlyRequestedFlow
        )

        XCTAssertEqual(selection.flowID, "requested-voice")
        XCTAssertEqual(configuration?.presetID, "requested-voice")
        XCTAssertEqual(configuration?.speakerDiarizationEnabled, true)
        XCTAssertEqual(mode.recordingJobDelivery, .captureDraft(attachAudio: false))
        XCTAssertNil(mode.flowID, "Draft processing must not acquire a preset export destination")
        XCTAssertEqual(CapturePresetStore.selectedFlowId(defaults: defaults), "selected-draft")
    }

    func testDisabledAndStalePresetFallbackStillCompletesIntoDraft() throws {
        let defaults = try makeDefaults()
        let (selected, enabledRequested) = makePresets()
        var requested = enabledRequested
        requested.isEnabled = false
        CapturePresetStore.saveFlows([selected, requested], defaults: defaults)
        CapturePresetStore.selectFlow(id: selected.id, defaults: defaults)
        for requestedID in [requested.id, "deleted-preset", "", nil] as [String?] {
            let request = PendingQuickRecordingRequest(requestedFlowID: requestedID, draftAttachAudio: true)
            let selection = WidgetRecordingFlowSelection.resolve(requestedFlowID: request.requestedFlowID, defaults: defaults)
            XCTAssertEqual(selection.flowID, selected.id)
            XCTAssertNil(selection.explicitlyRequestedFlow)
            XCTAssertEqual(request.completionMode(flowID: selection.flowID), .captureDraft(attachAudio: true))
        }
    }

    func testLegacyWidgetURLClearsDraftOverride() throws {
        let defaults = try makeDefaults()
        PendingQuickRecordingRequest(requestedFlowID: "draft-preset", draftAttachAudio: true)
            .persist(defaults: defaults)
        WidgetRecordingFlowSelection.persistRequestedFlowID(
            from: try XCTUnwrap(URL(string: "voxboard://widget-record?flowId=legacy")),
            defaults: defaults
        )
        let request = PendingQuickRecordingRequest.consume(defaults: defaults)
        XCTAssertEqual(request.requestedFlowID, "legacy")
        XCTAssertEqual(request.completionMode(flowID: "legacy"), .runVox(flowID: "legacy"))
    }

    func testConfiguredIntentSchedulesAutomaticDraftStartAndDefaultIntentRemainsImmediate() async throws {
        let defaults = try XCTUnwrap(AppConstants.sharedDefaults)
        let keys = [AppConstants.lockScreenQuickRecordEnabledKey, AppConstants.pendingWidgetRecordKey,
                    AppConstants.pendingWidgetRecordFlowIdKey, AppConstants.pendingWidgetRecordDraftAttachAudioKey,
                    WidgetRecordingActionSelection.key]
        let originals = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, originals) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
        _ = try await OpenVoxboardRecordIntent(vox: nil, delivery: .draft, attachAudio: true).foregroundIntent.perform()
        XCTAssertTrue(defaults.bool(forKey: AppConstants.pendingWidgetRecordKey))
        XCTAssertEqual(defaults.object(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey) as? Bool, true)
        XCTAssertTrue(OpenVoxboardRecordingActionIntent.openAppWhenRun)
        XCTAssertEqual(WidgetRecordingActionSelection.consume(defaults: defaults), .start)

        _ = try await OpenVoxboardRecordIntent().foregroundIntent.perform()
        XCTAssertTrue(defaults.bool(forKey: AppConstants.pendingWidgetRecordKey))
        XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey))

        defaults.set(false, forKey: AppConstants.pendingWidgetRecordKey)
        defaults.set(false, forKey: AppConstants.lockScreenQuickRecordEnabledKey)
        _ = try await OpenVoxboardRecordIntent(vox: nil, delivery: .draft).foregroundIntent.perform()
        XCTAssertFalse(defaults.bool(forKey: AppConstants.pendingWidgetRecordKey))
        XCTAssertNil(defaults.object(forKey: AppConstants.pendingWidgetRecordDraftAttachAudioKey))
    }

    func testStopHandoffRecoveryAndRetryRetainDraftAndImmutableVoicePolicy() async throws {
        let root = try makeRoot()
        let audioURL = root.appendingPathComponent("recording_draft.wav")
        try AudioFileConverter.writeWAV(samples: Array(repeating: 0.01, count: 16_000), to: audioURL)
        let request = PendingQuickRecordingRequest(requestedFlowID: "requested-voice", draftAttachAudio: true)
        let draft = CaptureDraft(text: "Already here")
        var preset = makePresets().requested
        let mode = request.completionMode(flowID: preset.id)
        let voicePolicy = RecordingCompletionMode.voiceProcessingConfiguration(for: mode, selectedPreset: preset)
        let snapshot = PersistentRecorder.handoffSnapshot(
            draftRequestID: request.draftRequestID(in: draft),
            liveSessionID: UUID(),
            presetSnapshot: nil,
            voiceProcessingConfiguration: voicePolicy
        )
        let handoff = RecordingJobHandoffIntent(
            audioFilename: audioURL.lastPathComponent,
            requestID: "draft-stop-request",
            draftRequestID: snapshot.draftRequestID,
            liveSessionID: snapshot.liveSessionID,
            captureSource: .shortcut,
            duration: 1,
            source: .iOSApp,
            delivery: mode.recordingJobDelivery,
            voiceProcessingConfiguration: snapshot.voiceProcessingConfiguration,
            modelID: "automatic",
            language: "en",
            configuration: RecordingQueueConfiguration(processingPolicy: .manual)
        )
        preset.speakerDiarizationEnabled = false
        preset.name = "Changed after start"
        try RecordingJobHandoffIntentStore(recordingsDirectoryURL: root).save(handoff)
        let store = RecordingJobStore(rootDirectoryURL: root.appendingPathComponent("jobs"))
        let recovered = try await store.recoverExternalOrphans(recordingsDirectoryURL: root, olderThan: .distantFuture)
        let job = try XCTUnwrap(recovered.first)
        XCTAssertEqual(job.delivery, .captureDraft(attachAudio: true))
        XCTAssertEqual(job.draftRequestID, draft.requestID)
        XCTAssertEqual(job.requestID, "draft-stop-request")
        XCTAssertEqual(job.effectiveVoiceProcessingConfiguration?.speakerDiarizationEnabled, true)
        XCTAssertEqual(job.effectiveVoiceProcessingConfiguration?.presetID, "requested-voice")
        XCTAssertEqual(RecordingCompletionMode(jobDelivery: job.delivery), .captureDraft(attachAudio: true))

        _ = try await store.claim(id: job.id)
        _ = try await store.markFailed(id: job.id, stage: .delivery, message: "Synthetic failure")
        let retried = try await store.retry(id: job.id)
        XCTAssertEqual(retried.delivery, .captureDraft(attachAudio: true))
        XCTAssertEqual(retried.draftRequestID, draft.requestID)
        XCTAssertEqual(retried.effectiveVoiceProcessingConfiguration, voicePolicy)
    }

    func testColdLaunchDraftEventsPreserveContentsAttachmentsAndRequestIdentity() async throws {
        let fixture = try await makeDraftFixture()
        let model = fixture.model
        let draft = fixture.draft
        let deliveryID = UUID()
        let transcriptAccepted = await CaptureDraftRecordingEventDelivery.deliver(
            .transcript("Review this", draftRequestID: draft.requestID, liveSessionID: nil, deliveryID: deliveryID),
            to: model
        )
        XCTAssertTrue(transcriptAccepted, "The durable draft must be loaded before checking its identity")
        let audioAccepted = await CaptureDraftRecordingEventDelivery.deliver(
            .audio(fixture.audioURL, draftRequestID: draft.requestID, deliveryID: deliveryID), to: model
        )
        XCTAssertTrue(audioAccepted)
        XCTAssertEqual(model.draft.id, draft.id)
        XCTAssertEqual(model.draft.requestID, draft.requestID)
        XCTAssertEqual(model.draft.voxID, draft.voxID)
        XCTAssertEqual(model.draft.destinationID, draft.destinationID)
        XCTAssertEqual(model.draft.text, "Existing draft\n\nReview this")
        XCTAssertEqual(model.draft.additionalPayloads.first, draft.additionalPayloads.first)
        XCTAssertEqual(model.draft.additionalPayloads.count, 2)
        XCTAssertNil(model.lastReceipt)
        XCTAssertTrue(model.historyRecords.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.vault.path), [])

        let relaunched = QuickCaptureViewModel(captureRootURL: fixture.root, defaults: fixture.defaults, pipeline: CapturePipeline())
        let repeated = await CaptureDraftRecordingEventDelivery.deliver(
            .transcript("Must not duplicate", draftRequestID: draft.requestID, liveSessionID: nil, deliveryID: deliveryID),
            to: relaunched
        )
        XCTAssertTrue(repeated)
        XCTAssertEqual(relaunched.draft.text, "Existing draft\n\nReview this")
        XCTAssertEqual(relaunched.draft.additionalPayloads, model.draft.additionalPayloads)
    }

    func testEventsForAnotherDraftAreRejectedRatherThanSentElsewhere() async throws {
        let fixture = try await makeDraftFixture()
        let mismatchedID = UUID()
        let transcriptAccepted = await CaptureDraftRecordingEventDelivery.deliver(
            .transcript("Wrong target", draftRequestID: mismatchedID, liveSessionID: nil, deliveryID: UUID()), to: fixture.model
        )
        let audioAccepted = await CaptureDraftRecordingEventDelivery.deliver(
            .audio(fixture.audioURL, draftRequestID: mismatchedID, deliveryID: UUID()), to: fixture.model
        )
        XCTAssertFalse(transcriptAccepted)
        XCTAssertFalse(audioAccepted)
        XCTAssertEqual(fixture.model.draft.text, "Existing draft")
        XCTAssertEqual(fixture.model.draft.additionalPayloads, fixture.draft.additionalPayloads)
        XCTAssertEqual(fixture.model.draft.requestID, fixture.draft.requestID)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.vault.path), [])
    }

    func testActualRecorderQueueAddsToDraftWithoutNoteExport() async throws {
        let fixture = try await makeDraftFixture()
        await fixture.model.load()
        let jobStore = RecordingJobStore(rootDirectoryURL: fixture.root.appendingPathComponent("jobs"))
        let transcriptStore = TranscriptStore()
        let originalRecorder = PersistentRecorder.active
        let usage = UsageTracker(defaults: fixture.defaults)
        let recorder = PersistentRecorder(
            transcriptStore: transcriptStore,
            usageTracker: usage,
            transcriptionService: OnDeviceTranscriptionService(
                systemBackend: DraftActionSyntheticSpeechBackend(), usesDownloadedLocalFallbacks: false
            ),
            captureDraftEventHandler: { event in
                await CaptureDraftRecordingEventDelivery.deliver(event, to: fixture.model)
            },
            recordingJobStore: jobStore
        )
        let jobID = UUID()
        defer {
            transcriptStore.delete(ids: [jobID])
            PersistentRecorder.active = originalRecorder
        }
        let request = PendingQuickRecordingRequest(requestedFlowID: "requested-voice", draftAttachAudio: true)
        let mode = request.completionMode(flowID: "requested-voice")
        _ = try await recorder.recordingQueue.enqueue(
            // Match the real startInAppSegment request identity, which keeps
            // app-owned results off the legacy keyboard IPC response channel.
            sourceURL: fixture.audioURL, id: jobID, requestID: "inapp-synthetic-draft-recording",
            draftRequestID: request.draftRequestID(in: fixture.model.draft), captureSource: .shortcut,
            duration: 1, source: .iOSApp, delivery: mode.recordingJobDelivery,
            voiceProcessingConfiguration: RecordingVoiceProcessingConfiguration(presetID: "requested-voice", speakerDiarizationEnabled: false),
            modelID: "automatic", fallbackModelID: nil, language: "en",
            configuration: RecordingQueueConfiguration(sourceAudioRetention: .permanent, processingPolicy: .immediate)
        )
        let deadline = Date().addingTimeInterval(10)
        var completed: RecordingJob?
        while Date() < deadline {
            // Observe a live worker; do not run crash recovery on its claim.
            completed = try await jobStore.load(recoverInterrupted: false).first(where: { $0.id == jobID })
            if completed?.phase == .completed || completed?.phase == .failed { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(completed?.phase, .completed, completed?.statusMessage ?? recorder.lastError ?? "Queue did not finish")
        XCTAssertEqual(fixture.model.draft.text, "Existing draft\n\nSynthetic reviewed transcript")
        XCTAssertEqual(fixture.model.draft.requestID, fixture.draft.requestID)
        XCTAssertEqual(fixture.model.draft.additionalPayloads.count, 2)
        XCTAssertEqual(usage.totalSecondsUsed, 1)
        XCTAssertNil(recorder.lastFileExportEvent)
        XCTAssertNil(recorder.lastSentAudioUndoSnapshot)
        XCTAssertNil(fixture.model.lastReceipt)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.vault.path), [])

        // Only an explicit Send may cross the synthetic destination boundary.
        XCTAssertTrue(fixture.model.canSubmit)
        await fixture.model.submit()
        let receipt = try XCTUnwrap(fixture.model.lastReceipt, fixture.model.errorMessage ?? "Explicit Send did not deliver")
        let markdown = try String(contentsOf: receipt.noteURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("Existing draft"))
        XCTAssertTrue(markdown.contains("Synthetic reviewed transcript"))
        XCTAssertEqual(receipt.attachmentURLs.count, 2)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suite = "DraftRecordingActionTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    func testNoSpeechStillExportsConfiguredAudioAndRetainsSource() async throws {
        try await assertNoSpeechExport(audioSaveMode: .alongsideTranscript)
    }

    func testNoSpeechInTextOnlyPresetStillSavesAudioToFiles() async throws {
        try await assertNoSpeechExport(audioSaveMode: .off)
    }

    private func assertNoSpeechExport(audioSaveMode: CapturePresetAudioSaveMode) async throws {
        let fixture = try await makeDraftFixture()
        var preset = makePresets().selected
        preset.captureDestinationID = nil
        preset.audioSaveMode = audioSaveMode
        preset.exportSettings.usesCustomExportSettings = true
        preset.exportSettings.exportEnabled = true
        preset.exportSettings.folderBookmark = try fixture.vault.bookmarkData()
        preset.exportSettings.format = .md
        let jobStore = RecordingJobStore(rootDirectoryURL: fixture.root.appendingPathComponent("jobs"))
        let transcriptStore = TranscriptStore()
        let originalRecorder = PersistentRecorder.active
        let recorder = PersistentRecorder(
            transcriptStore: transcriptStore,
            usageTracker: UsageTracker(defaults: fixture.defaults),
            transcriptionService: OnDeviceTranscriptionService(
                systemBackend: DraftActionEmptySpeechBackend(), usesDownloadedLocalFallbacks: false
            ),
            recordingJobStore: jobStore
        )
        let jobID = UUID()
        defer {
            transcriptStore.delete(ids: [jobID])
            PersistentRecorder.active = originalRecorder
        }
        _ = try await recorder.recordingQueue.enqueue(
            sourceURL: fixture.audioURL, id: jobID, requestID: "inapp-no-speech",
            captureSource: .shortcut, duration: 1, source: .iOSApp, delivery: .preset(preset),
            modelID: "automatic", fallbackModelID: nil, language: "en",
            configuration: RecordingQueueConfiguration(sourceAudioRetention: .permanent)
        )
        let deadline = Date().addingTimeInterval(10)
        var finished: RecordingJob?
        while Date() < deadline {
            finished = try await jobStore.load(recoverInterrupted: false).first(where: { $0.id == jobID })
            if finished?.phase == .completed || finished?.phase == .failed { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        let job = try XCTUnwrap(finished)
        XCTAssertEqual(job.phase, .completed, job.statusMessage ?? "Queue did not finish")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jobStore.audioURL(for: job).path))
        let files = try FileManager.default.contentsOfDirectory(at: fixture.vault, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { ["m4a", "wav"].contains($0.pathExtension) }, "No-speech recording must reach Files")
        XCTAssertTrue(files.contains { $0.pathExtension == "md" })
    }

    func testRepeatedStopsPreserveShortQuietAndSilentRecordingAudio() async throws {
        let fixture = try await makeDraftFixture()
        let jobStore = RecordingJobStore(rootDirectoryURL: fixture.root.appendingPathComponent("jobs"))
        let buffer = CircularAudioBuffer(capacity: 100_000)
        let originalRecorder = PersistentRecorder.active
        let recorder = PersistentRecorder(
            transcriptStore: TranscriptStore(),
            usageTracker: UsageTracker(defaults: fixture.defaults),
            transcriptionService: OnDeviceTranscriptionService(
                systemBackend: DraftActionEmptySpeechBackend(), usesDownloadedLocalFallbacks: false
            ),
            recordingJobStore: jobStore,
            circularBuffer: buffer
        )
        // Hold processing while exercising the real segment stop/handoff path.
        // Samples are injected at the audio-tap boundary; no microphone is used.
        _ = recorder.recordingQueue.beginCaptureLease()
        recorder.isListening = true
        defer {
            recorder.stopListening()
            PersistentRecorder.active = originalRecorder
        }
        for (index, samples) in [
            Array(repeating: Float(0.1), count: 1_600),
            Array(repeating: Float(0.000_001), count: 16_000),
            Array(repeating: Float(0), count: 16_000)
        ].enumerated() {
            buffer.reset()
            recorder.startInAppSegment(completionMode: .captureDraft(attachAudio: false), origin: .quickRecord)
            XCTAssertTrue(recorder.isSegmentActive)
            buffer.append(samples)
            recorder.stopInAppSegment()
            recorder.stopInAppSegment()
            let deadline = Date().addingTimeInterval(3)
            var jobs: [RecordingJob] = []
            while Date() < deadline {
                jobs = try await jobStore.load(recoverInterrupted: false)
                if jobs.count == index + 1 { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            XCTAssertEqual(jobs.count, index + 1, recorder.lastError ?? "Recording never reached the durable queue")
            guard let job = jobs.max(by: { $0.createdAt < $1.createdAt }) else { continue }
            XCTAssertEqual(job.retentionPolicy, .permanent)
            let saved = try Data(contentsOf: jobStore.audioURL(for: job))
            XCTAssertEqual(saved.count, 44 + samples.count * 2)
            XCTAssertEqual(job.duration, Double(samples.count) / 16_000, accuracy: 0.000_1)
        }
    }

    func testDefaultQueuePreferencesRetainAudioAndRespectExplicitDeletion() throws {
        let defaults = try makeDefaults()
        XCTAssertEqual(RecordingQueueConfiguration.default.sourceAudioRetention, .permanent)
        XCTAssertEqual(RecordingQueuePreferences.load(from: defaults).sourceAudioRetention, .permanent)
        defaults.set(SourceAudioRetentionMode.deleteAfterSuccess.rawValue, forKey: RecordingQueuePreferences.retentionModeKey)
        XCTAssertEqual(RecordingQueuePreferences.load(from: defaults).sourceAudioRetention, .deleteAfterSuccess)
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DraftRecordingActionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func makePresets() -> (selected: CapturePreset, requested: CapturePreset) {
        var selected = CapturePresetStore.makeCustomFlow()
        selected.id = "selected-draft"
        selected.name = "Selected draft"
        var requested = CapturePresetStore.makeCustomFlow()
        requested.id = "requested-voice"
        requested.name = "Requested voice"
        requested.speakerDiarizationEnabled = true
        return (selected, requested)
    }

    private func makeDraftFixture() async throws -> DraftActionFixture {
        let root = try makeRoot()
        let defaults = try makeDefaults()
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let destination = CaptureDestination(name: "Review destination", rootBookmark: try vault.bookmarkData(), rootName: "Synthetic vault",
                                             noteTarget: .existingNote(relativePath: "Review.md"))
        var preset = makePresets().selected
        preset.captureDestinationID = destination.id
        CapturePresetStore.saveFlows([preset], defaults: defaults)
        CapturePresetStore.selectFlow(id: preset.id, defaults: defaults)
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let existingAsset = try CaptureAssetReference(relativePath: "keep.txt", originalFilename: "keep.txt", contentTypeIdentifier: "public.plain-text")
        let draft = CaptureDraft(text: "Existing draft", voxID: preset.id, destinationID: destination.id,
                                 additionalPayloads: [.file(existingAsset)])
        let staging = root.appendingPathComponent("staging/\(draft.id.uuidString.lowercased())")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("Existing attachment".utf8).write(to: staging.appendingPathComponent("keep.txt"))
        try await CaptureDraftStore(rootDirectoryURL: root).save(draft)
        let audioURL = root.appendingPathComponent("recording_synthetic.wav")
        try AudioFileConverter.writeWAV(samples: Array(repeating: 0.01, count: 16_000), to: audioURL)
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline())
        addTeardownBlock { @MainActor in _ = await model.flushDraftForTermination() }
        return DraftActionFixture(root: root, defaults: defaults, vault: vault, audioURL: audioURL, draft: draft, model: model)
    }
}

private struct DraftActionFixture {
    let root: URL
    let defaults: UserDefaults
    let vault: URL
    let audioURL: URL
    let draft: CaptureDraft
    let model: QuickCaptureViewModel
}

/// An ASR system boundary, never a microphone or network request.
private struct DraftActionSyntheticSpeechBackend: SystemTranscriptionBackend {
    func availability(language: String) async -> SystemTranscriptionAvailability { .ready }
    func prepare(language: String) async throws {}
    func transcribe(audioURL: URL, language: String) async throws -> SystemTranscriptionOutput {
        SystemTranscriptionOutput(text: "Synthetic reviewed transcript", language: "en")
    }
    func startLiveTranscription(
        language: String,
        onUpdate: @escaping @concurrent @Sendable (SystemTranscriptionUpdate) async -> Void
    ) async throws -> any SystemLiveTranscriptionSession {
        throw OnDeviceTranscriptionError.systemBackendUnavailable
    }
}

private struct DraftActionEmptySpeechBackend: SystemTranscriptionBackend {
    func availability(language: String) async -> SystemTranscriptionAvailability { .ready }
    func prepare(language: String) async throws {}
    func transcribe(audioURL: URL, language: String) async throws -> SystemTranscriptionOutput {
        SystemTranscriptionOutput(text: "", language: "en")
    }
    func startLiveTranscription(
        language: String,
        onUpdate: @escaping @concurrent @Sendable (SystemTranscriptionUpdate) async -> Void
    ) async throws -> any SystemLiveTranscriptionSession {
        throw OnDeviceTranscriptionError.systemBackendUnavailable
    }
}
