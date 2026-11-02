package md.vox.android

import android.content.ClipData
import android.content.ClipboardManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import md.vox.android.capturedomain.*
import java.time.ZoneId
import androidx.compose.foundation.background
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.ui.Alignment
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalDivider
import md.vox.android.ui.SignalFieldShape
import md.vox.android.ui.SignalGroup
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalPillButton
import md.vox.android.ui.SignalRowDivider
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalTextFieldColors

@Composable internal fun AudioFilenameControls(template: String, presetName: String, change: (String) -> Unit) {
    OutlinedTextField(template, { change(it.take(1024)) }, modifier = Modifier.fillMaxWidth(),
        label = { Text(voxString("Audio Filename Template")) }, singleLine = true,
        shape = SignalFieldShape, colors = signalTextFieldColors(),
        supportingText = { Text(voxString("Tokens: {timestamp}, {date}, {time}, {YR}, {id}, {id8}, {preset}, {original}. Leave empty for automatic naming. The recorded format determines the extension.")) })
    val preview = CaptureAudioFilename.render(template, "12345678-1234-4234-8234-123456789abc", 1700000000000,
        presetName, "Recording.wav", zone = ZoneId.of("UTC"))
    if (preview != null) Text(voxFormat("Example: %@", preview), style = SignalType.monoCaption, color = Signal.colors.muted)
}

@Composable internal fun CaptureAppearanceControls(configuration: CaptureBarConfiguration, busy: Boolean,
    setTwentyFourHour: (Boolean) -> Unit, setRailSide: (CaptureRailSide) -> Unit) {
    val c = Signal.colors
    Column(
        Modifier.fillMaxWidth().padding(horizontal = SignalMetrics.PageGutter, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        SignalGroup(voxString("Timestamp Format")) {
            CaptureTimestampFormat.entries.forEachIndexed { index, format ->
                if (index > 0) SignalRowDivider()
                CaptureAppearanceRadioRow(
                    title = if (format == CaptureTimestampFormat.TWELVE_HOUR) voxString("12-hour") else voxString("24-hour"),
                    subtitle = format.render(1700000000000, ZoneId.of("UTC")),
                    selected = configuration.timestampFormat == format,
                    enabled = !busy,
                    testTag = "timestamp-${format.wireName}",
                    onClick = { setTwentyFourHour(format == CaptureTimestampFormat.TWENTY_FOUR_HOUR) },
                )
            }
        }
        SignalGroup(voxString("Pinned Preset Rail")) {
            CaptureRailSide.entries.forEachIndexed { index, side ->
                if (index > 0) SignalRowDivider()
                CaptureAppearanceRadioRow(
                    title = if (side == CaptureRailSide.LEFT) voxString("Left edge") else voxString("Right edge"),
                    subtitle = null,
                    selected = configuration.railSide == side,
                    enabled = !busy,
                    testTag = "rail-${side.name}",
                    onClick = { setRailSide(side) },
                )
            }
        }
    }
    Spacer(Modifier.height(8.dp))
}

@Composable private fun CaptureAppearanceRadioRow(title: String, subtitle: String?, selected: Boolean, enabled: Boolean,
    testTag: String, onClick: () -> Unit) {
    val c = Signal.colors
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp).padding(start = 4.dp, end = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected, onClick = onClick, modifier = Modifier.testTag(testTag), enabled = enabled,
            colors = RadioButtonDefaults.colors(selectedColor = c.tint, unselectedColor = c.faint))
        Column(Modifier.weight(1f).padding(vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SignalType.rowTitle, color = if (enabled) c.text else c.faint)
            if (subtitle != null) Text(subtitle, style = SignalType.monoCaption, color = c.muted)
        }
    }
}

/** Primary content has a stable structural identity through resize, preview and font-scale changes. */
@Composable internal fun CaptureWorkspace(text: String, preset: CapturePreset?, destination: CaptureDestination?,
    route: CaptureRouteOverride?, attachmentCount: Int, modifier: Modifier = Modifier, primary: @Composable () -> Unit) {
    var enabled by rememberSaveable { mutableStateOf(false) }
    BoxWithConstraints(modifier) {
        val supported = maxWidth >= 760.dp && LocalDensity.current.fontScale < 1.5f
        val visible = supported && enabled && (text.isNotBlank() || attachmentCount > 0)
        Row(Modifier.fillMaxSize()) {
            Column(Modifier.weight(1f).fillMaxHeight()) {
                Box {
                    if (supported) SignalPillButton(
                        text = if (enabled) voxString("Hide draft preview") else voxString("Show draft preview"),
                        onClick = { enabled = !enabled },
                        modifier = Modifier.padding(start = SignalMetrics.PageGutter, top = 4.dp),
                        icon = Icons.Outlined.Visibility,
                    )
                }
                Box(Modifier.weight(1f).fillMaxWidth()) { primary() }
            }
            if (visible) {
                VerticalDivider(color = Signal.colors.border)
                CaptureDraftPreview(text, preset?.name.orEmpty(), destination?.displayName,
                    route?.relativeNotePath ?: preset?.let { if (it.noteTargetKind == CaptureNoteTargetKind.EXISTING_NOTE) it.existingNotePath else "${it.logicalFolder}/${it.noteNameTemplate}" },
                    attachmentCount, Modifier.width(300.dp).fillMaxHeight())
            }
        }
    }
}

