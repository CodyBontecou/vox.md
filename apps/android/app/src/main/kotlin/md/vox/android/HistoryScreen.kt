package md.vox.android

import android.Manifest
import android.app.Activity
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.result.IntentSenderRequest
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsFocusedAsState
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Search
import androidx.compose.material.icons.outlined.SearchOff
import androidx.compose.material3.minimumInteractiveComponentSize
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalDivider
import md.vox.android.ui.SignalChip
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalBanner
import md.vox.android.ui.SignalInvertedCard
import md.vox.android.ui.SignalPillButton
import md.vox.android.ui.SignalSectionLabel
import md.vox.android.capturedomain.CaptureHistoryDetail
import md.vox.android.ui.SignalIconTile
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalStatus
import md.vox.android.ui.SignalStatusBadge
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalStatusColors
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.absolutePadding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.FormatListBulleted
import androidx.compose.material.icons.automirrored.outlined.Undo
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Alarm
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.BarChart
import androidx.compose.material.icons.outlined.CalendarToday
import androidx.compose.material.icons.outlined.CheckBox
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.Dashboard
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Language
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.LocationOn
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material.icons.outlined.WorkOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.VerticalDivider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.AbsoluteAlignment
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import kotlinx.coroutines.delay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions.RESULT_FORMAT_JPEG
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions.RESULT_FORMAT_PDF
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions.SCANNER_MODE_FULL
import md.vox.android.capturedomain.CaptureRouteOverride
import md.vox.android.capturedomain.CaptureURLDeliverySettings
import md.vox.android.capturedomain.normalizedTranscriptProperty
import md.vox.android.capturedomain.CaptureHeadingPosition
import md.vox.android.capturedomain.CaptureRailSide
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureAttachment
import md.vox.android.ui.GeistMonoFontFamily
import md.vox.android.capturedomain.CaptureComposerCommand
import md.vox.android.capturedomain.CaptureInsertionFormatter
import md.vox.android.capturedomain.CaptureComposerTextEditor
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CapturePresetQuickAccess
import md.vox.android.capturedomain.CapturePresetEmoji
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CaptureMetadataScope
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CaptureRollingPeriod
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CaptureMissingHeadingBehavior
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureProcessingScope
import md.vox.android.capturedomain.CapturePresetLocationPolicy
import md.vox.android.capturedomain.CaptureLocationPrecision
import md.vox.android.capturedomain.CaptureLocationUnavailableBehavior
import md.vox.android.capturedomain.CaptureLocationUnavailableReason
import md.vox.android.capturedomain.CaptureLocationOutputMode
import md.vox.android.capturedomain.CaptureLocationField
import md.vox.android.capturedomain.CaptureLocationStructuredField
import md.vox.android.capturedomain.DEFAULT_CAPTURE_LOCATION_FIELDS
import md.vox.android.capturedomain.CaptureLocationOutcome
import md.vox.android.capturedomain.CaptureLocationLabel
import md.vox.android.capturedomain.CaptureLocationLabelLookupClass
import md.vox.android.capturedomain.CaptureLocationLabelObservation
import md.vox.android.capturedomain.CaptureLocationLabelOutcome
import md.vox.android.capturedomain.CaptureLocationSnapshot
import md.vox.android.capturedomain.CURRENT_LOCATION_LABEL_CONSENT_VERSION
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureExportFileFormat
import md.vox.android.capturedomain.CaptureExportFileMode
import md.vox.android.capturedomain.CaptureExportYAMLProperty
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.resolvingEntryTemplate
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureSubmitResult
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.capturedomain.WearRemoteRecordingPhase
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.capturedomain.CompletedRecordingActivity
import md.vox.android.ui.CaptureUiState
import md.vox.android.ui.CaptureViewModel
import md.vox.android.ui.VoxColors
import md.vox.android.ui.VoxTheme
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.CurrentLocationResolver
import md.vox.android.platformservices.CurrentLocationResult
import md.vox.android.platformservices.LocalTextRecognition
import md.vox.android.platformservices.LiveSpeechPhase
import md.vox.android.platformservices.LiveSpeechRegistry
import md.vox.android.platformservices.LiveSpeechState
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingJobPolicyStore
import md.vox.android.platformservices.RecordingProcessingPolicy
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingStatusRegistry
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.platformservices.SpeechModelManager
import md.vox.android.platformservices.SpeechModelSelectionMode
import md.vox.android.platformservices.TranscriptionUsageState
import md.vox.android.platformservices.shouldDeleteRecordingAudio
import md.vox.android.platformservices.shouldProcessRecordingAutomatically
import java.text.DateFormat
import java.text.SimpleDateFormat
import java.io.File
import java.util.Date
import java.util.Calendar
import java.util.Locale
import java.util.UUID
import kotlin.math.roundToLong

