package md.vox.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldColors
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp

/** Material 3 spacing, radius and control heights from the Vox.md design. */
object SignalMetrics {
    val CardRadius = 20.dp
    val GroupRadius = 16.dp
    /** Inner corners of segmented list rows (16dp outer, 4dp between rows). */
    val SegmentRadius = 4.dp
    val FieldRadius = 16.dp
    val ControlSmall = 36.dp
    val ControlMedium = 48.dp
    val ControlLarge = 56.dp
    val ControlHero = 64.dp
    /** Square-ish 56dp action buttons (Add media, Send) use a 16dp radius. */
    val ActionRadius = 16.dp
    val PageGutter = 16.dp
}

// region Text styles

object SignalType {
    /** Material list subheader above a group of rows ("Today", "Vault"). */
    val sectionLabel = TextStyle(
        fontFamily = GeistFontFamily,
        fontWeight = FontWeight.SemiBold,
        fontSize = 14.sp,
        lineHeight = 20.sp,
        letterSpacing = 0.007.em,
    )

    /** Mono metadata under a row title: paths, counts, model names. */
    val monoCaption = TextStyle(
        fontFamily = GeistMonoFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 12.sp,
        lineHeight = 16.sp,
    )

    val mono = TextStyle(
        fontFamily = GeistMonoFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 19.sp,
    )

    val rowTitle = TextStyle(
        fontFamily = GeistFontFamily,
        fontWeight = FontWeight.Medium,
        fontSize = 16.sp,
        lineHeight = 24.sp,
    )

    val caption = TextStyle(
        fontFamily = GeistFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 14.sp,
        lineHeight = 20.sp,
    )
}

// endregion

// region Buttons

/**
 * Material 3 button roles: PRIMARY is filled, SECONDARY outlined, TERTIARY a text
 * button, TONAL the secondary-container fill, ACCENT the primary-container fill used
 * by Send, and DESTRUCTIVE the error fill.
 */
enum class SignalButtonVariant { PRIMARY, SECONDARY, TERTIARY, DESTRUCTIVE, ACCENT, TONAL }
enum class SignalButtonSize(val height: Dp, val horizontalPadding: Dp) {
    SMALL(SignalMetrics.ControlSmall, 16.dp),
    MEDIUM(40.dp, 20.dp),
    LARGE(SignalMetrics.ControlLarge, 24.dp),
}

