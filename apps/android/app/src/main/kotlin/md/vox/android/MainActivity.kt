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
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.material.icons.outlined.ChevronRight
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

private enum class Destination(val route: String) {
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

private const val PRESET_EDITOR_ROUTE = "preset-editor"
private const val HISTORY_DETAIL_ROUTE = "history-detail"
private const val TRANSCRIPT_DETAIL_ROUTE = "transcript-detail"
private const val DEFAULT_CAPTURE_PRESET_ID = "33333333-3333-4333-8333-333333333333"

@Composable
private fun VoxApp(
    model: CaptureViewModel,
    billingManager: PlayBillingManager,
    externalCaptureRequest: ExternalCaptureRequest?,
    consumeExternalCaptureRequest: (String) -> Unit,
) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
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
    val microphonePermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        val preset = pendingRecordingPreset
        pendingRecordingPreset = null
        if (grants[Manifest.permission.RECORD_AUDIO] == true && preset != null) recordingClient.start(preset)
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
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Box(contentAlignment = Alignment.Center) {
            CircularProgressIndicator(
                modifier = Modifier
                    .size(32.dp)
                    .semantics { contentDescription = loadingDescription },
                strokeWidth = 3.dp,
            )
        }
    }
}

@Composable
internal fun VaultSetupScreen(notice: String?, onChooseFolder: () -> Unit) {
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .navigationBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp, vertical = 32.dp),
            verticalArrangement = Arrangement.Center,
        ) {
            Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceVariant) {
                Box(modifier = Modifier.size(64.dp), contentAlignment = Alignment.Center) {
                    Icon(Icons.Outlined.FolderOpen, contentDescription = null, modifier = Modifier.size(32.dp))
                }
            }
            Spacer(Modifier.height(24.dp))
            Text(voxString("Local drafts → precise Markdown routes"), style = MaterialTheme.typography.headlineLarge)
            Spacer(Modifier.height(12.dp))
            Text(voxString("Choose a vault or folder."),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(24.dp))
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                shape = RoundedCornerShape(16.dp),
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(voxString("Everything stays on this device."), style = MaterialTheme.typography.titleMedium)
                    Text(voxString("Your captured text is processed locally and is not sent to a cloud AI service."),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (notice != null) {
                Spacer(Modifier.height(16.dp))
                Text(
                    notice,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Spacer(Modifier.height(32.dp))
            Button(
                onClick = onChooseFolder,
                modifier = Modifier.fillMaxWidth().height(48.dp),
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(Icons.Outlined.FolderOpen, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text(voxString("Choose vault or folder"))
            }
        }
    }
}

@Composable
private fun VoxNavigation(
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

    Box(modifier = Modifier.fillMaxSize()) {
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
                    openHistory = { navController.navigate(Destination.History.route) },
                    openSettings = { navController.navigate(Destination.Settings.route) },
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
                        navigateBack = { navController.popBackStack() },
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
                    Row(Modifier.fillMaxSize()) {
                        Box(Modifier.weight(0.43f)) { historyList() }
                        VerticalDivider()
                        Box(Modifier.weight(0.57f)) {
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
                        }
                    }
                }
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
                        navigateBack = { navController.popBackStack() },
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
                    )
                }
                if (!expanded) {
                    settingsList()
                } else {
                    Row(Modifier.fillMaxSize()) {
                        Box(Modifier.weight(0.4f)) { settingsList() }
                        VerticalDivider()
                        Box(Modifier.weight(0.6f)) {
                            when {
                                adaptiveSettingsDestination == Destination.Upgrade.route -> UpgradeScreen(
                                    billingState = billingState,
                                    stats = latestState.activityStats,
                                    transcriptionUsage = transcriptionUsage,
                                    navigateBack = closeAdaptiveSettingsDetail,
                                    purchase = { context.findActivity()?.let(billingManager::launchPurchase) },
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
                        }
                    }
                }
            }
            composable(Destination.Upgrade.route) {
                val activity = context.findActivity()
                UpgradeScreen(
                    billingState = billingState,
                    stats = latestState.activityStats,
                    transcriptionUsage = transcriptionUsage,
                    navigateBack = { navController.popBackStack() },
                    purchase = { activity?.let(billingManager::launchPurchase) },
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
                    Row(Modifier.fillMaxSize()) {
                        Box(Modifier.weight(0.4f)) { presetsList() }
                        VerticalDivider()
                        Box(Modifier.weight(0.6f)) {
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
                        }
                    }
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
}

private data class PendingLocationSubmission(
    val text: String,
    val url: String?,
    val precision: CaptureLocationPrecision,
    val policy: CaptureLocationUnavailableBehavior,
    val requiresLabels: Boolean,
    val labelLookupClass: CaptureLocationLabelLookupClass,
    val labelConsentVersion: Int?,
    val originRecordingID: String? = null,
    val audioContentUri: String? = null,
    val audioDisplayName: String? = null,
    val frozenPreset: CapturePreset? = null,
)

private data class PendingLocationDecision(
    val submission: PendingLocationSubmission,
    val outcome: CaptureLocationOutcome.Unavailable,
)

@Composable
internal fun CaptureScreen(
    state: CaptureUiState,
    recordingStatus: RecordingStatus,
    recordingTranscription: RecordingTranscriptionState?,
    liveSpeech: LiveSpeechState?,
    onSubmit: (String, String?, CaptureLocationOutcome) -> Unit,
    onSubmitRecording: (String, String?, String, String?, String?, CapturePreset?, CaptureLocationOutcome) -> Unit,
    onDraftChanged: (String, String?) -> Unit,
    onEntryTemplateSelected: (String?) -> Unit,
    pinnedPresets: List<CapturePreset> = emptyList(),
    isPresetRailExpanded: Boolean = false,
    togglePresetRail: () -> Unit = {},
    onSelectPreset: (String) -> Unit = {},
    addDraftAttachment: (String, String?, String?, Boolean) -> Unit,
    removeDraftAttachment: (String) -> Unit,
    presentNotice: (VoxUiText) -> Unit,
    persistLocationUnavailableBehavior: (CapturePreset, CaptureLocationUnavailableBehavior) -> Unit,
    consumeAcceptedCapture: () -> Unit,
    consumeExternalDraft: () -> Unit,
    openHistory: () -> Unit,
    openSettings: () -> Unit,
    openPresets: () -> Unit,
    startRecording: () -> Unit,
    pauseRecording: () -> Unit,
    resumeRecording: () -> Unit,
    stopRecording: () -> Unit,
    cancelRecording: () -> Unit,
    dismissRecording: () -> Unit,
    processRecording: () -> Unit,
    cancelRecordingProcessing: () -> Unit,
    markRecordingAdded: () -> Unit,
    exportRecordingAudio: suspend (String) -> String?,
    frozenRecordingPreset: (String) -> CapturePreset?,
    requestEditorFocus: Boolean = true,
    initialShowsVoiceCaptureDetails: Boolean = false,
) {
    var editorValue by rememberSaveable(stateSaver = TextFieldValue.Saver) {
        mutableStateOf(TextFieldValue(state.draft.text, TextRange(state.draft.text.length)))
    }
    var capturedURL by rememberSaveable { mutableStateOf(state.draft.url) }
    var showsLinkDialog by rememberSaveable { mutableStateOf(false) }
    var showsDueDateDialog by rememberSaveable { mutableStateOf(false) }
    var showsMediaDialog by rememberSaveable { mutableStateOf(false) }
    var showsSketchDialog by rememberSaveable { mutableStateOf(false) }
    var showsVoiceCaptureDetails by rememberSaveable { mutableStateOf(initialShowsVoiceCaptureDetails) }
    var isResolvingPresetLocation by rememberSaveable { mutableStateOf(false) }
    var pendingLocationSubmission by remember { mutableStateOf<PendingLocationSubmission?>(null) }
    var locationDecision by remember { mutableStateOf<PendingLocationDecision?>(null) }
    var pendingCameraPath by rememberSaveable { mutableStateOf<String?>(null) }
    val undoStack = remember { mutableStateListOf<TextFieldValue>() }
    val editor = remember { CaptureComposerTextEditor() }
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current
    val context = LocalContext.current
    val activity = remember(context) { context.findActivity() }
    val coroutineScope = rememberCoroutineScope()
    val textRecognition = remember(context) { LocalTextRecognition(context) }
    val locationResolver = remember(context) { CurrentLocationResolver(context) }
    val clipboard = remember(context) { context.getSystemService(ClipboardManager::class.java) }
    fun attach(
        contentUri: String,
        displayName: String? = null,
        mediaType: String? = null,
        includeInMarkdown: Boolean = true,
    ) = addDraftAttachment(contentUri, displayName, mediaType, includeInMarkdown)
    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        uris.forEach { uri -> attach(uri.toString(), mediaType = context.contentResolver.getType(uri)) }
    }

    fun rememberUndo(value: TextFieldValue) {
        if (undoStack.lastOrNull() == value) return
        if (undoStack.size >= 100) undoStack.removeAt(0)
        undoStack += value
    }

    fun commitEditorValue(next: TextFieldValue, registerUndo: Boolean = true) {
        if (next.text.length > 65_536) return
        if (registerUndo && next.text != editorValue.text) rememberUndo(editorValue)
        editorValue = next
        onDraftChanged(next.text, capturedURL)
    }

    fun applyCommand(command: CaptureComposerCommand) {
        val result = editor.apply(
            command,
            editorValue.text,
            md.vox.android.capturedomain.CaptureTextSelection(editorValue.selection.start, editorValue.selection.end),
        )
        commitEditorValue(
            TextFieldValue(result.text, TextRange(result.selection.start, result.selection.end)),
            registerUndo = result.text != editorValue.text,
        )
        focusRequester.requestFocus()
        keyboardController?.show()
    }

    val photoPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(32)) { uris ->
        uris.forEach { uri -> attach(uri.toString(), mediaType = context.contentResolver.getType(uri)) }
    }
    val screenshotPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(32)) { uris ->
        val screenshots = uris.filter { isScreenshotUri(context, it) }
        screenshots.forEach { uri -> attach(uri.toString(), mediaType = context.contentResolver.getType(uri)) }
        val rejected = uris.size - screenshots.size
        if (rejected > 0) {
            presentNotice(if (screenshots.isEmpty()) {
                voxUiText("No screenshots were added. Choose images from a Screenshots album.")
            } else if (rejected == 1) {
                voxUiText("1 non-screenshot image was skipped.")
            } else {
                voxUiText("%lld non-screenshot images were skipped.", rejected.toLong())
            })
        }
    }
    val cameraLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { captured ->
        val file = pendingCameraPath?.let(::File)
        pendingCameraPath = null
        if (captured && file != null) {
            attach(captureImportUri(context, file).toString(), "Camera photo.jpg", "image/jpeg")
        } else {
            file?.delete()
        }
    }
    val documentScannerLauncher = rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
        if (result.resultCode != Activity.RESULT_OK) return@rememberLauncherForActivityResult
        val scan = GmsDocumentScanningResult.fromActivityResultIntent(result.data)
        val pageUris = scan?.pages.orEmpty().map { it.imageUri }
        val assets = documentScanAssetSpecs(
            pageUris = pageUris.map(Uri::toString),
            pdfUri = scan?.pdf?.uri?.toString(),
        )
        if (assets.isEmpty()) {
            presentNotice(voxUiText("The scanner did not return any pages or a PDF."))
            return@rememberLauncherForActivityResult
        }
        assets.forEach { asset ->
            attach(asset.sourceUri, asset.displayName, asset.mediaType, asset.includeInMarkdown)
        }
        if (pageUris.isNotEmpty()) coroutineScope.launch {
            val recognized = runCatching { textRecognition.recognize(pageUris) }.getOrDefault("")
            val ocrAsset = runCatching { createScanOcrAsset(context, recognized) }.getOrNull()
            if (ocrAsset == null) {
                presentNotice(voxUiText("The scan sources are attached, but no readable text was found."))
            } else {
                attach(ocrAsset.uri.toString(), ocrAsset.displayName, ocrAsset.mediaType, ocrAsset.includeInMarkdown)
                applyCommand(CaptureComposerCommand.ReplaceSelection(recognized))
            }
        }
    }
    val ocrPicker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia(20)) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        uris.forEach { uri -> attach(uri.toString(), mediaType = context.contentResolver.getType(uri)) }
        coroutineScope.launch {
            val recognized = runCatching { textRecognition.recognize(uris) }.getOrDefault("")
            if (recognized.isBlank()) {
                presentNotice(voxUiText("The original images are attached, but no readable text was found."))
            } else {
                applyCommand(CaptureComposerCommand.ReplaceSelection(recognized))
            }
        }
    }

    fun requestCurrentLocation() {
        coroutineScope.launch {
            when (val result = locationResolver.resolve()) {
                is CurrentLocationResult.Available -> {
                    applyCommand(
                        CaptureComposerCommand.ReplaceSelection(
                            CaptureInsertionFormatter.googleMapsLink(result.latitude, result.longitude),
                        ),
                    )
                }
                CurrentLocationResult.PermissionDenied,
                CurrentLocationResult.Restricted,
                -> presentNotice(voxUiText("Location permission is required to add your current location."))
                CurrentLocationResult.ReducedAccuracy -> presentNotice(voxUiText("Precise location is required for this action."))
                CurrentLocationResult.Timeout -> presentNotice(voxUiText("Location timed out. Try again when location services have a fix."))
                CurrentLocationResult.Unavailable -> presentNotice(voxUiText("Current location is unavailable. Try again when location services have a fix."))
            }
        }
    }
    val locationPermissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        if (grants.values.any { it }) requestCurrentLocation()
        else presentNotice(voxUiText("Location permission was not granted."))
    }

    fun deliverPending(pending: PendingLocationSubmission, outcome: CaptureLocationOutcome) {
        val originRecordingID = pending.originRecordingID
        if (originRecordingID == null) {
            onSubmit(pending.text, pending.url, outcome)
        } else {
            onSubmitRecording(
                pending.text,
                pending.url,
                originRecordingID,
                pending.audioContentUri,
                pending.audioDisplayName,
                pending.frozenPreset,
                outcome,
            )
        }
    }

    fun submitWithUnavailableLocation(
        pending: PendingLocationSubmission,
        reason: CaptureLocationUnavailableReason,
        attemptedAtEpochMillis: Long = System.currentTimeMillis(),
    ) {
        isResolvingPresetLocation = false
        val labelObservation = if (pending.requiresLabels && pending.labelLookupClass != CaptureLocationLabelLookupClass.NONE) {
            CaptureLocationLabelObservation(
                requested = true,
                lookupClass = pending.labelLookupClass,
                consentVersion = pending.labelConsentVersion,
                outcome = CaptureLocationLabelOutcome.UNAVAILABLE,
            )
        } else {
            CaptureLocationLabelObservation.NOT_REQUESTED
        }
        val outcome = CaptureLocationOutcome.Unavailable(reason, attemptedAtEpochMillis, labelObservation)
        when (pending.policy) {
            CaptureLocationUnavailableBehavior.SEND_WITHOUT_LOCATION -> deliverPending(pending, outcome)
            CaptureLocationUnavailableBehavior.ASK -> locationDecision = PendingLocationDecision(pending, outcome)
            CaptureLocationUnavailableBehavior.CANCEL -> presentNotice(voxUiText("Capture cancelled because location was unavailable. Your draft is preserved."))
        }
    }

    fun resolvePresetLocation(pending: PendingLocationSubmission) {
        coroutineScope.launch {
            isResolvingPresetLocation = true
            when (val result = locationResolver.resolve(exactRequired = pending.precision == CaptureLocationPrecision.EXACT)) {
                is CurrentLocationResult.Available -> {
                    val city = pending.precision == CaptureLocationPrecision.CITY
                    val latitude = if (city) (result.latitude * 100.0).roundToLong() / 100.0 else result.latitude
                    val longitude = if (city) (result.longitude * 100.0).roundToLong() / 100.0 else result.longitude
                    val accuracyMillimeters = result.accuracyMeters
                        .takeIf { it.isFinite() && it >= 0f }
                        ?.let { (it.toDouble() * 1_000.0).roundToLong() }
                    val frozenLabel = when (pending.labelLookupClass) {
                        CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK -> if (
                            pending.requiresLabels &&
                            pending.labelConsentVersion == CURRENT_LOCATION_LABEL_CONSENT_VERSION
                        ) {
                            locationResolver.resolveLabel(latitude, longitude)?.let { label ->
                                CaptureLocationLabel(
                                    place = label.place.takeUnless { city },
                                    city = label.city,
                                    region = label.region,
                                    country = label.country,
                                ).takeUnless(CaptureLocationLabel::isEmpty)
                            }
                        } else null
                        // No vetted offline database ships in this build. Preserve the
                        // frozen class as unavailable without switching to the system geocoder.
                        CaptureLocationLabelLookupClass.OFFLINE,
                        CaptureLocationLabelLookupClass.NONE,
                        -> null
                    }
                    val labelWasRequested = pending.requiresLabels &&
                        pending.labelLookupClass != CaptureLocationLabelLookupClass.NONE
                    val labelObservation = if (labelWasRequested) {
                        CaptureLocationLabelObservation(
                            requested = true,
                            lookupClass = pending.labelLookupClass,
                            consentVersion = pending.labelConsentVersion,
                            outcome = if (frozenLabel == null) {
                                CaptureLocationLabelOutcome.UNAVAILABLE
                            } else {
                                CaptureLocationLabelOutcome.FROZEN
                            },
                        )
                    } else {
                        CaptureLocationLabelObservation.NOT_REQUESTED
                    }
                    isResolvingPresetLocation = false
                    deliverPending(
                        pending,
                        CaptureLocationOutcome.Available(
                            CaptureLocationSnapshot(
                                latitudeE6 = (latitude * 1_000_000.0).roundToLong(),
                                longitudeE6 = (longitude * 1_000_000.0).roundToLong(),
                                accuracyMillimeters = accuracyMillimeters,
                                capturedAtEpochMillis = System.currentTimeMillis(),
                                precision = pending.precision,
                                source = "app",
                                label = frozenLabel,
                            ),
                            labelObservation,
                        ),
                    )
                }
                CurrentLocationResult.PermissionDenied -> submitWithUnavailableLocation(
                    pending,
                    CaptureLocationUnavailableReason.PERMISSION_DENIED,
                )
                CurrentLocationResult.Restricted -> submitWithUnavailableLocation(
                    pending,
                    CaptureLocationUnavailableReason.RESTRICTED,
                )
                CurrentLocationResult.ReducedAccuracy -> submitWithUnavailableLocation(
                    pending,
                    CaptureLocationUnavailableReason.REDUCED_ACCURACY,
                )
                CurrentLocationResult.Timeout -> submitWithUnavailableLocation(
                    pending,
                    CaptureLocationUnavailableReason.TIMEOUT,
                )
                CurrentLocationResult.Unavailable -> submitWithUnavailableLocation(
                    pending,
                    CaptureLocationUnavailableReason.UNAVAILABLE,
                )
            }
        }
    }
    val presetLocationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        val pending = pendingLocationSubmission ?: return@rememberLauncherForActivityResult
        pendingLocationSubmission = null
        if (grants.values.any { it }) {
            resolvePresetLocation(pending)
        } else {
            submitWithUnavailableLocation(pending, CaptureLocationUnavailableReason.PERMISSION_DENIED)
        }
    }

    fun submitCapture(
        text: String,
        url: String?,
        originRecordingID: String? = null,
        audioContentUri: String? = null,
        audioDisplayName: String? = null,
        frozenPreset: CapturePreset? = null,
    ) {
        val policy = (frozenPreset ?: state.presetCollection?.activePreset)?.locationPolicy
        if (policy?.isEnabled != true) {
            deliverPending(
                PendingLocationSubmission(
                    text,
                    url,
                    CaptureLocationPrecision.EXACT,
                    CaptureLocationUnavailableBehavior.SEND_WITHOUT_LOCATION,
                    false,
                    CaptureLocationLabelLookupClass.NONE,
                    null,
                    originRecordingID,
                    audioContentUri,
                    audioDisplayName,
                    frozenPreset,
                ),
                CaptureLocationOutcome.NotRequested,
            )
            return
        }
        val pending = PendingLocationSubmission(
            text,
            url,
            policy.precision,
            policy.unavailableBehavior,
            policy.requiresLabels,
            policy.labelLookupClass,
            policy.labelConsentVersion,
            originRecordingID,
            audioContentUri,
            audioDisplayName,
            frozenPreset,
        )
        val fine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (fine || coarse) {
            resolvePresetLocation(pending)
        } else {
            pendingLocationSubmission = pending
            presetLocationPermissionLauncher.launch(
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION),
            )
        }
    }

    fun startCameraCapture() {
        val file = runCatching {
            createCaptureImportFile(context, "${UUID.randomUUID().toString().lowercase(Locale.ROOT)}-camera.jpg")
        }.getOrElse {
            presentNotice(voxUiText("A camera file could not be prepared."))
            return
        }
        pendingCameraPath = file.absolutePath
        cameraLauncher.launch(captureImportUri(context, file))
    }

    fun startDocumentScan() {
        val host = activity
        if (host == null) {
            presentNotice(voxUiText("Document scanning is unavailable in this window."))
            return
        }
        val options = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(true)
            .setPageLimit(20)
            .setResultFormats(RESULT_FORMAT_JPEG, RESULT_FORMAT_PDF)
            .setScannerMode(SCANNER_MODE_FULL)
            .build()
        GmsDocumentScanning.getClient(options).getStartScanIntent(host)
            .addOnSuccessListener { sender ->
                documentScannerLauncher.launch(IntentSenderRequest.Builder(sender).build())
            }
            .addOnFailureListener {
                presentNotice(voxUiText("The on-device document scanner is unavailable. You can still attach a PDF from Files."))
            }
    }

    fun addCurrentLocation() {
        val fine = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (fine || coarse) requestCurrentLocation()
        else locationPermissionLauncher.launch(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION))
    }

    LaunchedEffect(requestEditorFocus) {
        if (requestEditorFocus) {
            delay(180)
            focusRequester.requestFocus()
            keyboardController?.show()
        }
    }
    LaunchedEffect(state.acceptedRequestID) {
        if (state.acceptedRequestID != null) {
            editorValue = TextFieldValue("")
            capturedURL = null
            undoStack.clear()
            consumeAcceptedCapture()
        }
    }
    LaunchedEffect(state.pendingExternalDraftID) {
        if (state.pendingExternalDraftID != null) {
            editorValue = TextFieldValue(state.draft.text, TextRange(state.draft.text.length))
            capturedURL = state.draft.url
            undoStack.clear()
            consumeExternalDraft()
        }
    }

    if (showsLinkDialog) {
        LinkDialog(
            initialValue = capturedURL.orEmpty(),
            onDismiss = {
                showsLinkDialog = false
                focusRequester.requestFocus()
            },
            onSave = {
                capturedURL = it
                onDraftChanged(editorValue.text, it)
                showsLinkDialog = false
                focusRequester.requestFocus()
            },
        )
    }
    if (showsDueDateDialog) {
        DueDateDialog(
            onDismiss = { showsDueDateDialog = false },
            onInsert = { value ->
                applyCommand(CaptureComposerCommand.ReplaceSelection(value))
                showsDueDateDialog = false
            },
        )
    }
    if (showsMediaDialog) {
        AlertDialog(
            onDismissRequest = { showsMediaDialog = false },
            title = { Text(voxString("Add Media")) },
            text = { Text(voxString("Choose photos, filter a selection to screenshots, or take a new photo.")) },
            confirmButton = {
                Column(horizontalAlignment = Alignment.End) {
                    TextButton(onClick = {
                        showsMediaDialog = false
                        photoPicker.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }) { Text(voxString("Photo Library")) }
                    TextButton(onClick = {
                        showsMediaDialog = false
                        screenshotPicker.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                    }) { Text(voxString("Screenshots")) }
                    TextButton(onClick = {
                        showsMediaDialog = false
                        startCameraCapture()
                    }) { Text(voxString("Camera")) }
                }
            },
            dismissButton = {
                TextButton(onClick = { showsMediaDialog = false }) { Text(voxString("Cancel")) }
            },
        )
    }
    if (showsSketchDialog) {
        SketchDialog(
            onDismiss = { showsSketchDialog = false },
            onSave = { assets ->
                assets.forEach { asset ->
                    attach(asset.uri.toString(), asset.displayName, asset.mediaType, asset.includeInMarkdown)
                }
                showsSketchDialog = false
            },
            onFailure = {
                showsSketchDialog = false
                presentNotice(voxUiText("The sketch could not be saved."))
            },
        )
    }
    if (locationDecision != null) {
        val decision = requireNotNull(locationDecision)
        LocationUnavailableDialog(
            reason = decision.outcome.reason,
            canPersistPreference = (decision.submission.frozenPreset ?: state.presetCollection?.activePreset) != null,
            retry = {
                locationDecision = null
                resolvePresetLocation(decision.submission)
            },
            sendWithoutLocation = {
                locationDecision = null
                deliverPending(decision.submission, decision.outcome)
            },
            alwaysSendWithoutLocation = {
                locationDecision = null
                (decision.submission.frozenPreset ?: state.presetCollection?.activePreset)?.let { preset ->
                    persistLocationUnavailableBehavior(preset, CaptureLocationUnavailableBehavior.SEND_WITHOUT_LOCATION)
                }
                deliverPending(decision.submission, decision.outcome)
            },
            cancel = { locationDecision = null },
        )
    }

    fun addRecordingTranscriptToDraft(transcript: String) {
        val existing = editorValue.text.trimEnd()
        val combined = if (existing.isBlank()) transcript else "$existing\n\n$transcript"
        commitEditorValue(TextFieldValue(combined, TextRange(combined.length)))
        markRecordingAdded()
        presentNotice(voxUiText("Transcript added to the current draft."))
    }

    fun sendRecordingWithPreset(transcript: String) {
        coroutineScope.launch {
            val sessionID = recordingStatus.sessionID
            if (sessionID == null) {
                presentNotice(voxUiText("The recording is no longer available."))
                return@launch
            }
            val preset = frozenRecordingPreset(sessionID)
                ?: state.presetCollection?.activePreset
            val retainsAudio = preset?.audioSaveMode != null && preset.audioSaveMode != CaptureAudioSaveMode.OFF
            val audioUri = if (retainsAudio) exportRecordingAudio(sessionID) else null
            if (retainsAudio && audioUri == null) {
                presentNotice(voxUiText("The audio could not be prepared. The original recording is still safe."))
                return@launch
            }
            val existing = editorValue.text.trimEnd()
            val combined = if (existing.isBlank()) transcript else "$existing\n\n$transcript"
            submitCapture(
                combined,
                capturedURL,
                originRecordingID = sessionID,
                audioContentUri = audioUri,
                audioDisplayName = "Recording-${sessionID.take(8)}.wav",
                frozenPreset = preset,
            )
        }
    }

    RecordingTranscriptCompletionEffect(
        transcription = recordingTranscription,
        confirmsVoiceNotesBeforeAdding = state.captureBar.confirmsVoiceNotesBeforeAdding,
        addToDraft = ::addRecordingTranscriptToDraft,
        voiceRecordingResult = state.captureBar.voiceRecordingResult,
        sendWithPreset = ::sendRecordingWithPreset,
        markRecordingAdded = markRecordingAdded,
    )
    LaunchedEffect(
        recordingStatus.phase,
        recordingTranscription?.phase,
        recordingTranscription?.addedToDraft,
        state.captureBar.confirmsVoiceNotesBeforeAdding,
    ) {
        val needsAttention = recordingStatus.phase in setOf(RecordingPhase.INTERRUPTED, RecordingPhase.FAILED) ||
            recordingTranscription?.phase == RecordingTranscriptionPhase.FAILED ||
            (state.captureBar.confirmsVoiceNotesBeforeAdding &&
                recordingTranscription?.phase == RecordingTranscriptionPhase.COMPLETED &&
                !recordingTranscription.addedToDraft)
        if (needsAttention) showsVoiceCaptureDetails = true
    }

    val captureTextDescription = voxString("Capture Text")
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            CaptureBottomControls(
                destination = requireNotNull(state.destination),
                preset = state.presetCollection?.activePreset,
                captureBar = state.captureBar,
                hasContent = editorValue.text.isNotBlank() || capturedURL != null || state.draft.attachments.isNotEmpty(),
                isSending = state.isSending || isResolvingPresetLocation,
                hasPinnedAlternates = pinnedPresets.isNotEmpty(),
                isPresetRailExpanded = isPresetRailExpanded,
                togglePresetRail = togglePresetRail,
                onSubmit = { submitCapture(editorValue.text, capturedURL) },
                openHistory = openHistory,
                openSettings = openSettings,
                openPresets = openPresets,
                toggleKeyboard = {
                    focusManager.clearFocus()
                    keyboardController?.hide()
                },
                addLink = { showsLinkDialog = true },
                addMedia = { showsMediaDialog = true },
                addFiles = { filePicker.launch(arrayOf("*/*")) },
                scanDocument = ::startDocumentScan,
                extractText = {
                    ocrPicker.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                },
                addSketch = { showsSketchDialog = true },
                addCurrentLocation = ::addCurrentLocation,
                canUndo = undoStack.isNotEmpty(),
                undo = {
                    val previous = undoStack.removeLastOrNull()
                    if (previous != null) commitEditorValue(previous, registerUndo = false)
                    focusRequester.requestFocus()
                },
                editorCommand = ::applyCommand,
                paste = {
                    clipboard?.primaryClip?.takeIf { it.itemCount > 0 }
                        ?.getItemAt(0)?.coerceToText(context)?.toString()?.takeIf(String::isNotEmpty)?.let {
                        applyCommand(CaptureComposerCommand.ReplaceSelection(it))
                    }
                },
                showDueDate = { showsDueDateDialog = true },
                recordingStatus = recordingStatus,
                recordingTranscription = recordingTranscription,
                liveSpeech = liveSpeech,
                showsVoiceCaptureDetails = showsVoiceCaptureDetails,
                toggleVoiceCaptureDetails = { showsVoiceCaptureDetails = !showsVoiceCaptureDetails },
                dismissVoiceCaptureDetails = { showsVoiceCaptureDetails = false },
                startRecording = startRecording,
                pauseRecording = pauseRecording,
                resumeRecording = resumeRecording,
                stopRecording = stopRecording,
                cancelRecording = cancelRecording,
                dismissRecording = dismissRecording,
                processRecording = processRecording,
                cancelRecordingProcessing = cancelRecordingProcessing,
                addRecordingToDraft = ::addRecordingTranscriptToDraft,
                sendRecordingWithPreset = ::sendRecordingWithPreset,
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 20.dp, vertical = 16.dp),
        ) {
            if (state.entryTemplates.isNotEmpty()) {
                PresetChoiceRow(
                    title = voxString("Entry template"),
                    options = listOf("" to voxString("Preset Default")) + state.entryTemplates.map { it.id to it.name },
                    selected = state.draft.entryTemplateIDOverride.orEmpty(),
                    onSelected = { onEntryTemplateSelected(it.ifEmpty { null }) },
                )
                Spacer(Modifier.height(12.dp))
            }
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f),
            ) {
                BasicTextField(
                    value = editorValue,
                    onValueChange = { commitEditorValue(it) },
                    modifier = Modifier
                        .fillMaxSize()
                        .focusRequester(focusRequester)
                        .testTag("capture-editor")
                        .semantics { contentDescription = captureTextDescription },
                textStyle = TextStyle(
                    color = MaterialTheme.colorScheme.onBackground,
                    fontFamily = GeistMonoFontFamily,
                    fontSize = 18.sp,
                    lineHeight = 26.sp,
                ),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                decorationBox = { inner ->
                    Box(Modifier.fillMaxSize()) {
                        if (editorValue.text.isEmpty()) {
                            Column(
                                modifier = Modifier
                                    .align(Alignment.Center)
                                    .widthIn(max = 520.dp)
                                    .fillMaxWidth()
                                    .padding(horizontal = 28.dp),
                                horizontalAlignment = Alignment.CenterHorizontally,
                                verticalArrangement = Arrangement.spacedBy(8.dp),
                            ) {
                                Text(voxString("Do what you can, with what you have, where you are."),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    style = MaterialTheme.typography.bodyLarge.copy(fontFamily = GeistMonoFontFamily),
                                    textAlign = TextAlign.Center,
                                )
                                Text(voxString("— Theodore Roosevelt"),
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.72f),
                                    style = MaterialTheme.typography.bodyMedium,
                                    textAlign = TextAlign.Center,
                                )
                            }
                        }
                        inner()
                    }
                },
                )
                CapturePresetQuickAccessRail(
                    presets = pinnedPresets,
                    isExpanded = isPresetRailExpanded,
                    canSelectPreset = !state.isSending && !state.isSavingConfiguration,
                    selectPreset = onSelectPreset,
                    modifier = Modifier.align(Alignment.BottomStart),
                )
            }
            if (capturedURL != null) {
                Spacer(Modifier.height(12.dp))
                LinkAttachment(
                    url = requireNotNull(capturedURL),
                    remove = {
                        capturedURL = null
                        onDraftChanged(editorValue.text, null)
                    },
                )
            }
            if (state.draft.attachments.isNotEmpty()) {
                Spacer(Modifier.height(12.dp))
                LazyRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.draft.attachments, key = CaptureAttachment::id) { attachment ->
                        AttachmentChip(attachment, remove = { removeDraftAttachment(attachment.id) })
                    }
                }
            }
        }
    }
}

