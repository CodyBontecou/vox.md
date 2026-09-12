package md.vox.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.material.icons.outlined.ArrowUpward
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.AttachFile
import androidx.compose.material.icons.outlined.CheckBox
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ChevronRight
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Image
import androidx.compose.material.icons.outlined.Keyboard
import androidx.compose.material.icons.outlined.Link
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.WorkOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
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
import androidx.core.content.ContextCompat
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureState
import md.vox.android.ui.CaptureUiState
import md.vox.android.ui.CaptureViewModel
import md.vox.android.ui.VoxColors
import md.vox.android.ui.VoxTheme
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingStatusRegistry
import java.text.DateFormat
import java.util.Date
import java.util.UUID

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val root = (application as VoxApplication).compositionRoot
        setContent {
            VoxTheme {
                Box(Modifier.semantics { testTagsAsResourceId = true }) {
                    val model: CaptureViewModel = viewModel(factory = CaptureViewModel.factory(root.captureRepository))
                    VoxApp(model)
                }
            }
        }
    }
}

private enum class Destination(val route: String) {
    Capture("capture"),
    History("history"),
    Settings("settings"),
    Presets("presets"),
}

private const val PRESET_EDITOR_ROUTE = "preset-editor"
private const val DEFAULT_CAPTURE_PRESET_ID = "33333333-3333-4333-8333-333333333333"

@Composable
private fun VoxApp(model: CaptureViewModel) {
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val recordingClient = remember(context) { AudioCaptureClient(context) }
    val recordingStatus by RecordingStatusRegistry.status.collectAsStateWithLifecycle()
    val microphonePermissions = remember {
        buildList {
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
        }.toTypedArray()
    }
    val microphonePermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { grants ->
        if (grants[Manifest.permission.RECORD_AUDIO] == true) recordingClient.start()
    }
    val startRecording: () -> Unit = {
        recordingClient.dismissResult()
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            recordingClient.start()
        } else {
            microphonePermissionLauncher.launch(microphonePermissions)
        }
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
        state.destination == null -> VaultSetupScreen(state.notice, onChooseFolder = { openTree(null) })
        else -> VoxNavigation(state, model, openTree, recordingStatus, recordingClient, startRecording)
    }
}

@Composable
private fun LoadingScreen() {
    Surface(modifier = Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
        Box(contentAlignment = Alignment.Center) {
            CircularProgressIndicator(modifier = Modifier.size(32.dp), strokeWidth = 3.dp)
        }
    }
}

