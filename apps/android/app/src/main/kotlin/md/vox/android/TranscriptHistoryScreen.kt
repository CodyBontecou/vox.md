package md.vox.android

import android.content.Intent
import android.media.MediaPlayer
import android.net.Uri
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.produceState
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import kotlinx.coroutines.delay
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.ui.Alignment
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalBanner
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalChip
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalFieldShape
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalSectionLabel
import md.vox.android.ui.SignalStatus
import md.vox.android.ui.SignalStatusBadge
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalTextFieldColors
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

@OptIn(ExperimentalLayoutApi::class)
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
    initialEditing: Boolean = false,
    initialOperationMessage: VoxUiText? = null,
    initialShowsDeleteConfirmation: Boolean = false,
    /** True when the recording's local audio is still retained; may read storage. */
    hasRetainedAudio: suspend (String) -> Boolean = { false },
    /** Prepares the retained audio for playback and returns its content URI. */
    loadRetainedAudio: suspend (String) -> String? = { null },
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val signal = Signal.colors
    val showsAudio by produceState(false, state?.sessionID) {
        val id = state?.sessionID
        value = id != null && withContext(Dispatchers.IO) { runCatching { hasRetainedAudio(id) }.getOrDefault(false) }
    }
    val configuredExporter = remember(context) { AndroidConfiguredTranscriptExporter(context) }
    var editing by remember(state?.sessionID) { mutableStateOf(initialEditing) }
    var editedRawText by remember(state?.sessionID, state?.transcript) { mutableStateOf(state?.transcript.orEmpty()) }
    var editedCleanedText by remember(state?.sessionID, state?.cleanedTranscript) {
        mutableStateOf(state?.cleanedTranscript.orEmpty())
    }
    var editedTitle by remember(state?.sessionID, state?.title) { mutableStateOf(state?.title.orEmpty()) }
    var editedTags by remember(state?.sessionID, state?.tags) { mutableStateOf(state?.tags.orEmpty().joinToString(", ")) }
    var editedCategory by remember(state?.sessionID, state?.category) { mutableStateOf(state?.category.orEmpty()) }
    var exportMenuOpen by remember { mutableStateOf(false) }
    var pendingFormat by remember { mutableStateOf<TranscriptExportFormat?>(null) }
    var operationMessage by remember { mutableStateOf(initialOperationMessage) }
    var showsDeleteConfirmation by remember { mutableStateOf(initialShowsDeleteConfirmation) }
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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(signal.bg)
            .navigationBarsPadding()
            .imePadding(),
    ) {
        VoxTopBar(
            title = voxUiText("Transcript"),
            navigateBack = navigateBack,
            actions = {
                if (state?.phase == RecordingTranscriptionPhase.COMPLETED) {
                    SignalCircleButton(
                        icon = if (editing) Icons.Outlined.Check else Icons.Outlined.Edit,
                        contentDescription = voxString(if (editing) "Stop editing" else "Edit transcript"),
                        onClick = { editing = !editing },
                        filled = if (editing) signal.text else null,
                        contentColor = if (editing) signal.bg else null,
                    )
                }
            },
        )
        if (state == null) {
            Column(
                modifier = Modifier.fillMaxWidth().weight(1f).verticalScroll(rememberScrollState()).padding(top = 24.dp),
            ) {
                SignalEmptyState(
                    icon = Icons.Outlined.ErrorOutline,
                    title = voxString("Transcript unavailable"),
                    message = voxString("It may have been deleted while its original recording was retained."),
                    iconTint = signal.muted,
                )
            }
        } else {
            val hasText = !state.preferredTranscript.isNullOrBlank()
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = SignalMetrics.PageGutter)
                    .padding(top = 2.dp, bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                SignalCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        LibraryTranscriptTile(state.phase, size = 40.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(
                                formatTranscriptDuration(state.durationMillis),
                                style = MaterialTheme.typography.titleMedium.copy(fontFamily = GeistMonoFontFamily),
                                color = signal.text,
                            )
                            state.completedAtEpochMillis?.let {
                                Text(DateFormat.getDateTimeInstance().format(Date(it)), style = SignalType.monoCaption, color = signal.muted)
                            }
                        }
                        if (state.phase != RecordingTranscriptionPhase.COMPLETED) {
                            SignalStatusBadge(
                                text = libraryTranscriptPhaseTitle(state),
                                status = libraryTranscriptStatus(state.phase),
                                liveRegion = true,
                            )
                        }
                    }
                    LibraryTranscriptProgress(state, Modifier.padding(top = 12.dp))
                    state.title?.let {
                        Spacer(Modifier.height(12.dp))
                        Text(it, style = MaterialTheme.typography.titleLarge, color = signal.text)
                    }
                    Spacer(Modifier.height(10.dp))
                    FlowRow(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        SignalChip(state.modelName ?: state.modelID ?: "Local model", color = signal.well, contentColor = signal.text)
                        state.languageTag?.let { SignalChip(it, mono = true, color = signal.well, contentColor = signal.text) }
                        state.category?.let {
                            SignalChip(voxFormat("%@: %@", voxString("Category"), it), color = signal.well, contentColor = signal.text)
                        }
                        if (state.speakerCount > 0) {
                            SignalChip(voxFormat("%lld speakers", state.speakerCount), color = signal.well, contentColor = signal.text)
                        }
                        state.tags.forEach { tag -> SignalChip("#$tag", mono = true, color = signal.bg) }
                    }
                    state.diarizationSkipReason?.let {
                        Spacer(Modifier.height(10.dp))
                        Text(it, style = SignalType.caption, color = signal.muted)
                    }
                }
                if (showsAudio) TranscriptAudioCard(state, loadRetainedAudio)
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
                        modifier = Modifier.weight(1f),
                        variant = SignalButtonVariant.SECONDARY,
                        size = SignalButtonSize.MEDIUM,
                        enabled = hasText,
                        icon = Icons.Outlined.Share,
                        fillWidth = true,
                    )
                    Box(Modifier.weight(1f)) {
                        SignalButton(
                            text = voxString("Export"),
                            onClick = { exportMenuOpen = true },
                            variant = SignalButtonVariant.SECONDARY,
                            size = SignalButtonSize.MEDIUM,
                            enabled = hasText,
                            icon = Icons.Outlined.FileDownload,
                            fillWidth = true,
                        )
                        LibraryExportMenu(
                            expanded = exportMenuOpen,
                            onDismiss = { exportMenuOpen = false },
                            labels = TranscriptExportFormat.entries.map { it.label },
                            onSelect = { index ->
                                val format = TranscriptExportFormat.entries[index]
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
                if (preset?.exportSettings?.let { it.usesCustomExportSettings && it.exportEnabled } == true) {
                    SignalButton(
                        text = voxString("Export with Preset"),
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
                        variant = SignalButtonVariant.SECONDARY,
                        size = SignalButtonSize.MEDIUM,
                        enabled = hasText,
                        icon = Icons.Outlined.FileDownload,
                        fillWidth = true,
                    )
                }
                if (editing) {
                    SignalSectionLabel(voxString("Edit transcript"), Modifier.padding(start = 4.dp, top = 4.dp))
                    TranscriptEditField(editedTitle, { editedTitle = it.take(128) }, voxString("Title"))
                    TranscriptEditField(editedTags, { editedTags = it.take(1_280) }, voxString("Tags, comma separated"))
                    TranscriptEditField(editedCategory, { editedCategory = it.take(64) }, voxString("Category"))
                    TranscriptEditField(
                        editedCleanedText,
                        { editedCleanedText = it.take(500_000) },
                        voxString("Cleaned text"),
                        minLines = 5,
                    )
                    TranscriptEditField(
                        editedRawText,
                        { editedRawText = it.take(500_000) },
                        voxString("Raw transcript"),
                        minLines = 7,
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        SignalButton(
                            text = voxString("Cancel"),
                            onClick = {
                                editedRawText = state.transcript.orEmpty()
                                editedCleanedText = state.cleanedTranscript.orEmpty()
                                editedTitle = state.title.orEmpty()
                                editedTags = state.tags.joinToString(", ")
                                editedCategory = state.category.orEmpty()
                                editing = false
                            },
                            modifier = Modifier.weight(1f),
                            variant = SignalButtonVariant.SECONDARY,
                            size = SignalButtonSize.MEDIUM,
                            fillWidth = true,
                        )
                        SignalButton(
                            text = voxString("Save"),
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
                            modifier = Modifier.weight(1f),
                            variant = SignalButtonVariant.PRIMARY,
                            size = SignalButtonSize.MEDIUM,
                            enabled = editedRawText.isNotBlank(),
                            fillWidth = true,
                        )
                    }
                } else if (hasText) {
                    SignalCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(18.dp)) {
                        Text(
                            state.preferredTranscript.orEmpty(),
                            modifier = Modifier.fillMaxWidth(),
                            style = MaterialTheme.typography.bodyLarge,
                            color = signal.text,
                        )
                    }
                }
                Spacer(Modifier.height(4.dp))
                SignalButton(
                    text = voxString("Add to Capture"),
                    onClick = { addToDraft(state.sessionID, state.preferredTranscript.orEmpty()) },
                    variant = SignalButtonVariant.PRIMARY,
                    size = SignalButtonSize.LARGE,
                    enabled = hasText,
                    icon = Icons.Outlined.Add,
                )
                LibraryDestructiveButton(
                    text = voxString("Delete Transcript"),
                    onClick = { showsDeleteConfirmation = true },
                )
            }
        }
    }
    if (showsDeleteConfirmation && state != null) {
        LibraryConfirmDialog(
            title = voxString("Delete this transcript?"),
            message = voxString("The transcript will be removed. Its original local recording is kept in the Recording Queue."),
            confirmLabel = voxString("Delete"),
            onConfirm = {
                showsDeleteConfirmation = false
                delete(state.sessionID)
            },
            onDismiss = { showsDeleteConfirmation = false },
        )
    }
}

