package md.vox.android

import md.vox.android.ui.Signal
import md.vox.android.ui.SignalBanner
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalIconTile
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalStatus
import md.vox.android.ui.SignalType
import md.vox.android.ui.SignalWordmark
import md.vox.android.ui.VoxTheme
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.foundation.layout.navigationBars
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.graphics.Color

import android.Manifest
import android.app.Activity
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.absolutePadding
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
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

class MainActivity : AppCompatActivity() {
    private var externalCaptureRequest by mutableStateOf<ExternalCaptureRequest?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        externalCaptureRequest = ExternalCaptureRequestParser.parse(intent)
        enableEdgeToEdge()
        val root = (application as VoxApplication).compositionRoot
        setContent {
            VoxTheme {
                Box(Modifier.semantics { testTagsAsResourceId = true }) {
                    val model: CaptureViewModel = viewModel(factory = CaptureViewModel.factory(root.captureRepository))
                    VoxApp(
                        model = model,
                        billingManager = root.billingManager,
                        externalCaptureRequest = externalCaptureRequest,
                        consumeExternalCaptureRequest = { correlationID ->
                            if (externalCaptureRequest?.correlationID == correlationID) externalCaptureRequest = null
                        },
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ExternalCaptureRequestParser.parse(intent)?.let { externalCaptureRequest = it }
    }

    override fun onResume() {
        super.onResume()
        (application as VoxApplication).compositionRoot.billingManager.refresh()
    }
}

internal enum class Destination(val route: String) {
    Capture("capture"),
    History("history"),
    Settings("settings"),
    Presets("presets"),
    CaptureBar("capture-bar"),
    Stats("stats"),
    Models("models"),
    RecordingQueue("recording-queue"),
    AppLanguage("app-language"),
    DebugLog("debug-log"),
    Upgrade("upgrade"),
}

internal const val PRESET_EDITOR_ROUTE = "preset-editor"
internal const val HISTORY_DETAIL_ROUTE = "history-detail"
internal const val TRANSCRIPT_DETAIL_ROUTE = "transcript-detail"
internal const val DEFAULT_CAPTURE_PRESET_ID = "33333333-3333-4333-8333-333333333333"

@Composable
internal fun VoxApp(
    model: CaptureViewModel,
    billingManager: PlayBillingManager,
    externalCaptureRequest: ExternalCaptureRequest?,
    consumeExternalCaptureRequest: (String) -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    LaunchedEffect(state.presetCollection) { VoxPresetWidgetProvider.refreshAll(context) }
    if (state.pendingWidgetPresetID != null) {
        AlertDialog(onDismissRequest = model::dismissWidgetPreset,
            title = { Text(voxString("Use this preset for your draft?")) },
            text = { Text(voxString("Your text and attachments will be kept. One-off routing will reset.")) },
            confirmButton = { TextButton(onClick = model::confirmWidgetPreset) { Text(voxString("Use preset")) } },
            dismissButton = { TextButton(onClick = model::dismissWidgetPreset) { Text(voxString("Cancel")) } })
    }
    val recordingClient = remember(context) { AudioCaptureClient(context) }
    val recordingStatus by RecordingStatusRegistry.status.collectAsStateWithLifecycle()
    val liveSpeechState by LiveSpeechRegistry.state.collectAsStateWithLifecycle()
    val transcriptionClient = remember(context) { RecordingTranscriptionClient.get(context) }
    val transcriptionStates by transcriptionClient.states.collectAsStateWithLifecycle()
    val recordingPolicyStore = remember(context) { RecordingJobPolicyStore.get(context) }
    val configuredTranscriptExporter = remember(context) { AndroidConfiguredTranscriptExporter(context) }
    val configuredExportReceiptStore = remember(context) { ConfiguredTranscriptExportReceiptStore(context) }
    val transcriptionUsage by transcriptionClient.usage.collectAsStateWithLifecycle()
    val modelManager = remember(context) { SpeechModelManager.get(context) }
    val modelManagerState by modelManager.state.collectAsStateWithLifecycle()
    val automaticConfiguredExportAttempts = remember { mutableSetOf<String>() }
    val reportedWearCaptureStates = remember { mutableMapOf<String, CaptureState>() }
    val microphonePermissions = remember {
        buildList {
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
        }.toTypedArray()
    }
    var pendingRecordingPreset by remember { mutableStateOf<CapturePreset?>(null) }
    // Whether the system offered the rationale before this request; together with the
    // reading afterwards it tells a permanent denial (Capture then offers Open Settings)
    // from a first refusal or a dismissed dialog.
    var microphoneRationaleBeforeRequest by remember { mutableStateOf(false) }
    val microphonePermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        val preset = pendingRecordingPreset
        pendingRecordingPreset = null
        val granted = grants[Manifest.permission.RECORD_AUDIO] == true
        MicrophonePermissionMemory.recordResult(
            context,
            granted = granted,
            rationaleBefore = microphoneRationaleBeforeRequest,
            rationaleAfter = MicrophonePermissionMemory.shouldShowRationale(context.findActivity()),
        )
        if (granted && preset != null) recordingClient.start(preset)
    }
    val startRecording: () -> Unit = {
        recordingClient.dismissResult()
        val preset = state.presetCollection?.activePreset?.resolvingEntryTemplate(
            state.entryTemplates,
            state.draft.entryTemplateIDOverride,
        )?.copy(entryTemplateID = null)
        if (preset == null) {
            model.presentNotice(voxUiText("Choose an enabled Capture Preset before recording."))
        } else if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            recordingClient.start(preset)
        } else {
            pendingRecordingPreset = preset
            microphoneRationaleBeforeRequest = MicrophonePermissionMemory.shouldShowRationale(context.findActivity())
            microphonePermissionLauncher.launch(microphonePermissions)
        }
    }
    LaunchedEffect(recordingStatus.sessionID, recordingStatus.phase) {
        PrivacySafeDebugLog.record(
            context,
            PrivacySafeDebugLog.Event.RECORDING_PHASE_CHANGED,
            mapOf("phase" to recordingStatus.phase.name.lowercase(Locale.ROOT)),
        )
        val completed = recordingClient.recordings()
            .filter { it.phase == RecordingPhase.COMPLETED && it.sessionID != null }
            .map { recording ->
                CompletedRecordingActivity(
                    sessionID = requireNotNull(recording.sessionID),
                    completedAtEpochMillis = recording.createdAtEpochMillis + recording.elapsedMillis,
                    durationMillis = recording.elapsedMillis,
                )
            }
        model.reconcileCompletedRecordings(completed)
    }
    LaunchedEffect(
        recordingStatus.sessionID,
        recordingStatus.phase,
        modelManagerState.selectedReadyModel?.descriptor?.id,
    ) {
        val sessionID = recordingStatus.sessionID ?: return@LaunchedEffect
        val phase = transcriptionStates[sessionID]?.phase
        val processingPolicy = recordingPolicyStore.policy(sessionID).processing
        if (processingPolicy == RecordingProcessingPolicy.WHEN_IDLE && recordingStatus.phase == RecordingPhase.COMPLETED) {
            kotlinx.coroutines.delay(2_000)
        }
        val canStartForPolicy = shouldProcessRecordingAutomatically(
            processingPolicy,
            appIsIdle = processingPolicy == RecordingProcessingPolicy.WHEN_IDLE && !RecordingStatusRegistry.status.value.isActive,
        )
        if (canStartForPolicy && shouldStartAutomaticTranscription(recordingStatus, phase, modelManagerState.selectedReadyModel != null)) {
            transcriptionClient.process(sessionID)
        }
    }
    LaunchedEffect(modelManagerState.selectedReadyModel?.descriptor?.id, state.isLoading) {
        if (state.isLoading || modelManagerState.selectedReadyModel == null) return@LaunchedEffect
        recordingClient.recordings().asSequence()
            .filter { recording ->
                val id = recording.sessionID
                id != null && recording.phase == RecordingPhase.COMPLETED && recordingClient.isImportedFromWear(id)
            }
            .forEach { recording ->
                val id = requireNotNull(recording.sessionID)
                val preset = recordingClient.frozenPreset(id)
                val transcription = transcriptionStates[id]
                if (preset?.watchOutputMode == CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE &&
                    (transcription == null ||
                        (transcription.phase == RecordingTranscriptionPhase.FAILED && transcription.failureCode == "modelNotInstalled"))
                ) {
                    WearTranscriptDeliveryWorker.enqueue(context, id, recording.chunkCount)
                }
            }
    }
    LaunchedEffect(transcriptionStates, state.isLoading, state.history) {
        val now = System.currentTimeMillis()
        transcriptionStates.values.forEach { transcription ->
            val frozenPreset = recordingClient.frozenPreset(transcription.sessionID)
            val exportSettings = frozenPreset?.exportSettings
            val configuredExportIsReady = transcription.phase == RecordingTranscriptionPhase.COMPLETED &&
                exportSettings?.usesCustomExportSettings == true && exportSettings.exportEnabled
            val configuredExportWasCompleted = if (configuredExportIsReady) {
                withContext(Dispatchers.IO) { configuredExportReceiptStore.wasExported(transcription.sessionID) }
            } else true
            if (transcription.phase == RecordingTranscriptionPhase.COMPLETED &&
                exportSettings?.usesCustomExportSettings == true && exportSettings.exportEnabled &&
                !configuredExportWasCompleted &&
                automaticConfiguredExportAttempts.add(transcription.sessionID)
            ) {
                val configuredAudioSource = configuredTranscriptAudioSource(
                    context = context,
                    client = recordingClient,
                    sessionID = transcription.sessionID,
                    preset = frozenPreset,
                )
                val audioWasRequired = frozenPreset.audioSaveMode != CaptureAudioSaveMode.OFF
                val exportResult = if (audioWasRequired && configuredAudioSource == null) {
                    ConfiguredTranscriptExportResult.Failed(
                        ConfiguredTranscriptExportFailure.RETAINED_AUDIO_UNAVAILABLE,
                    )
                } else {
                    withContext(Dispatchers.IO) {
                        configuredTranscriptExporter.export(transcription, exportSettings, configuredAudioSource)
                    }
                }
                when (val result = exportResult) {
                    ConfiguredTranscriptExportResult.Disabled -> Unit
                    is ConfiguredTranscriptExportResult.Exported -> {
                        if (!withContext(Dispatchers.IO) { configuredExportReceiptStore.markExported(transcription.sessionID) }) {
                            model.presentNotice(voxUiText("The transcript was exported, but its local delivery receipt could not be saved."))
                        }
                    }
                    is ConfiguredTranscriptExportResult.Failed -> model.presentNotice(result.reason.uiText())
                }
            }
            RecordingRetentionWorker.schedule(
                context = context,
                sessionID = transcription.sessionID,
                policy = recordingPolicyStore.policy(transcription.sessionID),
                transcriptionCompletedAtEpochMillis = transcription.completedAtEpochMillis,
                nowEpochMillis = now,
            )
            if (shouldDeleteRecordingAudio(
                    policy = recordingPolicyStore.policy(transcription.sessionID),
                    transcriptionCompleted = transcription.phase == RecordingTranscriptionPhase.COMPLETED,
                    completedAtEpochMillis = transcription.completedAtEpochMillis,
                    nowEpochMillis = now,
                )
            ) {
                recordingClient.deleteRetainedAudio(transcription.sessionID)
            }
        }
    }
    LaunchedEffect(state.history) {
        state.history.asSequence().filter { it.captureSource == "wear" }.forEach { item ->
            if (reportedWearCaptureStates[item.requestID] == item.state) return@forEach
            val posted = withContext(Dispatchers.IO) {
                PhoneWearBridge.postStatus(
                    context,
                    item.requestID,
                    remotePhaseForCaptureState(item.state),
                    minimumRevision = 0,
                    frontier = Int.MAX_VALUE,
                )
            }
            if (posted) reportedWearCaptureStates[item.requestID] = item.state
        }
    }
    LaunchedEffect(state.presetCollection) {
        state.presetCollection?.let { PhoneWearBridge.publishPresets(context, it) }
    }
    LaunchedEffect(externalCaptureRequest?.correlationID, state.isLoading) {
        val request = externalCaptureRequest ?: return@LaunchedEffect
        if (state.isLoading) return@LaunchedEffect
        PrivacySafeDebugLog.record(
            context,
            PrivacySafeDebugLog.Event.EXTERNAL_CAPTURE_RECEIVED,
            mapOf(
                "source" to request.captureSource,
                "attachments" to request.attachmentUris.size.toString(),
            ),
        )
        model.acceptExternalCapture(
            text = request.text,
            url = request.url,
            presetID = request.presetID,
            correlationID = request.correlationID,
            sourceLabel = request.sourceLabel,
            captureSource = request.captureSource,
            attachmentUris = request.attachmentUris,
        )
        if (request.action == ExternalCaptureAction.RECORD) startRecording()
        consumeExternalCaptureRequest(request.correlationID)
    }
    var retryAfterSelection by remember { mutableStateOf<String?>(null) }
    val treePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
            val retry = retryAfterSelection
            retryAfterSelection = null
            model.saveDestination(uri.toString(), queryTreeDisplayName(context, uri), retry)
        }
    }
    val openTree: (String?) -> Unit = { requestID ->
        retryAfterSelection = requestID
        treePicker.launch(null)
    }

    when {
        state.isLoading -> LoadingScreen()
        state.destination == null -> VaultSetupScreen(state.notice?.localized(), onChooseFolder = { openTree(null) })
        else -> VoxNavigation(
            state,
            model,
            openTree,
            recordingStatus,
            liveSpeechState,
            recordingClient,
            transcriptionClient,
            transcriptionStates,
            startRecording,
            billingManager,
            transcriptionUsage,
        )
    }
}

