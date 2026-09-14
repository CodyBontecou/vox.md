package md.vox.android

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
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
import java.text.DateFormat
import java.text.Normalizer
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.util.Date
import java.util.Locale
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import md.vox.android.ui.GeistMonoFontFamily
import kotlinx.coroutines.withContext
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureExportYAMLProperty
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState

internal enum class TranscriptExportFormat(val label: String, val extension: String, val mimeType: String) {
    MARKDOWN("Markdown", "md", "text/markdown"),
    TEXT("Plain Text", "txt", "text/plain"),
    JSON("JSON", "json", "application/json"),
    YAML("YAML", "yaml", "application/yaml"),
}

internal object TranscriptSearch {
    fun matches(state: RecordingTranscriptionState, query: String): Boolean {
        val tokens = normalize(query).split(Regex("\\s+")).filter(String::isNotBlank)
        if (tokens.isEmpty()) return true
        val haystack = normalize(
            listOfNotNull(
                state.transcript,
                state.cleanedTranscript,
                state.title,
                state.category,
                state.tags.joinToString(" "),
                state.modelName,
                state.modelID,
                state.languageTag,
            ).joinToString(" "),
        )
        return tokens.all(haystack::contains)
    }

    private fun normalize(value: String): String = Normalizer.normalize(value, Normalizer.Form.NFKD)
        .filterNot { Character.getType(it) == Character.NON_SPACING_MARK.toInt() }
        .lowercase(Locale.ROOT)
}

internal object TranscriptExporter {
    private val markdownDateFormatter = DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss", Locale.US)
        .withZone(ZoneId.systemDefault())

    fun render(
        state: RecordingTranscriptionState,
        format: TranscriptExportFormat,
        yamlProperties: Set<CaptureExportYAMLProperty> = CaptureExportYAMLProperty.entries.toSet(),
        yamlUsesMarkdownFrontmatter: Boolean = false,
        markdownObsidianEnabled: Boolean = false,
    ): String {
        val text = state.preferredTranscript.orEmpty()
        val timestamp = exportTimestamp(state)
        return when (format) {
            TranscriptExportFormat.TEXT -> buildString {
                append(text)
                if (state.tags.isNotEmpty()) {
                    append("\n\nTags: ").append(state.tags.joinToString(", "))
                }
            }
            TranscriptExportFormat.MARKDOWN -> if (markdownObsidianEnabled) {
                renderYAML(state, text, timestamp, CaptureExportYAMLProperty.entries.toSet(), wrapsInFrontmatter = true)
            } else buildString {
                append("## Transcript - ").append(markdownDateFormatter.format(Instant.ofEpochMilli(timestamp)))
                append("\n\n").append(text)
                if (state.tags.isNotEmpty()) {
                    append("\n\n")
                    append(state.tags.joinToString(" ") { "#${sanitizeHashtag(it)}" })
                }
            }
            TranscriptExportFormat.JSON -> renderJSON(state, text, timestamp)
            TranscriptExportFormat.YAML -> renderYAML(state, text, timestamp, yamlProperties, yamlUsesMarkdownFrontmatter)
        }
    }

    private fun renderJSON(state: RecordingTranscriptionState, text: String, timestamp: Long): String {
        val fields = buildList {
            state.category?.takeIf(String::isNotEmpty)?.let { add("category" to nullableJson(it)) }
            add("date" to jsonNumber((timestamp - SWIFT_REFERENCE_DATE_EPOCH_MILLIS) / 1_000.0))
            add("duration" to jsonNumber(state.durationMillis.coerceAtLeast(0) / 1_000.0))
            add("id" to nullableJson(state.sessionID.uppercase(Locale.ROOT)))
            add("language" to nullableJson(state.languageTag.orEmpty()))
            add("modelUsed" to nullableJson(state.modelName ?: state.modelID.orEmpty()))
            if (state.tags.isNotEmpty()) {
                add("tags" to state.tags.joinToString(prefix = "[", postfix = "]") { nullableJson(it) })
            }
            add("text" to nullableJson(text))
            state.title?.takeIf(String::isNotEmpty)?.let { add("title" to nullableJson(it)) }
        }.sortedBy(Pair<String, String>::first)
        return fields.joinToString(prefix = "{\n", postfix = "\n}", separator = ",\n") { (key, value) ->
            "  \"$key\" : $value"
        }
    }