/** Full-pill Material 3 button in one of the [SignalButtonVariant] roles. */
@Composable
fun SignalButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    variant: SignalButtonVariant = SignalButtonVariant.PRIMARY,
    size: SignalButtonSize = SignalButtonSize.LARGE,
    enabled: Boolean = true,
    loading: Boolean = false,
    icon: ImageVector? = null,
    fillWidth: Boolean = size == SignalButtonSize.LARGE,
) {
    val c = Signal.colors
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val (container, content) = when (variant) {
        SignalButtonVariant.PRIMARY -> c.accent to c.onAccent
        SignalButtonVariant.SECONDARY -> (if (pressed) c.pressed else Color.Transparent) to c.tint
        SignalButtonVariant.TERTIARY -> (if (pressed) c.pressed else Color.Transparent) to c.tint
        SignalButtonVariant.DESTRUCTIVE -> c.error to c.onError
        SignalButtonVariant.ACCENT -> c.accentSoft to c.accentText
        SignalButtonVariant.TONAL -> c.secondarySoft to c.secondaryText
    }
    Button(
        onClick = onClick,
        enabled = enabled && !loading,
        modifier = modifier
            .then(if (fillWidth) Modifier.fillMaxWidth() else Modifier)
            .heightIn(min = size.height),
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(
            containerColor = container,
            contentColor = content,
            disabledContainerColor = if (variant == SignalButtonVariant.TERTIARY || variant == SignalButtonVariant.SECONDARY) Color.Transparent else c.disabledFill,
            disabledContentColor = c.faint,
        ),
        border = if (variant == SignalButtonVariant.SECONDARY) BorderStroke(1.dp, if (enabled) c.borderHi else c.border) else null,
        contentPadding = PaddingValues(horizontal = size.horizontalPadding, vertical = 0.dp),
        elevation = null,
        interactionSource = interaction,
    ) {
        if (loading) {
            CircularProgressIndicator(
                modifier = Modifier.size(16.dp),
                strokeWidth = 2.dp,
                color = LocalContentColor.current,
            )
            Spacer(Modifier.width(8.dp))
        } else if (icon != null) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(if (size == SignalButtonSize.SMALL) 16.dp else 18.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(
            text,
            style = if (size == SignalButtonSize.LARGE) MaterialTheme.typography.labelLarge else MaterialTheme.typography.labelMedium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}

/**
 * 48dp Material icon button. Without [filled] it is a standard (transparent) icon
 * button in `onSurfaceVariant`; with [filled] it is a filled icon button.
 */
@Composable
fun SignalCircleButton(
    icon: ImageVector,
    contentDescription: String?,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    diameter: Dp = SignalMetrics.ControlMedium,
    filled: Color? = null,
    contentColor: Color? = null,
    enabled: Boolean = true,
) {
    val c = Signal.colors
    Box(
        modifier = modifier
            .size(diameter)
            .clip(CircleShape)
            .background(filled ?: Color.Transparent)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = contentDescription,
            tint = when {
                !enabled -> c.faint
                contentColor != null -> contentColor
                filled != null -> c.onAccent
                else -> c.muted
            },
            modifier = Modifier.size(24.dp.coerceAtMost(diameter * 0.5f)),
        )
    }
}

/** Outlined Material pill with a short label. */
@Composable
fun SignalPillButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
) {
    val c = Signal.colors
    Row(
        modifier = modifier
            .heightIn(min = 40.dp)
            .clip(CircleShape)
            .border(1.dp, c.borderHi, CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = c.tint, modifier = Modifier.size(18.dp))
        Text(text, style = MaterialTheme.typography.labelMedium, color = c.tint)
    }
}

// endregion

// region Page structure

/**
 * Material 3 top app bar. With [navigateBack] it is a small app bar: a back icon
 * button and a 22sp title on one 64dp row. Without it (a top-level destination) the
 * 28sp headline sits on the row beside the actions. An optional muted [subtitle]
 * follows underneath.
 */
@Composable
fun SignalTopBar(
    title: String,
    navigateBack: (() -> Unit)?,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    backDescription: String = "Back",
    actions: @Composable RowScope.() -> Unit = {},
) {
    val c = Signal.colors
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(c.bg)
            .statusBarsPadding()
            .padding(bottom = 8.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .padding(start = if (navigateBack != null) 4.dp else 20.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            if (navigateBack != null) {
                SignalCircleButton(Icons.AutoMirrored.Outlined.ArrowBack, backDescription, navigateBack, contentColor = c.text)
            }
            Text(
                title,
                style = if (navigateBack != null) MaterialTheme.typography.titleLarge else MaterialTheme.typography.headlineLarge,
                color = c.text,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .weight(1f)
                    .padding(start = if (navigateBack != null) 4.dp else 0.dp)
                    .semantics { heading() },
            )
            actions()
        }
        if (subtitle != null) {
            Text(
                subtitle,
                style = MaterialTheme.typography.bodyMedium,
                color = c.muted,
                modifier = Modifier.padding(horizontal = 20.dp).padding(bottom = 4.dp),
            )
        }
    }
}

@Composable
fun SignalPageTitle(title: String, subtitle: String? = null, modifier: Modifier = Modifier) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.headlineLarge,
            color = Signal.colors.text,
            modifier = Modifier.semantics { heading() },
        )
        if (subtitle != null) {
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = Signal.colors.muted)
        }
    }
}

