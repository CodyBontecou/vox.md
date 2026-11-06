package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import md.vox.android.ui.Signal
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.InstructionModelPhase
import md.vox.android.platformservices.InstructionModelState
import md.vox.android.platformservices.OnDeviceSpeechAvailability
import md.vox.android.platformservices.OnDeviceSpeechCapability
import md.vox.android.platformservices.RecordingJobPolicy
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingProcessingPolicy
import md.vox.android.platformservices.RecordingRetentionKind
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.platformservices.SpeakerModelInstallPhase
import md.vox.android.platformservices.SpeakerModelState
import md.vox.android.platformservices.SpeechModelDescriptor
import md.vox.android.platformservices.SpeechModelEngine
import md.vox.android.platformservices.SpeechModelInstallPhase
import md.vox.android.platformservices.SpeechModelInstallState
import md.vox.android.platformservices.SpeechModelManagerState
import md.vox.android.platformservices.SpeechModelSelectionMode
import md.vox.android.platformservices.VoiceAutoStopEndAction
import md.vox.android.platformservices.VoiceAutoStopSettings

/**
 * Signal redesign stories for the recovery area. Story ids use the
 * "recovery-" prefix; launch with
 * `adb shell am start -n md.vox.android/.VisualStoryActivity --es story <id> --ez dark <bool>`.
 * Returns false when [story] is not one of these.
 */
