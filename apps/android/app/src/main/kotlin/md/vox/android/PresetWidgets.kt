package md.vox.android

import android.app.Activity
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import androidx.activity.compose.setContent
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import md.vox.android.capturedomain.*
import md.vox.android.ui.VoxTheme

internal class PresetWidgetPreferences(context: Context) {
    private val preferences = context.getSharedPreferences("preset-widgets-v1", Context.MODE_PRIVATE)
    fun read(id: Int): PresetWidgetSelection = runCatching {
        val value = Json.parseToJsonElement(preferences.getString("widget-$id", null) ?: return PresetWidgetSelection()).jsonObject
        val source = PresetWidgetSource.valueOf(value.getValue("source").jsonPrimitive.content)
        PresetWidgetSelection(source, value.getValue("slots").jsonArray.take(6).map { it.jsonPrimitive.contentOrNull })
    }.getOrDefault(PresetWidgetSelection())
    fun save(id: Int, selection: PresetWidgetSelection) {
        require(id != AppWidgetManager.INVALID_APPWIDGET_ID)
        require(selection.slots.size == 6 && selection.slots.all { it == null || ID.matches(it) })
        val value = buildJsonObject {
            put("source", selection.source.name)
            put("slots", JsonArray(selection.slots.map { it?.let(::JsonPrimitive) ?: JsonNull }))
        }.toString()
        check(preferences.edit().putString("widget-$id", value).commit()) { "widgetConfigurationPersistence" }
    }
    fun delete(id: Int) { preferences.edit().remove("widget-$id").apply() }
    companion object { private val ID = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$") }
}

class VoxPresetWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                val presets = runCatching { (context.applicationContext as VoxApplication).compositionRoot.captureRepository.capturePresets().presets }.getOrNull()
                ids.forEach { id -> update(context, manager, id, presets) }
            } finally { pending?.finish() }
        }
    }
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) { onUpdate(context, manager, intArrayOf(id)) }
    override fun onDeleted(context: Context, ids: IntArray) { ids.forEach { PresetWidgetPreferences(context).delete(it) } }
    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, VoxPresetWidgetProvider::class.java))
            if (ids.isNotEmpty()) context.sendBroadcast(Intent(context, VoxPresetWidgetProvider::class.java)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE).putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids))
        }
        internal fun update(context: Context, manager: AppWidgetManager, id: Int, presets: List<CapturePreset>?) {
            val options = manager.getAppWidgetOptions(id)
            val small = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 280) < 250 ||
                options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 240) < 180
            manager.updateAppWidget(id, render(context,id,presets,PresetWidgetPreferences(context).read(id),small))
        }
        internal fun render(context: Context, id: Int, presets: List<CapturePreset>?, selection: PresetWidgetSelection, small: Boolean): RemoteViews {
            val tiles = PresetWidgetResolver.resolve(selection, presets.orEmpty(), small)
            val views = RemoteViews(context.packageName, R.layout.widget_presets)
            views.removeAllViews(R.id.preset_widget_rows)
            views.setViewVisibility(R.id.preset_widget_empty, if (tiles.isEmpty() || presets == null) View.VISIBLE else View.GONE)
            views.setTextViewText(R.id.preset_widget_empty, context.getString(if (presets == null) R.string.preset_widget_storage_unavailable else R.string.preset_widget_no_pins))
            tiles.chunked(if (small) 1 else 2).forEach { row ->
                val rowViews = RemoteViews(context.packageName, R.layout.widget_preset_row)
                row.forEach { tile ->
                    val child = RemoteViews(context.packageName, R.layout.widget_preset_slot)
                    val label = when (tile.availability) {
                        PresetWidgetAvailability.AVAILABLE -> listOfNotNull(tile.emoji, tile.name).joinToString(" ")
                        PresetWidgetAvailability.EMPTY -> context.getString(R.string.preset_widget_unconfigured)
                        PresetWidgetAvailability.DISABLED -> context.getString(R.string.preset_widget_disabled)
                        PresetWidgetAvailability.MISSING -> context.getString(R.string.preset_widget_missing)
                    }
                    child.setTextViewText(R.id.preset_widget_slot, label)
                    child.setContentDescription(R.id.preset_widget_slot, label)
                    val target = if (tile.presetID != null) Intent(Intent.ACTION_VIEW,
                        Uri.Builder().scheme("voxboard").authority("capture").appendQueryParameter("source", "widget")
                            .appendQueryParameter("preset", tile.presetID).appendQueryParameter("widget", id.toString())
                            .appendQueryParameter("slot", tile.slot.toString()).build(), context, MainActivity::class.java)
                        else configurationIntent(context, id)
                    child.setOnClickPendingIntent(R.id.preset_widget_slot, PendingIntent.getActivity(context, id * 10 + tile.slot, target,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
                    rowViews.addView(R.id.preset_widget_row, child)
                }
                views.addView(R.id.preset_widget_rows, rowViews)
            }
            views.setOnClickPendingIntent(R.id.preset_widget_configure, PendingIntent.getActivity(context, id,
                configurationIntent(context,id), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            return views
        }
        private fun configurationIntent(context: Context, id: Int): Intent = Intent(context, VoxPresetWidgetConfigureActivity::class.java)
            .setData(Uri.parse("vox-widget://configure/$id")).putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID,id)
    }
}

class VoxPresetWidgetConfigureActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(Activity.RESULT_CANCELED)
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        val manager = AppWidgetManager.getInstance(this)
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID || manager.getAppWidgetInfo(id)?.provider?.className != VoxPresetWidgetProvider::class.java.name) { finish(); return }
        lifecycleScope.launch {
            val presets = withContext(Dispatchers.IO) {
                runCatching { (application as VoxApplication).compositionRoot.captureRepository.capturePresets().presets }.getOrNull()
            }
            if (presets == null) { finish(); return@launch }
            val initial = PresetWidgetPreferences(this@VoxPresetWidgetConfigureActivity).read(id)
            setContent { VoxTheme { PresetWidgetConfigurationScreen(presets, initial, cancel = ::finish) { selection ->
                lifecycleScope.launch {
                    val saved = withContext(Dispatchers.IO) { runCatching { PresetWidgetPreferences(this@VoxPresetWidgetConfigureActivity).save(id,selection) }.isSuccess }
                    if (saved) {
                        VoxPresetWidgetProvider.update(this@VoxPresetWidgetConfigureActivity,manager,id,presets)
                        setResult(Activity.RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID,id)); finish()
                    }
                }
            } } }
        }
    }
}

