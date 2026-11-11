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

/** Spacing, radius and control heights shared with iOS `Geist`. */
object SignalMetrics {
    val CardRadius = 18.dp
    val GroupRadius = 16.dp
    val FieldRadius = 14.dp
    val ControlSmall = 32.dp
    val ControlMedium = 48.dp
    val ControlLarge = 52.dp
    val ControlHero = 64.dp
    /** Signal action buttons (Attach, Send) are circles; 999dp clips any size round. */
    val ActionRadius = 999.dp
    /** Rows inside a grouped card share the card's corners; no per-row rounding. */
    val SegmentRadius = 0.dp
    val PageGutter = 16.dp
}

// region Text styles

object SignalType {
    /** Mono uppercase section label above a grouped card ("VAULT"). */
    val sectionLabel = TextStyle(
        fontFamily = GeistMonoFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 11.sp,
        lineHeight = 14.sp,
        letterSpacing = 0.06.em,
    )

    /** Mono metadata under a row title: paths, counts, model names. */
    val monoCaption = TextStyle(
        fontFamily = GeistMonoFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 11.5.sp,
        lineHeight = 15.sp,
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
        lineHeight = 21.sp,
    )

    val caption = TextStyle(
        fontFamily = GeistFontFamily,
        fontWeight = FontWeight.Normal,
        fontSize = 13.sp,
        lineHeight = 18.sp,
    )
}

// endregion

// region Buttons

/** TONAL is a neutral well fill for secondary in-card actions. */
enum class SignalButtonVariant { PRIMARY, SECONDARY, TERTIARY, DESTRUCTIVE, ACCENT, TONAL }
enum class SignalButtonSize(val height: Dp, val horizontalPadding: Dp) {
    SMALL(SignalMetrics.ControlSmall, 12.dp),
    MEDIUM(SignalMetrics.ControlMedium, 16.dp),
    LARGE(SignalMetrics.ControlLarge, 20.dp),
}

/**
 * Capsule button matching iOS `GeistButtonStyle`: ink primary, white bordered
 * secondary, clear tertiary, red destructive, and the indigo accent fill used by Send.
 */
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
        SignalButtonVariant.PRIMARY -> (if (pressed) c.muted else c.text) to c.bg
        SignalButtonVariant.SECONDARY -> (if (pressed) c.divider else c.card) to c.text
        SignalButtonVariant.TERTIARY -> (if (pressed) c.pressed else Color.Transparent) to c.text
        SignalButtonVariant.DESTRUCTIVE -> c.recording to Color.White
        SignalButtonVariant.ACCENT -> c.accent to c.onAccent
        SignalButtonVariant.TONAL -> (if (pressed) c.borderHi else c.well) to c.text
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
            disabledContainerColor = if (variant == SignalButtonVariant.TERTIARY) Color.Transparent else c.disabledFill,
            disabledContentColor = c.faint,
        ),
        border = if (variant == SignalButtonVariant.SECONDARY) BorderStroke(1.dp, if (pressed) c.borderHi else c.border) else null,
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

/** 44dp circular icon button on a bordered card, used for Back, Activity, Settings and Attach. */
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
            .background(filled ?: c.card)
            .then(if (filled == null) Modifier.border(1.dp, c.border, CircleShape) else Modifier)
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
                else -> c.text
            },
            modifier = Modifier.size(diameter * 0.45f),
        )
    }
}

/** Bordered capsule holding a short label, e.g. the "Library" button on Activity. */
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
            .heightIn(min = SignalMetrics.ControlMedium)
            .clip(CircleShape)
            .background(c.card)
            .border(1.dp, c.border, CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = c.text, modifier = Modifier.size(16.dp))
        Text(text, style = MaterialTheme.typography.labelMedium, color = c.text)
    }
}

// endregion

// region Page structure

/**
 * Signal page header: a row of circular controls, then a large 34sp title with an
 * optional muted subtitle. Replaces Material top app bars across the app.
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
    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(Signal.colors.bg)
            .statusBarsPadding()
            .padding(horizontal = SignalMetrics.PageGutter)
            .padding(top = 8.dp, bottom = 12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().heightIn(min = SignalMetrics.ControlMedium),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            if (navigateBack != null) {
                SignalCircleButton(Icons.AutoMirrored.Outlined.ArrowBack, backDescription, navigateBack)
            }
            Spacer(Modifier.weight(1f))
            actions()
        }
        SignalPageTitle(title, subtitle, Modifier.padding(top = 14.dp))
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

/** Mono uppercase label, iOS `GeistSectionLabel`. */
@Composable
fun SignalSectionLabel(text: String, modifier: Modifier = Modifier, color: Color = Signal.colors.muted) {
    Text(
        text.uppercase(),
        style = SignalType.sectionLabel,
        color = color,
        modifier = modifier.semantics { heading() },
    )
}