/** Material list subheader in the primary color ("Today", "Delivered today"). */
@Composable
fun SignalSectionLabel(text: String, modifier: Modifier = Modifier, color: Color = Signal.colors.tint) {
    Text(
        text,
        style = SignalType.sectionLabel,
        color = color,
        modifier = modifier.semantics { heading() },
    )
}

/** Tonal Material card: `surfaceContainerLow`, 20dp radius, no outline by default. */
@Composable
fun SignalCard(
    modifier: Modifier = Modifier,
    padding: PaddingValues = PaddingValues(16.dp),
    radius: Dp = SignalMetrics.CardRadius,
    color: Color = Signal.colors.card,
    borderColor: Color? = null,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(radius)
    Column(
        modifier = modifier
            .clip(shape)
            .background(color)
            .then(if (borderColor != null) Modifier.border(1.dp, borderColor, shape) else Modifier)
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(padding),
        content = content,
    )
}

/**
 * Subheader above a segmented group of rows. Rows share one tonal container with
 * 16dp outer corners; [SignalRowDivider] draws the 2dp surface gap between them.
 */
@Composable
fun SignalGroup(
    title: String?,
    modifier: Modifier = Modifier,
    footer: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (title != null) {
            SignalSectionLabel(title, Modifier.padding(start = 4.dp, top = 16.dp, bottom = 2.dp))
        }
        SignalCard(
            modifier = Modifier.fillMaxWidth(),
            padding = PaddingValues(0.dp),
            radius = SignalMetrics.GroupRadius,
            content = content,
        )
        if (footer != null) {
            Text(
                footer,
                style = SignalType.caption,
                color = Signal.colors.muted,
                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
    }
}

@Composable
fun SignalDivider(modifier: Modifier = Modifier, inset: Dp = 0.dp) {
    HorizontalDivider(modifier = modifier.padding(start = inset), thickness = 1.dp, color = Signal.colors.divider)
}

/** The 2dp surface gap between segmented rows inside a [SignalGroup]. */
@Composable
fun SignalRowDivider() = HorizontalDivider(thickness = 2.dp, color = Signal.colors.bg)

@Composable
private fun SignalChevron() {
    Icon(
        Icons.AutoMirrored.Outlined.KeyboardArrowRight,
        contentDescription = null,
        tint = Signal.colors.muted,
        modifier = Modifier.size(20.dp),
    )
}

/** Leading 40dp circular icon tile; `primary` uses the primary fill. */
@Composable
fun SignalIconTile(icon: ImageVector, modifier: Modifier = Modifier, primary: Boolean = false, size: Dp = 40.dp, tint: Color? = null, fill: Color? = null) {
    val c = Signal.colors
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(fill ?: if (primary) c.accent else c.secondarySoft),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint ?: if (primary) c.onAccent else c.secondaryText, modifier = Modifier.size(size * 0.5f))
    }
}

/** Title + mono subtitle row with optional leading tile, trailing value and chevron. */
@Composable
fun SignalNavRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    value: String? = null,
    icon: ImageVector? = null,
    monoSubtitle: Boolean = true,
    showChevron: Boolean = true,
    enabled: Boolean = true,
    trailing: (@Composable () -> Unit)? = null,
    onClick: (() -> Unit)?,
) {
    val c = Signal.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .then(if (onClick != null) Modifier.clickable(enabled = enabled, onClick = onClick) else Modifier)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (icon != null) SignalIconTile(icon)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SignalType.rowTitle, color = if (enabled) c.text else c.faint)
            if (subtitle != null) {
                Text(subtitle, style = if (monoSubtitle) SignalType.monoCaption else SignalType.caption, color = c.muted)
            }
        }
        if (value != null) {
            Text(value, style = MaterialTheme.typography.bodyMedium, color = c.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 160.dp))
        }
        trailing?.invoke()
        if (onClick != null && showChevron) SignalChevron()
    }
}

