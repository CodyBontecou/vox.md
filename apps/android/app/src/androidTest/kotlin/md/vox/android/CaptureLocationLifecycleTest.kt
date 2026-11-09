package md.vox.android

import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Before
import md.vox.android.capturedomain.*
import md.vox.android.platformservices.*
import md.vox.android.ui.CaptureUiState
import md.vox.android.ui.VoxTheme
import kotlinx.coroutines.awaitCancellation
import org.junit.Rule
import org.junit.Test
import org.junit.Assert.assertEquals
import androidx.compose.ui.semantics.SemanticsActions

class CaptureLocationLifecycleTest {
    @get:Rule val compose = createComposeRule()
    @Before fun grantLocation() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        for (permission in listOf(android.Manifest.permission.ACCESS_FINE_LOCATION, android.Manifest.permission.ACCESS_COARSE_LOCATION)) {
            instrumentation.uiAutomation.grantRuntimePermission(instrumentation.targetContext.packageName, permission)
        }
    }
    private val route = CapturePresetEditorDraft.from(null).copy(name = "QA location").toPreset(1, emptyList()).copy(locationPolicy = CapturePresetLocationPolicy(isEnabled = true))

    @Test fun interruptedLocationLookupDoesNotLeaveTheRestoredComposerBusy() {
        val restoration = StateRestorationTester(compose)
        restoration.setContent { VoxTheme { capture { awaitCancellation() } } }
        compose.onNodeWithContentDescription("Send capture").performClick()
        compose.onNodeWithContentDescription("Sending capture").assertExists()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("capture-editor").assertTextEquals("Before")
        compose.onNodeWithContentDescription("Send capture").assertIsEnabled()
    }
    @Test fun unavailableDecisionSurvivesRotationAndCancelKeepsTheDraft() {
        val restoration = StateRestorationTester(compose)
        var lookups = 0
        restoration.setContent { VoxTheme { capture { lookups++; CurrentLocationResult.Unavailable } } }
        compose.onNodeWithContentDescription("Send capture").performClick()
        compose.onNodeWithText(locationUnavailableMessage(CaptureLocationUnavailableReason.UNAVAILABLE)).assertExists()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText(locationUnavailableMessage(CaptureLocationUnavailableReason.UNAVAILABLE)).assertExists()
        compose.onNodeWithText("Cancel").performClick()
        compose.onNodeWithTag("capture-editor").assertTextEquals("Before")
        compose.onNodeWithContentDescription("Send capture").assertIsEnabled()
        compose.runOnIdle { assertEquals(1, lookups) }
    }

    @Test fun locationLookupDisablesPresetAndDestinationChanges() {
        val other = route.copy(id = "bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb", name = "Other")
        compose.setContent { VoxTheme { capture(pinned = listOf(other)) { awaitCancellation() } } }
        compose.onNodeWithContentDescription("Send capture").performClick()
        compose.onNodeWithContentDescription("Sending capture").assertExists()
        compose.onNodeWithTag("capture-preset-rail-${other.id}").assertIsNotEnabled()
        compose.onNodeWithTag("capture-preset-selector").assertIsNotEnabled()
        compose.onNodeWithText("Route: Preset destination").assertIsNotEnabled()
    }

    @Test fun repeatedSendBeforeAFrameStartsOnlyOneLocationLookup() {
        var lookups = 0
        compose.setContent { VoxTheme { capture { lookups++; awaitCancellation() } } }
        // Two queued actions can run before the next composition disables the button.
        compose.onNodeWithTag("send-capture").performSemanticsAction(SemanticsActions.OnClick) { action ->
            action(); action()
        }
        compose.runOnIdle { assertEquals(1, lookups) }
    }

    @Composable private fun capture(
        pinned: List<CapturePreset> = emptyList(),
        select: (String) -> Unit = {},
        resolve: suspend (Boolean) -> md.vox.android.platformservices.CurrentLocationResult,
    ) {
        CaptureScreen(
            state = CaptureUiState(isLoading = false, draft = CaptureDraft("Before", null, 0),
                presetCollection = md.vox.android.capturedomain.CapturePresetCollection(route.id, listOf(route) + pinned)),
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
            pinnedPresets = pinned,
            isPresetRailExpanded = pinned.isNotEmpty(),
            onSelectPreset = select,
            resolveLocation = resolve,
        )
    }
}
