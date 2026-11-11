package md.vox.android

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.platformservices.LiveSpeechPhase
import md.vox.android.platformservices.LiveSpeechState
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.ui.CaptureUiState
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** The capture header's route pills, and recording in place on a phone (iOS parity). */
@RunWith(AndroidJUnit4::class)
class CaptureRoutePillsInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    private fun preset(id: String, name: String, isEnabled: Boolean = true) = CapturePreset(
        id = id,
        name = name,
        symbol = "square.and.pencil",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "{timestamp}",
        metadataFields = emptyList(),
        isEnabled = isEnabled,
    )

    private val active = preset("11111111-1111-4111-8111-111111111111", "Default")
    private val inbox = preset("22222222-2222-4222-8222-222222222222", "Inbox")
    private val disabled = preset("44444444-4444-4444-8444-444444444444", "Travel", isEnabled = false)
    private val collection = CapturePresetCollection(active.id, listOf(active, inbox, disabled))
    private val sessionID = "99999999-9999-4999-8999-999999999999"

    private fun render(
        draftText: String = "Draft text",
        recording: androidx.compose.runtime.MutableState<RecordingStatus> =
            mutableStateOf(RecordingStatus(phase = RecordingPhase.IDLE)),
        speech: androidx.compose.runtime.MutableState<LiveSpeechState?> = mutableStateOf(null),
        onSelectPreset: (String) -> Unit = {},
        openPresets: () -> Unit = {},
        cancelRecording: () -> Unit = {},
    ) {
        compose.setContent {
            VoxTheme {
                Box(Modifier.requiredSize(400.dp, 800.dp)) {
                    Surface {
                        CaptureScreen(
                            state = CaptureUiState(
                                isLoading = false,
                                destination = CaptureDestination("local", "Test Vault", "content://vault/root"),
                                draft = CaptureDraft(draftText, null, 0L),
                                presetCollection = collection,
                            ),
                            recordingStatus = recording.value,
                            recordingTranscription = null,
                            liveSpeech = speech.value,
                            onSubmit = { _, _, _ -> },
                            onSubmitRecording = { _, _, _, _, _, _, _ -> },
                            onDraftChanged = { _, _ -> },
                            onEntryTemplateSelected = {},
                            routePresets = collection.presets.filter { it.isEnabled },
                            onSelectPreset = onSelectPreset,
                            addDraftAttachment = { _, _, _, _ -> },
                            removeDraftAttachment = {},
                            presentNotice = {},
                            persistLocationUnavailableBehavior = { _, _ -> },
                            consumeAcceptedCapture = {},
                            consumeExternalDraft = {},
                            openHistory = {},
                            openSettings = {},
                            openPresets = openPresets,
                            startRecording = {},
                            pauseRecording = {},
                            resumeRecording = {},
                            stopRecording = {},
                            cancelRecording = cancelRecording,
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
            }
        }
    }

    @Test
    fun everyEnabledRouteIsAPillAndTappingOneSelectsIt() {
        var selected: String? = null
        render(onSelectPreset = { selected = it })

        compose.onNodeWithTag("capture-preset-selector").assertIsSelected()
        compose.onNodeWithContentDescription("Inbox").assertExists()
        compose.onNodeWithContentDescription("Travel").assertDoesNotExist()
        // No rail and no dropdown: the old toggle is gone.
        compose.onNodeWithContentDescription("Show pinned capture presets").assertDoesNotExist()

        compose.onNodeWithTag("capture-route-pill-${inbox.id}").performClick()
        compose.runOnIdle { assertEquals(inbox.id, selected) }
    }

    @Test
    fun selectedPillTapAndAnyLongPressOpenAllPresets() {
        var presetsOpened = 0
        var selected: String? = null
        render(onSelectPreset = { selected = it }, openPresets = { presetsOpened += 1 })

        compose.onNodeWithTag("capture-preset-selector").performClick()
        compose.onNodeWithTag("capture-route-pill-${inbox.id}").performTouchInput { longClick() }
        compose.runOnIdle {
            assertEquals(2, presetsOpened)
            assertEquals(null, selected)
        }
    }

    @Test
    fun phoneRecordsInPlaceWithLiveWordsAtTheEditorCursor() {
        val recording = mutableStateOf(RecordingStatus(sessionID = sessionID, phase = RecordingPhase.RECORDING))
        val speech = mutableStateOf<LiveSpeechState?>(
            LiveSpeechState(sessionID = sessionID, phase = LiveSpeechPhase.LISTENING, partialText = "spoken"),
        )
        var cancelled = 0
        render(recording = recording, speech = speech, cancelRecording = { cancelled += 1 })

        compose.onNodeWithTag("capture-live-recording-dock").assertExists()
        compose.onNodeWithTag("live-recording").assertDoesNotExist()
        compose.onNodeWithTag("capture-speak").assertDoesNotExist()
        compose.onNodeWithTag("capture-editor").assertTextEquals("Draft text spoken")

        compose.runOnIdle {
            speech.value = LiveSpeechState(
                sessionID = sessionID,
                phase = LiveSpeechPhase.LISTENING,
                committedText = "spoken words",
                partialText = "here",
            )
        }
        compose.onNodeWithTag("capture-editor").assertTextEquals("Draft text spoken words here")

        // Discard asks first, then takes the live words with it.
        compose.onNodeWithTag("capture-recording-discard").performClick()
        compose.onNodeWithTag("capture-recording-discard-confirm").performClick()
        compose.runOnIdle {
            assertEquals(1, cancelled)
            recording.value = RecordingStatus(phase = RecordingPhase.IDLE)
        }
        compose.onNodeWithTag("capture-editor").assertTextEquals("Draft text")
        compose.onNodeWithTag("capture-speak").assertExists()
    }
}