internal enum class UnifiedHistoryKind(val label: String) {
    ALL("All"),
    CAPTURES("Captures"),
    TRANSCRIPTS("Transcripts");

    /** Localizable chip label; literal sources keep the catalog audit static. */
    val labelText: VoxUiText
        get() = when (this) {
            ALL -> voxUiText("All")
            CAPTURES -> voxUiText("Captures")
            TRANSCRIPTS -> voxUiText("Transcripts")
        }
}

internal sealed interface UnifiedHistoryRow {
    val stableKey: String
    val sortTime: Long

    data class Capture(val item: CaptureHistoryItem) : UnifiedHistoryRow {
        override val stableKey: String = "capture:${item.requestID}"
        override val sortTime: Long = item.updatedAtEpochMillis
    }

    data class Transcript(val item: RecordingTranscriptionState) : UnifiedHistoryRow {
        override val stableKey: String = "transcript:${item.sessionID}"
        override val sortTime: Long = item.completedAtEpochMillis ?: item.recordedAtEpochMillis ?: 0L
    }
}

/** Local midnight that starts the day containing [epochMillis]. */
internal fun libraryStartOfDay(epochMillis: Long): Long = Calendar.getInstance().apply {
    timeInMillis = epochMillis
    set(Calendar.HOUR_OF_DAY, 0)
    set(Calendar.MINUTE, 0)
    set(Calendar.SECOND, 0)
    set(Calendar.MILLISECOND, 0)
}.timeInMillis

/** "Today", "Yesterday", or the medium date of the day starting at [dayStart]. */
@Composable
internal fun libraryDayLabel(dayStart: Long, nowEpochMillis: Long): String {
    val today = libraryStartOfDay(nowEpochMillis)
    val yesterday = libraryStartOfDay(today - 1L)
    return when (dayStart) {
        today -> voxString("Today")
        yesterday -> voxString("Yesterday")
        else -> DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(dayStart))
    }
}

/**
 * One Markdown document with everything the Library still holds locally: each pending
 * capture as it would be written, and each completed transcript. Completed captures are
 * content-free markers and are skipped. Returns null when nothing has text.
 */
internal fun libraryMarkdownExport(
    captures: List<CaptureHistoryDetail>,
    transcripts: List<RecordingTranscriptionState>,
): String? {
    val sections = buildList {
        captures.sortedByDescending(CaptureHistoryDetail::createdAtEpochMillis).forEach { detail ->
            HistoryDetailExporter.render(detail, HistoryExportFormat.MARKDOWN).trim().takeIf(String::isNotBlank)?.let(::add)
        }
        transcripts
            .filter { it.phase == RecordingTranscriptionPhase.COMPLETED && !it.preferredTranscript.isNullOrBlank() }
            .sortedByDescending { it.recordedAtEpochMillis ?: it.completedAtEpochMillis ?: 0L }
            .forEach { add(TranscriptExporter.render(it, TranscriptExportFormat.MARKDOWN).trim()) }
    }
    return sections.takeIf { it.isNotEmpty() }?.joinToString(separator = "\n\n---\n\n", postfix = "\n")
}

