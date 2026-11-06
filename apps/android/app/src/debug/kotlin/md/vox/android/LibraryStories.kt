package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import md.vox.android.capturedomain.CaptureAttachment
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureHistoryDetail
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureTextProcessingOutcome
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.Signal

/**
 * Signal redesign stories for the library area. Story ids use the
 * "library-" prefix; launch with
 * `adb shell am start -n md.vox.android/.VisualStoryActivity --es story <id> --ez dark <bool>`.
 * Returns false when [story] is not one of these.
 */
@Composable
internal fun LibraryStories(story: String): Boolean {
    when (story) {
        // History list
        "library-history" -> LibraryHistoryStory(libraryMixedCaptures, libraryTranscriptsAllPhases.take(2))
        "library-history-empty" -> LibraryHistoryStory(emptyList(), emptyList())
        "library-history-capture-states" -> LibraryHistoryStory(libraryCapturesAllStates, emptyList())
        "library-history-transcript-phases" -> LibraryHistoryStory(emptyList(), libraryTranscriptsAllPhases)
        "library-history-filter-captures" -> LibraryHistoryStory(
            libraryMixedCaptures,
            libraryTranscriptsAllPhases,
            initialKind = UnifiedHistoryKind.CAPTURES,
        )
        "library-history-filter-transcripts" -> LibraryHistoryStory(
            libraryMixedCaptures,
            libraryTranscriptsAllPhases,
            initialKind = UnifiedHistoryKind.TRANSCRIPTS,
        )
        "library-history-needs-attention" -> LibraryHistoryStory(
            libraryMixedCaptures,
            libraryTranscriptsAllPhases,
            initialNeedsAttentionOnly = true,
        )
        "library-history-search" -> LibraryHistoryStory(
            libraryMixedCaptures,
            libraryTranscriptsAllPhases,
            initialQuery = "launch",
        )
        "library-history-no-match" -> LibraryHistoryStory(
            libraryMixedCaptures,
            libraryTranscriptsAllPhases,
            initialQuery = "zebra",
        )
        "library-history-busy" -> LibraryHistoryStory(libraryMixedCaptures, emptyList(), isBusy = true)
        "library-history-long-text" -> LibraryHistoryStory(libraryLongTextCaptures, listOf(libraryLongTranscript))
        "library-history-grouped" -> LibraryHistoryStory(
            libraryMixedCaptures + libraryCapture(100, CaptureState.RETRYABLE_FAILURE, "Design crit", "Keyboard picker needs bigger targets"),
            libraryTranscriptsAllPhases.take(3),
            withRoutes = true,
        )
        "library-history-route-filter" -> LibraryHistoryStory(
            libraryMixedCaptures,
            libraryTranscriptsAllPhases.take(3),
            withRoutes = true,
            initialRoute = "Meeting Notes",
        )
        "library-history-read-only" -> LibraryHistoryStory(
            libraryMixedCaptures,
            libraryTranscriptsAllPhases.take(2),
            withRoutes = true,
            isReadOnly = true,
        )
        "library-history-clear-confirm" -> LibraryHistoryStory(
            libraryMixedCaptures,
            emptyList(),
            initialShowsClearConfirmation = true,
        )

        // Capture detail
        "library-capture-detail-loading" -> LibraryCaptureDetailStory(detail = null, isLoading = true)
        "library-capture-detail-unavailable" -> LibraryCaptureDetailStory(detail = null)
        "library-capture-detail-loaded" -> LibraryCaptureDetailStory(libraryCompletedDetail)
        "library-capture-detail-deleting" -> LibraryCaptureDetailStory(libraryCompletedDetail, isDeleting = true)
        "library-capture-detail-delete-confirm" -> LibraryCaptureDetailStory(
            libraryCompletedDetail,
            initialShowsDeleteConfirmation = true,
        )
        "library-capture-detail-exported" -> LibraryCaptureDetailStory(
            libraryCompletedDetail,
            initialOperationMessage = voxUiText("%@ exported.", voxUiText("Markdown")),
        )
        "library-capture-detail-failed-delivery" -> LibraryCaptureDetailStory(libraryFailedDeliveryDetail)
        "library-capture-detail-transcript-tab" -> LibraryCaptureDetailStory(
            libraryCompletedDetail,
            initialTab = CaptureDetailTab.TRANSCRIPT,
        )
        "library-capture-detail-route-log" -> LibraryCaptureDetailStory(
            libraryCompletedDetail,
            initialTab = CaptureDetailTab.ROUTE_LOG,
        )
        "library-capture-detail-route-log-failed" -> LibraryCaptureDetailStory(
            libraryFailedDeliveryDetail,
            initialTab = CaptureDetailTab.ROUTE_LOG,
        )
        "library-capture-detail-permanent-failure" -> LibraryCaptureDetailStory(
            libraryFailedDeliveryDetail.copy(state = CaptureState.PERMANENT_FAILURE),
        )
        "library-capture-detail-needs-permission" -> LibraryCaptureDetailStory(
            libraryFailedDeliveryDetail.copy(state = CaptureState.NEEDS_PERMISSION),
        )

        // Transcript detail
        "library-transcript-completed" -> LibraryTranscriptDetailStory(libraryCompletedTranscript)
        "library-transcript-editing" -> LibraryTranscriptDetailStory(libraryCompletedTranscript, initialEditing = true)
        "library-transcript-exported" -> LibraryTranscriptDetailStory(
            libraryCompletedTranscript,
            initialOperationMessage = voxUiText("%@ exported.", "Markdown"),
        )
        "library-transcript-delete-confirm" -> LibraryTranscriptDetailStory(
            libraryCompletedTranscript,
            initialShowsDeleteConfirmation = true,
        )
        "library-transcript-preset-export" -> LibraryTranscriptDetailStory(
            libraryCompletedTranscript,
            withPresetExport = true,
        )
        "library-transcript-queued" -> LibraryTranscriptDetailStory(libraryTranscriptsAllPhases.phase(RecordingTranscriptionPhase.QUEUED))
        "library-transcript-processing" -> LibraryTranscriptDetailStory(libraryTranscriptsAllPhases.phase(RecordingTranscriptionPhase.PROCESSING))
        "library-transcript-finalizing" -> LibraryTranscriptDetailStory(libraryTranscriptsAllPhases.phase(RecordingTranscriptionPhase.FINALIZING))
        "library-transcript-failed" -> LibraryTranscriptDetailStory(libraryTranscriptsAllPhases.phase(RecordingTranscriptionPhase.FAILED))
        "library-transcript-discarded" -> LibraryTranscriptDetailStory(libraryTranscriptsAllPhases.phase(RecordingTranscriptionPhase.DISCARDED))
        "library-transcript-long-text" -> LibraryTranscriptDetailStory(libraryLongTranscript)
        "library-transcript-audio" -> LibraryTranscriptDetailStory(libraryCompletedTranscript, withAudio = true)
        "library-transcript-unavailable" -> LibraryTranscriptDetailStory(null)

        // Adaptive split panes
        "library-adaptive-placeholder" -> AdaptiveDetailPlaceholder(
            title = voxUiText("Select a history item"),
            detail = voxUiText("Capture details and private on-device transcripts open here."),
        )
        "library-adaptive-split" -> LibraryAdaptiveSplitStory(detail = null)
        "library-adaptive-split-detail" -> LibraryAdaptiveSplitStory(detail = libraryCompletedDetail)
        else -> return false
    }
    return true
}

