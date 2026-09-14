package md.vox.android

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import md.vox.android.capturedomain.CaptureLocationUnavailableReason
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class LocationUnavailableUiInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun everyFrozenUnavailableReasonIsSurfacedAndEveryInteractiveDecisionDispatches() {
        var setReason: (CaptureLocationUnavailableReason) -> Unit = {}
        var retryCount = 0
        var sendCount = 0
        var alwaysCount = 0
        var cancelCount = 0
        compose.setContent {
            var reason by remember { mutableStateOf(CaptureLocationUnavailableReason.PERMISSION_DENIED) }
            setReason = { reason = it }
            VoxTheme {
                LocationUnavailableDialog(
                    reason = reason,
                    canPersistPreference = true,
                    retry = { retryCount++ },
                    sendWithoutLocation = { sendCount++ },
                    alwaysSendWithoutLocation = { alwaysCount++ },
                    cancel = { cancelCount++ },
                )
            }
        }

        CaptureLocationUnavailableReason.entries.forEach { reason ->
            compose.runOnIdle { setReason(reason) }
            compose.onNodeWithText(locationUnavailableMessage(reason)).assertIsDisplayed()
        }
        compose.onNodeWithText("Retry").performClick()
        compose.onNodeWithText("Send Without Location").performClick()
        compose.onNodeWithText("Always Send Without Location").performClick()
        compose.onNodeWithText("Cancel").performClick()
        compose.runOnIdle {
            assertEquals(1, retryCount)
            assertEquals(1, sendCount)
            assertEquals(1, alwaysCount)
            assertEquals(1, cancelCount)
        }
    }
}