    private fun renderYAML(
        state: RecordingTranscriptionState,
        text: String,
        timestamp: Long,
        properties: Set<CaptureExportYAMLProperty>,
        wrapsInFrontmatter: Boolean,
    ): String = buildString {
        if (wrapsInFrontmatter) append("---\n")
        if (CaptureExportYAMLProperty.ID in properties) append("id: \"").append(yamlQuote(state.sessionID)).append("\"\n")
        if (CaptureExportYAMLProperty.TEXT in properties) {
            if (text.isEmpty()) {
                append("text: \"\"\n")
            } else {
                append("text: |-\n")
                text.lines().forEach { append("  ").append(it).append('\n') }
            }
        }
        if (CaptureExportYAMLProperty.DATE in properties) {
            append("date: \"").append(isoTranscriptDate(timestamp)).append("\"\n")
        }
        if (CaptureExportYAMLProperty.DURATION in properties) {
            append("duration_seconds: ").append(String.format(Locale.US, "%.3f", state.durationMillis.coerceAtLeast(0) / 1_000.0)).append('\n')
        }
        if (CaptureExportYAMLProperty.MODEL_USED in properties) {
            append("model_used: \"").append(yamlQuote(state.modelName ?: state.modelID.orEmpty())).append("\"\n")
        }
        if (CaptureExportYAMLProperty.LANGUAGE in properties) {
            append("language: \"").append(yamlQuote(state.languageTag.orEmpty())).append("\"\n")
        }
        if (state.tags.isNotEmpty()) {
            append("tags: ")
            append(state.tags.joinToString(prefix = "[", postfix = "]") { "\"${yamlQuote(it)}\"" })
            append('\n')
        }
        state.category?.takeIf(String::isNotEmpty)?.let {
            append("category: \"").append(yamlQuote(it)).append("\"\n")
        }
        state.title?.takeIf(String::isNotEmpty)?.let {
            append("title: \"").append(yamlQuote(it)).append("\"\n")
        }
        if (wrapsInFrontmatter) append("---")
        else if (isNotEmpty()) setLength(length - 1)
    }

    private fun exportTimestamp(state: RecordingTranscriptionState): Long =
        state.recordedAtEpochMillis ?: state.completedAtEpochMillis ?: 0L

    private fun sanitizeHashtag(value: String): String = value.lowercase(Locale.ROOT)
        .map { if (it.isLetterOrDigit()) it else '-' }
        .joinToString("")
        .replace(Regex("-+"), "-")
        .trim('-')

    private fun jsonNumber(value: Double): String =
        if (value.isFinite() && value % 1.0 == 0.0) value.toLong().toString() else value.toString()

    private fun nullableJson(value: String?): String = value?.let { "\"${jsonEscape(it)}\"" } ?: "null"
    private fun yamlQuote(value: String): String = value
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")
        .replace("\n", "\\n")
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

    private const val SWIFT_REFERENCE_DATE_EPOCH_MILLIS = 978_307_200_000L
}

