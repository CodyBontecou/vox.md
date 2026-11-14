package md.vox.android

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTextInputSelection
import androidx.compose.ui.text.TextRange
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.test.platform.app.InstrumentationRegistry
import md.vox.android.capturedomain.*
import md.vox.android.platformservices.LiveSpeechPhase
import md.vox.android.platformservices.LiveSpeechState
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.CaptureViewModel
import md.vox.android.ui.VoxTheme
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import java.security.MessageDigest

/**
 * Live Notes end to end through the real composer and view model, with an in-memory vault:
 * the live transcript is written into a bound file while recording and removed again on
 * cancel, the final transcript lands where recording started, and Undo right after the first
 * write can never write the half-typed entry over the whole file.
 */
class LiveNoteComposerInstrumentationTest {
    @get:Rule val compose = createComposeRule()

    private val vault = CaptureDestination("22222222-2222-4222-8222-222222222222", "Vox Notes", "content://test/tree")
    private val daily = LiveNoteLocation(vault.id, vault.treeUri, "Daily/2026-11-13.md")
    private val existing = "# Log\n- 09:12 Standup\n"
    private val store = MemoryNotes()
    private val viewModels = ViewModelStore()
    private val session = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

    @After fun tearDown() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync { viewModels.clear() }
    }

    @Test fun liveTranscriptIsWrittenIntoTheBoundFileAndRemovedAgainOnCancel() {
        store.files[daily.relativePath] = existing
        val model = model(FakeRepository(store, daily))
        InstrumentationRegistry.getInstrumentation().runOnMainSync { model.openFile(daily, fromFiles = false) }
        compose.waitUntil(5_000) { model.state.value.liveNote.isBound }

        val recording = mutableStateOf(RecordingStatus())
        val speech = mutableStateOf<LiveSpeechState?>(null)
        val transcription = mutableStateOf<RecordingTranscriptionState?>(null)
        compose.setContent { VoxTheme { Composer(model, recording.value, speech.value, transcription.value) { transcription.value = transcription.value?.copy(addedToDraft = true) } } }
        compose.waitForIdle()
        // Caret after "# Log": speech must land there, not at the end of the file.
        compose.onNodeWithTag("capture-editor").performTextInputSelection(TextRange(5))

        recording.value = RecordingStatus(sessionID = session, phase = RecordingPhase.RECORDING)
        compose.waitForIdle()
        for (partial in listOf("call the", "call the building", "call the building office")) {
            speech.value = LiveSpeechState(session, LiveSpeechPhase.LISTENING, partialText = partial)
            compose.mainClock.advanceTimeBy(250)
        }
        compose.waitUntil(5_000) { store.files[daily.relativePath] == "# Log call the building office\n- 09:12 Standup\n" }
        compose.waitUntil(3_000) { model.state.value.liveNote.status == LiveNoteStatus.SAVED }

        // Cancelled: nothing was added to the editor, so the next save takes the preview out again.
        recording.value = RecordingStatus(sessionID = session, phase = RecordingPhase.DISCARDED)
        speech.value = null
        compose.waitUntil(5_000) { store.files[daily.relativePath] == existing }
        assertEquals(0, store.conflicts)

        // A second recording (each recording has its own session) that completes: the final
        // transcript replaces the preview at the start caret.
        val second = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        recording.value = RecordingStatus(sessionID = second, phase = RecordingPhase.RECORDING)
        compose.waitForIdle()
        speech.value = LiveSpeechState(second, LiveSpeechPhase.LISTENING, partialText = "draft words")
        compose.waitUntil(5_000) { store.files[daily.relativePath]?.contains("draft words") == true }
        recording.value = RecordingStatus(sessionID = second, phase = RecordingPhase.COMPLETED)
        transcription.value = RecordingTranscriptionState(second, RecordingTranscriptionPhase.PROCESSING, durationMillis = 21_000)
        compose.waitForIdle()
        transcription.value = RecordingTranscriptionState(second, RecordingTranscriptionPhase.COMPLETED, durationMillis = 21_000, transcript = "Final words")
        compose.waitUntil(5_000) { store.files[daily.relativePath] == "# Log Final words\n- 09:12 Standup\n" }
        assertEquals(0, store.conflicts)
    }

    @Test fun undoRightAfterTheFirstWriteNeverOverwritesTheFile() {
        store.files[daily.relativePath] = existing
        val model = model(FakeRepository(store, daily))
        compose.setContent { VoxTheme { Composer(model, RecordingStatus(), null, null) {} } }
        compose.waitUntil(5_000) { !model.state.value.isLoading }
        val editor = compose.onNodeWithTag("capture-editor")
        // Several edits, so the undo history holds half-typed states of the entry.
        for (chunk in listOf("Half", " typed", " entry")) {
            editor.performTextInput(chunk)
            compose.mainClock.advanceTimeBy(50)
        }
        compose.waitUntil(5_000) { model.state.value.liveNote.isBound }
        val bound = "# Log\n- 09:12 Standup\n- Half typed entry\n"
        assertEquals(bound, store.files[daily.relativePath])
        compose.waitUntil(3_000) { model.state.value.liveNote.localText == bound }

        // The whole file replaced the editor text: there is nothing to step back to.
        compose.onNodeWithContentDescription("Nothing to undo").assertIsNotEnabled().performClick()
        compose.mainClock.advanceTimeBy(3_000)
        Thread.sleep(1_500) // past the save debounce in real time
        compose.waitForIdle()
        assertEquals(bound, store.files[daily.relativePath])
        assertEquals(0, store.conflicts)
    }

    private fun model(repository: CaptureRepository): CaptureViewModel {
        var model: CaptureViewModel? = null
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            model = ViewModelProvider(viewModels, CaptureViewModel.factory(repository, store))[CaptureViewModel::class.java]
        }
        return requireNotNull(model)
    }

    @Composable private fun Composer(
        model: CaptureViewModel,
        recording: RecordingStatus,
        speech: LiveSpeechState?,
        transcription: RecordingTranscriptionState?,
        markAdded: () -> Unit,
    ) {
        val state by model.state.collectAsState()
        CaptureScreen(
            state = state,
            recordingStatus = recording,
            recordingTranscription = transcription,
            liveSpeech = speech,
            onSubmit = { _, _, _ -> },
            onSubmitRecording = { _, _, _, _, _, _, _ -> },
            onDraftChanged = model::updateDraft,
            onEntryTemplateSelected = {},
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
            markRecordingAdded = markAdded,
            exportRecordingAudio = { null },
            frozenRecordingPreset = { null },
            requestEditorFocus = false,
            onStartLiveNote = model::startLiveNote,
            onNewNote = model::newLiveNote,
        )
    }

    /** In-memory vault with the same version-checked replace semantics as the SAF store. */
    private class MemoryNotes : LiveNoteFileStore {
        val files = java.util.concurrent.ConcurrentHashMap<String, String>()
        @Volatile var writes = 0
        @Volatile var conflicts = 0

        override suspend fun read(location: LiveNoteLocation): LiveNoteReadResult =
            files[location.relativePath]?.let { LiveNoteReadResult.Found(LiveNoteFile(location, it, version(it))) } ?: LiveNoteReadResult.Missing

        override suspend fun replace(location: LiveNoteLocation, text: String, expected: LiveNoteVersion?): LiveNoteWriteResult {
            val current = files[location.relativePath]
            if (current == null && expected != null) return LiveNoteWriteResult.Missing
            if (current != null && (expected == null || !version(current).sameContentAs(expected))) {
                conflicts += 1
                return LiveNoteWriteResult.Changed(LiveNoteFile(location, current, version(current)))
            }
            files[location.relativePath] = text
            writes += 1
            return LiveNoteWriteResult.Written(version(text))
        }

        override suspend fun createCopy(location: LiveNoteLocation, text: String): LiveNoteCopyResult {
            val copy = location.sibling(LiveNotePlan.copyName(location.fileName, emptySet()))
            files[copy.relativePath] = text
            return LiveNoteCopyResult.Created(copy, version(text))
        }

        fun version(text: String): LiveNoteVersion {
            val bytes = text.toByteArray()
            return LiveNoteVersion(MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }, bytes.size.toLong())
        }
    }

    /** Daily-log route whose submit appends "- <text>" to the daily file, like the real rolling-note commit. */
    private class FakeRepository(private val notes: MemoryNotes, private val daily: LiveNoteLocation) : CaptureRepository {
        private val preset = CapturePreset(
            id = "11111111-1111-4111-8111-111111111111", name = "Daily log", symbol = "calendar", revision = 1,
            logicalFolder = "Daily", noteNameTemplate = "{date}.md", metadataFields = emptyList(),
            noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE,
        )
        private var draft = CaptureDraft("", null, 0)
        private var liveNote: LiveNoteSession? = null
        private val destination = CaptureDestination(daily.destinationID, "Vox Notes", daily.treeUri)

        override suspend fun currentDestination() = destination
        override suspend fun saveDestination(treeUri: String, displayName: String) = destination
        override suspend fun currentDraft() = draft
        override suspend fun saveDraft(text: String, url: String?, captureSource: String) = CaptureDraft(text, url, 0).also { draft = it }
        override suspend fun addDraftAttachment(contentUri: String, displayName: String?, mediaType: String?, includeInMarkdown: Boolean) = draft
        override suspend fun prepareVoiceDraft(text: String, url: String?, originRecordingID: String, audioContentUri: String?, audioDisplayName: String?, frozenPreset: CapturePreset?) = draft
        override suspend fun removeDraftAttachment(attachmentID: String) = draft
        override suspend fun captureBarConfiguration() = CaptureBarConfiguration()
        override suspend fun saveCaptureBarConfiguration(configuration: CaptureBarConfiguration) = configuration
        override suspend fun presetQuickAccessRailExpanded() = false
        override suspend fun setPresetQuickAccessRailExpanded(expanded: Boolean) {}
        override suspend fun capturePresets() = CapturePresetCollection(preset.id, listOf(preset))
        override suspend fun selectCapturePreset(presetID: String) = capturePresets()
        override suspend fun saveCapturePreset(preset: CapturePreset) = capturePresets()
        override suspend fun deleteCapturePreset(presetID: String) = capturePresets()
        override suspend fun entryTemplates() = emptyList<CaptureEntryTemplate>()
        override suspend fun saveEntryTemplate(template: CaptureEntryTemplate) = emptyList<CaptureEntryTemplate>()
        override suspend fun deleteEntryTemplate(templateID: String) = emptyList<CaptureEntryTemplate>()
        override suspend fun setDraftEntryTemplateOverride(templateID: String?) = draft
        override suspend fun submit(text: String, url: String?, locationOutcome: CaptureLocationOutcome): CaptureSubmitResult {
            val current = notes.files[daily.relativePath].orEmpty()
            notes.files[daily.relativePath] = current + "- " + text.trimEnd() + "\n"
            draft = CaptureDraft("", null, 0)
            return CaptureSubmitResult.Delivered("33333333-3333-4333-8333-333333333333", noteLocation = daily)
        }
        override suspend fun submitRecording(text: String, url: String?, originRecordingID: String, audioContentUri: String?, audioDisplayName: String?, frozenPreset: CapturePreset, captureSource: String, locationOutcome: CaptureLocationOutcome) =
            CaptureSubmitResult.InvalidInput("unused")
        override suspend fun retry(requestID: String) = CaptureSubmitResult.InvalidInput("unused")
        override suspend fun reconcile() = emptyList<CaptureHistoryItem>()
        override suspend fun history() = emptyList<CaptureHistoryItem>()
        override suspend fun historyDetail(requestID: String): CaptureHistoryDetail? = null
        override suspend fun deleteCompletedHistory(requestIDs: Set<String>) = 0
        override suspend fun activityStats() = ActivityStats.Empty
        override suspend fun recordCompletedRecordings(recordings: List<CompletedRecordingActivity>) = ActivityStats.Empty
        override suspend fun drainPending(maxItems: Int) = CaptureDrainSummary(0, 0, 0, 0, 0)
        override suspend fun liveNoteSession() = liveNote
        override suspend fun saveLiveNoteSession(session: LiveNoteSession) { liveNote = session }
    }
}
