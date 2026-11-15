package md.vox.android

import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.EaseOut
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.gestures.BringIntoViewSpec
import androidx.compose.foundation.gestures.LocalBringIntoViewSpec
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import md.vox.android.ui.Signal

/**
 * Phone capture header floating over the note (port of iOS `QuickCaptureFloatingChrome`).
 * The note scrolls up beneath it; while the writer drags or flings, the header gets out
 * of the way, and once the note comes to rest it returns over a soft scroll edge.
 */
internal data class CaptureFloatingHeaderState(
    /** The writer is dragging or flinging the note (not a programmatic scroll). */
    val isScrolling: Boolean = false,
    /** Text currently sits under the header. */
    val hasContentBeneath: Boolean = false,
) {
    val isHidden: Boolean get() = isScrolling && hasContentBeneath
}

/** Whether a finger is on the note (seen before the text field consumes the touch). */
@Stable
internal class CaptureNoteTouch {
    var touching by mutableStateOf(false)
}

/**
 * Watches touches on the note without consuming them. The editor's text field takes the
 * drag and hands the scroll to the note as a nested scroll, so the note's own
 * [DragInteraction]s never fire; the raw pointer stream is the reliable signal.
 */
internal fun Modifier.trackCaptureNoteTouch(touch: CaptureNoteTouch): Modifier = pointerInput(touch) {
    awaitEachGesture {
        awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        touch.touching = true
        try {
            do {
                val event = awaitPointerEvent(PointerEventPass.Initial)
            } while (event.changes.any { it.pressed })
        } finally {
            touch.touching = false
        }
    }
}

/**
 * Tracks the writer's own scrolling of [scroll]: the note moving while a finger is on it,
 * and the fling after it lifts, until the note has rested for a moment. The caret following
 * typing or speech (bring-into-view) and accessibility scroll actions move the note with no
 * finger on it, so they leave the header in place.
 */
@Composable
internal fun rememberCaptureFloatingHeaderState(
    scroll: ScrollState,
    touch: CaptureNoteTouch,
    enabled: Boolean,
): CaptureFloatingHeaderState {
    var userScrolling by remember { mutableStateOf(false) }
    LaunchedEffect(scroll, touch) {
        var settle: Job? = null
        snapshotFlow { scroll.value }.collect {
            if (!touch.touching && !userScrolling) return@collect
            userScrolling = true
            settle?.cancel()
            settle = launch {
                delay(SettleMillis)
                snapshotFlow { touch.touching }.first { !it }
                userScrolling = false
            }
        }
    }
    val beneath by remember(scroll) { derivedStateOf { scroll.value > 1 } }
    return if (enabled) CaptureFloatingHeaderState(isScrolling = userScrolling, hasContentBeneath = beneath) else CaptureFloatingHeaderState()
}

/** How long the note must stay still (finger up) before the header returns. */
private const val SettleMillis = 180L

/** Height of the soft fade under the header while text sits beneath it. */
private val ScrollEdgeFade = 14.dp

@Composable
internal fun CaptureFloatingHeader(state: CaptureFloatingHeaderState, content: @Composable () -> Unit) {
    val hidden = state.isHidden
    // Leaves quickly when a scroll starts; settles back more slowly
    // (SwiftUI spring(response: 0.42, dampingFraction: 0.86) ≈ stiffness 224).
    val progress by animateFloatAsState(
        targetValue = if (hidden) 1f else 0f,
        animationSpec = if (hidden) tween(180, easing = EaseOut) else spring(dampingRatio = 0.86f, stiffness = 224f),
        label = "captureHeaderHidden",
    )
    val edge by animateFloatAsState(
        targetValue = if (state.hasContentBeneath) 1f else 0f,
        animationSpec = tween(200, easing = EaseInOut),
        label = "captureHeaderEdge",
    )
    // Fully faded out: park the header off the hit path so touches meant for the
    // note under it (another flick) reach the editor. It stays composed, so the
    // pills row keeps its scroll position and the route editor its state.
    val parked = hidden && progress >= 0.99f
    val bg = Signal.colors.bg
    val shift = with(LocalDensity.current) { 18.dp.toPx() }
    val blur: Dp = (6f * progress).coerceAtLeast(0f).dp
    Box(
        Modifier
            .fillMaxWidth()
            // Hidden chrome is not announced or targeted while the note scrolls.
            .then(if (hidden) Modifier.clearAndSetSemantics {} else Modifier)
            .offset { if (parked) IntOffset(0, -1_000_000) else IntOffset.Zero }
            .graphicsLayer {
                alpha = (1f - progress).coerceIn(0f, 1f)
                translationY = -shift * progress
            }
            .then(if (blur > 0.dp) Modifier.blur(blur, BlurredEdgeTreatment.Unbounded) else Modifier)
            .drawWithContent {
                drawContent()
                if (edge > 0f) {
                    val fade = ScrollEdgeFade.toPx()
                    drawRect(
                        Brush.verticalGradient(listOf(bg.copy(alpha = edge), Color.Transparent), startY = size.height, endY = size.height + fade),
                        topLeft = Offset(0f, size.height),
                        size = Size(size.width, fade),
                    )
                }
            },
    ) {
        content()
    }
}

/**
 * Keeps the caret clear of the floating header: bring-into-view (typing, dictation)
 * treats the top [obscured] of the editor viewport as covered.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun ProvideTopObscuredBringIntoView(obscured: Dp, content: @Composable () -> Unit) {
    val base = LocalBringIntoViewSpec.current
    val obscuredPx = with(LocalDensity.current) { obscured.toPx() }
    if (obscuredPx <= 0f) {
        content()
        return
    }
    val spec = remember(base, obscuredPx) {
        object : BringIntoViewSpec {
            override fun calculateScrollDistance(offset: Float, size: Float, containerSize: Float): Float =
                base.calculateScrollDistance(offset - obscuredPx, size, (containerSize - obscuredPx).coerceAtLeast(0f))
        }
    }
    CompositionLocalProvider(LocalBringIntoViewSpec provides spec, content = content)
}
