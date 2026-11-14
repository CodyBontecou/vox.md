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
        compose.mainClock.advanceTimeBy(md.vox.android.ui.CaptureViewModel.LIVE_SAVE_DEBOUNCE_MILLIS + 100) // Live Notes: the first write starts after idle
        compose.onNodeWithTag("live-note-new").assertIsNotEnabled()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithTag("capture-editor").assertTextEquals("Before")
        compose.onNodeWithTag("live-note-new").assertIsEnabled()
    }
    @Test fun unavailableDecisionSurvivesRotationAndCancelKeepsTheDraft() {
        val restoration = StateRestorationTester(compose)
        var lookups = 0
        restoration.setContent { VoxTheme { capture { lookups++; CurrentLocationResult.Unavailable } } }
        compose.mainClock.advanceTimeBy(md.vox.android.ui.CaptureViewModel.LIVE_SAVE_DEBOUNCE_MILLIS + 100) // Live Notes: the first write starts after idle
        compose.onNodeWithText(locationUnavailableMessage(CaptureLocationUnavailableReason.UNAVAILABLE)).assertExists()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText(locationUnavailableMessage(CaptureLocationUnavailableReason.UNAVAILABLE)).assertExists()
        compose.onNodeWithText("Cancel").performClick()
        compose.onNodeWithTag("capture-editor").assertTextEquals("Before")
        compose.onNodeWithTag("live-note-new").assertIsEnabled()
        compose.runOnIdle { assertEquals(1, lookups) }
    }

    @Test fun locationLookupDisablesPresetAndDestinationChanges() {
        val other = route.copy(id = "bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb", name = "Other")
        compose.setContent { VoxTheme { capture(pinned = listOf(other)) { awaitCancellation() } } }
        compose.mainClock.advanceTimeBy(md.vox.android.ui.CaptureViewModel.LIVE_SAVE_DEBOUNCE_MILLIS + 100) // Live Notes: the first write starts after idle
        compose.onNodeWithTag("live-note-new").assertIsNotEnabled()
        compose.onNodeWithTag("capture-route-pill-${other.id}").assertIsNotEnabled()
        compose.onNodeWithTag("capture-preset-selector").assertIsNotEnabled()
        // The path breadcrumb only opens the route editor while nothing is in flight.
        compose.onNodeWithTag("live-note-path").assert(hasClickAction().not())
    }

    @Test fun repeatedIdleWritesStartOnlyOneLocationLookup() {
        var lookups = 0
        compose.setContent { VoxTheme { capture { lookups++; awaitCancellation() } } }
        // The idle first write re-arms on every state change; the preflight must still run once.
        repeat(3) { compose.mainClock.advanceTimeBy(md.vox.android.ui.CaptureViewModel.LIVE_SAVE_DEBOUNCE_MILLIS + 100) }
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
            routePresets = pinned,
            onSelectPreset = select,
            resolveLocation = resolve,
        )
    }
}