@Composable
internal fun LoadingScreen() {
    val loadingDescription = voxString("Loading Vox.md")
    Surface(modifier = Modifier.fillMaxSize(), color = Signal.colors.bg) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            SignalWordmark(size = 17)
            Spacer(Modifier.height(20.dp))
            CircularProgressIndicator(
                modifier = Modifier
                    .size(22.dp)
                    .semantics { contentDescription = loadingDescription },
                color = Signal.colors.tint,
                trackColor = Signal.colors.well,
                strokeWidth = 2.dp,
            )
        }
    }
}

/**
 * First run and folder repair. Mirrors the iOS Signal onboarding: the first run is
 * the always-dark Welcome artboard (wordmark, hero line, local-first bullets); a
 * repair (with [notice]) follows the system appearance and leads with the problem.
 * The folder action sits at the end of the scrolling content so it stays reachable
 * at large text sizes.
 */
@Composable
internal fun VaultSetupScreen(notice: String?, onChooseFolder: () -> Unit) {
    val isRepair = notice != null
    if (isRepair) {
        VaultSetupContent(notice, onChooseFolder)
    } else {
        WelcomeSystemBars()
        VoxTheme(darkTheme = true) { VaultSetupContent(null, onChooseFolder) }
    }
}

/** Project license identifier shown under Welcome; kept verbatim like the license name itself. */
private const val WELCOME_LICENSE_LINE = "Open source · AGPL-3.0"

