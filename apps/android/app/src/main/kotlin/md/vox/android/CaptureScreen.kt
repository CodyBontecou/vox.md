package md.vox.android

import android.Manifest
import md.vox.android.capturedomain.CaptureWebLink
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
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.material3.minimumInteractiveComponentSize
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
import androidx.compose.material.icons.outlined.Lock
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
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
import md.vox.android.ui.GeistFontFamily
import md.vox.android.ui.GeistMonoFontFamily
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalDivider
import md.vox.android.ui.SignalFieldShape
import md.vox.android.ui.SignalIconTile
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalNavRow
import md.vox.android.ui.SignalRouteTile
import md.vox.android.ui.SignalRouteTone
import md.vox.android.ui.SignalRowDivider
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalTextFieldColors
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.KeyboardHide
import androidx.compose.material.icons.outlined.LocationOff
import androidx.compose.material.icons.outlined.PhotoCamera
import androidx.compose.material.icons.outlined.Smartphone
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MenuDefaults
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.semantics.disabled
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
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

internal data class PendingLocationSubmission(
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

internal data class PendingLocationDecision(
    val submission: PendingLocationSubmission,
    val outcome: CaptureLocationOutcome.Unavailable,
)

@OptIn(ExperimentalMaterial3Api::class)
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
    onRouteChanged: (CaptureRouteOverride?) -> Unit = {},
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
    /** Phones only: Activity button in the header. Null when a navigation rail carries it. */
    openActivity: (() -> Unit)? = null,
    activityBadge: Int = 0,
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
    setVoiceRecordingResult: (md.vox.android.capturedomain.VoiceRecordingResult) -> Unit = {},
    requestEditorFocus: Boolean = true,
    initialShowsVoiceCaptureDetails: Boolean = false,
    microphoneBlocked: Boolean = false,
    hasVaultAccess: Boolean = true,
    regrantVaultAccess: (String?) -> Unit = {},
    initialShowsAttachSheet: Boolean = false,
    initialShowsAllQuickActions: Boolean = false,
    resolveLocation: (suspend (Boolean) -> CurrentLocationResult)? = null,
) {
    var editorValue by rememberSaveable(stateSaver = TextFieldValue.Saver) {
        mutableStateOf(TextFieldValue(state.draft.text, TextRange(state.draft.text.length)))
    }
    var capturedURL by rememberSaveable { mutableStateOf(state.draft.url) }
    var showsLinkDialog by rememberSaveable { mutableStateOf(false) }
    var showsDueDateDialog by rememberSaveable { mutableStateOf(false) }
    var showsAttachSheet by rememberSaveable { mutableStateOf(initialShowsAttachSheet) }
    var attachClipboardKind by remember { mutableStateOf<CaptureClipboardKind?>(null) }
    var showsSketchDialog by rememberSaveable { mutableStateOf(false) }
    var showsVoiceCaptureDetails by rememberSaveable { mutableStateOf(initialShowsVoiceCaptureDetails) }
    // The composition owns the lookup coroutine. Recreation cancels it, so its
    // busy flag must reset rather than restore a job that no longer exists.
    var isResolvingPresetLocation by remember { mutableStateOf(false) }
    val locationState = viewModel<CaptureLocationViewModel>()
    var pendingLocationSubmission by locationState.pendingSubmission
    var locationDecision by locationState.decision
    fun locationPreflightPending() = isResolvingPresetLocation ||
        pendingLocationSubmission != null || locationDecision != null
    val sendingCapture = state.isSending || locationPreflightPending()
    val canChangeCaptureRoute = !sendingCapture && !state.isSavingConfiguration
    var pendingCameraPath by rememberSaveable { mutableStateOf<String?>(null) }
    var pendingJournalCameraPath by rememberSaveable { mutableStateOf<String?>(null) }
    val undoStack = viewModel<CaptureUndoViewModel>().entries
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

    // Journal page from the camera: keep the photo, then read its text into the draft.
    val journalCameraLauncher = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { captured ->
        val file = pendingJournalCameraPath?.let(::File)
        pendingJournalCameraPath = null
        if (!captured || file == null) {
            file?.delete()
            return@rememberLauncherForActivityResult
        }
        val uri = captureImportUri(context, file)
        attach(uri.toString(), "Journal page.jpg", "image/jpeg")
        coroutineScope.launch {
            val recognized = runCatching { textRecognition.recognize(listOf(uri)) }.getOrDefault("")
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
        if (isResolvingPresetLocation) return
        // Admission must precede dispatch: another tap can arrive before a new frame.
        isResolvingPresetLocation = true
        coroutineScope.launch {
            when (val result = resolveLocation?.invoke(pending.precision == CaptureLocationPrecision.EXACT)
                ?: locationResolver.resolve(exactRequired = pending.precision == CaptureLocationPrecision.EXACT)) {
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
        if (state.isSending || locationPreflightPending()) return
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

    fun startJournalCameraCapture() {
        val file = runCatching {
            createCaptureImportFile(context, "${UUID.randomUUID().toString().lowercase(Locale.ROOT)}-journal.jpg")
        }.getOrElse {
            presentNotice(voxUiText("A camera file could not be prepared."))
            return
        }
        pendingJournalCameraPath = file.absolutePath
        journalCameraLauncher.launch(captureImportUri(context, file))
    }

    /** Attach sheet clipboard card: a copied image is attached, a copied web link becomes the capture link. */
    fun pasteFromClipboard() {
        val item = clipboard?.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0) ?: return
        val uri = item.uri
        if (uri != null && uri.scheme == "content") {
            attach(uri.toString(), mediaType = context.contentResolver.getType(uri))
            return
        }
        val text = item.coerceToText(context)?.toString()?.trim().orEmpty()
        if (text.isEmpty()) return
        val link = CaptureWebLink.normalize(text)
        if (link != null) {
            capturedURL = link
            onDraftChanged(editorValue.text, link)
        } else {
            applyCommand(CaptureComposerCommand.ReplaceSelection(text))
        }
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

    // The composer takes focus once when Capture first opens and again when a recording
    // ends. Coming back from Activity, Library, Settings or Routes keeps the keyboard down
    // so the header's Activity and Settings stay visible (Signal Capture board).
    var initialEditorFocusDone by rememberSaveable { mutableStateOf(false) }
    var wasRecording by remember { mutableStateOf(recordingStatus.isActive) }
    LaunchedEffect(requestEditorFocus, recordingStatus.isActive) {
        val recordingJustEnded = wasRecording && !recordingStatus.isActive
        wasRecording = recordingStatus.isActive
        if (recordingStatus.isActive) {
            focusManager.clearFocus()
            keyboardController?.hide()
        } else if (requestEditorFocus && (!initialEditorFocusDone || recordingJustEnded)) {
            initialEditorFocusDone = true
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
    var showsShareSheet by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.pendingExternalDraftID) {
        if (state.pendingExternalDraftID != null) {
            editorValue = TextFieldValue(state.draft.text, TextRange(state.draft.text.length))
            capturedURL = state.draft.url
            undoStack.clear()
            if (state.draft.captureSource == "share") showsShareSheet = true
            consumeExternalDraft()
        }
    }

    if (showsShareSheet) {
        ShareCaptureSheet(
            sharedText = editorValue.text,
            sharedURL = capturedURL,
            attachmentCount = state.draft.attachments.size,
            presets = state.presetCollection?.presets.orEmpty(),
            activePresetID = state.presetCollection?.activePreset?.id,
            isSending = sendingCapture,
            selectPreset = onSelectPreset,
            send = { note ->
                val combined = listOf(editorValue.text.trim(), note).filter(String::isNotBlank).joinToString("\n\n")
                showsShareSheet = false
                submitCapture(combined, capturedURL)
            },
            dismiss = { showsShareSheet = false },
        )
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
    if (showsAttachSheet) {
        DisposableEffect(clipboard) {
            attachClipboardKind = detectCaptureClipboardKind(clipboard)
            val listener = ClipboardManager.OnPrimaryClipChangedListener {
                attachClipboardKind = detectCaptureClipboardKind(clipboard)
            }
            clipboard?.addPrimaryClipChangedListener(listener)
            onDispose { clipboard?.removePrimaryClipChangedListener(listener) }
        }
        val sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true)
        // Tools launch after the sheet has hidden so the next activity never races it.
        fun closeThen(action: () -> Unit) {
            coroutineScope.launch {
                runCatching { sheetState.hide() }
                showsAttachSheet = false
                action()
            }
        }
        CaptureAttachSheet(
            destinationLine = captureDestinationLine(
                state.draft.frozenPreset ?: state.presetCollection?.activePreset,
                state.draft.routeOverride,
            ),
            clipboard = attachClipboardKind,
            isBusy = sendingCapture,
            onDismiss = { showsAttachSheet = false },
            paste = { closeThen(::pasteFromClipboard) },
            choosePhotos = {
                closeThen {
                    photoPicker.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
            },
            scanDocument = { closeThen(::startDocumentScan) },
            captureJournalPages = { closeThen(::startJournalCameraCapture) },
            chooseJournalPhotos = {
                closeThen {
                    ocrPicker.launch(androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
            },
            choose = { tool ->
                closeThen {
                    when (tool) {
                        CaptureAttachTool.CAMERA -> startCameraCapture()
                        CaptureAttachTool.FILE -> filePicker.launch(arrayOf("*/*"))
                        CaptureAttachTool.SKETCH -> showsSketchDialog = true
                        CaptureAttachTool.LINK -> showsLinkDialog = true
                        CaptureAttachTool.LOCATION -> addCurrentLocation()
                        CaptureAttachTool.SCREENSHOT -> screenshotPicker.launch(
                            androidx.activity.result.PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly),
                        )
                    }
                }
            },
            sheetState = sheetState,
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
    val composerPlaceholder = if (microphoneBlocked) {
        voxString("Type, paste or attach — or turn on the microphone to speak.")
    } else {
        (state.draft.frozenPreset ?: state.presetCollection?.activePreset)?.capturePrompt?.trim()?.takeIf(String::isNotEmpty)
            ?: voxString("Start typing, speak, or tap an action below")
    }
    val activePreset = state.draft.frozenPreset ?: state.presetCollection?.activePreset
    val routeDestination = activePreset?.destination ?: state.destination
    val vaultUnreachable = state.destination != null && captureVaultIsUnreachable(state.history, hasVaultAccess)
    val waitingCount = captureWaitingCount(state.history)
    val c = Signal.colors
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxSize()) {
    val compactHeight = maxWidth >= 600.dp && maxHeight < 480.dp
    Scaffold(
        // While the full-screen live recording covers the composer, the covered
        // composer (and its inline recording card) must not be read, announced or
        // targeted by TalkBack and Switch Access a second time.
        modifier = if (recordingStatus.isActive) Modifier.clearAndSetSemantics {} else Modifier,
        containerColor = c.bg,
        topBar = {
            CaptureTopControls(
                compactHeight = compactHeight,
                preset = state.presetCollection?.activePreset,
                destination = routeDestination,
                route = state.draft.routeOverride,
                onRouteChanged = { if (!state.isSending && !locationPreflightPending()) onRouteChanged(it) },
                canChangeRoute = canChangeCaptureRoute,
                hasPinnedAlternates = pinnedPresets.isNotEmpty(),
                isPresetRailExpanded = isPresetRailExpanded,
                togglePresetRail = togglePresetRail,
                openPresets = openPresets,
                openHistory = openHistory,
                openSettings = openSettings,
                openActivity = openActivity,
                activityBadge = activityBadge,
                hideKeyboard = {
                    focusManager.clearFocus()
                    keyboardController?.hide()
                },
            )
        },
        bottomBar = {
            CaptureBottomControls(
                compactHeight = compactHeight,
                // The route being typed into shows its own quick actions when it has them.
                captureBar = state.captureBar.forRoute(activePreset?.id),
                hasContent = editorValue.text.isNotBlank() || capturedURL != null || state.draft.attachments.isNotEmpty(),
                isSending = sendingCapture,
                onSubmit = { submitCapture(editorValue.text, capturedURL) },
                toggleKeyboard = {
                    focusManager.clearFocus()
                    keyboardController?.hide()
                },
                addLink = { showsLinkDialog = true },
                addMedia = {
                    focusManager.clearFocus()
                    keyboardController?.hide()
                    showsAttachSheet = true
                },
                microphoneBlocked = microphoneBlocked,
                openMicrophoneSettings = { openAppDetailsSettings(context) },
                waitingLine = if (vaultUnreachable && waitingCount > 0) captureWaitingLine(waitingCount) else null,
                initialShowsAllQuickActions = initialShowsAllQuickActions,
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
        CaptureWorkspace(
            text = editorValue.text,
            preset = activePreset,
            destination = routeDestination,
            route = state.draft.routeOverride,
            attachmentCount = state.draft.attachments.size,
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = SignalMetrics.PageGutter)
                .padding(top = 4.dp, bottom = 8.dp),
        ) {
            if (vaultUnreachable) {
                CaptureVaultUnreachableBanner(
                    regrantAccess = {
                        regrantVaultAccess(state.history.firstOrNull { it.state == CaptureState.NEEDS_PERMISSION }?.requestID)
                    },
                    modifier = Modifier.padding(bottom = 12.dp),
                )
            }
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
                        .then(if (isPresetRailExpanded && pinnedPresets.isNotEmpty()) {
                            if (state.captureBar.railSide == CaptureRailSide.LEFT) Modifier.absolutePadding(left = 60.dp) else Modifier.absolutePadding(right = 60.dp)
                        } else Modifier)
                        .testTag("capture-editor")
                        .semantics { contentDescription = captureTextDescription },
                    textStyle = TextStyle(
                        color = c.text,
                        fontFamily = GeistFontFamily,
                        fontSize = 18.sp,
                        lineHeight = 27.sp,
                    ),
                    cursorBrush = SolidColor(c.tint),
                    decorationBox = { inner ->
                        Box(Modifier.fillMaxSize().padding(top = 8.dp)) {
                            if (editorValue.text.isEmpty()) {
                                // CaptureRestActions board: a quiet prompt at the caret, the
                                // route's own capture prompt, or microphone-off guidance.
                                Text(
                                    composerPlaceholder,
                                    color = c.faint,
                                    style = TextStyle(fontFamily = GeistFontFamily, fontSize = 18.sp, lineHeight = 27.sp),
                                    modifier = Modifier.clearAndSetSemantics {},
                                )
                            }
                            inner()
                        }
                    },
                )
                CapturePresetQuickAccessRail(
                    presets = pinnedPresets,
                    isExpanded = isPresetRailExpanded,
                    canSelectPreset = canChangeCaptureRoute,
                    selectPreset = { if (!state.isSending && !locationPreflightPending()) onSelectPreset(it) },
                    modifier = Modifier.align(if (state.captureBar.railSide == CaptureRailSide.LEFT) AbsoluteAlignment.BottomLeft else AbsoluteAlignment.BottomRight),
                )
            }
            if (capturedURL != null) {
                Spacer(Modifier.height(10.dp))
                LinkAttachment(
                    url = requireNotNull(capturedURL),
                    remove = {
                        capturedURL = null
                        onDraftChanged(editorValue.text, null)
                    },
                )
            }
            if (state.draft.attachments.isNotEmpty()) {
                Spacer(Modifier.height(10.dp))
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
    if (recordingStatus.isActive) {
        LiveRecordingScreen(
            preset = recordingStatus.sessionID?.let(frozenRecordingPreset) ?: activePreset,
            status = recordingStatus,
            liveSpeech = liveSpeech,
            recordingResult = state.captureBar.voiceRecordingResult,
            setRecordingResult = setVoiceRecordingResult,
            pause = pauseRecording,
            resume = resumeRecording,
            stop = stopRecording,
            cancel = cancelRecording,
        )
    }
    }
}

/**
 * Capture header (Signal Capture board): the preset selector as a 40dp pill (route
 * tile, preset name, chevron), then on the trailing edge Activity and Settings on
 * phones, or the on-device indicator when a navigation rail carries them, and Done
 * while the keyboard is open; the mono route line sits underneath. The selector keeps
 * Android's preset semantics: tap toggles the pinned rail when pins exist,
 * long-press always opens all presets. Library is reached from Activity on phones.
 */
@OptIn(ExperimentalFoundationApi::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
internal fun CaptureTopControls(
    preset: CapturePreset?,
    destination: CaptureDestination?,
    route: CaptureRouteOverride?,
    onRouteChanged: (CaptureRouteOverride?) -> Unit,
    hasPinnedAlternates: Boolean,
    isPresetRailExpanded: Boolean,
    togglePresetRail: () -> Unit,
    openPresets: () -> Unit,
    openHistory: () -> Unit,
    openSettings: () -> Unit,
    hideKeyboard: () -> Unit = {},
    compactHeight: Boolean = false,
    canChangeRoute: Boolean = true,
    /** Phones only: opens Activity from the header. Null when a navigation rail carries it. */
    openActivity: (() -> Unit)? = null,
    activityBadge: Int = 0,
) {
    val routeEditor = rememberCaptureRouteEditorState()
    val c = Signal.colors
    val expandsRail = hasPinnedAlternates
    val selectorClickLabel = voxString(
        if (isPresetRailExpanded) "Hide pinned capture presets" else "Show pinned capture presets",
    )
    val chooseLabel = voxString("Choose Route")
    val railOpen = expandsRail && isPresetRailExpanded
    val selectorDescription = if (expandsRail) selectorClickLabel else chooseLabel
    val imeVisible = androidx.compose.foundation.layout.WindowInsets.isImeVisible
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(c.bg)
            .statusBarsPadding(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = if (compactHeight) 48.dp else 64.dp)
                .padding(start = 12.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Box(Modifier.weight(1f)) {
                Row(
                    modifier = Modifier
                        .heightIn(min = 40.dp)
                        .clip(CircleShape)
                        .background(if (railOpen) c.accentSoft else c.card)
                        .border(1.dp, if (railOpen) c.tint else c.border, CircleShape)
                        .combinedClickable(
                            enabled = canChangeRoute,
                            role = Role.Button,
                            onClickLabel = if (expandsRail) selectorClickLabel else null,
                            onLongClickLabel = chooseLabel,
                            onClick = { if (expandsRail) togglePresetRail() else openPresets() },
                            onLongClick = openPresets,
                        )
                        .testTag("capture-preset-selector")
                        .padding(start = 4.dp, end = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    SignalRouteTile(
                        label = preset?.emoji ?: preset?.name ?: "Default",
                        size = 32.dp,
                        tone = SignalRouteTone.PRIMARY,
                        circular = true,
                    )
                    Text(
                        preset?.name ?: "Default",
                        style = MaterialTheme.typography.labelMedium,
                        color = if (railOpen) c.accentText else c.text,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    Icon(
                        if (railOpen) Icons.Outlined.KeyboardArrowUp else Icons.Outlined.KeyboardArrowDown,
                        contentDescription = selectorDescription,
                        modifier = Modifier.size(18.dp),
                        tint = if (railOpen) c.accentText else c.secondaryText,
                    )
                }
            }
            if (compactHeight) {
                Box(Modifier.widthIn(max = 240.dp)) {
                    CaptureRouteControl(route = route, destination = destination, enabled = canChangeRoute, editor = routeEditor, onChanged = onRouteChanged)
                }
            }
            if (imeVisible) {
                androidx.compose.material3.TextButton(onClick = hideKeyboard) {
                    Text(voxString("Done"), style = MaterialTheme.typography.labelMedium, color = c.tint)
                }
            } else if (openActivity != null) {
                val activityLabel = voxString("Activity")
                val activityDescription = if (activityBadge > 0) {
                    voxFormat("%@ · %@", activityLabel, activityBadge.toString())
                } else activityLabel
                Box {
                    SignalCircleButton(
                        icon = Icons.Outlined.Schedule,
                        contentDescription = activityDescription,
                        onClick = openActivity,
                        modifier = Modifier.testTag("capture-activity"),
                    )
                    if (activityBadge > 0) {
                        Box(
                            Modifier
                                .align(Alignment.TopEnd)
                                .padding(top = 10.dp, end = 10.dp)
                                .size(8.dp)
                                .clip(CircleShape)
                                .background(c.warning),
                        )
                    }
                }
                SignalCircleButton(
                    icon = Icons.Outlined.Settings,
                    contentDescription = voxString("Settings"),
                    onClick = openSettings,
                    modifier = Modifier.testTag("capture-settings"),
                )
            } else {
                Row(
                    modifier = Modifier.heightIn(min = 32.dp).padding(horizontal = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Icon(Icons.Outlined.Lock, contentDescription = null, tint = c.muted, modifier = Modifier.size(14.dp))
                    Text(voxString("On-device"), style = MaterialTheme.typography.labelSmall, color = c.muted, maxLines = 1)
                }
            }
        }
        if (!compactHeight) Box(Modifier.padding(horizontal = 16.dp)) {
            CaptureRouteControl(
                route = route,
                destination = destination,
                enabled = canChangeRoute,
                editor = routeEditor,
                onChanged = onRouteChanged,
            )
        }
    }
}

/** Material dialog chrome matched to Signal: white card, hairline-free, 22dp radius. */
@Composable
internal fun CaptureSignalDialog(
    onDismissRequest: () -> Unit,
    title: String,
    confirmButton: @Composable () -> Unit,
    dismissButton: (@Composable () -> Unit)? = null,
    text: @Composable () -> Unit,
) {
    val c = Signal.colors
    AlertDialog(
        onDismissRequest = onDismissRequest,
        containerColor = c.card,
        shape = RoundedCornerShape(SignalMetrics.CardRadius + 4.dp),
        tonalElevation = 0.dp,
        title = { Text(title, style = MaterialTheme.typography.titleLarge, color = c.text) },
        text = text,
        confirmButton = confirmButton,
        dismissButton = dismissButton,
    )
}

/** Bordered row group inside a dialog (the dialog itself is already a white card). */
@Composable
internal fun CaptureDialogGroup(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    val c = Signal.colors
    val shape = RoundedCornerShape(SignalMetrics.GroupRadius)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.bg)
            .border(1.dp, c.border, shape),
        content = content,
    )
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
    val c = Signal.colors
    CaptureSignalDialog(
        onDismissRequest = cancel,
        title = voxString("Location unavailable"),
        confirmButton = {
            Column(
                modifier = Modifier.fillMaxWidth(),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SignalButton(voxString("Retry"), onClick = retry, size = SignalButtonSize.MEDIUM, icon = Icons.Outlined.Refresh, fillWidth = true)
                SignalButton(
                    voxString("Send Without Location"),
                    onClick = sendWithoutLocation,
                    variant = SignalButtonVariant.SECONDARY,
                    size = SignalButtonSize.MEDIUM,
                    fillWidth = true,
                )
                SignalButton(
                    voxString("Always Send Without Location"),
                    onClick = alwaysSendWithoutLocation,
                    variant = SignalButtonVariant.SECONDARY,
                    size = SignalButtonSize.MEDIUM,
                    enabled = canPersistPreference,
                    fillWidth = true,
                )
                SignalButton(
                    voxString("Cancel"),
                    onClick = cancel,
                    variant = SignalButtonVariant.TERTIARY,
                    size = SignalButtonSize.MEDIUM,
                    fillWidth = true,
                )
            }
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(SignalMetrics.FieldRadius))
                    .background(c.warningSoft)
                    .padding(horizontal = 14.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                Icon(Icons.Outlined.LocationOff, contentDescription = null, tint = c.warningText, modifier = Modifier.size(18.dp))
                Text(locationUnavailableUiText(reason).localized(), style = SignalType.caption, color = c.text)
            }
            Text(
                voxString("Retry, send this capture without location, or cancel. No new location is requested after the capture is queued."),
                style = SignalType.caption,
                color = c.muted,
            )
        }
    }
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
            .widthIn(min = 52.dp)
            .heightIn(max = 340.dp)
            .verticalScroll(scrollState)
            .padding(vertical = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        presets.forEachIndexed { index, preset ->
            // The active route (indigo) lives in the selector; the rail continues
            // the iOS order with the next route in ink and the rest neutral.
            CapturePresetQuickAccessButton(
                preset,
                enabled = canSelectPreset,
                tone = SignalRouteTone.forIndex(index + 1),
            ) { selectPreset(preset.id) }
        }
    }
}

@Composable
internal fun CapturePresetQuickAccessButton(
    preset: CapturePreset,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    CapturePresetQuickAccessButton(preset, enabled, SignalRouteTone.NEUTRAL, onClick)
}

/** Rail button: a bordered 52dp card holding the preset's route tile. */
@Composable
internal fun CapturePresetQuickAccessButton(
    preset: CapturePreset,
    enabled: Boolean,
    tone: SignalRouteTone,
    onClick: () -> Unit,
) {
    val c = Signal.colors
    val presetDescription = voxFormat("Capture Preset %@", preset.name)
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier = Modifier
            .padding(vertical = 3.dp)
            .size(52.dp)
            .clip(shape)
            .background(c.card)
            .border(1.dp, c.border, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .testTag("capture-preset-rail-${preset.id}")
            .semantics { contentDescription = presetDescription }
            .alpha(if (enabled) 1f else 0.45f),
        contentAlignment = Alignment.Center,
    ) {
        SignalRouteTile(
            label = preset.emoji ?: preset.name,
            size = 36.dp,
            tone = tone,
        )
    }
}

/**
 * Signal composer dock (iOS QuickCaptureView): optional recording sheet, the
 * configurable Markdown toolbar, then a row with a circular utility button
 * (hide keyboard, or pause/resume while recording), the wide ink "speak" capsule
 * and the circular indigo Send button.
 */
@OptIn(ExperimentalFoundationApi::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
@Composable
internal fun CaptureBottomControls(
    captureBar: CaptureBarConfiguration,
    hasContent: Boolean,
    isSending: Boolean,
    onSubmit: () -> Unit,
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
    microphoneBlocked: Boolean = false,
    openMicrophoneSettings: () -> Unit = {},
    waitingLine: String? = null,
    initialShowsAllQuickActions: Boolean = false,
    compactHeight: Boolean = false,
) {
    val c = Signal.colors
    var showsAllQuickActions by rememberSaveable { mutableStateOf(initialShowsAllQuickActions) }
    BackHandler(enabled = showsAllQuickActions) { showsAllQuickActions = false }
    val imeVisible = androidx.compose.foundation.layout.WindowInsets.isImeVisible
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
    val isPaused = recordingStatus.phase == RecordingPhase.PAUSED
    val pauseDescription = voxString(if (isPaused) "Resume recording" else "Pause recording")
    val handleVoiceClick = {
        when {
            recordingStatus.isActive -> stopRecording()
            recordingIsProcessing || recordingNeedsAttention -> toggleVoiceCaptureDetails()
            else -> startRecording()
        }
    }
    val voiceIdle = !recordingStatus.isActive && !recordingIsProcessing && !recordingNeedsAttention
    // Microphone permanently off: Speak rests disabled under the "Open Settings" card.
    val speakEnabled = !isSending && !(microphoneBlocked && voiceIdle)
    val actionItem: @Composable (CaptureBarAction) -> Unit = { action ->
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
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(c.bg)
            .imePadding(),
    ) {
        // The full-screen live recording supersedes the inline card while it is active.
        if (showsVoiceCaptureDetails && !recordingStatus.isActive) {
            RecordingDetails(
                modifier = Modifier
                    .padding(horizontal = SignalMetrics.PageGutter, vertical = 4.dp)
                    .heightIn(max = LocalConfiguration.current.screenHeightDp.dp * 0.42f),
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
        // The route's pinned quick actions, then "•••" for every action (CaptureRestActions).
        // While typing the row becomes a grey band (CaptureKeyboard) with a keyboard-down
        // button; Attach / Speak / Send stay underneath it.
        val typing = imeVisible && !recordingStatus.isActive
        if (typing) HorizontalDivider(thickness = 1.dp, color = c.border)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .then(if (typing) Modifier.background(c.well) else Modifier)
                .height(56.dp)
                .padding(end = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            LazyRow(
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                items(captureBar.visibleActions, key = CaptureBarAction::persistedName) { action ->
                    actionItem(action)
                }
            }
            if (captureBar.visibleActions.isNotEmpty()) {
                Box(Modifier.padding(horizontal = 4.dp).width(1.dp).height(24.dp).background(c.border))
            }
            CaptureAllQuickActionsButton(
                expanded = showsAllQuickActions,
                onClick = {
                    if (!showsAllQuickActions) toggleKeyboard()
                    showsAllQuickActions = !showsAllQuickActions
                },
            )
            if (typing) {
                IconButton(onClick = toggleKeyboard, modifier = Modifier.testTag("capture-hide-keyboard")) {
                    Icon(Icons.Outlined.KeyboardHide, contentDescription = voxString("Hide keyboard"), tint = c.text)
                }
            }
        }
        if (showsAllQuickActions) {
            CaptureAllQuickActionsPanel(
                close = { showsAllQuickActions = false },
                modifier = Modifier.navigationBarsPadding(),
                item = actionItem,
            )
            return@Column
        }
        if (microphoneBlocked && voiceIdle && !imeVisible) {
            CaptureMicrophoneOffCard(
                openSettings = openMicrophoneSettings,
                modifier = Modifier.padding(horizontal = SignalMetrics.PageGutter, vertical = 4.dp),
            )
        }
        if (!imeVisible && !recordingStatus.isActive && (waitingLine != null || (!compactHeight && !microphoneBlocked))) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = SignalMetrics.PageGutter),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    waitingLine ?: voxString("Tap to record"),
                    style = SignalType.caption.copy(fontSize = 13.sp),
                    color = c.muted,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.weight(1f, fill = false),
                )
                if (waitingLine == null) {
                    val optionsDescription = voxString("Show detailed recording controls")
                    IconButton(
                        onClick = toggleVoiceCaptureDetails,
                        modifier = Modifier
                            .size(40.dp)
                            .testTag("capture-recording-options")
                            .semantics { contentDescription = optionsDescription },
                    ) {
                        Icon(Icons.Outlined.Tune, contentDescription = null, tint = c.muted, modifier = Modifier.size(16.dp))
                    }
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(start = SignalMetrics.PageGutter, end = SignalMetrics.PageGutter, top = 4.dp, bottom = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            val actionShape = RoundedCornerShape(SignalMetrics.ActionRadius)
            if (recordingStatus.isActive) {
                SignalCircleButton(
                    icon = if (isPaused) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                    contentDescription = pauseDescription,
                    onClick = if (isPaused) resumeRecording else pauseRecording,
                    diameter = 56.dp,
                    filled = if (isPaused) c.accent else c.text,
                    contentColor = if (isPaused) c.onAccent else c.bg,
                    enabled = !isSending,
                )
            } else {
                // Add media (Attach on the Signal board): 56dp white bordered circle.
                val addMediaDescription = voxString("Add media")
                Box(
                    modifier = Modifier
                        .size(56.dp)
                        .clip(actionShape)
                        .background(c.card)
                        .border(1.dp, c.border, actionShape)
                        .clickable(enabled = !isSending, role = Role.Button, onClick = addMedia)
                        .testTag("capture-add-media")
                        .semantics { contentDescription = addMediaDescription },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Outlined.Add, contentDescription = null, tint = c.text, modifier = Modifier.size(24.dp))
                }
            }
            val (capsuleFill, capsuleContent) = when {
                !speakEnabled -> c.well to c.faint
                recordingStatus.phase == RecordingPhase.RECORDING -> c.recording to c.onRecording
                isPaused -> c.text to c.bg
                recordingIsProcessing -> c.well to c.text
                recordingTranscription?.phase == RecordingTranscriptionPhase.COMPLETED && !recordingTranscription.addedToDraft ->
                    c.successSoft to c.successText
                recordingStatus.phase == RecordingPhase.COMPLETED && recordingTranscription == null -> c.accentSoft to c.accentText
                recordingNeedsAttention -> c.errorSoft to c.errorText
                else -> c.text to c.bg
            }
            // Speak: the 64dp ink capsule from the Signal Capture board.
            val speakShape = CircleShape
            // On tablets and unfolded foldables the voice FAB also lives in the rail, so
            // Speak keeps a phone-like width instead of spanning the whole composer.
            val wideComposer = LocalConfiguration.current.screenWidthDp >= 600
            val detailsLabel = voxString("Show detailed recording controls")
            Box(
                modifier = Modifier
                    .then(if (wideComposer) Modifier.widthIn(min = 200.dp, max = 360.dp) else Modifier.weight(1f))
                    .height(if (compactHeight) 48.dp else SignalMetrics.ControlHero)
                    .clip(speakShape)
                    .background(capsuleFill)
                    // Tap starts and stops recording; long-press opens the detailed controls.
                    .combinedClickable(
                        enabled = speakEnabled,
                        role = Role.Button,
                        onClick = handleVoiceClick,
                        onLongClick = toggleVoiceCaptureDetails,
                    )
                    .semantics {
                        role = Role.Button
                        contentDescription = voiceDescription
                        if (speakEnabled) {
                            onClick(label = voiceDescription) {
                                handleVoiceClick()
                                true
                            }
                            onLongClick(label = detailsLabel) {
                                toggleVoiceCaptureDetails()
                                true
                            }
                        } else {
                            disabled()
                        }
                    }
                    .testTag("capture-speak")
                    .padding(horizontal = 18.dp),
                contentAlignment = Alignment.Center,
            ) {
                CompositionLocalProvider(LocalContentColor provides capsuleContent) {
                    CompactVoiceCaptureStatus(
                        status = recordingStatus,
                        transcription = recordingTranscription,
                    )
                }
            }
            if (compactHeight) {
                IconButton(onClick = toggleVoiceCaptureDetails, modifier = Modifier.testTag("capture-recording-options")) {
                    Icon(Icons.Outlined.Tune, contentDescription = detailsLabel, tint = c.muted)
                }
            }
            if (wideComposer) Spacer(Modifier.weight(1f))
            val canSend = hasContent && !isSending
            Box(
                modifier = Modifier
                    .size(56.dp)
                    .clip(actionShape)
                    .background(if (canSend || isSending) c.accent else c.accent.copy(alpha = 0.3f))
                    .clickable(enabled = canSend, role = Role.Button, onClick = onSubmit)
                    .testTag("send-capture")
                    .semantics { contentDescription = sendDescription },
                contentAlignment = Alignment.Center,
            ) {
                if (isSending) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(22.dp),
                        strokeWidth = 2.dp,
                        color = c.onAccent,
                    )
                } else {
                    Icon(
                        Icons.Outlined.ArrowUpward,
                        contentDescription = null,
                        tint = c.onAccent.copy(alpha = if (canSend) 1f else 0.8f),
                        modifier = Modifier.size(24.dp),
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

/**
 * Contents of the speak capsule. Colors come from [LocalContentColor] so the
 * capsule decides the treatment (ink idle, recording red, tinted status fills).
 * No status titles are repeated here: the recording sheet owns those strings.
 */
@Composable
internal fun CompactVoiceCaptureStatus(
    status: RecordingStatus,
    transcription: RecordingTranscriptionState?,
) {
    val content = LocalContentColor.current
    when {
        status.isActive -> {
            val paused = status.phase == RecordingPhase.PAUSED
            val level = if (paused) 0.15f else status.level.coerceIn(0.15f, 1f)
            val barLevels = listOf(0.55f, 1f, 0.72f, 0.9f, 0.48f, 0.8f, 0.62f).map { level * it }
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    Icons.Outlined.Stop,
                    contentDescription = null,
                    modifier = Modifier.size(22.dp),
                    tint = content,
                )
                Text(
                    formatRecordingElapsed(status.elapsedMillis),
                    style = TextStyle(fontFamily = GeistMonoFontFamily, fontWeight = FontWeight.Medium, fontSize = 18.sp),
                    color = content,
                )
                Row(
                    modifier = Modifier.height(24.dp),
                    horizontalArrangement = Arrangement.spacedBy(3.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    barLevels.forEach { barLevel ->
                        Box(
                            Modifier
                                .width(3.dp)
                                .height((4f + (18f * barLevel)).dp)
                                .clip(CircleShape)
                                .background(content.copy(alpha = if (paused) 0.5f else 0.9f)),
                        )
                    }
                }
            }
        }
        transcription?.phase == RecordingTranscriptionPhase.PROCESSING -> {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                CircularProgressIndicator(
                    progress = { transcription.progress },
                    modifier = Modifier.size(22.dp),
                    strokeWidth = 2.5.dp,
                    color = Signal.colors.tint,
                    trackColor = content.copy(alpha = 0.15f),
                )
                Text(
                    voxFormat("%lld%%", (transcription.progress * 100).toInt()),
                    style = TextStyle(fontFamily = GeistMonoFontFamily, fontWeight = FontWeight.Medium, fontSize = 16.sp),
                    color = content,
                )
            }
        }
        transcription?.phase in setOf(RecordingTranscriptionPhase.QUEUED, RecordingTranscriptionPhase.FINALIZING) ->
            CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.5.dp, color = Signal.colors.tint, trackColor = content.copy(alpha = 0.15f))
        transcription?.phase == RecordingTranscriptionPhase.COMPLETED && !transcription.addedToDraft -> Icon(
            Icons.Outlined.CheckCircle,
            contentDescription = null,
            tint = content,
            modifier = Modifier.size(26.dp),
        )
        transcription?.phase in setOf(RecordingTranscriptionPhase.FAILED, RecordingTranscriptionPhase.DISCARDED) ||
            status.phase in setOf(RecordingPhase.FAILED, RecordingPhase.INTERRUPTED) -> Icon(
                Icons.Outlined.ErrorOutline,
                contentDescription = null,
                tint = content,
                modifier = Modifier.size(26.dp),
            )
        status.phase == RecordingPhase.COMPLETED && transcription == null -> Icon(
            Icons.Outlined.Schedule,
            contentDescription = null,
            tint = content,
            modifier = Modifier.size(26.dp),
        )
        else -> Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Icon(Icons.Outlined.MicNone, contentDescription = null, tint = content, modifier = Modifier.size(24.dp))
            Text(
                voxString("Speak"),
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold, fontSize = 17.sp),
                color = content,
                maxLines = 1,
            )
        }
    }
}

private val RecordingWaveShape = listOf(
    0.35f, 0.6f, 0.45f, 0.85f, 0.55f, 1f, 0.7f, 0.4f, 0.65f, 0.9f, 0.5f, 0.75f,
    0.3f, 0.55f, 0.8f, 0.45f, 0.95f, 0.6f, 0.4f, 0.7f, 0.5f, 0.85f, 0.35f, 0.6f,
)

/** Recording-red waveform for the live sheet; levels are deterministic for stories. */
@Composable
private fun CaptureRecordingWaveform(level: Float, paused: Boolean, modifier: Modifier = Modifier) {
    val c = Signal.colors
    val clamped = if (paused) 0.12f else level.coerceIn(0.2f, 1f)
    Row(
        modifier = modifier.height(40.dp),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RecordingWaveShape.forEach { shape ->
            Box(
                Modifier
                    .width(3.dp)
                    .height((4f + 34f * clamped * shape).dp)
                    .clip(CircleShape)
                    .background(if (paused) c.faint else c.recording),
            )
        }
    }
}

@OptIn(androidx.compose.foundation.layout.ExperimentalLayoutApi::class)
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
    val c = Signal.colors
    val active = status.isActive
    val paused = status.phase == RecordingPhase.PAUSED
    val hideDetailsDescription = voxString("Hide detailed recording controls")
    val color = when {
        transcription?.phase == RecordingTranscriptionPhase.FAILED -> c.error
        transcription?.phase in setOf(
            RecordingTranscriptionPhase.QUEUED,
            RecordingTranscriptionPhase.PROCESSING,
            RecordingTranscriptionPhase.FINALIZING,
        ) -> c.tint
        transcription?.phase == RecordingTranscriptionPhase.COMPLETED -> c.success
        status.phase == RecordingPhase.RECORDING -> c.recording
        status.phase in setOf(RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED) -> c.warning
        status.phase == RecordingPhase.COMPLETED -> c.success
        status.phase == RecordingPhase.FAILED -> c.error
        else -> c.faint
    }
    val shape = RoundedCornerShape(SignalMetrics.CardRadius)
    Box(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.card)
            .border(1.dp, if (status.phase == RecordingPhase.RECORDING) c.recording.copy(alpha = 0.45f) else c.border, shape),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 14.dp)
                .testTag("capture-recording-details"),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(9.dp).clip(CircleShape).background(color))
                Spacer(Modifier.width(10.dp))
                Text(
                    recordingDetailsTitle(status, transcription).localized(),
                    style = MaterialTheme.typography.titleSmall,
                    color = c.text,
                    modifier = Modifier
                        .weight(1f)
                        .semantics { liveRegion = LiveRegionMode.Polite },
                )
                if (!active && status.phase != RecordingPhase.IDLE) {
                    Text(
                        formatRecordingElapsed(status.elapsedMillis),
                        style = SignalType.mono,
                        color = c.muted,
                    )
                }
                IconButton(
                    onClick = close,
                    modifier = Modifier.size(48.dp).semantics { contentDescription = hideDetailsDescription },
                ) {
                    Icon(Icons.Outlined.Close, contentDescription = null, tint = c.muted, modifier = Modifier.size(20.dp))
                }
            }
            val recordingControls: @Composable () -> Unit = {
                FlowRow(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (active) {
                        SignalButton(
                            voxString(if (paused) "Resume" else "Pause"),
                            onClick = if (paused) resume else pause,
                            variant = if (paused) SignalButtonVariant.ACCENT else SignalButtonVariant.SECONDARY,
                            size = SignalButtonSize.MEDIUM,
                            icon = if (paused) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                        )
                        SignalButton(
                            voxString("Stop"),
                            onClick = stop,
                            variant = SignalButtonVariant.DESTRUCTIVE,
                            size = SignalButtonSize.MEDIUM,
                            icon = Icons.Outlined.Stop,
                        )
                        SignalButton(
                            voxString("Cancel"),
                            onClick = cancel,
                            variant = SignalButtonVariant.TERTIARY,
                            size = SignalButtonSize.MEDIUM,
                        )
                    } else if (status.phase == RecordingPhase.INTERRUPTED) {
                        SignalButton(
                            voxString("Resume"),
                            onClick = resume,
                            size = SignalButtonSize.MEDIUM,
                            icon = Icons.Outlined.PlayArrow,
                        )
                        SignalButton(
                            voxString("Finish"),
                            onClick = stop,
                            variant = SignalButtonVariant.SECONDARY,
                            size = SignalButtonSize.MEDIUM,
                        )
                        SignalButton(
                            voxString("Cancel"),
                            onClick = cancel,
                            variant = SignalButtonVariant.TERTIARY,
                            size = SignalButtonSize.MEDIUM,
                        )
                    } else if (status.phase == RecordingPhase.IDLE) {
                        SignalButton(
                            voxString("Record"),
                            onClick = start,
                            size = SignalButtonSize.MEDIUM,
                            icon = Icons.Outlined.MicNone,
                        )
                    } else {
                        SignalButton(
                            voxString("Dismiss"),
                            onClick = dismiss,
                            variant = SignalButtonVariant.SECONDARY,
                            size = SignalButtonSize.MEDIUM,
                        )
                    }
                }
            }
            Column(
                modifier = Modifier.padding(end = 12.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (active) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(14.dp),
                    ) {
                        Text(
                            formatRecordingElapsed(status.elapsedMillis),
                            style = TextStyle(
                                fontFamily = GeistMonoFontFamily,
                                fontWeight = FontWeight.Medium,
                                fontSize = 40.sp,
                                lineHeight = 44.sp,
                            ),
                            color = if (paused) c.muted else c.text,
                        )
                        CaptureRecordingWaveform(
                            level = status.level,
                            paused = paused,
                            modifier = Modifier.weight(1f).wrapContentSize(Alignment.CenterEnd, unbounded = false),
                        )
                    }
                }
                if (active) recordingControls()
                val routeSteps = if (active) emptyList() else captureRouteSteps(status, transcription)
                if (routeSteps.isEmpty()) {
                    Text(
                        recordingDetailsSubtitle(status, transcription).localized(),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                } else {
                    CaptureRouteProgressSteps(routeSteps)
                }
                if (active) {
                    val liveStatusStyle = SignalType.caption
                    when (liveSpeech?.phase) {
                        LiveSpeechPhase.STARTING -> Text(voxString("Starting private live transcript…"),
                            style = liveStatusStyle,
                            color = c.faint,
                        )
                        LiveSpeechPhase.LISTENING, LiveSpeechPhase.PAUSED -> {
                            if (liveSpeech.displayText.isNotBlank()) {
                                Text(
                                    liveSpeech.displayText,
                                    style = MaterialTheme.typography.bodyLarge.copy(
                                        fontWeight = FontWeight.Medium,
                                        fontSize = 19.sp,
                                        lineHeight = 26.sp,
                                    ),
                                    color = if (paused) c.muted else c.text,
                                )
                            } else {
                                Text(
                                    voxString(if (liveSpeech.phase == LiveSpeechPhase.PAUSED) "Live transcript paused" else "Listening on this device…"),
                                    style = liveStatusStyle,
                                    color = c.faint,
                                )
                            }
                            if (liveSpeech.droppedBufferCount > 0) {
                                Text(voxString("Live preview fell behind. The complete durable recording is unaffected."),
                                    style = liveStatusStyle,
                                    color = c.warningText,
                                )
                            }
                        }
                        LiveSpeechPhase.UNAVAILABLE, LiveSpeechPhase.FAILED -> Text(voxString("Live preview is unavailable. The recording remains safe for final on-device transcription."),
                            style = liveStatusStyle,
                            color = c.faint,
                        )
                        LiveSpeechPhase.COMPLETED, null -> Unit
                    }
                }
                when (transcription?.phase) {
                    RecordingTranscriptionPhase.QUEUED -> Unit
                    RecordingTranscriptionPhase.PROCESSING -> {
                        LinearProgressIndicator(
                            progress = { transcription.progress },
                            modifier = Modifier.fillMaxWidth().height(6.dp).clip(CircleShape),
                            color = c.tint,
                            trackColor = c.well,
                            gapSize = 0.dp,
                            drawStopIndicator = {},
                        )
                        Text(voxFormat("Transcribing voice capture, %@ complete", voxFormat("%lld%%", (transcription.progress * 100).toInt())),
                            style = SignalType.monoCaption,
                            color = c.muted,
                        )
                        SignalButton(
                            voxString("Cancel Processing"),
                            onClick = cancelProcessing,
                            variant = SignalButtonVariant.SECONDARY,
                            size = SignalButtonSize.MEDIUM,
                        )
                    }
                    RecordingTranscriptionPhase.FINALIZING -> Text(
                        voxString("Finalizing transcript…"),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                    RecordingTranscriptionPhase.COMPLETED -> {
                        val transcript = transcription.preferredTranscript.orEmpty()
                        Text(
                            transcript,
                            style = MaterialTheme.typography.bodyLarge,
                            color = c.text,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(SignalMetrics.FieldRadius))
                                .background(c.bg)
                                .border(1.dp, c.divider, RoundedCornerShape(SignalMetrics.FieldRadius))
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                        )
                        FlowRow(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            verticalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            SignalButton(
                                voxString(if (transcription.addedToDraft) "Added" else "Add to Draft"),
                                onClick = { addToDraft(transcript) },
                                size = SignalButtonSize.MEDIUM,
                                enabled = transcript.isNotBlank() && !transcription.addedToDraft,
                                icon = if (transcription.addedToDraft) Icons.Outlined.Check else Icons.Outlined.Add,
                            )
                            SignalButton(
                                voxString("Send with Preset"),
                                onClick = { sendWithPreset(transcript) },
                                variant = SignalButtonVariant.ACCENT,
                                size = SignalButtonSize.MEDIUM,
                                enabled = transcript.isNotBlank() && !transcription.addedToDraft,
                                icon = Icons.Outlined.ArrowUpward,
                            )
                        }
                    }
                    RecordingTranscriptionPhase.FAILED -> {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(SignalMetrics.FieldRadius))
                                .background(c.errorSoft)
                                .padding(horizontal = 14.dp, vertical = 12.dp),
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Icon(Icons.Outlined.ErrorOutline, contentDescription = null, tint = c.error, modifier = Modifier.size(18.dp))
                            Text(
                                voxString(if (transcription.failureCode == "transcriptionQuotaReached") {
                                    "The free transcription limit has been reached. The original recording is still safe."
                                } else {
                                    "Local transcription failed. The original recording is still safe."
                                }),
                                modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                                style = SignalType.caption,
                                color = c.error,
                            )
                        }
                        SignalButton(
                            voxString("Retry Processing"),
                            onClick = process,
                            size = SignalButtonSize.MEDIUM,
                            icon = Icons.Outlined.Refresh,
                        )
                    }
                    RecordingTranscriptionPhase.DISCARDED -> Text(
                        voxString("Processing discarded. The original audio is still safe."),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                    null -> if (status.phase == RecordingPhase.COMPLETED) {
                        SignalButton(
                            voxString("Process Recording"),
                            onClick = process,
                            size = SignalButtonSize.MEDIUM,
                            icon = Icons.Outlined.GraphicEq,
                        )
                    }
                }
                if (!active) recordingControls()
            }
        }
    }
}

internal fun recordingDetailsTitle(
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

internal fun recordingDetailsSubtitle(
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

internal fun recordingTitleUiText(phase: RecordingPhase): VoxUiText = when (phase) {
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

internal fun recordingDetailUiText(status: RecordingStatus): VoxUiText = when (status.phase) {
    RecordingPhase.RECORDING -> voxUiText("Audio is staying on this device and is checkpointed every second.")
    RecordingPhase.PAUSED -> voxUiText("The recorded chunks are safe. Resume or stop when you’re ready.")
    RecordingPhase.COMPLETED -> when (status.failureCode) {
        "voiceAutoStop" -> voxUiText("Voice Auto-Stop detected the end of speech. The recording was saved locally.")
        "segmentBoundaryPersistence" -> voxUiText("A segment boundary could not be saved, so recording stopped with all audio preserved.")
        else -> voxUiText("Saved locally in %lld durable chunks.", status.chunkCount.toLong())
    }
    RecordingPhase.INTERRUPTED -> voxUiText("The audio recorded before interruption is safe and available for recovery.")
    RecordingPhase.FAILED -> voxUiText("The microphone stopped, but completed chunks remain local.")
    RecordingPhase.DISCARDED -> voxUiText("The session is marked cancelled; its source remains recoverable for now.")
    RecordingPhase.IDLE -> voxUiText("Ready")
}

internal fun formatRecordingElapsed(milliseconds: Long): String {
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

internal suspend fun configuredTranscriptAudioSource(
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
        audioFilenameTemplate = resolvedPreset.audioFilenameTemplate,
        presetName = resolvedPreset.name,
    )
}

@Composable
internal fun IconAction(icon: ImageVector, label: String, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(48.dp)) {
        Icon(icon, contentDescription = label, tint = Signal.colors.text)
    }
}

@Composable
internal fun ToolbarAction(
    icon: ImageVector,
    label: VoxUiText,
    enabled: Boolean,
    disabledDescription: VoxUiText = voxUiText("This action is not available yet"),
    onClick: () -> Unit = {},
) {
    val c = Signal.colors
    val description = (if (enabled) label else disabledDescription).localized()
    CaptureBarChip(onClick = onClick, enabled = enabled, description = description) {
        Icon(icon, contentDescription = null, tint = if (enabled) c.text else c.faint.copy(alpha = 0.6f), modifier = Modifier.size(20.dp))
    }
}

/**
 * Capture Bar quick action: a 36dp outlined chip with an 8dp radius inside a 48dp
 * touch target, holding an icon or a short mono glyph ("[[", "Abc").
 */
@Composable
internal fun CaptureBarChip(
    onClick: () -> Unit,
    enabled: Boolean,
    description: String,
    content: @Composable () -> Unit,
) {
    LocalCaptureBarTile.current?.let { tile ->
        CaptureBarTile(tile, onClick = onClick, enabled = enabled, description = description, content = content)
        return
    }
    val c = Signal.colors
    val shape = RoundedCornerShape(8.dp)
    Box(
        modifier = Modifier
            .minimumInteractiveComponentSize()
            .heightIn(min = 36.dp)
            .widthIn(min = 44.dp)
            .clip(shape)
            .border(1.dp, c.border, shape)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description }
            .padding(horizontal = 12.dp, vertical = 8.dp),
        contentAlignment = Alignment.Center,
    ) {
        content()
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
internal fun ToolbarTextAction(text: String, label: VoxUiText, onClick: () -> Unit) {
    val localizedLabel = label.localized()
    CaptureBarChip(onClick = onClick, enabled = true, description = localizedLabel) {
        Text(text, style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily, fontWeight = FontWeight.Medium), color = Signal.colors.text)
    }
}

@Composable
internal fun MarkdownFormatMenu(command: (CaptureComposerCommand) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ToolbarAction(Icons.Outlined.TextFields, voxUiText("Format Markdown"), enabled = true) { expanded = true }
        CaptureSignalMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            CommandMenuItem(voxUiText("Bold"), CaptureComposerCommand.ToggleBold, command) { expanded = false }
            CommandMenuItem(voxUiText("Italic"), CaptureComposerCommand.ToggleItalic, command) { expanded = false }
            CommandMenuItem(voxUiText("Hashtag"), CaptureComposerCommand.InsertHashtag, command) { expanded = false }
            SignalDivider(Modifier.padding(vertical = 4.dp))
            (1..6).forEach { level ->
                CommandMenuItem(voxUiText("Heading %lld", level.toLong()), CaptureComposerCommand.Heading(level), command) { expanded = false }
            }
        }
    }
}

@Composable
internal fun TextCaseMenu(command: (CaptureComposerCommand) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Box {
        ToolbarTextAction("Abc", voxUiText("Change text case")) { expanded = true }
        CaptureSignalMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            CommandMenuItem(voxUiText("Lowercase"), CaptureComposerCommand.Lowercase, command) { expanded = false }
            CommandMenuItem(voxUiText("Uppercase"), CaptureComposerCommand.Uppercase, command) { expanded = false }
            CommandMenuItem(voxUiText("Sentence case"), CaptureComposerCommand.SentenceCase, command) { expanded = false }
            CommandMenuItem(voxUiText("Capitalize case"), CaptureComposerCommand.CapitalizeWords, command) { expanded = false }
            CommandMenuItem(voxUiText("Slugify case"), CaptureComposerCommand.Slugify, command) { expanded = false }
        }
    }
}

@Composable
internal fun CommandMenuItem(
    label: VoxUiText,
    value: CaptureComposerCommand,
    command: (CaptureComposerCommand) -> Unit,
    dismiss: () -> Unit,
) {
    DropdownMenuItem(
        text = { Text(label.localized(), style = MaterialTheme.typography.bodyLarge) },
        onClick = {
            dismiss()
            command(value)
        },
        colors = MenuDefaults.itemColors(textColor = Signal.colors.text),
        modifier = Modifier.heightIn(min = 48.dp),
    )
}

/** Dropdown menu on a white bordered card (no tonal elevation). */
@Composable
internal fun CaptureSignalMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit,
) {
    val c = Signal.colors
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismissRequest,
        shape = RoundedCornerShape(SignalMetrics.GroupRadius),
        containerColor = c.card,
        tonalElevation = 0.dp,
        shadowElevation = 8.dp,
        border = BorderStroke(1.dp, c.border),
        content = content,
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
    val c = Signal.colors
    CaptureSignalDialog(
        onDismissRequest = onDismiss,
        title = voxString("Set due date"),
        confirmButton = {},
        dismissButton = {
            SignalButton(voxString("Cancel"), onClick = onDismiss, variant = SignalButtonVariant.TERTIARY, size = SignalButtonSize.MEDIUM)
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
            Text(voxString("Insert an Obsidian-compatible due-date token at the current selection."),
                style = SignalType.caption,
                color = c.muted,
            )
            CaptureDialogGroup {
                listOf(
                    voxString("Today") to token(today),
                    voxString("Tomorrow") to token(tomorrow),
                    voxString("This Weekend") to token(weekend),
                ).forEachIndexed { index, (label, value) ->
                    if (index > 0) SignalRowDivider()
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 52.dp)
                            .clickable(role = Role.Button) { onInsert(value) }
                            .padding(horizontal = 14.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp),
                    ) {
                        SignalIconTile(Icons.Outlined.CalendarToday, primary = index == 0)
                        Text(label, style = SignalType.rowTitle, color = c.text, modifier = Modifier.weight(1f))
                        Text(value, style = SignalType.monoCaption, color = c.muted, maxLines = 1)
                    }
                }
            }
        }
    }
}

