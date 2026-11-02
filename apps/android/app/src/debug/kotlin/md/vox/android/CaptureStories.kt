package md.vox.android

import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import md.vox.android.capturedomain.CaptureAttachment
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.CaptureLocationUnavailableReason
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CapturePresetQuickAccess
import md.vox.android.capturedomain.CaptureRailSide
import md.vox.android.capturedomain.CaptureRouteOverride
import md.vox.android.platformservices.LiveSpeechPhase
import md.vox.android.platformservices.LiveSpeechState
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.CaptureUiState

/**
 * Signal redesign stories for the capture area. Story ids use the
 * "capture-" prefix; launch with
 * `adb shell am start -n md.vox.android/.VisualStoryActivity --es story <id> --ez dark <bool>`.
 * Returns false when [story] is not one of these.
 */
@Composable
internal fun CaptureStories(story: String): Boolean {
    when (story) {
        // Composer states
        "capture-empty" -> CaptureSignalStory(text = "")
        "capture-draft" -> CaptureSignalStory()
        "capture-minimal-bar" -> CaptureSignalStory(
            captureBar = CaptureBarConfiguration(hiddenActions = CaptureBarAction.entries.toSet()),
        )
        "capture-long-text" -> CaptureSignalStory(text = captureStoryLongText)
        "capture-attachments" -> CaptureSignalStory(
            url = "https://example.com/launch/story-with-a-long-path",
            attachments = captureStoryAttachments,
        )
        "capture-sending" -> CaptureSignalStory(isSending = true)
        "capture-route-override" -> CaptureSignalStory(
            routeOverride = CaptureRouteOverride("Journal/Today.md", CapturePlacementKind.PREPEND),
        )
        "capture-entry-templates" -> CaptureSignalStory(
            entryTemplates = listOf(
                CaptureEntryTemplate(
                    id = "44444444-4444-4444-8444-444444444444",
                    name = "Meeting bullet",
                    entryPrefix = "- {time} ",
                ),
            ),
        )
        "capture-no-pins" -> CaptureSignalStory(
            presets = visualPresets.copy(presets = visualPresets.presets.map { it.copy(isPinned = false) }),
        )
        "capture-rail-left" -> CaptureSignalStory(presets = railStoryPresets, isPresetRailExpanded = true)
        "capture-rail-right" -> CaptureSignalStory(
            presets = railStoryPresets,
            isPresetRailExpanded = true,
            captureBar = CaptureBarConfiguration(railSide = CaptureRailSide.RIGHT),
        )

        // Voice capture states
        "capture-voice-idle-details" -> CaptureSignalStory(showDetails = true)
        "capture-recording" -> CaptureSignalStory(recordingPhase = RecordingPhase.RECORDING, level = 0.7f)
        "capture-recording-paused" -> CaptureSignalStory(recordingPhase = RecordingPhase.PAUSED)
        "capture-recording-collapsed" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.RECORDING,
            level = 0.7f,
            showDetails = false,
        )
        "capture-recording-listening" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.RECORDING,
            level = 0.4f,
            liveSpeech = LiveSpeechState(sessionID = RECORDING_ID, phase = LiveSpeechPhase.LISTENING),
        )
        "capture-recording-preview-unavailable" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.RECORDING,
            level = 0.5f,
            liveSpeech = LiveSpeechState(sessionID = RECORDING_ID, phase = LiveSpeechPhase.UNAVAILABLE),
        )
        "capture-recording-interrupted" -> CaptureSignalStory(recordingPhase = RecordingPhase.INTERRUPTED)
        "capture-recording-failed" -> CaptureSignalStory(recordingPhase = RecordingPhase.FAILED)
        "capture-recording-saved" -> CaptureSignalStory(recordingPhase = RecordingPhase.COMPLETED)
        "capture-transcript-queued" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.COMPLETED,
            transcription = captureStoryTranscription(RecordingTranscriptionPhase.QUEUED),
        )
        "capture-transcribing" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.COMPLETED,
            transcription = captureStoryTranscription(RecordingTranscriptionPhase.PROCESSING, progress = 0.42f),
        )
        "capture-transcribing-collapsed" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.COMPLETED,
            transcription = captureStoryTranscription(RecordingTranscriptionPhase.PROCESSING, progress = 0.42f),
            showDetails = false,
        )
        "capture-transcript-finalizing" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.COMPLETED,
            transcription = captureStoryTranscription(RecordingTranscriptionPhase.FINALIZING, progress = 1f),
        )
        "capture-transcript-ready" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.COMPLETED,
            transcription = captureStoryTranscription(RecordingTranscriptionPhase.COMPLETED, progress = 1f),
            captureBar = CaptureBarConfiguration(confirmsVoiceNotesBeforeAdding = true),
        )
        "capture-transcript-added" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.COMPLETED,
            transcription = captureStoryTranscription(RecordingTranscriptionPhase.COMPLETED, progress = 1f, added = true),
            captureBar = CaptureBarConfiguration(confirmsVoiceNotesBeforeAdding = true),
        )
        "capture-transcription-failed" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.COMPLETED,
            transcription = captureStoryTranscription(RecordingTranscriptionPhase.FAILED, failureCode = "modelNotInstalled"),
        )
        "capture-transcription-discarded" -> CaptureSignalStory(
            recordingPhase = RecordingPhase.COMPLETED,
            transcription = captureStoryTranscription(RecordingTranscriptionPhase.DISCARDED),
        )

        // Dialogs over the composer
        "capture-location-unavailable" -> Box {
            CaptureSignalStory()
            LocationUnavailableDialog(
                reason = CaptureLocationUnavailableReason.TIMEOUT,
                canPersistPreference = true,
                retry = {},
                sendWithoutLocation = {},
                alwaysSendWithoutLocation = {},
                cancel = {},
            )
        }
        "capture-location-unavailable-no-preset" -> Box {
            CaptureSignalStory()
            LocationUnavailableDialog(
                reason = CaptureLocationUnavailableReason.REDUCED_ACCURACY,
                canPersistPreference = false,
                retry = {},
                sendWithoutLocation = {},
                alwaysSendWithoutLocation = {},
                cancel = {},
            )
        }
        "capture-due-date" -> Box {
            CaptureSignalStory()
            DueDateDialog(onDismiss = {}, onInsert = {})
        }
        "capture-link-dialog" -> Box {
            CaptureSignalStory()
            LinkDialog(initialValue = "https://example.com/story", onDismiss = {}, onSave = {})
        }
        "capture-link-dialog-empty" -> Box {
            CaptureSignalStory()
            LinkDialog(initialValue = "", onDismiss = {}, onSave = {})
        }
        "capture-media-dialog" -> Box {
            CaptureSignalStory()
            CaptureMediaDialog(onDismiss = {}, choosePhotos = {}, chooseScreenshots = {}, takePhoto = {})
        }
        "capture-sketch" -> Box {
            CaptureSignalStory()
            SketchDialog(onDismiss = {}, onSave = {}, onFailure = {})
        }
        else -> return false
    }
    return true
}

