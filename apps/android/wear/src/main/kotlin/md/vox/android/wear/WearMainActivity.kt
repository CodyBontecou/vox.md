package md.vox.android.wear

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.itemsIndexed
import androidx.wear.compose.foundation.rotary.RotaryScrollableDefaults
import androidx.wear.compose.foundation.rotary.rotaryScrollable
import androidx.wear.compose.material.ListHeader
import androidx.wear.compose.material.TimeText
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.Typography
import kotlinx.coroutines.launch
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingPresetSnapshotCodec
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingStatusRegistry

class WearMainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { WearVoxTheme { WearRecorderScreen() } }
    }
}

@Composable
private fun WearRecorderScreen() {
    val context = LocalContext.current
    val client = remember(context) { AudioCaptureClient(context) }
    val status by RecordingStatusRegistry.status.collectAsStateWithLifecycle()
    val queue by WearQueueStore.items.collectAsStateWithLifecycle()
    val presets by WearPresetStore.presets.collectAsStateWithLifecycle()
    val selectedPresetID by WearPresetStore.selection.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    var showsQueue by remember { mutableStateOf(false) }
    var isSyncing by remember { mutableStateOf(false) }
    var isStarting by remember { mutableStateOf(false) }
    var unavailableMessage by remember { mutableStateOf<String?>(null) }
    var pendingRecordingPreset by remember { mutableStateOf<CapturePreset?>(null) }
    var result by remember { mutableStateOf<WearRecordingResult?>(null) }
    // The status registry keeps the last session's terminal phase across launches; only a session
    // this screen saw recording may produce a result screen.
    var observedSessionID by remember { mutableStateOf<String?>(null) }
    val levels = remember { mutableStateListOf<Float>().apply { repeat(WEAR_LEVEL_BARS) { add(0f) } } }
    val pauseActionLabel = stringResource(R.string.wear_pause_action)
    val resumeActionLabel = stringResource(R.string.wear_resume_action)
    val stopActionLabel = stringResource(R.string.wear_stop_action)
    val cancelActionLabel = stringResource(R.string.wear_cancel_action)
    val startActionLabel = stringResource(R.string.wear_start_action)
    val microphoneUnavailableLabel = stringResource(R.string.wear_microphone_unavailable)
    val permissions = remember {
        buildList {
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
        }.toTypedArray()
    }
    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        if (grants[Manifest.permission.RECORD_AUDIO] == true) {
            pendingRecordingPreset?.let { preset ->
                unavailableMessage = null
                client.start(preset)
            }
        } else {
            isStarting = false
            unavailableMessage = microphoneUnavailableLabel
        }
        pendingRecordingPreset = null
    }

    fun start(preset: WearPreset) {
        WearPresetStore.select(context, preset.id)
        val selected = WearPresetStore.selected()
        val capturePreset = RecordingPresetSnapshotCodec.decode(selected.snapshot.toString(Charsets.UTF_8))
            ?: CapturePreset(
                id = selected.id,
                name = selected.name,
                symbol = selected.symbol,
                revision = 1,
                logicalFolder = "Daily",
                noteNameTemplate = "daily-{uuid}.md",
                metadataFields = emptyList(),
            )
        result = null
        pendingRecordingPreset = capturePreset
        isStarting = true
        unavailableMessage = null
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            client.start(capturePreset)
            pendingRecordingPreset = null
        } else {
            permissionLauncher.launch(permissions)
        }
    }

    LaunchedEffect(Unit) {
        WearPresetStore.load(context)
        WearQueueStore.load(context)
    }
    LaunchedEffect(status.sessionID) {
        for (index in levels.indices) levels[index] = 0f
    }
    LaunchedEffect(status.elapsedMillis, status.level) {
        if (status.phase == RecordingPhase.RECORDING) {
            levels.removeAt(0)
            levels.add(status.level)
        }
    }
    LaunchedEffect(status.sessionID, status.phase, status.chunkCount) {
        if (status.phase != RecordingPhase.IDLE) isStarting = false
        WearSystemSurfaces.requestRefresh(context)
        val id = status.sessionID ?: return@LaunchedEffect
        when (status.phase) {
            RecordingPhase.RECORDING, RecordingPhase.PAUSED -> {
                observedSessionID = id
                WearQueueStore.begin(context, id, status.createdAtEpochMillis, WearPresetStore.selected())
            }
            RecordingPhase.COMPLETED, RecordingPhase.INTERRUPTED, RecordingPhase.FAILED -> {
                if (status.chunkCount > 0) {
                    WearQueueStore.finish(context, id, status.elapsedMillis, status.chunkCount)
                    if (status.phase == RecordingPhase.COMPLETED && id == observedSessionID) {
                        observedSessionID = null
                        val preset = WearPresetStore.selected()
                        val duration = status.elapsedMillis
                        scope.launch {
                            val synced = WearDataBridge.syncAll(context)
                            val reachable = WearDataBridge.isPhoneConnected(context)
                            result = WearRecordingResult(preset.id, preset.name, duration, sentToPhone = synced > 0 && reachable)
                        }
                    }
                }
            }
            RecordingPhase.DISCARDED -> {
                client.deleteRecording(id)
                WearQueueStore.load(context)
            }
            else -> Unit
        }
    }
    LaunchedEffect(queue) { WearSystemSurfaces.requestRefresh(context) }

    if (showsQueue) {
        WearQueueScreen(
            queue = queue,
            retry = { recordingID ->
                scope.launch {
                    WearQueueStore.prepareRetry(context, recordingID)
                    isSyncing = true
                    WearDataBridge.syncAll(context)
                    isSyncing = false
                }
            },
            discard = { recordingID -> WearQueueStore.discard(context, recordingID) },
            close = { showsQueue = false },
        )
    } else {
        WearRecorderContent(
            status = status,
            queue = queue,
            presets = presets,
            recordingPreset = presets.firstOrNull { it.id == selectedPresetID } ?: WearPresetStore.selected(),
            levels = levels,
            result = result,
            isStarting = isStarting,
            isSyncing = isSyncing,
            unavailableMessage = unavailableMessage,
            pauseActionLabel = pauseActionLabel,
            resumeActionLabel = resumeActionLabel,
            stopActionLabel = stopActionLabel,
            cancelActionLabel = cancelActionLabel,
            startActionLabel = startActionLabel,
            start = ::start,
            pause = client::pause,
            resume = client::resume,
            stop = client::stop,
            cancel = client::cancel,
            showQueue = { showsQueue = true },
            speakAgain = { finished ->
                start(presets.firstOrNull { it.id == finished.presetID } ?: WearPresetStore.selected())
            },
            dismissResult = { result = null },
        )
    }
}

