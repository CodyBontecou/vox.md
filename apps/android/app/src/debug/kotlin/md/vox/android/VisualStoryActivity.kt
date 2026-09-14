package md.vox.android

import android.os.Bundle
import android.graphics.Color
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.activity.compose.setContent
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.platformservices.LiveSpeechState
import md.vox.android.platformservices.LiveSpeechPhase
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.platformservices.TranscriptionUsageState
import md.vox.android.ui.CaptureUiState
import md.vox.android.ui.VoxTheme

/** Debug-only deterministic stories for cross-platform visual review and screenshot regression. */
class VisualStoryActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val story = intent.getStringExtra(EXTRA_STORY) ?: STORY_CAPTURE
        val dark = intent.getBooleanExtra(EXTRA_DARK, true)
        val systemBarStyle = if (dark) {
            SystemBarStyle.dark(Color.TRANSPARENT)
        } else {
            SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
        }
        enableEdgeToEdge(statusBarStyle = systemBarStyle, navigationBarStyle = systemBarStyle)
        setContent {
            VoxTheme(darkTheme = dark) {
                androidx.compose.foundation.layout.Box(
                    Modifier.semantics { testTagsAsResourceId = true },
                ) {
                    VisualParityStory(story)
                }
            }
        }
    }

    companion object {
        const val EXTRA_STORY = "story"
        const val EXTRA_DARK = "dark"
        const val STORY_CAPTURE = "01-quick-capture"
        const val STORY_HISTORY = "02-history"
        const val STORY_SETTINGS = "03-settings"
        const val STORY_MODELS = "04-models"
        const val STORY_PRESETS = "05-capture-presets"
        const val STORY_APP_LANGUAGE = "06-app-language"
        const val STORY_LIVE_RECORDING = "07-live-recording"
        const val STORY_VAULT_REPAIR = "08-vault-repair"
        const val STORY_HISTORY_EMPTY = "09-history-empty"
        const val STORY_HISTORY_FOLDER_REPAIR = "10-history-folder-repair"
        const val STORY_RECORDING_PAUSED = "11-recording-paused"
        const val STORY_RECORDING_FAILED = "12-recording-failed"
        const val STORY_UPGRADE_PENDING = "13-upgrade-pending"
        const val STORY_UPGRADE_ACTIVE = "14-upgrade-active"
        const val STORY_LOADING = "15-loading"
        const val STORY_UPGRADE_QUOTA_REACHED = "16-upgrade-quota-reached"
        const val STORY_UPGRADE_OFFLINE = "17-upgrade-offline"
        const val STORY_RECORDING_QUOTA_REACHED = "18-recording-quota-reached"
        const val STORY_RECORDING_INTERRUPTED = "19-recording-interrupted"
        const val STORY_HISTORY_UNKNOWN_OUTCOME = "20-history-unknown-outcome"
        const val STORY_HISTORY_PERMANENT_FAILURE = "21-history-permanent-failure"
        const val STORY_PRESET_RAIL = "22-preset-rail"
    }
}

