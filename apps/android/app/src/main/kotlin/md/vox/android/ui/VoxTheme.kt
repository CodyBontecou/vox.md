package md.vox.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape
import md.vox.android.R

object VoxColors {
    val BackgroundLight = Color(0xFFE2E4E8)
    val BackgroundDark = Color(0xFF1A1A1C)
    val TextLight = Color(0xFF171717)
    val TextDark = Color(0xFFEDEDED)
    val MutedLight = Color(0xFF4D4D4D)
    val MutedDark = Color(0xFFA0A0A0)
    val BorderLight = Color(0x24000000)
    val BorderDark = Color(0x3DFFFFFF)
    val Blue = Color(0xFF006BFF)
    val BlueDark = Color(0xFF47A8FF)
    val Red = Color(0xFFD8001B)
    val RedDark = Color(0xFFFF565F)
    val Amber = Color(0xFFAA4D00)
    val AmberDark = Color(0xFFFF9300)
    val Green = Color(0xFF107D32)
    val GreenDark = Color(0xFF00CA50)
}

private val VoxLightColors = lightColorScheme(
    primary = VoxColors.Blue,
    onPrimary = Color.White,
    background = VoxColors.BackgroundLight,
    onBackground = VoxColors.TextLight,
    surface = VoxColors.BackgroundLight,
    onSurface = VoxColors.TextLight,
    surfaceVariant = Color(0x14000000),
    onSurfaceVariant = VoxColors.MutedLight,
    outline = VoxColors.BorderLight,
    error = VoxColors.Red,
)

private val VoxDarkColors = darkColorScheme(
    primary = VoxColors.BlueDark,
    onPrimary = Color.Black,
    background = VoxColors.BackgroundDark,
    onBackground = VoxColors.TextDark,
    surface = VoxColors.BackgroundDark,
    onSurface = VoxColors.TextDark,
    surfaceVariant = Color(0x24FFFFFF),
    onSurfaceVariant = VoxColors.MutedDark,
    outline = VoxColors.BorderDark,
    error = VoxColors.RedDark,
)

internal val GeistFontFamily = FontFamily(
    Font(R.font.geist_regular, weight = FontWeight.Normal),
    Font(R.font.geist_medium, weight = FontWeight.Medium),
    Font(R.font.geist_semibold, weight = FontWeight.SemiBold),
)

internal val GeistMonoFontFamily = FontFamily(
    Font(R.font.geist_mono_regular, weight = FontWeight.Normal),
    Font(R.font.geist_mono_medium, weight = FontWeight.Medium),
)

private val VoxTypography = Typography(
    displayLarge = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 32.sp, lineHeight = 38.sp),
    displayMedium = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 32.sp, lineHeight = 38.sp),
    displaySmall = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, lineHeight = 30.sp),
    headlineLarge = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 32.sp, lineHeight = 38.sp),
    headlineMedium = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, lineHeight = 30.sp),
    headlineSmall = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, lineHeight = 26.sp),
    titleLarge = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, lineHeight = 30.sp),
    titleMedium = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 22.sp),
    titleSmall = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, lineHeight = 20.sp),
    bodyLarge = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.Normal, fontSize = 13.sp, lineHeight = 18.sp),
    labelLarge = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp),
    labelMedium = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 18.sp),
    labelSmall = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp),
)

private val VoxShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(6.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(16.dp),
)

@Composable
fun VoxTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    MaterialTheme(
        colorScheme = if (darkTheme) VoxDarkColors else VoxLightColors,
        typography = VoxTypography,
        shapes = VoxShapes,
        content = content,
    )
}
