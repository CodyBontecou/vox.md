package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CloudOff
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.OffsetMapping
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import md.vox.android.capturedomain.LiveNoteConflict
import md.vox.android.capturedomain.LiveNoteDiffKind
import md.vox.android.capturedomain.LiveNoteRange
import md.vox.android.capturedomain.LiveNoteRelease
import md.vox.android.capturedomain.LiveNoteStatus
import md.vox.android.ui.GeistMonoFontFamily
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalType

/** "Vox Notes / Inbox / Radiator follow-up.md": the vault name, then the path segments. */
internal fun liveNoteBreadcrumb(vaultName: String?, relativePath: String?, heading: String? = null): String {
    val parts = listOfNotNull(vaultName?.takeIf(String::isNotBlank)) + relativePath.orEmpty().split('/').filter(String::isNotBlank)
    val crumb = parts.joinToString(" / ")
    return if (heading.isNullOrBlank()) crumb else "$crumb · $heading"
}

@Composable
internal fun liveNoteStatusLabel(status: LiveNoteStatus): String = when (status) {
    LiveNoteStatus.BLANK -> voxString("Saves as you go")
    LiveNoteStatus.SAVING -> voxString("Saving…")
    LiveNoteStatus.SAVED -> voxString("Saved")
    LiveNoteStatus.CONFLICT -> voxString("Not saved")
    LiveNoteStatus.OFFLINE -> voxString("On this phone only")
}

/** The pill next to the path: grey idle, indigo saving, green saved, amber conflict/offline. */
@Composable
internal fun LiveNoteStatusPill(status: LiveNoteStatus, modifier: Modifier = Modifier) {
    val c = Signal.colors
    val (fill, ink) = when (status) {
        LiveNoteStatus.BLANK -> c.well to c.muted
        LiveNoteStatus.SAVING -> c.accentSoft to c.accentText
        LiveNoteStatus.SAVED -> c.successSoft to c.successText
        LiveNoteStatus.CONFLICT, LiveNoteStatus.OFFLINE -> c.warningSoft to c.warningText
    }
    Row(
        modifier = modifier
            .clip(CircleShape)
            .background(fill)
            .padding(horizontal = 10.dp, vertical = 4.dp)
            .semantics { liveRegion = LiveRegionMode.Polite }
            .testTag("live-note-status"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(ink))
        Text(
            liveNoteStatusLabel(status),
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 12.sp, fontWeight = FontWeight.Medium),
            color = ink,
            maxLines = 1,
        )
    }
}