private const val captureStoryText =
    "# Launch notes\n\n- [ ] Review final designs\n- [ ] Publish release notes\n\nMeeting ideas captured while they are fresh."

private val captureStoryLongText = buildString {
    append("# Quarterly planning — a very long heading that wraps across several lines on a phone\n\n")
    repeat(14) { index ->
        append("- [ ] Follow up on item ${index + 1} with the design, research and engineering leads before Friday\n")
    }
    append("\nDecision: ship routing first and keep the composer calm.")
}

private val captureStoryAttachments = listOf(
    CaptureAttachment(
        id = "a1",
        displayName = "Photo.png",
        vaultFileName = "Photo.png",
        mediaType = "image/png",
        byteCount = 2_400_000,
        sha256 = "0".repeat(64),
    ),
    CaptureAttachment(
        id = "a2",
        displayName = "Quarterly planning document with a long name.pdf",
        vaultFileName = "Document.pdf",
        mediaType = "application/pdf",
        byteCount = 182_000,
        sha256 = "1".repeat(64),
    ),
)

private fun captureStoryTranscription(
    phase: RecordingTranscriptionPhase,
    progress: Float = 0f,
    added: Boolean = false,
    failureCode: String? = null,
) = RecordingTranscriptionState(
    sessionID = RECORDING_ID,
    phase = phase,
    progress = progress,
    modelID = "ggml-small",
    modelName = "Whisper Small",
    durationMillis = 42_000,
    recordedAtEpochMillis = FIXED_TIME,
    transcript = if (phase == RecordingTranscriptionPhase.COMPLETED) {
        "Loop in design before Friday and ship routing first."
    } else null,
    failureCode = failureCode,
    addedToDraft = added,
)