@Composable
fun signalSwitchColors() = SwitchDefaults.colors(
    checkedThumbColor = Signal.colors.onAccent,
    checkedTrackColor = Signal.colors.accent,
    checkedBorderColor = Signal.colors.accent,
    uncheckedThumbColor = Signal.colors.borderHi,
    uncheckedTrackColor = Signal.colors.wellHigh,
    uncheckedBorderColor = Signal.colors.borderHi,
)

@Composable
fun SignalSwitch(checked: Boolean, onCheckedChange: ((Boolean) -> Unit)?, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Switch(checked = checked, onCheckedChange = onCheckedChange, modifier = modifier, enabled = enabled, colors = signalSwitchColors())
}

@Composable
fun SignalToggleRow(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    description: String? = null,
    enabled: Boolean = true,
) {
    val c = Signal.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(enabled = enabled, role = Role.Switch) { onCheckedChange(!checked) }
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SignalType.rowTitle, color = if (enabled) c.text else c.faint)
            if (description != null) Text(description, style = SignalType.caption, color = c.muted)
        }
        SignalSwitch(checked = checked, onCheckedChange = null, enabled = enabled)
    }
}

@Composable
fun SignalValueRow(title: String, value: String, modifier: Modifier = Modifier) {
    Row(
        modifier = modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(title, style = SignalType.rowTitle, color = Signal.colors.text, modifier = Modifier.weight(1f))
        Text(value, style = MaterialTheme.typography.bodyMedium, color = Signal.colors.muted, textAlign = TextAlign.End, modifier = Modifier.weight(1f))
    }
}

@Composable
fun SignalActionRow(title: String, onClick: () -> Unit, modifier: Modifier = Modifier, destructive: Boolean = false, icon: ImageVector? = null) {
    val c = Signal.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = if (destructive) c.error else c.text, modifier = Modifier.size(18.dp))
        Text(title, style = SignalType.rowTitle, color = if (destructive) c.error else c.text, modifier = Modifier.weight(1f))
        if (!destructive) SignalChevron()
    }
}

// endregion

// region Routes, chips and badges

enum class SignalRouteTone { PRIMARY, INK, NEUTRAL;
    companion object {
        /** First enabled route primary, second inverse, every other tertiary container. */
        fun forIndex(index: Int?): SignalRouteTone = when (index) {
            0 -> PRIMARY
            1 -> INK
            else -> NEUTRAL
        }
    }
}

/** Rounded letter tile identifying a route (capture preset). */
@Composable
fun SignalRouteTile(
    label: String,
    modifier: Modifier = Modifier,
    size: Dp = 40.dp,
    tone: SignalRouteTone = SignalRouteTone.NEUTRAL,
    circular: Boolean = false,
) {
    val c = Signal.colors
    val (fill, ink) = when (tone) {
        SignalRouteTone.PRIMARY -> c.accent to c.onAccent
        SignalRouteTone.INK -> c.inverse to c.onInverse
        SignalRouteTone.NEUTRAL -> c.tertiarySoft to c.tertiaryText
    }
    val glyph = label.trim().let { trimmed ->
        val first = trimmed.codePointAtOrNull(0) ?: return@let "•"
        String(Character.toChars(first)).uppercase()
    }
    Box(
        modifier = modifier
            .size(size)
            .clip(if (circular) CircleShape else RoundedCornerShape(size * 0.5f))
            .background(fill),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            glyph,
            color = ink,
            style = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.Bold, fontSize = (size.value * 0.4f).sp),
        )
    }
}

private fun String.codePointAtOrNull(index: Int): Int? = if (isEmpty()) null else codePointAt(index)

/** Small 8dp-radius chip for route steps and metadata (`surfaceContainerHigh`). */
@Composable
fun SignalChip(text: String, modifier: Modifier = Modifier, mono: Boolean = false, color: Color = Signal.colors.well, contentColor: Color = Signal.colors.text) {
    Text(
        text,
        style = if (mono) SignalType.monoCaption else MaterialTheme.typography.labelSmall,
        color = contentColor,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier
            .clip(RoundedCornerShape(8.dp))
            .background(color)
            .padding(horizontal = 10.dp, vertical = 6.dp),
    )
}

