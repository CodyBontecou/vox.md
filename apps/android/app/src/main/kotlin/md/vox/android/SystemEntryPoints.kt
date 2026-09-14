package md.vox.android

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.widget.RemoteViews

internal object CaptureEntryIntents {
    fun capture(context: Context, source: String): Intent = Intent(
        Intent.ACTION_VIEW,
        android.net.Uri.parse("voxboard://capture?source=$source"),
        context,
        MainActivity::class.java,
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

    fun record(context: Context, source: String): Intent = Intent(
        Intent.ACTION_VIEW,
        android.net.Uri.parse("voxboard://record?source=$source"),
        context,
        MainActivity::class.java,
    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)

    fun pendingActivity(context: Context, intent: Intent, requestCode: Int): PendingIntent = PendingIntent.getActivity(
        context,
        requestCode,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

class VoxCaptureWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, appWidgetIds: IntArray) {
        appWidgetIds.forEach { widgetID ->
            val views = RemoteViews(context.packageName, R.layout.widget_capture).apply {
                setOnClickPendingIntent(
                    R.id.widget_capture,
                    CaptureEntryIntents.pendingActivity(context, CaptureEntryIntents.capture(context, "widget"), widgetID * 2),
                )
                setOnClickPendingIntent(
                    R.id.widget_record,
                    CaptureEntryIntents.pendingActivity(context, CaptureEntryIntents.record(context, "widget"), widgetID * 2 + 1),
                )
            }
            manager.updateAppWidget(widgetID, views)
        }
    }

    companion object {
        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, VoxCaptureWidgetProvider::class.java)
            val ids = manager.getAppWidgetIds(component)
            if (ids.isNotEmpty()) VoxCaptureWidgetProvider().onUpdate(context, manager, ids)
        }
    }
}

class CaptureTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.apply {
            state = Tile.STATE_ACTIVE
            label = getString(R.string.tile_capture_label)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                subtitle = getString(R.string.tile_capture_subtitle)
            }
            updateTile()
        }
    }

    @SuppressLint("StartActivityAndCollapseDeprecated") // Required fallback below Android 14.
    override fun onClick() {
        super.onClick()
        val launch = CaptureEntryIntents.pendingActivity(this, CaptureEntryIntents.capture(this, "quick-settings"), 4_201)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(launch)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(CaptureEntryIntents.capture(this, "quick-settings"))
        }
    }
}
