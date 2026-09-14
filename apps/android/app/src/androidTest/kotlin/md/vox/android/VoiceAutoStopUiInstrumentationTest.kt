package md.vox.android

import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isToggleable
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.platformservices.VoiceAutoStopEndAction
import md.vox.android.platformservices.VoiceAutoStopSettings
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VoiceAutoStopUiInstrumentationTest {
    @get:Rule val compose = createComposeRule()

    @Test
    fun pauseDetectionCanBeEnabledConfiguredAndSwitchedToPersistentSegments() {
        var settings by mutableStateOf(VoiceAutoStopSettings())
        compose.setContent {
            VoxTheme {
                Surface {
                    VoiceAutoStopCard(settings = settings, update = { settings = it })
                }
            }
        }

        compose.onNode(isToggleable()).performClick()
        compose.onNode(hasText("Pause", substring = true) and hasClickAction()).performClick()
        compose.onNodeWithText("1.5 seconds").performClick()
        compose.onNodeWithText("Keep Listening").performClick()
        compose.onNodeWithText("Each detected thought becomes a transcript paragraph. Continuous listening ends after 10 minutes.")
            .assertExists()

        compose.runOnIdle {
            assertTrue(settings.enabled)
            assertEquals(1_500, settings.pauseDurationMillis)
            assertEquals(VoiceAutoStopEndAction.SAVE_SEGMENT_AND_CONTINUE, settings.endAction)
        }
    }
}
