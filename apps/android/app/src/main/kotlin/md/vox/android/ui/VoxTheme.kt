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
 * Material 3 tokens for Vox.md ("Vox.md Material 3" design): a warm neutral surface
 * ladder, one indigo primary, a recording red and tonal success / warning / error
 * containers. The field names are kept from the earlier Signal kit so every screen
 * picks the new roles up; the KDoc on each field names the Material role it carries.
 */
@Immutable
data class SignalColors(
    val isDark: Boolean,
    /** `surface`: the page ground. */
    val bg: Color,
    /** `surfaceContainerLow`: tonal cards, list rows and grouped settings. */
    val card: Color,
    /** `surfaceContainerLowest`: the composer sheet on large screens and raised keys. */
    val cardLowest: Color,
    /** `surfaceContainer`: navigation bar and rail containers, media players. */
    val container: Color,
    /** `surfaceContainerHigh`: search fields, neutral icon buttons and chips. */
    val well: Color,
    /** `surfaceContainerHighest`: code / Markdown previews and image placeholders. */
    val wellHigh: Color,
    /** `outlineVariant`: chip and card outlines. */
    val border: Color,
    /** `outline`: outlined buttons and segmented controls. */
    val borderHi: Color,
    val divider: Color,
    /** `onSurface`. */
    val text: Color,
    /** `onSurfaceVariant`. */
    val muted: Color,
    /** `outline` used for placeholder and disabled ink. */
    val faint: Color,
    val disabledFill: Color,
    /** `primary` fill (Speak, filled buttons, the first route tile). */
    val accent: Color,
    /** `onPrimary`. */
    val onAccent: Color,
    /** Interactive tint: links, toggles, focus and progress (`primary`). */
    val tint: Color,
    /** `primaryContainer` (Send, highlighted wiki links). */
    val accentSoft: Color,
    /** `onPrimaryContainer`. */
    val accentText: Color,
    /** `secondaryContainer`: selected chips, nav indicators, tonal buttons. */
    val secondarySoft: Color,
    /** `onSecondaryContainer`. */
    val secondaryText: Color,
    /** `inverseSurface` / `inverseOnSurface`: the second route tile. */
    val inverse: Color,
    val onInverse: Color,
    /** `tertiaryContainer` / `onTertiaryContainer`: neutral route tiles. */
    val tertiarySoft: Color,
    val tertiaryText: Color,
    val recording: Color,
    val onRecording: Color,
    val recordingSoft: Color,
    val error: Color,
    val onError: Color,
    val errorSoft: Color,
    val errorText: Color,
    /** "Needs you" amber. */
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
        bg = Color(0xFFF7F6F2),
        card = Color(0xFFF1F0EB),
        cardLowest = Color(0xFFFFFFFF),
        container = Color(0xFFECEBE5),
        well = Color(0xFFE6E5DF),
        wellHigh = Color(0xFFE0DFD9),
        border = Color(0xFFC7C6CF),
        borderHi = Color(0xFF77767F),
        divider = Color(0xFFE0DFD9),
        text = Color(0xFF1B1B1F),
        muted = Color(0xFF46464F),
        faint = Color(0xFF77767F),
        disabledFill = Color(0xFFE6E5DF),
        accent = Color(0xFF2F3BE8),
        onAccent = Color.White,
        tint = Color(0xFF2F3BE8),
        accentSoft = Color(0xFFE0E0FF),
        accentText = Color(0xFF0A1170),
        secondarySoft = Color(0xFFE0E1F9),
        secondaryText = Color(0xFF181A2C),
        inverse = Color(0xFF303034),
        onInverse = Color(0xFFF3EFF4),
        tertiarySoft = Color(0xFFE3E2DC),
        tertiaryText = Color(0xFF1B1B1F),
        recording = Color(0xFFD7263D),
        onRecording = Color.White,
        recordingSoft = Color(0xFFFFDAD9),
        error = Color(0xFFBA1A1A),
        onError = Color.White,
        errorSoft = Color(0xFFFFDAD6),
        errorText = Color(0xFF410002),
        warning = Color(0xFF8B5000),
        warningSoft = Color(0xFFFFDCBE),
        warningText = Color(0xFF2D1600),
        success = Color(0xFF0F7B5F),
        successSoft = Color(0xFFC9F0DF),
        successText = Color(0xFF00382A),
        pressed = Color(0x1A1B1B1F),
    )

    val Dark = SignalColors(
        isDark = true,
        bg = Color(0xFF131316),
        card = Color(0xFF1B1B1F),
        cardLowest = Color(0xFF0E0E11),
        container = Color(0xFF1F1F23),
        well = Color(0xFF2A292D),
        wellHigh = Color(0xFF353438),
        border = Color(0xFF46464F),
        borderHi = Color(0xFF918F9A),
        divider = Color(0xFF2A292D),
        text = Color(0xFFE5E1E6),
        muted = Color(0xFFC7C5D0),
        faint = Color(0xFF918F9A),
        disabledFill = Color(0xFF2A292D),
        accent = Color(0xFFBEC2FF),
        onAccent = Color(0xFF0E1690),
        tint = Color(0xFFBEC2FF),
        accentSoft = Color(0xFF2F3BE8),
        accentText = Color(0xFFE0E0FF),
        secondarySoft = Color(0xFF44465A),
        secondaryText = Color(0xFFE0E1F9),
        inverse = Color(0xFFE5E1E6),
        onInverse = Color(0xFF303034),
        tertiarySoft = Color(0xFF3F4357),
        tertiaryText = Color(0xFFDDE1F9),
        recording = Color(0xFFFF6B6B),
        onRecording = Color(0xFF2D0004),
        recordingSoft = Color(0xFF5C1A1F),
        error = Color(0xFFFFB4AB),
        onError = Color(0xFF690005),
        errorSoft = Color(0xFF93000A),
        errorText = Color(0xFFFFDAD6),
        warning = Color(0xFFFFB870),
        warningSoft = Color(0xFF5C3500),
        warningText = Color(0xFFFFDCBE),
        success = Color(0xFF7AD9B4),
        successSoft = Color(0xFF0B4F3C),
        successText = Color(0xFFA6F2D2),
        pressed = Color(0x1FE5E1E6),
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

/** Access point for theme tokens inside composables: `Signal.colors.card`. */
object Signal {
    val colors: SignalColors
        @Composable get() = LocalSignalColors.current
}

/** Maps the tokens onto Material 3 roles so stock components follow the design. */
private fun SignalColors.toMaterial(): ColorScheme {
    val base = if (isDark) darkColorScheme() else lightColorScheme()
    return base.copy(
        primary = accent,
        onPrimary = onAccent,
        primaryContainer = accentSoft,
        onPrimaryContainer = accentText,
        inversePrimary = if (isDark) Color(0xFF2F3BE8) else Color(0xFFBEC2FF),
        secondary = if (isDark) Color(0xFFC4C5DD) else Color(0xFF5B5D72),
        onSecondary = if (isDark) Color(0xFF2D2F42) else Color.White,
        secondaryContainer = secondarySoft,
        onSecondaryContainer = secondaryText,
        tertiary = recording,
        onTertiary = onRecording,
        tertiaryContainer = tertiarySoft,
        onTertiaryContainer = tertiaryText,
        background = bg,
        onBackground = text,
        surface = bg,
        onSurface = text,
        surfaceVariant = well,
        onSurfaceVariant = muted,
        surfaceTint = Color.Transparent,
        surfaceBright = if (isDark) Color(0xFF39393C) else Color(0xFFF7F6F2),
        surfaceDim = if (isDark) Color(0xFF131316) else Color(0xFFDDDCD6),
        surfaceContainerLowest = cardLowest,
        surfaceContainerLow = card,
        surfaceContainer = container,
        surfaceContainerHigh = well,
        surfaceContainerHighest = wellHigh,
        inverseSurface = inverse,
        inverseOnSurface = onInverse,
        outline = borderHi,
        outlineVariant = border,
        error = error,
        onError = onError,
        errorContainer = errorSoft,
        onErrorContainer = errorText,
    )
}

/**
 * Geist stays the shared brand typeface (packaged from `Voxboard/Fonts` and pinned by the
 * artifact validators); the Material 3 type scale below sets its sizes and weights.
 */
internal val GeistFontFamily = FontFamily(
    Font(R.font.geist_regular, weight = FontWeight.Normal),
    Font(R.font.geist_medium, weight = FontWeight.Medium),
    Font(R.font.geist_semibold, weight = FontWeight.SemiBold),
)

internal val GeistMonoFontFamily = FontFamily(
    Font(R.font.geist_mono_regular, weight = FontWeight.Normal),
    Font(R.font.geist_mono_medium, weight = FontWeight.Medium),
)

private fun m3(weight: FontWeight, size: Int, line: Int, tracking: Double = 0.0) = TextStyle(
    fontFamily = GeistFontFamily,
    fontWeight = weight,
    fontSize = size.sp,
    lineHeight = line.sp,
    letterSpacing = tracking.em,
)

private val VoxTypography = Typography(
    // Hero copy, e.g. "Say it. It lands in Markdown."
    displayLarge = m3(FontWeight.Medium, 44, 50, -0.02),
    displayMedium = m3(FontWeight.Medium, 34, 40, -0.015),
    displaySmall = m3(FontWeight.Medium, 32, 38, -0.015),
    // Top-level page titles ("History", "Activity").
    headlineLarge = m3(FontWeight.Medium, 28, 36, -0.007),
    headlineMedium = m3(FontWeight.Medium, 24, 32),
    headlineSmall = m3(FontWeight.Medium, 22, 28),
    // Small top app bar titles ("Capture Detail").
    titleLarge = m3(FontWeight.Normal, 22, 28),
    titleMedium = m3(FontWeight.Medium, 16, 24, 0.01),
    titleSmall = m3(FontWeight.SemiBold, 14, 20, 0.007),
    bodyLarge = m3(FontWeight.Normal, 16, 24, 0.03),
    bodyMedium = m3(FontWeight.Normal, 14, 20, 0.018),
    bodySmall = m3(FontWeight.Normal, 12, 16, 0.03),
    labelLarge = m3(FontWeight.SemiBold, 16, 22, 0.006),
    labelMedium = m3(FontWeight.SemiBold, 14, 20, 0.007),
    labelSmall = m3(FontWeight.Medium, 12, 16, 0.04),
)

private val VoxShapes = Shapes(
    extraSmall = RoundedCornerShape(4.dp),
    small = RoundedCornerShape(8.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(28.dp),
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
