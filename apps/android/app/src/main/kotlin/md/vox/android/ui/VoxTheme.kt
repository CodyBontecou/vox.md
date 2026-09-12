package md.vox.android.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.shape.RoundedCornerShape

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

private val VoxTypography = Typography(
    headlineLarge = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.SemiBold, fontSize = 32.sp, lineHeight = 38.sp),
    headlineSmall = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.SemiBold, fontSize = 20.sp, lineHeight = 26.sp),
    titleLarge = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, lineHeight = 30.sp),
    titleMedium = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 22.sp),
    bodyLarge = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Normal, fontSize = 16.sp, lineHeight = 24.sp),
    bodyMedium = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
    labelLarge = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Medium, fontSize = 14.sp, lineHeight = 20.sp),
    labelMedium = TextStyle(fontFamily = FontFamily.SansSerif, fontWeight = FontWeight.Medium, fontSize = 13.sp, lineHeight = 18.sp),
)

private val VoxShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(6.dp),
    medium = RoundedCornerShape(12.dp),
    large = RoundedCornerShape(16.dp),
    extraLarge = RoundedCornerShape(16.dp),
)

@Composable
fun VoxTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = if (isSystemInDarkTheme()) VoxDarkColors else VoxLightColors,
        typography = VoxTypography,
        shapes = VoxShapes,
        content = content,
    )
}