@androidx.compose.runtime.Composable
internal fun VisualParityStory(story: String) {
    when (story) {
        VisualStoryActivity.STORY_CAPTURE -> CaptureStory()
        VisualStoryActivity.STORY_LIVE_RECORDING -> CaptureStory(recordingPhase = RecordingPhase.RECORDING)
        VisualStoryActivity.STORY_HISTORY -> HistoryStory()
        VisualStoryActivity.STORY_SETTINGS -> SettingsStory()
        VisualStoryActivity.STORY_MODELS -> ModelsScreen(navigateBack = {})
        VisualStoryActivity.STORY_PRESETS -> PresetsStory()
        VisualStoryActivity.STORY_APP_LANGUAGE -> AppLanguageSettingsScreen(navigateBack = {})
        VisualStoryActivity.STORY_VAULT_REPAIR -> VaultSetupScreen(
            notice = "Folder access changed. Your capture is saved locally; choose the folder again to continue.",
            onChooseFolder = {},
        )
        VisualStoryActivity.STORY_HISTORY_EMPTY -> EmptyHistoryStory()
        VisualStoryActivity.STORY_HISTORY_FOLDER_REPAIR -> FolderRepairHistoryStory()
        VisualStoryActivity.STORY_RECORDING_PAUSED -> CaptureStory(recordingPhase = RecordingPhase.PAUSED)
        VisualStoryActivity.STORY_RECORDING_FAILED -> CaptureStory(
            recordingPhase = RecordingPhase.COMPLETED,
            recordingTranscription = RecordingTranscriptionState(
                sessionID = RECORDING_ID,
                phase = RecordingTranscriptionPhase.FAILED,
                modelID = "ggml-small",
                modelName = "Whisper Small",
                durationMillis = 42_000,
                recordedAtEpochMillis = FIXED_TIME,
                failureCode = "modelNotInstalled",
            ),
        )
        VisualStoryActivity.STORY_UPGRADE_PENDING -> UpgradeStory(VoxEntitlement.PENDING)
        VisualStoryActivity.STORY_UPGRADE_ACTIVE -> UpgradeStory(VoxEntitlement.UNLIMITED)
        VisualStoryActivity.STORY_LOADING -> LoadingScreen()
        VisualStoryActivity.STORY_UPGRADE_QUOTA_REACHED -> UpgradeStory(
            entitlement = VoxEntitlement.FREE,
            captureCount = 10,
            transcriptionUsedMillis = 15 * 60_000L,
        )
        VisualStoryActivity.STORY_UPGRADE_OFFLINE -> UpgradeStory(
            entitlement = VoxEntitlement.FREE,
            connectionPhase = BillingConnectionPhase.UNAVAILABLE,
            lastOutcome = BillingActionOutcome.UNAVAILABLE,
            productAvailable = false,
            formattedPrice = null,
        )
        VisualStoryActivity.STORY_RECORDING_QUOTA_REACHED -> CaptureStory(
            recordingPhase = RecordingPhase.COMPLETED,
            recordingTranscription = RecordingTranscriptionState(
                sessionID = RECORDING_ID,
                phase = RecordingTranscriptionPhase.FAILED,
                modelID = "ggml-small",
                modelName = "Whisper Small",
                durationMillis = 42_000,
                recordedAtEpochMillis = FIXED_TIME,
                failureCode = "transcriptionQuotaReached",
            ),
        )
        VisualStoryActivity.STORY_RECORDING_INTERRUPTED -> CaptureStory(
            recordingPhase = RecordingPhase.INTERRUPTED,
        )
        VisualStoryActivity.STORY_HISTORY_UNKNOWN_OUTCOME -> HistoryStateStory(
            state = CaptureState.UNKNOWN_OUTCOME,
            requestID = "88888888-8888-4888-8888-888888888888",
            title = "Launch summary",
            snippet = "Vox.md is checking whether the provider committed the note before retrying.",
        )
        VisualStoryActivity.STORY_HISTORY_PERMANENT_FAILURE -> HistoryStateStory(
            state = CaptureState.PERMANENT_FAILURE,
            requestID = "99999999-9999-4999-8999-999999999999",
            title = "Client debrief",
            snippet = "The provider rejected this note. The original capture remains available for recovery.",
        )
        VisualStoryActivity.STORY_PRESET_RAIL -> CaptureStory(
            presets = railStoryPresets,
            isPresetRailExpanded = true,
        )
        else -> Text("Unknown visual story: $story")
    }
}

@androidx.compose.runtime.Composable
private fun CaptureStory(
    recordingPhase: RecordingPhase = RecordingPhase.IDLE,
    recordingTranscription: RecordingTranscriptionState? = null,
    presets: CapturePresetCollection = visualPresets,
    isPresetRailExpanded: Boolean = false,
) {
    val state = CaptureUiState(
        isLoading = false,
        destination = visualDestination,
        draft = CaptureDraft(
            text = "# Launch notes\n\n- [ ] Review final designs\n- [ ] Publish release notes\n\nMeeting ideas captured while they are fresh.",
            url = null,
            updatedAtEpochMillis = FIXED_TIME,
        ),
        presetCollection = presets,
        isPresetRailExpanded = isPresetRailExpanded,
    )
    val recordingStatus = if (recordingPhase != RecordingPhase.IDLE) {
        RecordingStatus(
            sessionID = RECORDING_ID,
            phase = recordingPhase,
            createdAtEpochMillis = FIXED_TIME,
            elapsedMillis = 42_000,
            chunkCount = 2,
        )
    } else {
        RecordingStatus(phase = RecordingPhase.IDLE)
    }
    CaptureScreen(
        state = state,
        recordingStatus = recordingStatus,
        recordingTranscription = recordingTranscription,
        liveSpeech = if (recordingPhase in setOf(RecordingPhase.RECORDING, RecordingPhase.PAUSED)) {
            LiveSpeechState(
                sessionID = RECORDING_ID,
                phase = if (recordingPhase == RecordingPhase.PAUSED) LiveSpeechPhase.PAUSED else LiveSpeechPhase.LISTENING,
                committedText = "Meeting ideas captured while they are fresh.",
                partialText = "Review the launch checklist",
            )
        } else null,
        onSubmit = { _, _, _ -> },
        onSubmitRecording = { _, _, _, _, _, _, _ -> },
        onDraftChanged = { _, _ -> },
        onEntryTemplateSelected = {},
        pinnedPresets = md.vox.android.capturedomain.CapturePresetQuickAccess.alternatePresets(presets),
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
        initialShowsVoiceCaptureDetails = recordingPhase != RecordingPhase.IDLE || recordingTranscription != null,
    )
}