private fun List<RecordingTranscriptionState>.phase(phase: RecordingTranscriptionPhase) = first { it.phase == phase }

@Composable
private fun LibraryHistoryStory(
    items: List<CaptureHistoryItem>,
    transcripts: List<RecordingTranscriptionState>,
    isBusy: Boolean = false,
    initialQuery: String = "",
    initialKind: UnifiedHistoryKind = UnifiedHistoryKind.ALL,
    initialNeedsAttentionOnly: Boolean = false,
    initialShowsClearConfirmation: Boolean = false,
    withRoutes: Boolean = false,
    initialRoute: String? = null,
    isReadOnly: Boolean = false,
) {
    HistoryScreen(
        items = items,
        transcripts = transcripts,
        isBusy = isBusy,
        navigateBack = {},
        refresh = {},
        retry = {},
        repairAccess = {},
        openDetail = {},
        openTranscript = {},
        clearCompleted = {},
        initialQuery = initialQuery,
        initialKind = initialKind,
        initialNeedsAttentionOnly = initialNeedsAttentionOnly,
        initialShowsClearConfirmation = initialShowsClearConfirmation,
        captureRouteName = { item -> if (withRoutes) libraryStoryRoute(item.requestID) else null },
        transcriptRouteName = { id -> if (withRoutes) libraryStoryRoute(id) else null },
        initialRoute = initialRoute,
        isReadOnly = isReadOnly,
        openPlans = {},
        nowEpochMillis = FIXED_TIME,
    )
}

private val libraryStoryRoutes = listOf("Meeting Notes", "Inbox", "Journal", "Tasks")

/** Deterministic route for a fixture ID so route chips and rows are stable across runs. */
internal fun libraryStoryRoute(id: String): String = libraryStoryRoutes[id.take(8).toInt() % libraryStoryRoutes.size]