@Composable
internal fun HistoryScreen(
    items: List<CaptureHistoryItem>,
    transcripts: List<RecordingTranscriptionState>,
    isBusy: Boolean,
    navigateBack: (() -> Unit)?,
    refresh: () -> Unit,
    retry: (String) -> Unit,
    repairAccess: (String?) -> Unit,
    openDetail: (String) -> Unit,
    openTranscript: (String) -> Unit,
    clearCompleted: () -> Unit,
    initialQuery: String = "",
    initialKind: UnifiedHistoryKind = UnifiedHistoryKind.ALL,
    initialNeedsAttentionOnly: Boolean = false,
    initialShowsClearConfirmation: Boolean = false,
    /** Route (capture preset) name for a pending capture, from its frozen preset ID. */
    captureRouteName: (CaptureHistoryItem) -> String? = { null },
    /** Route name frozen with a recording; may read local storage, so it runs off the main thread. */
    transcriptRouteName: suspend (String) -> String? = { null },
    /** Loads a capture's local package for "Export all as Markdown". */
    loadCaptureDetail: suspend (String) -> CaptureHistoryDetail? = { null },
    initialRoute: String? = null,
    /** Paid access ended: the Library stays readable, new captures need a plan. */
    isReadOnly: Boolean = false,
    openPlans: (() -> Unit)? = null,
    nowEpochMillis: Long = System.currentTimeMillis(),
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var query by rememberSaveable { mutableStateOf(initialQuery) }
    var needsAttentionOnly by rememberSaveable { mutableStateOf(initialNeedsAttentionOnly) }
    var kind by rememberSaveable { mutableStateOf(initialKind.name) }
    var route by rememberSaveable { mutableStateOf(initialRoute) }
    var showsClearConfirmation by rememberSaveable { mutableStateOf(initialShowsClearConfirmation) }
    var exportMenuOpen by remember { mutableStateOf(false) }
    var isExporting by remember { mutableStateOf(false) }
    val pendingExport = rememberPendingDocumentRequest()
    val exportStore = remember(context) { PendingTextExportStore(java.io.File(context.noBackupFilesDir, "pending-library-exports")) }
    var operationMessage by remember { mutableStateOf<VoxUiText?>(null) }
    val transcriptIDs = transcripts.map(RecordingTranscriptionState::sessionID)
    val transcriptRoutes by produceState(emptyMap<String, String>(), transcriptIDs) {
        value = withContext(Dispatchers.IO) {
            transcriptIDs.mapNotNull { id -> runCatching { transcriptRouteName(id) }.getOrNull()?.let { id to it } }.toMap()
        }
    }
    val routeOf: (UnifiedHistoryRow) -> String? = { row ->
        when (row) {
            is UnifiedHistoryRow.Capture -> captureRouteName(row.item)
            is UnifiedHistoryRow.Transcript -> transcriptRoutes[row.item.sessionID]
        }
    }
    val allRows = buildList<UnifiedHistoryRow> {
        items.forEach { add(UnifiedHistoryRow.Capture(it)) }
        transcripts.forEach { add(UnifiedHistoryRow.Transcript(it)) }
    }.sortedByDescending(UnifiedHistoryRow::sortTime)
    val routeNames = allRows.mapNotNull(routeOf).filter(String::isNotBlank).distinct()
    val selectedRoute = route?.takeIf(routeNames::contains)
    val searchTerms = query.trim().split(Regex("\\s+")).filter(String::isNotBlank)
    val unifiedRows = allRows.filter { row ->
        val rowRoute = routeOf(row)
        val matchesRoute = selectedRoute == null || rowRoute == selectedRoute
        val matches = when (row) {
            is UnifiedHistoryRow.Capture -> {
                val item = row.item
                val searchText = listOfNotNull(
                    item.requestID,
                    historyTitleUiText(item.state).source,
                    item.title,
                    item.snippet,
                    item.logicalPath,
                    item.captureSource,
                    rowRoute,
                ).joinToString(" ")
                searchTerms.all { searchText.contains(it, ignoreCase = true) } &&
                    (!needsAttentionOnly || item.state != CaptureState.COMPLETED) &&
                    kind != UnifiedHistoryKind.TRANSCRIPTS.name
            }
            is UnifiedHistoryRow.Transcript -> {
                val transcript = row.item
                (TranscriptSearch.matches(transcript, query) ||
                    (rowRoute != null && searchTerms.isNotEmpty() && searchTerms.all { rowRoute.contains(it, ignoreCase = true) })) &&
                    (!needsAttentionOnly || transcript.phase != RecordingTranscriptionPhase.COMPLETED) &&
                    kind != UnifiedHistoryKind.CAPTURES.name
            }
        }
        matchesRoute && matches
    }
    val dayGroups = unifiedRows.groupBy { libraryStartOfDay(it.sortTime) }.toSortedMap(compareByDescending { it })
    val hasExportableContent = items.any { it.state != CaptureState.COMPLETED } ||
        transcripts.any { it.phase == RecordingTranscriptionPhase.COMPLETED && !it.preferredTranscript.isNullOrBlank() }
    val createDocument = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/markdown")) { uri ->
        val exportKey = pendingExport.consume()
        if (exportKey != null) {
            scope.launch {
                val written = withContext(Dispatchers.IO) {
                    runCatching {
                        if (uri == null) {
                            exportStore.discard(exportKey)
                            false
                        } else exportStore.consume(exportKey) { input ->
                            context.contentResolver.openOutputStream(uri, "w")?.use { output ->
                                input.copyTo(output)
                                output.flush()
                                true
                            } ?: false
                        }
                    }.getOrDefault(false)
                }
                if (uri != null) operationMessage = if (written) {
                    voxUiText("%@ exported.", voxUiText("Markdown"))
                } else {
                    voxUiText("The export could not be written.")
                }
            }
        }
    }

    val exportAll: () -> Unit = {
        exportMenuOpen = false
        isExporting = true
        scope.launch {
            val details = items
                .filter { it.state != CaptureState.COMPLETED }
                .mapNotNull { runCatching { loadCaptureDetail(it.requestID) }.getOrNull() }
            val markdown = withContext(Dispatchers.Default) { libraryMarkdownExport(details, transcripts) }
            if (markdown == null) {
                operationMessage = voxUiText("The export could not be written.")
            } else {
                val exportKey = withContext(Dispatchers.IO) { runCatching { exportStore.stage(markdown) }.getOrNull() }
                if (exportKey == null) {
                    operationMessage = voxUiText("The export could not be written.")
                } else {
                    pendingExport.begin(exportKey)
                    createDocument.launch("vox-library.md")
                }
            }
            isExporting = false
        }
    }
    val signal = Signal.colors
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(signal.bg)
            .navigationBarsPadding(),
    ) {
        VoxTopBar(
            title = voxUiText("Library"),
            navigateBack = navigateBack,
            actions = {
                SignalCircleButton(
                    icon = Icons.Outlined.Refresh,
                    contentDescription = voxString("Refresh"),
                    onClick = refresh,
                    enabled = !isBusy,
                )
                Box {
                    val exportLabel = voxString("Export all")
                    SignalPillButton(
                        text = voxString("Export"),
                        onClick = { exportMenuOpen = true },
                        modifier = Modifier
                            .padding(end = 4.dp)
                            .semantics { contentDescription = exportLabel }
                            .testTag("library-export-menu"),
                    )
                    LibraryExportMenu(
                        expanded = exportMenuOpen,
                        onDismiss = { exportMenuOpen = false },
                        labels = listOf(voxString("Export all as Markdown"), voxString("Clear Library…")),
                        enabled = listOf(
                            hasExportableContent && !isExporting,
                            !isBusy && items.any { it.state == CaptureState.COMPLETED },
                        ),
                        destructive = setOf(1),
                        onSelect = { index ->
                            if (index == 0) {
                                exportAll()
                            } else {
                                exportMenuOpen = false
                                showsClearConfirmation = true
                            }
                        },
                    )
                }
            },
        )
        if (isReadOnly) {
            SignalInvertedCard(
                title = voxString("Your subscription has ended"),
                message = voxString("You can still read, search, copy, export and delete everything here. New captures and edits need Vox.md."),
                actionLabel = openPlans?.let { voxString("See plans") },
                onAction = openPlans,
                modifier = Modifier
                    .padding(horizontal = SignalMetrics.PageGutter)
                    .padding(bottom = 12.dp)
                    .testTag("library-read-only"),
            )
        }
        LibrarySearchField(
            value = query,
            onValueChange = { query = it.take(128) },
            modifier = Modifier.padding(horizontal = SignalMetrics.PageGutter),
        )
        val allLabel = voxString("All")
        LazyRow(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 6.dp)
                .testTag("library-filters"),
            contentPadding = PaddingValues(horizontal = SignalMetrics.PageGutter),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            item(key = "all") {
                LibraryFilterChip(
                    text = allLabel,
                    selected = selectedRoute == null && kind == UnifiedHistoryKind.ALL.name,
                    onClick = {
                        route = null
                        kind = UnifiedHistoryKind.ALL.name
                    },
                )
            }
            items(routeNames, key = { "route:$it" }) { name ->
                LibraryFilterChip(
                    text = name,
                    selected = selectedRoute == name,
                    onClick = { route = if (selectedRoute == name) null else name },
                )
            }
            items(UnifiedHistoryKind.entries.filter { it != UnifiedHistoryKind.ALL }, key = UnifiedHistoryKind::name) { option ->
                LibraryFilterChip(
                    text = option.labelText.localized(),
                    selected = kind == option.name,
                    onClick = { kind = if (kind == option.name) UnifiedHistoryKind.ALL.name else option.name },
                )
            }
            item(key = "needs-attention") {
                LibraryFilterChip(
                    text = voxString("Needs attention"),
                    selected = needsAttentionOnly,
                    onClick = { needsAttentionOnly = !needsAttentionOnly },
                    toggle = true,
                    dotColor = signal.warning,
                )
            }
        }
        Text(
            voxFormat("%lld of %lld", unifiedRows.size, items.size + transcripts.size),
            style = SignalType.sectionLabel,
            color = signal.muted,
            modifier = Modifier.padding(start = SignalMetrics.PageGutter + 4.dp, end = SignalMetrics.PageGutter, top = 2.dp, bottom = 8.dp),
        )
        operationMessage?.let { message ->
            SignalBanner(
                message = message.localized(),
                status = SignalStatus.ACTIVE,
                liveRegion = true,
                modifier = Modifier.padding(horizontal = SignalMetrics.PageGutter).padding(bottom = 8.dp),
            )
        }
        if (unifiedRows.isEmpty()) {
            val nothingYet = items.isEmpty() && transcripts.isEmpty()
            if (nothingYet) {
                EmptyHistory(
                    modifier = Modifier.fillMaxWidth().weight(1f),
                    title = voxString("Nothing in Library Yet"),
                    detail = voxString("Record or send a Capture to add it to your Library."),
                    icon = Icons.Outlined.Inbox,
                )
            } else {
                LibraryNoMatches(query = query, modifier = Modifier.fillMaxWidth().weight(1f))
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().weight(1f).testTag("library-list"),
                contentPadding = PaddingValues(
                    start = SignalMetrics.PageGutter,
                    end = SignalMetrics.PageGutter,
                    top = 2.dp,
                    bottom = 24.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                dayGroups.forEach { (dayStart, rows) ->
                    item(key = "day:$dayStart") {
                        SignalSectionLabel(
                            libraryDayLabel(dayStart, nowEpochMillis),
                            Modifier.padding(start = 4.dp, top = 8.dp),
                            color = signal.muted,
                        )
                    }
                    // Library board: a day's captures share one white bordered card.
                    item(key = "rows:$dayStart") {
                        SignalCard(
                            modifier = Modifier.fillMaxWidth(),
                            padding = PaddingValues(0.dp),
                            radius = SignalMetrics.GroupRadius,
                        ) {
                            rows.forEachIndexed { index, row ->
                                if (index > 0) SignalDivider(inset = 14.dp)
                                androidx.compose.runtime.key(row.stableKey) {
                                    when (row) {
                                        is UnifiedHistoryRow.Capture -> HistoryCard(
                                            item = row.item,
                                            isBusy = isBusy,
                                            retry = { retry(row.item.requestID) },
                                            repairAccess = { repairAccess(row.item.requestID) },
                                            openDetail = { openDetail(row.item.requestID) },
                                            routeName = routeOf(row),
                                            grouped = true,
                                        )
                                        is UnifiedHistoryRow.Transcript -> TranscriptHistoryCard(
                                            transcript = row.item,
                                            openDetail = { openTranscript(row.item.sessionID) },
                                            routeName = routeOf(row),
                                            grouped = true,
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    if (showsClearConfirmation) {
        LibraryConfirmDialog(
            title = voxString("Clear completed History?"),
            message = voxString("Completed local History markers will be removed. Markdown notes already written to your folder are not deleted, and lifetime Stats remain content-free and intact."),
            confirmLabel = voxString("Clear"),
            onConfirm = {
                showsClearConfirmation = false
                clearCompleted()
            },
            onDismiss = { showsClearConfirmation = false },
        )
    }
}

/** Search found nothing: explain the Library's scope and offer an Obsidian search when it is installed. */
@Composable
private fun LibraryNoMatches(query: String, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val trimmed = query.trim()
    val searchUri = remember(trimmed) { trimmed.takeIf(String::isNotEmpty)?.let(::obsidianSearchUri) }
    val canSearchObsidian = remember(searchUri) { searchUri != null && canOpenObsidian(context, searchUri) }
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()).padding(top = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        SignalEmptyState(
            icon = Icons.Outlined.SearchOff,
            title = voxString("No captures match"),
            message = voxString("Library searches what Vox.md captured on this device. Older notes live in your vault."),
            iconTint = Signal.colors.muted,
            action = if (canSearchObsidian && searchUri != null) {
                {
                    SignalButton(
                        text = voxString("Search in Obsidian"),
                        onClick = { openObsidian(context, searchUri) },
                        variant = SignalButtonVariant.SECONDARY,
                        size = SignalButtonSize.MEDIUM,
                        fillWidth = false,
                    )
                }
            } else null,
        )
    }
}

/** Capsule search field on a white card; its label stays in the semantics tree while text is entered. */
@Composable
private fun LibrarySearchField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val signal = Signal.colors
    val interaction = remember { MutableInteractionSource() }
    val focused by interaction.collectIsFocusedAsState()
    val label = voxString("Search words, routes, files")
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = true,
        textStyle = MaterialTheme.typography.bodyLarge.copy(color = signal.text),
        cursorBrush = SolidColor(signal.tint),
        interactionSource = interaction,
        modifier = modifier.fillMaxWidth(),
        decorationBox = { innerTextField ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 48.dp)
                    .clip(CircleShape)
                    .background(signal.card)
                    .border(if (focused) 2.dp else 1.dp, if (focused) signal.tint else signal.border, CircleShape)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(Icons.Outlined.Search, contentDescription = null, tint = signal.muted, modifier = Modifier.size(18.dp))
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
                    Text(
                        label,
                        style = MaterialTheme.typography.bodyLarge,
                        color = signal.muted,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.alpha(if (value.isEmpty()) 1f else 0f),
                    )
                    innerTextField()
                }
            }
        },
    )
}

/** Signal filter capsule: ink when on, white bordered when off, with a 48dp touch target. */
@Composable
private fun LibraryFilterChip(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    toggle: Boolean = false,
    dotColor: Color? = null,
) {
    val signal = Signal.colors
    val selection = if (toggle) {
        Modifier.toggleable(value = selected, role = Role.Checkbox, onValueChange = { onClick() })
    } else {
        Modifier.selectable(selected = selected, role = Role.Tab, onClick = onClick)
    }
    Row(
        modifier = modifier
            .minimumInteractiveComponentSize()
            .heightIn(min = 34.dp)
            .clip(CircleShape)
            .background(if (selected) signal.text else signal.card)
            .then(if (selected) Modifier else Modifier.border(1.dp, signal.border, CircleShape))
            .then(selection)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        if (dotColor != null) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(dotColor))
        }
        Text(
            text,
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Medium),
            color = if (selected) signal.bg else signal.text,
            maxLines = 1,
        )
    }
}

