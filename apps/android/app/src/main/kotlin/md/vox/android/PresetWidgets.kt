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
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalGroup
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalPageTitle
import md.vox.android.ui.SignalRowDivider
import md.vox.android.ui.SignalType
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.ui.Alignment
import androidx.compose.ui.semantics.Role

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
                    child.setTextViewCompoundDrawablesRelative(R.id.preset_widget_slot, routeTileDrawable(tile, tiles.indexOf(tile)), 0, 0, 0)
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
        /** Signal route tiles: the first position is indigo, the second ink, the rest (and any unavailable slot) neutral. */
        private fun routeTileDrawable(tile: PresetWidgetTile, position: Int): Int = when {
            tile.availability != PresetWidgetAvailability.AVAILABLE -> R.drawable.widget_route_tile_neutral
            position == 0 -> R.drawable.widget_route_tile_primary
            position == 1 -> R.drawable.widget_route_tile_ink
            else -> R.drawable.widget_route_tile_neutral
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
    val c = Signal.colors
    Surface(color = c.bg, contentColor = c.text) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .systemBarsPadding()
                .padding(horizontal = SignalMetrics.PageGutter, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SignalPageTitle(
                title = voxString("Capture Presets Widget"),
                subtitle = voxString("Open a preset without sending or recording. Small widgets show the first slot. Larger widgets show all six positions."),
                modifier = Modifier.padding(start = 4.dp, end = 4.dp, top = 24.dp, bottom = 8.dp),
            )
            SignalGroup(title = null) {
                PresetWidgetSourceRow(voxString("Follow Capture Bar"), selection.source == PresetWidgetSource.FOLLOW_CAPTURE_BAR) {
                    selection = selection.copy(source = PresetWidgetSource.FOLLOW_CAPTURE_BAR)
                }
                SignalRowDivider()
                PresetWidgetSourceRow(voxString("Custom slots"), selection.source == PresetWidgetSource.CUSTOM) {
                    selection = selection.copy(source = PresetWidgetSource.CUSTOM)
                }
            }
            if (selection.source == PresetWidgetSource.CUSTOM) SignalGroup(title = null, modifier = Modifier.padding(top = 8.dp)) {
                repeat(6) { slot ->
                    var expanded by remember { mutableStateOf(false) }
                    val target = presets.firstOrNull { it.id == selection.slots[slot] }
                    if (slot > 0) SignalRowDivider()
                    Box {
                        Row(
                            Modifier
                                .fillMaxWidth()
                                .heightIn(min = 56.dp)
                                .clickable(role = Role.Button) { expanded = true }
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(12.dp),
                        ) {
                            Text(
                                voxFormat("%lld: %@", slot + 1, target?.name ?: voxString("Empty or unavailable")),
                                style = SignalType.rowTitle,
                                color = if (target == null) c.muted else c.text,
                                modifier = Modifier.weight(1f),
                            )
                            Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null, tint = c.faint, modifier = Modifier.size(20.dp))
                        }
                        DropdownMenu(expanded, { expanded = false }, containerColor = c.card) {
                            DropdownMenuItem(text = { Text(voxString("Empty"), color = c.muted) }, onClick = {
                                selection = selection.copy(slots = selection.slots.toMutableList().apply { set(slot,null) }); expanded = false
                            })
                            presets.filter { it.isEnabled }.forEach { preset ->
                                DropdownMenuItem(text = { Text(preset.name, color = c.text) }, onClick = {
                                    selection = selection.copy(slots = selection.slots.toMutableList().apply { set(slot,preset.id) }); expanded = false
                                })
                            }
                        }
                    }
                }
            }
            Spacer(Modifier.height(16.dp))
            SignalButton(text = voxString("Save widget"), onClick = { save(selection) })
            SignalButton(text = voxString("Cancel"), onClick = cancel, variant = SignalButtonVariant.TERTIARY)
        }
    }
}

/** Radio row choosing where the widget's slots come from. */
@Composable private fun PresetWidgetSourceRow(label: String, selected: Boolean, onClick: () -> Unit) {
    val c = Signal.colors
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(label, style = SignalType.rowTitle, color = c.text, modifier = Modifier.weight(1f))
        RadioButton(selected, null, colors = RadioButtonDefaults.colors(selectedColor = c.accent, unselectedColor = c.borderHi))
    }
}
