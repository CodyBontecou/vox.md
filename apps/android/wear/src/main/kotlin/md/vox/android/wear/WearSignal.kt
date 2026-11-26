package md.vox.android.wear

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.GenericShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Text

/**
 * The Wear OS translation of the Vox.md "Signal" watch design shared with the Apple Watch app
 * (Voxboard Watch/WatchRecorderView.swift): true-black ground, #1C1C1E surfaces, indigo accent,
 * recording red, Geist and Geist Mono type.
 */
internal object WearSignal {
    val background = Color(0xFF000000)
    val surface = Color(0xFF1C1C1E)
    val surfaceRaised = Color(0xFF3A3A3C)
    val text = Color(0xFFF4F4F1)
    val muted = Color(0xFF9A9A95)
    val idleBar = Color(0xFF48484A)
    val accent = Color(0xFF8A8FFF)
    val accentFill = Color(0xFF2F3BE8)
    val red = Color(0xFFF0474A)
    val redText = Color(0xFFFF8A8C)
    val green = Color(0xFF4CC9A0)
    val greenBackground = Color(0xFF0F3B2E)
}

/** Lettered circle identifying a capture preset. Fill cycles accent, light, graphite like iOS route tiles. */
@Composable
internal fun WearPresetTile(name: String, index: Int, size: Dp = 26.dp) {
    val (fill, letter) = when (index % 3) {
        0 -> WearSignal.accentFill to Color.White
        1 -> WearSignal.text to Color.Black
        else -> WearSignal.surfaceRaised to WearSignal.text
    }
    Box(
        modifier = Modifier.size(size).clip(CircleShape).background(fill),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = name.trim().take(1).uppercase(),
            color = letter,
            fontWeight = FontWeight.Bold,
            fontSize = (size.value * 0.45f).sp,
        )
    }
}

/** Flat top with rounded shoulders, bottom bowed to follow the round display's lower edge. */
private val WearEdgeShape = GenericShape { size, _ ->
    val width = size.width
    val height = size.height
    val shoulder = height * 0.45f
    moveTo(0f, shoulder)
    arcTo(Rect(0f, 0f, shoulder * 2, shoulder * 2), 180f, 90f, false)
    lineTo(width - shoulder, 0f)
    arcTo(Rect(width - shoulder * 2, 0f, width, shoulder * 2), 270f, 90f, false)
    cubicTo(width, height * 0.85f, width * 0.78f, height, width * 0.5f, height)
    cubicTo(width * 0.22f, height, 0f, height * 0.85f, 0f, shoulder)
    close()
}

/** The one prominent action of a screen, hugging the bottom of the round display. */
@Composable
internal fun WearEdgeButton(
    label: String,
    description: String,
    background: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    glyph: WearGlyph? = null,
) {
    Box(
        modifier = modifier
            .fillMaxWidth(0.64f)
            .height(62.dp)
            .clip(WearEdgeShape)
            .background(if (enabled) background else background.copy(alpha = 0.55f))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier.padding(bottom = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(7.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (glyph != null) WearGlyphIcon(glyph, Color.White, 12.dp)
            Text(label, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Secondary full-width capsule, used for actions below the fold. */
@Composable
internal fun WearPillButton(
    label: String,
    description: String,
    glyph: WearGlyph,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    contentColor: Color = WearSignal.text,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .height(46.dp)
            .clip(RoundedCornerShape(50))
            .background(WearSignal.surface)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        horizontalArrangement = Arrangement.spacedBy(7.dp, Alignment.CenterHorizontally),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        WearGlyphIcon(glyph, contentColor, 12.dp)
        Text(label, color = contentColor, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
    }
}

internal enum class WearGlyph { STOP, PAUSE, PLAY, CANCEL, CHECK, SAVED }

/** Small vector glyphs drawn in place, so the watch needs no icon font or extra dependency. */
@Composable
internal fun WearGlyphIcon(glyph: WearGlyph, color: Color, size: Dp, modifier: Modifier = Modifier) {
    Canvas(modifier.size(size)) {
        val w = this.size.width
        val stroke = Stroke(width = w * 0.17f, cap = StrokeCap.Round, join = StrokeJoin.Round)
        when (glyph) {
            WearGlyph.STOP -> drawRoundRect(color, cornerRadius = CornerRadius(w * 0.22f))
            WearGlyph.PAUSE -> {
                drawLine(color, Offset(w * 0.3f, w * 0.12f), Offset(w * 0.3f, w * 0.88f), stroke.width, StrokeCap.Round)
                drawLine(color, Offset(w * 0.7f, w * 0.12f), Offset(w * 0.7f, w * 0.88f), stroke.width, StrokeCap.Round)
            }
            WearGlyph.PLAY -> drawPath(
                Path().apply {
                    moveTo(w * 0.22f, w * 0.1f)
                    lineTo(w * 0.9f, w * 0.5f)
                    lineTo(w * 0.22f, w * 0.9f)
                    close()
                },
                color,
            )
            WearGlyph.CANCEL -> {
                drawLine(color, Offset(w * 0.15f, w * 0.15f), Offset(w * 0.85f, w * 0.85f), stroke.width, StrokeCap.Round)
                drawLine(color, Offset(w * 0.85f, w * 0.15f), Offset(w * 0.15f, w * 0.85f), stroke.width, StrokeCap.Round)
            }
            WearGlyph.CHECK -> drawPath(
                Path().apply {
                    moveTo(w * 0.12f, w * 0.52f)
                    lineTo(w * 0.4f, w * 0.78f)
                    lineTo(w * 0.88f, w * 0.24f)
                },
                color,
                style = stroke,
            )
            WearGlyph.SAVED -> drawPath(
                Path().apply {
                    moveTo(w * 0.5f, w * 0.1f)
                    lineTo(w * 0.5f, w * 0.64f)
                    moveTo(w * 0.24f, w * 0.42f)
                    lineTo(w * 0.5f, w * 0.66f)
                    lineTo(w * 0.76f, w * 0.42f)
                    moveTo(w * 0.14f, w * 0.88f)
                    lineTo(w * 0.86f, w * 0.88f)
                },
                color,
                style = stroke,
            )
        }
    }
}

/** Rolling microphone level history; the five newest bars are recording red while live. */
@Composable
internal fun WearLevelWaveform(levels: List<Float>, isPaused: Boolean, modifier: Modifier = Modifier) {
    Canvas(modifier) {
        if (levels.isEmpty()) return@Canvas
        val gap = 2.dp.toPx()
        val minimum = 3.dp.toPx()
        val barWidth = (size.width - gap * (levels.size - 1)) / levels.size
        levels.forEachIndexed { index, level ->
            val barHeight = minimum + level.coerceIn(0f, 1f) * (size.height - minimum)
            val color = if (!isPaused && index >= levels.size - 5) WearSignal.red else WearSignal.idleBar
            drawRoundRect(
                color = color,
                topLeft = Offset(index * (barWidth + gap), (size.height - barHeight) / 2),
                size = Size(barWidth, barHeight),
                cornerRadius = CornerRadius(1.dp.toPx()),
            )
        }
    }
}
