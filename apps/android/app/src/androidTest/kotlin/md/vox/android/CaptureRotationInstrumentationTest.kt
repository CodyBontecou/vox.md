package md.vox.android

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.ui.CaptureUiState
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class CaptureRotationInstrumentationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun templateFieldsSurviveRestorationAndAdaptiveRelocation() {
        val restoration = StateRestorationTester(compose)
        var expanded by mutableStateOf(false)
        var saved: CaptureEntryTemplate? = null
        restoration.setContent {
            val editor = rememberEntryTemplateEditorState()
            MaterialTheme {
                // The same editor moves between list-only and list/detail branches.
                if (expanded) {
                    Box { templateDialog(editor) { saved = it } }
                } else {
                    templateDialog(editor) { saved = it }
                }
            }
        }
        compose.onNodeWithText("Name").performTextInput("Rotation template")
        compose.onNodeWithText("Prefix").performTextInput("- 🧪 {time} ")
        compose.onNodeWithText("Suffix").performTextInput("\n---")
        compose.runOnIdle { expanded = true }
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("Save").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals("Rotation template", saved?.name)
            assertEquals("- 🧪 {time} ", saved?.entryPrefix)
            assertEquals("\n---", saved?.entrySuffix)
        }
    }

    @Composable private fun templateDialog(editor: EntryTemplateEditorState, save: (CaptureEntryTemplate) -> Unit) {
        EntryTemplateEditorDialog(null, false, {}, save, null, editorState = editor)
    }

    @Test fun undoSurvivesRestorationAndRestoresThePreviousText() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent { VoxTheme { capture() } }
        compose.onNodeWithTag("capture-editor").performTextInput(" after")
        compose.onNodeWithContentDescription("Undo").assertIsEnabled()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithContentDescription("Undo").assertIsEnabled().performClick()
        compose.onNodeWithTag("capture-editor").assertTextEquals("Before")
    }

    @Test fun shortLandscapeWindowLeavesRoomForReadableDraft() {
        compose.setContent {
            VoxTheme {
                Box(Modifier.requiredSize(900.dp, 360.dp)) { capture() }
            }
        }
        compose.onNodeWithTag("capture-editor").assertHeightIsAtLeast(96.dp)
        compose.onNodeWithText("Hide draft preview").assertDoesNotExist()
        compose.onNodeWithContentDescription("Show detailed recording controls").assertExists()
    }

    @Composable private fun capture() {
        CaptureScreen(
            state = CaptureUiState(isLoading = false, draft = CaptureDraft("Before", null, 0)),
            recordingStatus = RecordingStatus(phase = RecordingPhase.IDLE),
            recordingTranscription = null,
            liveSpeech = null,
            onSubmit = { _, _, _ -> },
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
            requestEditorFocus = false,
        )
    }
}
