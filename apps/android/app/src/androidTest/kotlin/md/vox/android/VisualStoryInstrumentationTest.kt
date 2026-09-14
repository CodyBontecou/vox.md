package md.vox.android

import android.content.res.Configuration
import android.os.LocaleList
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VisualStoryInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun everyDeterministicVisualStoryRendersItsProductionSurface() {
        val englishConfiguration = englishConfiguration()
        var story by mutableStateOf(VisualStoryActivity.STORY_CAPTURE)
        compose.setContent {
            CompositionLocalProvider(
                LocalConfiguration provides englishConfiguration,
                LocalLayoutDirection provides LayoutDirection.Ltr,
            ) {
                VoxTheme(darkTheme = true) {
                    key(story) { VisualParityStory(story) }
                }
            }
        }

        compose.runOnIdle { story = VisualStoryActivity.STORY_LOADING }
        compose.waitForIdle()
        compose.onNodeWithContentDescription("Loading Vox.md").assertIsDisplayed()

        val expectations = listOf(
            VisualStoryActivity.STORY_CAPTURE to "Launch notes",
            VisualStoryActivity.STORY_HISTORY to "History",
            VisualStoryActivity.STORY_SETTINGS to "Settings",
            VisualStoryActivity.STORY_MODELS to "Models",
            VisualStoryActivity.STORY_PRESETS to "Capture Presets",
            VisualStoryActivity.STORY_APP_LANGUAGE to "App Language",
            VisualStoryActivity.STORY_LIVE_RECORDING to "Recording",
            VisualStoryActivity.STORY_VAULT_REPAIR to "Choose vault or folder",
            VisualStoryActivity.STORY_HISTORY_EMPTY to "No history yet",
            VisualStoryActivity.STORY_HISTORY_FOLDER_REPAIR to "Folder access needed",
            VisualStoryActivity.STORY_RECORDING_PAUSED to "Recording paused",
            VisualStoryActivity.STORY_RECORDING_FAILED to "Local transcription failed",
            VisualStoryActivity.STORY_UPGRADE_PENDING to "Purchase Pending",
            VisualStoryActivity.STORY_UPGRADE_ACTIVE to "Unlimited is active",
            VisualStoryActivity.STORY_UPGRADE_QUOTA_REACHED to "10 of 10 used",
            VisualStoryActivity.STORY_UPGRADE_OFFLINE to "Google Play is unavailable",
            VisualStoryActivity.STORY_RECORDING_QUOTA_REACHED to "free transcription limit has been reached",
            VisualStoryActivity.STORY_RECORDING_INTERRUPTED to "Recording interrupted",
            VisualStoryActivity.STORY_HISTORY_UNKNOWN_OUTCOME to "Checking delivery",
            VisualStoryActivity.STORY_HISTORY_PERMANENT_FAILURE to "Capture failed",
        )
        expectations.forEach { (nextStory, expectedText) ->
            compose.runOnIdle { story = nextStory }
            compose.waitForIdle()
            val expectedNode = compose.onNodeWithText(
                expectedText,
                substring = nextStory in setOf(
                    VisualStoryActivity.STORY_CAPTURE,
                    VisualStoryActivity.STORY_RECORDING_FAILED,
                    VisualStoryActivity.STORY_UPGRADE_OFFLINE,
                    VisualStoryActivity.STORY_RECORDING_QUOTA_REACHED,
                ),
                useUnmergedTree = true,
            )
            if (nextStory in setOf(
                    VisualStoryActivity.STORY_RECORDING_FAILED,
                    VisualStoryActivity.STORY_UPGRADE_PENDING,
                    VisualStoryActivity.STORY_UPGRADE_QUOTA_REACHED,
                    VisualStoryActivity.STORY_UPGRADE_OFFLINE,
                    VisualStoryActivity.STORY_RECORDING_QUOTA_REACHED,
                )
            ) {
                expectedNode.performScrollTo()
            }
            expectedNode.assertIsDisplayed()
        }
    }

    @Test
    fun twoHundredPercentTextKeepsHistoryAndRecordingActionsOnSingleControlLines() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val deviceDensity = context.resources.displayMetrics.density
        val englishConfiguration = englishConfiguration()
        var story by mutableStateOf(VisualStoryActivity.STORY_HISTORY)
        compose.setContent {
            CompositionLocalProvider(
                LocalConfiguration provides englishConfiguration,
                LocalLayoutDirection provides LayoutDirection.Ltr,
                LocalDensity provides Density(deviceDensity, 2f),
            ) {
                VoxTheme(darkTheme = true) {
                    VisualParityStory(story)
                }
            }
        }

        assertControlIsWiderThanTall("Transcripts")
        compose.runOnIdle { story = VisualStoryActivity.STORY_LIVE_RECORDING }
        compose.waitForIdle()
        listOf("Pause", "Stop", "Cancel").forEach(::assertControlIsWiderThanTall)
    }

    @Test
    fun twoHundredPercentTextKeepsRecoveryAndPurchaseActionsReachable() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val deviceDensity = context.resources.displayMetrics.density
        val englishConfiguration = englishConfiguration()
        var story by mutableStateOf(VisualStoryActivity.STORY_VAULT_REPAIR)
        compose.setContent {
            CompositionLocalProvider(
                LocalConfiguration provides englishConfiguration,
                LocalLayoutDirection provides LayoutDirection.Ltr,
                LocalDensity provides Density(deviceDensity, 2f),
            ) {
                VoxTheme(darkTheme = true) {
                    VisualParityStory(story)
                }
            }
        }

        assertScrollableControlIsWiderThanTall("Choose vault or folder")
        compose.runOnIdle { story = VisualStoryActivity.STORY_HISTORY_FOLDER_REPAIR }
        compose.waitForIdle()
        assertScrollableControlIsWiderThanTall("Repair Folder Access")
        compose.runOnIdle { story = VisualStoryActivity.STORY_UPGRADE_PENDING }
        compose.waitForIdle()
        compose.onNodeWithText("Purchase Pending", useUnmergedTree = true)
            .performScrollTo()
            .assertIsDisplayed()
        assertScrollableControlIsWiderThanTall("Restore Purchase")
    }

    @Test
    fun twoHundredPercentTextKeepsResilienceActionsReachable() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val deviceDensity = context.resources.displayMetrics.density
        val englishConfiguration = englishConfiguration()
        var story by mutableStateOf(VisualStoryActivity.STORY_UPGRADE_QUOTA_REACHED)
        compose.setContent {
            CompositionLocalProvider(
                LocalConfiguration provides englishConfiguration,
                LocalLayoutDirection provides LayoutDirection.Ltr,
                LocalDensity provides Density(deviceDensity, 2f),
            ) {
                VoxTheme(darkTheme = true) {
                    VisualParityStory(story)
                }
            }
        }

        compose.onNodeWithText("10 of 10 used", useUnmergedTree = true)
            .performScrollTo()
            .assertIsDisplayed()
        assertScrollableControlIsWiderThanTall("Restore Purchase")
        compose.runOnIdle { story = VisualStoryActivity.STORY_UPGRADE_OFFLINE }
        compose.waitForIdle()
        compose.onNodeWithText("Google Play is unavailable", substring = true, useUnmergedTree = true)
            .performScrollTo()
            .assertIsDisplayed()
        assertScrollableControlIsWiderThanTall("Restore Purchase")
        compose.runOnIdle { story = VisualStoryActivity.STORY_RECORDING_QUOTA_REACHED }
        compose.waitForIdle()
        assertScrollableControlIsWiderThanTall("Retry Processing")
        compose.runOnIdle { story = VisualStoryActivity.STORY_RECORDING_INTERRUPTED }
        compose.waitForIdle()
        listOf("Resume", "Finish", "Cancel").forEach(::assertScrollableControlIsWiderThanTall)
        compose.runOnIdle { story = VisualStoryActivity.STORY_HISTORY_UNKNOWN_OUTCOME }
        compose.waitForIdle()
        assertScrollableControlIsWiderThanTall("Retry")
        compose.runOnIdle { story = VisualStoryActivity.STORY_HISTORY_PERMANENT_FAILURE }
        compose.waitForIdle()
        assertScrollableControlIsWiderThanTall("Retry")
    }

    @Test
    fun stateChangesExposePoliteTalkBackAnnouncements() {
        val englishConfiguration = englishConfiguration()
        var story by mutableStateOf(VisualStoryActivity.STORY_VAULT_REPAIR)
        compose.setContent {
            CompositionLocalProvider(
                LocalConfiguration provides englishConfiguration,
                LocalLayoutDirection provides LayoutDirection.Ltr,
            ) {
                VoxTheme(darkTheme = true) {
                    VisualParityStory(story)
                }
            }
        }

        val announcementMatcher = SemanticsMatcher.expectValue(
            SemanticsProperties.LiveRegion,
            LiveRegionMode.Polite,
        )
        val expectations = listOf(
            VisualStoryActivity.STORY_VAULT_REPAIR to "Folder access changed",
            VisualStoryActivity.STORY_RECORDING_PAUSED to "Recording paused",
            VisualStoryActivity.STORY_RECORDING_FAILED to "Local transcription failed",
            VisualStoryActivity.STORY_UPGRADE_PENDING to "Your purchase is pending",
            VisualStoryActivity.STORY_UPGRADE_ACTIVE to "Unlimited is active",
            VisualStoryActivity.STORY_UPGRADE_QUOTA_REACHED to "Capture without limits",
            VisualStoryActivity.STORY_UPGRADE_OFFLINE to "Google Play is unavailable",
            VisualStoryActivity.STORY_RECORDING_QUOTA_REACHED to "free transcription limit",
            VisualStoryActivity.STORY_RECORDING_INTERRUPTED to "Recording interrupted",
            VisualStoryActivity.STORY_HISTORY_UNKNOWN_OUTCOME to "Checking delivery",
            VisualStoryActivity.STORY_HISTORY_PERMANENT_FAILURE to "Capture failed",
        )
        expectations.forEach { (nextStory, announcement) ->
            compose.runOnIdle { story = nextStory }
            compose.waitForIdle()
            compose.onNode(
                hasText(announcement, substring = true) and announcementMatcher,
                useUnmergedTree = true,
            ).fetchSemanticsNode()
        }
    }

    @Test
    fun stateRecoveryActionsExposeLabeledMinimumSwitchAccessTargets() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val deviceDensity = context.resources.displayMetrics.density
        val englishConfiguration = englishConfiguration()
        var story by mutableStateOf(VisualStoryActivity.STORY_VAULT_REPAIR)
        compose.setContent {
            CompositionLocalProvider(
                LocalConfiguration provides englishConfiguration,
                LocalLayoutDirection provides LayoutDirection.Ltr,
            ) {
                VoxTheme(darkTheme = true) {
                    VisualParityStory(story)
                }
            }
        }

        val actionMatrix = listOf(
            VisualStoryActivity.STORY_VAULT_REPAIR to listOf("Choose vault or folder"),
            VisualStoryActivity.STORY_HISTORY_FOLDER_REPAIR to listOf("Repair Folder Access"),
            VisualStoryActivity.STORY_RECORDING_PAUSED to listOf("Resume", "Stop", "Cancel"),
            VisualStoryActivity.STORY_RECORDING_FAILED to listOf("Retry Processing", "Dismiss"),
            VisualStoryActivity.STORY_UPGRADE_PENDING to listOf("Restore Purchase"),
            VisualStoryActivity.STORY_UPGRADE_ACTIVE to listOf("Restore Purchase"),
            VisualStoryActivity.STORY_UPGRADE_QUOTA_REACHED to listOf("Restore Purchase"),
            VisualStoryActivity.STORY_UPGRADE_OFFLINE to listOf("Restore Purchase"),
            VisualStoryActivity.STORY_RECORDING_QUOTA_REACHED to listOf("Retry Processing", "Dismiss"),
            VisualStoryActivity.STORY_RECORDING_INTERRUPTED to listOf("Resume", "Finish", "Cancel"),
            VisualStoryActivity.STORY_HISTORY_UNKNOWN_OUTCOME to listOf("Retry"),
            VisualStoryActivity.STORY_HISTORY_PERMANENT_FAILURE to listOf("Retry"),
        )
        actionMatrix.forEach { (nextStory, actions) ->
            compose.runOnIdle { story = nextStory }
            compose.waitForIdle()
            actions.forEach { label -> assertAccessibleSwitchTarget(label, deviceDensity) }
        }
    }

    private fun assertControlIsWiderThanTall(label: String) {
        compose.onNode(hasText(label) and hasClickAction()).assertIsDisplayed()
        val node = compose.onNodeWithText(label, useUnmergedTree = true)
            .assertIsDisplayed()
            .fetchSemanticsNode()
        assertTrue("$label wrapped inside its control", node.boundsInRoot.width > node.boundsInRoot.height)
    }

    private fun assertScrollableControlIsWiderThanTall(label: String) {
        compose.onNode(hasText(label) and hasClickAction())
            .performScrollTo()
            .assertIsDisplayed()
        assertControlIsWiderThanTall(label)
    }

    private fun assertAccessibleSwitchTarget(label: String, deviceDensity: Float) {
        val action = compose.onNode(hasText(label) and hasClickAction())
            .performScrollTo()
            .assertIsDisplayed()
            .assertHasClickAction()
            .fetchSemanticsNode()
        assertTrue("$label switch target is narrower than 48 dp", action.touchBoundsInRoot.width / deviceDensity >= 48f)
        assertTrue("$label switch target is shorter than 48 dp", action.touchBoundsInRoot.height / deviceDensity >= 48f)
    }

    private fun englishConfiguration(): Configuration {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        return Configuration(context.resources.configuration).apply {
            setLocales(LocaleList.forLanguageTags("en-US"))
        }
    }
}