internal fun isoTranscriptDate(epochMillis: Long): String = DateTimeFormatterBuilder()
    .appendInstant(3)
    .toFormatter()
    .format(Instant.ofEpochMilli(epochMillis.coerceAtLeast(0)))

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun TranscriptDetailScreen(
    state: RecordingTranscriptionState?,
    preset: CapturePreset? = null,
    prepareConfiguredExportAudio: suspend (String, CapturePreset) -> ConfiguredTranscriptAudioSource? = { _, _ -> null },
    shareTranscript: ((String) -> Unit)? = null,
    exportTranscript: ((RecordingTranscriptionState, TranscriptExportFormat) -> Unit)? = null,
    navigateBack: () -> Unit,
    save: (String, String, String, String, List<String>, String) -> Boolean,
    delete: (String) -> Unit,
    addToDraft: (String, String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val configuredExporter = remember(context) { AndroidConfiguredTranscriptExporter(context) }
    var editing by remember(state?.sessionID) { mutableStateOf(false) }
    var editedRawText by remember(state?.sessionID, state?.transcript) { mutableStateOf(state?.transcript.orEmpty()) }
    var editedCleanedText by remember(state?.sessionID, state?.cleanedTranscript) {
        mutableStateOf(state?.cleanedTranscript.orEmpty())
    }
    var editedTitle by remember(state?.sessionID, state?.title) { mutableStateOf(state?.title.orEmpty()) }
    var editedTags by remember(state?.sessionID, state?.tags) { mutableStateOf(state?.tags.orEmpty().joinToString(", ")) }
    var editedCategory by remember(state?.sessionID, state?.category) { mutableStateOf(state?.category.orEmpty()) }
    var exportMenuOpen by remember { mutableStateOf(false) }
    var pendingFormat by remember { mutableStateOf<TranscriptExportFormat?>(null) }
    var operationMessage by remember { mutableStateOf<VoxUiText?>(null) }
    var showsDeleteConfirmation by remember { mutableStateOf(false) }
    val createDocument = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("*/*")) { uri ->
        val format = pendingFormat
        pendingFormat = null
        if (uri != null && format != null && state != null) {
            scope.launch {
                val written = withContext(Dispatchers.IO) {
                    runCatching {
                        context.contentResolver.openOutputStream(uri, "w")?.use { output ->
                            output.write(TranscriptExporter.render(state, format).toByteArray(Charsets.UTF_8))
                            output.flush()
                        } != null
                    }.getOrDefault(false)
                }
                operationMessage = if (written) {
                    voxUiText("%@ exported.", format.label)
                } else {
                    voxUiText("The transcript could not be exported.")
                }
            }
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(voxString("Transcript"), style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    IconButton(onClick = navigateBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = voxString("Back"))
                    }
                },
                actions = {
                    if (state?.phase == RecordingTranscriptionPhase.COMPLETED) {
                        IconButton(onClick = { editing = !editing }) {
                            Icon(Icons.Outlined.Edit, contentDescription = voxString(if (editing) "Stop editing" else "Edit transcript"))
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        if (state == null) {
            Column(Modifier.fillMaxSize().padding(padding).padding(24.dp)) {
                Text(voxString("Transcript unavailable"), style = MaterialTheme.typography.titleMedium)
                Spacer(Modifier.height(8.dp))
                Text(voxString("It may have been deleted while its original recording was retained."))
            }
        } else {
            Column(
                modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                operationMessage?.let { Text(it.localized(), color = MaterialTheme.colorScheme.primary) }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(
                        onClick = {
                            val text = state.preferredTranscript.orEmpty()
                            if (shareTranscript != null) {
                                shareTranscript(text)
                            } else {
                                context.startActivity(
                                    Intent.createChooser(
                                        Intent(Intent.ACTION_SEND).apply {
                                            type = "text/plain"
                                            putExtra(Intent.EXTRA_TEXT, text)
                                        },
                                        "Share Transcript",
                                    ),
                                )
                            }
                        },
                        enabled = !state.preferredTranscript.isNullOrBlank(),
                    ) {
                        Icon(Icons.Outlined.Share, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Share"))
                    }
                    androidx.compose.foundation.layout.Box {
                        Button(onClick = { exportMenuOpen = true }, enabled = !state.preferredTranscript.isNullOrBlank()) {
                            Icon(Icons.Outlined.FileDownload, contentDescription = null, modifier = Modifier.size(18.dp))
                            Spacer(Modifier.width(6.dp))
                            Text(voxString("Export"))
                        }
                        DropdownMenu(expanded = exportMenuOpen, onDismissRequest = { exportMenuOpen = false }) {
                            TranscriptExportFormat.entries.forEach { format ->
                                DropdownMenuItem(
                                    text = { Text(format.label) },
                                    onClick = {
                                        exportMenuOpen = false
                                        if (exportTranscript != null) {
                                            exportTranscript(state, format)
                                        } else {
                                            pendingFormat = format
                                            createDocument.launch("vox-transcript-${state.sessionID.take(8)}.${format.extension}")
                                        }
                                    },
                                )
                            }
                        }
                    }
                }
                if (preset?.exportSettings?.let { it.usesCustomExportSettings && it.exportEnabled } == true) {
                    Button(
                        onClick = {
                            scope.launch {
                                val audioSource = if (preset.audioSaveMode == CaptureAudioSaveMode.OFF) {
                                    null
                                } else {
                                    prepareConfiguredExportAudio(state.sessionID, preset)
                                }
                                val result = if (
                                    preset.audioSaveMode != CaptureAudioSaveMode.OFF && audioSource == null
                                ) {
                                    ConfiguredTranscriptExportResult.Failed(
                                        ConfiguredTranscriptExportFailure.RETAINED_AUDIO_UNAVAILABLE,
                                    )
                                } else {
                                    withContext(Dispatchers.IO) {
                                        configuredExporter.export(state, preset.exportSettings, audioSource)
                                    }
                                }
                                operationMessage = when (result) {
                                    ConfiguredTranscriptExportResult.Disabled -> voxUiText("Preset export is disabled.")
                                    is ConfiguredTranscriptExportResult.Exported -> voxUiText(
                                        "Exported %@.",
                                        result.displayName,
                                    )
                                    is ConfiguredTranscriptExportResult.Failed -> result.reason.uiText()
                                }
                            }
                        },
                        enabled = !state.preferredTranscript.isNullOrBlank(),
                    ) {
                        Icon(Icons.Outlined.FileDownload, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Export with Preset"))
                    }
                }
                Card(
                    colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                    shape = RoundedCornerShape(16.dp),
                ) {
                    Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(formatTranscriptDuration(state.durationMillis), style = MaterialTheme.typography.titleMedium)
                        state.completedAtEpochMillis?.let {
                            Text(DateFormat.getDateTimeInstance().format(Date(it)), color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Text(state.modelName ?: state.modelID ?: "Local model", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        state.languageTag?.let { Text(it, style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily)) }
                        state.title?.let { Text(it, style = MaterialTheme.typography.bodyLarge) }
                        state.category?.let {
                            Text(
                                voxFormat("%@: %@", voxString("Category"), it),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (state.tags.isNotEmpty()) Text(
                            state.tags.joinToString(" · ") { "#$it" },
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (state.speakerCount > 0) {
                            Text(
                                voxFormat("%lld speaker%@", state.speakerCount, if (state.speakerCount == 1) "" else "s"),
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        state.diarizationSkipReason?.let { Text(it, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    }
                }
                if (editing) {
                    OutlinedTextField(
                        value = editedTitle,
                        onValueChange = { editedTitle = it.take(128) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        label = { Text(voxString("Title")) },
                    )
                    OutlinedTextField(
                        value = editedTags,
                        onValueChange = { editedTags = it.take(1_280) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        label = { Text(voxString("Tags, comma separated")) },
                    )
                    OutlinedTextField(
                        value = editedCategory,
                        onValueChange = { editedCategory = it.take(64) },
                        modifier = Modifier.fillMaxWidth(),
                        singleLine = true,
                        label = { Text(voxString("Category")) },
                    )
                    OutlinedTextField(
                        value = editedCleanedText,
                        onValueChange = { editedCleanedText = it.take(500_000) },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 5,
                        label = { Text(voxString("Cleaned text")) },
                    )
                    OutlinedTextField(
                        value = editedRawText,
                        onValueChange = { editedRawText = it.take(500_000) },
                        modifier = Modifier.fillMaxWidth(),
                        minLines = 7,
                        label = { Text(voxString("Raw transcript")) },
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = {
                                val saved = save(
                                    state.sessionID,
                                    editedRawText,
                                    editedCleanedText,
                                    editedTitle,
                                    editedTags.split(',').map(String::trim).filter(String::isNotBlank),
                                    editedCategory,
                                )
                                operationMessage = voxUiText(
                                    if (saved) "Transcript saved." else "The transcript could not be saved.",
                                )
                                if (saved) editing = false
                            },
                            enabled = editedRawText.isNotBlank(),
                        ) { Text(voxString("Save")) }
                        TextButton(onClick = {
                            editedRawText = state.transcript.orEmpty()
                            editedCleanedText = state.cleanedTranscript.orEmpty()
                            editedTitle = state.title.orEmpty()
                            editedTags = state.tags.joinToString(", ")
                            editedCategory = state.category.orEmpty()
                            editing = false
                        }) { Text(voxString("Cancel")) }
                    }
                } else {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                        shape = RoundedCornerShape(16.dp),
                    ) {
                        Text(
                            state.preferredTranscript.orEmpty(),
                            modifier = Modifier.fillMaxWidth().padding(16.dp),
                            style = MaterialTheme.typography.bodyLarge,
                        )
                    }
                }
                Button(
                    onClick = { addToDraft(state.sessionID, state.preferredTranscript.orEmpty()) },
                    enabled = !state.preferredTranscript.isNullOrBlank(),
                ) { Text(voxString("Add to Capture")) }
                TextButton(onClick = { showsDeleteConfirmation = true }) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.width(6.dp))
                    Text(voxString("Delete Transcript"), color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
    if (showsDeleteConfirmation && state != null) {
        AlertDialog(
            onDismissRequest = { showsDeleteConfirmation = false },
            title = { Text(voxString("Delete this transcript?")) },
            text = { Text(voxString("The transcript will be removed. Its original local recording is kept in the Recording Queue.")) },
            confirmButton = {
                TextButton(onClick = { showsDeleteConfirmation = false; delete(state.sessionID) }) {
                    Text(voxString("Delete"), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { showsDeleteConfirmation = false }) { Text(voxString("Cancel")) } },
        )
    }
}

internal fun formatTranscriptDuration(milliseconds: Long): String {
    val totalSeconds = milliseconds.coerceAtLeast(0) / 1_000
    val hours = totalSeconds / 3_600
    val minutes = (totalSeconds % 3_600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) "%d:%02d:%02d".format(Locale.ROOT, hours, minutes, seconds)
    else "%d:%02d".format(Locale.ROOT, minutes, seconds)
}