@androidx.compose.runtime.Composable
private fun EmptyHistoryStory() {
    HistoryScreen(
        items = emptyList(),
        transcripts = emptyList(),
        isBusy = false,
        navigateBack = {},
        refresh = {},
        retry = {},
        repairAccess = {},
        openDetail = {},
        openTranscript = {},
        clearCompleted = {},
    )
}

@androidx.compose.runtime.Composable
private fun FolderRepairHistoryStory() {
    HistoryScreen(
        items = listOf(
            CaptureHistoryItem(
                requestID = "77777777-7777-4777-8777-777777777777",
                createdAtEpochMillis = FIXED_TIME - 7_200_000,
                updatedAtEpochMillis = FIXED_TIME - 3_600_000,
                state = CaptureState.NEEDS_PERMISSION,
                attemptCount = 1,
                title = "Interview follow-up",
                snippet = "The capture remains safe on this device.",
                logicalPath = "Inbox/Interview follow-up.md",
            ),
        ),
        transcripts = emptyList(),
        isBusy = false,
        navigateBack = {},
        refresh = {},
        retry = {},
        repairAccess = {},
        openDetail = {},
        openTranscript = {},
        clearCompleted = {},
    )
}

@androidx.compose.runtime.Composable
private fun HistoryStateStory(
    state: CaptureState,
    requestID: String,
    title: String,
    snippet: String,
) {
    HistoryScreen(
        items = listOf(
            CaptureHistoryItem(
                requestID = requestID,
                createdAtEpochMillis = FIXED_TIME - 7_200_000,
                updatedAtEpochMillis = FIXED_TIME - 3_600_000,
                state = state,
                attemptCount = 3,
                title = title,
                snippet = snippet,
                logicalPath = "Inbox/$title.md",
            ),
        ),
        transcripts = emptyList(),
        isBusy = false,
        navigateBack = {},
        refresh = {},
        retry = {},
        repairAccess = {},
        openDetail = {},
        openTranscript = {},
        clearCompleted = {},
    )
}

@androidx.compose.runtime.Composable
private fun UpgradeStory(
    entitlement: VoxEntitlement,
    connectionPhase: BillingConnectionPhase = BillingConnectionPhase.READY,
    lastOutcome: BillingActionOutcome? = if (entitlement == VoxEntitlement.PENDING) {
        BillingActionOutcome.PENDING
    } else {
        null
    },
    productAvailable: Boolean = true,
    formattedPrice: String? = "$9.99",
    captureCount: Int = 9,
    transcriptionUsedMillis: Long = 13 * 60_000L,
) {
    UpgradeScreen(
        billingState = BillingUiState(
            connectionPhase = connectionPhase,
            entitlement = entitlement,
            formattedPrice = formattedPrice,
            productAvailable = productAvailable,
            lastOutcome = lastOutcome,
        ),
        stats = ActivityStats(
            recordingCount = 4,
            captureCount = captureCount,
            recordedDurationMillis = 12 * 60_000L,
            attachmentCount = 3,
            lastSevenDays = emptyList(),
            captureSources = mapOf("app" to captureCount),
        ),
        transcriptionUsage = TranscriptionUsageState(usedMillis = transcriptionUsedMillis),
        navigateBack = {},
        purchase = {},
        restore = {},
    )
}

@androidx.compose.runtime.Composable
private fun HistoryStory() {
    HistoryScreen(
        items = listOf(
            CaptureHistoryItem(
                requestID = "11111111-1111-4111-8111-111111111111",
                createdAtEpochMillis = FIXED_TIME - 1_800_000,
                updatedAtEpochMillis = FIXED_TIME - 1_800_000,
                state = CaptureState.COMPLETED,
                attemptCount = 1,
                title = "Launch notes",
                snippet = "Review final designs and publish release notes.",
                logicalPath = "Projects/Launch notes.md",
            ),
            CaptureHistoryItem(
                requestID = "22222222-2222-4222-8222-222222222222",
                createdAtEpochMillis = FIXED_TIME - 7_200_000,
                updatedAtEpochMillis = FIXED_TIME - 3_600_000,
                state = CaptureState.RETRYABLE_FAILURE,
                attemptCount = 2,
                title = "Interview follow-up",
                snippet = "Capture is safe and ready to retry.",
                logicalPath = "Inbox/Interview follow-up.md",
            ),
        ),
        transcripts = listOf(
            RecordingTranscriptionState(
                sessionID = RECORDING_ID,
                phase = RecordingTranscriptionPhase.COMPLETED,
                progress = 1f,
                modelID = "ggml-small",
                modelName = "Whisper Small",
                languageTag = "en",
                durationMillis = 184_000,
                recordedAtEpochMillis = FIXED_TIME - 86_400_000,
                completedAtEpochMillis = FIXED_TIME - 86_000_000,
                transcript = "We agreed to publish the release notes on Friday.",
                cleanedTranscript = "Publish the release notes on Friday.",
                title = "Weekly planning",
                tags = listOf("meeting", "launch"),
                category = "Work",
                speakerCount = 2,
            ),
        ),
        isBusy = false,
        navigateBack = {},
        refresh = {},
        retry = {},
        repairAccess = {},
        openDetail = {},
        openTranscript = {},
        clearCompleted = {},
    )
}

