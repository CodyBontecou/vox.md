package md.vox.android.wear

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
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
    var showsPresets by remember { mutableStateOf(false) }
    var showsQueue by remember { mutableStateOf(false) }
    var syncMessage by remember { mutableStateOf<String?>(null) }
    var isSyncing by remember { mutableStateOf(false) }
    var isStarting by remember { mutableStateOf(false) }
    var unavailableMessage by remember { mutableStateOf<String?>(null) }
    var pendingRecordingPreset by remember { mutableStateOf<CapturePreset?>(null) }
    val syncingLabel = stringResource(R.string.wear_syncing)
    val queuedLabel = stringResource(R.string.wear_queued)
    val nothingToSyncLabel = stringResource(R.string.wear_nothing_to_sync)
    val savedOnWatchLabel = stringResource(R.string.wear_saved_watch)
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

    fun start() {
        val selected = WearPresetStore.selected()
        val preset = RecordingPresetSnapshotCodec.decode(selected.snapshot.toString(Charsets.UTF_8))
            ?: CapturePreset(
                id = selected.id,
                name = selected.name,
                symbol = selected.symbol,
                revision = 1,
                logicalFolder = "Daily",
                noteNameTemplate = "daily-{uuid}.md",
                metadataFields = emptyList(),
            )
        pendingRecordingPreset = preset
        isStarting = true
        unavailableMessage = null
        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            client.start(preset)
            pendingRecordingPreset = null
        } else {
            permissionLauncher.launch(permissions)
        }
    }

    LaunchedEffect(Unit) {
        WearPresetStore.load(context)
        WearQueueStore.load(context)
    }
    LaunchedEffect(status.sessionID, status.phase, status.chunkCount) {
        if (status.phase != RecordingPhase.IDLE) isStarting = false
        WearSystemSurfaces.requestRefresh(context)
        val id = status.sessionID ?: return@LaunchedEffect
        when (status.phase) {
            RecordingPhase.RECORDING, RecordingPhase.PAUSED -> {
                WearQueueStore.begin(context, id, status.createdAtEpochMillis, WearPresetStore.selected())
            }
            RecordingPhase.COMPLETED, RecordingPhase.INTERRUPTED, RecordingPhase.FAILED -> {
                if (status.chunkCount > 0) {
                    WearQueueStore.finish(context, id, status.elapsedMillis, status.chunkCount)
                    if (status.phase == RecordingPhase.COMPLETED) {
                        scope.launch {
                            val synced = WearDataBridge.syncAll(context)
                            syncMessage = if (synced > 0) queuedLabel else savedOnWatchLabel
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

    Scaffold {
        if (showsPresets) {
            PresetPicker(
                presets = presets,
                selectedPresetID = selectedPresetID,
                select = { preset ->
                    WearPresetStore.select(context, preset.id)
                    showsPresets = false
                },
                close = { showsPresets = false },
            )
        } else if (showsQueue) {
            WearQueueScreen(
                queue = queue,
                retry = { recordingID ->
                    scope.launch {
                        WearQueueStore.prepareRetry(context, recordingID)
                        isSyncing = true
                        syncMessage = syncingLabel
                        val count = WearDataBridge.syncAll(context)
                        syncMessage = if (count > 0) queuedLabel else nothingToSyncLabel
                        isSyncing = false
                    }
                },
                discard = { recordingID ->
                    if (WearQueueStore.discard(context, recordingID)) {
                        syncMessage = nothingToSyncLabel
                    }
                },
                close = { showsQueue = false },
            )
        } else {
            WearRecorderContent(
                status = status,
                queue = queue,
                selectedPreset = WearPresetStore.selected(),
                syncMessage = syncMessage,
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
                showPresets = { showsPresets = true },
                showQueue = { showsQueue = true },
                sync = {
                    scope.launch {
                        isSyncing = true
                        syncMessage = syncingLabel
                        val count = WearDataBridge.syncAll(context)
                        syncMessage = if (count > 0) queuedLabel else nothingToSyncLabel
                        isSyncing = false
                    }
                },
            )
        }
    }
}

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
    selectedPreset: WearPreset,
    syncMessage: String?,
    isStarting: Boolean,
    isSyncing: Boolean,
    unavailableMessage: String?,
    pauseActionLabel: String,
    resumeActionLabel: String,
    stopActionLabel: String,
    cancelActionLabel: String,
    startActionLabel: String,
    start: () -> Unit,
    pause: () -> Unit,
    resume: () -> Unit,
    stop: () -> Unit,
    cancel: () -> Unit,
    showPresets: () -> Unit,
    showQueue: () -> Unit,
    sync: () -> Unit,
) {
    val displayPhase = resolveWearDisplayPhase(status, queue, isStarting, isSyncing, unavailableMessage)
    val listState = rememberScalingLazyListState(initialCenterItemIndex = 0)
    LaunchedEffect(status.phase) {
        if (status.isActive) listState.scrollToItem(0)
    }
    ScalingLazyColumn(
        modifier = Modifier.fillMaxSize(),
        state = listState,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        item {
            Column(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(stringResource(R.string.wear_brand), style = MaterialTheme.typography.caption1)
                Text(wearDisplayTitle(displayPhase), style = MaterialTheme.typography.title3)
                Text(
                    formatWearDuration(status.elapsedMillis),
                    style = MaterialTheme.typography.display2.copy(fontFamily = WearGeistMonoFontFamily),
                )
                if (status.isActive) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(
                            onClick = if (status.phase == RecordingPhase.PAUSED) resume else pause,
                            modifier = Modifier.size(52.dp).semantics {
                                contentDescription = if (status.phase == RecordingPhase.PAUSED) resumeActionLabel else pauseActionLabel
                                role = Role.Button
                            },
                        ) { Text(if (status.phase == RecordingPhase.PAUSED) "▶" else "Ⅱ") }
                        Button(
                            onClick = stop,
                            modifier = Modifier.size(52.dp).semantics {
                                contentDescription = stopActionLabel
                                role = Role.Button
                            },
                            colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFFF565F)),
                        ) { Text("■") }
                        Button(
                            onClick = cancel,
                            modifier = Modifier.size(52.dp).semantics {
                                contentDescription = cancelActionLabel
                                role = Role.Button
                            },
                        ) { Text("×") }
                    }
                } else {
                    Button(
                        onClick = start,
                        enabled = !isStarting,
                        modifier = Modifier.size(72.dp).semantics {
                            contentDescription = startActionLabel
                            role = Role.Button
                        },
                        colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFF2F1EE), contentColor = Color(0xFF171614)),
                    ) { Text("REC") }
                }
                Text(
                    unavailableMessage ?: wearDisplayDetail(displayPhase, queue.size),
                    style = MaterialTheme.typography.caption1,
                )
            }
        }
        item {
            Chip(
                label = { Text(selectedPreset.name) },
                secondaryLabel = { Text(stringResource(R.string.wear_capture_preset)) },
                onClick = showPresets,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                colors = ChipDefaults.secondaryChipColors(),
            )
        }
        if (queue.isNotEmpty()) {
            item {
                Chip(
                    label = { Text(stringResource(R.string.wear_review_recordings)) },
                    secondaryLabel = { Text(savedRecordingsLabel(queue.size)) },
                    onClick = showQueue,
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
                    colors = ChipDefaults.secondaryChipColors(),
                )
            }
        }
        item {
            Chip(
                label = { Text(if (queue.isEmpty()) stringResource(R.string.wear_sync_status) else stringResource(R.string.wear_sync)) },
                secondaryLabel = { Text(syncMessage ?: queueSummary(queue)) },
                onClick = sync,
                enabled = !isSyncing && !status.isActive,
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
            )
        }
        item { Spacer(Modifier.height(20.dp)) }
    }
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
                    colors = ChipDefaults.primaryChipColors(backgroundColor = Color(0xFFFF565F)),
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
                                colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFFFF565F)),
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
internal fun PresetPicker(
    presets: List<WearPreset>,
    selectedPresetID: String,
    select: (WearPreset) -> Unit,
    close: () -> Unit,
) {
    ScalingLazyColumn(modifier = Modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        item { Spacer(Modifier.height(28.dp)) }
        item { Text(stringResource(R.string.wear_capture_preset), style = MaterialTheme.typography.title3) }
        items(presets, key = WearPreset::id) { preset ->
            Chip(
                label = { Text(preset.name) },
                secondaryLabel = if (preset.id == selectedPresetID) ({ Text(stringResource(R.string.wear_selected)) }) else null,
                onClick = { select(preset) },
                modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp),
            )
        }
        item { Chip(label = { Text(stringResource(R.string.wear_done)) }, onClick = close, modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp)) }
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
private fun wearDisplayDetail(phase: WearDisplayPhase, queuedCount: Int): String = when (phase) {
    WearDisplayPhase.RECORDING -> stringResource(R.string.wear_recording_detail)
    WearDisplayPhase.PAUSED -> stringResource(R.string.wear_paused_detail)
    WearDisplayPhase.LISTENING -> stringResource(R.string.wear_listening_detail)
    WearDisplayPhase.TRANSCRIBING -> stringResource(R.string.wear_remote_transcribing)
    WearDisplayPhase.DELIVERING -> stringResource(R.string.wear_remote_saving)
    WearDisplayPhase.ERROR -> stringResource(R.string.wear_failure_detail)
    WearDisplayPhase.UNAVAILABLE -> stringResource(R.string.wear_unavailable_detail)
    WearDisplayPhase.SYNCING -> stringResource(R.string.wear_syncing_detail)
    WearDisplayPhase.PENDING -> stringResource(R.string.wear_pending_detail)
    WearDisplayPhase.DELIVERED -> stringResource(R.string.wear_delivery_complete)
    WearDisplayPhase.IDLE -> if (queuedCount > 0) savedRecordingsLabel(queuedCount) else stringResource(R.string.wear_ready_detail)
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
private fun queueSummary(queue: List<WearQueueItem>): String = when {
    queue.isEmpty() -> stringResource(R.string.wear_nothing_to_sync)
    queue.any { it.phase == WearQueuePhase.PHONE_DELIVERING } -> stringResource(R.string.wear_remote_saving)
    queue.any { it.phase == WearQueuePhase.PHONE_TRANSCRIBING } -> stringResource(R.string.wear_remote_transcribing)
    queue.any { it.phase in setOf(WearQueuePhase.PHONE_RECEIVING, WearQueuePhase.PHONE_QUEUED, WearQueuePhase.PHONE_INGESTED) } ->
        stringResource(R.string.wear_remote_waiting)
    queue.any { it.phase == WearQueuePhase.FAILED } -> stringResource(R.string.wear_remote_failed)
    queue.any { it.phase == WearQueuePhase.TRANSPORT_FAILED } -> stringResource(R.string.wear_remote_transport_failed)
    else -> stringResource(R.string.wear_queue_preserved)
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
            primary = Color(0xFFF2F1EE),
            background = Color(0xFF1A1A1C),
            surface = Color(0xFF1F1F1F),
            error = Color(0xFFFF565F),
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
