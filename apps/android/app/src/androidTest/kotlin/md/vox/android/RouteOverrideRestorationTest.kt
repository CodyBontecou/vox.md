package md.vox.android

import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import md.vox.android.capturedomain.*
import md.vox.android.ui.VoxTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class RouteOverrideRestorationTest {
    @get:Rule val compose = createComposeRule()

    @Test fun pathPlacementAndOpenDialogSurviveRestorationUntilApply() {
        var saved: CaptureRouteOverride? = null
        val restoration = StateRestorationTester(compose)
        restoration.setContent { VoxTheme { CaptureRouteControl(null, null) { saved = it } } }
        compose.onNodeWithText("Route: Preset destination").performClick()
        compose.onNodeWithText("Note path in this vault").performTextInput("QA/日本語.md")
        compose.onNodeWithText("Top").performScrollTo().performClick()
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("Route this capture").assertExists()
        compose.onNode(hasSetTextAction()).assertTextContains("QA/日本語.md")
        compose.runOnIdle { assertNull(saved) }
        compose.onNodeWithText("Apply").performClick()
        compose.runOnIdle { assertEquals(CaptureRouteOverride("QA/日本語.md", CapturePlacementKind.PREPEND), saved) }
    }

    @Test fun invalidDraftSurvivesRestorationWithoutBeingApplied() {
        var calls = 0
        val restoration = StateRestorationTester(compose)
        restoration.setContent { VoxTheme { CaptureRouteControl(null, null) { calls++ } } }
        compose.onNodeWithText("Route: Preset destination").performClick()
        compose.onNodeWithText("Note path in this vault").performTextInput("../escape.md")
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("Apply").assertIsNotEnabled()
        compose.onNode(hasSetTextAction()).assertTextContains("../escape.md")
        compose.onNodeWithText("Route this capture").assertExists()
        compose.runOnIdle { assertEquals(0, calls) }
    }
    @Test fun adaptiveHeaderRelocationPreservesOpenDialogPathAndPlacement() {
        var compact by mutableStateOf(false)
        var saved: CaptureRouteOverride? = null
        val restoration = StateRestorationTester(compose)
        restoration.setContent { VoxTheme {
            CaptureTopControls(null, null, null, { saved = it }, emptyList(), {},
                {}, {}, {}, compactHeight = compact)
        } }
        compose.onNodeWithText("Route: Preset destination").performClick()
        compose.onNodeWithText("Note path in this vault").performTextInput("QA/日本語.md")
        compose.onNodeWithText("Top").performScrollTo().performClick()
        compose.runOnIdle { compact = true }
        compose.onNodeWithText("Route this capture").assertExists()
        compose.onNode(hasSetTextAction()).assertTextContains("QA/日本語.md")
        restoration.emulateSavedInstanceStateRestore()
        compose.runOnIdle { compact = false }
        compose.onNodeWithText("Route this capture").assertExists()
        compose.onNodeWithText("Apply").performClick()
        compose.runOnIdle { assertEquals(CaptureRouteOverride("QA/日本語.md", CapturePlacementKind.PREPEND), saved) }
    }

}