/** Path breadcrumb and status pill under the preset chip. The path is tappable only before the first write. */
@Composable
internal fun LiveNoteCrumb(
    breadcrumb: String,
    status: LiveNoteStatus,
    onPathClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
) {
    val c = Signal.colors
    Row(
        modifier = modifier.fillMaxWidth().heightIn(min = 36.dp).testTag("live-note-crumb"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Text(
            breadcrumb,
            style = SignalType.monoCaption,
            color = c.muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier
                .weight(1f)
                .clip(RoundedCornerShape(8.dp))
                .then(if (onPathClick != null) Modifier.clickable(role = Role.Button, onClick = onPathClick) else Modifier)
                .padding(vertical = 6.dp)
                .testTag("live-note-path"),
        )
        trailing?.invoke()
        LiveNoteStatusPill(status)
    }
}

/** Conflict card: what changed elsewhere, then Use theirs / Keep mine / Save copy. */
@Composable
internal fun LiveNoteConflictBanner(
    conflict: LiveNoteConflict,
    isBusy: Boolean,
    useTheirs: () -> Unit,
    keepMine: () -> Unit,
    saveCopy: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    val shape = RoundedCornerShape(16.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.card)
            .border(1.dp, c.warning.copy(alpha = 0.4f), shape)
            .padding(14.dp)
            .semantics { liveRegion = LiveRegionMode.Polite }
            .testTag("live-note-conflict"),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = c.warningText, modifier = Modifier.size(20.dp).padding(top = 1.dp))
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(voxString("This file changed in another app"), style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold), color = c.text)
                Text(
                    voxString("You both edited it. Choose which version to keep. Saving is paused until you do."),
                    style = SignalType.caption,
                    color = c.muted,
                )
            }
        }
        if (conflict.summary.isNotEmpty()) {
            Column(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(c.bg).padding(horizontal = 10.dp, vertical = 8.dp),
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                conflict.summary.forEach { line ->
                    val added = line.kind == LiveNoteDiffKind.ADDED
                    Text(
                        (if (added) "+ " else "- ") + line.text,
                        style = SignalType.monoCaption,
                        color = if (added) c.successText else c.errorText,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Text(voxString("Changed in another app"), style = SignalType.monoCaption, color = c.muted)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            LiveNoteBannerButton(voxString("Use theirs"), useTheirs, enabled = !isBusy, modifier = Modifier.weight(1f).testTag("live-note-use-theirs"))
            LiveNoteBannerButton(voxString("Keep mine"), keepMine, enabled = !isBusy, primary = true, modifier = Modifier.weight(1f).testTag("live-note-keep-mine"))
            LiveNoteBannerButton(voxString("Save copy"), saveCopy, enabled = !isBusy, modifier = Modifier.weight(1f).testTag("live-note-save-copy"))
        }
    }
}

@Composable
private fun LiveNoteBannerButton(text: String, onClick: () -> Unit, enabled: Boolean, modifier: Modifier = Modifier, primary: Boolean = false) {
    val c = Signal.colors
    val shape = RoundedCornerShape(12.dp)
    Box(
        modifier = modifier
            .heightIn(min = 44.dp)
            .clip(shape)
            .background(if (primary) c.text else c.card)
            .border(1.dp, if (primary) c.text else c.border, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            style = MaterialTheme.typography.labelMedium.copy(fontSize = 13.sp, fontWeight = FontWeight.SemiBold),
            color = (if (primary) c.bg else c.text).copy(alpha = if (enabled) 1f else 0.5f),
            maxLines = 1,
        )
    }
}

/** Vault unreachable: edits stay on the phone and are written once the folder is back. */
@Composable
internal fun LiveNoteOfflineBanner(
    folderName: String,
    relativePath: String?,
    reconnect: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.card)
            .border(1.dp, c.warning.copy(alpha = 0.4f), shape)
            .padding(14.dp)
            .semantics { liveRegion = LiveRegionMode.Polite }
            .testTag("live-note-offline"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(Icons.Outlined.CloudOff, contentDescription = null, tint = c.warningText, modifier = Modifier.size(20.dp).padding(top = 1.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(voxFormat("Can't reach your %@ folder", folderName), style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold), color = c.text)
            Text(
                if (relativePath != null) {
                    voxFormat("Keep going. Your edits are kept on this phone and written to %@ as soon as the folder is available again.", relativePath)
                } else {
                    voxString("Keep going. Your edits are kept on this phone and written as soon as the folder is available again.")
                },
                style = SignalType.caption,
                color = c.muted,
            )
            Text(
                voxString("Reconnect folder"),
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = c.tint,
                modifier = Modifier
                    .clip(RoundedCornerShape(6.dp))
                    .clickable(role = Role.Button, onClick = reconnect)
                    .padding(vertical = 4.dp)
                    .testTag("live-note-reconnect"),
            )
        }
    }
}

