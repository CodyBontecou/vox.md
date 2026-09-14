package md.vox.android

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HistoryDetailScreen(
    detail: CaptureHistoryDetail?,
    isLoading: Boolean,
    isDeleting: Boolean,
    navigateBack: () -> Unit,
    delete: (String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var exportMenuOpen by remember { mutableStateOf(false) }
    var pendingFormat by remember { mutableStateOf<HistoryExportFormat?>(null) }
    var operationMessage by remember { mutableStateOf<VoxUiText?>(null) }
    var showsDeleteConfirmation by remember { mutableStateOf(false) }
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

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(voxString("Capture Detail"), style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    IconButton(onClick = navigateBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = voxString("Back"))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        when {
            isLoading -> Box(Modifier.fillMaxSize().padding(padding)) {
                CircularProgressIndicator(modifier = Modifier.padding(32.dp).size(28.dp), strokeWidth = 3.dp)
            }
            detail == null -> Column(Modifier.fillMaxSize().padding(padding).padding(24.dp)) {
                Text(voxString("Capture unavailable"), style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                Text(voxString("Its verified local package could not be opened."), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            else -> Column(
                modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                operationMessage?.let { Text(it.localized(), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = {
                            val content = HistoryDetailExporter.render(detail, HistoryExportFormat.MARKDOWN)
                            val share = Intent(Intent.ACTION_SEND).apply {
                                type = "text/markdown"
                                putExtra(Intent.EXTRA_TEXT, content)
                            }
                            context.startActivity(Intent.createChooser(share, "Share Capture"))
                        },
                    ) {
                        Icon(Icons.Outlined.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Share"))
                    }
                    Box {
                        Button(onClick = { exportMenuOpen = true }) {
                            Icon(Icons.Outlined.FileDownload, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(voxString("Export"))
                        }
                        DropdownMenu(expanded = exportMenuOpen, onDismissRequest = { exportMenuOpen = false }) {
                            HistoryExportFormat.entries.forEach { format ->
                                DropdownMenuItem(
                                    text = { Text(format.uiText().localized()) },
                                    onClick = {
                                        exportMenuOpen = false
                                        pendingFormat = format
                                        createDocument.launch("vox-capture-${detail.requestID.take(8)}.${format.extension}")
                                    },
                                )
                            }
                        }
                    }
                }
                if (detail.state == CaptureState.COMPLETED) {
                    TextButton(onClick = { showsDeleteConfirmation = true }, enabled = !isDeleting) {
                        if (isDeleting) CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        else Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Remove from History"), color = MaterialTheme.colorScheme.error)
                    }
                }
                DetailMetadataCard(detail)
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
                    Text(voxString("Rendered Markdown is unavailable until local preparation succeeds."),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }
    if (showsDeleteConfirmation && detail != null) {
        AlertDialog(
            onDismissRequest = { showsDeleteConfirmation = false },
            title = { Text(voxString("Remove this capture from History?")) },
            text = { Text(voxString("The completed local History package will be removed. Its exported Markdown note is not deleted, and lifetime Stats remain intact.")) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showsDeleteConfirmation = false
                        delete(detail.requestID)
                    },
                ) { Text(voxString("Remove"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { showsDeleteConfirmation = false }) { Text(voxString("Cancel")) } },
        )
    }
}

@Composable
private fun DetailMetadataCard(detail: CaptureHistoryDetail) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(
                captureStateUiText(detail.state).localized(),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(detail.createdAtEpochMillis)),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            detail.logicalPath?.let { Text(it, style = MaterialTheme.typography.bodyMedium.copy(fontFamily = GeistMonoFontFamily)) }
            Text(
                voxFormat("%@: %@", voxString("Capture Sources"), captureSourceUiText(detail.captureSource).localized()),
                style = MaterialTheme.typography.bodyMedium,
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(vertical = 4.dp))
            Text(voxFormat("%@: %@", voxString("Capture"), detail.requestID), style = MaterialTheme.typography.labelSmall.copy(fontFamily = GeistMonoFontFamily))
            Text(voxFormat("%@: %@", voxString("Preset"), detail.presetID), style = MaterialTheme.typography.labelSmall.copy(fontFamily = GeistMonoFontFamily))
            detail.processingMode?.let { mode ->
                Text(
                    voxFormat(
                        "%@ · %@",
                        voxFormat("%@: %@", voxString("Processing"), processingModeUiText(mode).localized()),
                        processingOutcomeUiText(detail.processingOutcome).localized(),
                    ),
                    style = MaterialTheme.typography.labelSmall,
                )
            }
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
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
            shape = RoundedCornerShape(16.dp),
        ) {
            Text(
                content,
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                style = MaterialTheme.typography.bodyMedium.copy(fontFamily = GeistMonoFontFamily),
            )
        }
    }
}
