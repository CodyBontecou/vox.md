package md.vox.android

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedButton
import androidx.compose.ui.Alignment
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalBanner
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalChip
import md.vox.android.ui.SignalDivider
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalIconTile
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalSectionLabel
import md.vox.android.ui.SignalStatus
import md.vox.android.ui.SignalStatusBadge
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalStatusColors
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Button
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import md.vox.android.capturedomain.CaptureHistoryDetail
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureTextProcessingOutcome
import md.vox.android.ui.GeistMonoFontFamily
import java.text.DateFormat
import java.util.Date

internal enum class HistoryExportFormat(val label: String, val extension: String) {
    MARKDOWN("Markdown", "md"),
    TEXT("Plain Text", "txt"),
    JSON("JSON", "json"),
    YAML("YAML", "yaml"),
}

private fun HistoryExportFormat.uiText(): VoxUiText = when (this) {
    HistoryExportFormat.MARKDOWN -> voxUiText("Markdown")
    HistoryExportFormat.TEXT -> voxUiText("Plain Text")
    HistoryExportFormat.JSON -> voxUiText("JSON")
    HistoryExportFormat.YAML -> voxUiText("YAML")
}

internal object HistoryDetailExporter {
    fun render(detail: CaptureHistoryDetail, format: HistoryExportFormat): String {
        val source = buildString {
            if (detail.capturedText.isNotBlank()) append(detail.capturedText.trimEnd())
            detail.capturedURL?.let { url ->
                if (isNotEmpty()) append("\n\n")
                append(url)
            }
        }
        return when (format) {
            HistoryExportFormat.MARKDOWN -> detail.preparedMarkdown ?: source.let { if (it.endsWith('\n')) it else "$it\n" }
            HistoryExportFormat.TEXT -> source.let { if (it.endsWith('\n')) it else "$it\n" }
            HistoryExportFormat.JSON -> buildString {
                append("{\n")
                append("  \"requestID\": \"").append(jsonEscape(detail.requestID)).append("\",\n")
                append("  \"createdAtEpochMillis\": ").append(detail.createdAtEpochMillis).append(",\n")
                append("  \"state\": \"").append(detail.state.name.lowercase()).append("\",\n")
                append("  \"presetID\": \"").append(jsonEscape(detail.presetID)).append("\",\n")
                append("  \"logicalPath\": ").append(detail.logicalPath?.let { "\"${jsonEscape(it)}\"" } ?: "null").append(",\n")
                append("  \"text\": \"").append(jsonEscape(detail.capturedText)).append("\",\n")
                append("  \"originalText\": ").append(detail.originalCapturedText?.let { "\"${jsonEscape(it)}\"" } ?: "null").append(",\n")
                append("  \"processingMode\": ").append(detail.processingMode?.let { "\"${it.name.lowercase()}\"" } ?: "null").append(",\n")
                append("  \"processingOutcome\": ").append(detail.processingOutcome?.let { "\"${it.name.lowercase()}\"" } ?: "null").append(",\n")
                append("  \"url\": ").append(detail.capturedURL?.let { "\"${jsonEscape(it)}\"" } ?: "null").append(",\n")
                append("  \"attachments\": [")
                detail.attachments.forEachIndexed { index, attachment ->
                    if (index > 0) append(", ")
                    append("\"").append(jsonEscape(attachment.displayName)).append("\"")
                }
                append("]\n")
                append("}\n")
            }
            HistoryExportFormat.YAML -> buildString {
                append("requestID: '").append(yamlSingleQuoted(detail.requestID)).append("'\n")
                append("createdAtEpochMillis: ").append(detail.createdAtEpochMillis).append('\n')
                append("state: '").append(detail.state.name.lowercase()).append("'\n")
                append("presetID: '").append(yamlSingleQuoted(detail.presetID)).append("'\n")
                append("logicalPath: ").append(detail.logicalPath?.let { "'${yamlSingleQuoted(it)}'" } ?: "null").append('\n')
                append("text: |-\n")
                if (detail.capturedText.isNotEmpty()) detail.capturedText.lines().forEach { append("  ").append(it).append('\n') }
                append("originalText:")
                detail.originalCapturedText?.let { original ->
                    append(" |-\n")
                    original.lines().forEach { append("  ").append(it).append('\n') }
                } ?: append(" null\n")
                append("processingMode: ").append(detail.processingMode?.let { "'${it.name.lowercase()}'" } ?: "null").append('\n')
                append("processingOutcome: ").append(detail.processingOutcome?.let { "'${it.name.lowercase()}'" } ?: "null").append('\n')
                append("url: ").append(detail.capturedURL?.let { "'${yamlSingleQuoted(it)}'" } ?: "null").append('\n')
                append("attachments:\n")
                detail.attachments.forEach { append("  - '").append(yamlSingleQuoted(it.displayName)).append("'\n") }
            }
        }
    }

