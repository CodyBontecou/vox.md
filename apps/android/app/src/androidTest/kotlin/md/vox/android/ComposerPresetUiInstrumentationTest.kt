package md.vox.android

import android.content.Context
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import md.vox.android.capturedomain.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class ComposerPresetUiInstrumentationTest {
    @get:Rule val compose=createComposeRule()
    @Test fun widePreviewToggleAndResizeKeepEditorTextAndPreset() {
        var width by mutableStateOf(900)
        var value by mutableStateOf("# Draft")
        compose.setContent { MaterialTheme {
            Box(Modifier.requiredWidth(width.dp).height(500.dp)) {
                CaptureWorkspace(value,null,null,null,0) { BasicTextField(value,{ value=it },Modifier.testTag("preview-source")) }
            }
        } }
        compose.onNodeWithTag("preview-source").performTextInput(" edited")
        // The wide-layout preview is the tablet board's side panel and starts open.
        compose.onNodeWithText("Copy draft Markdown").assertExists()
        compose.onNodeWithText("Hide draft preview").performClick()
        compose.onNodeWithText("Copy draft Markdown").assertDoesNotExist()
        compose.onNodeWithTag("preview-source").assertTextContains("edited",substring=true)
        compose.onNodeWithText("Show draft preview").performClick()
        compose.onNodeWithText("Copy draft Markdown").assertExists()
        compose.runOnIdle { width=400 }
        compose.onNodeWithText("Copy draft Markdown").assertDoesNotExist()
        compose.onNodeWithTag("preview-source").assertTextContains("edited",substring=true)
        compose.runOnIdle { width=900 }
        compose.onNodeWithText("Hide draft preview").performClick()
        compose.onNodeWithTag("preview-source").assertTextContains("edited",substring=true)
    }
    @Test fun timestampSelectionDispatchesInRtl() {
        var configuration by mutableStateOf(CaptureBarConfiguration())
        compose.setContent { CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
            MaterialTheme { Column { CaptureAppearanceControls(configuration,false,
                { configuration=configuration.copy(usesTwentyFourHourTimestamps=it) }) } }
        } }
        compose.onNodeWithTag("timestamp-24-hour").performClick()
        compose.runOnIdle { assertEquals(CaptureTimestampFormat.TWENTY_FOUR_HOUR,configuration.timestampFormat) }
    }
    @Test fun railAndTimestampPreferencesSurviveRepositoryReload() = kotlinx.coroutines.runBlocking {
        val context: Context=ApplicationProvider.getApplicationContext()
        val repository=(context.applicationContext as VoxApplication).compositionRoot.captureRepository
        val original=repository.captureBarConfiguration()
        try {
            repository.saveCaptureBarConfiguration(original.copy(railSide=CaptureRailSide.RIGHT,usesTwentyFourHourTimestamps=true))
            val loaded=repository.captureBarConfiguration()
            assertEquals(CaptureRailSide.RIGHT,loaded.railSide)
            assertEquals(CaptureTimestampFormat.TWENTY_FOUR_HOUR,loaded.timestampFormat)
        } finally { repository.saveCaptureBarConfiguration(original) }
    }
    @Test fun widgetPreferencesArePerInstanceAndCustomSlotsPreserveEmptyAndRepeatedTargets() {
        val context: Context=ApplicationProvider.getApplicationContext()
        val store=PresetWidgetPreferences(context)
        val id="12345678-1234-4234-8234-123456789abc"
        val custom=PresetWidgetSelection(PresetWidgetSource.CUSTOM,listOf(null,id,id,null,null,null))
        try {
            store.save(91201,custom);store.save(91202,PresetWidgetSelection())
            assertEquals(custom,store.read(91201));assertEquals(PresetWidgetSource.FOLLOW_CAPTURE_BAR,store.read(91202).source)
            store.delete(91201);assertEquals(PresetWidgetSelection(),store.read(91201))
        } finally { store.delete(91201);store.delete(91202) }
    }
    @Test fun launcherRemoteViewsPreserveCustomSlotsAndSmallFirstPosition() {
        val context: Context=ApplicationProvider.getApplicationContext()
        val preset=CapturePreset("12345678-1234-4234-8234-123456789abc","Inbox","",revision=1,logicalFolder="Inbox",noteNameTemplate="capture-{id}.md",metadataFields=emptyList())
        val selection=PresetWidgetSelection(PresetWidgetSource.CUSTOM,listOf(null,preset.id,preset.id,"12345678-1234-4234-8234-123456789abd",null,null))
        compose.runOnUiThread {
            val large=VoxPresetWidgetProvider.render(context,91203,listOf(preset),selection,false).apply(context,android.widget.FrameLayout(context))
            val rows=large.findViewById<android.widget.LinearLayout>(R.id.preset_widget_rows)
            assertEquals(3,rows.childCount)
            val first=rows.getChildAt(0) as android.widget.LinearLayout
            assertEquals(context.getString(R.string.preset_widget_unconfigured),(first.getChildAt(0) as android.widget.TextView).text)
            assertEquals(" Inbox".trim(),(first.getChildAt(1) as android.widget.TextView).text.toString().trim())
            val small=VoxPresetWidgetProvider.render(context,91203,listOf(preset),selection,true).apply(context,android.widget.FrameLayout(context))
            val smallRows=small.findViewById<android.widget.LinearLayout>(R.id.preset_widget_rows)
            assertEquals(1,smallRows.childCount)
            assertEquals(1,(smallRows.getChildAt(0) as android.widget.LinearLayout).childCount)
        }
    }
    @Test fun widgetConfigurationSavesOrderedCustomSlots() {
        val preset=CapturePreset("12345678-1234-4234-8234-123456789abc","Inbox","",revision=1,logicalFolder="Inbox",noteNameTemplate="capture-{id}.md",metadataFields=emptyList())
        var saved: PresetWidgetSelection?=null
        compose.setContent { MaterialTheme { PresetWidgetConfigurationScreen(listOf(preset),PresetWidgetSelection(),{}, { saved=it }) } }
        compose.onNodeWithText("Custom slots").performClick()
        compose.onNodeWithText("1: Empty or unavailable").performClick()
        compose.onNodeWithText("Inbox").performClick()
        compose.onNodeWithText("Save widget").performScrollTo().performClick()
        compose.runOnIdle { assertEquals(preset.id,saved!!.slots[0]);assertNull(saved!!.slots[1]) }
    }
}
