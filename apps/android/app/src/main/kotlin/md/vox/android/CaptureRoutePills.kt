package md.vox.android

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalRouteTile
import md.vox.android.ui.SignalRouteTone

/** Longest route name the selected pill shows before shortening; TalkBack keeps the full name. */
internal const val ROUTE_PILL_NAME_LIMIT = 24

internal fun routePillName(name: String): String =
    if (name.length <= ROUTE_PILL_NAME_LIMIT) name else name.take(ROUTE_PILL_NAME_LIMIT - 1).trimEnd() + "…"

private val RoutePillsEdgeFade = 28.dp

/** What a route pill shows: the preset's identity, nothing about its destination. */
internal data class CaptureRoutePill(val id: String, val name: String, val emoji: String?) {
    constructor(preset: CapturePreset) : this(preset.id, preset.name, preset.emoji)
}

/**
 * Horizontal route radio row: the capture header's only route switcher, resting or
 * typing (port of iOS `CaptureRoutePillsRow`). Every pill keeps its route-order
 * letter tile; only the selected pill shows the name. Tapping another pill switches
 * the route; tapping the selected one, or long-pressing any pill, opens all presets.
 * Edges fade only while pills are scrolled past them, so the row never ends in a
 * hard cut against the header actions.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun CaptureRoutePillsRow(
    presets: List<CaptureRoutePill>,
    selectedID: String?,
    enabled: Boolean,
    select: (String) -> Unit,
    openPresets: () -> Unit,
    modifier: Modifier = Modifier,
    pillHeight: Dp = 40.dp,
) {
    val c = Signal.colors
    val listState = rememberLazyListState()
    val selectedIndex = presets.indexOfFirst { it.id == selectedID }
    LaunchedEffect(selectedIndex) {
        if (selectedIndex >= 0) listState.animateScrollToItem(selectedIndex)
    }
    val fadesStart = listState.canScrollBackward
    val fadesEnd = listState.canScrollForward
    val routeLabel = voxString("Route")
    val chooseLabel = voxString("Choose Route")
    LazyRow(
        state = listState,
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
            .drawWithContent {
                drawContent()
                val fade = RoutePillsEdgeFade.toPx()
                if (fadesStart) {
                    drawRect(
                        Brush.horizontalGradient(listOf(Color.Transparent, Color.Black), startX = 0f, endX = fade),
                        size = Size(fade, size.height),
                        blendMode = BlendMode.DstIn,
                    )
                }
                if (fadesEnd) {
                    drawRect(
                        Brush.horizontalGradient(listOf(Color.Black, Color.Transparent), startX = size.width - fade, endX = size.width),
                        topLeft = Offset(size.width - fade, 0f),
                        size = Size(fade, size.height),
                        blendMode = BlendMode.DstIn,
                    )
                }
            }
            .semantics { contentDescription = routeLabel }
            .testTag("capture-route-pills"),
        // Lets the last pill scroll fully clear of the trailing fade.
        contentPadding = PaddingValues(end = RoutePillsEdgeFade / 2),
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        itemsIndexed(presets, key = { _, preset -> preset.id }) { index, preset ->
            val on = preset.id == selectedID
            val name = preset.name.trim().ifEmpty { "Default" }
            Row(
                modifier = Modifier
                    .padding(vertical = 2.dp)
                    .height(pillHeight)
                    .clip(CircleShape)
                    .background(if (on) c.card else Color.Transparent)
                    .border(if (on) 1.5.dp else 1.dp, if (on) c.text else c.border, CircleShape)
                    .combinedClickable(
                        enabled = enabled,
                        role = Role.RadioButton,
                        onLongClickLabel = chooseLabel,
                        onClick = { if (on) openPresets() else select(preset.id) },
                        onLongClick = openPresets,
                    )
                    .semantics {
                        contentDescription = name
                        selected = on
                    }
                    .testTag(if (on) "capture-preset-selector" else "capture-route-pill-${preset.id}")
                    .padding(start = if (on) 7.dp else 6.dp, end = if (on) 14.dp else 6.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SignalRouteTile(
                    label = preset.emoji ?: name,
                    size = 26.dp,
                    tone = SignalRouteTone.forIndex(index),
                    circular = true,
                )
                if (on) {
                    Text(
                        routePillName(name),
                        style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                        color = c.text,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}