    private fun jsonEscape(value: String): String = buildString(value.length) {
        value.forEach { character ->
            when (character) {
                '\\' -> append("\\\\")
                '"' -> append("\\\"")
                '\b' -> append("\\b")
                '\u000c' -> append("\\f")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                else -> if (character.code < 0x20) append("\\u%04x".format(character.code)) else append(character)
            }
        }
    }

    private fun yamlSingleQuoted(value: String): String = value.replace("'", "''")
}

@Composable
internal fun HistoryDetailScreen(
    detail: CaptureHistoryDetail?,
    isLoading: Boolean,
    isDeleting: Boolean,
    navigateBack: () -> Unit,
    delete: (String) -> Unit,
    initialOperationMessage: VoxUiText? = null,
    initialShowsDeleteConfirmation: Boolean = false,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val signal = Signal.colors
    var exportMenuOpen by remember { mutableStateOf(false) }
    var pendingFormat by remember { mutableStateOf<HistoryExportFormat?>(null) }
    var operationMessage by remember { mutableStateOf(initialOperationMessage) }
    var showsDeleteConfirmation by remember { mutableStateOf(initialShowsDeleteConfirmation) }
    val createDocument = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("*/*")) { uri ->
        val format = pendingFormat
        pendingFormat = null
        if (uri != null && format != null && detail != null) {
            scope.launch {
                val saved = withContext(Dispatchers.IO) {
                    runCatching {
                        context.contentResolver.openOutputStream(uri, "w")?.use { output ->
                            output.write(HistoryDetailExporter.render(detail, format).toByteArray(Charsets.UTF_8))
                            output.flush()
                        } != null
                    }.getOrDefault(false)
                }
                operationMessage = if (saved) {
                    voxUiText("%@ exported.", format.uiText())
                } else {
                    voxUiText("The export could not be written.")
                }
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(signal.bg)
            .navigationBarsPadding(),
    ) {
        VoxTopBar(title = voxUiText("Capture Detail"), navigateBack = navigateBack)
        when {
            isLoading -> Box(
                modifier = Modifier.fillMaxWidth().weight(1f).padding(top = 48.dp),
                contentAlignment = Alignment.TopCenter,
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(28.dp),
                    strokeWidth = 3.dp,
                    color = signal.tint,
                    trackColor = signal.well,
                )
            }
            detail == null -> Column(
                modifier = Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(top = 24.dp),
            ) {
                SignalEmptyState(
                    icon = Icons.Outlined.ErrorOutline,
                    title = voxString("Capture unavailable"),
                    message = voxString("Its verified local package could not be opened."),
                    iconTint = signal.muted,
                )
            }
            else -> Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = SignalMetrics.PageGutter)
                    .padding(top = 2.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                DetailMetadataCard(detail)
                operationMessage?.let { message ->
                    SignalBanner(
                        message = message.localized(),
                        status = SignalStatus.ACTIVE,
                        liveRegion = true,
                    )
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    SignalButton(
                        text = voxString("Share"),
                        onClick = {
                            val content = HistoryDetailExporter.render(detail, HistoryExportFormat.MARKDOWN)
                            val share = Intent(Intent.ACTION_SEND).apply {
                                type = "text/markdown"
                                putExtra(Intent.EXTRA_TEXT, content)
                            }
                            context.startActivity(Intent.createChooser(share, "Share Capture"))
                        },
                        modifier = Modifier.weight(1f),
                        variant = SignalButtonVariant.SECONDARY,
                        size = SignalButtonSize.MEDIUM,
                        icon = Icons.Outlined.Share,
                        fillWidth = true,
                    )
                    Box(Modifier.weight(1f)) {
                        SignalButton(
                            text = voxString("Export"),
                            onClick = { exportMenuOpen = true },
                            variant = SignalButtonVariant.SECONDARY,
                            size = SignalButtonSize.MEDIUM,
                            icon = Icons.Outlined.FileDownload,
                            fillWidth = true,
                        )
                        LibraryExportMenu(
                            expanded = exportMenuOpen,
                            onDismiss = { exportMenuOpen = false },
                            labels = HistoryExportFormat.entries.map { it.uiText().localized() },
                            onSelect = { index ->
                                val format = HistoryExportFormat.entries[index]
                                exportMenuOpen = false
                                pendingFormat = format
                                createDocument.launch("vox-capture-${detail.requestID.take(8)}.${format.extension}")
                            },
                        )
                    }
                }
                if (detail.capturedText.isNotBlank()) ContentCard("Processed Text", detail.capturedText)
                detail.originalCapturedText?.let { original -> ContentCard("Original Text", original) }
                detail.processingNotice?.let { notice -> ContentCard("Processing Note", notice) }
                detail.capturedURL?.let { ContentCard("Captured Link", it) }
                if (detail.attachments.isNotEmpty()) {
                    ContentCard(
                        "Attachments",
                        detail.attachments.joinToString("\n") { "${it.displayName} · ${it.mediaType} · ${it.byteCount} bytes" },
                    )
                }
                detail.preparedMarkdown?.let { ContentCard("Rendered Markdown", it) }
                if (detail.preparedMarkdown == null) {
                    Text(
                        voxString("Rendered Markdown is unavailable until local preparation succeeds."),
                        style = SignalType.caption,
                        color = signal.muted,
                        modifier = Modifier.padding(horizontal = 4.dp),
                    )
                }
                if (detail.state == CaptureState.COMPLETED) {
                    Spacer(Modifier.height(4.dp))
                    LibraryDestructiveButton(
                        text = voxString("Remove from History"),
                        onClick = { showsDeleteConfirmation = true },
                        enabled = !isDeleting,
                        loading = isDeleting,
                    )
                }
            }
        }
    }
    if (showsDeleteConfirmation && detail != null) {
        LibraryConfirmDialog(
            title = voxString("Remove this capture from History?"),
            message = voxString("The completed local History package will be removed. Its exported Markdown note is not deleted, and lifetime Stats remain intact."),
            confirmLabel = voxString("Remove"),
            onConfirm = {
                showsDeleteConfirmation = false
                delete(detail.requestID)
            },
            onDismiss = { showsDeleteConfirmation = false },
        )
    }
}