@Composable
internal fun RecoveryStories(story: String): Boolean {
    when (story) {
        // Recording queue
        "recovery-queue-empty" -> QueueStory(emptyList())
        "recovery-queue-importing" -> QueueStory(emptyList(), isImporting = true)
        "recovery-queue-import-failed" -> QueueStory(
            emptyList(),
            message = voxUiText("This device cannot decode that media format."),
        )
        "recovery-queue-recording" -> QueueStory(
            listOf(QueueRow(queueRecording(RecordingPhase.RECORDING, elapsed = 83_000, chunks = 4), canControl = true)),
        )
        "recovery-queue-paused" -> QueueStory(
            listOf(QueueRow(queueRecording(RecordingPhase.PAUSED, elapsed = 142_000, chunks = 7), canControl = true)),
        )
        "recovery-queue-interrupted" -> QueueStory(
            listOf(
                QueueRow(
                    queueRecording(RecordingPhase.INTERRUPTED, elapsed = 318_000, chunks = 16),
                    canControl = true,
                    reassignPresets = visualPresets.presets,
                ),
            ),
        )
        "recovery-queue-failed" -> QueueStory(
            listOf(QueueRow(queueRecording(RecordingPhase.FAILED, elapsed = 9_000, chunks = 0))),
        )
        "recovery-queue-waiting" -> QueueStory(
            listOf(QueueRow(queueRecording(RecordingPhase.COMPLETED), transcription(RecordingTranscriptionPhase.QUEUED))),
        )
        "recovery-queue-transcribing" -> QueueStory(
            listOf(
                QueueRow(
                    queueRecording(RecordingPhase.COMPLETED),
                    transcription(RecordingTranscriptionPhase.PROCESSING, progress = 0.42f),
                ),
            ),
        )
        "recovery-queue-finalizing" -> QueueStory(
            listOf(QueueRow(queueRecording(RecordingPhase.COMPLETED), transcription(RecordingTranscriptionPhase.FINALIZING, progress = 1f))),
        )
        "recovery-queue-retry" -> QueueStory(
            listOf(
                QueueRow(
                    queueRecording(RecordingPhase.COMPLETED),
                    transcription(RecordingTranscriptionPhase.FAILED, failureCode = "processInterrupted"),
                ),
            ),
            showRetryAll = true,
        )
        "recovery-queue-quota" -> QueueStory(
            listOf(
                QueueRow(
                    queueRecording(RecordingPhase.COMPLETED),
                    transcription(RecordingTranscriptionPhase.FAILED, failureCode = "transcriptionQuotaReached"),
                ),
            ),
        )
        "recovery-queue-no-model" -> QueueStory(
            listOf(QueueRow(queueRecording(RecordingPhase.COMPLETED), canProcess = false)),
        )
        "recovery-queue-ready" -> QueueStory(
            listOf(QueueRow(queueRecording(RecordingPhase.COMPLETED), transcription(RecordingTranscriptionPhase.COMPLETED))),
        )
        "recovery-queue-exported" -> QueueStory(
            listOf(
                QueueRow(
                    queueRecording(RecordingPhase.COMPLETED),
                    transcription(RecordingTranscriptionPhase.COMPLETED, addedToDraft = true),
                    policy = RecordingJobPolicy(
                        processing = RecordingProcessingPolicy.MANUAL,
                        retention = RecordingRetentionKind.PERMANENT,
                    ),
                ),
            ),
            message = voxUiText("Audio exported as WAV."),
        )
        "recovery-queue-exporting" -> QueueStory(
            listOf(QueueRow(queueRecording(RecordingPhase.COMPLETED), isExporting = true)),
        )
        "recovery-queue-discarded" -> QueueStory(
            listOf(QueueRow(queueRecording(RecordingPhase.COMPLETED), transcription(RecordingTranscriptionPhase.DISCARDED))),
        )
        "recovery-queue-populated" -> QueueStory(
            listOf(
                QueueRow(
                    queueRecording(RecordingPhase.COMPLETED, id = "a1111111-1111-4111-8111-111111111111"),
                    transcription(RecordingTranscriptionPhase.PROCESSING, progress = 0.68f, id = "a1111111-1111-4111-8111-111111111111"),
                ),
                QueueRow(
                    queueRecording(RecordingPhase.COMPLETED, id = "b2222222-2222-4222-8222-222222222222", elapsed = 61_000),
                    transcription(RecordingTranscriptionPhase.FAILED, failureCode = "noSpeech", id = "b2222222-2222-4222-8222-222222222222"),
                ),
                QueueRow(
                    queueRecording(RecordingPhase.COMPLETED, id = "c3333333-3333-4333-8333-333333333333", elapsed = 204_000),
                    transcription(RecordingTranscriptionPhase.COMPLETED, id = "c3333333-3333-4333-8333-333333333333"),
                ),
            ),
            showRetryAll = true,
            message = voxUiText("Transcript copied."),
        )
        "recovery-queue-long-text" -> QueueStory(
            listOf(
                QueueRow(
                    queueRecording(RecordingPhase.COMPLETED, elapsed = 3_725_000, chunks = 240),
                    transcription(
                        RecordingTranscriptionPhase.COMPLETED,
                        transcript = List(6) {
                            "We agreed to move the launch review to Thursday, keep the onboarding copy as drafted, and follow up with design on the empty states for Activity and Library."
                        }.joinToString(" "),
                    ),
                    reassignPresets = visualPresets.presets,
                ),
            ),
        )

        // Models
        "recovery-models-default" -> ModelsStory()
        "recovery-models-automatic-unready" -> ModelsStory(
            models = storyModels(whisperSmall = SpeechModelInstallPhase.NOT_INSTALLED),
            selectedModelID = null,
        )
        "recovery-models-selected" -> ModelsStory(
            models = storyModels(parakeet = SpeechModelInstallPhase.READY),
            selectionMode = SpeechModelSelectionMode.MANUAL,
            selectedModelID = PARAKEET_ID,
        )
        "recovery-models-downloading" -> ModelsStory(
            models = storyModels(parakeet = SpeechModelInstallPhase.DOWNLOADING),
            speaker = SpeakerModelState(SpeakerModelInstallPhase.DOWNLOADING, downloadedBytes = 4_200_000, totalBytes = 13_000_000),
            instruction = InstructionModelState(InstructionModelPhase.INSTALLING, progress = 0.27f),
        )
        "recovery-models-verifying" -> ModelsStory(
            models = storyModels(parakeet = SpeechModelInstallPhase.VERIFYING, vosk = SpeechModelInstallPhase.INSTALLING),
            speaker = SpeakerModelState(SpeakerModelInstallPhase.VERIFYING),
        )
        "recovery-models-failed" -> ModelsStory(
            models = storyModels(parakeet = SpeechModelInstallPhase.FAILED, voskFailure = "unsafeArchive", vosk = SpeechModelInstallPhase.FAILED),
            speaker = SpeakerModelState(SpeakerModelInstallPhase.FAILED, failureCode = "downloadHttp503"),
            instruction = InstructionModelState(InstructionModelPhase.FAILED, failureCode = "modelChecksumMismatch"),
        )
        "recovery-models-unsupported" -> ModelsStory(
            capability = OnDeviceSpeechCapability(OnDeviceSpeechAvailability.REQUIRES_ANDROID_12, 30),
            models = storyModels(
                whisperSmall = SpeechModelInstallPhase.NOT_INSTALLED,
                parakeet = SpeechModelInstallPhase.FAILED,
                parakeetFailure = "insufficientDeviceMemory",
            ),
            selectedModelID = null,
            instruction = InstructionModelState(InstructionModelPhase.FAILED, failureCode = "insufficientDeviceMemory"),
        )
        "recovery-models-check-failed" -> ModelsStory(
            capability = OnDeviceSpeechCapability(OnDeviceSpeechAvailability.CHECK_FAILED, 35),
        )
        "recovery-models-unavailable" -> ModelsStory(
            capability = OnDeviceSpeechCapability(OnDeviceSpeechAvailability.NOT_AVAILABLE, 35),
        )
        "recovery-models-installed" -> ModelsStory(
            models = storyModels(parakeet = SpeechModelInstallPhase.READY, vosk = SpeechModelInstallPhase.READY),
            speaker = SpeakerModelState(SpeakerModelInstallPhase.READY, installedBytes = 13_400_000),
            instruction = InstructionModelState(InstructionModelPhase.READY, progress = 1f),
        )
        "recovery-models-autostop-on" -> ModelsStory(
            autoStop = VoiceAutoStopSettings(enabled = true, pauseDurationMillis = 1_000L),
        )
        "recovery-models-autostop-keep-listening" -> ModelsStory(
            autoStop = VoiceAutoStopSettings(
                enabled = true,
                pauseDurationMillis = 1_500L,
                endAction = VoiceAutoStopEndAction.SAVE_SEGMENT_AND_CONTINUE,
            ),
        )
        // Activity
        "recovery-activity-all" -> ActivityStory(activityStoryItems, activityStoryTranscripts)
        "recovery-activity-needs-you" -> ActivityStory(activityStoryItems, activityStoryTranscripts, ActivityFilter.NEEDS_YOU)
        "recovery-activity-in-flight" -> ActivityStory(activityStoryItems, activityStoryTranscripts, ActivityFilter.IN_FLIGHT)
        "recovery-activity-empty" -> ActivityStory(emptyList())
        "recovery-activity-needs-you-empty" -> ActivityStory(emptyList(), filter = ActivityFilter.NEEDS_YOU)

        // Delivery problem sheet content
        "recovery-delivery-failed" -> DeliveryProblemStory(activityCapture(5, md.vox.android.capturedomain.CaptureState.NEEDS_USER_ACTION))
        "recovery-delivery-vault" -> DeliveryProblemStory(activityCapture(4, md.vox.android.capturedomain.CaptureState.NEEDS_PERMISSION))
        else -> return false
    }
    return true
}