/** After New note: "<title> is in <preset>" with the path and Reopen. Dismisses itself. */
@Composable
internal fun LiveNoteReleasedToast(
    release: LiveNoteRelease,
    reopen: () -> Unit,
    dismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    LaunchedEffect(release) {
        delay(6_000)
        dismiss()
    }
    val title = release.title?.takeUnless { it.contains('{') } ?: voxString("Your note")
    val place = release.presetName ?: voxString("your vault")
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(c.inverse)
            .padding(start = 14.dp, end = 8.dp, top = 10.dp, bottom = 10.dp)
            .semantics { liveRegion = LiveRegionMode.Polite }
            .testTag("live-note-toast"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = if (c.isDark) md.vox.android.ui.VoxColors.Light.success else md.vox.android.ui.VoxColors.Dark.success, modifier = Modifier.size(20.dp))
        Column(Modifier.weight(1f)) {
            Text(
                voxFormat("%1\$@ is in %2\$@", title, place),
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = c.onInverse,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            release.relativePath?.takeUnless { it.contains('{') }?.let { path ->
                Text(path, style = SignalType.monoCaption, color = c.onInverse.copy(alpha = 0.7f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (release.binding != null) {
            Text(
                voxString("Reopen"),
                style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
                color = c.onInverse,
                modifier = Modifier
                    .clip(RoundedCornerShape(10.dp))
                    .border(1.dp, c.onInverse.copy(alpha = 0.3f), RoundedCornerShape(10.dp))
                    .clickable(role = Role.Button, onClick = reopen)
                    .padding(horizontal = 12.dp, vertical = 8.dp)
                    .testTag("live-note-reopen"),
            )
        }
    }
}

/** Append presets: the editor shows the whole file; say so and point at the entry. */
@Composable
internal fun LiveNoteWholeFileHint(modifier: Modifier = Modifier) {
    val c = Signal.colors
    Text(
        voxString("Showing the whole file · your entry is highlighted"),
        style = SignalType.caption,
        color = c.muted,
        modifier = modifier.fillMaxWidth().padding(vertical = 6.dp),
    )
}

/**
 * Paints the new entry's background inside the whole-file editor and, when [label] is set,
 * shows a small "JUST ADDED · 0:21" line above the entry's line. The label is display-only:
 * the offset mapping keeps the caret out of it and the file text is never touched.
 */
internal class LiveNoteHighlightTransformation(
    private val range: LiveNoteRange?,
    private val color: Color,
    private val label: String? = null,
    private val labelStyle: SpanStyle? = null,
) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText {
        val start = range?.start?.coerceIn(0, text.length) ?: return TransformedText(text, OffsetMapping.Identity)
        val end = range.end.coerceIn(start, text.length)
        if (start == end) return TransformedText(text, OffsetMapping.Identity)
        if (label == null) {
            val highlighted = buildAnnotatedString {
                append(text)
                addStyle(SpanStyle(background = color), start, end)
            }
            return TransformedText(highlighted, OffsetMapping.Identity)
        }
        val insertAt = text.text.lastIndexOf('\n', (start - 1).coerceAtLeast(0)).let { if (it < 0 || start == 0) 0 else it + 1 }
        val inserted = label + "\n"
        val length = inserted.length
        val transformed = buildAnnotatedString {
            append(text.subSequence(0, insertAt))
            append(inserted)
            append(text.subSequence(insertAt, text.length))
            labelStyle?.let { addStyle(it, insertAt, insertAt + label.length) }
            addStyle(SpanStyle(background = color), insertAt, end + length)
        }
        val mapping = object : OffsetMapping {
            override fun originalToTransformed(offset: Int): Int = if (offset < insertAt) offset else offset + length
            override fun transformedToOriginal(offset: Int): Int = when {
                offset < insertAt -> offset
                offset < insertAt + length -> insertAt
                else -> offset - length
            }
        }
        return TransformedText(transformed, mapping)
    }

    override fun equals(other: Any?): Boolean =
        other is LiveNoteHighlightTransformation && other.range == range && other.color == color && other.label == label

    override fun hashCode(): Int = 31 * (31 * (range?.hashCode() ?: 0) + color.hashCode()) + (label?.hashCode() ?: 0)
}

/** "JUST ADDED", plus "· 0:21" when the entry came from a recording. */
@Composable
internal fun liveNoteJustAddedLabel(recordingDurationMillis: Long?): String {
    val base = voxString("Just added").uppercase(java.util.Locale.getDefault())
    return recordingDurationMillis?.takeIf { it > 0 }?.let { "$base · ${formatTranscriptDuration(it)}" } ?: base
}

@Composable
internal fun liveNoteJustAddedStyle(): SpanStyle = SpanStyle(
    color = Signal.colors.accentText,
    fontSize = 10.5.sp,
    fontWeight = FontWeight.SemiBold,
    letterSpacing = 0.8.sp,
)

/**
 * Recording dock line. Bound: "Writing to Inbox/Note.md as you talk" (indigo, mono, file icon)
 * with the save pill. Not bound yet: "Saves to Inbox/{title}.md when you stop" (muted).
 */
@Composable
internal fun LiveNoteRecordingLine(relativePath: String, isBound: Boolean, status: LiveNoteStatus?, modifier: Modifier = Modifier) {
    val c = Signal.colors
    Row(
        modifier = modifier.fillMaxWidth().testTag("live-note-recording-line"),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (isBound) Icon(Icons.Outlined.Description, contentDescription = null, tint = c.accentText, modifier = Modifier.size(14.dp))
        Text(
            if (isBound) voxFormat("Writing to %@ as you talk", relativePath) else voxFormat("Saves to %@ when you stop", relativePath),
            style = SignalType.monoCaption,
            color = if (isBound) c.accentText else c.muted,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
        if (isBound && status != null) LiveNoteStatusPill(status)
    }
}

/** Keeps the highlighted entry over the same words as the person edits around and inside it. */
internal fun shiftLiveNoteHighlight(range: LiveNoteRange?, before: String, after: String, editStart: Int): LiveNoteRange? {
    range ?: return null
    val delta = after.length - before.length
    if (delta == 0) return range
    return when {
        editStart < range.start -> LiveNoteRange((range.start + delta).coerceAtLeast(0), (range.end + delta).coerceAtLeast(0))
        editStart <= range.end -> LiveNoteRange(range.start, (range.end + delta).coerceAtLeast(range.start))
        else -> range
    }.takeIf { it.end > it.start }
}

@Composable
internal fun liveNoteHighlightColor(): Color = Signal.colors.accentSoft

internal val LiveNoteMonoStyle = androidx.compose.ui.text.TextStyle(fontFamily = GeistMonoFontFamily, fontSize = 12.sp)