@Composable
private fun CaptureSignalStory(
    text: String = captureStoryText,
    url: String? = null,
    attachments: List<CaptureAttachment> = emptyList(),
    isSending: Boolean = false,
    routeOverride: CaptureRouteOverride? = null,
    entryTemplates: List<CaptureEntryTemplate> = emptyList(),
    presets: CapturePresetCollection = visualPresets,
    isPresetRailExpanded: Boolean = false,
    captureBar: CaptureBarConfiguration = CaptureBarConfiguration(),
    recordingPhase: RecordingPhase = RecordingPhase.IDLE,
    level: Float = 0f,
    transcription: RecordingTranscriptionState? = null,
    liveSpeech: LiveSpeechState? = null,
    showDetails: Boolean = recordingPhase != RecordingPhase.IDLE || transcription != null,
) {
    val state = CaptureUiState(
        isLoading = false,
        isSending = isSending,
        destination = visualDestination,
        draft = CaptureDraft(
            text = text,
            url = url,
            updatedAtEpochMillis = FIXED_TIME,
            attachments = attachments,
            routeOverride = routeOverride,
        ),
        captureBar = captureBar,
        presetCollection = presets,
        isPresetRailExpanded = isPresetRailExpanded,
        entryTemplates = entryTemplates,
    )
    val recordingStatus = if (recordingPhase != RecordingPhase.IDLE) {
        RecordingStatus(
            sessionID = RECORDING_ID,
            phase = recordingPhase,
            createdAtEpochMillis = FIXED_TIME,
            elapsedMillis = 42_000,
            level = level,
            chunkCount = 2,
        )
    } else {
        RecordingStatus(phase = RecordingPhase.IDLE)
    }
    val speech = liveSpeech ?: if (recordingPhase in setOf(RecordingPhase.RECORDING, RecordingPhase.PAUSED)) {
        LiveSpeechState(
            sessionID = RECORDING_ID,
            phase = if (recordingPhase == RecordingPhase.PAUSED) LiveSpeechPhase.PAUSED else LiveSpeechPhase.LISTENING,
            committedText = "Meeting ideas captured while they are fresh.",
            partialText = "Review the launch checklist",
        )
    } else null
    CaptureScreen(
        state = state,
        recordingStatus = recordingStatus,
        recordingTranscription = transcription,
        liveSpeech = speech,
        onSubmit = { _, _, _ -> },
        onSubmitRecording = { _, _, _, _, _, _, _ -> },
        onDraftChanged = { _, _ -> },
        onEntryTemplateSelected = {},
        pinnedPresets = CapturePresetQuickAccess.alternatePresets(presets),
        isPresetRailExpanded = isPresetRailExpanded,
        togglePresetRail = {},
        onSelectPreset = {},
        addDraftAttachment = { _, _, _, _ -> },
        removeDraftAttachment = {},
        presentNotice = {},
        persistLocationUnavailableBehavior = { _, _ -> },
        consumeAcceptedCapture = {},
        consumeExternalDraft = {},
        openHistory = {},
        openSettings = {},
        openPresets = {},
        startRecording = {},
        pauseRecording = {},
        resumeRecording = {},
        stopRecording = {},
        cancelRecording = {},
        dismissRecording = {},
        processRecording = {},
        cancelRecordingProcessing = {},
        markRecordingAdded = {},
        exportRecordingAudio = { null },
        frozenRecordingPreset = { visualPresets.activePreset },
        requestEditorFocus = false,
        initialShowsVoiceCaptureDetails = showDetails,
    )
}