/** Export format menu on a white card, shared by capture and transcript detail. */
@Composable
internal fun LibraryExportMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    labels: List<String>,
    onSelect: (Int) -> Unit,
) {
    val signal = Signal.colors
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismiss,
        containerColor = signal.card,
        shape = RoundedCornerShape(SignalMetrics.FieldRadius),
        border = BorderStroke(1.dp, signal.border),
        tonalElevation = 0.dp,
        shadowElevation = 6.dp,
    ) {
        labels.forEachIndexed { index, label ->
            DropdownMenuItem(
                text = { Text(label, style = MaterialTheme.typography.bodyLarge, color = signal.text) },
                onClick = { onSelect(index) },
            )
        }
    }
}

/** White bordered capsule with red text, for removing an item from the Library. */
@Composable
internal fun LibraryDestructiveButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
) {
    val signal = Signal.colors
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.fillMaxWidth().heightIn(min = SignalMetrics.ControlMedium),
        shape = CircleShape,
        border = BorderStroke(1.dp, signal.border),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = signal.card,
            contentColor = signal.error,
            disabledContainerColor = signal.disabledFill,
            disabledContentColor = signal.faint,
        ),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 0.dp),
    ) {
        if (loading) {
            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = signal.faint)
        } else {
            Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(8.dp))
        Text(text, style = MaterialTheme.typography.labelMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun DetailMetadataCard(detail: CaptureHistoryDetail) {
    val signal = Signal.colors
    val status = libraryCaptureStatus(detail.state)
    val statusColors = signalStatusColors(status)
    SignalCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SignalIconTile(
                icon = libraryCaptureIcon(detail.state),
                size = 40.dp,
                fill = statusColors.fill,
                tint = statusColors.ink,
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                SignalStatusBadge(captureStateUiText(detail.state).localized(), status)
                Text(
                    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(detail.createdAtEpochMillis)),
                    style = SignalType.monoCaption,
                    color = signal.muted,
                )
            }
        }
        detail.logicalPath?.let { path ->
            Spacer(Modifier.height(12.dp))
            Text(path, style = SignalType.mono, color = signal.text)
        }
        Spacer(Modifier.height(12.dp))
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(6.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            SignalChip(
                voxFormat("%@: %@", voxString("Capture Sources"), captureSourceUiText(detail.captureSource).localized()),
                color = signal.well,
                contentColor = signal.text,
            )
            detail.processingMode?.let { mode ->
                SignalChip(
                    voxFormat(
                        "%@ · %@",
                        voxFormat("%@: %@", voxString("Processing"), processingModeUiText(mode).localized()),
                        processingOutcomeUiText(detail.processingOutcome).localized(),
                    ),
                    color = signal.well,
                    contentColor = signal.text,
                )
            }
        }
        Spacer(Modifier.height(12.dp))
        SignalDivider()
        Spacer(Modifier.height(12.dp))
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                voxFormat("%@: %@", voxString("Capture"), detail.requestID),
                style = SignalType.monoCaption,
                color = signal.muted,
            )
            Text(
                voxFormat("%@: %@", voxString("Preset"), detail.presetID),
                style = SignalType.monoCaption,
                color = signal.muted,
            )
        }
    }
}