/** Small label badge such as "Default" (`primaryContainer`). */
@Composable
fun SignalBadge(text: String, modifier: Modifier = Modifier, color: Color = Signal.colors.accentSoft, contentColor: Color = Signal.colors.accentText) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp),
        color = contentColor,
        modifier = modifier
            .clip(RoundedCornerShape(6.dp))
            .background(color)
            .padding(horizontal = 8.dp, vertical = 2.dp),
    )
}

enum class SignalStatus { ACTIVE, NEUTRAL, SUCCESS, WARNING, ERROR, RECORDING }

data class SignalStatusColors(val fill: Color, val ink: Color, val dot: Color)

@Composable
fun signalStatusColors(status: SignalStatus): SignalStatusColors {
    val c = Signal.colors
    return when (status) {
        SignalStatus.ACTIVE -> SignalStatusColors(c.accentSoft, c.accentText, c.tint)
        SignalStatus.NEUTRAL -> SignalStatusColors(c.well, c.muted, c.faint)
        SignalStatus.SUCCESS -> SignalStatusColors(c.successSoft, c.successText, c.success)
        SignalStatus.WARNING -> SignalStatusColors(c.warningSoft, c.warningText, c.warning)
        SignalStatus.ERROR -> SignalStatusColors(c.errorSoft, c.errorText, c.error)
        SignalStatus.RECORDING -> SignalStatusColors(c.recordingSoft, c.text, c.recording)
    }
}

/** Dot + label status chip (8dp radius, tonal container). */
@Composable
fun SignalStatusBadge(text: String, status: SignalStatus, modifier: Modifier = Modifier, liveRegion: Boolean = false) {
    val s = signalStatusColors(status)
    Row(
        modifier = modifier
            .heightIn(min = 32.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(s.fill)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(s.dot))
        Text(
            text,
            style = SignalType.caption.copy(fontSize = 13.sp, fontWeight = FontWeight.Medium),
            color = s.ink,
            maxLines = 1,
            modifier = if (liveRegion) Modifier.semantics { this.liveRegion = LiveRegionMode.Polite } else Modifier,
        )
    }
}

/** `vox.md` mono wordmark with the primary-colored extension. */
@Composable
fun SignalWordmark(modifier: Modifier = Modifier, extensionColor: Color = Signal.colors.tint, size: Int = 15) {
    val c = Signal.colors
    Text(
        buildAnnotatedString {
            withStyle(SpanStyle(color = c.text)) { append("vox") }
            withStyle(SpanStyle(color = extensionColor)) { append(".md") }
        },
        style = TextStyle(fontFamily = GeistMonoFontFamily, fontWeight = FontWeight.Medium, fontSize = size.sp),
        modifier = modifier.semantics { heading() },
    )
}

// endregion

// region States

/**
 * Centered empty / caught-up state: a 72dp tonal tile, a 22sp title and a muted
 * explanation, with an optional action (Activity "All caught up").
 */
@Composable
fun SignalEmptyState(
    icon: ImageVector,
    title: String,
    message: String?,
    modifier: Modifier = Modifier,
    iconTint: Color = Signal.colors.text,
    action: (@Composable () -> Unit)? = null,
) {
    val c = Signal.colors
    Column(
        modifier = modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .clip(RoundedCornerShape(24.dp))
                .background(c.well),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(32.dp))
        }
        Text(title, style = MaterialTheme.typography.headlineSmall, color = c.text, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 4.dp))
        if (message != null) {
            Text(message, style = MaterialTheme.typography.bodyMedium, color = c.muted, textAlign = TextAlign.Center)
        }
        if (action != null) {
            Spacer(Modifier.size(4.dp))
            action()
        }
    }
}

