package md.vox.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import md.vox.android.R

/**
 * Tokens for the "Signal" design shared with the iOS app (`Voxboard/GeistTheme.swift`):
 * a warm paper ground, near-black ink, white bordered cards, one indigo accent and a
 * recording red. Dark mode inverts to a near-black ground with raised charcoal cards.
 */
@Immutable
data class SignalColors(
    val isDark: Boolean,
    /** Page ground (warm paper / near-black). */
    val bg: Color,
    /** White bordered cards, list rows and grouped settings. */
    val card: Color,
    /** Composer sheet on large screens and raised keys (the card). */
    val cardLowest: Color,
    /** Rail and media player containers (the card). */
    val container: Color,
    /** Inset wells, segmented-control tracks and neutral chips. */
    val well: Color,
    /** Code / Markdown previews and image placeholders (the well). */
    val wellHigh: Color,
    /** Hairline card and chip border. */
    val border: Color,
    /** Stronger border for pressed and outlined controls. */
    val borderHi: Color,
    val divider: Color,
    /** Near-black ink; also the primary button fill. */
    val text: Color,
    val muted: Color,
    /** Placeholder and disabled ink. */
    val faint: Color,
    val disabledFill: Color,
    /** Fixed indigo fill for Send and the first route tile in both modes. */
    val accent: Color,
    val onAccent: Color,
    /** Interactive tint: links, toggles, focus and progress. */
    val tint: Color,
    /** Soft indigo for highlights and the DEFAULT badge. */
    val accentSoft: Color,
    val accentText: Color,
    /** Selected chips and rail indicators (the well). */
    val secondarySoft: Color,
    val secondaryText: Color,
    /** Ink fill for the second route tile. */
    val inverse: Color,
    val onInverse: Color,
    /** Neutral route tiles (the well). */
    val tertiarySoft: Color,
    val tertiaryText: Color,
    val recording: Color,
    val onRecording: Color,
    val recordingSoft: Color,
    val error: Color,
    val onError: Color,
    val errorSoft: Color,
    val errorText: Color,
    /** "Needs you" orange. */
    val warning: Color,
    val warningSoft: Color,
    val warningText: Color,
    /** Delivered green. */
    val success: Color,
    val successSoft: Color,
    val successText: Color,
    val pressed: Color,
)

object VoxColors {
    val Light = SignalColors(
        isDark = false,
        bg = Color(0xFFF2F2EE),
        card = Color(0xFFFFFFFF),
        cardLowest = Color(0xFFFFFFFF),
        container = Color(0xFFFFFFFF),
        well = Color(0xFFE3E3DC),
        wellHigh = Color(0xFFE3E3DC),
        border = Color(0xFFDEDED8),
        borderHi = Color(0xFFC9C9C3),
        divider = Color(0xFFECECE6),
        text = Color(0xFF121212),
        muted = Color(0xFF5E5E5A),
        faint = Color(0xFF8A8A85),
        disabledFill = Color(0xFFF7F7F4),
        accent = Color(0xFF2F3BE8),
        onAccent = Color.White,
        tint = Color(0xFF2F3BE8),
        accentSoft = Color(0xFFE6E6FC),
        accentText = Color(0xFF2F3BE8),
        secondarySoft = Color(0xFFE3E3DC),
        secondaryText = Color(0xFF121212),
        inverse = Color(0xFF121212),
        onInverse = Color(0xFFF2F2EE),
        tertiarySoft = Color(0xFFE3E3DC),
        tertiaryText = Color(0xFF121212),
        recording = Color(0xFFF0474A),
        onRecording = Color.White,
        recordingSoft = Color(0xFFFDEEEE),
        error = Color(0xFFC42A2D),
        onError = Color.White,
        errorSoft = Color(0xFFFDEEEE),
        errorText = Color(0xFFC42A2D),
        warning = Color(0xFFE8590C),
        warningSoft = Color(0xFFFDF0E8),
        warningText = Color(0xFFC2410C),
        success = Color(0xFF0F7B5F),
        successSoft = Color(0xFFE7F4EF),
        successText = Color(0xFF0F7B5F),
        pressed = Color(0x12121212),
    )

    val Dark = SignalColors(
        isDark = true,
        bg = Color(0xFF0B0B0B),
        card = Color(0xFF161616),
        cardLowest = Color(0xFF161616),
        container = Color(0xFF161616),
        well = Color(0xFF222220),
        wellHigh = Color(0xFF222220),
        border = Color(0xFF2A2A28),
        borderHi = Color(0xFF3A3A38),
        divider = Color(0xFF1C1C1C),
        text = Color(0xFFF4F4F1),
        muted = Color(0xFF9A9A95),
        faint = Color(0xFF8A8A85),
        disabledFill = Color(0xFF161616),
        accent = Color(0xFF2F3BE8),
        onAccent = Color.White,
        tint = Color(0xFF9DA4FF),
        accentSoft = Color(0xFF1B1E4A),
        accentText = Color(0xFF9DA4FF),
        secondarySoft = Color(0xFF222220),
        secondaryText = Color(0xFFF4F4F1),
        inverse = Color(0xFFF4F4F1),
        onInverse = Color(0xFF0B0B0B),
        tertiarySoft = Color(0xFF222220),
        tertiaryText = Color(0xFFF4F4F1),
        recording = Color(0xFFF0474A),
        onRecording = Color.White,
        recordingSoft = Color(0xFF2A1112),
        error = Color(0xFFFF7A7C),
        onError = Color(0xFF0B0B0B),
        errorSoft = Color(0xFF2A1112),
        errorText = Color(0xFFFF7A7C),
        warning = Color(0xFFFF8A4C),
        warningSoft = Color(0xFF2A1508),
        warningText = Color(0xFFFF8A4C),
        success = Color(0xFF4CC9A0),
        successSoft = Color(0xFF0D251E),
        successText = Color(0xFF4CC9A0),
        pressed = Color(0x14F4F4F1),
    )