@Composable
private fun TranscriptEditField(
    value: String,
    onValueChange: (String) -> Unit,
    label: String,
    minLines: Int = 1,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = Modifier.fillMaxWidth(),
        singleLine = minLines == 1,
        minLines = minLines,
        label = { Text(label) },
        shape = SignalFieldShape,
        colors = signalTextFieldColors(),
        textStyle = MaterialTheme.typography.bodyLarge,
    )
}


internal fun formatTranscriptDuration(milliseconds: Long): String {
    val totalSeconds = milliseconds.coerceAtLeast(0) / 1_000
    val hours = totalSeconds / 3_600
    val minutes = (totalSeconds % 3_600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) "%d:%02d:%02d".format(Locale.ROOT, hours, minutes, seconds)
    else "%d:%02d".format(Locale.ROOT, minutes, seconds)
}

/**
 * Player for a recording's retained local audio: a play/pause button, a seekable
 * scrubber and the elapsed and total time. The WAV is prepared only on first play.
 */
@Composable
internal fun TranscriptAudioCard(
    state: RecordingTranscriptionState,
    loadRetainedAudio: suspend (String) -> String?,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val signal = Signal.colors
    var player by remember(state.sessionID) { mutableStateOf<MediaPlayer?>(null) }
    var isPlaying by remember(state.sessionID) { mutableStateOf(false) }
    var isPreparing by remember(state.sessionID) { mutableStateOf(false) }
    var unavailable by remember(state.sessionID) { mutableStateOf(false) }
    var positionMillis by remember(state.sessionID) { mutableLongStateOf(0L) }
    var durationMillis by remember(state.sessionID) { mutableLongStateOf(state.durationMillis.coerceAtLeast(0L)) }
    DisposableEffect(state.sessionID) {
        onDispose {
            player?.release()
            player = null
        }
    }
    LaunchedEffect(isPlaying, player) {
        val active = player ?: return@LaunchedEffect
        while (isPlaying) {
            positionMillis = runCatching { active.currentPosition.toLong() }.getOrDefault(positionMillis)
            delay(200)
        }
    }
    val togglePlayback: () -> Unit = {
        val current = player
        when {
            current != null && isPlaying -> {
                current.pause()
                isPlaying = false
            }
            current != null -> {
                current.start()
                isPlaying = true
            }
            !isPreparing -> {
                isPreparing = true
                scope.launch {
                    val prepared = withContext(Dispatchers.IO) {
                        val uri = runCatching { loadRetainedAudio(state.sessionID) }.getOrNull() ?: return@withContext null
                        runCatching {
                            MediaPlayer().apply {
                                setDataSource(context, Uri.parse(uri))
                                prepare()
                            }
                        }.getOrNull()
                    }
                    isPreparing = false
                    if (prepared == null) {
                        unavailable = true
                    } else {
                        prepared.setOnCompletionListener {
                            isPlaying = false
                            positionMillis = 0L
                            it.seekTo(0)
                        }
                        prepared.duration.toLong().takeIf { it > 0 }?.let { durationMillis = it }
                        if (positionMillis > 0) prepared.seekTo(positionMillis.toInt())
                        prepared.start()
                        player = prepared
                        isPlaying = true
                    }
                }
            }
        }
    }
    SignalCard(
        modifier = modifier.fillMaxWidth().testTag("transcript-audio"),
        padding = PaddingValues(horizontal = 14.dp, vertical = 12.dp),
        radius = SignalMetrics.GroupRadius,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SignalCircleButton(
                icon = if (isPlaying) Icons.Outlined.Pause else Icons.Outlined.PlayArrow,
                contentDescription = voxString(if (isPlaying) "Pause recording" else "Play recording"),
                onClick = togglePlayback,
                filled = signal.text,
                contentColor = signal.bg,
                enabled = !unavailable && !isPreparing,
            )
            Column(Modifier.weight(1f)) {
                val playbackLabel = voxString("Playback position")
                Slider(
                    value = if (durationMillis > 0) (positionMillis.toFloat() / durationMillis).coerceIn(0f, 1f) else 0f,
                    onValueChange = { fraction ->
                        positionMillis = (fraction * durationMillis).toLong()
                        player?.seekTo(positionMillis.toInt())
                    },
                    enabled = !unavailable && durationMillis > 0,
                    colors = SliderDefaults.colors(
                        thumbColor = signal.text,
                        activeTrackColor = signal.tint,
                        inactiveTrackColor = signal.well,
                    ),
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = playbackLabel },
                )
                Text(
                    listOfNotNull(
                        "${formatTranscriptDuration(positionMillis)} / ${formatTranscriptDuration(durationMillis)}",
                        if (state.speakerCount > 0) voxFormat("%lld speakers", state.speakerCount) else null,
                    ).joinToString(" · "),
                    style = SignalType.monoCaption,
                    color = signal.muted,
                )
            }
        }
        if (unavailable) {
            Spacer(Modifier.height(8.dp))
            Text(
                voxString("Playback is unavailable, but the audio remains safely attached."),
                style = SignalType.caption,
                color = signal.muted,
            )
        }
    }
}
