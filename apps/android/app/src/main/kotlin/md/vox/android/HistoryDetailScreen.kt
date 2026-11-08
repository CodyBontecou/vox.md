package md.vox.android

import android.content.Intent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import androidx.compose.foundation.border
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Remove
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import md.vox.android.ui.SignalRouteTile
import md.vox.android.ui.SignalRouteTone
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
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

/** The three views of one capture: what is written, what was said or typed, and what happened to it. */
internal enum class CaptureDetailTab { WRITTEN, TRANSCRIPT, ROUTE_LOG }

internal enum class CaptureRouteLogOutcome { SUCCEEDED, SKIPPED, FAILED, PENDING }

/** One row of the Route log, derived only from what the local package records. */
internal data class CaptureRouteLogEntry(
    val title: VoxUiText,
    val outcome: CaptureRouteLogOutcome,
    val atEpochMillis: Long? = null,
    val detail: VoxUiText? = null,
)

/**
 * Builds the Route log from the capture package: captured, on-device processing, the
 * prepared entry and the delivery state. Android keeps no per-step timings, so only the
 * capture step carries a time.
 */
internal fun captureRouteLogEntries(detail: CaptureHistoryDetail): List<CaptureRouteLogEntry> = buildList {
    add(
        CaptureRouteLogEntry(
            title = voxUiText("Captured"),
            outcome = CaptureRouteLogOutcome.SUCCEEDED,
            atEpochMillis = detail.createdAtEpochMillis,
            detail = captureSourceUiText(detail.captureSource),
        ),
    )
    detail.processingMode?.takeIf { it != CaptureProcessingMode.NONE }?.let { mode ->
        val (title, outcome) = when (detail.processingOutcome) {
            CaptureTextProcessingOutcome.APPLIED, CaptureTextProcessingOutcome.UNCHANGED ->
                voxUiText("Processed on device") to CaptureRouteLogOutcome.SUCCEEDED
            CaptureTextProcessingOutcome.MODEL_FAILURE ->
                voxUiText("Processing failed") to CaptureRouteLogOutcome.FAILED
            else -> voxUiText("Processing skipped") to CaptureRouteLogOutcome.SKIPPED
        }
        add(CaptureRouteLogEntry(title, outcome, detail = processingModeUiText(mode)))
    }
    if (detail.preparedMarkdown != null) {
        add(CaptureRouteLogEntry(voxUiText("Shaped with the route template"), CaptureRouteLogOutcome.SUCCEEDED))
    }
    val deliverOutcome = when (detail.state) {
        CaptureState.COMPLETED -> CaptureRouteLogOutcome.SUCCEEDED
        CaptureState.DISCARDED -> CaptureRouteLogOutcome.SKIPPED
        CaptureState.RETRYABLE_FAILURE, CaptureState.NEEDS_PERMISSION, CaptureState.NEEDS_USER_ACTION,
        CaptureState.PERMANENT_FAILURE -> CaptureRouteLogOutcome.FAILED
        CaptureState.QUEUED, CaptureState.PREPARING, CaptureState.MATERIALIZED, CaptureState.COMMITTING,
        CaptureState.UNKNOWN_OUTCOME -> CaptureRouteLogOutcome.PENDING
    }
    add(
        CaptureRouteLogEntry(
            title = when (deliverOutcome) {
                CaptureRouteLogOutcome.SUCCEEDED -> voxUiText("Delivered")
                CaptureRouteLogOutcome.FAILED -> voxUiText("Delivery failed")
                else -> historyTitleUiText(detail.state)
            },
            outcome = deliverOutcome,
            detail = when (deliverOutcome) {
                CaptureRouteLogOutcome.SUCCEEDED -> detail.logicalPath?.let { voxUiText("%@", it) }
                else -> captureStateUiText(detail.state)
            },
        ),
    )
}

/** First line of what was captured, used as the detail heading. */
internal fun captureDetailHeadline(detail: CaptureHistoryDetail): String? =
    detail.capturedText.lineSequence().map(String::trim).firstOrNull(String::isNotEmpty)?.take(96)
        ?: detail.capturedURL?.take(96)

// region Obsidian

private const val OBSIDIAN_SCHEME = "obsidian"

