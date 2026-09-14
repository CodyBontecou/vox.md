package md.vox.android

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.material3.Surface
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.capturedomain.CaptureAttachment
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.CaptureUiState
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EntryPointUiInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun mainAppQuickCaptureAcceptsTextAndDispatchesSend() {
        var submittedText: String? = null
        renderCapture(
            state = state(CaptureDraft("", null, 0)),
            onSubmit = { text, _ -> submittedText = text },
        )

        compose.onNodeWithContentDescription("Capture Text").performTextInput("Main app capture")
        compose.onNodeWithContentDescription("Send capture").performClick()
        compose.runOnIdle { assertEquals("Main app capture", submittedText) }
    }

    @Test
    fun quickCaptureExposesAOneShotEntryTemplateOverride() {
        val template = CaptureEntryTemplate(
            id = "22222222-2222-4222-8222-222222222222",
            name = "Meeting bullet",
            entryPrefix = "- {time} ",
        )
        var selected: String? = null
        compose.setContent {
            VoxTheme {
                CaptureScreen(
                    state = state(CaptureDraft("Draft", null, 0)).copy(entryTemplates = listOf(template)),
                    recordingStatus = RecordingStatus(phase = RecordingPhase.IDLE),
                    recordingTranscription = null,
                    liveSpeech = null,
                    onSubmit = { _, _, _ -> },
                    onSubmitRecording = { _, _, _, _, _, _, _ -> },
                    onDraftChanged = { _, _ -> },
                    onEntryTemplateSelected = { selected = it },
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
                    frozenRecordingPreset = { null },
                )
            }
        }

        compose.onNodeWithText("Preset Default").performClick()
        compose.onNodeWithText("Meeting bullet").performClick()
        compose.runOnIdle { assertEquals(template.id, selected) }
    }

    @Test
    fun deepLinkIsNormalizedIntoTheNativeCaptureReviewUi() {
        val presetID = "22222222-2222-4222-8222-222222222222"
        val request = requireNotNull(
            ExternalCaptureRequestParser.parse(
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("voxboard://capture?text=Deep%20note&url=https%3A%2F%2Fexample.com%2Fstory&preset=$presetID"),
                ),
            ),
        )
        var consumed = 0
        renderCapture(
            state = state(
                CaptureDraft(request.text, request.url, 1, captureSource = request.captureSource),
                pendingExternalDraftID = request.correlationID,
            ),
            consumeExternalDraft = { consumed += 1 },
        )

        compose.onNodeWithContentDescription("Capture Text").assertTextContains("Deep note")
        compose.onNodeWithText("https://example.com/story").assertExists()
        compose.runOnIdle {
            assertEquals(presetID, request.presetID)
            assertEquals("shortcut", request.captureSource)
            assertEquals(ExternalCaptureAction.REVIEW, request.action)
            assertEquals(1, consumed)
        }
    }

    @Test
    fun shareAndFileIntentsKeepTextAndEveryAdmittedAttachmentForReview() {
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "*/*"
            putCharSequenceArrayListExtra(Intent.EXTRA_TEXT, arrayListOf("Shared text", "Second paragraph"))
            putParcelableArrayListExtra(
                Intent.EXTRA_STREAM,
                arrayListOf(Uri.parse("content://sender/one.png"), Uri.parse("content://sender/two.pdf")),
            )
        }
        val request = requireNotNull(ExternalCaptureRequestParser.parse(intent))
        val attachments = request.attachmentUris.mapIndexed { index, uri ->
            CaptureAttachment(
                id = "attachment-$index",
                displayName = if (index == 0) "Photo.png" else "Document.pdf",
                vaultFileName = if (index == 0) "photo.png" else "document.pdf",
                mediaType = if (index == 0) "image/png" else "application/pdf",
                byteCount = 10,
                sha256 = "0".repeat(64),
            )
        }
        renderCapture(
            state = state(
                CaptureDraft(
                    text = request.text,
                    url = request.url,
                    updatedAtEpochMillis = 1,
                    captureSource = request.captureSource,
                    attachments = attachments,
                ),
                pendingExternalDraftID = request.correlationID,
            ),
        )

        compose.onNodeWithContentDescription("Capture Text").assertTextContains("Shared text\n\nSecond paragraph")
        compose.onNodeWithText("Photo.png").assertExists()
        compose.onNodeWithText("Document.pdf").assertExists()
        compose.runOnIdle {
            assertEquals("share", request.captureSource)
            assertEquals(2, request.attachmentUris.size)
        }
    }

    @Test
    fun shortcutWidgetQuickSettingsAndVoiceIntentsMapToTheExpectedNativeActions() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val shortcut = requireNotNull(ExternalCaptureRequestParser.parse(CaptureEntryIntents.capture(context, "shortcut")))
        val widget = requireNotNull(ExternalCaptureRequestParser.parse(CaptureEntryIntents.capture(context, "widget")))
        val widgetVoice = requireNotNull(ExternalCaptureRequestParser.parse(CaptureEntryIntents.record(context, "widget")))
        val quickSettings = requireNotNull(ExternalCaptureRequestParser.parse(CaptureEntryIntents.capture(context, "quick-settings")))
        val shortcutVoice = requireNotNull(ExternalCaptureRequestParser.parse(CaptureEntryIntents.record(context, "shortcut")))

        assertEquals("shortcut", shortcut.captureSource)
        assertEquals(ExternalCaptureAction.REVIEW, shortcut.action)
        assertEquals("widget", widget.captureSource)
        assertEquals(ExternalCaptureAction.REVIEW, widget.action)
        assertEquals("widget", widgetVoice.captureSource)
        assertEquals(ExternalCaptureAction.RECORD, widgetVoice.action)
        assertEquals("Quick Settings", quickSettings.sourceLabel)
        assertEquals(ExternalCaptureAction.REVIEW, quickSettings.action)
        assertEquals("Shortcut", shortcutVoice.sourceLabel)
        assertEquals(ExternalCaptureAction.RECORD, shortcutVoice.action)
    }

    @Test
    fun recordingQueueExposesTheNativeAudioVideoImportAction() {
        var imports = 0
        compose.setContent {
            VoxTheme {
                Surface {
                    RecordingQueueImportAction(enabled = true, isImporting = false) { imports += 1 }
                }
            }
        }
        compose.onNodeWithText("Import Audio or Video").performClick()
        compose.runOnIdle { assertEquals(1, imports) }
    }

    @Test
    fun quickCaptureRemainsAvailableWhileAnEarlierRecordingProcesses() {
        var submitted: String? = null
        compose.setContent {
            VoxTheme {
                CaptureScreen(
                    state = state(CaptureDraft("", null, 0)),
                    recordingStatus = RecordingStatus(
                        sessionID = "33333333-3333-4333-8333-333333333333",
                        phase = RecordingPhase.COMPLETED,
                        createdAtEpochMillis = 1_700_000_000_000,
                        elapsedMillis = 4_000,
                        chunkCount = 1,
                    ),
                    recordingTranscription = RecordingTranscriptionState(
                        sessionID = "33333333-3333-4333-8333-333333333333",
                        phase = RecordingTranscriptionPhase.PROCESSING,
                        progress = 0.5f,
                    ),
                    liveSpeech = null,
                    onSubmit = { text, _, _ -> submitted = text },
                    onSubmitRecording = { _, _, _, _, _, _, _ -> },
                    onDraftChanged = { _, _ -> },
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
                    markRecordingAdded = {},
                    exportRecordingAudio = { null },
                    frozenRecordingPreset = { null },
                )
            }
        }

        compose.onNodeWithContentDescription("Capture Text").performTextInput("Next capture")
        compose.onNodeWithContentDescription("Send capture").performClick()
        compose.runOnIdle { assertEquals("Next capture", submitted) }
    }

    private fun renderCapture(
        state: CaptureUiState,
        onSubmit: (String, String?) -> Unit = { _, _ -> },
        consumeExternalDraft: () -> Unit = {},
    ) {
        compose.setContent {
            VoxTheme {
                CaptureScreen(
                    state = state,
                    recordingStatus = RecordingStatus(phase = RecordingPhase.IDLE),
                    recordingTranscription = null,
                    liveSpeech = null,
                    onSubmit = { text, url, _ -> onSubmit(text, url) },
                    onSubmitRecording = { _, _, _, _, _, _, _ -> },
                    onDraftChanged = { _, _ -> },
                    onEntryTemplateSelected = {},
                    addDraftAttachment = { _, _, _, _ -> },
                    removeDraftAttachment = {},
                    presentNotice = {},
                    persistLocationUnavailableBehavior = { _, _ -> },
                    consumeAcceptedCapture = {},
                    consumeExternalDraft = consumeExternalDraft,
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
                    frozenRecordingPreset = { null },
                )
            }
        }
    }

    private fun state(draft: CaptureDraft, pendingExternalDraftID: String? = null): CaptureUiState {
        val preset = CapturePreset(
            id = "11111111-1111-4111-8111-111111111111",
            name = "Default",
            symbol = "square.and.pencil",
            revision = 1,
            logicalFolder = "Inbox",
            noteNameTemplate = "{timestamp}",
            metadataFields = emptyList(),
        )
        return CaptureUiState(
            isLoading = false,
            destination = CaptureDestination("local", "Test Vault", "content://vault/root"),
            draft = draft,
            presetCollection = CapturePresetCollection(preset.id, listOf(preset)),
            pendingExternalDraftID = pendingExternalDraftID,
        )
    }
}