private const val QUEUE_TIME = FIXED_TIME
private const val WHISPER_SMALL_ID = "sherpa-whisper-small"
private const val PARAKEET_ID = "sherpa-parakeet-v3"
private const val VOSK_ID = "vosk-small-en-us-0.15"

private data class QueueRow(
    val recording: RecordingStatus,
    val transcription: RecordingTranscriptionState? = null,
    val canControl: Boolean = false,
    val canProcess: Boolean = true,
    val isExporting: Boolean = false,
    val reassignPresets: List<CapturePreset> = emptyList(),
    val policy: RecordingJobPolicy = RecordingJobPolicy(),
)

private fun queueRecording(
    phase: RecordingPhase,
    id: String = RECORDING_ID,
    elapsed: Long = 42_000,
    chunks: Int = 3,
) = RecordingStatus(
    sessionID = id,
    phase = phase,
    createdAtEpochMillis = QUEUE_TIME,
    elapsedMillis = elapsed,
    level = 0.4f,
    chunkCount = chunks,
)

private fun transcription(
    phase: RecordingTranscriptionPhase,
    progress: Float = 0f,
    failureCode: String? = null,
    addedToDraft: Boolean = false,
    id: String = RECORDING_ID,
    transcript: String = "Remember to send the revised launch notes to Priya before Friday and book the room for the retro.",
) = RecordingTranscriptionState(
    sessionID = id,
    phase = phase,
    progress = progress,
    modelID = "ggml-small",
    modelName = "Whisper Small",
    durationMillis = 42_000,
    recordedAtEpochMillis = QUEUE_TIME,
    completedAtEpochMillis = if (phase == RecordingTranscriptionPhase.COMPLETED) QUEUE_TIME + 60_000 else null,
    transcript = if (phase == RecordingTranscriptionPhase.COMPLETED) transcript else null,
    failureCode = failureCode,
    addedToDraft = addedToDraft,
)