/** Signal-styled confirmation dialog shared by the Library screens. */
@Composable
internal fun LibraryConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val signal = Signal.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = signal.card,
        titleContentColor = signal.text,
        textContentColor = signal.muted,
        shape = RoundedCornerShape(SignalMetrics.CardRadius),
        tonalElevation = 0.dp,
        title = { Text(title, style = MaterialTheme.typography.titleLarge) },
        text = { Text(message, style = MaterialTheme.typography.bodyMedium) },
        confirmButton = {
            TextButton(onClick = onConfirm) {
                Text(confirmLabel, color = signal.error, style = MaterialTheme.typography.labelLarge)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(voxString("Cancel"), color = signal.text, style = MaterialTheme.typography.labelLarge)
            }
        },
    )
}

@Composable
internal fun EmptyHistory(
    modifier: Modifier = Modifier,
    title: String = "No captures yet",
    detail: String = "Sent and recoverable captures will appear here without storing their note text.",
    icon: ImageVector = Icons.Outlined.Inbox,
) {
    Column(
        modifier = modifier.verticalScroll(rememberScrollState()).padding(top = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        SignalEmptyState(icon = icon, title = title, message = detail)
    }
}

internal fun libraryCaptureStatus(state: CaptureState): SignalStatus = when (state) {
    CaptureState.COMPLETED -> SignalStatus.SUCCESS
    CaptureState.QUEUED, CaptureState.PREPARING, CaptureState.MATERIALIZED, CaptureState.COMMITTING -> SignalStatus.ACTIVE
    CaptureState.RETRYABLE_FAILURE, CaptureState.NEEDS_PERMISSION, CaptureState.NEEDS_USER_ACTION,
    CaptureState.UNKNOWN_OUTCOME -> SignalStatus.WARNING
    CaptureState.PERMANENT_FAILURE -> SignalStatus.ERROR
    CaptureState.DISCARDED -> SignalStatus.NEUTRAL
}

internal fun libraryCaptureIcon(state: CaptureState): ImageVector = when (state) {
    CaptureState.COMPLETED -> Icons.Outlined.CheckCircle
    CaptureState.QUEUED, CaptureState.PREPARING, CaptureState.MATERIALIZED, CaptureState.COMMITTING -> Icons.Outlined.ArrowUpward
    CaptureState.RETRYABLE_FAILURE -> Icons.Outlined.Refresh
    CaptureState.NEEDS_PERMISSION -> Icons.Outlined.FolderOpen
    CaptureState.NEEDS_USER_ACTION -> Icons.Outlined.ErrorOutline
    CaptureState.UNKNOWN_OUTCOME -> Icons.Outlined.Schedule
    CaptureState.PERMANENT_FAILURE -> Icons.Outlined.ErrorOutline
    CaptureState.DISCARDED -> Icons.Outlined.Close
}

@Composable
internal fun HistoryCard(
    item: CaptureHistoryItem,
    isBusy: Boolean,
    retry: () -> Unit,
    repairAccess: () -> Unit,
    openDetail: () -> Unit,
    routeName: String? = null,
    /** Inside a day's shared card (Library board): no card chrome of its own. */
    grouped: Boolean = false,
) {
    val signal = Signal.colors
    val completed = item.state == CaptureState.COMPLETED
    val needsPermission = item.state == CaptureState.NEEDS_PERMISSION
    val status = libraryCaptureStatus(item.state)
    val statusColors = signalStatusColors(status)
    val statusText = historyTitleUiText(item.state).localized()
    val headline = item.title?.takeIf(String::isNotBlank)
    SignalCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(14.dp),
        radius = if (grouped) 0.dp else SignalMetrics.GroupRadius,
        color = if (grouped) Color.Transparent else signal.card,
        borderColor = if (grouped) null else signal.border,
        onClick = if (completed) null else openDetail,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            SignalIconTile(
                icon = libraryCaptureIcon(item.state),
                size = 36.dp,
                fill = statusColors.fill,
                tint = statusColors.ink,
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.Top) {
                    Text(
                        headline ?: statusText,
                        style = SignalType.rowTitle,
                        color = signal.text,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .weight(1f)
                            .then(if (headline == null) Modifier.semantics { liveRegion = LiveRegionMode.Polite } else Modifier),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        item.requestID.take(8),
                        style = SignalType.monoCaption,
                        color = signal.faint,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
                item.snippet?.takeIf { it != item.title }?.let { snippet ->
                    Text(
                        snippet,
                        style = MaterialTheme.typography.bodyMedium,
                        color = signal.muted,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Text(
                    listOfNotNull(
                        routeName,
                        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(item.updatedAtEpochMillis)),
                    ).joinToString(" · "),
                    style = SignalType.monoCaption,
                    color = signal.muted,
                )
                item.logicalPath?.let { path ->
                    Text(path, style = SignalType.monoCaption, color = signal.muted, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                if (!completed) {
                    val sourceLabel = captureSourceUiText(item.captureSource).localized()
                    Text(
                        when (item.attachmentCount) {
                            0 -> sourceLabel
                            else -> voxFormat("%@ · %lld attachments", sourceLabel, item.attachmentCount.toLong())
                        },
                        style = SignalType.caption,
                        color = signal.muted,
                    )
                }
                if (headline != null) {
                    SignalStatusBadge(
                        text = statusText,
                        status = status,
                        modifier = Modifier.padding(top = 4.dp),
                        liveRegion = true,
                    )
                }
            }
        }
        if (!completed && item.state != CaptureState.DISCARDED) {
            Spacer(Modifier.height(12.dp))
            SignalButton(
                text = voxString(if (needsPermission) "Repair Folder Access" else "Retry"),
                onClick = if (needsPermission) repairAccess else retry,
                variant = if (needsPermission) SignalButtonVariant.PRIMARY else SignalButtonVariant.SECONDARY,
                size = SignalButtonSize.MEDIUM,
                enabled = !isBusy,
                icon = if (needsPermission) Icons.Outlined.FolderOpen else Icons.Outlined.Refresh,
                fillWidth = true,
            )
        }
    }
}

internal fun libraryTranscriptPhaseTitle(transcript: RecordingTranscriptionState): String = when (transcript.phase) {
    RecordingTranscriptionPhase.QUEUED -> "Transcript queued"
    RecordingTranscriptionPhase.PROCESSING -> "Transcribing"
    RecordingTranscriptionPhase.FINALIZING -> "Finalizing transcript"
    RecordingTranscriptionPhase.COMPLETED -> transcript.title ?: "Voice transcript"
    RecordingTranscriptionPhase.FAILED -> "Transcription needs attention"
    RecordingTranscriptionPhase.DISCARDED -> "Transcription discarded"
}

internal fun libraryTranscriptStatus(phase: RecordingTranscriptionPhase): SignalStatus = when (phase) {
    RecordingTranscriptionPhase.QUEUED, RecordingTranscriptionPhase.PROCESSING, RecordingTranscriptionPhase.FINALIZING -> SignalStatus.ACTIVE
    RecordingTranscriptionPhase.COMPLETED -> SignalStatus.SUCCESS
    RecordingTranscriptionPhase.FAILED -> SignalStatus.ERROR
    RecordingTranscriptionPhase.DISCARDED -> SignalStatus.NEUTRAL
}

/** Leading tile for a transcript: indigo microphone once complete, status-tinted otherwise. */
@Composable
internal fun LibraryTranscriptTile(phase: RecordingTranscriptionPhase, size: androidx.compose.ui.unit.Dp = 36.dp) {
    if (phase == RecordingTranscriptionPhase.COMPLETED) {
        SignalIconTile(Icons.Outlined.MicNone, primary = true, size = size)
    } else {
        val colors = signalStatusColors(libraryTranscriptStatus(phase))
        SignalIconTile(
            icon = when (phase) {
                RecordingTranscriptionPhase.QUEUED -> Icons.Outlined.Schedule
                RecordingTranscriptionPhase.PROCESSING, RecordingTranscriptionPhase.FINALIZING -> Icons.Outlined.GraphicEq
                RecordingTranscriptionPhase.FAILED -> Icons.Outlined.ErrorOutline
                else -> Icons.Outlined.Close
            },
            size = size,
            fill = colors.fill,
            tint = colors.ink,
        )
    }
}

@Composable
internal fun LibraryTranscriptProgress(transcript: RecordingTranscriptionState, modifier: Modifier = Modifier) {
    val signal = Signal.colors
    val active = transcript.phase == RecordingTranscriptionPhase.PROCESSING ||
        transcript.phase == RecordingTranscriptionPhase.FINALIZING
    if (!active) return
    val barModifier = modifier.fillMaxWidth().height(4.dp).clip(CircleShape)
    if (transcript.phase == RecordingTranscriptionPhase.PROCESSING && transcript.progress > 0f) {
        LinearProgressIndicator(
            progress = { transcript.progress.coerceIn(0f, 1f) },
            modifier = barModifier,
            color = signal.tint,
            trackColor = signal.well,
            drawStopIndicator = {},
            gapSize = 0.dp,
        )
    } else {
        LinearProgressIndicator(modifier = barModifier, color = signal.tint, trackColor = signal.well, gapSize = 0.dp)
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun TranscriptHistoryCard(
    transcript: RecordingTranscriptionState,
    openDetail: () -> Unit,
    routeName: String? = null,
    /** Inside a day's shared card (Library board): no card chrome of its own. */
    grouped: Boolean = false,
) {
    val signal = Signal.colors
    val title = libraryTranscriptPhaseTitle(transcript)
    SignalCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(14.dp),
        radius = if (grouped) 0.dp else SignalMetrics.GroupRadius,
        color = if (grouped) Color.Transparent else signal.card,
        borderColor = if (grouped) null else signal.border,
        onClick = openDetail,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            LibraryTranscriptTile(transcript.phase)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Row(verticalAlignment = Alignment.Top) {
                    Text(
                        title,
                        style = SignalType.rowTitle,
                        color = signal.text,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    Spacer(Modifier.width(8.dp))
                    Text(
                        formatTranscriptDuration(transcript.durationMillis),
                        style = SignalType.monoCaption,
                        color = signal.muted,
                        modifier = Modifier.padding(top = 2.dp),
                    )
                }
                transcript.preferredTranscript?.takeIf(String::isNotBlank)?.let { text ->
                    Text(
                        text.replace('\n', ' ').take(180),
                        style = MaterialTheme.typography.bodyMedium,
                        color = signal.muted,
                        maxLines = 3,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                LibraryTranscriptProgress(transcript, Modifier.padding(vertical = 4.dp))
                val metadata = listOfNotNull(
                    routeName,
                    transcript.completedAtEpochMillis?.let {
                        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(it))
                    },
                    transcript.modelName ?: transcript.modelID,
                    transcript.languageTag,
                )
                if (metadata.isNotEmpty()) {
                    Text(metadata.joinToString(" · "), style = SignalType.monoCaption, color = signal.muted)
                }
                if (transcript.category != null || transcript.tags.isNotEmpty()) {
                    FlowRow(
                        modifier = Modifier.padding(top = 2.dp),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        transcript.category?.let { SignalChip(it, color = signal.well, contentColor = signal.text) }
                        transcript.tags.forEach { tag -> SignalChip("#$tag", mono = true, color = signal.bg) }
                    }
                }
            }
        }
    }
}

internal fun historyTitleUiText(state: CaptureState): VoxUiText = when (state) {
    CaptureState.COMPLETED -> voxUiText("Capture sent")
    CaptureState.QUEUED, CaptureState.PREPARING, CaptureState.MATERIALIZED, CaptureState.COMMITTING -> voxUiText("Capture in progress")
    CaptureState.RETRYABLE_FAILURE -> voxUiText("Ready to retry")
    CaptureState.NEEDS_PERMISSION -> voxUiText("Folder access needed")
    CaptureState.NEEDS_USER_ACTION -> voxUiText("Action needed")
    CaptureState.UNKNOWN_OUTCOME -> voxUiText("Checking delivery")
    CaptureState.PERMANENT_FAILURE -> voxUiText("Capture failed")
    CaptureState.DISCARDED -> voxUiText("Capture discarded")
}