/** White card with an 18dp radius and a hairline border (iOS `geistCard`). */
@Composable
fun SignalCard(
    modifier: Modifier = Modifier,
    padding: PaddingValues = PaddingValues(16.dp),
    radius: Dp = SignalMetrics.CardRadius,
    color: Color = Signal.colors.card,
    borderColor: Color? = Signal.colors.border,
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

/** Mono section label above a white bordered card of rows (iOS `settingsGroup`). */
@Composable
fun SignalGroup(
    title: String?,
    modifier: Modifier = Modifier,
    footer: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (title != null) {
            SignalSectionLabel(title, Modifier.padding(start = 4.dp, top = 14.dp))
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

/** Divider between rows inside a [SignalGroup]. */
@Composable
fun SignalRowDivider() = SignalDivider(inset = 14.dp)

@Composable
private fun SignalChevron() {
    Icon(
        Icons.AutoMirrored.Outlined.KeyboardArrowRight,
        contentDescription = null,
        tint = Signal.colors.faint,
        modifier = Modifier.size(20.dp),
    )
}

/** Leading 32dp rounded icon tile; `primary` uses the indigo accent fill. */
@Composable
fun SignalIconTile(icon: ImageVector, modifier: Modifier = Modifier, primary: Boolean = false, size: Dp = 32.dp, tint: Color? = null, fill: Color? = null) {
    val c = Signal.colors
    Box(
        modifier = modifier
            .size(size)
            .clip(RoundedCornerShape(size * 0.31f))
            .background(fill ?: if (primary) c.accent else c.well),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint ?: if (primary) c.onAccent else c.text, modifier = Modifier.size(size * 0.5f))
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
            .heightIn(min = 52.dp)
            .then(if (onClick != null) Modifier.clickable(enabled = enabled, onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
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
    checkedThumbColor = Color.White,
    checkedTrackColor = Signal.colors.accent,
    checkedBorderColor = Signal.colors.accent,
    uncheckedThumbColor = Color.White,
    uncheckedTrackColor = Signal.colors.well,
    uncheckedBorderColor = Signal.colors.well,
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
            .heightIn(min = 52.dp)
            .clickable(enabled = enabled, role = Role.Switch) { onCheckedChange(!checked) }
            .padding(horizontal = 14.dp, vertical = 10.dp),
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
        modifier = modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = 14.dp, vertical = 12.dp),
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
            .heightIn(min = 52.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(horizontal = 14.dp, vertical = 12.dp),
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
        /** First enabled route indigo, second ink, every other neutral — as on iOS. */
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
        SignalRouteTone.INK -> c.text to c.bg
        SignalRouteTone.NEUTRAL -> c.well to c.text
    }
    val glyph = label.trim().let { trimmed ->
        val first = trimmed.codePointAtOrNull(0) ?: return@let "•"
        String(Character.toChars(first)).uppercase()
    }
    Box(
        modifier = modifier
            .size(size)
            .clip(if (circular) CircleShape else RoundedCornerShape(size * 0.3f))
            .background(fill),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            glyph,
            color = ink,
            style = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = (size.value * 0.42f).sp),
        )
    }
}

private fun String.codePointAtOrNull(index: Int): Int? = if (isEmpty()) null else codePointAt(index)

/** Small neutral capsule for route steps and metadata. */
@Composable
fun SignalChip(text: String, modifier: Modifier = Modifier, mono: Boolean = false, color: Color = Signal.colors.bg, contentColor: Color = Signal.colors.muted) {
    Text(
        text,
        style = if (mono) SignalType.monoCaption else MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal),
        color = contentColor,
        maxLines = 1,
        overflow = TextOverflow.Ellipsis,
        modifier = modifier
            .clip(CircleShape)
            .background(color)
            .padding(horizontal = 9.dp, vertical = 4.dp),
    )
}

/** Mono uppercase badge such as DEFAULT. */
@Composable
fun SignalBadge(text: String, modifier: Modifier = Modifier, color: Color = Signal.colors.accentSoft, contentColor: Color = Signal.colors.accentText) {
    Text(
        text.uppercase(),
        style = SignalType.monoCaption.copy(fontSize = 10.5.sp, letterSpacing = 0.04.em),
        color = contentColor,
        modifier = modifier
            .clip(RoundedCornerShape(5.dp))
            .background(color)
            .padding(horizontal = 6.dp, vertical = 2.dp),
    )
}

enum class SignalStatus { ACTIVE, NEUTRAL, SUCCESS, WARNING, ERROR, RECORDING }

data class SignalStatusColors(val fill: Color, val ink: Color, val dot: Color)

@Composable
fun signalStatusColors(status: SignalStatus): SignalStatusColors {
    val c = Signal.colors
    return when (status) {
        SignalStatus.ACTIVE -> SignalStatusColors(c.accentSoft, c.accentText, c.accentText)
        SignalStatus.NEUTRAL -> SignalStatusColors(c.well, c.muted, c.faint)
        SignalStatus.SUCCESS -> SignalStatusColors(c.successSoft, c.success, c.success)
        SignalStatus.WARNING -> SignalStatusColors(c.warningSoft, c.warningText, c.warning)
        SignalStatus.ERROR -> SignalStatusColors(c.errorSoft, c.error, c.error)
        SignalStatus.RECORDING -> SignalStatusColors(c.recordingSoft, c.recording, c.recording)
    }
}

/** Dot + label capsule (iOS `GeistStatusBadge`). */
@Composable
fun SignalStatusBadge(text: String, status: SignalStatus, modifier: Modifier = Modifier, liveRegion: Boolean = false) {
    val s = signalStatusColors(status)
    Row(
        modifier = modifier
            .heightIn(min = 26.dp)
            .clip(CircleShape)
            .background(s.fill)
            .padding(horizontal = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(6.dp).clip(CircleShape).background(s.dot))
        Text(
            text,
            style = SignalType.caption.copy(fontSize = 12.sp),
            color = s.ink,
            maxLines = 1,
            modifier = if (liveRegion) Modifier.semantics { this.liveRegion = LiveRegionMode.Polite } else Modifier,
        )
    }
}

/** `vox.md` mono wordmark with the indigo extension. */
@Composable
fun SignalWordmark(modifier: Modifier = Modifier, extensionColor: Color = Signal.colors.accentText, size: Int = 15) {
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
 * Centered empty / caught-up state: a 56dp bordered card tile, a title and a muted
 * explanation, with an optional action (iOS Activity "All caught up").
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
                .size(56.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(c.card)
                .border(1.dp, c.border, RoundedCornerShape(16.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = iconTint, modifier = Modifier.size(26.dp))
        }
        Text(title, style = MaterialTheme.typography.titleLarge, color = c.text, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 4.dp))
        if (message != null) {
            Text(message, style = MaterialTheme.typography.bodyMedium, color = c.muted, textAlign = TextAlign.Center)
        }
        if (action != null) {
            Spacer(Modifier.size(4.dp))
            action()
        }
    }
}