@Composable
private fun QueueStory(
    rows: List<QueueRow>,
    message: VoxUiText? = null,
    isImporting: Boolean = false,
    showRetryAll: Boolean = false,
) {
    RecordingQueueContent(
        recordings = rows.map { it.recording },
        operationMessage = message,
        importEnabled = true,
        isImporting = isImporting,
        showRetryAll = showRetryAll,
        navigateBack = {},
        refresh = {},
        importMedia = {},
        retryAll = {},
    ) { recording ->
        val row = rows.first { it.recording.sessionID == recording.sessionID }
        RecordingQueueCard(
            recording = row.recording,
            transcription = row.transcription,
            policy = row.policy,
            canProcess = row.canProcess,
            canControl = row.canControl,
            isExporting = row.isExporting,
            resume = {},
            finish = {},
            cancel = {},
            export = {},
            shareAudio = {},
            delete = {},
            process = {},
            cancelProcessing = {},
            addToDraft = {},
            copyTranscript = {},
            shareTranscript = {},
            reassignPresets = row.reassignPresets,
            reassign = {},
            updatePolicy = {},
        )
    }
}

private val whisperSmallDescriptor = SpeechModelDescriptor(
    id = WHISPER_SMALL_ID,
    displayName = "Whisper Small",
    languageTag = "multilingual",
    archiveName = "whisper-small",
    approximateBytes = 375_000_000,
    engine = SpeechModelEngine.SHERPA_WHISPER,
    modelDescription = "Private multilingual transcription on this device.",
    isMultilingual = true,
    bundledByDefault = true,
    licenseName = "MIT",
)

private val parakeetDescriptor = SpeechModelDescriptor(
    id = PARAKEET_ID,
    displayName = "Parakeet v3",
    languageTag = "multilingual",
    archiveName = "parakeet-v3",
    approximateBytes = 671_000_000,
    engine = SpeechModelEngine.SHERPA_PARAKEET,
    modelDescription = "Fast, punctuation-aware transcription in 25 languages.",
    isMultilingual = true,
    minimumMemoryBytes = 4_000_000_000,
    licenseName = "CC-BY-4.0",
)

private val voskDescriptor = SpeechModelDescriptor(
    id = VOSK_ID,
    displayName = "English (US)",
    languageTag = "en-US",
    archiveName = "vosk-model-small-en-us-0.15",
    approximateBytes = 40_000_000,
)

private fun installState(
    descriptor: SpeechModelDescriptor,
    phase: SpeechModelInstallPhase,
    failureCode: String? = null,
) = SpeechModelInstallState(
    descriptor = descriptor,
    phase = phase,
    downloadedBytes = if (phase == SpeechModelInstallPhase.DOWNLOADING) descriptor.approximateBytes * 38 / 100 else 0,
    totalBytes = if (phase == SpeechModelInstallPhase.DOWNLOADING) descriptor.approximateBytes else null,
    installedBytes = if (phase == SpeechModelInstallPhase.READY) descriptor.approximateBytes else 0,
    failureCode = if (phase == SpeechModelInstallPhase.FAILED) failureCode else null,
)

private fun storyModels(
    whisperSmall: SpeechModelInstallPhase = SpeechModelInstallPhase.READY,
    parakeet: SpeechModelInstallPhase = SpeechModelInstallPhase.NOT_INSTALLED,
    parakeetFailure: String? = "downloadHttp404",
    vosk: SpeechModelInstallPhase = SpeechModelInstallPhase.NOT_INSTALLED,
    voskFailure: String? = null,
) = listOf(
    installState(whisperSmallDescriptor, whisperSmall),
    installState(parakeetDescriptor, parakeet, parakeetFailure),
    installState(voskDescriptor, vosk, voskFailure),
)

@Composable
private fun ModelsStory(
    capability: OnDeviceSpeechCapability = OnDeviceSpeechCapability(OnDeviceSpeechAvailability.AVAILABLE, 35),
    models: List<SpeechModelInstallState> = storyModels(),
    selectionMode: SpeechModelSelectionMode = SpeechModelSelectionMode.AUTOMATIC,
    selectedModelID: String? = WHISPER_SMALL_ID,
    speaker: SpeakerModelState = SpeakerModelState(SpeakerModelInstallPhase.NOT_INSTALLED),
    autoStop: VoiceAutoStopSettings = VoiceAutoStopSettings(),
    instruction: InstructionModelState = InstructionModelState(InstructionModelPhase.ABSENT),
) {
    var settings by remember { mutableStateOf(autoStop) }
    ModelsScreenContent(
        capability = capability,
        modelState = SpeechModelManagerState(models, selectedModelID, selectionMode),
        speakerModelState = speaker,
        autoStopSettings = settings,
        navigateBack = {},
        refresh = {},
        updateAutoStop = { settings = it },
        installSpeaker = {},
        cancelSpeaker = {},
        deleteSpeaker = { false },
        selectAutomatic = { false },
        installModel = {},
        importModel = {},
        cancelModel = {},
        selectModel = {},
        deleteModel = {},
        instructionModel = {
            InstructionModelCardContent(state = instruction, install = {}, cancel = {}, delete = {})
        },
    )
}

