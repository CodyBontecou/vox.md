package md.vox.android

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** The "Before you go" actions are a pinned footer: visible at first open, with no scrolling. */
class BeforeYouGoSheetInstrumentationTest {
    @get:Rule val compose = createComposeRule()
    private val weeklyWithOffer = beforeYouGoCopy(
        VoxPlan.WEEKLY,
        VoxYearlySwitchOffer("test-switch-yearly", "$19.99", "$29.99"),
    )!!

    @Test fun actionsAndFootnoteAreVisibleAtFirstOpen() = assertActionsVisible(fontScale = null)

    @Test fun actionsAndFootnoteAreVisibleAtLargestFontScale() = assertActionsVisible(fontScale = 2f)

    private fun assertActionsVisible(fontScale: Float?) {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale ?: density.fontScale)) {
                VoxTheme { BeforeYouGoSheet(weeklyWithOffer, onDismiss = {}, continueToCancel = {}, switchToYearly = {}) }
            }
        }
        val keep = compose.onNodeWithTag("keep-unlimited").assertIsDisplayed()
        val cancel = compose.onNodeWithTag("continue-to-cancel").assertIsDisplayed()
        compose.onNodeWithText("Continue to cancel opens your Vox.md subscription in Google Play.").assertIsDisplayed()
        val keepBounds = keep.fetchSemanticsNode().boundsInRoot
        val cancelBounds = cancel.fetchSemanticsNode().boundsInRoot
        assertEquals(keepBounds.width, cancelBounds.width, 1f)
        assertEquals(keepBounds.height, cancelBounds.height, 1f)
    }
}
