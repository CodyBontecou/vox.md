package md.vox.android

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.platformservices.LiveSpeechPhase
import md.vox.android.platformservices.LiveSpeechState
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiveTranscriptUiInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun committedLocalPhrasesStreamWhileTentativeTextRemainsVolatile() {
        val live = mutableStateOf(
            LiveSpeechState(
                sessionID = SESSION_ID,
                phase = LiveSpeechPhase.LISTENING,
                committedText = "Final phrase",
                partialText = "tentative one",
            ),
        )
        var durableInsertions = 0
        compose.setContent {
            VoxTheme {
                RecordingDetails(
                    status = RecordingStatus(
                        sessionID = SESSION_ID,
                        phase = RecordingPhase.RECORDING,
                        createdAtEpochMillis = 1_700_000_000_000,
                        elapsedMillis = 3_000,
                        chunkCount = 1,
                    ),
                    transcription = null,
                    liveSpeech = live.value,
                    start = {},
                    pause = {},
                    resume = {},
                    stop = {},
                    cancel = {},
                    dismiss = {},
                    close = {},
                    process = {},
                    cancelProcessing = {},
                    addToDraft = { durableInsertions += 1 },
                    sendWithPreset = {},
                )
            }
        }

        compose.onNodeWithText("Final phrase tentative one").assertExists()
        compose.runOnIdle {
            live.value = live.value.copy(
                committedText = "Final phrase Confirmed words",
                partialText = "tentative two",
            )
        }
        compose.onNodeWithText("Final phrase tentative one").assertDoesNotExist()
        compose.onNodeWithText("Final phrase Confirmed words tentative two").assertExists()
        compose.runOnIdle { assertEquals(0, durableInsertions) }
    }

    private companion object {
        const val SESSION_ID = "77777777-7777-4777-8777-777777777777"
    }
}