internal fun captureStateUiText(state: CaptureState): VoxUiText = when (state) {
    CaptureState.QUEUED -> voxUiText("Queued")
    CaptureState.PREPARING -> voxUiText("Preparing")
    CaptureState.MATERIALIZED -> voxUiText("Materialized")
    CaptureState.COMMITTING -> voxUiText("Committing")
    CaptureState.RETRYABLE_FAILURE -> voxUiText("Retryable failure")
    CaptureState.NEEDS_PERMISSION -> voxUiText("Needs permission")
    CaptureState.NEEDS_USER_ACTION -> voxUiText("Needs user action")
    CaptureState.UNKNOWN_OUTCOME -> voxUiText("Unknown outcome")
    CaptureState.COMPLETED -> voxUiText("Completed")
    CaptureState.PERMANENT_FAILURE -> voxUiText("Permanent failure")
    CaptureState.DISCARDED -> voxUiText("Discarded")
}

internal fun processingModeUiText(mode: CaptureProcessingMode): VoxUiText = when (mode) {
    CaptureProcessingMode.NONE -> voxUiText("None")
    CaptureProcessingMode.CLEAN -> voxUiText("Clean")
    CaptureProcessingMode.TODO_LIST -> voxUiText("To-do List")
    CaptureProcessingMode.MEETING_NOTES -> voxUiText("Meeting Notes")
    CaptureProcessingMode.CUSTOM -> voxUiText("Custom")
}

internal fun processingOutcomeUiText(outcome: CaptureTextProcessingOutcome?): VoxUiText = when (outcome) {
    CaptureTextProcessingOutcome.APPLIED -> voxUiText("Applied")
    CaptureTextProcessingOutcome.UNCHANGED -> voxUiText("Unchanged")
    CaptureTextProcessingOutcome.UNSUPPORTED_CUSTOM_INSTRUCTION -> voxUiText("Unsupported custom instruction")
    CaptureTextProcessingOutcome.SKIPPED_TOO_LARGE -> voxUiText("Skipped because the capture is too large")
    CaptureTextProcessingOutcome.MODEL_UNAVAILABLE -> voxUiText("Local model unavailable; the original text was kept.")
    CaptureTextProcessingOutcome.MODEL_FAILURE -> voxUiText("Local processing failed; the original text was kept.")
    null -> voxUiText("Unknown")
}

internal fun captureSourceUiText(source: String): VoxUiText = when (source) {
    "share" -> voxUiText("Share")
    "keyboard" -> voxUiText("Keyboard")
    "widget" -> voxUiText("Widget")
    "shortcut" -> voxUiText("Shortcut")
    "watch", "wear" -> voxUiText("Watch")
    else -> voxUiText("App")
}

@Composable
private fun ContentCard(title: String, content: String) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        SignalSectionLabel(title, Modifier.padding(start = 4.dp, top = 4.dp))
        SignalCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(16.dp), radius = SignalMetrics.GroupRadius) {
            Text(
                content,
                modifier = Modifier.fillMaxWidth(),
                style = SignalType.mono,
                color = Signal.colors.text,
            )
        }
    }
}
