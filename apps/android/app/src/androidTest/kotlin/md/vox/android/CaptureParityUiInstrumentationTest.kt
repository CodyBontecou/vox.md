package md.vox.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.*
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import md.vox.android.capturedomain.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class CaptureParityUiInstrumentationTest {
    @get:Rule val compose = createComposeRule()
    @Test fun routeDialogAppliesOnlyValidRelativeNoteAndSupportsReset() {
        var route: CaptureRouteOverride? by mutableStateOf(null)
        compose.setContent { MaterialTheme { CaptureRouteControl(route, CaptureDestination("vault", "Work", "content://test/work")) { route = it } } }
        compose.onNodeWithText("Route: Work").performClick()
        compose.onNodeWithText("Note path in this vault").performTextInput("../outside.md")
        compose.onNodeWithText("Apply").assertIsNotEnabled()
        compose.onNodeWithText("Note path in this vault").performTextClearance()
        compose.onNodeWithText("Note path in this vault").performTextInput("Journal/Today.md")
        compose.onNodeWithText("Bottom", substring = true).performClick()
        compose.onNodeWithText("Apply").performClick()
        compose.runOnIdle { assertEquals(CaptureRouteOverride("Journal/Today.md", CapturePlacementKind.APPEND), route) }
        compose.onNodeWithText("Route: Journal/Today.md").performClick()
        compose.onNodeWithText("Reset route").performClick()
        compose.runOnIdle { assertNull(route) }
    }
    @Test fun transcriptPropertyExposesIndependentBodyToggle() {
        var name by mutableStateOf("")
        var includeBody by mutableStateOf(true)
        compose.setContent { MaterialTheme { Column { TranscriptPropertyControls(name, includeBody, { name = it }, { includeBody = it }) } } }
        compose.onNodeWithText("Transcript Property").performTextInput("note")
        compose.onNodeWithText("Also include transcript in body").assertIsDisplayed()
        compose.onNode(isToggleable()).performClick()
        compose.runOnIdle { assertFalse(includeBody); assertEquals("note", name) }
    }
}