/** Primary-container card for prominent notices, such as the read-only notice. */
@Composable
fun SignalInvertedCard(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    actionLabel: String? = null,
    onAction: (() -> Unit)? = null,
) {
    val c = Signal.colors
    SignalCard(modifier = modifier.fillMaxWidth(), color = c.text, borderColor = null, padding = PaddingValues(16.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall, color = c.bg)
        Spacer(Modifier.size(6.dp))
        Text(message, style = MaterialTheme.typography.bodyMedium, color = c.bg.copy(alpha = 0.78f))
        if (actionLabel != null && onAction != null) {
            Spacer(Modifier.size(12.dp))
            Box(
                Modifier
                    .clip(CircleShape)
                    .background(c.bg)
                    .clickable(role = Role.Button, onClick = onAction)
                    .heightIn(min = 40.dp)
                    .padding(horizontal = 14.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(actionLabel, style = MaterialTheme.typography.labelMedium, color = c.text)
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
            .clip(RoundedCornerShape(SignalMetrics.FieldRadius))
            .background(s.fill)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        if (icon != null) Icon(icon, contentDescription = null, tint = s.ink, modifier = Modifier.size(18.dp))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            if (title != null) Text(title, style = MaterialTheme.typography.titleSmall, color = s.ink)
            Text(
                message,
                style = SignalType.caption,
                color = if (title != null) Signal.colors.text else s.ink,
                modifier = if (liveRegion) Modifier.semantics { this.liveRegion = LiveRegionMode.Polite } else Modifier,
            )
        }
        action?.invoke(this)
    }
}

// endregion

// region Fields

/** Outlined text field colors: white field, hairline border, indigo focus. */
@Composable
fun signalTextFieldColors(): TextFieldColors {
    val c = Signal.colors
    return OutlinedTextFieldDefaults.colors(
        focusedContainerColor = c.card,
        unfocusedContainerColor = c.card,
        disabledContainerColor = c.disabledFill,
        errorContainerColor = c.card,
        focusedBorderColor = c.tint,
        unfocusedBorderColor = c.border,
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

val SignalFieldShape: Shape = RoundedCornerShape(SignalMetrics.FieldRadius)

/** Capsule search field on a card, as on Library. */
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
            .heightIn(min = SignalMetrics.ControlMedium)
            .clip(CircleShape)
            .background(c.card)
            .border(1.dp, c.border, CircleShape)
            .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Outlined.Search, contentDescription = null, tint = c.muted, modifier = Modifier.size(18.dp))
        Box(Modifier.weight(1f)) {
            if (value.isEmpty()) Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = c.faint)
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