/** Primary-container card for prominent notices ("Your trial has ended"). */
@Composable
fun SignalInvertedCard(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val c = Signal.colors
    SignalCard(modifier = modifier.fillMaxWidth(), color = c.accentSoft, radius = 16.dp, padding = PaddingValues(16.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = c.accentText)
        Spacer(Modifier.size(6.dp))
        Text(message, style = MaterialTheme.typography.bodyMedium, color = c.accentText)
        if (actionLabel != null && onAction != null) {
            Spacer(Modifier.size(12.dp))
            Box(
                Modifier
                    .clip(CircleShape)
                    .background(c.accent)
                    .clickable(role = Role.Button, onClick = onAction)
                    .heightIn(min = 40.dp)
                    .padding(horizontal = 20.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(actionLabel, style = MaterialTheme.typography.labelMedium, color = c.onAccent)
            }
        }
    }
}

/** Tinted inline banner for warnings, errors and confirmations. */
@Composable
fun SignalBanner(
    message: String,
    status: SignalStatus,
    modifier: Modifier = Modifier,
    title: String? = null,
    icon: ImageVector? = null,
    /** Announce [message] politely when it appears or changes. */
    liveRegion: Boolean = false,
    action: (@Composable RowScope.() -> Unit)? = null,
) {
    val s = signalStatusColors(status)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(s.fill)
            .padding(16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = s.ink, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            if (title != null) Text(title, style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold), color = s.ink)
            Text(
                message,
                style = SignalType.caption,
                color = s.ink,
                modifier = if (liveRegion) Modifier.semantics { this.liveRegion = LiveRegionMode.Polite } else Modifier,
            )
        }
        action?.invoke(this)
    }
}

// endregion

// region Fields

/** Outlined Material text field colors: transparent field, outline, primary focus. */
@Composable
fun signalTextFieldColors(): TextFieldColors {
    val c = Signal.colors
    return OutlinedTextFieldDefaults.colors(
        focusedContainerColor = Color.Transparent,
        unfocusedContainerColor = Color.Transparent,
        disabledContainerColor = Color.Transparent,
        errorContainerColor = Color.Transparent,
        focusedBorderColor = c.tint,
        unfocusedBorderColor = c.borderHi,
        disabledBorderColor = c.border,
        errorBorderColor = c.error,
        focusedTextColor = c.text,
        unfocusedTextColor = c.text,
        focusedLabelColor = c.tint,
        unfocusedLabelColor = c.muted,
        focusedPlaceholderColor = c.faint,
        unfocusedPlaceholderColor = c.faint,
        focusedSupportingTextColor = c.muted,
        unfocusedSupportingTextColor = c.muted,
        cursorColor = c.tint,
    )
}

val SignalFieldShape: Shape = RoundedCornerShape(12.dp)

/** Material 3 search bar: 56dp `surfaceContainerHigh` pill, as on History. */
@Composable
fun SignalSearchField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    modifier: Modifier = Modifier,
    contentDescription: String? = placeholder,
) {
    val c = Signal.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 56.dp)
            .clip(CircleShape)
            .background(c.well)
            .padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Outlined.Search, contentDescription = null, tint = c.muted, modifier = Modifier.size(24.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = c.muted)
            androidx.compose.foundation.text.BasicTextField(
                value = value,
                onValueChange = onValueChange,
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = c.text),
                cursorBrush = androidx.compose.ui.graphics.SolidColor(c.tint),
                modifier = Modifier
                    .fillMaxWidth()
                    .semantics { if (contentDescription != null) this.contentDescription = contentDescription },
            )
        }
    }
}

// endregion

/** Provides Signal content color to a subtree (for icons inside custom surfaces). */
@Composable
fun WithSignalContentColor(color: Color, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalContentColor provides color, content = content)
}

/** Annotated helper so call sites can colour part of a string with the accent. */
fun accentAnnotated(prefix: String, accent: String, accentColor: Color): AnnotatedString = buildAnnotatedString {
    append(prefix)
    withStyle(SpanStyle(color = accentColor)) { append(accent) }
}