@Composable
private fun LibraryCaptureDetailStory(
    detail: CaptureHistoryDetail?,
    isLoading: Boolean = false,
    isDeleting: Boolean = false,
    initialOperationMessage: VoxUiText? = null,
    initialShowsDeleteConfirmation: Boolean = false,
    initialTab: CaptureDetailTab = CaptureDetailTab.WRITTEN,
) {
    HistoryDetailScreen(
        detail = detail,
        isLoading = isLoading,
        isDeleting = isDeleting,
        navigateBack = {},
        delete = {},
        initialOperationMessage = initialOperationMessage,
        initialShowsDeleteConfirmation = initialShowsDeleteConfirmation,
        routeName = "Meeting Notes",
        retry = {},
        repairAccess = {},
        initialTab = initialTab,
    )
}

@Composable
private fun LibraryTranscriptDetailStory(
    state: RecordingTranscriptionState?,
    initialEditing: Boolean = false,
    initialOperationMessage: VoxUiText? = null,
    initialShowsDeleteConfirmation: Boolean = false,
    withPresetExport: Boolean = false,
    withAudio: Boolean = false,
) {
    TranscriptDetailScreen(
        state = state,
        preset = if (withPresetExport) {
            visualPresets.activePreset.copy(
                audioSaveMode = CaptureAudioSaveMode.OFF,
                exportSettings = CapturePresetExportSettings(usesCustomExportSettings = true, exportEnabled = true),
            )
        } else null,
        shareTranscript = {},
        exportTranscript = { _, _ -> },
        navigateBack = {},
        save = { _, _, _, _, _, _ -> true },
        delete = {},
        addToDraft = { _, _ -> },
        initialEditing = initialEditing,
        initialOperationMessage = initialOperationMessage,
        initialShowsDeleteConfirmation = initialShowsDeleteConfirmation,
        hasRetainedAudio = { withAudio },
    )
}

@Composable
private fun LibraryAdaptiveSplitStory(detail: CaptureHistoryDetail?) {
    Row(Modifier.fillMaxSize()) {
        Box(Modifier.weight(0.43f)) {
            LibraryHistoryStory(libraryMixedCaptures, libraryTranscriptsAllPhases.take(2))
        }
        Box(Modifier.width(1.dp).fillMaxHeight().background(Signal.colors.border))
        Box(Modifier.weight(0.57f)) {
            if (detail == null) {
                AdaptiveDetailPlaceholder(
                    title = voxUiText("Select a history item"),
                    detail = voxUiText("Capture details and private on-device transcripts open here."),
                )
            } else {
                LibraryCaptureDetailStory(detail)
            }
        }
    }
}

private fun libraryCapture(
    index: Int,
    state: CaptureState,
    title: String?,
    snippet: String?,
    path: String? = title?.let { "Inbox/$it.md" },
    source: String = "app",
    attachments: Int = 0,
): CaptureHistoryItem {
    val id = "%08d-0000-4000-8000-%012d".format(index, index)
    return CaptureHistoryItem(
        requestID = id,
        createdAtEpochMillis = FIXED_TIME - index * 900_000L,
        updatedAtEpochMillis = FIXED_TIME - index * 900_000L,
        state = state,
        attemptCount = if (state == CaptureState.COMPLETED) 1 else 2,
        title = title,
        snippet = snippet,
        logicalPath = path,
        captureSource = source,
        attachmentCount = attachments,
    )
}

private val libraryMixedCaptures = listOf(
    libraryCapture(1, CaptureState.COMPLETED, "Launch notes", "Review final designs and publish release notes.", "Projects/Launch notes.md"),
    libraryCapture(3, CaptureState.RETRYABLE_FAILURE, "Interview follow-up", "Capture is safe and ready to retry.", source = "share", attachments = 2),
    libraryCapture(5, CaptureState.NEEDS_PERMISSION, "Grocery run", "Oat milk, lemons, coffee beans.", source = "widget"),
    libraryCapture(7, CaptureState.COMPLETED, null, null, null),
)

private val libraryCapturesAllStates = CaptureState.entries.mapIndexed { index, state ->
    libraryCapture(
        index = index + 1,
        state = state,
        title = "Capture ${state.name.lowercase().replace('_', ' ')}",
        snippet = "Deterministic fixture for the ${state.name} state.",
        source = listOf("app", "share", "keyboard", "widget", "watch")[index % 5],
        attachments = index % 3,
    )
}

private val libraryLongTextCaptures = listOf(
    libraryCapture(
        2,
        CaptureState.UNKNOWN_OUTCOME,
        "A very long capture title that keeps going to check wrapping across two lines in the Library list",
        "This snippet is intentionally long so the row demonstrates how the excerpt is clamped to three lines " +
            "without pushing the metadata, status badge and actions out of the card on a narrow phone.",
        "Projects/Quarterly planning/Very long folder name/And an equally long note name for testing.md",
        source = "keyboard",
        attachments = 12,
    ),
)