@Composable internal fun PresetWidgetConfigurationScreen(presets: List<CapturePreset>, initial: PresetWidgetSelection,
    cancel: () -> Unit, save: (PresetWidgetSelection) -> Unit) {
    var selection by remember(initial) { mutableStateOf(initial.copy(slots = List(6) { initial.slots.getOrNull(it) })) }
    Surface {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(voxString("Capture Presets Widget"), style = MaterialTheme.typography.headlineSmall)
            Text(voxString("Open a preset without sending or recording. Small widgets show the first slot. Larger widgets show all six positions."))
            TextButton(onClick = { selection = selection.copy(source = PresetWidgetSource.FOLLOW_CAPTURE_BAR) }) {
                Text(voxString("Follow Capture Bar")); RadioButton(selection.source == PresetWidgetSource.FOLLOW_CAPTURE_BAR, null)
            }
            TextButton(onClick = { selection = selection.copy(source = PresetWidgetSource.CUSTOM) }) {
                Text(voxString("Custom slots")); RadioButton(selection.source == PresetWidgetSource.CUSTOM,null)
            }
            if (selection.source == PresetWidgetSource.CUSTOM) repeat(6) { slot ->
                var expanded by remember { mutableStateOf(false) }
                val target = presets.firstOrNull { it.id == selection.slots[slot] }
                Box {
                    OutlinedButton(onClick = { expanded = true }) {
                        Text(voxFormat("%lld: %@", slot + 1, target?.name ?: voxString("Empty or unavailable")))
                    }
                    DropdownMenu(expanded, { expanded = false }) {
                        DropdownMenuItem(text = { Text(voxString("Empty")) }, onClick = {
                            selection = selection.copy(slots = selection.slots.toMutableList().apply { set(slot,null) }); expanded = false
                        })
                        presets.filter { it.isEnabled }.forEach { preset ->
                            DropdownMenuItem(text = { Text(preset.name) }, onClick = {
                                selection = selection.copy(slots = selection.slots.toMutableList().apply { set(slot,preset.id) }); expanded = false
                            })
                        }
                    }
                }
            }
            Button(onClick = { save(selection) }) { Text(voxString("Save widget")) }
            TextButton(onClick = cancel) { Text(voxString("Cancel")) }
        }
    }
}
