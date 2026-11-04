package md.vox.android

import android.app.Activity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.State
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.window.layout.FoldingFeature
import androidx.window.layout.WindowInfoTracker
import androidx.window.layout.WindowLayoutInfo
import kotlinx.coroutines.flow.emptyFlow
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalMetrics
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.dp

internal enum class VoxWindowWidthClass { COMPACT, MEDIUM, EXPANDED }

internal fun classifyVoxWindowWidth(widthDp: Int): VoxWindowWidthClass = when {
    widthDp >= 840 -> VoxWindowWidthClass.EXPANDED
    widthDp >= 600 -> VoxWindowWidthClass.MEDIUM
    else -> VoxWindowWidthClass.COMPACT
}

@Composable
internal fun currentVoxWindowWidthClass(): VoxWindowWidthClass {
    val widthPixels = LocalWindowInfo.current.containerSize.width
    val widthDp = with(LocalDensity.current) { widthPixels.toDp().value.toInt() }
    return classifyVoxWindowWidth(widthDp)
}

/**
 * The window's current fold, if the device reports one through Jetpack WindowManager.
 * Bounds are in window pixels.
 */
internal data class VoxFold(
    val startPx: Int,
    val endPx: Int,
    val topPx: Int,
    val bottomPx: Int,
    val isVertical: Boolean,
    val isHalfOpened: Boolean,
    val isSeparating: Boolean,
) {
    /** Half-open with a horizontal hinge: the phone stands like a laptop ("tabletop"). */
    val isTabletop: Boolean get() = isHalfOpened && !isVertical
    /** Half-open with a vertical hinge, held like a book. */
    val isBook: Boolean get() = isHalfOpened && isVertical
}

internal fun FoldingFeature.toVoxFold(): VoxFold = VoxFold(
    startPx = bounds.left,
    endPx = bounds.right,
    topPx = bounds.top,
    bottomPx = bounds.bottom,
    isVertical = orientation == FoldingFeature.Orientation.VERTICAL,
    isHalfOpened = state == FoldingFeature.State.HALF_OPENED,
    isSeparating = isSeparating,
)

@Composable
internal fun rememberVoxFold(): VoxFold? {
    val activity = LocalContext.current.findActivity()
    val layoutInfo: State<WindowLayoutInfo?> = remember(activity) {
        activity?.let { WindowInfoTracker.getOrCreate(it).windowLayoutInfo(it as Activity) } ?: emptyFlow()
    }.collectAsState(initial = null)
    return layoutInfo.value?.displayFeatures
        ?.filterIsInstance<FoldingFeature>()
        ?.firstOrNull()
        ?.toVoxFold()
}

/**
 * Splits a container into two panes so neither crosses the hinge. Returns the first
 * pane's width and the gap (both in px) when a vertical fold falls inside the
 * container with at least [minPanePx] on each side, otherwise null.
 */
internal fun splitAroundFold(
    containerStartPx: Int,
    containerWidthPx: Int,
    foldStartPx: Int,
    foldEndPx: Int,
    minPanePx: Int,
    minimumGapPx: Int,
): Pair<Int, Int>? {
    if (containerWidthPx <= 0) return null
    val foldWidth = (foldEndPx - foldStartPx).coerceAtLeast(0)
    val gap = maxOf(foldWidth, minimumGapPx)
    val center = (foldStartPx + foldEndPx) / 2 - containerStartPx
    val first = center - gap / 2
    val second = containerWidthPx - first - gap
    if (first < minPanePx || second < minPanePx) return null
    return first to gap
}

/** Splits a height so the top and bottom panes meet at a horizontal hinge (tabletop). */
internal fun splitAroundHorizontalFold(
    containerTopPx: Int,
    containerHeightPx: Int,
    foldTopPx: Int,
    foldBottomPx: Int,
    minPanePx: Int,
): Pair<Int, Int>? {
    if (containerHeightPx <= 0) return null
    val gap = (foldBottomPx - foldTopPx).coerceAtLeast(0)
    val top = foldTopPx - containerTopPx
    val bottom = containerHeightPx - top - gap
    if (top < minPanePx || bottom < minPanePx) return null
    return top to gap
}

/**
 * List-detail pair for medium and expanded windows. On a foldable with a vertical
 * hinge the panes meet at the hinge, so nothing straddles it; otherwise [first] takes
 * [firstFraction] of the width. The detail pane sits in a 28dp `surfaceContainerLowest`
 * container as in the tablet boards.
 */
@Composable
internal fun HingeAwareTwoPane(
    firstFraction: Float,
    first: @Composable () -> Unit,
    second: @Composable () -> Unit,
    modifier: Modifier = Modifier,
    raiseSecond: Boolean = true,
) {
    val fold = rememberVoxFold()
    val density = LocalDensity.current
    var originX by remember { mutableStateOf(0) }
    var widthPx by remember { mutableStateOf(0) }
    val split = fold?.takeIf { it.isVertical }?.let {
        splitAroundFold(
            containerStartPx = originX,
            containerWidthPx = widthPx,
            foldStartPx = it.startPx,
            foldEndPx = it.endPx,
            minPanePx = with(density) { 280.dp.roundToPx() },
            minimumGapPx = with(density) { 12.dp.roundToPx() },
        )
    }
    val gapDp: Dp = 12.dp
    Row(
        modifier = modifier
            .fillMaxSize()
            .background(Signal.colors.bg)
            .onGloballyPositioned {
                originX = it.positionInWindow().x.toInt()
                widthPx = it.size.width
            },
    ) {
        if (split != null) {
            val (firstPx, gapPx) = split
            Box(Modifier.width(with(density) { firstPx.toDp() }).fillMaxHeight()) { first() }
            Spacer(Modifier.width(with(density) { gapPx.toDp() }))
        } else {
            Box(Modifier.weight(firstFraction).fillMaxHeight()) { first() }
            Spacer(Modifier.width(gapDp))
        }
        Box(
            Modifier
                .weight(if (split != null) 1f else (1f - firstFraction).coerceAtLeast(0.1f))
                .fillMaxHeight()
                .then(
                    if (raiseSecond) {
                        Modifier
                            .statusBarsPadding()
                            .navigationBarsPadding()
                            .padding(top = 12.dp, bottom = 12.dp, end = 12.dp)
                            .clip(RoundedCornerShape(28.dp))
                            .background(Signal.colors.cardLowest)
                    } else Modifier,
                ),
        ) { second() }
    }
}

@Composable
internal fun AdaptiveDetailPlaceholder(
    title: VoxUiText,
    detail: VoxUiText,
    modifier: Modifier = Modifier,
) {
    Box(
        modifier = modifier
            .fillMaxSize(),
        contentAlignment = Alignment.Center,
    ) {
        Column(
            modifier = Modifier
                .verticalScroll(rememberScrollState())
                .padding(horizontal = SignalMetrics.PageGutter, vertical = 32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            SignalEmptyState(
                icon = Icons.Outlined.Description,
                title = title.localized(),
                message = detail.localized(),
                iconTint = Signal.colors.muted,
                modifier = Modifier.widthIn(max = 420.dp),
            )
        }
    }
}