internal const val WEAR_LEVEL_BARS = 26

/** What the watch shows after Stop: handed to the phone, or kept on the watch until it is reachable. */
internal data class WearRecordingResult(
    val presetID: String,
    val presetName: String,
    val durationMillis: Long,
    val sentToPhone: Boolean,
)

internal enum class WearDisplayPhase {
    IDLE,
    LISTENING,
    RECORDING,
    PAUSED,
    PENDING,
    SYNCING,
    TRANSCRIBING,
    DELIVERING,
    DELIVERED,
    ERROR,
    UNAVAILABLE,
}

internal fun resolveWearDisplayPhase(
    status: RecordingStatus,
    queue: List<WearQueueItem>,
    isStarting: Boolean,
    isSyncing: Boolean,
    unavailableMessage: String?,
): WearDisplayPhase = when {
    status.phase == RecordingPhase.RECORDING -> WearDisplayPhase.RECORDING
    status.phase == RecordingPhase.PAUSED -> WearDisplayPhase.PAUSED
    isStarting -> WearDisplayPhase.LISTENING
    status.phase in setOf(RecordingPhase.FAILED, RecordingPhase.INTERRUPTED) ||
        queue.any { it.phase == WearQueuePhase.FAILED } -> WearDisplayPhase.ERROR
    unavailableMessage != null || queue.any { it.phase == WearQueuePhase.TRANSPORT_FAILED } -> WearDisplayPhase.UNAVAILABLE
    queue.any { it.phase == WearQueuePhase.PHONE_DELIVERING } -> WearDisplayPhase.DELIVERING
    queue.any { it.phase == WearQueuePhase.PHONE_TRANSCRIBING } -> WearDisplayPhase.TRANSCRIBING
    isSyncing || queue.any { it.phase == WearQueuePhase.SYNC_QUEUED } -> WearDisplayPhase.SYNCING
    queue.any { it.phase in setOf(WearQueuePhase.PHONE_QUEUED, WearQueuePhase.PHONE_RECEIVING, WearQueuePhase.PHONE_INGESTED) } ->
        WearDisplayPhase.PENDING
    status.phase == RecordingPhase.COMPLETED -> WearDisplayPhase.DELIVERED
    queue.any { it.phase == WearQueuePhase.LOCAL } -> WearDisplayPhase.PENDING
    else -> WearDisplayPhase.IDLE
}