private fun libraryTranscript(
    index: Int,
    phase: RecordingTranscriptionPhase,
    progress: Float = 0f,
    transcript: String? = null,
    cleaned: String? = null,
    title: String? = null,
    tags: List<String> = emptyList(),
    category: String? = null,
    speakers: Int = 0,
    failureCode: String? = null,
) = RecordingTranscriptionState(
    sessionID = "%08d-1111-4111-8111-%012d".format(index, index),
    phase = phase,
    progress = progress,
    modelID = "ggml-small",
    modelName = "Whisper Small",
    languageTag = "en",
    durationMillis = 30_000L + index * 47_000L,
    recordedAtEpochMillis = FIXED_TIME - index * 1_200_000L,
    completedAtEpochMillis = if (phase == RecordingTranscriptionPhase.QUEUED) null else FIXED_TIME - index * 1_100_000L,
    transcript = transcript,
    cleanedTranscript = cleaned,
    failureCode = failureCode,
    title = title,
    tags = tags,
    category = category,
    speakerCount = speakers,
)

private val libraryCompletedTranscript = libraryTranscript(
    index = 2,
    phase = RecordingTranscriptionPhase.COMPLETED,
    progress = 1f,
    transcript = "So we agreed to publish the release notes on Friday and to review the final designs on Thursday.",
    cleaned = "We agreed to publish the release notes on Friday and review the final designs on Thursday.",
    title = "Weekly planning",
    tags = listOf("meeting", "launch"),
    category = "Work",
    speakers = 2,
)

private val libraryTranscriptsAllPhases = listOf(
    libraryCompletedTranscript,
    libraryTranscript(4, RecordingTranscriptionPhase.PROCESSING, progress = 0.42f),
    libraryTranscript(6, RecordingTranscriptionPhase.QUEUED),
    libraryTranscript(8, RecordingTranscriptionPhase.FINALIZING, progress = 1f, transcript = "Draft words from the recording so far."),
    libraryTranscript(10, RecordingTranscriptionPhase.FAILED, failureCode = "modelNotInstalled"),
    libraryTranscript(12, RecordingTranscriptionPhase.DISCARDED),
)

private val libraryLongTranscript = libraryTranscript(
    index = 3,
    phase = RecordingTranscriptionPhase.COMPLETED,
    progress = 1f,
    transcript = List(14) {
        "This is a long dictated paragraph used to check how the transcript card handles wrapping and scrolling."
    }.joinToString(" "),
    title = "An unusually long transcript title that should wrap onto a second line gracefully",
    tags = listOf("research", "interviews", "follow-up", "quarterly-review", "customers"),
    category = "Customer research",
    speakers = 4,
)

private val libraryCompletedDetail = CaptureHistoryDetail(
    requestID = "11111111-1111-4111-8111-111111111111",
    createdAtEpochMillis = FIXED_TIME - 1_800_000,
    state = CaptureState.COMPLETED,
    capturedText = "- [ ] Review final designs\n- [ ] Publish release notes",
    capturedURL = "https://vox.md/changelog",
    presetID = "33333333-3333-4333-8333-333333333333",
    logicalPath = "Projects/Launch notes.md",
    preparedMarkdown = "## 10:42\n\n- [ ] Review final designs\n- [ ] Publish release notes\n\nhttps://vox.md/changelog\n",
    captureSource = "keyboard",
    attachments = listOf(
        CaptureAttachment(
            id = "a1",
            displayName = "whiteboard.jpg",
            vaultFileName = "whiteboard.jpg",
            mediaType = "image/jpeg",
            byteCount = 284_113,
            sha256 = "0".repeat(64),
        ),
    ),
    originalCapturedText = "review final designs and publish release notes",
    processingMode = CaptureProcessingMode.TODO_LIST,
    processingOutcome = CaptureTextProcessingOutcome.APPLIED,
)

private val libraryFailedDeliveryDetail = CaptureHistoryDetail(
    requestID = "22222222-2222-4222-8222-222222222222",
    createdAtEpochMillis = FIXED_TIME - 7_200_000,
    state = CaptureState.RETRYABLE_FAILURE,
    capturedText = "Follow up with the candidate about the take-home exercise.",
    capturedURL = null,
    presetID = "55555555-5555-4555-8555-555555555555",
    logicalPath = "Inbox/Interview follow-up.md",
    preparedMarkdown = null,
    captureSource = "share",
    processingMode = CaptureProcessingMode.CLEAN,
    processingOutcome = CaptureTextProcessingOutcome.MODEL_UNAVAILABLE,
    processingNotice = "The local model was unavailable, so the original text was kept.",
)