/** The Welcome artboard is always dark, so the system bars use light icons while it shows. */
@Composable
private fun WelcomeSystemBars() {
    val view = androidx.compose.ui.platform.LocalView.current
    if (view.isInEditMode) return
    DisposableEffect(view) {
        val window = (view.context as? Activity)?.window
        val controller = window?.let { androidx.core.view.WindowCompat.getInsetsController(it, view) }
        val lightStatus = controller?.isAppearanceLightStatusBars
        val lightNavigation = controller?.isAppearanceLightNavigationBars
        controller?.isAppearanceLightStatusBars = false
        controller?.isAppearanceLightNavigationBars = false
        onDispose {
            if (lightStatus != null) controller.isAppearanceLightStatusBars = lightStatus
            if (lightNavigation != null) controller.isAppearanceLightNavigationBars = lightNavigation
        }
    }
}

@Composable
private fun VaultSetupContent(notice: String?, onChooseFolder: () -> Unit) {
    val c = Signal.colors
    val welcomeAccent = c.tint
    Surface(modifier = Modifier.fillMaxSize(), color = c.bg) {
        BoxWithConstraints(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = maxHeight)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 24.dp)
                    .padding(top = 16.dp, bottom = 24.dp),
            ) {
                SignalWordmark(extensionColor = if (notice == null) welcomeAccent else c.accentText)
                Spacer(Modifier.height(40.dp))
                Text(
                    voxString("Local drafts → precise Markdown routes"),
                    style = if (notice == null) MaterialTheme.typography.displaySmall else MaterialTheme.typography.headlineLarge,
                    color = c.text,
                    modifier = Modifier.semantics { heading() },
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    voxString("Choose a vault or folder."),
                    style = MaterialTheme.typography.bodyLarge,
                    color = c.muted,
                )
                if (notice != null) {
                    Spacer(Modifier.height(24.dp))
                    SignalBanner(
                        message = notice,
                        status = SignalStatus.WARNING,
                        icon = Icons.Outlined.FolderOpen,
                        liveRegion = true,
                    )
                }
                Spacer(Modifier.height(28.dp))
                SignalCard(
                    modifier = Modifier.fillMaxWidth(),
                    radius = SignalMetrics.GroupRadius,
                    padding = PaddingValues(horizontal = 14.dp, vertical = 14.dp),
                    onClick = onChooseFolder,
                ) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        SignalIconTile(Icons.Outlined.FolderOpen, primary = true, size = 40.dp)
                        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                            Text(voxString("Everything stays on this device."), style = SignalType.rowTitle, color = c.text)
                            Text(
                                voxString("Your captured text is processed locally and is not sent to a cloud AI service."),
                                style = SignalType.caption,
                                color = c.muted,
                            )
                        }
                    }
                }
                Spacer(Modifier.weight(1f).heightIn(min = 32.dp))
                SignalButton(
                    text = voxString("Choose vault or folder"),
                    onClick = onChooseFolder,
                    icon = Icons.Outlined.FolderOpen,
                )
                Spacer(Modifier.height(14.dp))
                Text(
                    WELCOME_LICENSE_LINE,
                    style = SignalType.monoCaption,
                    color = c.muted,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun VoxNavigation(
    state: CaptureUiState,
    model: CaptureViewModel,
    openTree: (String?) -> Unit,
    recordingStatus: RecordingStatus,
    liveSpeechState: LiveSpeechState,
    recordingClient: AudioCaptureClient,
    transcriptionClient: RecordingTranscriptionClient,
    transcriptionStates: Map<String, RecordingTranscriptionState>,
    startRecording: () -> Unit,
    billingManager: PlayBillingManager,
    transcriptionUsage: TranscriptionUsageState,
) {
    val context = LocalContext.current
    val navController = rememberNavController()
    val snackbarHost = remember { SnackbarHostState() }
    val latestState by rememberUpdatedState(state)
    val billingState by billingManager.state.collectAsStateWithLifecycle()
    val expanded = currentVoxWindowWidthClass() == VoxWindowWidthClass.EXPANDED
    var adaptiveHistorySelection by rememberSaveable { mutableStateOf<String?>(null) }
    var adaptivePresetEditorID by rememberSaveable { mutableStateOf<String?>(null) }
    var adaptiveSettingsDestination by rememberSaveable { mutableStateOf<String?>(null) }
    val localizedNotice = state.notice?.localized()
    LaunchedEffect(state.notice, localizedNotice) {
        localizedNotice ?: return@LaunchedEffect
        snackbarHost.showSnackbar(localizedNotice)
        model.clearNotice()
    }

    val backStackEntry by navController.currentBackStackEntryAsState()
    val currentTopLevel = VoxTopLevelDestination.forRoute(backStackEntry?.destination?.route)
    val usesNavigationRail = currentVoxWindowWidthClass() != VoxWindowWidthClass.COMPACT
    val imeVisible = WindowInsets.isImeVisible
    val showsTopLevelChrome = currentTopLevel != null && !recordingStatus.isActive
    val showsNavigationBar = showsTopLevelChrome && !usesNavigationRail && !imeVisible
    val activityBadge = activityAttentionCount(state.history, transcriptionStates.values)
    val selectTopLevel: (VoxTopLevelDestination) -> Unit = { destination ->
        navController.navigate(destination.route) {
            popUpTo(Destination.Capture.route) { saveState = true }
            launchSingleTop = true
            restoreState = true
        }
    }
    Row(modifier = Modifier.fillMaxSize().background(Signal.colors.bg)) {
    if (showsTopLevelChrome && usesNavigationRail) {
        VoxNavigationRail(
            current = currentTopLevel,
            activityBadge = activityBadge,
            onSelect = selectTopLevel,
            startVoiceCapture = {
                selectTopLevel(VoxTopLevelDestination.CAPTURE)
                startRecording()
            },
        )
    }
    Column(modifier = Modifier.weight(1f).fillMaxHeight()) {
    Box(
        modifier = Modifier
            .weight(1f)
            .fillMaxWidth()
            .then(if (showsNavigationBar) Modifier.consumeWindowInsets(WindowInsets.navigationBars) else Modifier),
    ) {
        NavHost(navController = navController, startDestination = Destination.Capture.route) {
            composable(Destination.Capture.route) {
                CaptureScreen(
                    state = latestState,
                    recordingStatus = recordingStatus,
                    recordingTranscription = transcriptionStates[recordingStatus.sessionID],
                    liveSpeech = liveSpeechState.takeIf { it.sessionID == recordingStatus.sessionID },
                    onSubmit = model::submit,
                    onSubmitRecording = model::submitRecording,
                    onDraftChanged = model::updateDraft,
                    onEntryTemplateSelected = model::setEntryTemplateOverride,
                    onRouteChanged = model::setRouteOverride,
                    pinnedPresets = latestState.presetCollection?.let(CapturePresetQuickAccess::alternatePresets).orEmpty(),
                    isPresetRailExpanded = latestState.isPresetRailExpanded,
                    togglePresetRail = model::togglePresetRail,
                    onSelectPreset = model::selectPreset,
                    addDraftAttachment = model::addDraftAttachment,
                    removeDraftAttachment = model::removeDraftAttachment,
                    presentNotice = model::presentNotice,
                    persistLocationUnavailableBehavior = { preset, behavior ->
                        model.savePreset(
                            preset.copy(
                                revision = preset.revision + 1,
                                locationPolicy = preset.locationPolicy.copy(unavailableBehavior = behavior),
                            ),
                        )
                    },
                    consumeAcceptedCapture = model::consumeAcceptedCapture,
                    consumeExternalDraft = model::consumeExternalDraft,
                    openHistory = { selectTopLevel(VoxTopLevelDestination.HISTORY) },
                    openSettings = { selectTopLevel(VoxTopLevelDestination.SETTINGS) },
                    openPresets = { navController.navigate(Destination.Presets.route) },
                    startRecording = startRecording,
                    pauseRecording = recordingClient::pause,
                    resumeRecording = recordingClient::resume,
                    stopRecording = recordingClient::stop,
                    cancelRecording = recordingClient::cancel,
                    dismissRecording = recordingClient::dismissResult,
                    processRecording = { recordingStatus.sessionID?.let(transcriptionClient::process) },
                    cancelRecordingProcessing = { recordingStatus.sessionID?.let(transcriptionClient::cancel) },
                    markRecordingAdded = { recordingStatus.sessionID?.let(transcriptionClient::markAddedToDraft) },
                    exportRecordingAudio = { sessionID ->
                        exportRecordingForCapture(context, recordingClient, sessionID)
                    },
                    frozenRecordingPreset = recordingClient::frozenPreset,
                    setVoiceRecordingResult = model::setVoiceRecordingResult,
                    microphoneBlocked = rememberMicrophoneBlocked(),
                    hasVaultAccess = rememberVaultAccess(latestState.destination),
                    regrantVaultAccess = openTree,
                )
            }
            composable(Destination.History.route) {
                BackHandler(enabled = expanded && adaptiveHistorySelection != null) {
                    adaptiveHistorySelection = null
                    model.clearHistoryDetail()
                }
                val openCaptureDetail: (String) -> Unit = { requestID ->
                    model.loadHistoryDetail(requestID)
                    if (expanded) adaptiveHistorySelection = "capture:$requestID"
                    else navController.navigate("$HISTORY_DETAIL_ROUTE/$requestID")
                }
                val openTranscriptDetail: (String) -> Unit = { sessionID ->
                    if (expanded) adaptiveHistorySelection = "transcript:$sessionID"
                    else navController.navigate("$TRANSCRIPT_DETAIL_ROUTE/$sessionID")
                }
                val historyList: @Composable () -> Unit = {
                    HistoryScreen(
                        items = latestState.history,
                        isBusy = latestState.isSending || latestState.isDeletingHistory,
                        navigateBack = null,
                        refresh = { model.refresh(reconcile = true) },
                        retry = model::retry,
                        repairAccess = openTree,
                        openDetail = openCaptureDetail,
                        transcripts = transcriptionStates.values.toList(),
                        openTranscript = openTranscriptDetail,
                        clearCompleted = {
                            model.deleteCompletedHistory(latestState.history.filter { it.state == CaptureState.COMPLETED }.mapTo(mutableSetOf()) { it.requestID })
                        },
                    )
                }
                if (!expanded) {
                    historyList()
                } else {
                    HingeAwareTwoPane(firstFraction = 0.4f, first = historyList, second = {
                            when {
                                adaptiveHistorySelection?.startsWith("capture:") == true -> HistoryDetailScreen(
                                    detail = latestState.historyDetail,
                                    isLoading = latestState.isLoadingHistoryDetail,
                                    isDeleting = latestState.isDeletingHistory,
                                    navigateBack = {
                                        adaptiveHistorySelection = null
                                        model.clearHistoryDetail()
                                    },
                                    delete = { requestID ->
                                        model.deleteCompletedHistory(setOf(requestID)) {
                                            adaptiveHistorySelection = null
                                            model.clearHistoryDetail()
                                        }
                                    },
                                )
                                adaptiveHistorySelection?.startsWith("transcript:") == true -> {
                                    val sessionID = adaptiveHistorySelection?.substringAfter("transcript:")
                                    TranscriptDetailScreen(
                                        state = sessionID?.let(transcriptionStates::get),
                                        preset = sessionID?.let(recordingClient::frozenPreset),
                                        prepareConfiguredExportAudio = { id, preset ->
                                            configuredTranscriptAudioSource(context, recordingClient, id, preset)
                                        },
                                        navigateBack = { adaptiveHistorySelection = null },
                                        save = transcriptionClient::updateTranscriptDetails,
                                        delete = { id ->
                                            transcriptionClient.clear(id)
                                            adaptiveHistorySelection = null
                                        },
                                        addToDraft = { _, transcript ->
                                            val existing = latestState.draft.text.trimEnd()
                                            model.updateDraft(if (existing.isBlank()) transcript else "$existing\n\n$transcript", latestState.draft.url)
                                            model.presentNotice(voxUiText("Transcript added to the current draft."))
                                            adaptiveHistorySelection = null
                                            navController.popBackStack(Destination.Capture.route, inclusive = false)
                                        },
                                    )
                                }
                                else -> AdaptiveDetailPlaceholder(
                                    title = voxUiText("Select a history item"),
                                    detail = voxUiText("Capture details and private on-device transcripts open here."),
                                )
                            }
                    })
                }
            }
            composable(ACTIVITY_ROUTE) {
                ActivityScreen(
                    items = latestState.history,
                    transcripts = transcriptionStates.values.toList(),
                    isBusy = latestState.isSending || latestState.isDeletingHistory,
                    refresh = { model.refresh(reconcile = true) },
                    retry = model::retry,
                    repairAccess = openTree,
                    openDetail = { requestID ->
                        model.loadHistoryDetail(requestID)
                        navController.navigate("$HISTORY_DETAIL_ROUTE/$requestID")
                    },
                    openTranscript = { sessionID -> navController.navigate("$TRANSCRIPT_DETAIL_ROUTE/$sessionID") },
                    openCapture = { selectTopLevel(VoxTopLevelDestination.CAPTURE) },
                )
            }
            composable("$TRANSCRIPT_DETAIL_ROUTE/{sessionID}") { entry ->
                val sessionID = entry.arguments?.getString("sessionID")
                TranscriptDetailScreen(
                    state = sessionID?.let(transcriptionStates::get),
                    preset = sessionID?.let(recordingClient::frozenPreset),
                    prepareConfiguredExportAudio = { id, preset ->
                        configuredTranscriptAudioSource(context, recordingClient, id, preset)
                    },
                    navigateBack = { navController.popBackStack() },
                    save = transcriptionClient::updateTranscriptDetails,
                    delete = { id ->
                        transcriptionClient.clear(id)
                        navController.popBackStack()
                    },
                    addToDraft = { _, transcript ->
                        val existing = latestState.draft.text.trimEnd()
                        val combined = if (existing.isBlank()) transcript else "$existing\n\n$transcript"
                        model.updateDraft(combined, latestState.draft.url)
                        model.presentNotice(voxUiText("Transcript added to the current draft."))
                        navController.popBackStack(Destination.Capture.route, inclusive = false)
                    },
                )
            }
            composable("$HISTORY_DETAIL_ROUTE/{requestID}") {
                HistoryDetailScreen(
                    detail = latestState.historyDetail,
                    isLoading = latestState.isLoadingHistoryDetail,
                    isDeleting = latestState.isDeletingHistory,
                    navigateBack = {
                        model.clearHistoryDetail()
                        navController.popBackStack()
                    },
                    delete = { requestID ->
                        model.deleteCompletedHistory(setOf(requestID)) {
                            navController.popBackStack()
                        }
                    },
                )
            }
            composable(Destination.Settings.route) {
                val closeAdaptiveSettingsDetail = {
                    adaptiveSettingsDestination = if (adaptiveSettingsDestination?.startsWith("$PRESET_EDITOR_ROUTE/") == true) {
                        Destination.Presets.route
                    } else null
                }
                BackHandler(enabled = expanded && adaptiveSettingsDestination != null) { closeAdaptiveSettingsDetail() }
                val settingsList: @Composable () -> Unit = {
                    SettingsScreen(
                        destination = requireNotNull(latestState.destination),
                        navigateBack = null,
                        chooseFolder = { openTree(null) },
                        openPresets = {
                            if (expanded) adaptiveSettingsDestination = Destination.Presets.route
                            else navController.navigate(Destination.Presets.route)
                        },
                        openCaptureBar = {
                            if (expanded) adaptiveSettingsDestination = Destination.CaptureBar.route
                            else navController.navigate(Destination.CaptureBar.route)
                        },
                        openStats = {
                            if (expanded) adaptiveSettingsDestination = Destination.Stats.route
                            else navController.navigate(Destination.Stats.route)
                        },
                        openModels = {
                            if (expanded) adaptiveSettingsDestination = Destination.Models.route
                            else navController.navigate(Destination.Models.route)
                        },
                        openRecordingQueue = {
                            if (expanded) adaptiveSettingsDestination = Destination.RecordingQueue.route
                            else navController.navigate(Destination.RecordingQueue.route)
                        },
                        openAppLanguage = {
                            if (expanded) adaptiveSettingsDestination = Destination.AppLanguage.route
                            else navController.navigate(Destination.AppLanguage.route)
                        },
                        openDebugLog = {
                            if (expanded) adaptiveSettingsDestination = Destination.DebugLog.route
                            else navController.navigate(Destination.DebugLog.route)
                        },
                        openUpgrade = {
                            if (expanded) adaptiveSettingsDestination = Destination.Upgrade.route
                            else navController.navigate(Destination.Upgrade.route)
                        },
                        billingState = billingState,
                        presets = latestState.presetCollection?.presets.orEmpty(),
                    )
                }
                if (!expanded) {
                    settingsList()
                } else {
                    HingeAwareTwoPane(firstFraction = 0.4f, first = settingsList, second = {
                            when {
                                adaptiveSettingsDestination == Destination.Upgrade.route -> UpgradeScreen(
                                    billingState = billingState,
                                    stats = latestState.activityStats,
                                    transcriptionUsage = transcriptionUsage,
                                    navigateBack = closeAdaptiveSettingsDetail,
                                    purchase = { plan -> context.findActivity()?.let { billingManager.launchPurchase(it, plan) } },
                                    manageSubscriptions = { context.findActivity()?.let(billingManager::manageSubscriptions) },
                                    onTrialReminderPrompted = billingManager::consumeTrialReminderPrompt,
                                    restore = billingManager::restore,
                                )
                                adaptiveSettingsDestination == Destination.Stats.route -> StatsScreen(
                                    stats = latestState.activityStats,
                                    navigateBack = closeAdaptiveSettingsDetail,
                                )
                                adaptiveSettingsDestination == Destination.Models.route -> ModelsScreen(
                                    navigateBack = closeAdaptiveSettingsDetail,
                                )
                                adaptiveSettingsDestination == Destination.RecordingQueue.route -> RecordingQueueScreen(
                                    client = recordingClient,
                                    currentStatus = recordingStatus,
                                    importPreset = latestState.presetCollection?.activePreset,
                                    availablePresets = latestState.presetCollection?.presets.orEmpty()
                                        .filter(md.vox.android.capturedomain.CapturePreset::isEnabled),
                                    navigateBack = closeAdaptiveSettingsDetail,
                                    resume = recordingClient::resume,
                                    finish = recordingClient::stop,
                                    cancel = recordingClient::cancel,
                                    addToDraft = { _, transcript ->
                                        val existing = latestState.draft.text.trimEnd()
                                        model.updateDraft(if (existing.isBlank()) transcript else "$existing\n\n$transcript", latestState.draft.url)
                                        model.presentNotice(voxUiText("Transcript added to the current draft."))
                                        adaptiveSettingsDestination = null
                                        navController.popBackStack(Destination.Capture.route, inclusive = false)
                                    },
                                )
                                adaptiveSettingsDestination == Destination.AppLanguage.route -> AppLanguageSettingsScreen(
                                    navigateBack = closeAdaptiveSettingsDetail,
                                )
                                adaptiveSettingsDestination == Destination.DebugLog.route -> DebugLogScreen(
                                    navigateBack = closeAdaptiveSettingsDetail,
                                )
                                adaptiveSettingsDestination == Destination.CaptureBar.route -> CaptureBarSettingsScreen(
                                    configuration = latestState.captureBar,
                                    isBusy = latestState.isSavingConfiguration,
                                    navigateBack = closeAdaptiveSettingsDetail,
                                    setVisible = model::setCaptureBarActionVisible,
                                    move = model::moveCaptureBarAction,
                                    setTwentyFourHour = model::setTwentyFourHourTimestamps,
                                    setRailSide = model::setRailSide,
                                    setVoiceConfirmation = model::setConfirmsVoiceNotesBeforeAdding,
                                    setVoiceRecordingResult = model::setVoiceRecordingResult,
                                    reset = model::resetCaptureBar,
                                )
                                adaptiveSettingsDestination == Destination.Presets.route -> CapturePresetsScreen(
                                    collection = latestState.presetCollection,
                                    entryTemplates = latestState.entryTemplates,
                                    isBusy = latestState.isSavingConfiguration,
                                    navigateBack = closeAdaptiveSettingsDetail,
                                    selectPreset = model::selectPreset,
                                    editPreset = { adaptiveSettingsDestination = "$PRESET_EDITOR_ROUTE/$it" },
                                    createPreset = { adaptiveSettingsDestination = "$PRESET_EDITOR_ROUTE/new" },
                                    saveEntryTemplate = { model.saveEntryTemplate(it) },
                                    deleteEntryTemplate = { model.deleteEntryTemplate(it) },
                                )
                                adaptiveSettingsDestination?.startsWith("$PRESET_EDITOR_ROUTE/") == true -> {
                                    val presetID = adaptiveSettingsDestination?.substringAfter("$PRESET_EDITOR_ROUTE/") ?: "new"
                                    val preset = latestState.presetCollection?.presets?.firstOrNull { it.id == presetID }
                                    CapturePresetEditorScreen(
                                        preset = preset,
                                        entryTemplates = latestState.entryTemplates,
                                        isBusy = latestState.isSavingConfiguration,
                                        navigateBack = closeAdaptiveSettingsDetail,
                                        save = { draft -> model.savePreset(draft) { adaptiveSettingsDestination = Destination.Presets.route } },
                                        delete = preset?.takeUnless { it.id == DEFAULT_CAPTURE_PRESET_ID }?.let { existing ->
                                            { model.deletePreset(existing.id) { adaptiveSettingsDestination = Destination.Presets.route } }
                                        },
                                    )
                                }
                                else -> AdaptiveDetailPlaceholder(
                                    title = voxUiText("Choose a setting"),
                                    detail = voxUiText("Settings and supporting tools open here while Quick Capture stays one step away."),
                                )
                            }
                    })
                }
            }
            composable(Destination.Upgrade.route) {
                val activity = context.findActivity()
                UpgradeScreen(
                    billingState = billingState,
                    stats = latestState.activityStats,
                    transcriptionUsage = transcriptionUsage,
                    navigateBack = { navController.popBackStack() },
                    purchase = { plan -> activity?.let { billingManager.launchPurchase(it, plan) } },
                    manageSubscriptions = { activity?.let(billingManager::manageSubscriptions) },
                    onTrialReminderPrompted = billingManager::consumeTrialReminderPrompt,
                    restore = billingManager::restore,
                )
            }
            composable(Destination.Stats.route) {
                StatsScreen(
                    stats = latestState.activityStats,
                    navigateBack = { navController.popBackStack() },
                )
            }
            composable(Destination.Models.route) {
                ModelsScreen(navigateBack = { navController.popBackStack() })
            }
            composable(Destination.RecordingQueue.route) {
                RecordingQueueScreen(
                    client = recordingClient,
                    currentStatus = recordingStatus,
                    importPreset = latestState.presetCollection?.activePreset,
                    availablePresets = latestState.presetCollection?.presets.orEmpty()
                        .filter(md.vox.android.capturedomain.CapturePreset::isEnabled),
                    navigateBack = { navController.popBackStack() },
                    resume = recordingClient::resume,
                    finish = recordingClient::stop,
                    cancel = recordingClient::cancel,
                    addToDraft = { _, transcript ->
                        val existing = latestState.draft.text.trimEnd()
                        val combined = if (existing.isBlank()) transcript else "$existing\n\n$transcript"
                        model.updateDraft(combined, latestState.draft.url)
                        model.presentNotice(voxUiText("Transcript added to the current draft."))
                        navController.popBackStack(Destination.Capture.route, inclusive = false)
                    },
                )
            }
            composable(Destination.AppLanguage.route) {
                AppLanguageSettingsScreen(navigateBack = { navController.popBackStack() })
            }
            composable(Destination.DebugLog.route) {
                DebugLogScreen(navigateBack = { navController.popBackStack() })
            }
            composable(Destination.CaptureBar.route) {
                CaptureBarSettingsScreen(
                    configuration = latestState.captureBar,
                    isBusy = latestState.isSavingConfiguration,
                    navigateBack = { navController.popBackStack() },
                    setVisible = model::setCaptureBarActionVisible,
                    move = model::moveCaptureBarAction,
                    setTwentyFourHour = model::setTwentyFourHourTimestamps,
                                    setRailSide = model::setRailSide,
                    setVoiceConfirmation = model::setConfirmsVoiceNotesBeforeAdding,
                    setVoiceRecordingResult = model::setVoiceRecordingResult,
                    reset = model::resetCaptureBar,
                )
            }
            composable(Destination.Presets.route) {
                BackHandler(enabled = expanded && adaptivePresetEditorID != null) { adaptivePresetEditorID = null }
                val presetsList: @Composable () -> Unit = {
                    CapturePresetsScreen(
                        collection = latestState.presetCollection,
                        entryTemplates = latestState.entryTemplates,
                        isBusy = latestState.isSavingConfiguration,
                        navigateBack = { navController.popBackStack() },
                        selectPreset = model::selectPreset,
                        editPreset = { presetID ->
                            if (expanded) adaptivePresetEditorID = presetID
                            else navController.navigate("$PRESET_EDITOR_ROUTE/$presetID")
                        },
                        createPreset = {
                            if (expanded) adaptivePresetEditorID = "new"
                            else navController.navigate("$PRESET_EDITOR_ROUTE/new")
                        },
                        saveEntryTemplate = { model.saveEntryTemplate(it) },
                        deleteEntryTemplate = { model.deleteEntryTemplate(it) },
                    )
                }
                if (!expanded) {
                    presetsList()
                } else {
                    HingeAwareTwoPane(firstFraction = 0.4f, first = presetsList, second = {
                            val presetID = adaptivePresetEditorID
                            if (presetID == null) {
                                AdaptiveDetailPlaceholder(
                                    title = voxUiText("Select a capture preset"),
                                    detail = voxUiText("Edit routing, formatting, metadata, voice, and local processing here."),
                                )
                            } else {
                                val preset = latestState.presetCollection?.presets?.firstOrNull { it.id == presetID }
                                CapturePresetEditorScreen(
                                    preset = preset,
                                    entryTemplates = latestState.entryTemplates,
                                    isBusy = latestState.isSavingConfiguration,
                                    navigateBack = { adaptivePresetEditorID = null },
                                    save = { draft -> model.savePreset(draft) { adaptivePresetEditorID = null } },
                                    delete = preset?.takeUnless { it.id == DEFAULT_CAPTURE_PRESET_ID }?.let { existing ->
                                        { model.deletePreset(existing.id) { adaptivePresetEditorID = null } }
                                    },
                                )
                            }
                    })
                }
            }
            composable("$PRESET_EDITOR_ROUTE/{presetID}") { entry ->
                val presetID = entry.arguments?.getString("presetID") ?: "new"
                val preset = latestState.presetCollection?.presets?.firstOrNull { it.id == presetID }
                CapturePresetEditorScreen(
                    preset = preset,
                    entryTemplates = latestState.entryTemplates,
                    isBusy = latestState.isSavingConfiguration,
                    navigateBack = { navController.popBackStack() },
                    save = { draft -> model.savePreset(draft) { navController.popBackStack() } },
                    delete = preset?.takeUnless { it.id == DEFAULT_CAPTURE_PRESET_ID }?.let { existing ->
                        { model.deletePreset(existing.id) { navController.popBackStack() } }
                    },
                )
            }
        }
        SnackbarHost(
            hostState = snackbarHost,
            modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(16.dp),
        )
    }
    if (showsNavigationBar) {
        VoxNavigationBar(
            current = currentTopLevel,
            activityBadge = activityBadge,
            onSelect = selectTopLevel,
        )
    }
    }
    }
}

internal fun queryTreeDisplayName(context: android.content.Context, tree: Uri): String = runCatching {
    val document = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
    context.contentResolver.query(
        document,
        arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
}.getOrNull()?.takeIf { it.isNotBlank() } ?: "Markdown folder"

internal fun queryDocumentDisplayName(context: android.content.Context, document: Uri): String = runCatching {
    context.contentResolver.query(
        document,
        arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
}.getOrNull()?.takeIf { it.isNotBlank() } ?: "Markdown template"

internal fun Context.findActivity(): Activity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return current as? Activity
}