// region Activity and delivery problems

@Composable
private fun ActivityStory(
    items: List<md.vox.android.capturedomain.CaptureHistoryItem>,
    transcripts: List<RecordingTranscriptionState> = emptyList(),
    filter: ActivityFilter = ActivityFilter.ALL,
) {
    ActivityScreen(
        items = items,
        transcripts = transcripts,
        isBusy = false,
        refresh = {},
        retry = {},
        repairAccess = {},
        openDetail = {},
        openTranscript = {},
        openCapture = {},
        nowEpochMillis = FIXED_TIME,
        captureRouteName = { activityStoryRoutes[it.requestID.take(8).toInt() % activityStoryRoutes.size] },
        loadCaptureDetail = { activityStoryDetail(it) },
        editRoute = {},
        initialFilter = filter,
    )
}

@Composable
private fun DeliveryProblemStory(item: md.vox.android.capturedomain.CaptureHistoryItem) {
    androidx.compose.foundation.layout.Box(
        androidx.compose.ui.Modifier
            .fillMaxSize()
            .background(Signal.colors.bg)
            .padding(top = 24.dp),
    ) {
        DeliveryProblemContent(
            item = item,
            routeName = "Tasks",
            loadDetail = { activityStoryDetail(it) },
            isBusy = false,
            retry = {},
            repairAccess = {},
            openDetail = {},
            editRoute = {},
        )
    }
}

private val activityStoryRoutes = listOf("Tasks", "Journal", "Meeting Notes", "Inbox")

private fun activityCapture(
    index: Int,
    state: md.vox.android.capturedomain.CaptureState,
    path: String? = null,
) = md.vox.android.capturedomain.CaptureHistoryItem(
    requestID = "%08d-2222-4222-8222-%012d".format(index, index),
    createdAtEpochMillis = FIXED_TIME - index * 600_000L,
    updatedAtEpochMillis = FIXED_TIME - index * 600_000L,
    state = state,
    attemptCount = 1,
    logicalPath = path,
    presetID = "33333333-3333-4333-8333-333333333333",
)

private fun activityStoryDetail(requestID: String) = md.vox.android.capturedomain.CaptureHistoryDetail(
    requestID = requestID,
    createdAtEpochMillis = FIXED_TIME - 600_000L,
    state = md.vox.android.capturedomain.CaptureState.NEEDS_USER_ACTION,
    capturedText = "- [ ] Renew passport\n- [ ] Call the dentist\n- [ ] Order printer ink",
    capturedURL = null,
    presetID = "33333333-3333-4333-8333-333333333333",
    logicalPath = "Tasks.md",
    preparedMarkdown = "- [ ] Renew passport\n- [ ] Call the dentist\n- [ ] Order printer ink\n",
)

private val activityStoryItems = listOf(
    activityCapture(4, md.vox.android.capturedomain.CaptureState.NEEDS_PERMISSION),
    activityCapture(5, md.vox.android.capturedomain.CaptureState.RETRYABLE_FAILURE),
    activityCapture(2, md.vox.android.capturedomain.CaptureState.COMMITTING),
    activityCapture(1, md.vox.android.capturedomain.CaptureState.COMPLETED, "Journal/2023-W46.md"),
    activityCapture(3, md.vox.android.capturedomain.CaptureState.COMPLETED, "Meetings/2023-11-14.md"),
    activityCapture(7, md.vox.android.capturedomain.CaptureState.COMPLETED, "Inbox/Book recs.md"),
)

private val activityStoryTranscripts = listOf(
    RecordingTranscriptionState(
        sessionID = "00000006-1111-4111-8111-000000000006",
        phase = RecordingTranscriptionPhase.PROCESSING,
        progress = 0.62f,
        durationMillis = 119_000L,
        recordedAtEpochMillis = FIXED_TIME - 300_000L,
    ),
)

// endregion