@Composable
private fun VaultSetupScreen(notice: String?, onChooseFolder: () -> Unit) {
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
            Text("Your notes. Your folder.", style = MaterialTheme.typography.headlineLarge)
            Spacer(Modifier.height(12.dp))
            Text(
                "Choose the Obsidian vault or Markdown folder where Vox.md should create notes.",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(24.dp))
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                shape = RoundedCornerShape(16.dp),
            ) {
                Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Local by design", style = MaterialTheme.typography.titleMedium)
                    Text(
                        "Captures are saved on this device before delivery. Vox.md only receives access to the folder you select.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            if (notice != null) {
                Spacer(Modifier.height(16.dp))
                Text(notice, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
            }
            Spacer(Modifier.height(32.dp))
            Button(
                onClick = onChooseFolder,
                modifier = Modifier.fillMaxWidth().height(48.dp),
                shape = RoundedCornerShape(12.dp),
            ) {
                Icon(Icons.Outlined.FolderOpen, contentDescription = null)
                Spacer(Modifier.width(8.dp))
                Text("Choose Markdown Folder")
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
    recordingClient: AudioCaptureClient,
    startRecording: () -> Unit,
) {
    val navController = rememberNavController()
    val snackbarHost = remember { SnackbarHostState() }
    LaunchedEffect(state.notice) {
        val notice = state.notice ?: return@LaunchedEffect
        snackbarHost.showSnackbar(notice)
        model.clearNotice()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        NavHost(navController = navController, startDestination = Destination.Capture.route) {
            composable(Destination.Capture.route) {
                CaptureScreen(
                    state = state,
                    recordingStatus = recordingStatus,
                    onSubmit = model::submit,
                    consumeAcceptedCapture = model::consumeAcceptedCapture,
                    openHistory = { navController.navigate(Destination.History.route) },
                    openSettings = { navController.navigate(Destination.Settings.route) },
                    openPresets = { navController.navigate(Destination.Presets.route) },
                    startRecording = startRecording,
                    pauseRecording = recordingClient::pause,
                    resumeRecording = recordingClient::resume,
                    stopRecording = recordingClient::stop,
                    cancelRecording = recordingClient::cancel,
                    dismissRecording = recordingClient::dismissResult,
                )
            }
            composable(Destination.History.route) {
                HistoryScreen(
                    items = state.history,
                    isBusy = state.isSending,
                    navigateBack = { navController.popBackStack() },
                    retry = model::retry,
                    repairAccess = openTree,
                )
            }
            composable(Destination.Settings.route) {
                SettingsScreen(
                    destination = requireNotNull(state.destination),
                    navigateBack = { navController.popBackStack() },
                    chooseFolder = { openTree(null) },
                    openPresets = { navController.navigate(Destination.Presets.route) },
                )
            }
            composable(Destination.Presets.route) {
                CapturePresetsScreen(
                    collection = state.presetCollection,
                    isBusy = state.isSavingConfiguration,
                    navigateBack = { navController.popBackStack() },
                    selectPreset = model::selectPreset,
                    editPreset = { presetID -> navController.navigate("$PRESET_EDITOR_ROUTE/$presetID") },
                    createPreset = { navController.navigate("$PRESET_EDITOR_ROUTE/new") },
                )
            }
            composable("$PRESET_EDITOR_ROUTE/{presetID}") { entry ->
                val presetID = entry.arguments?.getString("presetID") ?: "new"
                val preset = state.presetCollection?.presets?.firstOrNull { it.id == presetID }
                CapturePresetEditorScreen(
                    preset = preset,
                    isBusy = state.isSavingConfiguration,
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
            modifier = Modifier.align(Alignment.BottomCenter).navigationBarsPadding().padding(16.dp),
        )
    }
}

@Composable
private fun CaptureScreen(
    state: CaptureUiState,
    recordingStatus: RecordingStatus,
    onSubmit: (String, String?) -> Unit,
    consumeAcceptedCapture: () -> Unit,
    openHistory: () -> Unit,
    openSettings: () -> Unit,
    openPresets: () -> Unit,
    startRecording: () -> Unit,
    pauseRecording: () -> Unit,
    resumeRecording: () -> Unit,
    stopRecording: () -> Unit,
    cancelRecording: () -> Unit,
    dismissRecording: () -> Unit,
) {
    var text by rememberSaveable { mutableStateOf("") }
    var capturedURL by rememberSaveable { mutableStateOf<String?>(null) }
    var showsLinkDialog by rememberSaveable { mutableStateOf(false) }
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    val keyboardController = LocalSoftwareKeyboardController.current

    LaunchedEffect(Unit) {
        delay(180)
        focusRequester.requestFocus()
        keyboardController?.show()
    }
    LaunchedEffect(state.acceptedRequestID) {
        if (state.acceptedRequestID != null) {
            text = ""
            capturedURL = null
            consumeAcceptedCapture()
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
                showsLinkDialog = false
                focusRequester.requestFocus()
            },
        )
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        bottomBar = {
            CaptureBottomControls(
                destination = requireNotNull(state.destination),
                preset = state.presetCollection?.activePreset,
                hasContent = text.isNotBlank() || capturedURL != null,
                isSending = state.isSending,
                onSubmit = { onSubmit(text, capturedURL) },
                openHistory = openHistory,
                openSettings = openSettings,
                openPresets = openPresets,
                toggleKeyboard = {
                    focusManager.clearFocus()
                    keyboardController?.hide()
                },
                addLink = { showsLinkDialog = true },
                recordingStatus = recordingStatus,
                startRecording = startRecording,
                stopRecording = stopRecording,
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 20.dp, vertical = 16.dp),
        ) {
            BasicTextField(
                value = text,
                onValueChange = { if (it.length <= 65_536) text = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .focusRequester(focusRequester)
                    .testTag("capture-editor")
                    .semantics { contentDescription = "Capture text" },
                textStyle = TextStyle(
                    color = MaterialTheme.colorScheme.onBackground,
                    fontFamily = FontFamily.Monospace,
                    fontSize = 18.sp,
                    lineHeight = 26.sp,
                ),
                cursorBrush = SolidColor(MaterialTheme.colorScheme.primary),
                decorationBox = { inner ->
                    Box(Modifier.fillMaxSize()) {
                        if (text.isEmpty()) {
                            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(
                                    "Do what you can, with what you have, where you are.",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    style = MaterialTheme.typography.bodyLarge.copy(fontFamily = FontFamily.Monospace),
                                )
                                Text(
                                    "— Theodore Roosevelt",
                                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.72f),
                                    style = MaterialTheme.typography.bodyMedium,
                                )
                            }
                        }
                        inner()
                    }
                },
            )
            if (capturedURL != null) {
                Spacer(Modifier.height(12.dp))
                LinkAttachment(url = requireNotNull(capturedURL), remove = { capturedURL = null })
            }
            if (recordingStatus.phase != RecordingPhase.IDLE) {
                Spacer(Modifier.height(12.dp))
                RecordingCard(
                    status = recordingStatus,
                    pause = pauseRecording,
                    resume = resumeRecording,
                    stop = stopRecording,
                    cancel = cancelRecording,
                    dismiss = dismissRecording,
                )
            }
        }
    }
}

@Composable
private fun CaptureBottomControls(
    destination: CaptureDestination,
    preset: CapturePreset?,
    hasContent: Boolean,
    isSending: Boolean,
    onSubmit: () -> Unit,
    openHistory: () -> Unit,
    openSettings: () -> Unit,
    openPresets: () -> Unit,
    toggleKeyboard: () -> Unit,
    addLink: () -> Unit,
    recordingStatus: RecordingStatus,
    startRecording: () -> Unit,
    stopRecording: () -> Unit,
) {
    Surface(color = MaterialTheme.colorScheme.background, tonalElevation = 0.dp) {
        Column(modifier = Modifier.fillMaxWidth().imePadding()) {
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(56.dp)
                    .clickable(onClick = openPresets)
                    .padding(horizontal = 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(presetIcon(preset?.symbol), contentDescription = null, modifier = Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text(preset?.name ?: "Default", style = MaterialTheme.typography.labelLarge)
                Spacer(Modifier.width(16.dp))
                Text(
                    destination.displayName,
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Icon(Icons.Outlined.ChevronRight, contentDescription = "Choose capture preset", modifier = Modifier.size(20.dp))
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
                            contentDescription = if (isSending) "Sending capture" else "Send capture"
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
                IconButton(
                    onClick = if (recordingStatus.isActive) stopRecording else startRecording,
                    enabled = !isSending,
                    modifier = Modifier.semantics {
                        contentDescription = if (recordingStatus.isActive) "Stop voice capture" else "Start voice capture"
                    },
                ) {
                    Icon(
                        if (recordingStatus.isActive) Icons.Outlined.Stop else Icons.Outlined.MicNone,
                        contentDescription = null,
                        tint = if (recordingStatus.isActive) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurface,
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
                item { ToolbarAction(Icons.Outlined.Link, "Add link", enabled = true, onClick = addLink) }
                item { ToolbarAction(Icons.Outlined.Image, "Add media", enabled = false) }
                item { ToolbarAction(Icons.Outlined.AttachFile, "Add files", enabled = false) }
                item { ToolbarAction(Icons.Outlined.Description, "Scan document", enabled = false) }
            }
        }
    }
}

@Composable
private fun RecordingCard(
    status: RecordingStatus,
    pause: () -> Unit,
    resume: () -> Unit,
    stop: () -> Unit,
    cancel: () -> Unit,
    dismiss: () -> Unit,
) {
    val active = status.isActive
    val color = when (status.phase) {
        RecordingPhase.RECORDING -> MaterialTheme.colorScheme.error
        RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED -> if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.AmberDark else VoxColors.Amber
        RecordingPhase.COMPLETED -> if (androidx.compose.foundation.isSystemInDarkTheme()) VoxColors.GreenDark else VoxColors.Green
        RecordingPhase.FAILED -> MaterialTheme.colorScheme.error
        else -> MaterialTheme.colorScheme.onSurfaceVariant
    }
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Surface(shape = CircleShape, color = color, modifier = Modifier.size(10.dp)) {}
                Spacer(Modifier.width(8.dp))
                Text(recordingTitle(status.phase), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Text(
                    formatRecordingElapsed(status.elapsedMillis),
                    style = MaterialTheme.typography.labelLarge.copy(fontFamily = FontFamily.Monospace),
                )
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
                recordingDetail(status),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                if (active) {
                    TextButton(onClick = if (status.phase == RecordingPhase.PAUSED) resume else pause) {
                        Icon(
                            if (status.phase == RecordingPhase.PAUSED) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(Modifier.width(6.dp))
                        Text(if (status.phase == RecordingPhase.PAUSED) "Resume" else "Pause")
                    }
                    TextButton(onClick = stop) {
                        Icon(Icons.Outlined.Stop, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Stop")
                    }
                    TextButton(onClick = cancel) { Text("Cancel") }
                } else if (status.phase == RecordingPhase.INTERRUPTED) {
                    TextButton(onClick = resume) {
                        Icon(Icons.Outlined.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("Resume")
                    }
                    TextButton(onClick = stop) { Text("Finish") }
                    TextButton(onClick = cancel) { Text("Cancel") }
                } else {
                    TextButton(onClick = dismiss) { Text("Dismiss") }
                }
            }
        }
    }
}

private fun recordingTitle(phase: RecordingPhase): String = when (phase) {
    RecordingPhase.RECORDING -> "Recording"
    RecordingPhase.PAUSED -> "Recording paused"
    RecordingPhase.COMPLETED -> "Recording saved"
    RecordingPhase.INTERRUPTED -> "Recording interrupted"
    RecordingPhase.FAILED -> "Recording failed"
    RecordingPhase.DISCARDED -> "Recording cancelled"
    RecordingPhase.IDLE -> "Voice capture"
}

private fun recordingDetail(status: RecordingStatus): String = when (status.phase) {
    RecordingPhase.RECORDING -> "Audio is staying on this device and is checkpointed every second."
    RecordingPhase.PAUSED -> "The recorded chunks are safe. Resume or stop when you’re ready."
    RecordingPhase.COMPLETED -> "Saved locally in ${status.chunkCount} durable chunk${if (status.chunkCount == 1) "" else "s"}."
    RecordingPhase.INTERRUPTED -> "The audio recorded before interruption is safe and available for recovery."
    RecordingPhase.FAILED -> "The microphone stopped, but completed chunks remain local."
    RecordingPhase.DISCARDED -> "The session is marked cancelled; its source remains recoverable for now."
    RecordingPhase.IDLE -> ""
}

private fun formatRecordingElapsed(milliseconds: Long): String {
    val seconds = milliseconds.coerceAtLeast(0) / 1_000
    return "%d:%02d".format(seconds / 60, seconds % 60)
}

@Composable
private fun IconAction(icon: ImageVector, label: String, onClick: () -> Unit) {
    IconButton(onClick = onClick, modifier = Modifier.size(48.dp)) {
        Icon(icon, contentDescription = label)
    }
}

@Composable
private fun ToolbarAction(icon: ImageVector, label: String, enabled: Boolean, onClick: () -> Unit = {}) {
    IconButton(onClick = onClick, enabled = enabled, modifier = Modifier.size(48.dp)) {
        Icon(icon, contentDescription = if (enabled) label else "$label is not available yet")
    }
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
                Icon(Icons.Outlined.Close, contentDescription = "Remove link", modifier = Modifier.size(18.dp))
            }
        }
    }
}

@Composable
private fun LinkDialog(initialValue: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var value by rememberSaveable(initialValue) { mutableStateOf(initialValue) }
    val valid = value.startsWith("https://") || value.startsWith("http://")
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Capture Link") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it.take(8_192) },
                    label = { Text("Web address") },
                    placeholder = { Text("https://example.com") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    singleLine = true,
                )
                Text(
                    "The link stays in your durable draft until the note is captured.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = { TextButton(onClick = { onSave(value.trim()) }, enabled = valid) { Text("Add") } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun HistoryScreen(
    items: List<CaptureHistoryItem>,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    retry: (String) -> Unit,
    repairAccess: (String?) -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { VoxTopBar("History", navigateBack) },
    ) { padding ->
        if (items.isEmpty()) {
            EmptyHistory(modifier = Modifier.fillMaxSize().padding(padding))
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(items, key = CaptureHistoryItem::requestID) { item ->
                    HistoryCard(
                        item = item,
                        isBusy = isBusy,
                        retry = { retry(item.requestID) },
                        repairAccess = { repairAccess(item.requestID) },
                    )
                }
            }
        }
    }
}

@Composable
private fun EmptyHistory(modifier: Modifier = Modifier) {
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
        Text("No captures yet", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(8.dp))
        Text(
            "Sent and recoverable captures will appear here without storing their note text.",
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
                Text(historyTitle(item.state), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Text(
                    item.requestID.take(8),
                    style = MaterialTheme.typography.labelMedium.copy(fontFamily = FontFamily.Monospace),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(item.updatedAtEpochMillis)),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (!completed && item.state != CaptureState.DISCARDED) {
                TextButton(onClick = if (needsPermission) repairAccess else retry, enabled = !isBusy) {
                    Icon(
                        if (needsPermission) Icons.Outlined.FolderOpen else Icons.Outlined.Refresh,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(6.dp))
                    Text(if (needsPermission) "Repair Folder Access" else "Retry")
                }
            }
        }
    }
}

private fun historyTitle(state: CaptureState): String = when (state) {
    CaptureState.COMPLETED -> "Capture sent"
    CaptureState.QUEUED, CaptureState.PREPARING, CaptureState.MATERIALIZED, CaptureState.COMMITTING -> "Capture in progress"
    CaptureState.RETRYABLE_FAILURE -> "Ready to retry"
    CaptureState.NEEDS_PERMISSION -> "Folder access needed"
    CaptureState.NEEDS_USER_ACTION -> "Action needed"
    CaptureState.UNKNOWN_OUTCOME -> "Checking delivery"
    CaptureState.PERMANENT_FAILURE -> "Capture failed"
    CaptureState.DISCARDED -> "Capture discarded"
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CapturePresetsScreen(
    collection: CapturePresetCollection?,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    selectPreset: (String) -> Unit,
    editPreset: (String) -> Unit,
    createPreset: () -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text("Capture Presets", style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    IconButton(onClick = navigateBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(onClick = createPreset, enabled = !isBusy && collection != null) {
                        Icon(Icons.Outlined.Add, contentDescription = "New capture preset")
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
                    Text(
                        "A preset freezes the folder, filename, and frontmatter used by a capture before delivery starts.",
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                items(collection.presets, key = CapturePreset::id) { preset ->
                    val active = preset.id == collection.activePresetID
                    ListItem(
                        headlineContent = { Text(preset.name) },
                        supportingContent = {
                            Text(
                                "${preset.logicalFolder}  ·  ${preset.noteNameTemplate}",
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
                                    Icon(
                                        presetIcon(preset.symbol),
                                        contentDescription = null,
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
                                        contentDescription = "Selected",
                                        tint = MaterialTheme.colorScheme.primary,
                                    )
                                }
                                IconButton(onClick = { editPreset(preset.id) }, enabled = !isBusy) {
                                    Icon(Icons.Outlined.Edit, contentDescription = "Edit ${preset.name}")
                                }
                            }
                        },
                        colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                        modifier = Modifier.clickable(enabled = !isBusy) { selectPreset(preset.id) },
                    )
                    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CapturePresetEditorScreen(
    preset: CapturePreset?,
    isBusy: Boolean,
    navigateBack: () -> Unit,
    save: (CapturePreset) -> Unit,
    delete: (() -> Unit)?,
) {
    val id = rememberSaveable(preset?.id) { preset?.id ?: UUID.randomUUID().toString().lowercase() }
    var name by rememberSaveable(preset?.id) { mutableStateOf(preset?.name ?: "") }
    var symbol by rememberSaveable(preset?.id) { mutableStateOf(preset?.symbol ?: "description") }
    var logicalFolder by rememberSaveable(preset?.id) { mutableStateOf(preset?.logicalFolder ?: "Inbox") }
    var noteNameTemplate by rememberSaveable(preset?.id) { mutableStateOf(preset?.noteNameTemplate ?: "capture-{id}.md") }
    var metadataText by rememberSaveable(preset?.id) {
        mutableStateOf(preset?.metadataFields?.joinToString("\n") { "${it.name}=${it.value}" }.orEmpty())
    }
    val metadata = parseMetadataFields(metadataText)
    val valid = name.trim().isNotEmpty() &&
        logicalFolder.trim('/').isNotEmpty() &&
        noteNameTemplate.trim().endsWith(".md", ignoreCase = true) &&
        metadata != null

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(if (preset == null) "New Preset" else "Edit Preset", style = MaterialTheme.typography.titleLarge) },
                navigationIcon = {
                    IconButton(onClick = navigateBack) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(
                        onClick = {
                            save(
                                CapturePreset(
                                    id = id,
                                    name = name,
                                    symbol = symbol,
                                    revision = preset?.revision ?: 1,
                                    logicalFolder = logicalFolder,
                                    noteNameTemplate = noteNameTemplate,
                                    metadataFields = requireNotNull(metadata),
                                ),
                            )
                        },
                        enabled = valid && !isBusy,
                    ) {
                        if (isBusy) {
                            CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                        } else {
                            Icon(Icons.Outlined.CheckCircle, contentDescription = "Save capture preset")
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
            OutlinedTextField(
                value = name,
                onValueChange = { name = it.take(64) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Name") },
                singleLine = true,
            )
            Text("Icon", style = MaterialTheme.typography.titleMedium)
            LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                items(PRESET_SYMBOLS) { option ->
                    val selected = symbol == option
                    Surface(
                        shape = RoundedCornerShape(12.dp),
                        color = if (selected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier
                            .size(48.dp)
                            .clickable { symbol = option }
                            .semantics { contentDescription = "${presetSymbolLabel(option)} preset icon${if (selected) ", selected" else ""}" },
                    ) {
                        Box(contentAlignment = Alignment.Center) {
                            Icon(
                                presetIcon(option),
                                contentDescription = null,
                                tint = if (selected) MaterialTheme.colorScheme.onPrimary else MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }
            }
            OutlinedTextField(
                value = logicalFolder,
                onValueChange = { logicalFolder = it.take(512) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Folder inside Markdown folder") },
                supportingText = { Text("Use / between nested folders, for example Journal/Daily.") },
                singleLine = true,
            )
            OutlinedTextField(
                value = noteNameTemplate,
                onValueChange = { noteNameTemplate = it.take(128) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Filename") },
                supportingText = { Text("{id} is replaced with the durable capture id. Filenames must end in .md.") },
                isError = noteNameTemplate.isNotBlank() && !noteNameTemplate.endsWith(".md", ignoreCase = true),
                singleLine = true,
            )
            OutlinedTextField(
                value = metadataText,
                onValueChange = { metadataText = it.take(8_192) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Frontmatter") },
                placeholder = { Text("source=android\nstatus=inbox") },
                supportingText = {
                    Text(if (metadata == null) "Use one unique name=value field per line." else "Optional. Values are frozen when the capture is saved locally.")
                },
                isError = metadata == null,
                minLines = 3,
            )
            Card(
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                shape = RoundedCornerShape(16.dp),
            ) {
                Text(
                    "Preset changes only affect new captures. A pending capture keeps the exact preset snapshot it started with.",
                    modifier = Modifier.padding(16.dp),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (delete != null) {
                TextButton(onClick = delete, enabled = !isBusy) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.width(8.dp))
                    Text("Delete Preset", color = MaterialTheme.colorScheme.error)
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

private fun parseMetadataFields(value: String): List<CaptureMetadataField>? {
    val lines = value.lines().map(String::trim).filter(String::isNotEmpty)
    if (lines.size > 16) return null
    val fields = lines.map { line ->
        val split = line.indexOf('=')
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

private fun presetSymbolLabel(symbol: String): String = when (symbol) {
    "mic" -> "Microphone"
    "checklist" -> "Checklist"
    "lightbulb" -> "Idea"
    "work" -> "Work"
    "favorite" -> "Favorite"
    else -> "Document"
}

@Composable
private fun SettingsScreen(
    destination: CaptureDestination,
    navigateBack: () -> Unit,
    chooseFolder: () -> Unit,
    openPresets: () -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = { VoxTopBar("Settings", navigateBack) },
    ) { padding ->
        Column(modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState())) {
            SettingsSection("Capture")
            ListItem(
                headlineContent = { Text("Markdown Folder") },
                supportingContent = { Text(destination.displayName, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                leadingContent = { Icon(Icons.Outlined.FolderOpen, contentDescription = null) },
                trailingContent = { Icon(Icons.Outlined.ChevronRight, contentDescription = null) },
                colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
                modifier = Modifier.clickable(onClick = chooseFolder),
            )
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            SettingsSection("Customization")
            PlaceholderSettingsRow("Models", "Local transcription engines and language")
            SettingsNavigationRow(
                title = "Capture Presets",
                subtitle = "Formatting, metadata, filenames, and folders",
                onClick = openPresets,
            )
            PlaceholderSettingsRow("Capture Bar", "Choose, reorder, and hide quick actions")
            HorizontalDivider(color = MaterialTheme.colorScheme.outline)
            SettingsSection("Privacy")
            Text(
                "Capture contents stay on this device until Vox.md writes them to the folder you selected. Android backup is disabled for content-bearing storage.",
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun SettingsNavigationRow(title: String, subtitle: String, onClick: () -> Unit) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(subtitle) },
        trailingContent = { Icon(Icons.Outlined.ChevronRight, contentDescription = null) },
        colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
        modifier = Modifier.clickable(onClick = onClick),
    )
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@Composable
private fun SettingsSection(title: String) {
    Text(
        title,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 28.dp, bottom = 12.dp),
        style = MaterialTheme.typography.titleMedium,
    )
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@Composable
private fun PlaceholderSettingsRow(title: String, subtitle: String) {
    ListItem(
        headlineContent = { Text(title) },
        supportingContent = { Text(subtitle) },
        trailingContent = {
            Text("Planned", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        },
        colors = androidx.compose.material3.ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.background),
    )
    HorizontalDivider(color = MaterialTheme.colorScheme.outline)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun VoxTopBar(title: String, navigateBack: () -> Unit) {
    TopAppBar(
        title = { Text(title, style = MaterialTheme.typography.titleLarge) },
        navigationIcon = {
            IconButton(onClick = navigateBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = "Back")
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