@Composable
internal fun WearRecorderContent(
    status: RecordingStatus,
    queue: List<WearQueueItem>,
    presets: List<WearPreset>,
    recordingPreset: WearPreset,
    levels: List<Float>,
    result: WearRecordingResult?,
    isStarting: Boolean,
    isSyncing: Boolean,
    unavailableMessage: String?,
    pauseActionLabel: String,
    resumeActionLabel: String,
    stopActionLabel: String,
    cancelActionLabel: String,
    startActionLabel: String,
    start: (WearPreset) -> Unit,
    pause: () -> Unit,
    resume: () -> Unit,
    stop: () -> Unit,
    cancel: () -> Unit,
    showQueue: () -> Unit,
    speakAgain: (WearRecordingResult) -> Unit,
    dismissResult: () -> Unit,
) {
    Scaffold(timeText = { TimeText() }) {
        when {
            status.isActive -> WearRecordingScreen(
                status = status,
                preset = recordingPreset,
                presetIndex = presets.indexOfFirst { it.id == recordingPreset.id }.coerceAtLeast(0),
                levels = levels,
                pauseActionLabel = pauseActionLabel,
                resumeActionLabel = resumeActionLabel,
                stopActionLabel = stopActionLabel,
                cancelActionLabel = cancelActionLabel,
                pause = pause,
                resume = resume,
                stop = stop,
                cancel = cancel,
            )
            result != null -> WearResultScreen(
                result = result,
                speakAgain = { speakAgain(result) },
                dismiss = dismissResult,
            )
            else -> WearHomeScreen(
                presets = presets,
                displayPhase = resolveWearDisplayPhase(status, queue, isStarting, isSyncing, unavailableMessage),
                queue = queue,
                isStarting = isStarting,
                unavailableMessage = unavailableMessage,
                startActionLabel = startActionLabel,
                start = start,
                showQueue = showQueue,
            )
        }
    }
}