internal fun locationUnavailableMessage(reason: CaptureLocationUnavailableReason): String = when (reason) {
    CaptureLocationUnavailableReason.PERMISSION_DENIED -> "Location permission was denied. Your draft is preserved."
    CaptureLocationUnavailableReason.RESTRICTED -> "Location access is restricted on this device. Your draft is preserved."
    CaptureLocationUnavailableReason.NOT_DETERMINED -> "Location permission has not been decided. Your draft is preserved."
    CaptureLocationUnavailableReason.REDUCED_ACCURACY -> "Precise location is required by this preset, but only approximate location is available. Your draft is preserved."
    CaptureLocationUnavailableReason.TIMEOUT -> "The location request timed out. Your draft is preserved."
    CaptureLocationUnavailableReason.CANCELLED -> "The location request was cancelled. Your draft is preserved."
    CaptureLocationUnavailableReason.UNAVAILABLE -> "A current location is unavailable. Your draft is preserved."
}

internal fun locationUnavailableUiText(reason: CaptureLocationUnavailableReason): VoxUiText = when (reason) {
    CaptureLocationUnavailableReason.PERMISSION_DENIED -> voxUiText("Location permission was denied. Your draft is preserved.")
    CaptureLocationUnavailableReason.RESTRICTED -> voxUiText("Location access is restricted on this device. Your draft is preserved.")
    CaptureLocationUnavailableReason.NOT_DETERMINED -> voxUiText("Location permission has not been decided. Your draft is preserved.")
    CaptureLocationUnavailableReason.REDUCED_ACCURACY -> voxUiText("Precise location is required by this preset, but only approximate location is available. Your draft is preserved.")
    CaptureLocationUnavailableReason.TIMEOUT -> voxUiText("The location request timed out. Your draft is preserved.")
    CaptureLocationUnavailableReason.CANCELLED -> voxUiText("The location request was cancelled. Your draft is preserved.")
    CaptureLocationUnavailableReason.UNAVAILABLE -> voxUiText("A current location is unavailable. Your draft is preserved.")
}

@Composable
internal fun LocationUnavailableDialog(
    reason: CaptureLocationUnavailableReason,
    canPersistPreference: Boolean,
    retry: () -> Unit,
    sendWithoutLocation: () -> Unit,
    alwaysSendWithoutLocation: () -> Unit,
    cancel: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = cancel,
        title = { Text(voxString("Location unavailable")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(locationUnavailableUiText(reason).localized())
                Text(voxString("Retry, send this capture without location, or cancel. No new location is requested after the capture is queued."))
            }
        },
        confirmButton = {
            Column(horizontalAlignment = Alignment.End) {
                TextButton(onClick = retry) { Text(voxString("Retry")) }
                TextButton(onClick = sendWithoutLocation) { Text(voxString("Send Without Location")) }
                TextButton(onClick = alwaysSendWithoutLocation, enabled = canPersistPreference) {
                    Text(voxString("Always Send Without Location"))
                }
            }
        },
        dismissButton = {
            TextButton(onClick = cancel) { Text(voxString("Cancel")) }
        },
    )
}

/**
 * Pinned quick-access rail mirrored from the iOS capture screen: an icon column
 * on the editor's start edge, bottom-anchored near the controls. The active
 * preset is never listed — the selector row already represents it, and that
 * row's tap toggles this rail (long-press keeps full preset access). Collapsed
 * or without usable pins the rail renders nothing, like iOS's plain-menu
 * fallback.
 */