/** `obsidian://open?vault=…&file=…` for a vault-relative note path; the vault is the chosen folder's name. */
internal fun obsidianOpenUri(vaultName: String, relativePath: String): Uri {
    val file = if (relativePath.endsWith(".md", ignoreCase = true)) relativePath.dropLast(3) else relativePath
    return Uri.Builder()
        .scheme(OBSIDIAN_SCHEME)
        .authority("open")
        .appendQueryParameter("vault", vaultName)
        .appendQueryParameter("file", file)
        .build()
}

internal fun obsidianSearchUri(query: String, vaultName: String? = null): Uri = Uri.Builder()
    .scheme(OBSIDIAN_SCHEME)
    .authority("search")
    .apply { if (vaultName != null) appendQueryParameter("vault", vaultName) }
    .appendQueryParameter("query", query)
    .build()

/** True only when an installed app (Obsidian) handles the `obsidian://` link. */
internal fun canOpenObsidian(context: Context, uri: Uri): Boolean = runCatching {
    context.packageManager.queryIntentActivities(Intent(Intent.ACTION_VIEW, uri), 0).isNotEmpty()
}.getOrDefault(false)

internal fun openObsidian(context: Context, uri: Uri) {
    runCatching {
        context.startActivity(Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

// endregion

@Composable
internal fun HistoryDetailScreen(
    detail: CaptureHistoryDetail?,
    isLoading: Boolean,
    isDeleting: Boolean,
    navigateBack: () -> Unit,
    delete: (String) -> Unit,
    initialOperationMessage: VoxUiText? = null,
    initialShowsDeleteConfirmation: Boolean = false,
    /** Name of the route (capture preset) the capture was frozen with. */
    routeName: String? = null,
    /** Display name of the chosen vault folder, used for `obsidian://open`. */
    vaultName: String? = null,
    retry: ((String) -> Unit)? = null,
    repairAccess: ((String) -> Unit)? = null,
    isBusy: Boolean = false,
    initialTab: CaptureDetailTab = CaptureDetailTab.WRITTEN,
) {
    val context = LocalContext.current
    val signal = Signal.colors
    var exportMenuOpen by remember { mutableStateOf(false) }
    var operationMessage by remember { mutableStateOf(initialOperationMessage) }
    var showsDeleteConfirmation by remember { mutableStateOf(initialShowsDeleteConfirmation) }
    var tab by rememberSaveable(detail?.requestID) { mutableStateOf(initialTab) }
    val exportDocument = rememberDetailExport { formatName, written ->
        val format = HistoryExportFormat.valueOf(formatName)
        operationMessage = if (written) voxUiText("%@ exported.", format.uiText())
            else voxUiText("The export could not be written.")
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
            else -> {
                val obsidianUri = remember(detail.requestID, detail.state, detail.logicalPath, vaultName) {
                    val path = detail.logicalPath
                    if (detail.state == CaptureState.COMPLETED && path != null && !vaultName.isNullOrBlank()) {
                        obsidianOpenUri(vaultName, path).takeIf { canOpenObsidian(context, it) }
                    } else null
                }
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = SignalMetrics.PageGutter)
                        .padding(top = 2.dp, bottom = 24.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    CaptureDetailHeader(detail, routeName)
                    operationMessage?.let { message ->
                        SignalBanner(
                            message = message.localized(),
                            status = SignalStatus.ACTIVE,
                            liveRegion = true,
                        )
                    }
                    LibrarySegmentedTabs(
                        options = listOf(
                            voxString("As written") to CaptureDetailTab.WRITTEN,
                            voxString("Transcript") to CaptureDetailTab.TRANSCRIPT,
                            voxString("Route log") to CaptureDetailTab.ROUTE_LOG,
                        ),
                        selected = tab,
                        onSelect = { tab = it },
                        contentDescription = voxString("View"),
                    )
                    when (tab) {
                        CaptureDetailTab.WRITTEN -> {
                            val markdown = detail.preparedMarkdown
                            if (markdown != null) {
                                LibraryCodeBlock(markdown)
                            } else {
                                Text(
                                    voxString("Rendered Markdown is unavailable until local preparation succeeds."),
                                    style = SignalType.caption,
                                    color = signal.muted,
                                    modifier = Modifier.padding(horizontal = 4.dp),
                                )
                                if (detail.capturedText.isNotBlank()) LibraryCodeBlock(HistoryDetailExporter.render(detail, HistoryExportFormat.MARKDOWN))
                            }
                        }
                        CaptureDetailTab.TRANSCRIPT -> {
                            if (detail.capturedText.isBlank() && detail.capturedURL == null) {
                                ContentText(voxString("No transcript for this capture."), muted = true)
                            }
                            if (detail.capturedText.isNotBlank()) ContentCard(voxString("Processed Text"), detail.capturedText)
                            detail.originalCapturedText?.let { original -> ContentCard(voxString("Original Text"), original) }
                            detail.processingNotice?.let { notice -> ContentCard(voxString("Processing Note"), notice) }
                            detail.capturedURL?.let { ContentCard(voxString("Captured Link"), it) }
                            if (detail.attachments.isNotEmpty()) {
                                ContentCard(
                                    voxString("Attachments"),
                                    detail.attachments.joinToString("\n") { "${it.displayName} · ${it.mediaType} · ${it.byteCount} bytes" },
                                )
                            }
                        }
                        CaptureDetailTab.ROUTE_LOG -> CaptureRouteLog(captureRouteLogEntries(detail))
                    }
                    DetailMetadataCard(detail)
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
                                    exportDocument(format.name, HistoryDetailExporter.render(detail, format), "vox-capture-${detail.requestID.take(8)}.${format.extension}")
                                },
                            )
                        }
                    }
                    SignalButton(
                        text = voxString("Copy Markdown"),
                        onClick = {
                            copyLibraryText(context, HistoryDetailExporter.render(detail, HistoryExportFormat.MARKDOWN))
                            operationMessage = voxUiText("Copied Markdown")
                        },
                        variant = SignalButtonVariant.SECONDARY,
                        size = SignalButtonSize.MEDIUM,
                        icon = Icons.Outlined.ContentCopy,
                        fillWidth = true,
                    )
                    val canRepair = detail.state == CaptureState.NEEDS_PERMISSION && repairAccess != null
                    val canRetry = retry != null && detail.state in setOf(
                        CaptureState.RETRYABLE_FAILURE,
                        CaptureState.UNKNOWN_OUTCOME,
                        CaptureState.NEEDS_USER_ACTION,
                        CaptureState.PERMANENT_FAILURE,
                    )
                    if (canRepair) {
                        SignalButton(
                            text = voxString("Fix access"),
                            onClick = { repairAccess?.invoke(detail.requestID) },
                            size = SignalButtonSize.LARGE,
                            enabled = !isBusy,
                            icon = Icons.Outlined.FolderOpen,
                        )
                    } else if (canRetry) {
                        SignalButton(
                            text = voxString("Retry delivery"),
                            onClick = { retry?.invoke(detail.requestID) },
                            size = SignalButtonSize.LARGE,
                            enabled = !isBusy,
                            loading = isBusy,
                            icon = Icons.Outlined.Refresh,
                        )
                    }
                    if (obsidianUri != null) {
                        SignalButton(
                            text = voxString("Open in Obsidian"),
                            onClick = { openObsidian(context, obsidianUri) },
                            size = SignalButtonSize.LARGE,
                            icon = Icons.AutoMirrored.Outlined.OpenInNew,
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

internal fun copyLibraryText(context: Context, text: String) {
    val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
    clipboard.setPrimaryClip(ClipData.newPlainText("Vox.md", text))
}

/** Route tile, route name and time, the capture's first line, then where it went. */
@Composable
private fun CaptureDetailHeader(detail: CaptureHistoryDetail, routeName: String?) {
    val signal = Signal.colors
    Column(Modifier.padding(horizontal = 4.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (routeName != null) {
                SignalRouteTile(routeName, size = 24.dp, tone = SignalRouteTone.PRIMARY)
                Text(routeName, style = SignalType.rowTitle, color = signal.text, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Text(
                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(detail.createdAtEpochMillis)),
                style = SignalType.monoCaption,
                color = signal.muted,
            )
        }
        Text(
            captureDetailHeadline(detail) ?: historyTitleUiText(detail.state).localized(),
            style = MaterialTheme.typography.headlineSmall,
            color = signal.text,
            maxLines = 3,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.semantics { heading() },
        )
        val path = detail.logicalPath
        if (detail.state == CaptureState.COMPLETED && path != null) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Icon(Icons.Outlined.Check, contentDescription = null, tint = signal.successText, modifier = Modifier.size(16.dp))
                Text(voxFormat("Delivered to %@", path), style = SignalType.caption, color = signal.successText)
            }
        } else {
            SignalStatusBadge(historyTitleUiText(detail.state).localized(), libraryCaptureStatus(detail.state), liveRegion = true)
        }
    }
}

/** Ink code block for Markdown exactly as it is (or would be) written. */
@Composable
internal fun LibraryCodeBlock(text: String, modifier: Modifier = Modifier) {
    val signal = Signal.colors
    Text(
        text.trimEnd(),
        style = SignalType.mono.copy(lineHeight = 20.sp),
        color = signal.onInverse,
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(SignalMetrics.GroupRadius))
            .background(signal.inverse)
            .padding(16.dp)
            .testTag("capture-detail-markdown"),
    )
}

@Composable
private fun CaptureRouteLog(steps: List<CaptureRouteLogEntry>) {
    val signal = Signal.colors
    SignalCard(
        modifier = Modifier.fillMaxWidth().testTag("capture-route-log"),
        padding = PaddingValues(horizontal = 14.dp),
        radius = SignalMetrics.GroupRadius,
    ) {
        steps.forEachIndexed { index, step ->
            if (index > 0) SignalDivider()
            val (icon, tint) = when (step.outcome) {
                CaptureRouteLogOutcome.SUCCEEDED -> Icons.Outlined.Check to signal.successText
                CaptureRouteLogOutcome.FAILED -> Icons.Outlined.ErrorOutline to signal.warningText
                CaptureRouteLogOutcome.SKIPPED -> Icons.Outlined.Remove to signal.muted
                CaptureRouteLogOutcome.PENDING -> Icons.Outlined.Schedule to signal.tint
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp).semantics(mergeDescendants = true) {},
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalAlignment = Alignment.Top,
            ) {
                Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(18.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(step.title.localized(), style = MaterialTheme.typography.labelLarge, color = signal.text)
                    step.detail?.let {
                        Text(
                            it.localized(),
                            style = SignalType.monoCaption,
                            color = if (step.outcome == CaptureRouteLogOutcome.FAILED) signal.warningText else signal.muted,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                step.atEpochMillis?.let {
                    Text(
                        DateFormat.getTimeInstance(DateFormat.MEDIUM).format(Date(it)),
                        style = SignalType.monoCaption,
                        color = signal.muted,
                    )
                }
            }
        }
    }
}

/** Pill segmented control on a well track; the selected segment is a raised card. */
@Composable
internal fun <T> LibrarySegmentedTabs(
    options: List<Pair<String, T>>,
    selected: T,
    onSelect: (T) -> Unit,
    modifier: Modifier = Modifier,
    contentDescription: String? = null,
) {
    val c = Signal.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(CircleShape)
            .background(c.well)
            .padding(3.dp)
            .selectableGroup()
            .then(if (contentDescription != null) Modifier.semantics { this.contentDescription = contentDescription } else Modifier),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
    ) {
        options.forEach { (label, value) ->
            val isSelected = value == selected
            Box(
                modifier = Modifier
                    .weight(1f)
                    .heightIn(min = SignalMetrics.ControlMedium - 6.dp)
                    .clip(CircleShape)
                    .background(if (isSelected) c.card else Color.Transparent)
                    .then(if (isSelected) Modifier.border(1.dp, c.border, CircleShape) else Modifier)
                    .selectable(selected = isSelected, role = Role.Tab, onClick = { onSelect(value) })
                    .padding(horizontal = 8.dp, vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.labelMedium.copy(
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    ),
                    color = if (isSelected) c.text else c.muted,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                )
            }
        }
    }
}

/** Export format menu on a white card, shared by capture and transcript detail. */
@Composable
internal fun LibraryExportMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    labels: List<String>,
    onSelect: (Int) -> Unit,
    enabled: List<Boolean> = emptyList(),
    destructive: Set<Int> = emptySet(),
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
            val isEnabled = enabled.getOrElse(index) { true }
            DropdownMenuItem(
                text = {
                    Text(
                        label,
                        style = MaterialTheme.typography.bodyLarge,
                        color = when {
                            !isEnabled -> signal.faint
                            index in destructive -> signal.error
                            else -> signal.text
                        },
                    )
                },
                enabled = isEnabled,
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
private fun ContentText(text: String, muted: Boolean = false) {
    SignalCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(16.dp), radius = SignalMetrics.GroupRadius) {
        Text(text, style = MaterialTheme.typography.bodyMedium, color = if (muted) Signal.colors.muted else Signal.colors.text)
    }
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