/** "Speak to…": one tap on a preset starts recording to it. */
@Composable
private fun WearHomeScreen(
    presets: List<WearPreset>,
    displayPhase: WearDisplayPhase,
    queue: List<WearQueueItem>,
    isStarting: Boolean,
    unavailableMessage: String?,
    startActionLabel: String,
    start: (WearPreset) -> Unit,
    showQueue: () -> Unit,
) {
    val listState = rememberScalingLazyListState(initialCenterItemIndex = 1)
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item {
            ListHeader {
                Text(
                    stringResource(R.string.wear_speak_to),
                    color = WearSignal.accent,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
        itemsIndexed(presets, key = { _, preset -> preset.id }) { index, preset ->
            Chip(
                onClick = { start(preset) },
                enabled = !isStarting,
                label = {
                    Text(
                        preset.name,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                },
                icon = { WearPresetTile(preset.name, index) },
                colors = ChipDefaults.chipColors(backgroundColor = WearSignal.surface, contentColor = WearSignal.text),
                modifier = Modifier.fillMaxWidth().semantics { contentDescription = startActionLabel },
            )
        }
        if (displayPhase != WearDisplayPhase.IDLE) {
            item {
                WearStatusCard(
                    phase = displayPhase,
                    queuedCount = queue.size,
                    message = unavailableMessage,
                    onClick = showQueue.takeIf { queue.isNotEmpty() },
                )
            }
        }
    }
}

/** Compact pipeline status under the presets; hidden when there is nothing to report. */
@Composable
private fun WearStatusCard(phase: WearDisplayPhase, queuedCount: Int, message: String?, onClick: (() -> Unit)?) {
    val isProblem = phase == WearDisplayPhase.ERROR || phase == WearDisplayPhase.UNAVAILABLE
    val detail = when {
        message != null -> message
        queuedCount > 0 -> savedRecordingsLabel(queuedCount)
        else -> null
    }
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(16.dp))
            .background(WearSignal.surface)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        Text(
            wearDisplayTitle(phase),
            color = if (isProblem) WearSignal.redText else WearSignal.text,
            fontSize = 14.sp,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
        )
        if (detail != null) {
            Text(detail, color = WearSignal.muted, fontSize = 12.sp, textAlign = TextAlign.Center, maxLines = 3)
        }
    }
}

/** Preset, timer and live levels above one Stop button; Pause/Resume and Cancel sit below the fold. */
@Composable
private fun WearRecordingScreen(
    status: RecordingStatus,
    preset: WearPreset,
    presetIndex: Int,
    levels: List<Float>,
    pauseActionLabel: String,
    resumeActionLabel: String,
    stopActionLabel: String,
    cancelActionLabel: String,
    pause: () -> Unit,
    resume: () -> Unit,
    stop: () -> Unit,
    cancel: () -> Unit,
) {
    val isPaused = status.phase == RecordingPhase.PAUSED
    WearFoldedScreen(
        primary = {
            Column(
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 34.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    WearPresetTile(preset.name, presetIndex, size = 15.dp)
                    Text(preset.name, color = WearSignal.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    if (isPaused) {
                        Text("· " + stringResource(R.string.wear_paused), color = WearSignal.muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                    }
                }
                Text(
                    formatWearDuration(status.elapsedMillis),
                    color = if (isPaused) WearSignal.muted else WearSignal.text,
                    fontFamily = WearGeistMonoFontFamily,
                    fontWeight = FontWeight.Medium,
                    fontSize = 46.sp,
                )
                WearLevelWaveform(levels, isPaused, Modifier.width(148.dp).height(26.dp))
            }
            WearEdgeButton(
                label = stringResource(R.string.wear_stop),
                description = stopActionLabel,
                background = WearSignal.red,
                onClick = stop,
                glyph = WearGlyph.STOP,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        },
        secondary = {
            if (isPaused) {
                WearPillButton(stringResource(R.string.wear_resume), resumeActionLabel, WearGlyph.PLAY, resume)
            } else {
                WearPillButton(stringResource(R.string.wear_pause), pauseActionLabel, WearGlyph.PAUSE, pause)
            }
            WearPillButton(
                stringResource(R.string.wear_cancel),
                cancelActionLabel,
                WearGlyph.CANCEL,
                cancel,
                contentColor = WearSignal.redText,
            )
        },
    )
}

/** After Stop: handed to the phone, or kept on the watch until the phone is reachable. */
@Composable
private fun WearResultScreen(result: WearRecordingResult, speakAgain: () -> Unit, dismiss: () -> Unit) {
    val speakAgainLabel = stringResource(R.string.wear_speak_again)
    val doneLabel = stringResource(R.string.wear_done)
    WearFoldedScreen(
        primary = {
            Column(
                modifier = Modifier.align(Alignment.TopCenter).padding(top = 32.dp, start = 20.dp, end = 20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(52.dp)
                        .clip(CircleShape)
                        .background(if (result.sentToPhone) WearSignal.greenBackground else WearSignal.surface),
                    contentAlignment = Alignment.Center,
                ) {
                    WearGlyphIcon(
                        if (result.sentToPhone) WearGlyph.CHECK else WearGlyph.SAVED,
                        if (result.sentToPhone) WearSignal.green else WearSignal.accent,
                        22.dp,
                    )
                }
                Text(
                    if (result.sentToPhone) stringResource(R.string.wear_sent_to, result.presetName)
                    else stringResource(R.string.wear_saved_on_watch),
                    color = WearSignal.text,
                    fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold,
                    textAlign = TextAlign.Center,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    if (result.sentToPhone) formatWearDuration(result.durationMillis)
                    else formatWearDuration(result.durationMillis) + " · " + stringResource(R.string.wear_remote_waiting),
                    color = WearSignal.muted,
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                )
            }
            WearEdgeButton(
                label = speakAgainLabel,
                description = speakAgainLabel,
                background = WearSignal.accentFill,
                onClick = speakAgain,
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        },
        secondary = {
            WearPillButton(doneLabel, doneLabel, WearGlyph.CHECK, dismiss)
        },
    )
}

/**
 * A full-screen first page (content plus its edge button), then secondary actions reached by scrolling
 * or the crown, matching the Apple Watch recording screen's fold.
 */
@Composable
private fun WearFoldedScreen(
    primary: @Composable BoxScope.() -> Unit,
    secondary: @Composable ColumnScope.() -> Unit,
) {
    val scrollState = rememberScrollState()
    val focusRequester = remember { FocusRequester() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val screenHeight = maxHeight
        Column(
            modifier = Modifier
                .fillMaxSize()
                .rotaryScrollable(RotaryScrollableDefaults.behavior(scrollableState = scrollState), focusRequester)
                .verticalScroll(scrollState),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(Modifier.fillMaxWidth().height(screenHeight), content = primary)
            Column(
                modifier = Modifier.fillMaxWidth().padding(start = 30.dp, end = 30.dp, top = 8.dp, bottom = 40.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
                content = secondary,
            )
        }
    }
    LaunchedEffect(Unit) { focusRequester.requestFocus() }
}

@Composable
internal fun WearQueueScreen(
    queue: List<WearQueueItem>,
    retry: (String) -> Unit,
    discard: (String) -> Unit,
    close: () -> Unit,
) {
    var pendingDiscard by remember { mutableStateOf<WearQueueItem?>(null) }
    val retryLabel = stringResource(R.string.wear_retry_action)
    val discardLabel = stringResource(R.string.wear_discard_action)
    val pending = pendingDiscard
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item { Spacer(Modifier.height(28.dp)) }
        if (pending != null) {
            item { Text(stringResource(R.string.wear_confirm_discard_title), style = MaterialTheme.typography.title3) }
            item { Text(stringResource(R.string.wear_confirm_discard_detail, pending.presetName)) }
            item {
                Chip(
                    label = { Text(stringResource(R.string.wear_discard_recording)) },
                    onClick = {
                        discard(pending.recordingID)
                        pendingDiscard = null
                    },
                    colors = ChipDefaults.primaryChipColors(backgroundColor = Color(0xFFFF6B6B)),
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                )
            }
            item {
                Chip(
                    label = { Text(stringResource(R.string.wear_keep_recording)) },
                    onClick = { pendingDiscard = null },
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                )
            }
        } else {
            item { Text(stringResource(R.string.wear_saved_recordings), style = MaterialTheme.typography.title3) }
            if (queue.isEmpty()) {
                item { Text(stringResource(R.string.wear_nothing_to_sync)) }
            }
            items(queue, key = WearQueueItem::recordingID) { item ->
                Column(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Text(item.presetName, style = MaterialTheme.typography.title3)
                    Text(wearQueuePhaseLabel(item.phase), style = MaterialTheme.typography.caption1)
                    if (item.phase in setOf(
                            WearQueuePhase.LOCAL,
                            WearQueuePhase.SYNC_QUEUED,
                            WearQueuePhase.FAILED,
                            WearQueuePhase.TRANSPORT_FAILED,
                        )
                    ) {
                        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Button(
                                onClick = { retry(item.recordingID) },
                                modifier = Modifier.size(48.dp).semantics {
                                    contentDescription = retryLabel
                                    role = Role.Button
                                },
                            ) { Text("↻") }
                            Button(
                                onClick = { pendingDiscard = item },
                                modifier = Modifier.size(48.dp).semantics {
                                    contentDescription = discardLabel
                                    role = Role.Button
                                },
                                colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFFF6B6B)),
                            ) { Text("×") }
                        }
                    }
                }
            }
            item {
                Chip(
                    label = { Text(stringResource(R.string.wear_back)) },
                    onClick = close,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                )
            }
        }
        item { Spacer(Modifier.height(20.dp)) }
    }
}

@Composable
private fun wearDisplayTitle(phase: WearDisplayPhase): String = when (phase) {
    WearDisplayPhase.IDLE -> stringResource(R.string.wear_ready)
    WearDisplayPhase.LISTENING -> stringResource(R.string.wear_listening)
    WearDisplayPhase.RECORDING -> stringResource(R.string.wear_recording)
    WearDisplayPhase.PAUSED -> stringResource(R.string.wear_paused)
    WearDisplayPhase.PENDING -> stringResource(R.string.wear_pending)
    WearDisplayPhase.SYNCING -> stringResource(R.string.wear_syncing)
    WearDisplayPhase.TRANSCRIBING -> stringResource(R.string.wear_remote_transcribing)
    WearDisplayPhase.DELIVERING -> stringResource(R.string.wear_delivering)
    WearDisplayPhase.DELIVERED -> stringResource(R.string.wear_saved)
    WearDisplayPhase.ERROR -> stringResource(R.string.wear_needs_attention)
    WearDisplayPhase.UNAVAILABLE -> stringResource(R.string.wear_unavailable)
}

@Composable
private fun wearQueuePhaseLabel(phase: WearQueuePhase): String = when (phase) {
    WearQueuePhase.LOCAL -> stringResource(R.string.wear_saved_watch)
    WearQueuePhase.SYNC_QUEUED -> stringResource(R.string.wear_syncing)
    WearQueuePhase.PHONE_RECEIVING -> stringResource(R.string.wear_phone_receiving)
    WearQueuePhase.PHONE_QUEUED, WearQueuePhase.PHONE_INGESTED -> stringResource(R.string.wear_remote_waiting)
    WearQueuePhase.PHONE_TRANSCRIBING -> stringResource(R.string.wear_remote_transcribing)
    WearQueuePhase.PHONE_DELIVERING -> stringResource(R.string.wear_remote_saving)
    WearQueuePhase.DELIVERED -> stringResource(R.string.wear_synced)
    WearQueuePhase.FAILED -> stringResource(R.string.wear_remote_failed)
    WearQueuePhase.TRANSPORT_FAILED -> stringResource(R.string.wear_remote_transport_failed)
}


@Composable
private fun savedRecordingsLabel(count: Int): String = if (count == 1) {
    stringResource(R.string.wear_one_recording_saved)
} else stringResource(R.string.wear_recordings_saved_count, count)

private fun formatWearDuration(milliseconds: Long): String {
    val seconds = milliseconds.coerceAtLeast(0) / 1_000
    return "%d:%02d".format(seconds / 60, seconds % 60)
}

@Composable
internal fun WearVoxTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colors = MaterialTheme.colors.copy(
            primary = Color(0xFFBEC2FF),
            onPrimary = Color(0xFF0E1690),
            background = Color(0xFF000000),
            surface = Color(0xFF1F1F23),
            error = Color(0xFFFF6B6B),
        ),
        typography = Typography(defaultFontFamily = WearGeistFontFamily),
        content = content,
    )
}

internal val WearGeistFontFamily = FontFamily(
    Font(R.font.geist_regular, weight = FontWeight.Normal),
    Font(R.font.geist_medium, weight = FontWeight.Medium),
    Font(R.font.geist_semibold, weight = FontWeight.SemiBold),
)

internal val WearGeistMonoFontFamily = FontFamily(
    Font(R.font.geist_mono_regular, weight = FontWeight.Normal),
    Font(R.font.geist_mono_medium, weight = FontWeight.Medium),
)
