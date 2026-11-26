package md.vox.android

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalRouteTile
import md.vox.android.ui.SignalRouteTone

/**
 * Where the phone composer shows its vertical route rail (iOS `CaptureRouteRailPlacement`,
 * #160): a thumb-reach column of routes beside Speak. Physical screen edges, so Left stays
 * on the left in right-to-left layouts too.
 */
internal enum class CaptureRouteRailPlacement(val persistedName: String) {
    OFF("off"),
    LEFT("left"),
    RIGHT("right"),
    ;

    /** The rail's corner of the composer: always the bottom, on the chosen physical edge. */
    val alignment: Alignment
        get() = if (this == RIGHT) AbsoluteAlignment.BottomRight else AbsoluteAlignment.BottomLeft

    companion object {
        fun fromPersistedName(value: String?): CaptureRouteRailPlacement =
            entries.firstOrNull { it.persistedName == value } ?: OFF
    }
}

/**
 * Settings > Capture Bar > Route Rail, remembered on this phone. Off by default. A UI
 * preference like [MarkdownEditorMode], so it lives in the app's own preferences rather
 * than the synced capture bar configuration.
 */
internal object CaptureRouteRail {
    private const val PREFERENCES = "vox_capture_composer"
    internal const val PLACEMENT_KEY = "route_rail_placement"
    private var loaded = false
    private var placement by mutableStateOf(CaptureRouteRailPlacement.OFF)

    fun read(preferences: SharedPreferences): CaptureRouteRailPlacement =
        CaptureRouteRailPlacement.fromPersistedName(preferences.getString(PLACEMENT_KEY, null))

    @Composable
    fun placement(): CaptureRouteRailPlacement {
        val context = LocalContext.current
        if (!loaded) {
            placement = read(context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE))
            loaded = true
        }
        return placement
    }

    fun set(context: Context, value: CaptureRouteRailPlacement) {
        placement = value
        loaded = true
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit()
            .putString(PLACEMENT_KEY, value.persistedName).apply()
    }
}

/** 44dp hit target around a 30dp tile, as on iOS. */
internal val RouteRailHitTarget = 44.dp
private val RouteRailTileSize = 30.dp
private val RouteRailEdgePadding = 4.dp

/** Editor gutter on the rail's side: the rail column and its edge padding, so text never sits under it. */
internal val RouteRailGutter = RouteRailHitTarget + RouteRailEdgePadding * 2

/** The rail is drawn on phones with the setting on, and only when there is more than one route. */
internal fun showsRouteRail(placement: CaptureRouteRailPlacement, isPhone: Boolean, routeCount: Int): Boolean =
    isPhone && placement != CaptureRouteRailPlacement.OFF && routeCount > 1

/**
 * While the rail is drawn it is the route switcher, so the header keeps only the selected
 * route's pill as a label (tester feedback 2026-11-26: the header repeated every route).
 * The rail draws nothing for a single route, so the header keeps that pill either way.
 */
internal fun routeRailReplacesHeaderPills(railShown: Boolean, routeCount: Int): Boolean =
    railShown && routeCount > 1

/**
 * The header pills to draw, each with its position in route order so a pill keeps the
 * same tile tone as its rail tile when the others are hidden.
 */
internal fun visibleRoutePills(
    pills: List<CaptureRoutePill>,
    selectedID: String?,
    showsOnlySelected: Boolean,
): List<IndexedValue<CaptureRoutePill>> {
    val all = pills.withIndex().toList()
    if (!showsOnlySelected) return all
    return all.filter { it.value.id == selectedID }.ifEmpty { all.take(1) }
}

/** The header's pills, with the selected route always present even before the collection loads. */
internal fun captureRoutePills(
    selected: md.vox.android.capturedomain.CapturePreset?,
    routePresets: List<md.vox.android.capturedomain.CapturePreset>,
): List<CaptureRoutePill> = when {
    selected != null && routePresets.none { it.id == selected.id } -> listOf(selected) + routePresets
    else -> routePresets
}.map(::CaptureRoutePill).ifEmpty { listOf(CaptureRoutePill("default", "Default", null)) }

/** A rail tap switches only to another route, and only while the rail is enabled. */
internal fun routeRailSelects(id: String, selectedID: String?, enabled: Boolean, routes: List<CaptureRoutePill>): Boolean =
    enabled && id != selectedID && routes.any { it.id == id }

/**
 * Phone route rail (port of iOS `CaptureRouteSideRail`): route tiles in a column on one
 * screen edge, just above the quick actions and Speak. The first route sits nearest the
 * controls and later routes rise up the edge; a long list scrolls inside the rail, which
 * only takes the height its tiles need, so the editor beside it stays usable.
 */
@Composable
internal fun CaptureRouteSideRail(
    routes: List<CaptureRoutePill>,
    selectedID: String?,
    enabled: Boolean,
    select: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (routes.size < 2) return
    val c = Signal.colors
    val listState = rememberLazyListState()
    val selectedIndex = routes.indexOfFirst { it.id == selectedID }
    LaunchedEffect(selectedIndex) {
        if (selectedIndex >= 0) listState.animateScrollToItem(selectedIndex)
    }
    val routeLabel = voxString("Route")
    val selectedName = routes.getOrNull(selectedIndex)?.name?.trim().orEmpty()
    LazyColumn(
        state = listState,
        // Item 0 at the bottom, nearest Speak; TalkBack still reads routes in route order.
        reverseLayout = true,
        contentPadding = PaddingValues(vertical = RouteRailEdgePadding),
        modifier = modifier
            .padding(horizontal = RouteRailEdgePadding)
            .width(RouteRailHitTarget)
            .alpha(if (enabled) 1f else 0.45f)
            .semantics {
                contentDescription = routeLabel
                stateDescription = selectedName
            }
            .testTag("capture-route-rail"),
    ) {
        itemsIndexed(routes, key = { _, route -> route.id }) { index, route ->
            val on = route.id == selectedID
            val name = route.name.trim().ifEmpty { "Default" }
            Box(
                modifier = Modifier
                    .size(RouteRailHitTarget)
                    .clickable(enabled = enabled, role = Role.RadioButton) {
                        if (routeRailSelects(route.id, selectedID, enabled, routes)) select(route.id)
                    }
                    .semantics {
                        contentDescription = name
                        selected = on
                    }
                    .testTag(if (on) "capture-route-rail-selected" else "capture-route-rail-${route.id}"),
                contentAlignment = Alignment.Center,
            ) {
                Box(
                    Modifier
                        .background(c.bg, CircleShape)
                        .border(if (on) 2.dp else 1.dp, if (on) c.text else c.border, CircleShape)
                        .padding(3.dp),
                ) {
                    SignalRouteTile(
                        label = route.emoji ?: name,
                        size = RouteRailTileSize,
                        tone = SignalRouteTone.forIndex(index),
                        circular = true,
                    )
                }
            }
        }
    }
}
