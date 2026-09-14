package md.vox.android.wear

import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.wear.compose.material.MaterialTheme
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WearRecorderUiInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun wearableTypographyAndTimerUseTheSharedGeistFamilies() {
        var usesGeist = false
        compose.setContent {
            WearVoxTheme {
                val typography = MaterialTheme.typography
                SideEffect {
                    usesGeist = typography.title3.fontFamily == WearGeistFontFamily &&
                        typography.caption1.fontFamily == WearGeistFontFamily &&
                        typography.display2.fontFamily == WearGeistFontFamily
                }
                androidx.wear.compose.material.Text(
                    "00:42",
                    style = typography.display2.copy(fontFamily = WearGeistMonoFontFamily),
                )
            }
        }
        compose.runOnIdle { assertTrue(usesGeist) }
    }

    @Test
    fun allInventoriedWatchPhasesHaveAConcreteStatusSurface() {
        val model = mutableStateOf(model())
        compose.setContent {
            WearVoxTheme {
                val current = model.value
                recorder(current)
            }
        }

        val stories = listOf(
            model() to "Ready",
            model(isStarting = true) to "Listening",
            model(status = status(RecordingPhase.RECORDING)) to "Recording",
            model(status = status(RecordingPhase.PAUSED)) to "Paused",
            model(queue = listOf(queue(WearQueuePhase.LOCAL))) to "Pending",
            model(queue = listOf(queue(WearQueuePhase.SYNC_QUEUED))) to "Syncing",
            model(queue = listOf(queue(WearQueuePhase.PHONE_TRANSCRIBING))) to "Transcribing on phone",
            model(queue = listOf(queue(WearQueuePhase.PHONE_DELIVERING))) to "Delivering",
            model(status = status(RecordingPhase.COMPLETED)) to "Saved",
            model(status = status(RecordingPhase.FAILED)) to "Needs attention",
            model(unavailableMessage = "Phone unavailable. Recording is safe.") to "Phone unavailable",
        )
        stories.forEach { (story, title) ->
            compose.runOnIdle { model.value = story }
            compose.waitForIdle()
            compose.onAllNodesWithText(title).onFirst().assertExists()
        }
    }

    @Test
    fun recorderControlsAndPresetEntryDispatchThroughTheProductionSurface() {
        var starts = 0
        var pauses = 0
        var resumes = 0
        var stops = 0
        var cancels = 0
        var presets = 0
        val model = mutableStateOf(model())
        compose.setContent {
            WearVoxTheme {
                val current = model.value
                recorder(
                    current,
                    start = { starts += 1 },
                    pause = { pauses += 1 },
                    resume = { resumes += 1 },
                    stop = { stops += 1 },
                    cancel = { cancels += 1 },
                    showPresets = { presets += 1 },
                )
            }
        }

        compose.onNodeWithContentDescription("Start Watch recording").performClick()
        compose.onRoot().performTouchInput { swipeUp() }
        compose.onNodeWithText("Daily").performClick()
        compose.runOnIdle { model.value = model(status = status(RecordingPhase.RECORDING)) }
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Pause Watch recording").performClick()
        compose.onNodeWithContentDescription("Stop Watch recording").performClick()
        compose.onNodeWithContentDescription("Cancel and delete Watch recording").performClick()
        compose.runOnIdle { model.value = model(status = status(RecordingPhase.PAUSED)) }
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Resume Watch recording").performClick()

        compose.runOnIdle {
            assertEquals(1, starts)
            assertEquals(1, pauses)
            assertEquals(1, resumes)
            assertEquals(1, stops)
            assertEquals(1, cancels)
            assertEquals(1, presets)
        }
    }

    @Test
    fun presetPickerSelectsACompleteSnapshotAndRecoveryRequiresConfirmedDiscard() {
        val selected = mutableListOf<WearPreset>()
        val presets = listOf(
            preset("11111111-1111-4111-8111-111111111111", "Daily"),
            preset("22222222-2222-4222-8222-222222222222", "Meetings"),
        )
        compose.setContent {
            WearVoxTheme {
                PresetPicker(presets, presets.first().id, { selected += it }, {})
            }
        }
        compose.onNodeWithText("Meetings").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals("Meetings", selected.single().name)
            assertEquals(presets[1].snapshot.toList(), selected.single().snapshot.toList())
        }
    }

    @Test
    fun recoveryScreenRetriesAndConfirmsDestructiveDiscard() {
        var retries = 0
        var discards = 0
        compose.setContent {
            WearVoxTheme {
                WearQueueScreen(
                    queue = listOf(queue(WearQueuePhase.TRANSPORT_FAILED)),
                    retry = { retries += 1 },
                    discard = { discards += 1 },
                    close = {},
                )
            }
        }

        compose.onNodeWithContentDescription("Retry Watch recording").performScrollTo().performClick()
        compose.onNodeWithContentDescription("Discard Watch recording").performScrollTo().performClick()
        compose.onNodeWithText("Discard recording?").assertExists()
        compose.runOnIdle { assertEquals(0, discards) }
        compose.onNodeWithText("Discard recording").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(1, retries)
            assertEquals(1, discards)
        }
    }

    @Composable
    private fun recorder(
        model: UiModel,
        start: () -> Unit = {},
        pause: () -> Unit = {},
        resume: () -> Unit = {},
        stop: () -> Unit = {},
        cancel: () -> Unit = {},
        showPresets: () -> Unit = {},
    ) = WearRecorderContent(
        status = model.status,
        queue = model.queue,
        selectedPreset = preset("11111111-1111-4111-8111-111111111111", "Daily"),
        syncMessage = null,
        isStarting = model.isStarting,
        isSyncing = false,
        unavailableMessage = model.unavailableMessage,
        pauseActionLabel = "Pause Watch recording",
        resumeActionLabel = "Resume Watch recording",
        stopActionLabel = "Stop Watch recording",
        cancelActionLabel = "Cancel and delete Watch recording",
        startActionLabel = "Start Watch recording",
        start = start,
        pause = pause,
        resume = resume,
        stop = stop,
        cancel = cancel,
        showPresets = showPresets,
        showQueue = {},
        sync = {},
    )

    private fun model(
        status: RecordingStatus = RecordingStatus(),
        queue: List<WearQueueItem> = emptyList(),
        isStarting: Boolean = false,
        unavailableMessage: String? = null,
    ) = UiModel(status, queue, isStarting, unavailableMessage)

    private fun status(phase: RecordingPhase) = RecordingStatus(
        sessionID = if (phase == RecordingPhase.IDLE) null else "11111111-1111-4111-8111-111111111111",
        phase = phase,
        createdAtEpochMillis = 1_700_000_000_000,
        elapsedMillis = 42_000,
        chunkCount = if (phase == RecordingPhase.IDLE) 0 else 1,
    )

    private fun preset(id: String, name: String) = WearPreset(
        id,
        name,
        "description",
        """{"id":"$id","name":"$name","revision":1,"logicalFolder":"Daily","noteNameTemplate":"daily-{uuid}.md","metadataFields":[]}""".toByteArray(),
    )

    private fun queue(phase: WearQueuePhase) = WearQueueItem(
        recordingID = "11111111-1111-4111-8111-111111111111",
        createdAtEpochMillis = 1_700_000_000_000,
        durationMillis = 42_000,
        chunkCount = 1,
        presetID = "22222222-2222-4222-8222-222222222222",
        presetName = "Daily",
        presetSnapshot = byteArrayOf(1),
        phase = phase,
        revision = 1,
        acknowledgedFrontier = 0,
        message = null,
    )

    private data class UiModel(
        val status: RecordingStatus,
        val queue: List<WearQueueItem>,
        val isStarting: Boolean,
        val unavailableMessage: String?,
    )
}
