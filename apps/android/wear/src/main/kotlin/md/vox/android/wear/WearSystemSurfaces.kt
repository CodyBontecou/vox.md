package md.vox.android.wear

import android.app.PendingIntent
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.ColorBuilders
import androidx.wear.protolayout.DimensionBuilders
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import com.google.common.util.concurrent.ListenableFuture
import md.vox.android.platformservices.RecordingStatusRegistry

class VoxCaptureTileService : TileService() {
    override fun onTileRequest(requestParams: RequestBuilders.TileRequest): ListenableFuture<TileBuilders.Tile> {
        val state = wearSurfaceState(this)
        return immediateFuture(captureTile(this, state), "Vox.md capture tile")
    }

    override fun onTileResourcesRequest(requestParams: RequestBuilders.ResourcesRequest): ListenableFuture<ResourceBuilders.Resources> =
        immediateFuture(ResourceBuilders.Resources.Builder().setVersion(RESOURCES_VERSION).build(), "Vox.md tile resources")

    companion object { internal const val RESOURCES_VERSION = "vox-capture-v1" }
}

internal fun captureTile(context: Context, state: WearSurfaceState): TileBuilders.Tile {
        val launch = ActionBuilders.LaunchAction.Builder()
            .setAndroidActivity(
                ActionBuilders.AndroidActivity.Builder()
                    .setPackageName(context.packageName)
                    .setClassName(WearMainActivity::class.java.name)
                    .build(),
            )
            .build()
        val click = ModifiersBuilders.Clickable.Builder()
            .setId("open-capture")
            .setOnClick(launch)
            .build()
        val button = LayoutElementBuilders.Box.Builder()
            .setWidth(DimensionBuilders.dp(112f))
            .setHeight(DimensionBuilders.dp(64f))
            .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .setModifiers(
                ModifiersBuilders.Modifiers.Builder()
                    .setBackground(
                        ModifiersBuilders.Background.Builder()
                            .setColor(ColorBuilders.argb(if (state.recording) 0xFFFF565F.toInt() else 0xFFF2F1EE.toInt()))
                            .setCorner(ModifiersBuilders.Corner.Builder().setRadius(DimensionBuilders.dp(32f)).build())
                            .build(),
                    )
                    .setClickable(click)
                    .build(),
            )
            .addContent(tileText(context.getString(if (state.recording) R.string.wear_recording else R.string.wear_record), if (state.recording) 0xFFFFFFFF.toInt() else 0xFF171614.toInt(), 18f))
            .build()
        val column = LayoutElementBuilders.Column.Builder()
            .setWidth(DimensionBuilders.expand())
            .setHeight(DimensionBuilders.expand())
            .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
            .addContent(tileText(context.getString(R.string.wear_brand), 0xFFF2F1EE.toInt(), 16f))
            .addContent(button)
            .addContent(tileText(wearSurfaceDetail(context, state), 0xFFB8B6B2.toInt(), 12f))
            .build()
        val layout = LayoutElementBuilders.Layout.Builder().setRoot(column).build()
        val timeline = TimelineBuilders.Timeline.Builder()
            .addTimelineEntry(TimelineBuilders.TimelineEntry.Builder().setLayout(layout).build())
            .build()
        val tile = TileBuilders.Tile.Builder()
                .setResourcesVersion(VoxCaptureTileService.RESOURCES_VERSION)
                .setFreshnessIntervalMillis(60_000)
                .setTileTimeline(timeline)
                .build()
        return tile
}

private fun tileText(value: String, color: Int, size: Float): LayoutElementBuilders.Text =
    LayoutElementBuilders.Text.Builder()
            .setText(value)
            .setFontStyle(
                LayoutElementBuilders.FontStyle.Builder()
                    .setColor(ColorBuilders.argb(color))
                    .setSize(DimensionBuilders.sp(size))
                    .build(),
            )
            .setMaxLines(1)
            .build()

private fun <T> immediateFuture(value: T, tag: String): ListenableFuture<T> =
    CallbackToFutureAdapter.getFuture { completer ->
        completer.set(value)
        tag
    }

class VoxCaptureComplicationService : SuspendingComplicationDataSourceService() {
    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        if (request.complicationType != ComplicationType.SHORT_TEXT) return null
        return complicationData(this, preview = false)
    }

    override fun getPreviewData(type: ComplicationType): ComplicationData? =
        if (type == ComplicationType.SHORT_TEXT) complicationData(this, preview = true) else null
}

internal data class WearSurfaceState(val recording: Boolean, val queued: Int)

internal data class CaptureTileEvidence(
    val brand: String,
    val action: String,
    val detail: String,
    val clickID: String,
    val launchPackage: String,
    val launchClass: String,
)

internal fun captureTileEvidence(context: Context, state: WearSurfaceState) = CaptureTileEvidence(
    brand = context.getString(R.string.wear_brand),
    action = context.getString(if (state.recording) R.string.wear_recording else R.string.wear_record),
    detail = wearSurfaceDetail(context, state),
    clickID = "open-capture",
    launchPackage = context.packageName,
    launchClass = WearMainActivity::class.java.name,
)

private fun wearSurfaceDetail(context: Context, state: WearSurfaceState): String = when {
    state.recording -> context.getString(R.string.wear_open_controls)
    state.queued == 1 -> context.getString(R.string.wear_one_recording_saved)
    state.queued > 1 -> context.getString(R.string.wear_recordings_saved_count, state.queued)
    else -> context.getString(R.string.wear_ready)
}

private fun wearSurfaceState(context: Context): WearSurfaceState = WearSurfaceState(
    recording = RecordingStatusRegistry.status.value.isActive,
    queued = WearQueueStore.load(context).size,
)

internal fun complicationData(
    context: Context,
    preview: Boolean,
    injectedState: WearSurfaceState? = null,
): ComplicationData {
    val state = injectedState ?: if (preview) WearSurfaceState(recording = false, queued = 0) else wearSurfaceState(context)
    val visibleText = when {
        state.recording -> "REC"
        state.queued > 0 -> state.queued.coerceAtMost(999).toString()
        else -> "VOX"
    }
    val description = when {
        state.recording -> context.getString(R.string.wear_is_recording)
        state.queued == 1 -> context.getString(R.string.wear_one_recording_saved)
        state.queued > 1 -> context.getString(R.string.wear_recordings_saved_count, state.queued)
        else -> context.getString(R.string.wear_quick_capture)
    }
    val intent = Intent(context, WearMainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    val tapAction = PendingIntent.getActivity(
        context,
        9401,
        intent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    return ShortTextComplicationData.Builder(
        PlainComplicationText.Builder(visibleText).build(),
        PlainComplicationText.Builder(description).build(),
    ).setTitle(PlainComplicationText.Builder(context.getString(R.string.wear_brand)).build())
        .setTapAction(tapAction)
        .build()
}

internal object WearSystemSurfaces {
    fun requestRefresh(context: Context) {
        TileService.getUpdater(context).requestUpdate(VoxCaptureTileService::class.java)
        ComplicationDataSourceUpdateRequester.create(
            context,
            ComponentName(context, VoxCaptureComplicationService::class.java),
        ).requestUpdateAll()
    }
}
