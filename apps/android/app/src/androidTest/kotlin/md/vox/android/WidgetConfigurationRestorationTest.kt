package md.vox.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import md.vox.android.capturedomain.*
import md.vox.android.ui.VoxTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class WidgetConfigurationRestorationTest {
    @get:Rule val compose = createComposeRule()
    private val route = CapturePresetEditorDraft.from(null).copy(name = "QA route").toPreset(1, emptyList())

    @Test fun sourceRepeatedTargetsAndEmptyPositionsSurviveRestorationBeforeSave() {
        var saved: PresetWidgetSelection? = null
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            VoxTheme { PresetWidgetConfigurationScreen(listOf(route), PresetWidgetSelection(), {}, { saved = it }) }
        }
        compose.onNodeWithText("Custom slots").performClick()
        chooseSlot(1, "QA route")
        chooseSlot(6, "QA route")
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("1: QA route").assertExists()
        compose.onNodeWithText("6: QA route").performScrollTo().assertIsDisplayed()
        compose.runOnIdle { assertNull(saved) }
        compose.onNodeWithText("Save widget").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(PresetWidgetSource.CUSTOM, saved?.source)
            assertEquals(listOf(route.id, null, null, null, null, route.id), saved?.slots)
        }
    }

    @Test fun clearingExistingTargetSurvivesRestorationAndDoesNotRestoreTheOldValue() {
        var saved: PresetWidgetSelection? = null
        val initial = PresetWidgetSelection(PresetWidgetSource.CUSTOM, List(6) { route.id })
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            VoxTheme { PresetWidgetConfigurationScreen(listOf(route), initial, {}, { saved = it }) }
        }
        chooseSlot(2, "Empty")
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("2: Empty or unavailable").assertExists()
        compose.onNodeWithText("Save widget").performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(initial.copy(slots = initial.slots.toMutableList().apply { set(1, null) }), saved)
        }
    }

    @Test fun cancelAfterRestorationDoesNotCommitTheDraft() {
        var saves = 0
        var cancels = 0
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            VoxTheme { PresetWidgetConfigurationScreen(listOf(route), PresetWidgetSelection(), { cancels++ }, { saves++ }) }
        }
        compose.onNodeWithText("Custom slots").performClick()
        chooseSlot(1, "QA route")
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("Cancel").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(1, cancels); assertEquals(0, saves) }
    }

    private fun chooseSlot(number: Int, target: String) {
        compose.onNode(hasText("$number:", substring = true) and hasClickAction()).performScrollTo().performClick()
        compose.onNodeWithText(target).performClick()
    }
}