    // Earlier names, kept for existing call sites and tests.
    val BackgroundLight = Light.bg
    val BackgroundDark = Dark.bg
    val Blue = Light.accent
    val BlueDark = Dark.tint
    val Red = Light.recording
    val RedDark = Dark.recording
    val Amber = Light.warning
    val AmberDark = Dark.warning
    val Green = Light.success
    val GreenDark = Dark.success
}

val LocalSignalColors = staticCompositionLocalOf { VoxColors.Light }

/** Access point for Signal tokens inside composables: `Signal.colors.card`. */
object Signal {
    val colors: SignalColors
        @Composable get() = LocalSignalColors.current
}

/**
 * Material roles map onto Signal so stock components pick up the design:
 * `primary` is the interactive tint (text buttons, switches, progress, focus),
 * every surface container is the white card, and outlines are the hairline border.
 * Filled actions use the Signal buttons, whose primary fill is ink.
 */
private fun SignalColors.toMaterial(): ColorScheme {
    val base = if (isDark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = tint,
        onPrimary = if (isDark) bg else onAccent,
        primaryContainer = accentSoft,
        onPrimaryContainer = accentText,
        inversePrimary = accent,
        secondary = text,
        onSecondary = bg,
        secondaryContainer = accentSoft,
        onSecondaryContainer = accentText,
        tertiary = recording,
        onTertiary = Color.White,
        tertiaryContainer = recordingSoft,
        onTertiaryContainer = error,
        background = bg,
        onBackground = text,
        surface = bg,
        onSurface = text,
        surfaceVariant = well,
        onSurfaceVariant = muted,
        surfaceTint = Color.Transparent,
        surfaceBright = card,
        surfaceDim = bg,
        surfaceContainerLowest = card,
        surfaceContainerLow = card,
        surfaceContainer = card,
        surfaceContainerHigh = card,
        surfaceContainerHighest = card,
        inverseSurface = text,
        inverseOnSurface = bg,
        outline = borderHi,
        outlineVariant = border,
        error = error,
        onError = Color.White,
        errorContainer = errorSoft,
        onErrorContainer = error,
    )
}

internal val GeistFontFamily = FontFamily(
    Font(R.font.geist_regular, weight = FontWeight.Normal),
    Font(R.font.geist_medium, weight = FontWeight.Medium),
    Font(R.font.geist_semibold, weight = FontWeight.SemiBold),
)

internal val GeistMonoFontFamily = FontFamily(
    Font(R.font.geist_mono_regular, weight = FontWeight.Normal),
    Font(R.font.geist_mono_medium, weight = FontWeight.Medium),
)

private fun geist(weight: FontWeight, size: Int, line: Int, tracking: Double = 0.0) = TextStyle(
    fontFamily = GeistFontFamily,
    fontWeight = weight,
    fontSize = size.sp,
    lineHeight = line.sp,
    letterSpacing = tracking.em,
)

private val VoxTypography = Typography(
    // Hero copy, e.g. "Say it. It lands in Markdown."
    displayLarge = geist(FontWeight.SemiBold, 46, 48, -0.035),
    displayMedium = geist(FontWeight.SemiBold, 34, 38, -0.024),
    displaySmall = geist(FontWeight.SemiBold, 32, 36, -0.025),
    // Signal page titles ("Library", "Settings").
    headlineLarge = geist(FontWeight.SemiBold, 34, 38, -0.024),
    headlineMedium = geist(FontWeight.SemiBold, 24, 30, -0.01),
    headlineSmall = geist(FontWeight.SemiBold, 20, 26),
    titleLarge = geist(FontWeight.SemiBold, 20, 26),
    titleMedium = geist(FontWeight.SemiBold, 17, 22),
    titleSmall = geist(FontWeight.SemiBold, 14, 20),
    bodyLarge = geist(FontWeight.Normal, 16, 24),
    bodyMedium = geist(FontWeight.Normal, 14, 20),
    bodySmall = geist(FontWeight.Normal, 13, 18),
    labelLarge = geist(FontWeight.Medium, 16, 22),
    labelMedium = geist(FontWeight.Medium, 14, 20),
    labelSmall = geist(FontWeight.Medium, 12, 16),
)

private val VoxShapes = Shapes(
    extraSmall = RoundedCornerShape(8.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(18.dp),
    extraLarge = RoundedCornerShape(24.dp),
)

@Composable
fun VoxTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = if (darkTheme) VoxColors.Dark else VoxColors.Light
    CompositionLocalProvider(LocalSignalColors provides colors) {
        MaterialTheme(
            colorScheme = colors.toMaterial(),
            typography = VoxTypography,
            shapes = VoxShapes,
            content = content,
        )
    }
}
