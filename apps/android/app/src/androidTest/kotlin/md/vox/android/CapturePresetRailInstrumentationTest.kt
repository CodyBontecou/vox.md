package md.vox.android

import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.longClick
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CapturePresetQuickAccess
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.ui.CaptureUiState
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CapturePresetRailInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    private fun preset(id: String, name: String, isPinned: Boolean = false, isEnabled: Boolean = true) = CapturePreset(
        id = id,
        name = name,
        symbol = "square.and.pencil",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "{timestamp}",
        metadataFields = emptyList(),
        isEnabled = isEnabled,
        isPinned = isPinned,
    )

    private val active = preset("11111111-1111-4111-8111-111111111111", "Default")
    private val inbox = preset("22222222-2222-4222-8222-222222222222", "Inbox", isPinned = true)
    private val work = preset("33333333-3333-4333-8333-333333333333", "Work", isPinned = true)
    private val disabledPin = preset("44444444-4444-4444-8444-444444444444", "Travel", isPinned = true, isEnabled = false)
    private val unpinned = preset("55555555-5555-4555-8555-555555555555", "Tasks")

    private fun state(isPresetRailExpanded: Boolean, withPins: Boolean = true): CaptureUiState {
        val presets = if (withPins) listOf(active, inbox, work, disabledPin, unpinned) else listOf(active, unpinned)
        return CaptureUiState(
            isLoading = false,
            destination = CaptureDestination("local", "Test Vault", "content://vault/root"),
            draft = CaptureDraft("Draft text", null, 0L),
            presetCollection = CapturePresetCollection(active.id, presets),
            isPresetRailExpanded = isPresetRailExpanded,
        )
    }

    private fun render(
        isExpanded: androidx.compose.runtime.MutableState<Boolean>,
        withPins: androidx.compose.runtime.MutableState<Boolean> = androidx.compose.runtime.mutableStateOf(true),
        onSelectPreset: (String) -> Unit = {},
        openPresets: () -> Unit = {},
    ) {
        compose.setContent {
            VoxTheme {
                Surface {
                    val uiState = state(isExpanded.value, withPins.value)
                    CaptureScreen(
                        state = uiState,
                        recordingStatus = RecordingStatus(phase = RecordingPhase.IDLE),
                        recordingTranscription = null,
                        liveSpeech = null,
                        onSubmit = { _, _, _ -> },
                        onSubmitRecording = { _, _, _, _, _, _, _ -> },
                        onDraftChanged = { _, _ -> },
                        onEntryTemplateSelected = {},
                        pinnedPresets = CapturePresetQuickAccess.alternatePresets(
                            requireNotNull(uiState.presetCollection),
                        ),
                        isPresetRailExpanded = isExpanded.value,
                        togglePresetRail = { isExpanded.value = !isExpanded.value },
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
    }

    @Test
    fun selectorTapTogglesTheRailAndRailButtonsDispatchSelection() {
        val isExpanded = androidx.compose.runtime.mutableStateOf(false)
        var selected: String? = null
        render(isExpanded, onSelectPreset = { selected = it })

        // Collapsed: no rail controls; the selector is the only affordance.
        compose.onNodeWithContentDescription("Show pinned capture presets").assertExists()
        compose.onNodeWithContentDescription("Capture Preset Inbox").assertDoesNotExist()

        compose.onNodeWithTag("capture-preset-selector").performClick()
        compose.runOnIdle { assertTrue(isExpanded.value) }

        compose.onNodeWithContentDescription("Capture Preset Inbox").assertExists()
        compose.onNodeWithContentDescription("Capture Preset Work").assertExists()
        // The selector row already represents the active preset; the disabled
        // pin (Travel) and unpinned preset (Tasks) resolve off the rail.
        compose.onNodeWithContentDescription("Capture Preset Default").assertDoesNotExist()
        compose.onNodeWithContentDescription("Capture Preset Travel").assertDoesNotExist()
        compose.onNodeWithContentDescription("Capture Preset Tasks").assertDoesNotExist()

        compose.onNodeWithContentDescription("Capture Preset Inbox").performClick()
        compose.runOnIdle { assertEquals(inbox.id, selected) }

        // A second selector tap collapses the rail again.
        compose.onNodeWithContentDescription("Hide pinned capture presets").assertExists()
        compose.onNodeWithTag("capture-preset-selector").performClick()
        compose.runOnIdle { assertFalse(isExpanded.value) }
        compose.onNodeWithContentDescription("Capture Preset Inbox").assertDoesNotExist()
    }

    @Test
    fun selectorLongPressAlwaysOpensPresetsAndPlainTapFallsBackWithoutPins() {
        val isExpanded = androidx.compose.runtime.mutableStateOf(true)
        val withPins = androidx.compose.runtime.mutableStateOf(true)
        var presetsOpened = 0
        render(isExpanded, withPins, openPresets = { presetsOpened += 1 })

        compose.onNodeWithTag("capture-preset-selector").performTouchInput { longClick() }
        compose.runOnIdle { assertEquals(1, presetsOpened) }

        // No usable pins: tap keeps its ordinary navigation behavior and the
        // rail disappears even though it was expanded.
        compose.runOnIdle {
            withPins.value = false
            isExpanded.value = false
        }
        compose.onNodeWithTag("capture-preset-selector").performClick()
        compose.runOnIdle { assertEquals(2, presetsOpened) }
    }
}