@Composable
internal fun CapturePresetQuickAccessRail(
    presets: List<CapturePreset>,
    isExpanded: Boolean,
    canSelectPreset: Boolean,
    selectPreset: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (presets.isEmpty() || !isExpanded) return
    val scrollState = rememberScrollState()
    // The list reads from the controls upward: anchor an overflowing rail at
    // its bottom edge so the highest-priority pin stays visible.
    var anchoredToBottom by remember { mutableStateOf(false) }
    LaunchedEffect(scrollState.maxValue) {
        if (!anchoredToBottom && scrollState.maxValue > 0) {
            scrollState.scrollTo(scrollState.maxValue)
            anchoredToBottom = true
        }
    }
    Column(
        modifier = modifier
            .widthIn(min = 48.dp)
            .heightIn(max = 320.dp)
            .verticalScroll(scrollState)
            .padding(vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        presets.forEach { preset ->
            CapturePresetQuickAccessButton(preset, enabled = canSelectPreset) { selectPreset(preset.id) }
        }
    }
}

@Composable
private fun CapturePresetQuickAccessButton(
    preset: CapturePreset,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val presetDescription = voxFormat("Capture Preset %@", preset.name)
    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.92f),
        border = androidx.compose.foundation.BorderStroke(1.dp, MaterialTheme.colorScheme.outline.copy(alpha = 0.6f)),
        modifier = Modifier.padding(vertical = 2.dp),
    ) {
        IconButton(
            onClick = onClick,
            enabled = enabled,
            modifier = Modifier
                .size(48.dp)
                .testTag("capture-preset-rail-${preset.id}")
                .semantics { contentDescription = presetDescription },
        ) {
            PresetIdentityIcon(
                symbol = preset.symbol,
                emoji = preset.emoji,
                name = preset.name,
                modifier = Modifier.size(24.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CaptureBottomControls(
    destination: CaptureDestination,
    preset: CapturePreset?,
    captureBar: CaptureBarConfiguration,
    hasContent: Boolean,
    isSending: Boolean,
    hasPinnedAlternates: Boolean,
    isPresetRailExpanded: Boolean,
    togglePresetRail: () -> Unit,
    onSubmit: () -> Unit,
    openHistory: () -> Unit,
    openSettings: () -> Unit,
    openPresets: () -> Unit,
    toggleKeyboard: () -> Unit,
    addLink: () -> Unit,
    addMedia: () -> Unit,
    addFiles: () -> Unit,
    scanDocument: () -> Unit,
    extractText: () -> Unit,
    addSketch: () -> Unit,
    addCurrentLocation: () -> Unit,
    canUndo: Boolean,
    undo: () -> Unit,
    editorCommand: (CaptureComposerCommand) -> Unit,
    paste: () -> Unit,
    showDueDate: () -> Unit,
    recordingStatus: RecordingStatus,
    recordingTranscription: RecordingTranscriptionState?,
    liveSpeech: LiveSpeechState?,
    showsVoiceCaptureDetails: Boolean,
    toggleVoiceCaptureDetails: () -> Unit,
    dismissVoiceCaptureDetails: () -> Unit,
    startRecording: () -> Unit,
    pauseRecording: () -> Unit,
    resumeRecording: () -> Unit,
    stopRecording: () -> Unit,
    cancelRecording: () -> Unit,
    dismissRecording: () -> Unit,
    processRecording: () -> Unit,
    cancelRecordingProcessing: () -> Unit,
    addRecordingToDraft: (String) -> Unit,
    sendRecordingWithPreset: (String) -> Unit,
) {
    val sendDescription = voxString(if (isSending) "Sending capture" else "Send capture")
    val recordingIsProcessing = recordingTranscription?.phase in setOf(
        RecordingTranscriptionPhase.QUEUED,
        RecordingTranscriptionPhase.PROCESSING,
        RecordingTranscriptionPhase.FINALIZING,
    )
    val recordingNeedsAttention = recordingStatus.phase in setOf(
        RecordingPhase.INTERRUPTED,
        RecordingPhase.FAILED,
    ) || recordingTranscription?.phase in setOf(
        RecordingTranscriptionPhase.FAILED,
        RecordingTranscriptionPhase.DISCARDED,
    ) || (recordingTranscription?.phase == RecordingTranscriptionPhase.COMPLETED && !recordingTranscription.addedToDraft) ||
        (recordingStatus.phase == RecordingPhase.COMPLETED && recordingTranscription == null)
    val voiceDescription = voxString(when {
        recordingStatus.isActive -> "Stop voice capture"
        recordingIsProcessing -> "Voice capture is being transcribed. Show detailed recording controls"
        recordingNeedsAttention -> "Voice capture needs attention. Show detailed recording controls"
        else -> "Start voice capture"
    })
    val pauseDescription = voxString(
        if (recordingStatus.phase == RecordingPhase.PAUSED) "Resume recording" else "Pause recording",
    )
    val handleVoiceClick = {
        when {
            recordingStatus.isActive -> stopRecording()
            recordingIsProcessing || recordingNeedsAttention -> toggleVoiceCaptureDetails()
            else -> startRecording()
        }
    }
    Surface(color = MaterialTheme.colorScheme.background, tonalElevation = 0.dp) {
        Column(modifier = Modifier.fillMaxWidth().imePadding()) {
            if (showsVoiceCaptureDetails) {
                RecordingDetails(
                    modifier = Modifier.heightIn(max = LocalConfiguration.current.screenHeightDp.dp * 0.42f),
                    status = recordingStatus,
                    transcription = recordingTranscription,
                    liveSpeech = liveSpeech,
                    start = startRecording,
                    pause = pauseRecording,
                    resume = resumeRecording,
                    stop = stopRecording,
                    cancel = cancelRecording,
                    dismiss = dismissRecording,
                    close = dismissVoiceCaptureDetails,
                    process = processRecording,
                    cancelProcessing = cancelRecordingProcessing,
                    addToDraft = addRecordingToDraft,
                    sendWithPreset = sendRecordingWithPreset,
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            // iOS parity: the selector's primary action toggles the pinned rail
            // when usable pins exist; touch-and-hold keeps the complete preset
            // list. Without pins it stays a plain navigation control.
            val expandsRail = hasPinnedAlternates
            val selectorClickLabel = voxString(
                if (isPresetRailExpanded) "Hide pinned capture presets" else "Show pinned capture presets",
            )
            val selectorTint = if (expandsRail && isPresetRailExpanded) {
                MaterialTheme.colorScheme.primary
            } else {
                MaterialTheme.colorScheme.onSurface
            }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .combinedClickable(
                        enabled = true,
                        onClickLabel = if (expandsRail) selectorClickLabel else null,
                        onLongClickLabel = voxString("Choose Capture Preset"),
                        onClick = { if (expandsRail) togglePresetRail() else openPresets() },
                        onLongClick = openPresets,
                    )
                    .testTag("capture-preset-selector")
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                PresetIdentityIcon(
                    symbol = preset?.symbol,
                    emoji = preset?.emoji,
                    name = preset?.name,
                    modifier = Modifier.size(20.dp),
                    tint = selectorTint,
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    preset?.name ?: "Default",
                    style = MaterialTheme.typography.labelLarge,
                    color = selectorTint,
                )
                Spacer(Modifier.width(16.dp))
                Text(
                    destination.displayName,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                val chevronDescription = if (expandsRail) selectorClickLabel else voxString("Choose Capture Preset")
                Icon(
                    Icons.Outlined.ChevronRight,
                    contentDescription = chevronDescription,
                    modifier = Modifier.size(20.dp),
                    tint = selectorTint,
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            Row(
                modifier = Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconAction(Icons.Outlined.History, "Recent captures", openHistory)
                IconAction(Icons.Outlined.Settings, "Settings", openSettings)
                Spacer(Modifier.weight(1f))
                FilledIconButton(
                    onClick = onSubmit,
                    enabled = hasContent && !isSending,
                    modifier = Modifier
                        .size(48.dp)
                        .testTag("send-capture")
                        .semantics {
                            contentDescription = sendDescription
                        },
                    colors = androidx.compose.material3.IconButtonDefaults.filledIconButtonColors(
                        containerColor = MaterialTheme.colorScheme.onSurface,
                        contentColor = MaterialTheme.colorScheme.surface,
                    ),
                ) {
                    if (isSending) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(20.dp),
                            strokeWidth = 2.dp,
                            color = MaterialTheme.colorScheme.surface,
                        )
                    } else Icon(Icons.Outlined.ArrowUpward, contentDescription = null)
                }
                Spacer(Modifier.width(4.dp))
                if (recordingStatus.isActive) {
                    IconButton(
                        onClick = if (recordingStatus.phase == RecordingPhase.PAUSED) resumeRecording else pauseRecording,
                        enabled = !isSending,
                        modifier = Modifier.semantics { contentDescription = pauseDescription },
                    ) {
                        Icon(
                            if (recordingStatus.phase == RecordingPhase.PAUSED) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                            contentDescription = null,
                            tint = if (recordingStatus.phase == RecordingPhase.PAUSED) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
                Box(
                    modifier = Modifier
                        .sizeIn(minWidth = 48.dp, minHeight = 48.dp)
                        .combinedClickable(
                            enabled = !isSending,
                            role = Role.Button,
                            onClickLabel = voiceDescription,
                            onLongClickLabel = voxString("Show detailed recording controls"),
                            onLongClick = toggleVoiceCaptureDetails,
                            onClick = handleVoiceClick,
                        )
                        .semantics { contentDescription = voiceDescription },
                    contentAlignment = Alignment.Center,
                ) {
                    CompactVoiceCaptureStatus(
                        status = recordingStatus,
                        transcription = recordingTranscription,
                    )
                }
                IconAction(Icons.Outlined.Keyboard, "Hide keyboard", toggleKeyboard)
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            LazyRow(
                modifier = Modifier.fillMaxWidth().height(68.dp).navigationBarsPadding(),
                contentPadding = PaddingValues(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                items(captureBar.visibleActions, key = CaptureBarAction::persistedName) { action ->
                    CaptureBarActionItem(
                        action = action,
                        usesTwentyFourHourTimestamps = captureBar.usesTwentyFourHourTimestamps,
                        canUndo = canUndo,
                        addLink = addLink,
                        addMedia = addMedia,
                        addFiles = addFiles,
                        scanDocument = scanDocument,
                        extractText = extractText,
                        addSketch = addSketch,
                        addCurrentLocation = addCurrentLocation,
                        undo = undo,
                        editorCommand = editorCommand,
                        paste = paste,
                        showDueDate = showDueDate,
                    )
                }
            }
        }
    }
}

@Composable
internal fun RecordingTranscriptCompletionEffect(
    transcription: RecordingTranscriptionState?,
    confirmsVoiceNotesBeforeAdding: Boolean,
    addToDraft: (String) -> Unit,
    voiceRecordingResult: VoiceRecordingResult = VoiceRecordingResult.ADD_TO_DRAFT,
    sendWithPreset: (String) -> Unit = {},
    markRecordingAdded: () -> Unit = {},
) {
    val preferredTranscript = transcription?.preferredTranscript.orEmpty()
    LaunchedEffect(
        transcription?.sessionID,
        transcription?.phase,
        transcription?.addedToDraft,
        voiceRecordingResult,
        confirmsVoiceNotesBeforeAdding,
        preferredTranscript,
    ) {
        if (
            transcription?.phase == RecordingTranscriptionPhase.COMPLETED &&
            !transcription.addedToDraft &&
            !confirmsVoiceNotesBeforeAdding &&
            preferredTranscript.isNotBlank()
        ) {
            when (voiceRecordingResult) {
                VoiceRecordingResult.ADD_TO_DRAFT -> addToDraft(preferredTranscript)
                VoiceRecordingResult.SEND_IMMEDIATELY -> {
                    // Mark consumed up front so the effect cannot re-fire (and
                    // double-send) while the asynchronous submission resolves.
                    markRecordingAdded()
                    sendWithPreset(preferredTranscript)
                }
            }
        }
    }
}

@Composable
private fun CompactVoiceCaptureStatus(
    status: RecordingStatus,
    transcription: RecordingTranscriptionState?,
) {
    when {
        status.isActive -> {
            val level = if (status.phase == RecordingPhase.PAUSED) 0.15f else status.level.coerceIn(0.15f, 1f)
            val barLevels = listOf(level * 0.55f, level, level * 0.72f, level * 0.9f, level * 0.48f)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(
                    formatRecordingElapsed(status.elapsedMillis),
                    style = MaterialTheme.typography.labelSmall.copy(fontFamily = GeistMonoFontFamily),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row(
                    modifier = Modifier.height(20.dp),
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    barLevels.forEach { barLevel ->
                        Surface(
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.8f),
                            shape = CircleShape,
                            modifier = Modifier.width(3.dp).height((4f + (16f * barLevel)).dp),
                        ) {}
                    }
                }
                Icon(
                    Icons.Outlined.Stop,
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                    tint = MaterialTheme.colorScheme.error,
                )
            }
        }
        transcription?.phase == RecordingTranscriptionPhase.PROCESSING -> {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                CircularProgressIndicator(
                    progress = { transcription.progress },
                    modifier = Modifier.size(20.dp),
                    strokeWidth = 2.dp,
                )
                Text(
                    voxFormat("%lld%%", (transcription.progress * 100).toInt()),
                    style = MaterialTheme.typography.labelSmall.copy(fontFamily = GeistMonoFontFamily),
                )
            }
        }
        transcription?.phase in setOf(RecordingTranscriptionPhase.QUEUED, RecordingTranscriptionPhase.FINALIZING) ->
            CircularProgressIndicator(modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
        transcription?.phase == RecordingTranscriptionPhase.COMPLETED && !transcription.addedToDraft -> Icon(
            Icons.Outlined.CheckCircle,
            contentDescription = null,
            tint = if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.GreenDark else VoxColors.Green,
        )
        transcription?.phase in setOf(RecordingTranscriptionPhase.FAILED, RecordingTranscriptionPhase.DISCARDED) ||
            status.phase in setOf(RecordingPhase.FAILED, RecordingPhase.INTERRUPTED) -> Icon(
                Icons.Outlined.ErrorOutline,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.error,
            )
        status.phase == RecordingPhase.COMPLETED && transcription == null -> Icon(
            Icons.Outlined.Schedule,
            contentDescription = null,
            tint = MaterialTheme.colorScheme.primary,
        )
        else -> Icon(Icons.Outlined.MicNone, contentDescription = null)
    }
}

@Composable
internal fun RecordingDetails(
    modifier: Modifier = Modifier,
    status: RecordingStatus,
    transcription: RecordingTranscriptionState?,
    liveSpeech: LiveSpeechState?,
    start: () -> Unit,
    pause: () -> Unit,
    resume: () -> Unit,
    stop: () -> Unit,
    cancel: () -> Unit,
    dismiss: () -> Unit,
    close: () -> Unit,
    process: () -> Unit,
    cancelProcessing: () -> Unit,
    addToDraft: (String) -> Unit,
    sendWithPreset: (String) -> Unit,
) {
    val active = status.isActive
    val hideDetailsDescription = voxString("Hide detailed recording controls")
    val color = when {
        transcription?.phase == RecordingTranscriptionPhase.FAILED -> MaterialTheme.colorScheme.error
        transcription?.phase in setOf(
            RecordingTranscriptionPhase.QUEUED,
            RecordingTranscriptionPhase.PROCESSING,
            RecordingTranscriptionPhase.FINALIZING,
        ) -> MaterialTheme.colorScheme.primary
        transcription?.phase == RecordingTranscriptionPhase.COMPLETED ->
            if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.GreenDark else VoxColors.Green
        status.phase == RecordingPhase.RECORDING -> MaterialTheme.colorScheme.error
        status.phase in setOf(RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED) ->
            if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.AmberDark else VoxColors.Amber
        status.phase == RecordingPhase.COMPLETED ->
            if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.GreenDark else VoxColors.Green
        status.phase == RecordingPhase.FAILED -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Column(
        modifier = modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 12.dp)
            .testTag("capture-recording-details"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(shape = CircleShape, color = color, modifier = Modifier.size(10.dp)) {}
                Spacer(Modifier.width(8.dp))
                Text(
                    recordingDetailsTitle(status, transcription).localized(),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { liveRegion = LiveRegionMode.Polite },
                )
                if (status.phase != RecordingPhase.IDLE) {
                    Text(
                        formatRecordingElapsed(status.elapsedMillis),
                        style = MaterialTheme.typography.labelLarge.copy(fontFamily = GeistMonoFontFamily),
                    )
                    Spacer(Modifier.width(4.dp))
                }
                IconButton(
                    onClick = close,
                    modifier = Modifier.size(40.dp).semantics { contentDescription = hideDetailsDescription },
                ) {
                    Icon(Icons.Outlined.Close, contentDescription = null, modifier = Modifier.size(20.dp))
                }
            }
            if (status.phase == RecordingPhase.RECORDING) {
                Surface(
                    color = MaterialTheme.colorScheme.outline,
                    shape = CircleShape,
                    modifier = Modifier.fillMaxWidth().height(4.dp),
                ) {
                    Row {
                        Surface(
                            color = color,
                            shape = CircleShape,
                            modifier = Modifier.fillMaxWidth(status.level.coerceIn(0.03f, 1f)),
                        ) {}
                    }
                }
            }
            Text(
                recordingDetailsSubtitle(status, transcription).localized(),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (active) {
                when (liveSpeech?.phase) {
                    LiveSpeechPhase.STARTING -> Text(voxString("Starting private live transcript…"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    LiveSpeechPhase.LISTENING, LiveSpeechPhase.PAUSED -> {
                        if (liveSpeech.displayText.isNotBlank()) {
                            Text(liveSpeech.displayText, style = MaterialTheme.typography.bodyMedium)
                        } else {
                            Text(
                                voxString(if (liveSpeech.phase == LiveSpeechPhase.PAUSED) "Live transcript paused" else "Listening on this device…"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        if (liveSpeech.droppedBufferCount > 0) {
                            Text(voxString("Live preview fell behind. The complete durable recording is unaffected."),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    LiveSpeechPhase.UNAVAILABLE, LiveSpeechPhase.FAILED -> Text(voxString("Live preview is unavailable. The recording remains safe for final on-device transcription."),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    LiveSpeechPhase.COMPLETED, null -> Unit
                }
            }
            when (transcription?.phase) {
                RecordingTranscriptionPhase.QUEUED -> Unit
                RecordingTranscriptionPhase.PROCESSING -> {
                    LinearProgressIndicator(progress = { transcription.progress }, modifier = Modifier.fillMaxWidth())
                    Text(voxFormat("Transcribing voice capture, %@ complete", voxFormat("%lld%%", (transcription.progress * 100).toInt())),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    TextButton(onClick = cancelProcessing) { Text(voxString("Cancel Processing")) }
                }
                RecordingTranscriptionPhase.FINALIZING -> Text(
                    voxString("Finalizing transcript…"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                RecordingTranscriptionPhase.COMPLETED -> {
                    val transcript = transcription.preferredTranscript.orEmpty()
                    Text(transcript, style = MaterialTheme.typography.bodyMedium)
                    FlowRow(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(4.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Button(
                            onClick = { addToDraft(transcript) },
                            enabled = transcript.isNotBlank() && !transcription.addedToDraft,
                        ) {
                            Text(voxString(if (transcription.addedToDraft) "Added" else "Add to Draft"), maxLines = 1)
                        }
                        TextButton(
                            onClick = { sendWithPreset(transcript) },
                            enabled = transcript.isNotBlank() && !transcription.addedToDraft,
                        ) { Text(voxString("Send with Preset"), maxLines = 1) }
                    }
                }
                RecordingTranscriptionPhase.FAILED -> {
                    Text(
                        voxString(if (transcription.failureCode == "transcriptionQuotaReached") {
                            "The free transcription limit has been reached. The original recording is still safe."
                        } else {
                            "Local transcription failed. The original recording is still safe."
                        }),
                        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.error,
                    )
                    TextButton(onClick = process) { Text(voxString("Retry Processing")) }
                }
                RecordingTranscriptionPhase.DISCARDED -> Text(
                    voxString("Processing discarded. The original audio is still safe."),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                null -> if (status.phase == RecordingPhase.COMPLETED) {
                    TextButton(onClick = process) { Text(voxString("Process Recording")) }
                }
            }
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                if (active) {
                    TextButton(onClick = if (status.phase == RecordingPhase.PAUSED) resume else pause) {
                        Icon(
                            if (status.phase == RecordingPhase.PAUSED) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(voxString(if (status.phase == RecordingPhase.PAUSED) "Resume" else "Pause"), maxLines = 1)
                    }
                    TextButton(onClick = stop) {
                        Icon(Icons.Outlined.Stop, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Stop"), maxLines = 1)
                    }
                    TextButton(onClick = cancel) { Text(voxString("Cancel"), maxLines = 1) }
                } else if (status.phase == RecordingPhase.INTERRUPTED) {
                    TextButton(onClick = resume) {
                        Icon(Icons.Outlined.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Resume"), maxLines = 1)
                    }
                    TextButton(onClick = stop) { Text(voxString("Finish"), maxLines = 1) }
                    TextButton(onClick = cancel) { Text(voxString("Cancel"), maxLines = 1) }
                } else if (status.phase == RecordingPhase.IDLE) {
                    Button(onClick = start) {
                        Icon(Icons.Outlined.MicNone, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Record"), maxLines = 1)
                    }
                } else {
                    TextButton(onClick = dismiss) { Text(voxString("Dismiss")) }
                }
            }
    }
}

private fun recordingDetailsTitle(
    status: RecordingStatus,
    transcription: RecordingTranscriptionState?,
): VoxUiText = when (transcription?.phase) {
    RecordingTranscriptionPhase.QUEUED -> voxUiText("Preparing transcript")
    RecordingTranscriptionPhase.PROCESSING -> voxUiText(
        "Transcribing voice capture, %@ complete",
        voxUiText("%lld%%", (transcription.progress * 100).toLong()),
    )
    RecordingTranscriptionPhase.FINALIZING -> voxUiText("Finalizing transcript")
    RecordingTranscriptionPhase.COMPLETED -> voxUiText("Transcript ready")
    RecordingTranscriptionPhase.FAILED -> voxUiText("Transcription needs attention")
    RecordingTranscriptionPhase.DISCARDED -> voxUiText("Transcription cancelled")
    null -> recordingTitleUiText(status.phase)
}

private fun recordingDetailsSubtitle(
    status: RecordingStatus,
    transcription: RecordingTranscriptionState?,
): VoxUiText = when (transcription?.phase) {
    RecordingTranscriptionPhase.QUEUED -> voxUiText("Waiting for the local model…")
    RecordingTranscriptionPhase.PROCESSING,
    RecordingTranscriptionPhase.FINALIZING,
    -> voxUiText("Processing audio on this device")
    RecordingTranscriptionPhase.COMPLETED -> if (transcription.addedToDraft) {
        voxUiText("Transcript added to Capture")
    } else {
        voxUiText("Review the transcript or send it with the selected preset")
    }
    RecordingTranscriptionPhase.FAILED -> voxUiText("The original recording is still safe on this device")
    RecordingTranscriptionPhase.DISCARDED -> voxUiText("The original recording remains available")
    null -> recordingDetailUiText(status)
}

private fun recordingTitleUiText(phase: RecordingPhase): VoxUiText = when (phase) {
    RecordingPhase.RECORDING -> voxUiText("Recording")
    RecordingPhase.PAUSED -> voxUiText("Recording paused")
    RecordingPhase.COMPLETED -> voxUiText("Recording saved")
    RecordingPhase.INTERRUPTED -> voxUiText("Recording interrupted")
    RecordingPhase.FAILED -> voxUiText("Recording failed")
    RecordingPhase.DISCARDED -> voxUiText("Recording cancelled")
    RecordingPhase.IDLE -> voxUiText("Voice capture")
}

internal fun shouldStartAutomaticTranscription(
    recording: RecordingStatus,
    transcriptionPhase: RecordingTranscriptionPhase?,
    hasSelectedModel: Boolean,
): Boolean = recording.sessionID != null &&
    recording.phase == RecordingPhase.COMPLETED &&
    hasSelectedModel &&
    transcriptionPhase == null

internal fun remotePhaseForTranscription(
    phase: RecordingTranscriptionPhase,
): WearRemoteRecordingPhase? = when (phase) {
    RecordingTranscriptionPhase.QUEUED,
    -> WearRemoteRecordingPhase.QUEUED
    RecordingTranscriptionPhase.PROCESSING,
    RecordingTranscriptionPhase.FINALIZING,
    -> WearRemoteRecordingPhase.TRANSCRIBING
    RecordingTranscriptionPhase.COMPLETED -> null
    RecordingTranscriptionPhase.FAILED -> WearRemoteRecordingPhase.FAILED
    RecordingTranscriptionPhase.DISCARDED -> WearRemoteRecordingPhase.DISCARDED
}

internal fun recordingCaptureWasAccepted(result: CaptureSubmitResult): Boolean = when (result) {
    is CaptureSubmitResult.Delivered -> true
    is CaptureSubmitResult.SavedForRetry -> result.durablySaved
    is CaptureSubmitResult.NeedsPermission -> result.requestID != null
    is CaptureSubmitResult.LimitReached -> true
    is CaptureSubmitResult.DestinationRequired,
    is CaptureSubmitResult.InvalidInput,
    -> false
}

internal fun remotePhaseForCaptureResult(result: CaptureSubmitResult): WearRemoteRecordingPhase = when (result) {
    is CaptureSubmitResult.Delivered -> WearRemoteRecordingPhase.DELIVERED
    is CaptureSubmitResult.SavedForRetry,
    is CaptureSubmitResult.NeedsPermission,
    is CaptureSubmitResult.LimitReached,
    is CaptureSubmitResult.DestinationRequired,
    is CaptureSubmitResult.InvalidInput,
    -> WearRemoteRecordingPhase.FAILED
}

internal fun remoteMessageForCaptureResult(result: CaptureSubmitResult): String? = when (result) {
    is CaptureSubmitResult.Delivered -> null
    is CaptureSubmitResult.SavedForRetry -> result.reason
    is CaptureSubmitResult.NeedsPermission -> "folderAccess"
    is CaptureSubmitResult.LimitReached -> "quotaReached"
    is CaptureSubmitResult.DestinationRequired -> "destinationRequired"
    is CaptureSubmitResult.InvalidInput -> "invalidCapture"
}

internal fun remotePhaseForCaptureState(state: CaptureState): WearRemoteRecordingPhase = when (state) {
    CaptureState.COMPLETED -> WearRemoteRecordingPhase.DELIVERED
    CaptureState.DISCARDED -> WearRemoteRecordingPhase.DISCARDED
    CaptureState.RETRYABLE_FAILURE,
    CaptureState.NEEDS_PERMISSION,
    CaptureState.NEEDS_USER_ACTION,
    CaptureState.PERMANENT_FAILURE,
    -> WearRemoteRecordingPhase.FAILED
    CaptureState.QUEUED,
    CaptureState.PREPARING,
    CaptureState.MATERIALIZED,
    CaptureState.COMMITTING,
    CaptureState.UNKNOWN_OUTCOME,
    -> WearRemoteRecordingPhase.DELIVERING
}

private fun recordingDetailUiText(status: RecordingStatus): VoxUiText = when (status.phase) {
    RecordingPhase.RECORDING -> voxUiText("Audio is staying on this device and is checkpointed every second.")
    RecordingPhase.PAUSED -> voxUiText("The recorded chunks are safe. Resume or stop when you’re ready.")
    RecordingPhase.COMPLETED -> when (status.failureCode) {
        "safetyLimitReached" -> voxUiText("Recording reached the 24-hour safety limit. All completed audio chunks were saved locally.")
        "continuousListeningLimitReached" -> voxUiText("Continuous listening reached its 10-minute limit. All segments were saved locally.")
        "voiceAutoStop" -> voxUiText("Voice Auto-Stop detected the end of speech. The recording was saved locally.")
        "segmentBoundaryPersistence" -> voxUiText("A segment boundary could not be saved, so recording stopped with all audio preserved.")
        else -> if (status.chunkCount == 1) {
            voxUiText("Saved locally in %lld durable chunk.", 1L)
        } else {
            voxUiText("Saved locally in %lld durable chunks.", status.chunkCount.toLong())
        }
    }
    RecordingPhase.INTERRUPTED -> voxUiText("The audio recorded before interruption is safe and available for recovery.")
    RecordingPhase.FAILED -> voxUiText("The microphone stopped, but completed chunks remain local.")
    RecordingPhase.DISCARDED -> voxUiText("The session is marked cancelled; its source remains recoverable for now.")
    RecordingPhase.IDLE -> voxUiText("Ready")
}

private fun formatRecordingElapsed(milliseconds: Long): String {
    val seconds = milliseconds.coerceAtLeast(0) / 1_000
    return "%d:%02d".format(seconds / 60, seconds % 60)
}

internal suspend fun exportRecordingForCapture(
    context: Context,
    client: AudioCaptureClient,
    sessionID: String,
): String? = withContext(Dispatchers.IO) {
    if (!sessionID.matches(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"))) {
        return@withContext null
    }
    runCatching {
        val file = createCaptureImportFile(context, "$sessionID-recording.wav") { output ->
            check(client.exportWav(sessionID, output)) { "recordingExportFailed" }
        }
        captureImportUri(context, file).toString()
    }.getOrNull()
}

private suspend fun configuredTranscriptAudioSource(
    context: Context,
    client: AudioCaptureClient,
    sessionID: String,
    preset: CapturePreset?,
): ConfiguredTranscriptAudioSource? {
    val resolvedPreset = preset ?: return null
    if (resolvedPreset.audioSaveMode == CaptureAudioSaveMode.OFF) return null
    val contentUri = exportRecordingForCapture(context, client, sessionID) ?: return null
    return ConfiguredTranscriptAudioSource(
        contentUri = contentUri,
        displayName = "Recording-${sessionID.take(8)}.wav",
        saveMode = resolvedPreset.audioSaveMode,
        attachmentsFolder = resolvedPreset.attachmentsFolder,
    )
}

@Composable
private fun IconAction(icon: ImageVector, label: String, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(48.dp)) {
        Icon(icon, contentDescription = label)
    }
}

@Composable
private fun ToolbarAction(
    icon: ImageVector,
    label: VoxUiText,
    enabled: Boolean,
    disabledDescription: VoxUiText = voxUiText("This action is not available yet"),
    onClick: () -> Unit = {},
) {
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(48.dp)) {
        Icon(icon, contentDescription = (if (enabled) label else disabledDescription).localized())
    }
}

@Composable
internal fun CaptureBarActionItem(
    action: CaptureBarAction,
    usesTwentyFourHourTimestamps: Boolean,
    canUndo: Boolean,
    addLink: () -> Unit,
    addMedia: () -> Unit,
    addFiles: () -> Unit,
    scanDocument: () -> Unit,
    extractText: () -> Unit,
    addSketch: () -> Unit,
    addCurrentLocation: () -> Unit,
    undo: () -> Unit,
    editorCommand: (CaptureComposerCommand) -> Unit,
    paste: () -> Unit,
    showDueDate: () -> Unit,
) {
    when (action) {
        CaptureBarAction.ADD_MEDIA -> ToolbarAction(Icons.Outlined.Image, voxUiText("Add media"), enabled = true, onClick = addMedia)
        CaptureBarAction.ADD_FILES -> ToolbarAction(Icons.Outlined.AttachFile, voxUiText("Add files"), enabled = true, onClick = addFiles)
        CaptureBarAction.SCAN_DOCUMENT -> ToolbarAction(Icons.Outlined.Description, voxUiText("Scan document"), enabled = true, onClick = scanDocument)
        CaptureBarAction.EXTRACT_TEXT -> ToolbarAction(Icons.Outlined.DocumentScanner, voxUiText("Extract text from journal images"), enabled = true, onClick = extractText)
        CaptureBarAction.UNDO -> ToolbarAction(
            Icons.AutoMirrored.Outlined.Undo,
            voxUiText("Undo"),
            enabled = canUndo,
            disabledDescription = voxUiText("Nothing to undo"),
            onClick = undo,
        )
        CaptureBarAction.FORMAT_MARKDOWN -> MarkdownFormatMenu(editorCommand)
        CaptureBarAction.MARKDOWN_LINK -> ToolbarAction(Icons.Outlined.Link, voxUiText("Markdown link"), enabled = true) {
            editorCommand(CaptureComposerCommand.MarkdownLink())
        }
        CaptureBarAction.DUE_DATE -> ToolbarAction(Icons.Outlined.Alarm, voxUiText("Set due date"), enabled = true, onClick = showDueDate)
        CaptureBarAction.CHECKLIST -> ToolbarAction(Icons.Outlined.CheckBox, voxUiText("Checklist"), enabled = true) {
            editorCommand(CaptureComposerCommand.TaskCheckbox)
        }
        CaptureBarAction.BULLET_LIST -> ToolbarAction(Icons.AutoMirrored.Outlined.FormatListBulleted, voxUiText("Bullet list"), enabled = true) {
            editorCommand(CaptureComposerCommand.Bullet)
        }
        CaptureBarAction.PASTE -> ToolbarAction(Icons.Outlined.ContentPaste, voxUiText("Paste"), enabled = true, onClick = paste)
        CaptureBarAction.INTERNAL_LINK -> ToolbarTextAction("[[", voxUiText("Internal link")) {
            editorCommand(CaptureComposerCommand.WikiLink())
        }
        CaptureBarAction.SKETCH -> ToolbarAction(Icons.Outlined.Edit, voxUiText("Sketch"), enabled = true, onClick = addSketch)
        CaptureBarAction.CURRENT_LOCATION -> ToolbarAction(Icons.Outlined.LocationOn, voxUiText("Insert current location"), enabled = true, onClick = addCurrentLocation)
        CaptureBarAction.TIMESTAMP -> ToolbarAction(Icons.Outlined.Schedule, voxUiText("Insert timestamp"), enabled = true) {
            val pattern = if (usesTwentyFourHourTimestamps) "HH:mm yyyy-MM-dd" else "h:mm a yyyy-MM-dd"
            editorCommand(CaptureComposerCommand.ReplaceSelection(SimpleDateFormat(pattern, Locale.US).format(Date())))
        }
        CaptureBarAction.DATE -> ToolbarAction(Icons.Outlined.CalendarToday, voxUiText("Insert date"), enabled = true) {
            editorCommand(CaptureComposerCommand.ReplaceSelection(SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())))
        }
        CaptureBarAction.TEXT_CASE -> TextCaseMenu(editorCommand)
    }
}

@Composable
private fun ToolbarTextAction(text: String, label: VoxUiText, onClick: () -> Unit) {
    val localizedLabel = label.localized()
    IconButton(onClick = onClick, modifier = Modifier.size(48.dp).semantics { contentDescription = localizedLabel }) {
        Text(text, style = MaterialTheme.typography.labelLarge.copy(fontFamily = GeistMonoFontFamily))
    }
}

@Composable
private fun MarkdownFormatMenu(command: (CaptureComposerCommand) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ToolbarAction(Icons.Outlined.TextFields, voxUiText("Format Markdown"), enabled = true) { expanded = true }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            CommandMenuItem(voxUiText("Bold"), CaptureComposerCommand.ToggleBold, command) { expanded = false }
            CommandMenuItem(voxUiText("Italic"), CaptureComposerCommand.ToggleItalic, command) { expanded = false }
            CommandMenuItem(voxUiText("Hashtag"), CaptureComposerCommand.InsertHashtag, command) { expanded = false }
            HorizontalDivider()
            (1..6).forEach { level ->
                CommandMenuItem(voxUiText("Heading %lld", level.toLong()), CaptureComposerCommand.Heading(level), command) { expanded = false }
            }
        }
    }
}

@Composable
private fun TextCaseMenu(command: (CaptureComposerCommand) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ToolbarTextAction("Abc", voxUiText("Change text case")) { expanded = true }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            CommandMenuItem(voxUiText("Lowercase"), CaptureComposerCommand.Lowercase, command) { expanded = false }
            CommandMenuItem(voxUiText("Uppercase"), CaptureComposerCommand.Uppercase, command) { expanded = false }
            CommandMenuItem(voxUiText("Sentence case"), CaptureComposerCommand.SentenceCase, command) { expanded = false }
            CommandMenuItem(voxUiText("Capitalize case"), CaptureComposerCommand.CapitalizeWords, command) { expanded = false }
            CommandMenuItem(voxUiText("Slugify case"), CaptureComposerCommand.Slugify, command) { expanded = false }
        }
    }
}

@Composable
private fun CommandMenuItem(
    label: VoxUiText,
    value: CaptureComposerCommand,
    command: (CaptureComposerCommand) -> Unit,
    dismiss: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(label.localized()) },
        onClick = {
            dismiss()
            command(value)
        },
    )
}

@Composable
internal fun DueDateDialog(onDismiss: () -> Unit, onInsert: (String) -> Unit) {
    fun token(calendar: Calendar): String = "(@${SimpleDateFormat("yyyy-MM-dd", Locale.US).format(calendar.time)})"
    fun calendarAfter(days: Int): Calendar = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, days) }
    val today = remember { Calendar.getInstance() }
    val tomorrow = remember { calendarAfter(1) }
    val weekend = remember {
        Calendar.getInstance().apply {
            val day = get(Calendar.DAY_OF_WEEK)
            val daysUntilWeekend = when (day) {
                Calendar.SATURDAY, Calendar.SUNDAY -> 0
                else -> (Calendar.SATURDAY - day + 7) % 7
            }
            add(Calendar.DAY_OF_YEAR, daysUntilWeekend)
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(voxString("Set due date")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(voxString("Insert an Obsidian-compatible due-date token at the current selection."),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Button(onClick = { onInsert(token(today)) }, modifier = Modifier.fillMaxWidth()) { Text(voxFormat("%@ · %@", voxString("Today"), token(today))) }
                Button(onClick = { onInsert(token(tomorrow)) }, modifier = Modifier.fillMaxWidth()) { Text(voxFormat("%@ · %@", voxString("Tomorrow"), token(tomorrow))) }
                Button(onClick = { onInsert(token(weekend)) }, modifier = Modifier.fillMaxWidth()) { Text(voxFormat("%@ · %@", voxString("This Weekend"), token(weekend))) }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text(voxString("Cancel")) } },
    )
}

@Composable
private fun LinkAttachment(url: String, remove: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier.padding(start = 12.dp, top = 8.dp, bottom = 8.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Link, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Text(
                url,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = MaterialTheme.typography.bodyMedium,
            )
            IconButton(onClick = remove, modifier = Modifier.size(40.dp)) {
                Icon(Icons.Outlined.Close, contentDescription = voxFormat("Remove %@", voxString("Link")), modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun AttachmentChip(attachment: CaptureAttachment, remove: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
    ) {
        Row(
            modifier = Modifier.padding(start = 12.dp, top = 6.dp, bottom = 6.dp, end = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                if (attachment.isImage) Icons.Outlined.Image else Icons.Outlined.AttachFile,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Column(modifier = Modifier.width(160.dp)) {
                Text(attachment.displayName, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodyMedium)
                Text(
                    formatAttachmentSize(attachment.byteCount),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    style = MaterialTheme.typography.labelSmall,
                )
            }
            IconButton(onClick = remove, modifier = Modifier.size(40.dp)) {
                Icon(Icons.Outlined.Close, contentDescription = voxFormat("Remove %@", attachment.displayName), modifier = Modifier.size(18.dp))
            }
        }
    }
}

private fun formatAttachmentSize(bytes: Long): String = when {
    bytes >= 1024 * 1024 -> "%.1f MB".format(Locale.getDefault(), bytes / (1024.0 * 1024.0))
    bytes >= 1024 -> "%.1f KB".format(Locale.getDefault(), bytes / 1024.0)
    else -> "$bytes B"
}

@Composable
private fun LinkDialog(initialValue: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var value by rememberSaveable(initialValue) { mutableStateOf(initialValue) }
    val valid = value.startsWith("https://") || value.startsWith("http://")
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(voxString("Capture Link")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it.take(8_192) },
                    label = { Text(voxString("Web address")) },
                    placeholder = { Text(voxString("https://example.com")) },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    singleLine = true,
                )
                Text(voxString("The link stays in your durable draft until the note is captured."),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = { TextButton(onClick = { onSave(value.trim()) }, enabled = valid) { Text(voxString("Add")) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(voxString("Cancel")) } },
    )
}

private enum class UnifiedHistoryKind(val label: String) {
    ALL("All"),
    CAPTURES("Captures"),
    TRANSCRIPTS("Transcripts"),
}

private sealed interface UnifiedHistoryRow {
    val stableKey: String
    val sortTime: Long

    data class Capture(val item: CaptureHistoryItem) : UnifiedHistoryRow {
        override val stableKey: String = "capture:${item.requestID}"
        override val sortTime: Long = item.updatedAtEpochMillis
    }

    data class Transcript(val item: RecordingTranscriptionState) : UnifiedHistoryRow {
        override val stableKey: String = "transcript:${item.sessionID}"
        override val sortTime: Long = item.completedAtEpochMillis ?: 0L
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun HistoryScreen(
    items: List<CaptureHistoryItem>,
    transcripts: List<RecordingTranscriptionState>,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    refresh: () -> Unit,
    retry: (String) -> Unit,
    repairAccess: (String?) -> Unit,
    openDetail: (String) -> Unit,
    openTranscript: (String) -> Unit,
    clearCompleted: () -> Unit,
) {
    var query by rememberSaveable { mutableStateOf("") }
    var needsAttentionOnly by rememberSaveable { mutableStateOf(false) }
    var kind by rememberSaveable { mutableStateOf(UnifiedHistoryKind.ALL.name) }
    var showsClearConfirmation by rememberSaveable { mutableStateOf(false) }
    val filteredCaptures = items.filter { item ->
        val searchTerms = query.trim().split(Regex("\\s+")).filter(String::isNotBlank)
        val searchText = listOfNotNull(
            item.requestID,
            historyTitleUiText(item.state).source,
            item.title,
            item.snippet,
            item.logicalPath,
            item.captureSource,
        ).joinToString(" ")
        val matchesQuery = searchTerms.all { searchText.contains(it, ignoreCase = true) }
        val matchesAttention = !needsAttentionOnly || item.state != CaptureState.COMPLETED
        val matchesKind = kind != UnifiedHistoryKind.TRANSCRIPTS.name
        matchesQuery && matchesAttention && matchesKind
    }
    val filteredTranscripts = transcripts.filter { transcript ->
        val matchesQuery = TranscriptSearch.matches(transcript, query)
        val matchesAttention = !needsAttentionOnly || transcript.phase != RecordingTranscriptionPhase.COMPLETED
        val matchesKind = kind != UnifiedHistoryKind.CAPTURES.name
        matchesQuery && matchesAttention && matchesKind
    }
    val unifiedRows = buildList<UnifiedHistoryRow> {
        filteredCaptures.forEach { add(UnifiedHistoryRow.Capture(it)) }
        filteredTranscripts.forEach { add(UnifiedHistoryRow.Transcript(it)) }
    }.sortedByDescending(UnifiedHistoryRow::sortTime)
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(voxString("History"), style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    IconButton(onClick = navigateBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = voxString("Back"))
                    }
                },
                actions = {
                    IconButton(
                        onClick = { showsClearConfirmation = true },
                        enabled = !isBusy && items.any { it.state == CaptureState.COMPLETED },
                    ) {
                        Icon(Icons.Outlined.Delete, contentDescription = voxString("Clear all history"))
                    }
                    IconButton(onClick = refresh, enabled = !isBusy) {
                        Icon(Icons.Outlined.Refresh, contentDescription = voxString("Refresh"))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding)) {
            OutlinedTextField(
                value = query,
                onValueChange = { query = it.take(128) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp),
                label = { Text(voxString("Search History")) },
                placeholder = { Text(voxString("Text, model, status, or ID")) },
                singleLine = true,
            )
            LazyRow(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                items(UnifiedHistoryKind.entries, key = UnifiedHistoryKind::name) { option ->
                    FilterChip(
                        selected = kind == option.name,
                        onClick = { kind = option.name },
                        label = { Text(option.label, maxLines = 1) },
                    )
                }
            }
            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FilterChip(
                    selected = needsAttentionOnly,
                    onClick = { needsAttentionOnly = !needsAttentionOnly },
                    label = { Text(voxString("Needs attention")) },
                )
                Spacer(Modifier.weight(1f))
                Text(voxFormat("%lld of %lld", unifiedRows.size, items.size + transcripts.size),
                    style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (unifiedRows.isEmpty()) {
                EmptyHistory(
                    modifier = Modifier.fillMaxWidth().weight(1f),
                    title = if (items.isEmpty() && transcripts.isEmpty()) "No history yet" else "No matching history",
                    detail = if (items.isEmpty() && transcripts.isEmpty()) {
                        "Captures and private on-device transcripts will appear here."
                    } else "Try another search or filter.",
                )
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxWidth().weight(1f),
                    contentPadding = PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(unifiedRows, key = UnifiedHistoryRow::stableKey) { row ->
                        when (row) {
                            is UnifiedHistoryRow.Capture -> HistoryCard(
                                item = row.item,
                                isBusy = isBusy,
                                retry = { retry(row.item.requestID) },
                                repairAccess = { repairAccess(row.item.requestID) },
                                openDetail = { openDetail(row.item.requestID) },
                            )
                            is UnifiedHistoryRow.Transcript -> TranscriptHistoryCard(
                                transcript = row.item,
                                openDetail = { openTranscript(row.item.sessionID) },
                            )
                        }
                    }
                }
            }
        }
    }
    if (showsClearConfirmation) {
        AlertDialog(
            onDismissRequest = { showsClearConfirmation = false },
            title = { Text(voxString("Clear completed History?")) },
            text = {
                Text(voxString("Completed local History markers will be removed. Markdown notes already written to your folder are not deleted, and lifetime Stats remain content-free and intact."))
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        showsClearConfirmation = false
                        clearCompleted()
                    },
                ) { Text(voxString("Clear"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { showsClearConfirmation = false }) { Text(voxString("Cancel")) } },
        )
    }
}

@Composable
private fun EmptyHistory(
    modifier: Modifier = Modifier,
    title: String = "No captures yet",
    detail: String = "Sent and recoverable captures will appear here without storing their note text.",
) {
    Column(
        modifier = modifier.padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            Icons.Outlined.History,
            contentDescription = null,
            modifier = Modifier.size(40.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.height(16.dp))
        Text(title, style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        Text(
            detail,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun HistoryCard(
    item: CaptureHistoryItem,
    isBusy: Boolean,
    retry: () -> Unit,
    repairAccess: () -> Unit,
    openDetail: () -> Unit,
) {
    val completed = item.state == CaptureState.COMPLETED
    val needsPermission = item.state == CaptureState.NEEDS_PERMISSION
    val statusColor = when {
        completed -> if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.GreenDark else VoxColors.Green
        needsPermission || item.state == CaptureState.UNKNOWN_OUTCOME ->
            if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.AmberDark else VoxColors.Amber
        item.state == CaptureState.RETRYABLE_FAILURE || item.state == CaptureState.PERMANENT_FAILURE -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.primary
    }
    Card(
        modifier = if (completed) Modifier else Modifier.clickable(onClick = openDetail),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    when {
                        completed -> Icons.Outlined.CheckCircle
                        needsPermission || item.state == CaptureState.UNKNOWN_OUTCOME -> Icons.Outlined.ErrorOutline
                        else -> Icons.Outlined.Schedule
                    },
                    contentDescription = null,
                    tint = statusColor,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    historyTitleUiText(item.state).localized(),
                    style = MaterialTheme.typography.titleMedium,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { liveRegion = LiveRegionMode.Polite },
                )
                Text(
                    item.requestID.take(8),
                    style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(item.updatedAtEpochMillis)),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            item.title?.takeIf(String::isNotBlank)?.let { title ->
                Text(title, style = MaterialTheme.typography.bodyLarge, maxLines = 2)
            }
            item.snippet?.takeIf { it != item.title }?.let { snippet ->
                Text(
                    snippet,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3,
                )
            }
            item.logicalPath?.let { path ->
                Text(
                    path,
                    style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!completed) {
                val sourceLabel = captureSourceUiText(item.captureSource).localized()
                Text(
                    when (item.attachmentCount) {
                        0 -> sourceLabel
                        1 -> voxFormat("%@ · %lld attachment", sourceLabel, 1L)
                        else -> voxFormat("%@ · %lld attachments", sourceLabel, item.attachmentCount.toLong())
                    },
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!completed && item.state != CaptureState.DISCARDED) {
                TextButton(onClick = if (needsPermission) repairAccess else retry, enabled = !isBusy) {
                    Icon(
                        if (needsPermission) Icons.Outlined.FolderOpen else Icons.Outlined.Refresh,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(voxString(if (needsPermission) "Repair Folder Access" else "Retry"))
                }
            }
        }
    }
}

@Composable
private fun TranscriptHistoryCard(
    transcript: RecordingTranscriptionState,
    openDetail: () -> Unit,
) {
    val complete = transcript.phase == RecordingTranscriptionPhase.COMPLETED
    val title = when (transcript.phase) {
        RecordingTranscriptionPhase.QUEUED -> "Transcript queued"
        RecordingTranscriptionPhase.PROCESSING -> "Transcribing"
        RecordingTranscriptionPhase.FINALIZING -> "Finalizing transcript"
        RecordingTranscriptionPhase.COMPLETED -> transcript.title ?: "Voice transcript"
        RecordingTranscriptionPhase.FAILED -> "Transcription needs attention"
        RecordingTranscriptionPhase.DISCARDED -> "Transcription discarded"
    }
    Card(
        modifier = Modifier.clickable(onClick = openDetail),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (complete) Icons.Outlined.MicNone else Icons.Outlined.ErrorOutline,
                    contentDescription = null,
                    tint = if (complete) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(title, style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Text(
                    formatTranscriptDuration(transcript.durationMillis),
                    style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily),
                )
            }
            transcript.completedAtEpochMillis?.let { completedAt ->
                Text(
                    DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(completedAt)),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            transcript.preferredTranscript?.takeIf(String::isNotBlank)?.let { text ->
                Text(
                    text.replace('\n', ' ').take(180),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 3,
                )
            }
            Text(
                listOfNotNull(transcript.modelName ?: transcript.modelID, transcript.languageTag).joinToString(" · "),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (transcript.category != null || transcript.tags.isNotEmpty()) {
                Text(
                    listOfNotNull(transcript.category, transcript.tags.takeIf { it.isNotEmpty() }?.joinToString(" · ") { "#$it" })
                        .joinToString(" · "),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun historyTitleUiText(state: CaptureState): VoxUiText = when (state) {
    CaptureState.COMPLETED -> voxUiText("Capture sent")
    CaptureState.QUEUED, CaptureState.PREPARING, CaptureState.MATERIALIZED, CaptureState.COMMITTING -> voxUiText("Capture in progress")
    CaptureState.RETRYABLE_FAILURE -> voxUiText("Ready to retry")
    CaptureState.NEEDS_PERMISSION -> voxUiText("Folder access needed")
    CaptureState.NEEDS_USER_ACTION -> voxUiText("Action needed")
    CaptureState.UNKNOWN_OUTCOME -> voxUiText("Checking delivery")
    CaptureState.PERMANENT_FAILURE -> voxUiText("Capture failed")
    CaptureState.DISCARDED -> voxUiText("Capture discarded")
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun CapturePresetsScreen(
    collection: CapturePresetCollection?,
    entryTemplates: List<CaptureEntryTemplate>,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    selectPreset: (String) -> Unit,
    editPreset: (String) -> Unit,
    createPreset: () -> Unit,
    saveEntryTemplate: (CaptureEntryTemplate) -> Unit,
    deleteEntryTemplate: (String) -> Unit,
) {
    var editingEntryTemplateID by rememberSaveable { mutableStateOf<String?>(null) }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(voxString("Capture Presets"), style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    IconButton(onClick = navigateBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = voxString("Back"))
                    }
                },
                actions = {
                    IconButton(onClick = createPreset, enabled = !isBusy && collection != null) {
                        Icon(Icons.Outlined.Add, contentDescription = voxString("New Capture Preset"))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        if (collection == null) {
            Box(Modifier.fillMaxSize().padding(padding), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(modifier = Modifier.size(28.dp), strokeWidth = 3.dp)
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(bottom = 32.dp),
            ) {
                item {
                    Text(voxString("A preset freezes the folder, filename, and frontmatter used by a capture before delivery starts."),
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                items(
                    collection.presets.sortedWith(compareByDescending<CapturePreset> { it.isPinned }.thenBy { it.name.lowercase() }),
                    key = CapturePreset::id,
                ) { preset ->
                    val active = preset.id == collection.activePreset.id
                    ListItem(
                        headlineContent = {
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(preset.name)
                                if (preset.isPinned) Text(voxString("Pinned"), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.primary)
                                if (!preset.isEnabled) Text(voxString("Disabled"), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                        },
                        supportingContent = {
                            Text(
                                presetRouteDescription(preset),
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        leadingContent = {
                            Surface(
                                shape = RoundedCornerShape(12.dp),
                                color = if (active) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                            ) {
                                Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                                    PresetIdentityIcon(
                                        symbol = preset.symbol,
                                        emoji = preset.emoji,
                                        name = preset.name,
                                        tint = if (active) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        },
                        trailingContent = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                if (active) {
                                    Icon(
                                        Icons.Outlined.CheckCircle,
                                        contentDescription = voxString("Selected"),
                                        tint = MaterialTheme.colorScheme.primary,
                                    )
                                }
                                IconButton(onClick = { editPreset(preset.id) }, enabled = !isBusy) {
                                    Icon(Icons.Outlined.Edit, contentDescription = voxFormat("%@: %@", voxString("Edit"), preset.name))
                                }
                            }
                        },
                        colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                        modifier = Modifier.clickable(enabled = !isBusy && preset.isEnabled) { selectPreset(preset.id) },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                }
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 20.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(voxString("Entry Templates"), style = MaterialTheme.typography.titleMedium)
                            Text(
                                voxString("Reusable prefix and suffix formatting. Linked presets receive edits automatically."),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        IconButton(onClick = { editingEntryTemplateID = "new" }, enabled = !isBusy) {
                            Icon(Icons.Outlined.Add, contentDescription = voxString("New Entry Template"))
                        }
                    }
                }
                items(entryTemplates.sortedBy { it.name.lowercase() }, key = CaptureEntryTemplate::id) { template ->
                    ListItem(
                        headlineContent = { Text(template.name) },
                        supportingContent = {
                            Text(
                                entryTemplateDescription(template),
                                maxLines = 2,
                                overflow = TextOverflow.Ellipsis,
                            )
                        },
                        leadingContent = { Icon(Icons.Outlined.TextFields, contentDescription = null) },
                        trailingContent = {
                            IconButton(onClick = { editingEntryTemplateID = template.id }, enabled = !isBusy) {
                                Icon(Icons.Outlined.Edit, contentDescription = voxFormat("%@: %@", voxString("Edit"), template.name))
                            }
                        },
                        colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                        modifier = Modifier.clickable(enabled = !isBusy) { editingEntryTemplateID = template.id },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                }
            }
        }
    }
    editingEntryTemplateID?.let { templateID ->
        val existing = entryTemplates.firstOrNull { it.id == templateID }
        EntryTemplateEditorDialog(
            template = existing,
            isBusy = isBusy,
            dismiss = { editingEntryTemplateID = null },
            save = { template ->
                saveEntryTemplate(template)
                editingEntryTemplateID = null
            },
            delete = existing?.let { template ->
                {
                    deleteEntryTemplate(template.id)
                    editingEntryTemplateID = null
                }
            },
        )
    }
}

@Composable
private fun entryTemplateDescription(template: CaptureEntryTemplate): String = buildList {
    template.entryPrefix.takeIf(String::isNotBlank)?.let {
        add(voxFormat("%@: %@", voxString("Prefix"), it.replace('\n', ' ').take(80)))
    }
    template.entrySuffix.takeIf(String::isNotBlank)?.let {
        add(voxFormat("%@: %@", voxString("Suffix"), it.replace('\n', ' ').take(80)))
    }
}.joinToString(" · ").ifBlank { voxString("No prefix or suffix") }

@Composable
private fun EntryTemplateEditorDialog(
    template: CaptureEntryTemplate?,
    isBusy: Boolean,
    dismiss: () -> Unit,
    save: (CaptureEntryTemplate) -> Unit,
    delete: (() -> Unit)?,
) {
    var name by remember(template?.id) { mutableStateOf(template?.name.orEmpty()) }
    var prefix by remember(template?.id) { mutableStateOf(template?.entryPrefix.orEmpty()) }
    var suffix by remember(template?.id) { mutableStateOf(template?.entrySuffix.orEmpty()) }
    AlertDialog(
        onDismissRequest = dismiss,
        title = { Text(voxString(if (template == null) "New Entry Template" else "Edit Entry Template")) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it.take(80) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Name")) },
                    singleLine = true,
                )
                OutlinedTextField(
                    value = prefix,
                    onValueChange = { prefix = it.take(16_384) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Prefix")) },
                    placeholder = { Text(voxString("- {time} ")) },
                    minLines = 2,
                )
                OutlinedTextField(
                    value = suffix,
                    onValueChange = { suffix = it.take(16_384) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Suffix")) },
                    minLines = 2,
                )
                if (delete != null) {
                    TextButton(onClick = delete, enabled = !isBusy) {
                        Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                        Spacer(Modifier.width(8.dp))
                        Text(voxString("Delete Template"), color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    save(
                        CaptureEntryTemplate(
                            id = template?.id ?: UUID.randomUUID().toString().lowercase(),
                            name = name,
                            entryPrefix = prefix,
                            entrySuffix = suffix,
                        ),
                    )
                },
                enabled = name.trim().isNotEmpty() && !isBusy,
            ) { Text(voxString("Save")) }
        },
        dismissButton = { TextButton(onClick = dismiss) { Text(voxString("Cancel")) } },
    )
}

@Composable
private fun presetRouteDescription(preset: CapturePreset): String = when (preset.noteTargetKind) {
    CaptureNoteTargetKind.NEW_NOTE -> voxFormat("%@ · %@", preset.logicalFolder, preset.noteNameTemplate)
    CaptureNoteTargetKind.ROLLING_NOTE -> voxFormat(
        "%@ · %@/%@",
        captureRollingPeriodUiText(preset.rollingPeriod).localized(),
        preset.logicalFolder,
        preset.noteNameTemplate,
    )
    CaptureNoteTargetKind.EXISTING_NOTE -> voxFormat(
        "%@ · %@",
        preset.existingNotePath,
        capturePlacementUiText(preset.placement).localized(),
    )
}

private fun captureRollingPeriodUiText(period: CaptureRollingPeriod): VoxUiText = when (period) {
    CaptureRollingPeriod.DAILY -> voxUiText("Daily")
    CaptureRollingPeriod.WEEKLY -> voxUiText("Weekly")
    CaptureRollingPeriod.MONTHLY -> voxUiText("Monthly")
    CaptureRollingPeriod.QUARTERLY -> voxUiText("Quarterly")
    CaptureRollingPeriod.YEARLY -> voxUiText("Yearly")
}

private fun capturePlacementUiText(placement: CapturePlacementKind): VoxUiText = when (placement) {
    CapturePlacementKind.APPEND -> voxUiText("Append")
    CapturePlacementKind.PREPEND -> voxUiText("Prepend")
    CapturePlacementKind.BENEATH_HEADING -> voxUiText("Beneath Heading")
}

private data class CapturePresetEditorDraft(
    val id: String,
    val name: String,
    val symbol: String,
    val emoji: String?,
    val isEnabled: Boolean,
    val isPinned: Boolean,
    val noteTargetKind: CaptureNoteTargetKind,
    val rollingPeriod: CaptureRollingPeriod,
    val logicalFolder: String,
    val noteNameTemplate: String,
    val existingNotePath: String,
    val placement: CapturePlacementKind,
    val headingTitle: String,
    val headingLevel: Int,
    val missingHeadingBehavior: CaptureMissingHeadingBehavior,
    val entryPrefix: String,
    val entrySuffix: String,
    val entryTemplateID: String?,
    val attachmentsFolder: String,
    val retryProtectionEnabled: Boolean,
    val metadataScope: CaptureMetadataScope,
    val metadataText: String,
    val speakerDiarizationEnabled: Boolean,
    val processingEnabled: Boolean,
    val processingMode: CaptureProcessingMode,
    val processingScope: CaptureProcessingScope,
    val customInstruction: String,
    val capturePrompt: String,
    val generateImageAltText: Boolean,
    val locationEnabled: Boolean,
    val locationPrecision: CaptureLocationPrecision,
    val locationUnavailableBehavior: CaptureLocationUnavailableBehavior,
    val locationMetadataEnabled: Boolean,
    val locationOutputMode: CaptureLocationOutputMode,
    val locationStructuredFields: List<CaptureLocationStructuredField>,
    val locationCollectionKey: String,
    val locationAdvancedTemplate: String,
    val locationLabelLookupClass: CaptureLocationLabelLookupClass,
    val locationLabelConsentVersion: Int?,
    val audioSaveMode: CaptureAudioSaveMode,
    val embedAudio: Boolean,
    val audioEmbedPlacement: CaptureAudioEmbedPlacement,
    val watchOutputMode: CaptureWatchOutputMode,
    val exportSettings: CapturePresetExportSettings,
) {
    fun toPreset(revision: Int, metadataFields: List<CaptureMetadataField>) = CapturePreset(
        id = id,
        name = name,
        symbol = symbol,
        emoji = emoji,
        revision = revision,
        logicalFolder = logicalFolder,
        noteNameTemplate = noteNameTemplate,
        metadataFields = metadataFields,
        isEnabled = isEnabled,
        isPinned = isPinned,
        noteTargetKind = noteTargetKind,
        rollingPeriod = rollingPeriod,
        existingNotePath = existingNotePath,
        placement = placement,
        headingTitle = headingTitle,
        headingLevel = headingLevel,
        missingHeadingBehavior = missingHeadingBehavior,
        entryPrefix = entryPrefix,
        entrySuffix = entrySuffix,
        entryTemplateID = entryTemplateID,
        attachmentsFolder = attachmentsFolder,
        retryProtectionEnabled = retryProtectionEnabled,
        metadataScope = metadataScope,
        speakerDiarizationEnabled = speakerDiarizationEnabled,
        processingEnabled = processingEnabled,
        processingMode = processingMode,
        processingScope = processingScope,
        customProcessingInstruction = customInstruction,
        capturePrompt = capturePrompt,
        generateImageAltText = generateImageAltText,
        locationPolicy = CapturePresetLocationPolicy(
            isEnabled = locationEnabled,
            precision = locationPrecision,
            unavailableBehavior = locationUnavailableBehavior,
            metadataOutputEnabled = locationMetadataEnabled,
            outputMode = locationOutputMode,
            structuredFields = locationStructuredFields,
            collectionKey = locationCollectionKey,
            advancedTemplate = locationAdvancedTemplate,
            labelLookupClass = locationLabelLookupClass,
            labelConsentVersion = locationLabelConsentVersion,
        ),
        audioSaveMode = audioSaveMode,
        embedAudioInMarkdown = embedAudio,
        audioEmbedPlacement = audioEmbedPlacement,
        watchOutputMode = watchOutputMode,
        exportSettings = exportSettings,
    )

    companion object {
        fun from(preset: CapturePreset?): CapturePresetEditorDraft = if (preset == null) {
            CapturePresetEditorDraft(
                id = UUID.randomUUID().toString().lowercase(),
                name = "",
                symbol = "description",
                emoji = null,
                isEnabled = true,
                isPinned = false,
                noteTargetKind = CaptureNoteTargetKind.NEW_NOTE,
                rollingPeriod = CaptureRollingPeriod.DAILY,
                logicalFolder = "Inbox",
                noteNameTemplate = "capture-{id}.md",
                existingNotePath = "",
                placement = CapturePlacementKind.APPEND,
                headingTitle = "",
                headingLevel = 1,
                missingHeadingBehavior = CaptureMissingHeadingBehavior.FAIL,
                entryPrefix = "",
                entrySuffix = "",
                entryTemplateID = null,
                attachmentsFolder = "Attachments",
                retryProtectionEnabled = false,
                metadataScope = CaptureMetadataScope.DOCUMENT,
                metadataText = "",
                speakerDiarizationEnabled = false,
                processingEnabled = false,
                processingMode = CaptureProcessingMode.CLEAN,
                processingScope = CaptureProcessingScope.BOTH,
                customInstruction = "",
                capturePrompt = "",
                generateImageAltText = false,
                locationEnabled = false,
                locationPrecision = CaptureLocationPrecision.EXACT,
                locationUnavailableBehavior = CaptureLocationUnavailableBehavior.ASK,
                locationMetadataEnabled = false,
                locationOutputMode = CaptureLocationOutputMode.STRUCTURED_FIELDS,
                locationStructuredFields = DEFAULT_CAPTURE_LOCATION_FIELDS,
                locationCollectionKey = "locations",
                locationAdvancedTemplate = "",
                locationLabelLookupClass = CaptureLocationLabelLookupClass.NONE,
                locationLabelConsentVersion = null,
                audioSaveMode = CaptureAudioSaveMode.OFF,
                embedAudio = false,
                audioEmbedPlacement = CaptureAudioEmbedPlacement.AFTER_TEXT,
                watchOutputMode = CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE,
                exportSettings = CapturePresetExportSettings(
                    usesCustomExportSettings = true,
                    exportEnabled = false,
                ),
            )
        } else {
            CapturePresetEditorDraft(
                id = preset.id,
                name = preset.name,
                symbol = preset.symbol,
                emoji = preset.emoji,
                isEnabled = preset.isEnabled,
                isPinned = preset.isPinned,
                noteTargetKind = preset.noteTargetKind,
                rollingPeriod = preset.rollingPeriod,
                logicalFolder = preset.logicalFolder,
                noteNameTemplate = preset.noteNameTemplate,
                existingNotePath = preset.existingNotePath,
                placement = preset.placement,
                headingTitle = preset.headingTitle,
                headingLevel = preset.headingLevel,
                missingHeadingBehavior = preset.missingHeadingBehavior,
                entryPrefix = preset.entryPrefix,
                entrySuffix = preset.entrySuffix,
                entryTemplateID = preset.entryTemplateID,
                attachmentsFolder = preset.attachmentsFolder,
                retryProtectionEnabled = preset.retryProtectionEnabled,
                metadataScope = preset.metadataScope,
                metadataText = preset.metadataFields.joinToString("\n") { "${it.name}=${it.value}" },
                speakerDiarizationEnabled = preset.speakerDiarizationEnabled,
                processingEnabled = preset.processingEnabled,
                processingMode = preset.processingMode,
                processingScope = preset.processingScope,
                customInstruction = preset.customProcessingInstruction,
                capturePrompt = preset.capturePrompt,
                generateImageAltText = preset.generateImageAltText,
                locationEnabled = preset.locationPolicy.isEnabled,
                locationPrecision = preset.locationPolicy.precision,
                locationUnavailableBehavior = preset.locationPolicy.unavailableBehavior,
                locationMetadataEnabled = preset.locationPolicy.metadataOutputEnabled,
                locationOutputMode = preset.locationPolicy.outputMode,
                locationStructuredFields = preset.locationPolicy.structuredFields,
                locationCollectionKey = preset.locationPolicy.collectionKey,
                locationAdvancedTemplate = preset.locationPolicy.advancedTemplate,
                locationLabelLookupClass = preset.locationPolicy.labelLookupClass,
                locationLabelConsentVersion = preset.locationPolicy.labelConsentVersion,
                audioSaveMode = preset.audioSaveMode,
                embedAudio = preset.embedAudioInMarkdown,
                audioEmbedPlacement = preset.audioEmbedPlacement,
                watchOutputMode = preset.watchOutputMode,
                exportSettings = preset.exportSettings,
            )
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CapturePresetEditorScreen(
    preset: CapturePreset?,
    entryTemplates: List<CaptureEntryTemplate>,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    save: (CapturePreset) -> Unit,
    delete: (() -> Unit)?,
) {
    var draft by remember(preset?.id) { mutableStateOf(CapturePresetEditorDraft.from(preset)) }
    val metadata = parseMetadataFields(draft.metadataText)
    val routeIsValid = when (draft.noteTargetKind) {
        CaptureNoteTargetKind.EXISTING_NOTE -> draft.existingNotePath.trim().endsWith(".md", ignoreCase = true)
        CaptureNoteTargetKind.NEW_NOTE, CaptureNoteTargetKind.ROLLING_NOTE ->
            draft.logicalFolder.trim('/').isNotEmpty() && draft.noteNameTemplate.trim().endsWith(".md", ignoreCase = true)
    }
    val headingIsValid = draft.placement != CapturePlacementKind.BENEATH_HEADING || draft.headingTitle.trim().isNotEmpty()
    val processingIsValid = !draft.processingEnabled ||
        draft.processingMode != CaptureProcessingMode.CUSTOM ||
        draft.customInstruction.trim().isNotEmpty()
    val configuredExportEnabled = draft.exportSettings.usesCustomExportSettings && draft.exportSettings.exportEnabled
    val exportIsValid = !configuredExportEnabled || (
        draft.exportSettings.destinationTreeUri != null &&
            draft.exportSettings.newFileNameTemplate.trim().isNotEmpty() &&
            draft.exportSettings.appendFileName.trim().isNotEmpty() &&
            (!draft.exportSettings.markdownTemplateEnabled || draft.exportSettings.markdownTemplateUri != null)
        )
    val locationIsValid = !draft.locationMetadataEnabled || (
        draft.locationCollectionKey.matches(Regex("^[A-Za-z_][A-Za-z0-9_-]{0,63}$")) &&
            when (draft.locationOutputMode) {
                CaptureLocationOutputMode.STRUCTURED_FIELDS -> structuredLocationFieldsAreValid(draft.locationStructuredFields)
                CaptureLocationOutputMode.ADVANCED_YAML ->
                    draft.metadataScope == CaptureMetadataScope.DOCUMENT && draft.locationAdvancedTemplate.isNotBlank()
            }
        )
    val locationLabelConsentIsValid = when (draft.locationLabelLookupClass) {
        CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK ->
            draft.locationLabelConsentVersion == CURRENT_LOCATION_LABEL_CONSENT_VERSION
        CaptureLocationLabelLookupClass.NONE,
        CaptureLocationLabelLookupClass.OFFLINE,
        -> draft.locationLabelConsentVersion == null
    }
    val valid = draft.name.trim().isNotEmpty() && routeIsValid && headingIsValid && processingIsValid &&
        exportIsValid && locationIsValid && locationLabelConsentIsValid && metadata != null

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(voxString(if (preset == null) "New Preset" else "Edit Preset"), style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    IconButton(onClick = navigateBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = voxString("Back"))
                    }
                },
                actions = {
                    IconButton(
                        onClick = {
                            save(draft.toPreset(preset?.revision ?: 1, requireNotNull(metadata)))
                        },
                        enabled = valid && !isBusy,
                    ) {
                        if (isBusy) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Outlined.CheckCircle, contentDescription = voxString("Save Capture Preset"))
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            CapturePresetIdentityEditor(
                name = draft.name,
                symbol = draft.symbol,
                emoji = draft.emoji,
                isEnabled = draft.isEnabled,
                isPinned = draft.isPinned,
                setName = { draft = draft.copy(name = it) },
                setSymbol = { draft = draft.copy(symbol = it, emoji = null) },
                setEmoji = { draft = draft.copy(emoji = it) },
                setEnabled = { draft = draft.copy(isEnabled = it) },
                setPinned = { draft = draft.copy(isPinned = it) },
            )
            CapturePresetDestinationEditor(
                noteTargetKind = draft.noteTargetKind,
                rollingPeriod = draft.rollingPeriod,
                logicalFolder = draft.logicalFolder,
                noteNameTemplate = draft.noteNameTemplate,
                existingNotePath = draft.existingNotePath,
                placement = draft.placement,
                headingTitle = draft.headingTitle,
                headingLevel = draft.headingLevel,
                missingHeadingBehavior = draft.missingHeadingBehavior,
                entryPrefix = draft.entryPrefix,
                entrySuffix = draft.entrySuffix,
                entryTemplateID = draft.entryTemplateID,
                entryTemplates = entryTemplates,
                attachmentsFolder = draft.attachmentsFolder,
                retryProtectionEnabled = draft.retryProtectionEnabled,
                setNoteTargetKind = { kind ->
                    draft = draft.copy(
                        noteTargetKind = kind,
                        noteNameTemplate = when {
                            kind == CaptureNoteTargetKind.ROLLING_NOTE && draft.noteNameTemplate == "capture-{id}.md" -> "{period}.md"
                            kind == CaptureNoteTargetKind.NEW_NOTE && draft.noteNameTemplate == "{period}.md" -> "capture-{id}.md"
                            else -> draft.noteNameTemplate
                        },
                    )
                },
                setRollingPeriod = { draft = draft.copy(rollingPeriod = it) },
                setLogicalFolder = { draft = draft.copy(logicalFolder = it) },
                setNoteNameTemplate = { draft = draft.copy(noteNameTemplate = it) },
                setExistingNotePath = { draft = draft.copy(existingNotePath = it) },
                setPlacement = { draft = draft.copy(placement = it) },
                setHeadingTitle = { draft = draft.copy(headingTitle = it) },
                setHeadingLevel = { draft = draft.copy(headingLevel = it) },
                setMissingHeadingBehavior = { draft = draft.copy(missingHeadingBehavior = it) },
                setEntryPrefix = { draft = draft.copy(entryPrefix = it) },
                setEntrySuffix = { draft = draft.copy(entrySuffix = it) },
                setEntryTemplateID = { templateID ->
                    val template = entryTemplates.firstOrNull { it.id == templateID }
                    draft = if (template == null) {
                        draft.copy(entryTemplateID = null)
                    } else {
                        draft.copy(
                            entryTemplateID = template.id,
                            entryPrefix = template.entryPrefix,
                            entrySuffix = template.entrySuffix,
                        )
                    }
                },
                setAttachmentsFolder = { draft = draft.copy(attachmentsFolder = it) },
                setRetryProtectionEnabled = { draft = draft.copy(retryProtectionEnabled = it) },
            )
            CapturePresetMetadataEditor(
                metadataScope = draft.metadataScope,
                metadataText = draft.metadataText,
                metadataIsValid = metadata != null,
                setMetadataScope = { draft = draft.copy(metadataScope = it) },
                setMetadataText = { draft = draft.copy(metadataText = it) },
            )
            CapturePresetVoiceEditor(
                speakerDiarizationEnabled = draft.speakerDiarizationEnabled,
                watchOutputMode = draft.watchOutputMode,
                audioSaveMode = draft.audioSaveMode,
                embedAudio = draft.embedAudio,
                audioEmbedPlacement = draft.audioEmbedPlacement,
                setSpeakerDiarizationEnabled = { draft = draft.copy(speakerDiarizationEnabled = it) },
                setWatchOutputMode = { draft = draft.copy(watchOutputMode = it) },
                setAudioSaveMode = { draft = draft.copy(audioSaveMode = it) },
                setEmbedAudio = { draft = draft.copy(embedAudio = it) },
                setAudioEmbedPlacement = { draft = draft.copy(audioEmbedPlacement = it) },
            )
            CapturePresetTranscriptExportEditor(
                settings = draft.exportSettings,
                audioSaveMode = draft.audioSaveMode,
                attachmentsFolder = draft.attachmentsFolder,
                onSettingsChanged = { draft = draft.copy(exportSettings = it) },
            )
            CapturePresetProcessingEditor(
                processingEnabled = draft.processingEnabled,
                processingScope = draft.processingScope,
                processingMode = draft.processingMode,
                customInstruction = draft.customInstruction,
                capturePrompt = draft.capturePrompt,
                generateImageAltText = draft.generateImageAltText,
                setProcessingEnabled = { draft = draft.copy(processingEnabled = it) },
                setProcessingScope = { draft = draft.copy(processingScope = it) },
                setProcessingMode = { draft = draft.copy(processingMode = it) },
                setCustomInstruction = { draft = draft.copy(customInstruction = it) },
                setCapturePrompt = { draft = draft.copy(capturePrompt = it) },
                setGenerateImageAltText = { draft = draft.copy(generateImageAltText = it) },
            )
            CapturePresetLocationEditor(
                locationEnabled = draft.locationEnabled,
                locationPrecision = draft.locationPrecision,
                locationUnavailableBehavior = draft.locationUnavailableBehavior,
                locationMetadataEnabled = draft.locationMetadataEnabled,
                locationOutputMode = draft.locationOutputMode,
                locationStructuredFields = draft.locationStructuredFields,
                locationCollectionKey = draft.locationCollectionKey,
                locationAdvancedTemplate = draft.locationAdvancedTemplate,
                locationLabelLookupClass = draft.locationLabelLookupClass,
                locationLabelConsentVersion = draft.locationLabelConsentVersion,
                setLocationEnabled = { draft = draft.copy(locationEnabled = it) },
                setLocationPrecision = { draft = draft.copy(locationPrecision = it) },
                setLocationUnavailableBehavior = { draft = draft.copy(locationUnavailableBehavior = it) },
                setLocationMetadataEnabled = { draft = draft.copy(locationMetadataEnabled = it) },
                setLocationOutputMode = { draft = draft.copy(locationOutputMode = it) },
                setLocationStructuredFields = { draft = draft.copy(locationStructuredFields = it) },
                setLocationCollectionKey = { draft = draft.copy(locationCollectionKey = it) },
                setLocationAdvancedTemplate = { draft = draft.copy(locationAdvancedTemplate = it) },
                setLocationLabelConsent = { consented ->
                    draft = draft.copy(
                        locationLabelLookupClass = if (consented) {
                            CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK
                        } else {
                            CaptureLocationLabelLookupClass.NONE
                        },
                        locationLabelConsentVersion = if (consented) CURRENT_LOCATION_LABEL_CONSENT_VERSION else null,
                    )
                },
            )
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                shape = RoundedCornerShape(16.dp),
            ) {
                Text(voxString("Preset changes only affect new captures. A pending capture keeps the exact preset snapshot it started with."),
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (delete != null) {
                TextButton(onClick = delete, enabled = !isBusy) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.width(8.dp))
                    Text(voxString("Delete Preset"), color = MaterialTheme.colorScheme.error)
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

@Composable
private fun CapturePresetIdentityEditor(
    name: String,
    symbol: String,
    emoji: String?,
    isEnabled: Boolean,
    isPinned: Boolean,
    setName: (String) -> Unit,
    setSymbol: (String) -> Unit,
    setEmoji: (String?) -> Unit,
    setEnabled: (Boolean) -> Unit,
    setPinned: (Boolean) -> Unit,
) {
    PresetSectionTitle(voxString("Identity"))
    OutlinedTextField(
        value = name,
        onValueChange = { setName(it.take(80)) },
        modifier = Modifier.fillMaxWidth(),
        label = { Text(voxString("Name")) },
        singleLine = true,
    )
    PresetSwitchRow(voxString("Enabled"), voxString("Show this preset in capture pickers."), isEnabled, setEnabled)
    PresetSwitchRow(voxString("Pinned"), voxString("Keep this preset at the top of the list."), isPinned, setPinned)
    Text(voxString("Icon"), style = MaterialTheme.typography.titleMedium)
    // One mode at a time: a symbol, an emoji, or no icon at all. The selection is
    // local state so an empty emoji field still shows Emoji mode; switching away
    // from Emoji commits immediately. Only the emoji field keeps uncommitted input.
    var selectedMode by remember { mutableStateOf(presetIconMode(symbol, emoji)) }
    val iconMode = selectedMode
    // Uncommitted native text input; validation never rewrites the field while a
    // multi-emoji paste is still visible. Only a normalized value reaches the draft.
    var emojiInput by remember(symbol, emoji) { mutableStateOf(emoji.orEmpty()) }
    val normalizedInput = CapturePresetEmoji.normalized(emojiInput)
    val previewEmoji = if (iconMode == PresetIconMode.EMOJI) normalizedInput ?: emoji else emoji
    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
        PresetIconMode.entries.forEachIndexed { index, mode ->
            SegmentedButton(
                selected = iconMode == mode,
                onClick = {
                    selectedMode = mode
                    when (mode) {
                        PresetIconMode.SYMBOL -> {
                            setEmoji(null)
                            if (symbol.isBlank()) setSymbol(PRESET_SYMBOLS.first())
                        }
                        PresetIconMode.EMOJI -> Unit // The field below commits once input is valid.
                        PresetIconMode.NONE -> {
                            setEmoji(null)
                            setSymbol("")
                        }
                    }
                },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = PresetIconMode.entries.size),
                label = {
                    Text(
                        when (mode) {
                            PresetIconMode.SYMBOL -> voxString("Symbol")
                            PresetIconMode.EMOJI -> voxString("Emoji")
                            PresetIconMode.NONE -> voxString("None")
                        },
                    )
                },
            )
        }
    }
    when (iconMode) {
        PresetIconMode.SYMBOL -> LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(PRESET_SYMBOLS, key = { it }) { option ->
                FilterChip(
                    selected = symbol == option,
                    onClick = { setSymbol(option) },
                    label = { Text(presetSymbolLabel(option).localized()) },
                    leadingIcon = { Icon(presetIcon(option), contentDescription = null, modifier = Modifier.size(18.dp)) },
                )
            }
        }
        PresetIconMode.EMOJI -> {
            OutlinedTextField(
                value = emojiInput,
                onValueChange = { input ->
                    emojiInput = input
                    // Valid input applies immediately; blank clears back to the symbol;
                    // an invalid value never overwrites the committed emoji.
                    setEmoji(CapturePresetEmoji.normalized(input) ?: if (input.isBlank()) null else emoji)
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(voxString("Emoji")) },
                singleLine = true,
                isError = emojiInput.isNotBlank() && normalizedInput == null,
                supportingText = {
                    Text(
                        if (normalizedInput == null) {
                            if (emojiInput.isBlank()) voxString("Enter one emoji to preview it, or choose a symbol.")
                            else voxString("Enter a single emoji, not text or multiple emoji. Your current icon has not changed.")
                        } else {
                            voxString("Use the emoji keyboard or paste one emoji. Flags, skin tones, and family emoji are supported.")
                        },
                        color = if (emojiInput.isNotBlank() && normalizedInput == null) {
                            MaterialTheme.colorScheme.error
                        } else {
                            MaterialTheme.colorScheme.onSurfaceVariant
                        },
                    )
                },
            )
            Text(
                voxString("Your symbol is kept as a fallback for surfaces that cannot display emoji."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        PresetIconMode.NONE -> Text(
            voxString("Without an icon, the preset's first letter is shown where an icon is required."),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PresetIdentityIcon(
            symbol = symbol,
            emoji = previewEmoji,
            name = name,
            modifier = Modifier.size(44.dp),
            contentDescription = null,
        )
        Column {
            Text(
                if (iconMode == PresetIconMode.EMOJI && normalizedInput != null) {
                    voxString("Preview")
                } else {
                    voxString("Current Icon")
                },
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(name.ifBlank { voxString("Name") }, style = MaterialTheme.typography.bodyMedium)
        }
    }
}

private enum class PresetIconMode { SYMBOL, EMOJI, NONE }

private fun presetIconMode(symbol: String, emoji: String?): PresetIconMode = when {
    emoji != null -> PresetIconMode.EMOJI
    symbol.isNotBlank() -> PresetIconMode.SYMBOL
    else -> PresetIconMode.NONE
}

/**
 * Decorative preset identity: a validated emoji wins over the stored symbol;
 * with neither, the preset's initial stands in so icon-only surfaces (the rail)
 * never render a blank target. The enclosing control owns the name label.
 */
@Composable
internal fun PresetIdentityIcon(
    symbol: String?,
    emoji: String?,
    name: String? = null,
    modifier: Modifier = Modifier,
    contentDescription: String? = null,
    tint: Color = LocalContentColor.current,
    emojiStyle: TextStyle = LocalTextStyle.current.copy(color = tint),
) {
    val normalized = CapturePresetEmoji.normalized(emoji)
    Box(modifier = modifier.wrapContentSize(Alignment.Center), contentAlignment = Alignment.Center) {
        when {
            normalized != null -> Text(normalized, style = emojiStyle, color = tint)
            !symbol.isNullOrBlank() -> Icon(presetIcon(symbol), contentDescription = contentDescription, tint = tint)
            else -> {
                val initial = name?.trim()?.takeIf(String::isNotEmpty)
                    ?.let { String(Character.toChars(it.codePointAt(0))) }
                    ?.uppercase()
                    .orEmpty()
                Text(initial, style = MaterialTheme.typography.labelLarge, color = tint)
            }
        }
    }
}

@Composable
private fun CapturePresetDestinationEditor(
    noteTargetKind: CaptureNoteTargetKind,
    rollingPeriod: CaptureRollingPeriod,
    logicalFolder: String,
    noteNameTemplate: String,
    existingNotePath: String,
    placement: CapturePlacementKind,
    headingTitle: String,
    headingLevel: Int,
    missingHeadingBehavior: CaptureMissingHeadingBehavior,
    entryPrefix: String,
    entrySuffix: String,
    entryTemplateID: String?,
    entryTemplates: List<CaptureEntryTemplate>,
    attachmentsFolder: String,
    retryProtectionEnabled: Boolean,
    setNoteTargetKind: (CaptureNoteTargetKind) -> Unit,
    setRollingPeriod: (CaptureRollingPeriod) -> Unit,
    setLogicalFolder: (String) -> Unit,
    setNoteNameTemplate: (String) -> Unit,
    setExistingNotePath: (String) -> Unit,
    setPlacement: (CapturePlacementKind) -> Unit,
    setHeadingTitle: (String) -> Unit,
    setHeadingLevel: (Int) -> Unit,
    setMissingHeadingBehavior: (CaptureMissingHeadingBehavior) -> Unit,
    setEntryPrefix: (String) -> Unit,
    setEntrySuffix: (String) -> Unit,
    setEntryTemplateID: (String?) -> Unit,
    setAttachmentsFolder: (String) -> Unit,
    setRetryProtectionEnabled: (Boolean) -> Unit,
) {
    PresetSectionTitle(voxString("Destination"))
    PresetChoiceRow(
        title = voxString("Note target"),
        options = listOf(
            CaptureNoteTargetKind.NEW_NOTE.name to voxString("New Note"),
            CaptureNoteTargetKind.ROLLING_NOTE.name to voxString("Rolling Note"),
            CaptureNoteTargetKind.EXISTING_NOTE.name to voxString("Existing Note"),
        ),
        selected = noteTargetKind.name,
        onSelected = { setNoteTargetKind(CaptureNoteTargetKind.valueOf(it)) },
    )
    if (noteTargetKind == CaptureNoteTargetKind.ROLLING_NOTE) {
        PresetChoiceRow(
            title = voxString("Rolling period"),
            options = CaptureRollingPeriod.entries.map { period ->
                period.name to captureRollingPeriodUiText(period).localized()
            },
            selected = rollingPeriod.name,
            onSelected = { setRollingPeriod(CaptureRollingPeriod.valueOf(it)) },
        )
    }
    if (noteTargetKind == CaptureNoteTargetKind.EXISTING_NOTE) {
        OutlinedTextField(
            value = existingNotePath,
            onValueChange = { setExistingNotePath(it.take(512)) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text(voxString("Existing note path")) },
            placeholder = { Text(voxString("Journal/Inbox.md")) },
            singleLine = true,
        )
    } else {
        OutlinedTextField(
            value = logicalFolder,
            onValueChange = { setLogicalFolder(it.take(256)) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text(voxString("Folder")) },
            placeholder = { Text(voxString("Inbox")) },
            singleLine = true,
        )
        OutlinedTextField(
            value = noteNameTemplate,
            onValueChange = { setNoteNameTemplate(it.take(256)) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text(voxString("Note filename template")) },
            placeholder = { Text(voxString("capture-{id}.md")) },
            supportingText = { Text(voxString("Supports {id}, {date}, {time}, {year}, {month}, {week}, and {quarter}.")) },
            singleLine = true,
        )
    }
    if (noteTargetKind != CaptureNoteTargetKind.NEW_NOTE) {
        PresetChoiceRow(
            title = voxString("Placement"),
            options = listOf(
                CapturePlacementKind.APPEND.name to capturePlacementUiText(CapturePlacementKind.APPEND).localized(),
                CapturePlacementKind.PREPEND.name to capturePlacementUiText(CapturePlacementKind.PREPEND).localized(),
                CapturePlacementKind.BENEATH_HEADING.name to capturePlacementUiText(CapturePlacementKind.BENEATH_HEADING).localized(),
            ),
            selected = placement.name,
            onSelected = { setPlacement(CapturePlacementKind.valueOf(it)) },
        )
        if (placement == CapturePlacementKind.BENEATH_HEADING) {
            OutlinedTextField(
                value = headingTitle,
                onValueChange = { setHeadingTitle(it.take(256)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(voxString("Heading title")) },
                singleLine = true,
            )
            PresetChoiceRow(
                title = voxString("Heading level"),
                options = (1..6).map { it.toString() to "H$it" },
                selected = headingLevel.toString(),
                onSelected = { setHeadingLevel(it.toInt()) },
            )
            PresetChoiceRow(
                title = voxString("If heading is missing"),
                options = listOf(
                    CaptureMissingHeadingBehavior.FAIL.name to voxString("Keep Pending"),
                    CaptureMissingHeadingBehavior.CREATE.name to voxString("Create Heading"),
                ),
                selected = missingHeadingBehavior.name,
                onSelected = { setMissingHeadingBehavior(CaptureMissingHeadingBehavior.valueOf(it)) },
            )
        }
    }
    PresetSectionTitle(voxString("Entry"))
    PresetChoiceRow(
        title = voxString("Formatting"),
        options = listOf("" to voxString("Custom")) + entryTemplates.map { it.id to it.name },
        selected = entryTemplateID.orEmpty(),
        onSelected = { setEntryTemplateID(it.ifEmpty { null }) },
    )
    if (entryTemplateID == null) {
        OutlinedTextField(
            value = entryPrefix,
            onValueChange = { setEntryPrefix(it.take(16_384)) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text(voxString("Prefix")) },
            placeholder = { Text(voxString("- {time} ")) },
            minLines = 2,
        )
        OutlinedTextField(
            value = entrySuffix,
            onValueChange = { setEntrySuffix(it.take(16_384)) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text(voxString("Suffix")) },
            minLines = 2,
        )
    } else {
        Text(
            voxString("This preset uses the linked template. Template edits apply automatically; the last formatting remains safe if the template is removed."),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(entryTemplateDescription(CaptureEntryTemplate(entryTemplateID, "", entryPrefix, entrySuffix)), style = MaterialTheme.typography.bodyMedium)
    }
    OutlinedTextField(
        value = attachmentsFolder,
        onValueChange = { setAttachmentsFolder(it.take(256)) },
        modifier = Modifier.fillMaxWidth(),
        label = { Text(voxString("Attachments folder")) },
        supportingText = { Text(voxString("Leave empty to store files beside the note.")) },
        singleLine = true,
    )
    PresetSwitchRow(
        voxString("Retry protection marker"),
        voxString("Embed an invisible request marker so interrupted writes can be reconciled safely."),
        retryProtectionEnabled,
        setRetryProtectionEnabled,
    )
}

@Composable
private fun CapturePresetMetadataEditor(
    metadataScope: CaptureMetadataScope,
    metadataText: String,
    metadataIsValid: Boolean,
    setMetadataScope: (CaptureMetadataScope) -> Unit,
    setMetadataText: (String) -> Unit,
) {
    PresetSectionTitle(voxString("Metadata"))
    PresetChoiceRow(
        title = voxString("Scope"),
        options = listOf(
            CaptureMetadataScope.DOCUMENT.name to voxString("Document Frontmatter"),
            CaptureMetadataScope.ENTRY.name to voxString("Inline Entry"),
        ),
        selected = metadataScope.name,
        onSelected = { setMetadataScope(CaptureMetadataScope.valueOf(it)) },
    )
    OutlinedTextField(
        value = metadataText,
        onValueChange = { setMetadataText(it.take(9_216)) },
        modifier = Modifier.fillMaxWidth(),
        label = { Text(voxString("Metadata fields")) },
        placeholder = { Text(voxString("source: android\ntags: inbox")) },
        supportingText = {
            Text(voxString(if (metadataIsValid) "One key/value pair per line." else "Use unique letters, numbers, _ or - for each key."))
        },
        isError = !metadataIsValid,
        minLines = 3,
    )
}

@Composable
private fun CapturePresetVoiceEditor(
    speakerDiarizationEnabled: Boolean,
    watchOutputMode: CaptureWatchOutputMode,
    audioSaveMode: CaptureAudioSaveMode,
    embedAudio: Boolean,
    audioEmbedPlacement: CaptureAudioEmbedPlacement,
    setSpeakerDiarizationEnabled: (Boolean) -> Unit,
    setWatchOutputMode: (CaptureWatchOutputMode) -> Unit,
    setAudioSaveMode: (CaptureAudioSaveMode) -> Unit,
    setEmbedAudio: (Boolean) -> Unit,
    setAudioEmbedPlacement: (CaptureAudioEmbedPlacement) -> Unit,
) {
    PresetSectionTitle(voxString("Voice and Audio"))
    PresetSwitchRow(
        voxString("Speaker diarization"),
        voxString("Label detected speakers when the installed transcription engine supports it."),
        speakerDiarizationEnabled,
        setSpeakerDiarizationEnabled,
    )
    PresetChoiceRow(
        title = voxString("Watch output"),
        options = listOf(
            CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE.name to voxString("Transcribe & Capture"),
            CaptureWatchOutputMode.RECORDING_ONLY.name to voxString("Recording Only"),
        ),
        selected = watchOutputMode.name,
        onSelected = { setWatchOutputMode(CaptureWatchOutputMode.valueOf(it)) },
    )
    if (watchOutputMode == CaptureWatchOutputMode.RECORDING_ONLY) {
        Text(
            voxString("Recording Only writes verified WAV audio to this preset's export folder using the new-file name template. It skips transcription and location."),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
    PresetChoiceRow(
        title = voxString("Save original audio"),
        options = listOf(
            CaptureAudioSaveMode.OFF.name to voxString("Off"),
            CaptureAudioSaveMode.ALONGSIDE_NOTE.name to voxString("Beside Note"),
            CaptureAudioSaveMode.ATTACHMENTS_FOLDER.name to voxString("Attachments"),
        ),
        selected = audioSaveMode.name,
        onSelected = { setAudioSaveMode(CaptureAudioSaveMode.valueOf(it)) },
    )
    if (audioSaveMode != CaptureAudioSaveMode.OFF) {
        PresetSwitchRow(voxString("Embed audio"), voxString("Add an audio link to the Markdown entry."), embedAudio, setEmbedAudio)
        if (embedAudio) {
            PresetChoiceRow(
                title = voxString("Audio link placement"),
                options = listOf(
                    CaptureAudioEmbedPlacement.BEFORE_TEXT.name to voxString("Before Text"),
                    CaptureAudioEmbedPlacement.AFTER_TEXT.name to voxString("After Text"),
                ),
                selected = audioEmbedPlacement.name,
                onSelected = { setAudioEmbedPlacement(CaptureAudioEmbedPlacement.valueOf(it)) },
            )
        }
    }
}

@Composable
private fun CapturePresetTranscriptExportEditor(
    settings: CapturePresetExportSettings,
    audioSaveMode: CaptureAudioSaveMode,
    attachmentsFolder: String,
    onSettingsChanged: (CapturePresetExportSettings) -> Unit,
) {
    val context = LocalContext.current
    val exportEnabled = settings.usesCustomExportSettings && settings.exportEnabled
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
            }
            onSettingsChanged(
                settings.copy(
                    usesCustomExportSettings = true,
                    destinationTreeUri = uri.toString(),
                    destinationName = queryTreeDisplayName(context, uri),
                ),
            )
        }
    }
    val templatePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
            onSettingsChanged(
                settings.copy(
                    usesCustomExportSettings = true,
                    markdownTemplateUri = uri.toString(),
                    markdownTemplateName = queryDocumentDisplayName(context, uri),
                ),
            )
        }
    }

    PresetSectionTitle(voxString("Transcript File Export"))
    PresetSwitchRow(
        voxString("Export completed transcripts"),
        voxString("Write completed recordings to a separate document folder using this preset's format."),
        exportEnabled,
    ) { enabled ->
        onSettingsChanged(settings.copy(usesCustomExportSettings = true, exportEnabled = enabled))
    }
    if (!exportEnabled) return

    Button(onClick = { folderPicker.launch(null) }) {
        Text(voxString(if (settings.destinationTreeUri == null) "Choose Export Folder" else "Change Export Folder"))
    }
    Text(
        settings.destinationName.takeIf(String::isNotBlank) ?: voxString("No export folder selected"),
        color = if (settings.destinationTreeUri == null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
        style = MaterialTheme.typography.bodyMedium,
    )
    PresetChoiceRow(
        title = voxString("File mode"),
        options = listOf(
            CaptureExportFileMode.NEW_FILE.name to voxString("New File"),
            CaptureExportFileMode.APPEND.name to voxString("Append"),
        ),
        selected = settings.mode.name,
        onSelected = { onSettingsChanged(settings.copy(mode = CaptureExportFileMode.valueOf(it))) },
    )
    PresetChoiceRow(
        title = voxString("Format"),
        options = listOf(
            CaptureExportFileFormat.MARKDOWN.name to voxString("Markdown"),
            CaptureExportFileFormat.TEXT.name to voxString("Plain Text"),
            CaptureExportFileFormat.JSON.name to voxString("JSON"),
            CaptureExportFileFormat.YAML.name to voxString("YAML"),
        ),
        selected = settings.format.name,
        onSelected = {
            val format = CaptureExportFileFormat.valueOf(it)
            onSettingsChanged(
                settings.copy(
                    format = format,
                    markdownTemplateEnabled = settings.markdownTemplateEnabled && format == CaptureExportFileFormat.MARKDOWN,
                ),
            )
        },
    )
    if (settings.mode == CaptureExportFileMode.NEW_FILE) {
        OutlinedTextField(
            value = settings.newFileNameTemplate,
            onValueChange = { onSettingsChanged(settings.copy(newFileNameTemplate = it.take(256))) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text(voxString("New filename template")) },
            supportingText = { Text(voxString("Supports {timestamp}, {date}, {YR}, {time}, {id}, {id8}, {model}, and {language}.")) },
            singleLine = true,
        )
    } else {
        OutlinedTextField(
            value = settings.appendFileName,
            onValueChange = { onSettingsChanged(settings.copy(appendFileName = it.take(256))) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text(voxString("Append filename")) },
            singleLine = true,
        )
    }
    if (settings.format == CaptureExportFileFormat.MARKDOWN) {
        PresetSwitchRow(
            voxString("Obsidian frontmatter"),
            voxString("Export Markdown as YAML frontmatter followed by the transcript metadata."),
            settings.mdObsidianEnabled,
        ) { onSettingsChanged(settings.copy(mdObsidianEnabled = it)) }
        PresetSwitchRow(
            voxString("Use Markdown template"),
            voxString("Render a selected Markdown template, fill its known frontmatter fields, then append the transcript."),
            settings.markdownTemplateEnabled,
        ) { onSettingsChanged(settings.copy(markdownTemplateEnabled = it)) }
        if (settings.markdownTemplateEnabled) {
            Button(onClick = { templatePicker.launch(arrayOf("text/markdown", "text/plain")) }) {
                Text(voxString(if (settings.markdownTemplateUri == null) "Choose Markdown Template" else "Change Markdown Template"))
            }
            Text(
                settings.markdownTemplateName.takeIf(String::isNotBlank) ?: voxString("No Markdown template selected"),
                color = if (settings.markdownTemplateUri == null) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        if (audioSaveMode != CaptureAudioSaveMode.OFF) {
            PresetSwitchRow(
                voxString("Embed exported audio"),
                if (audioSaveMode == CaptureAudioSaveMode.ATTACHMENTS_FOLDER) {
                    voxFormat(
                        "Copy retained audio into %@ and add an Obsidian audio embed.",
                        attachmentsFolder.takeIf(String::isNotBlank) ?: voxString("Attachments"),
                    )
                } else {
                    voxString("Copy retained audio beside the transcript and add an Obsidian audio embed.")
                },
                settings.embedAudioInMarkdown,
            ) { onSettingsChanged(settings.copy(embedAudioInMarkdown = it)) }
            if (settings.embedAudioInMarkdown) {
                PresetChoiceRow(
                    title = voxString("Exported audio placement"),
                    options = listOf(
                        CaptureAudioEmbedPlacement.BEFORE_TEXT.name to voxString("Top"),
                        CaptureAudioEmbedPlacement.AFTER_TEXT.name to voxString("Bottom"),
                    ),
                    selected = settings.audioEmbedPlacement.name,
                    onSelected = {
                        onSettingsChanged(
                            settings.copy(audioEmbedPlacement = CaptureAudioEmbedPlacement.valueOf(it)),
                        )
                    },
                )
            }
        }
    }
    if (settings.format == CaptureExportFileFormat.YAML) {
        PresetSwitchRow(
            voxString("Use .md extension"),
            voxString("Wrap YAML in Markdown frontmatter for Obsidian-compatible files."),
            settings.yamlUsesMarkdownExtension,
        ) { onSettingsChanged(settings.copy(yamlUsesMarkdownExtension = it)) }
        Text(voxString("YAML properties"), style = MaterialTheme.typography.titleMedium)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(CaptureExportYAMLProperty.entries, key = { it.name }) { property ->
                val selected = property in settings.yamlProperties
                FilterChip(
                    selected = selected,
                    onClick = {
                        val next = if (selected) settings.yamlProperties - property else settings.yamlProperties + property
                        if (next.isNotEmpty()) onSettingsChanged(settings.copy(yamlProperties = next))
                    },
                    label = { Text(exportYAMLPropertyUiText(property).localized()) },
                )
            }
        }
    }
}

private fun exportYAMLPropertyUiText(property: CaptureExportYAMLProperty): VoxUiText = when (property) {
    CaptureExportYAMLProperty.ID -> voxUiText("Identifier")
    CaptureExportYAMLProperty.TEXT -> voxUiText("Text")
    CaptureExportYAMLProperty.DATE -> voxUiText("Date")
    CaptureExportYAMLProperty.DURATION -> voxUiText("Duration")
    CaptureExportYAMLProperty.MODEL_USED -> voxUiText("Model")
    CaptureExportYAMLProperty.LANGUAGE -> voxUiText("Language")
}

@Composable
private fun CapturePresetProcessingEditor(
    processingEnabled: Boolean,
    processingScope: CaptureProcessingScope,
    processingMode: CaptureProcessingMode,
    customInstruction: String,
    capturePrompt: String,
    generateImageAltText: Boolean,
    setProcessingEnabled: (Boolean) -> Unit,
    setProcessingScope: (CaptureProcessingScope) -> Unit,
    setProcessingMode: (CaptureProcessingMode) -> Unit,
    setCustomInstruction: (String) -> Unit,
    setCapturePrompt: (String) -> Unit,
    setGenerateImageAltText: (Boolean) -> Unit,
) {
    PresetSectionTitle(voxString("On-device Processing"))
    PresetSwitchRow(
        voxString("Process before delivery"),
        voxString("Transform captured text locally after transcription and before Markdown rendering."),
        processingEnabled,
        setProcessingEnabled,
    )
    if (processingEnabled) {
        PresetChoiceRow(
            title = voxString("Scope"),
            options = listOf(
                CaptureProcessingScope.BOTH.name to voxString("Voice & Text"),
                CaptureProcessingScope.VOICE_ONLY.name to voxString("Voice Only"),
                CaptureProcessingScope.TEXT_ONLY.name to voxString("Text Only"),
            ),
            selected = processingScope.name,
            onSelected = { setProcessingScope(CaptureProcessingScope.valueOf(it)) },
        )
        PresetChoiceRow(
            title = voxString("Mode"),
            options = listOf(
                CaptureProcessingMode.NONE.name to voxString("None"),
                CaptureProcessingMode.CLEAN.name to voxString("Clean"),
                CaptureProcessingMode.TODO_LIST.name to voxString("To-do List"),
                CaptureProcessingMode.MEETING_NOTES.name to voxString("Meeting Notes"),
                CaptureProcessingMode.CUSTOM.name to voxString("Custom"),
            ),
            selected = processingMode.name,
            onSelected = { setProcessingMode(CaptureProcessingMode.valueOf(it)) },
        )
        if (processingMode == CaptureProcessingMode.CUSTOM) {
            OutlinedTextField(
                value = customInstruction,
                onValueChange = { setCustomInstruction(it.take(4_096)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(voxString("Custom instruction")) },
                minLines = 3,
            )
        }
        OutlinedTextField(
            value = capturePrompt,
            onValueChange = { setCapturePrompt(it.take(4_096)) },
            modifier = Modifier.fillMaxWidth(),
            label = { Text(voxString("Capture prompt")) },
            supportingText = { Text(voxString("Optional local context supplied to the processor.")) },
            minLines = 2,
        )
        PresetSwitchRow(
            voxString("Generate image alt text"),
            voxString("Describe attached images locally when a compatible model is installed."),
            generateImageAltText,
            setGenerateImageAltText,
        )
    }
}

@Composable
private fun CapturePresetLocationEditor(
    locationEnabled: Boolean,
    locationPrecision: CaptureLocationPrecision,
    locationUnavailableBehavior: CaptureLocationUnavailableBehavior,
    locationMetadataEnabled: Boolean,
    locationOutputMode: CaptureLocationOutputMode,
    locationStructuredFields: List<CaptureLocationStructuredField>,
    locationCollectionKey: String,
    locationAdvancedTemplate: String,
    locationLabelLookupClass: CaptureLocationLabelLookupClass,
    locationLabelConsentVersion: Int?,
    setLocationEnabled: (Boolean) -> Unit,
    setLocationPrecision: (CaptureLocationPrecision) -> Unit,
    setLocationUnavailableBehavior: (CaptureLocationUnavailableBehavior) -> Unit,
    setLocationMetadataEnabled: (Boolean) -> Unit,
    setLocationOutputMode: (CaptureLocationOutputMode) -> Unit,
    setLocationStructuredFields: (List<CaptureLocationStructuredField>) -> Unit,
    setLocationCollectionKey: (String) -> Unit,
    setLocationAdvancedTemplate: (String) -> Unit,
    setLocationLabelConsent: (Boolean) -> Unit,
) {
    val labelsNeeded = CapturePresetLocationPolicy(
        isEnabled = locationEnabled,
        precision = locationPrecision,
        unavailableBehavior = locationUnavailableBehavior,
        metadataOutputEnabled = locationMetadataEnabled,
        outputMode = locationOutputMode,
        structuredFields = locationStructuredFields,
        collectionKey = locationCollectionKey,
        advancedTemplate = locationAdvancedTemplate,
    ).requiresLabels
    PresetSectionTitle(voxString("Location"))
    PresetSwitchRow(
        voxString("Current location"),
        voxString("Request one location at send or recording stop; never track in the background."),
        locationEnabled,
        setLocationEnabled,
    )
    if (locationEnabled) {
        PresetChoiceRow(
            title = voxString("Precision"),
            options = listOf(
                CaptureLocationPrecision.EXACT.name to voxString("Exact"),
                CaptureLocationPrecision.CITY.name to voxString("City"),
            ),
            selected = locationPrecision.name,
            onSelected = { setLocationPrecision(CaptureLocationPrecision.valueOf(it)) },
        )
        PresetChoiceRow(
            title = voxString("If unavailable"),
            options = listOf(
                CaptureLocationUnavailableBehavior.ASK.name to voxString("Ask Every Time"),
                CaptureLocationUnavailableBehavior.SEND_WITHOUT_LOCATION.name to voxString("Send Without"),
                CaptureLocationUnavailableBehavior.CANCEL.name to voxString("Cancel Capture"),
            ),
            selected = locationUnavailableBehavior.name,
            onSelected = { setLocationUnavailableBehavior(CaptureLocationUnavailableBehavior.valueOf(it)) },
        )
        PresetSwitchRow(
            voxString("Write location metadata"),
            voxString("Add the frozen result to note frontmatter or inline entry fields."),
            locationMetadataEnabled,
            setLocationMetadataEnabled,
        )
        if (locationMetadataEnabled) {
            PresetChoiceRow(
                title = voxString("Output"),
                options = listOf(
                    CaptureLocationOutputMode.STRUCTURED_FIELDS.name to voxString("Structured Fields"),
                    CaptureLocationOutputMode.ADVANCED_YAML.name to voxString("Advanced YAML"),
                ),
                selected = locationOutputMode.name,
                onSelected = { setLocationOutputMode(CaptureLocationOutputMode.valueOf(it)) },
            )
            OutlinedTextField(
                value = locationCollectionKey,
                onValueChange = { setLocationCollectionKey(it.take(64)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(voxString("Collection key")) },
                singleLine = true,
            )
            if (locationOutputMode == CaptureLocationOutputMode.ADVANCED_YAML) {
                OutlinedTextField(
                    value = locationAdvancedTemplate,
                    onValueChange = { setLocationAdvancedTemplate(it.take(8_192)) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(voxString("Advanced YAML template")) },
                    placeholder = { Text(voxString("lat: {latitude}\nlon: {longitude}")) },
                    minLines = 4,
                )
            } else {
                Text(
                    voxString("Capture ID is always written as id. Choose other fields and rename their output keys below."),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                CaptureLocationField.entries.filterNot { it == CaptureLocationField.ID }.forEach { field ->
                    val selected = locationStructuredFields.firstOrNull { it.field == field }
                    PresetSwitchRow(
                        captureLocationFieldUiText(field).localized(),
                        voxFormat("Write %@ when the frozen snapshot contains it.", field.wireName),
                        selected != null,
                    ) { enabled ->
                        setLocationStructuredFields(
                            if (enabled) {
                                locationStructuredFields + CaptureLocationStructuredField(field)
                            } else {
                                locationStructuredFields.filterNot { it.field == field }
                            },
                        )
                    }
                    if (selected != null) {
                        OutlinedTextField(
                            value = selected.outputKey,
                            onValueChange = { outputKey ->
                                setLocationStructuredFields(
                                    locationStructuredFields.map { item ->
                                        if (item.field == field) item.copy(outputKey = outputKey.take(64)) else item
                                    },
                                )
                            },
                            modifier = Modifier.fillMaxWidth(),
                            label = { Text(voxFormat("%@: %@", captureLocationFieldUiText(field).localized(), voxString("Output key"))) },
                            isError = !selected.outputKey.matches(Regex("^[A-Za-z_][A-Za-z0-9_-]{0,63}$")) ||
                                selected.outputKey == "id",
                            singleLine = true,
                        )
                    }
                }
            }
            if (labelsNeeded) {
                PresetSwitchRow(
                    voxString("Use place labels"),
                    voxString("Android's system geocoder may contact a remote service and transmit the privacy-adjusted coordinates. This consent applies only to this preset."),
                    locationLabelLookupClass == CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK &&
                        locationLabelConsentVersion == CURRENT_LOCATION_LABEL_CONSENT_VERSION,
                    setLocationLabelConsent,
                )
                Text(
                    voxString("If you leave this off, capture still writes coordinates and map links; place, city, region, and country fields are omitted."),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

private fun captureLocationFieldUiText(field: CaptureLocationField): VoxUiText = when (field) {
    CaptureLocationField.COORDINATES -> voxUiText("Coordinates")
    CaptureLocationField.LATITUDE -> voxUiText("Latitude")
    CaptureLocationField.LONGITUDE -> voxUiText("Longitude")
    CaptureLocationField.PLACE -> voxUiText("Place")
    CaptureLocationField.CITY -> voxUiText("City")
    CaptureLocationField.REGION -> voxUiText("Region")
    CaptureLocationField.COUNTRY -> voxUiText("Country")
    CaptureLocationField.APPLE_MAPS_URL -> voxUiText("Apple Maps URL")
    CaptureLocationField.GOOGLE_MAPS_URL -> voxUiText("Google Maps URL")
    CaptureLocationField.OPEN_STREET_MAP_URL -> voxUiText("OpenStreetMap URL")
    CaptureLocationField.GEO_URI -> voxUiText("geo URI")
    CaptureLocationField.ACCURACY -> voxUiText("Accuracy")
    CaptureLocationField.TIMESTAMP -> voxUiText("Timestamp")
    CaptureLocationField.SOURCE -> voxUiText("Source")
    CaptureLocationField.ID -> voxUiText("Capture ID")
}

internal fun structuredLocationFieldsAreValid(fields: List<CaptureLocationStructuredField>): Boolean {
    if (fields.size > CaptureLocationField.entries.size) return false
    val fieldIDs = fields.map(CaptureLocationStructuredField::field)
    val outputKeys = fields.map(CaptureLocationStructuredField::outputKey)
    return fieldIDs.distinct().size == fieldIDs.size &&
        outputKeys.distinct().size == outputKeys.size &&
        fields.all { selection ->
            selection.outputKey.matches(Regex("^[A-Za-z_][A-Za-z0-9_-]{0,63}$")) &&
                if (selection.field == CaptureLocationField.ID) selection.outputKey == "id" else selection.outputKey != "id"
        }
}

@Composable
private fun PresetSectionTitle(title: String) {
    Text(
        title,
        modifier = Modifier.padding(top = 8.dp),
        style = MaterialTheme.typography.titleLarge,
    )
}

@Composable
private fun PresetSwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable { onCheckedChange(!checked) }
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun PresetChoiceRow(
    title: String,
    options: List<Pair<String, String>>,
    selected: String,
    onSelected: (String) -> Unit,
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(options, key = { it.second }) { (value, label) ->
                FilterChip(
                    selected = value == selected,
                    onClick = { onSelected(value) },
                    label = { Text(label) },
                )
            }
        }
    }
}

private fun parseMetadataFields(value: String): List<CaptureMetadataField>? {
    val lines = value.lines().map(String::trim).filter(String::isNotEmpty)
    if (lines.size > 16) return null
    val fields = lines.map { line ->
        val split = line.indexOf('=').takeIf { it > 0 } ?: line.indexOf(':')
        if (split !in 1 until line.length) return null
        val name = line.substring(0, split).trim()
        val fieldValue = line.substring(split + 1)
        if (!name.matches(Regex("^[A-Za-z0-9_-]{1,64}$")) || fieldValue.length > 512) return null
        CaptureMetadataField(name, fieldValue)
    }
    return fields.takeIf { items -> items.map { it.name.lowercase() }.distinct().size == items.size }
}

private val PRESET_SYMBOLS = listOf("description", "mic", "checklist", "lightbulb", "work", "favorite")

private fun presetIcon(symbol: String?): ImageVector = when (symbol) {
    "mic" -> Icons.Outlined.MicNone
    "checklist" -> Icons.Outlined.CheckBox
    "lightbulb" -> Icons.Outlined.Lightbulb
    "work" -> Icons.Outlined.WorkOutline
    "favorite" -> Icons.Outlined.FavoriteBorder
    else -> Icons.Outlined.Description
}

private fun presetSymbolLabel(symbol: String): VoxUiText = when (symbol) {
    "mic" -> voxUiText("Voice")
    "checklist" -> voxUiText("Checklist")
    "lightbulb" -> voxUiText("Idea")
    "work" -> voxUiText("Work")
    "favorite" -> voxUiText("Favorite")
    else -> voxUiText("Document")
}

@Composable
internal fun SettingsScreen(
    destination: CaptureDestination,
    navigateBack: () -> Unit,
    chooseFolder: () -> Unit,
    openPresets: () -> Unit,
    openCaptureBar: () -> Unit,
    openStats: () -> Unit,
    openModels: () -> Unit,
    openRecordingQueue: () -> Unit,
    openAppLanguage: () -> Unit,
    openDebugLog: () -> Unit,
    openUpgrade: () -> Unit,
    billingState: BillingUiState,
) {
    val context = LocalContext.current
    val speechModels by remember(context) { SpeechModelManager.get(context) }.state.collectAsStateWithLifecycle()
    val keyboardPreferences = remember(context) { context.getSharedPreferences("vox-settings", android.content.Context.MODE_PRIVATE) }
    var keyboardHaptics by rememberSaveable {
        mutableStateOf(keyboardPreferences.getBoolean("keyboard-haptics", true))
    }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { VoxTopBar(VoxUiText(stringResource(R.string.settings_title)), navigateBack) },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            SettingsSection(voxUiText("Unlimited"))
            SettingsNavigationRow(
                title = if (billingState.hasUnlimitedAccess) voxUiText("Vox.md Unlimited") else voxUiText("Get Vox.md Unlimited"),
                subtitle = if (billingState.hasUnlimitedAccess) {
                    voxUiText("Unlimited is unlocked on this device.")
                } else {
                    voxUiText("Unlock unlimited local Capture and private, on-device transcription. Pay once with no subscription.")
                },
                value = billingState.formattedPrice,
                onClick = openUpgrade,
            )
            SettingsSection(voxUiText("Capture"))
            ListItem(
                headlineContent = { Text(voxString("Capture Destination")) },
                supportingContent = { Text(destination.displayName, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                leadingContent = { Icon(Icons.Outlined.FolderOpen, contentDescription = null) },
                trailingContent = { Icon(Icons.Outlined.ChevronRight, contentDescription = null) },
                colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                modifier = Modifier.clickable(onClick = chooseFolder),
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            SettingsSection(voxUiText("Activity"))
            SettingsNavigationRow(
                title = voxUiText("Stats"),
                subtitle = voxUiText("Recordings, recording time, and Capture activity"),
                icon = Icons.Outlined.BarChart,
                onClick = openStats,
            )
            SettingsSection(voxUiText("Recordings"))
            SettingsNavigationRow(
                title = voxUiText("Recordings"),
                subtitle = voxUiText("Recover, export, and manage durable audio"),
                icon = Icons.Outlined.GraphicEq,
                onClick = openRecordingQueue,
            )
            SettingsSection(voxUiText("Customization"))
            SettingsNavigationRow(
                title = voxUiText("Models"),
                subtitle = voxUiText("Transcription engines, model downloads, and language"),
                icon = Icons.Outlined.Memory,
                onClick = openModels,
            )
            SettingsNavigationRow(
                title = voxUiText("Capture Presets"),
                subtitle = voxUiText("Processing, formatting, metadata, and destinations"),
                icon = Icons.Outlined.Tune,
                onClick = openPresets,
            )
            SettingsNavigationRow(
                title = voxUiText("Capture Bar"),
                subtitle = voxUiText("Choose, reorder, and hide quick actions"),
                icon = Icons.Outlined.Dashboard,
                onClick = openCaptureBar,
            )
            SettingsNavigationRow(
                title = VoxUiText(stringResource(R.string.app_language_title)),
                subtitle = VoxUiText(stringResource(R.string.app_language_choose)),
                icon = Icons.Outlined.Language,
                value = AppLanguage.current().let { language ->
                    if (language == AppLanguage.SYSTEM) stringResource(R.string.system_language_short) else language.nativeDisplayName
                },
                onClick = openAppLanguage,
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            SettingsSection(voxUiText("Keyboard"))
            SettingsActionRow(voxUiText("Set Up Vox.md Keyboard")) { openInputMethodSettings(context) }
            ListItem(
                headlineContent = { Text(voxString("Haptic Feedback")) },
                supportingContent = { Text(voxString("Vibrate on key press")) },
                trailingContent = {
                    Switch(
                        checked = keyboardHaptics,
                        onCheckedChange = { enabled ->
                            keyboardHaptics = enabled
                            keyboardPreferences.edit().putBoolean("keyboard-haptics", enabled).apply()
                        },
                    )
                },
                colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            SettingsSection(voxUiText("About"))
            SettingsValueRow(
                voxUiText("Default transcription"),
                speechModels.selectedReadyModel?.descriptor?.let {
                    if (speechModels.selectionMode == SpeechModelSelectionMode.AUTOMATIC) {
                        voxFormat("%@ · %@ · local %@", voxString("Automatic"), it.displayName, it.engine.displayName)
                    } else {
                        voxFormat("%@ · local %@", it.displayName, it.engine.displayName)
                    }
                }
                    ?: voxString("Android Speech when explicitly on-device"),
            )
            SettingsValueRow(voxUiText("Audio capture"), voxString("On-device"))
            SettingsValueRow(voxUiText("Processing"), voxString("On-device"))
            SettingsValueRow(voxUiText("Privacy"), voxString("Voice/text stay local"))
            SettingsValueRow(voxUiText("Version"), appVersionString(context))
            Text(voxString("Capture contents stay on this device until Vox.md writes them to the folder you selected. Android backup is disabled for content-bearing storage."),
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            SettingsSection(voxUiText("Feedback"))
            SettingsActionRow(voxUiText("Join Our Discord")) { openDiscord(context) }
            SettingsActionRow(voxUiText("Send Feedback")) { sendFeedback(context) }
            SettingsSection(voxUiText("Debug"))
            SettingsNavigationRow(
                title = voxUiText("View Debug Log"),
                subtitle = voxUiText("Content-free operational events stored only on this device"),
                onClick = openDebugLog,
            )
        }
    }
}

@Composable
private fun StatsScreen(stats: ActivityStats, navigateBack: () -> Unit) {
    val locale = LocalConfiguration.current.locales[0] ?: Locale.ENGLISH
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { VoxTopBar(voxUiText("Stats"), navigateBack) },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(voxString("Lifetime on-device activity calculated from a content-free local ledger."),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatCard(voxUiText("Recordings"), stats.recordingCount.toString(), Modifier.weight(1f))
                StatCard(voxUiText("Captures"), stats.captureCount.toString(), Modifier.weight(1f))
            }
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                StatCard(voxUiText("Recorded duration"), formatActivityDuration(stats.recordedDurationMillis), Modifier.weight(1f))
                StatCard(voxUiText("Attachments"), stats.attachmentCount.toString(), Modifier.weight(1f))
            }
            Text(voxString("Last 7 Days"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
            if (stats.lastSevenDays.isEmpty()) {
                Text(voxString("No activity yet"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            } else {
                val maximum = stats.lastSevenDays.maxOf { it.captureCount + it.recordingCount }.coerceAtLeast(1)
                stats.lastSevenDays.forEach { day ->
                    val localDate = java.time.LocalDate.ofEpochDay(day.epochDay)
                    val dayName = localDate.dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, locale)
                    val abbreviatedDayName = localDate.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, locale)
                    val dayDescription = voxFormat(
                        "%@: %@",
                        dayName,
                        voxFormat("%lld recordings, %lld captures", day.recordingCount, day.captureCount),
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth().semantics {
                            contentDescription = dayDescription
                        },
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                    ) {
                        Text(
                            abbreviatedDayName,
                            modifier = Modifier.width(36.dp),
                            style = MaterialTheme.typography.labelMedium,
                        )
                        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                            LinearProgressIndicator(
                                progress = { day.recordingCount.toFloat() / maximum },
                                modifier = Modifier.fillMaxWidth().height(6.dp),
                                color = MaterialTheme.colorScheme.primary,
                            )
                            LinearProgressIndicator(
                                progress = { day.captureCount.toFloat() / maximum },
                                modifier = Modifier.fillMaxWidth().height(6.dp),
                                color = if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.GreenDark else VoxColors.Green,
                            )
                        }
                        Text(voxFormat("%lld recordings · %lld captures", day.recordingCount, day.captureCount),
                            modifier = Modifier.width(48.dp),
                            style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily),
                        )
                    }
                }
            }
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.padding(vertical = 4.dp)) {
                Text(voxString("● Recordings"), color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.labelMedium)
                Text(voxString("● Captures"),
                    color = if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.GreenDark else VoxColors.Green,
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            Text(voxString("Capture Sources"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.padding(top = 12.dp))
            if (stats.captureSources.isEmpty()) {
                Text(voxString("No delivered captures yet"), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            stats.captureSources.forEach { (source, count) ->
                Row(modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(statsSourceUiText(source).localized(), modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
                    Text(count.toString(), style = MaterialTheme.typography.labelLarge.copy(fontFamily = GeistMonoFontFamily))
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            }
            Text(voxString("No captured content, filenames, or destinations are stored with stats."),
                modifier = Modifier.padding(top = 12.dp),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

private fun formatActivityDuration(milliseconds: Long): String {
    val minutes = milliseconds.coerceAtLeast(0) / 60_000
    return if (minutes < 60) "${minutes}m" else "${minutes / 60}h ${minutes % 60}m"
}

private fun statsSourceUiText(source: String): VoxUiText = captureSourceUiText(source)

@Composable
private fun StatCard(title: VoxUiText, value: String, modifier: Modifier = Modifier) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(value, style = MaterialTheme.typography.headlineSmall.copy(fontFamily = GeistMonoFontFamily))
            Text(title.localized(), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
internal fun CaptureBarSettingsScreen(
    configuration: CaptureBarConfiguration,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    setVisible: (CaptureBarAction, Boolean) -> Unit,
    move: (CaptureBarAction, Int) -> Unit,
    setTwentyFourHour: (Boolean) -> Unit,
    setVoiceConfirmation: (Boolean) -> Unit,
    setVoiceRecordingResult: (VoiceRecordingResult) -> Unit = {},
    reset: () -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { VoxTopBar(voxUiText("Capture Bar"), navigateBack) },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(bottom = 32.dp),
        ) {
            item {
                Text(voxString("Choose which actions appear below Capture. Move actions into the order that works for you."),
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            items(configuration.orderedActions, key = CaptureBarAction::persistedName) { action ->
                val index = configuration.orderedActions.indexOf(action)
                val actionLabel = captureBarActionUiText(action).localized()
                val showDescription = voxFormat("%@: %@", voxString("Show"), actionLabel)
                ListItem(
                    headlineContent = { Text(actionLabel) },
                    leadingContent = {
                        Switch(
                            checked = action !in configuration.hiddenActions,
                            onCheckedChange = { setVisible(action, it) },
                            enabled = !isBusy,
                            modifier = Modifier.semantics {
                                contentDescription = showDescription
                            },
                        )
                    },
                    trailingContent = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            IconButton(onClick = { move(action, -1) }, enabled = !isBusy && index > 0) {
                                Icon(Icons.Outlined.KeyboardArrowUp, contentDescription = voxFormat("%@: %@", voxString("Move Up"), actionLabel))
                            }
                            IconButton(
                                onClick = { move(action, 1) },
                                enabled = !isBusy && index < configuration.orderedActions.lastIndex,
                            ) {
                                Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = voxFormat("%@: %@", voxString("Move Down"), actionLabel))
                            }
                        }
                    },
                    colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            }
            item {
                SettingsSection(voxUiText("Timestamp"))
                ListItem(
                    headlineContent = { Text(voxString("24-hour timestamps")) },
                    supportingContent = { Text(voxString("Off uses the iOS-compatible 12-hour format with AM or PM.")) },
                    trailingContent = {
                        Switch(
                            checked = configuration.usesTwentyFourHourTimestamps,
                            onCheckedChange = setTwentyFourHour,
                            enabled = !isBusy,
                        )
                    },
                    colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                ListItem(
                    headlineContent = { Text(voxString("Review Before Adding")) },
                    supportingContent = {
                        Text(voxString("Off adds a finished voice transcript to the draft automatically. Turn this on to review it first."))
                    },
                    trailingContent = {
                        val description = voxString("Review Before Adding")
                        Switch(
                            checked = configuration.confirmsVoiceNotesBeforeAdding,
                            onCheckedChange = setVoiceConfirmation,
                            enabled = !isBusy,
                            modifier = Modifier.semantics { contentDescription = description },
                        )
                    },
                    colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                SettingsSection(voxUiText("Recording Result"))
                ListItem(
                    headlineContent = { Text(voxString("Add to Draft")) },
                    supportingContent = {
                        Text(voxString("A finished voice transcript lands in the composer, ready to review before sending."))
                    },
                    leadingContent = {
                        RadioButton(
                            selected = configuration.voiceRecordingResult == VoiceRecordingResult.ADD_TO_DRAFT,
                            onClick = { setVoiceRecordingResult(VoiceRecordingResult.ADD_TO_DRAFT) },
                            enabled = !isBusy,
                        )
                    },
                    colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                )
                ListItem(
                    headlineContent = { Text(voxString("Send Immediately")) },
                    supportingContent = {
                        Text(voxString("A finished voice transcript is sent straight to the active preset without stopping in the composer."))
                    },
                    leadingContent = {
                        RadioButton(
                            selected = configuration.voiceRecordingResult == VoiceRecordingResult.SEND_IMMEDIATELY,
                            onClick = { setVoiceRecordingResult(VoiceRecordingResult.SEND_IMMEDIATELY) },
                            enabled = !isBusy,
                        )
                    },
                    colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                )
                HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                TextButton(
                    onClick = reset,
                    enabled = !isBusy,
                    modifier = Modifier.padding(horizontal = 8.dp, vertical = 12.dp),
                ) { Text(voxString("Reset Capture Bar")) }
            }
        }
    }
}

private fun captureBarActionUiText(action: CaptureBarAction): VoxUiText = when (action) {
    CaptureBarAction.ADD_MEDIA -> voxUiText("Add Media")
    CaptureBarAction.ADD_FILES -> voxUiText("Add Files")
    CaptureBarAction.SCAN_DOCUMENT -> voxUiText("Scan Document")
    CaptureBarAction.EXTRACT_TEXT -> voxUiText("Extract Text")
    CaptureBarAction.UNDO -> voxUiText("Undo")
    CaptureBarAction.FORMAT_MARKDOWN -> voxUiText("Format Markdown")
    CaptureBarAction.MARKDOWN_LINK -> voxUiText("Markdown Link")
    CaptureBarAction.DUE_DATE -> voxUiText("Set Due Date")
    CaptureBarAction.CHECKLIST -> voxUiText("Checklist")
    CaptureBarAction.BULLET_LIST -> voxUiText("Bullet List")
    CaptureBarAction.PASTE -> voxUiText("Paste")
    CaptureBarAction.INTERNAL_LINK -> voxUiText("Internal Link")
    CaptureBarAction.SKETCH -> voxUiText("Sketch")
    CaptureBarAction.CURRENT_LOCATION -> voxUiText("Current Location")
    CaptureBarAction.TIMESTAMP -> voxUiText("Insert Timestamp")
    CaptureBarAction.DATE -> voxUiText("Insert Date")
    CaptureBarAction.TEXT_CASE -> voxUiText("Change Text Case")
}

@Composable
private fun SettingsNavigationRow(title: VoxUiText, subtitle: VoxUiText, value: String? = null, icon: ImageVector? = null, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title.localized()) },
        supportingContent = { Text(subtitle.localized()) },
        leadingContent = if (icon != null) {
            { Icon(icon, contentDescription = null) }
        } else {
            null
        },
        trailingContent = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (value != null) {
                    Text(value, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.width(8.dp))
                }
                Icon(Icons.Outlined.ChevronRight, contentDescription = null)
            }
        },
        colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
        modifier = Modifier.clickable(onClick = onClick),
    )
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@Composable
private fun SettingsValueRow(title: VoxUiText, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title.localized(), modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium)
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@Composable
private fun SettingsActionRow(title: VoxUiText, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 20.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title.localized(), modifier = Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Text(voxString("→"), style = MaterialTheme.typography.bodyLarge, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@Composable
private fun SettingsSection(title: VoxUiText) {
    Text(
        title.localized(),
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 28.dp, bottom = 12.dp),
        style = MaterialTheme.typography.titleMedium,
    )
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@Composable
private fun PlaceholderSettingsRow(title: VoxUiText, subtitle: VoxUiText) {
    ListItem(
        headlineContent = { Text(title.localized()) },
        supportingContent = { Text(subtitle.localized()) },
        trailingContent = {
            Text(voxString("Planned"), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        },
        colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
    )
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun VoxTopBar(title: VoxUiText, navigateBack: () -> Unit) {
    TopAppBar(
        title = { Text(title.localized(), style = MaterialTheme.typography.titleLarge) },
        navigationIcon = {
            IconButton(onClick = navigateBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = voxString("Back"))
            }
        },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
    )
}

private fun queryTreeDisplayName(context: android.content.Context, tree: Uri): String = runCatching {
    val document = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
    context.contentResolver.query(
        document,
        arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
}.getOrNull()?.takeIf { it.isNotBlank() } ?: "Markdown folder"

private fun queryDocumentDisplayName(context: android.content.Context, document: Uri): String = runCatching {
    context.contentResolver.query(
        document,
        arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
}.getOrNull()?.takeIf { it.isNotBlank() } ?: "Markdown template"

private fun Context.findActivity(): Activity? {
    var current: Context? = this
    while (current is ContextWrapper) {
        if (current is Activity) return current
        current = current.baseContext
    }
    return current as? Activity
}