@androidx.compose.runtime.Composable
private fun SettingsStory() {
    SettingsScreen(
        destination = visualDestination,
        navigateBack = {},
        chooseFolder = {},
        openPresets = {},
        openCaptureBar = {},
        openStats = {},
        openModels = {},
        openRecordingQueue = {},
        openAppLanguage = {},
        openDebugLog = {},
        openUpgrade = {},
        billingState = BillingUiState(
            connectionPhase = BillingConnectionPhase.READY,
            entitlement = VoxEntitlement.FREE,
            formattedPrice = "$9.99",
            productAvailable = true,
        ),
    )
}

@androidx.compose.runtime.Composable
private fun PresetsStory() {
    CapturePresetsScreen(
        collection = visualPresets,
        entryTemplates = listOf(
            CaptureEntryTemplate(
                id = "44444444-4444-4444-8444-444444444444",
                name = "Meeting bullet",
                entryPrefix = "- {time} ",
            ),
        ),
        isBusy = false,
        navigateBack = {},
        selectPreset = {},
        editPreset = {},
        createPreset = {},
        saveEntryTemplate = {},
        deleteEntryTemplate = {},
    )
}

private val visualDestination = CaptureDestination(
    id = "local",
    displayName = "Vox Notes",
    treeUri = "content://md.vox.android.visual/vault",
)

private val visualPresets = CapturePresetCollection(
    activePresetID = "33333333-3333-4333-8333-333333333333",
    presets = listOf(
        CapturePreset(
            id = "33333333-3333-4333-8333-333333333333",
            name = "Default",
            symbol = "waveform",
            revision = 1,
            logicalFolder = "Documents Override",
            noteNameTemplate = "{timestamp}",
            metadataFields = emptyList(),
            isPinned = true,
        ),
        CapturePreset(
            id = "55555555-5555-4555-8555-555555555555",
            name = "Meeting Notes",
            symbol = "work",
            revision = 1,
            logicalFolder = "Meetings",
            noteNameTemplate = "{date}-meeting",
            metadataFields = emptyList(),
        ),
    ),
)

private const val FIXED_TIME = 1_700_000_000_000L

/** Rail story fixtures: the active pin stays in the selector, disabled and unpinned presets stay off the rail. */
private val railStoryPresets = CapturePresetCollection(
    activePresetID = "33333333-3333-4333-8333-333333333333",
    presets = listOf(
        CapturePreset(
            id = "33333333-3333-4333-8333-333333333333",
            name = "Default",
            symbol = "waveform",
            revision = 1,
            logicalFolder = "Documents Override",
            noteNameTemplate = "{timestamp}",
            metadataFields = emptyList(),
            isPinned = true,
        ),
        CapturePreset(
            id = "55555555-5555-4555-8555-555555555555",
            name = "Meeting Notes",
            symbol = "work",
            revision = 1,
            logicalFolder = "Meetings",
            noteNameTemplate = "{date}-meeting",
            metadataFields = emptyList(),
            isPinned = true,
        ),
        CapturePreset(
            id = "66666666-6666-4666-8666-666666666666",
            name = "Journal",
            symbol = "favorite",
            emoji = "📓",
            revision = 1,
            logicalFolder = "Journal",
            noteNameTemplate = "{date}",
            metadataFields = emptyList(),
            isPinned = true,
        ),
        CapturePreset(
            id = "77777777-7777-4777-8777-777777777777",
            name = "Tasks",
            symbol = "",
            revision = 1,
            logicalFolder = "Tasks",
            noteNameTemplate = "{date}-tasks",
            metadataFields = emptyList(),
            isPinned = true,
        ),
        CapturePreset(
            id = "88888888-8888-4888-8888-888888888888",
            name = "Travel",
            symbol = "lightbulb",
            revision = 1,
            logicalFolder = "Travel",
            noteNameTemplate = "{date}-travel",
            metadataFields = emptyList(),
            isEnabled = false,
            isPinned = true,
        ),
    ),
)
private const val RECORDING_ID = "66666666-6666-4666-8666-666666666666"