@Composable internal fun CaptureDraftPreview(text: String, presetName: String, vaultName: String?, path: String?,
    attachmentCount: Int, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val lines = remember(text) { previewLines(text) }
    val c = Signal.colors
    SelectionContainer(modifier.background(c.card)) {
        LazyColumn(contentPadding = PaddingValues(22.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            item {
                Text(voxString("Draft preview"), style = MaterialTheme.typography.titleMedium, color = c.text)
                TextButton(onClick = { context.getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("Markdown", text)) }) {
                    Text(voxString("Copy draft Markdown"))
                }
            }
            itemsIndexed(lines) { _, line ->
                Text(if (line.code) AnnotatedString(line.text) else previewInline(line.text), style = when (line.heading) {
                    1 -> MaterialTheme.typography.headlineMedium
                    2 -> MaterialTheme.typography.headlineSmall
                    3 -> MaterialTheme.typography.titleLarge
                    else -> MaterialTheme.typography.bodyMedium
                }, color = if (line.quote) c.muted else c.text,
                    fontFamily = if (line.code) md.vox.android.ui.GeistMonoFontFamily else null,
                    fontStyle = if (line.quote) FontStyle.Italic else null)
            }
            item {
                SignalDivider()
                Spacer(Modifier.height(12.dp))
                Text(presetName, style = MaterialTheme.typography.titleSmall, color = c.text)
                vaultName?.let { Text(it, style = SignalType.monoCaption, color = c.muted) }
                path?.let { Text(it, style = SignalType.monoCaption, color = c.muted) }
                if (attachmentCount > 0) Text(voxFormat("%lld attachments", attachmentCount), style = SignalType.caption, color = c.muted)
                Spacer(Modifier.height(6.dp))
                Text(voxString("Draft preview. Preset formatting and processing are applied when you send."), style = SignalType.caption, color = c.faint)
            }
        }
    }
}

internal data class PreviewLine(val text: String, val heading: Int = 0, val code: Boolean = false, val quote: Boolean = false)
internal fun previewLines(text: String): List<PreviewLine> {
    var fence: String? = null
    return text.lines().map { line ->
        val trimmed = line.trimStart()
        if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) {
            val mark = trimmed.takeWhile { it == trimmed[0] }
            if (fence == null) fence = mark else if (mark[0] == fence[0] && mark.length >= fence.length) fence = null
            PreviewLine("", code = true)
        } else if (fence != null) PreviewLine(line, code = true)
        else when {
            Regex("^#{1,6} ").containsMatchIn(line) -> PreviewLine(line.substringAfter(' '), line.takeWhile { it == '#' }.length)
            line.startsWith("- [ ] ") -> PreviewLine("☐ " + line.drop(6))
            line.startsWith("- [x] ", true) -> PreviewLine("☑ " + line.drop(6))
            line.startsWith("- ") || line.startsWith("* ") -> PreviewLine("• " + line.drop(2))
            line.startsWith("> ") -> PreviewLine(line.drop(2), quote = true)
            else -> PreviewLine(line)
        }
    }
}

/** Pure text spans: links and remote images never trigger network access. */
internal fun previewInline(text: String): AnnotatedString {
    val builder = AnnotatedString.Builder()
    val pattern = Regex("\\*\\*(.+?)\\*\\*|`([^`]+)`|\\[([^]]+)]\\(([^)]+)\\)|\\*([^*]+)\\*")
    var cursor = 0
    for (match in pattern.findAll(text)) {
        builder.append(text.substring(cursor, match.range.first))
        val group = match.groupValues
        val value = group[1].ifEmpty { group[2].ifEmpty { group[3].ifEmpty { group[5] } } }
        val style = when {
            group[1].isNotEmpty() -> SpanStyle(fontWeight = FontWeight.Bold)
            group[2].isNotEmpty() -> SpanStyle(fontFamily = md.vox.android.ui.GeistMonoFontFamily)
            group[3].isNotEmpty() -> SpanStyle(color = Color(0xFF0070F3))
            else -> SpanStyle(fontStyle = FontStyle.Italic)
        }
        builder.pushStyle(style); builder.append(value); builder.pop(); cursor = match.range.last + 1
    }
    builder.append(text.substring(cursor)); return builder.toAnnotatedString()
}