@Composable
internal fun LinkAttachment(url: String, remove: () -> Unit) {
    val c = Signal.colors
    SignalCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(start = 10.dp, end = 0.dp, top = 0.dp, bottom = 0.dp),
        radius = SignalMetrics.GroupRadius,
    ) {
        Row(
            modifier = Modifier.heightIn(min = 56.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SignalIconTile(Icons.Outlined.Link, primary = true)
            Spacer(Modifier.width(10.dp))
            Text(
                url,
                modifier = Modifier.weight(1f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = SignalType.mono,
                color = c.text,
            )
            IconButton(onClick = remove, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Outlined.Close, contentDescription = voxFormat("Remove %@", voxString("Link")), tint = c.muted, modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
internal fun AttachmentChip(attachment: CaptureAttachment, remove: () -> Unit) {
    val c = Signal.colors
    SignalCard(
        padding = PaddingValues(start = 10.dp, end = 0.dp, top = 0.dp, bottom = 0.dp),
        radius = SignalMetrics.GroupRadius,
    ) {
        Row(
            modifier = Modifier.heightIn(min = 56.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SignalIconTile(if (attachment.isImage) Icons.Outlined.Image else Icons.Outlined.AttachFile)
            Spacer(Modifier.width(10.dp))
            Column(modifier = Modifier.width(150.dp), verticalArrangement = Arrangement.spacedBy(1.dp)) {
                Text(attachment.displayName, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.labelMedium, color = c.text)
                Text(
                    formatAttachmentSize(attachment.byteCount),
                    color = c.muted,
                    style = SignalType.monoCaption,
                )
            }
            IconButton(onClick = remove, modifier = Modifier.size(48.dp)) {
                Icon(Icons.Outlined.Close, contentDescription = voxFormat("Remove %@", attachment.displayName), tint = c.muted, modifier = Modifier.size(18.dp))
            }
        }
    }
}

internal fun formatAttachmentSize(bytes: Long): String = when {
    bytes >= 1024 * 1024 -> "%.1f MB".format(Locale.getDefault(), bytes / (1024.0 * 1024.0))
    bytes >= 1024 -> "%.1f KB".format(Locale.getDefault(), bytes / 1024.0)
    else -> "$bytes B"
}

@Composable
internal fun LinkDialog(initialValue: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var value by rememberSaveable(initialValue) { mutableStateOf(initialValue) }
    val normalizedLink = CaptureWebLink.normalize(value)
    CaptureSignalDialog(
        onDismissRequest = onDismiss,
        title = voxString("Capture Link"),
        confirmButton = {
            SignalButton(voxString("Add"), onClick = { normalizedLink?.let(onSave) }, enabled = normalizedLink != null, size = SignalButtonSize.MEDIUM)
        },
        dismissButton = {
            SignalButton(voxString("Cancel"), onClick = onDismiss, variant = SignalButtonVariant.TERTIARY, size = SignalButtonSize.MEDIUM)
        },
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it.take(8_192) },
                label = { Text(voxString("Web address")) },
                placeholder = { Text(voxString("https://example.com")) },
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                singleLine = true,
                shape = SignalFieldShape,
                colors = signalTextFieldColors(),
                textStyle = SignalType.mono.copy(fontSize = 15.sp),
                leadingIcon = { Icon(Icons.Outlined.Link, contentDescription = null, tint = Signal.colors.muted) },
                modifier = Modifier.fillMaxWidth(),
            )
            Text(voxString("The link stays in your durable draft until the note is captured."),
                style = SignalType.caption,
                color = Signal.colors.muted,
            )
        }
    }
}
