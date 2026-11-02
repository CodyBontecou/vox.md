package md.vox.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Send
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.GraphicEq
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.RecordVoiceOver
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.InstructionModel
import md.vox.android.platformservices.InstructionModelManager
import md.vox.android.platformservices.InstructionModelPhase
import md.vox.android.platformservices.InstructionModelState
import md.vox.android.platformservices.OnDeviceSpeechAvailability
import md.vox.android.platformservices.OnDeviceSpeechCapability
import md.vox.android.platformservices.OnDeviceSpeechProbe
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingJobPolicy
import md.vox.android.platformservices.RecordingJobPolicyStore
import md.vox.android.platformservices.RecordingProcessingPolicy
import md.vox.android.platformservices.RecordingRetentionKind
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingMediaImportResult
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.WearRemoteRecordingPhase
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.platformservices.SpeechModelInstallPhase
import md.vox.android.platformservices.SpeechModelInstallState
import md.vox.android.platformservices.SpeechModelEngine
import md.vox.android.platformservices.SpeechModelManager
import md.vox.android.platformservices.SpeechModelManagerState
import md.vox.android.platformservices.SpeechModelSelectionMode
import md.vox.android.platformservices.SpeakerModelInstallPhase
import md.vox.android.platformservices.SpeakerModelManager
import md.vox.android.platformservices.SpeakerModelState
import md.vox.android.platformservices.VoiceAutoStopEndAction
import md.vox.android.platformservices.VoiceAutoStopSettings
import md.vox.android.platformservices.VoiceAutoStopSettingsStore
import md.vox.android.platformservices.shouldDeleteRecordingAudio
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalBanner
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalDivider
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalIconTile
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalSectionLabel
import md.vox.android.ui.SignalStatus
import md.vox.android.ui.SignalStatusBadge
import md.vox.android.ui.SignalSwitch
import md.vox.android.ui.SignalType
import md.vox.android.ui.signalStatusColors
import java.text.DateFormat
import java.io.File
import java.util.Date
import java.util.Locale

// region Recording queue

@Composable
internal fun RecordingQueueScreen(
    client: AudioCaptureClient,
    currentStatus: RecordingStatus,
    importPreset: CapturePreset?,
    availablePresets: List<CapturePreset>,
    navigateBack: () -> Unit,
    resume: () -> Unit,
    finish: () -> Unit,
    cancel: () -> Unit,
    addToDraft: (String, String) -> Unit,
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val transcriptionClient = remember(context) { RecordingTranscriptionClient.get(context) }
    val transcriptionStates by transcriptionClient.states.collectAsStateWithLifecycle()
    val modelManager = remember(context) { SpeechModelManager.get(context) }
    val modelState by modelManager.state.collectAsStateWithLifecycle()
    val policyStore = remember(context) { RecordingJobPolicyStore.get(context) }
    var recordings by remember { mutableStateOf(client.recordings()) }
    var policies by remember { mutableStateOf(recordings.associate { requireNotNull(it.sessionID) to policyStore.policy(requireNotNull(it.sessionID)) }) }
    var pendingExport by remember { mutableStateOf<RecordingStatus?>(null) }
    var pendingDelete by remember { mutableStateOf<RecordingStatus?>(null) }
    var operationMessage by remember { mutableStateOf<VoxUiText?>(null) }
    var isExporting by remember { mutableStateOf(false) }
    var isImporting by remember { mutableStateOf(false) }
    val mediaImporter = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val preset = importPreset
        if (uri != null && preset != null) {
            scope.launch {
                isImporting = true
                val result = withContext(Dispatchers.IO) { client.importMedia(uri.toString(), preset) }
                isImporting = false
                when (result) {
                    is RecordingMediaImportResult.Imported -> {
                        operationMessage = voxUiText("Media audio imported for private transcription.")
                        recordings = client.recordings()
                        policies = recordings.associate {
                            requireNotNull(it.sessionID) to policyStore.policy(requireNotNull(it.sessionID))
                        }
                    }
                    is RecordingMediaImportResult.Failed -> {
                        operationMessage = mediaImportFailureMessage(result.code)
                    }
                }
            }
        }
    }
    val exporter = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("audio/wav")) { uri ->
        val recording = pendingExport
        pendingExport = null
        val recordingID = recording?.sessionID
        if (uri != null && recordingID != null) {
            scope.launch {
                isExporting = true
                val exported = withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri, "w")?.use { output ->
                        client.exportWav(recordingID, output)
                    } == true
                }
                if (exported && client.isImportedFromWear(recordingID)) {
                    withContext(Dispatchers.IO) {
                        PhoneWearBridge.postStatus(
                            context,
                            recordingID,
                            WearRemoteRecordingPhase.DELIVERED,
                            Int.MAX_VALUE,
                            Int.MAX_VALUE,
                        )
                    }
                }
                isExporting = false
                operationMessage = if (exported) {
                    voxUiText("Audio exported as WAV.")
                } else {
                    voxUiText("Audio could not be exported.")
                }
            }
        }
    }

    fun refresh() {
        recordings = client.recordings()
        policies = recordings.associate { requireNotNull(it.sessionID) to policyStore.policy(requireNotNull(it.sessionID)) }
    }

    LaunchedEffect(currentStatus.sessionID, currentStatus.phase, currentStatus.chunkCount) { refresh() }

    val retryable = recordings.mapNotNull(RecordingStatus::sessionID).filter { id ->
        transcriptionStates[id]?.phase in setOf(
            RecordingTranscriptionPhase.FAILED,
        )
    }

    RecordingQueueContent(
        recordings = recordings,
        operationMessage = operationMessage,
        importEnabled = importPreset != null,
        isImporting = isImporting,
        showRetryAll = retryable.isNotEmpty() && modelState.selectedReadyModel != null,
        navigateBack = navigateBack,
        refresh = ::refresh,
        importMedia = { mediaImporter.launch(arrayOf("audio/*", "video/*")) },
        retryAll = { transcriptionClient.retryAll(retryable) },
    ) { recording ->
        val isCurrent = recording.sessionID == currentStatus.sessionID
        val sessionID = requireNotNull(recording.sessionID)
        RecordingQueueCard(
            recording = if (isCurrent) currentStatus else recording,
            transcription = transcriptionStates[sessionID],
            policy = policies[sessionID] ?: RecordingJobPolicy(),
            canProcess = modelState.selectedReadyModel != null,
            canControl = isCurrent,
            isExporting = isExporting,
            resume = resume,
            finish = finish,
            cancel = cancel,
            export = {
                pendingExport = recording
                exporter.launch("vox-recording-${recording.sessionID?.take(8)}.wav")
            },
            shareAudio = {
                scope.launch {
                    isExporting = true
                    val share = prepareRecordingAudioShare(context, client, sessionID)
                    isExporting = false
                    if (share == null) {
                        operationMessage = voxUiText("Audio could not be shared.")
                    } else {
                        context.startActivity(Intent.createChooser(share, "Share audio"))
                    }
                }
            },
            delete = { pendingDelete = recording },
            process = { transcriptionClient.process(sessionID) },
            cancelProcessing = { transcriptionClient.cancel(sessionID) },
            addToDraft = { transcript ->
                transcriptionClient.markAddedToDraft(sessionID)
                addToDraft(sessionID, transcript)
            },
            copyTranscript = { transcript ->
                context.getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("Vox.md transcript", transcript))
                operationMessage = voxUiText("Transcript copied.")
            },
            shareTranscript = { transcript ->
                context.startActivity(
                    Intent.createChooser(
                        Intent(Intent.ACTION_SEND).apply {
                            type = "text/plain"
                            putExtra(Intent.EXTRA_TEXT, transcript)
                        },
                        "Share transcript",
                    ),
                )
            },
            reassignPresets = if (
                recording.phase == RecordingPhase.INTERRUPTED || client.isImportedFromWear(sessionID)
            ) availablePresets else emptyList(),
            reassign = { preset ->
                if (client.reassignPreset(sessionID, preset)) {
                    transcriptionClient.cancel(sessionID)
                    transcriptionClient.clear(sessionID)
                    if (modelState.selectedReadyModel != null) transcriptionClient.process(sessionID)
                    operationMessage = voxUiText("Recording reassigned to %@.", preset.name)
                } else {
                    operationMessage = voxUiText("That recording could not be reassigned.")
                }
            },
            updatePolicy = { next ->
                if (policyStore.update(sessionID, next)) {
                    policies = policies + (sessionID to next.normalized())
                    val transcription = transcriptionStates[sessionID]
                    RecordingRetentionWorker.schedule(
                        context,
                        sessionID,
                        next,
                        transcription?.completedAtEpochMillis,
                    )
                    if (next.processing == RecordingProcessingPolicy.IMMEDIATE &&
                        recording.chunkCount > 0 &&
                        transcription?.phase != RecordingTranscriptionPhase.COMPLETED
                    ) {
                        transcriptionClient.process(sessionID)
                    }
                    if (shouldDeleteRecordingAudio(
                            next,
                            transcription?.phase == RecordingTranscriptionPhase.COMPLETED,
                            transcription?.completedAtEpochMillis,
                            System.currentTimeMillis(),
                        )
                    ) {
                        client.deleteRetainedAudio(sessionID)
                        refresh()
                    }
                } else {
                    operationMessage = voxUiText("That recording policy could not be saved.")
                }
            },
        )
    }

    pendingDelete?.let { recording ->
        RecoveryConfirmDialog(
            title = voxString("Delete Recording?"),
            message = voxString("This permanently removes the locally saved audio chunks. This cannot be undone."),
            confirmLabel = voxString("Delete"),
            dismissLabel = voxString("Cancel"),
            onDismiss = { pendingDelete = null },
            onConfirm = {
                val id = recording.sessionID
                pendingDelete = null
                val importedFromWear = id?.let(client::isImportedFromWear) == true
                if (id != null && client.deleteRecording(id)) {
                    transcriptionClient.clear(id)
                    if (importedFromWear) {
                        scope.launch(Dispatchers.IO) {
                            PhoneWearBridge.postStatus(
                                context,
                                id,
                                WearRemoteRecordingPhase.DISCARDED,
                                Int.MAX_VALUE,
                                Int.MAX_VALUE,
                            )
                        }
                    }
                    operationMessage = voxUiText("Recording deleted.")
                    refresh()
                } else {
                    operationMessage = voxUiText("Recording could not be deleted.")
                }
            },
        )
    }
}

/**
 * Stateless Signal layout of the recording queue: header, intro, import action,
 * operation notice, and either the empty state or one [card] per recording.
 * [RecordingQueueScreen] owns all state; debug stories drive this directly.
 */
@Composable
internal fun RecordingQueueContent(
    recordings: List<RecordingStatus>,
    operationMessage: VoxUiText?,
    importEnabled: Boolean,
    isImporting: Boolean,
    showRetryAll: Boolean,
    navigateBack: () -> Unit,
    refresh: () -> Unit,
    importMedia: () -> Unit,
    retryAll: () -> Unit,
    card: @Composable (RecordingStatus) -> Unit,
) {
    val c = Signal.colors
    Scaffold(
        containerColor = c.bg,
        topBar = {
            RecoveryTopBar(
                title = "Recording Queue",
                navigateBack = navigateBack,
                action = {
                    SignalCircleButton(
                        icon = Icons.Outlined.Refresh,
                        contentDescription = voxString("Refresh recording queue"),
                        onClick = refresh,
                    )
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(start = SignalMetrics.PageGutter, end = SignalMetrics.PageGutter, top = 4.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(
                    voxString("Recordings are checkpointed on this device before transcription. Interrupted audio stays here for recovery."),
                    style = MaterialTheme.typography.bodyMedium,
                    color = c.muted,
                )
            }
            item {
                RecordingQueueImportAction(
                    enabled = importEnabled,
                    isImporting = isImporting,
                    importMedia = importMedia,
                )
            }
            operationMessage?.let { message ->
                item {
                    SignalBanner(
                        message = message.localized(),
                        status = SignalStatus.NEUTRAL,
                        liveRegion = true,
                    )
                }
            }
            if (recordings.isEmpty()) {
                item { EmptyRecordingQueue() }
            } else {
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(start = 4.dp, end = 4.dp, top = 10.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        SignalSectionLabel(voxString("Recordings"), Modifier.weight(1f))
                        Text(
                            recordings.size.toString(),
                            style = SignalType.sectionLabel,
                            color = c.muted,
                        )
                    }
                }
                if (showRetryAll) {
                    item {
                        RecordingRetryAllAction(visible = true, retryAll = retryAll)
                    }
                }
                items(recordings, key = { requireNotNull(it.sessionID) }) { recording ->
                    card(recording)
                }
            }
        }
    }
}

@Composable
internal fun RecordingRetryAllAction(visible: Boolean, retryAll: () -> Unit) {
    if (!visible) return
    SignalButton(
        text = voxString("Retry All"),
        onClick = retryAll,
        variant = SignalButtonVariant.SECONDARY,
        size = SignalButtonSize.MEDIUM,
        icon = Icons.Outlined.Refresh,
        fillWidth = false,
    )
}

@Composable
internal fun RecordingQueueImportAction(
    enabled: Boolean,
    isImporting: Boolean,
    importMedia: () -> Unit,
) {
    SignalButton(
        text = voxString(if (isImporting) "Importing…" else "Import Audio or Video"),
        onClick = importMedia,
        variant = SignalButtonVariant.SECONDARY,
        size = SignalButtonSize.MEDIUM,
        enabled = enabled,
        loading = isImporting,
        icon = Icons.Outlined.FileDownload,
        fillWidth = true,
    )
}

private suspend fun prepareRecordingAudioShare(
    context: Context,
    client: AudioCaptureClient,
    sessionID: String,
): Intent? = withContext(Dispatchers.IO) {
    runCatching {
        val directory = File(context.cacheDir, "recording-shares").apply { mkdirs() }
        directory.listFiles()?.filter { it.isFile && it.name != "vox-recording-${sessionID.take(8)}.wav" }
            ?.forEach(File::delete)
        val file = File(directory, "vox-recording-${sessionID.take(8)}.wav")
        file.outputStream().buffered().use { output -> check(client.exportWav(sessionID, output)) }
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        Intent(Intent.ACTION_SEND).apply {
            type = "audio/wav"
            putExtra(Intent.EXTRA_STREAM, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            clipData = ClipData.newUri(context.contentResolver, "Vox.md recording", uri)
        }
    }.getOrNull()
}

private fun mediaImportFailureMessage(code: String): VoxUiText = when (code) {
    "noAudioTrack" -> voxUiText("That file does not contain an audio track.")
    "mediaPermission" -> voxUiText("The selected media permission expired before it could be copied.")
    "importedMediaTooLong" -> voxUiText("That media is too long to import safely on this device.")
    "noDecodableAudio" -> voxUiText("No decodable audio was found in that file.")
    "unsupportedMedia" -> voxUiText("This device cannot decode that media format.")
    else -> voxUiText("The media could not be imported. The original file was not changed.")
}

@Composable
private fun EmptyRecordingQueue() {
    SignalEmptyState(
        icon = Icons.Outlined.Check,
        title = voxString("No Recordings Yet"),
        message = voxString("Record audio to stage it here before transcription."),
        iconTint = Signal.colors.success,
        modifier = Modifier.padding(top = 24.dp),
    )
}

/** Status tone for one queue row, mirroring the iOS Activity dot colors. */
private fun recordingQueueStatus(
    recording: RecordingStatus,
    transcription: RecordingTranscriptionState?,
): SignalStatus = when {
    recording.phase == RecordingPhase.RECORDING -> SignalStatus.RECORDING
    recording.phase == RecordingPhase.FAILED -> SignalStatus.ERROR
    recording.phase == RecordingPhase.PAUSED || recording.phase == RecordingPhase.INTERRUPTED -> SignalStatus.WARNING
    transcription?.phase == RecordingTranscriptionPhase.FAILED -> SignalStatus.WARNING
    transcription?.phase == RecordingTranscriptionPhase.PROCESSING ||
        transcription?.phase == RecordingTranscriptionPhase.FINALIZING -> SignalStatus.ACTIVE
    transcription?.phase == RecordingTranscriptionPhase.COMPLETED -> SignalStatus.SUCCESS
    else -> SignalStatus.NEUTRAL
}

@Composable
internal fun RecordingQueueCard(
    recording: RecordingStatus,
    transcription: RecordingTranscriptionState?,
    policy: RecordingJobPolicy,
    canProcess: Boolean,
    canControl: Boolean,
    isExporting: Boolean,
    resume: () -> Unit,
    finish: () -> Unit,
    cancel: () -> Unit,
    export: () -> Unit,
    shareAudio: () -> Unit,
    delete: () -> Unit,
    process: () -> Unit,
    cancelProcessing: () -> Unit,
    addToDraft: (String) -> Unit,
    copyTranscript: (String) -> Unit,
    shareTranscript: (String) -> Unit,
    reassignPresets: List<CapturePreset>,
    reassign: (CapturePreset) -> Unit,
    updatePolicy: (RecordingJobPolicy) -> Unit,
) {
    val c = Signal.colors
    val hasAudio = recording.chunkCount > 0
    var processingMenuOpen by remember(recording.sessionID) { mutableStateOf(false) }
    var retentionMenuOpen by remember(recording.sessionID) { mutableStateOf(false) }
    var reassignMenuOpen by remember(recording.sessionID) { mutableStateOf(false) }
    val status = recordingQueueStatus(recording, transcription)
    val statusColors = signalStatusColors(status)
    val needsAttention = status == SignalStatus.ERROR ||
        recording.phase == RecordingPhase.INTERRUPTED ||
        transcription?.phase == RecordingTranscriptionPhase.FAILED
    SignalCard(
        modifier = Modifier.fillMaxWidth(),
        borderColor = if (needsAttention) statusColors.dot.copy(alpha = 0.55f) else c.border,
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
            // Header: status indicator, phase title, elapsed time, mono metadata.
            Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(Modifier.padding(top = 2.dp).size(18.dp), contentAlignment = Alignment.Center) {
                    if (transcription?.phase == RecordingTranscriptionPhase.COMPLETED && recording.phase == RecordingPhase.COMPLETED) {
                        Icon(Icons.Outlined.Check, contentDescription = null, tint = c.success, modifier = Modifier.size(18.dp))
                    } else {
                        Box(Modifier.size(8.dp).clip(CircleShape).background(statusColors.dot))
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            recordingQueueTitleUiText(recording.phase).localized(),
                            style = SignalType.rowTitle,
                            color = c.text,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            formatQueueElapsed(recording.elapsedMillis),
                            style = SignalType.mono,
                            color = if (status == SignalStatus.RECORDING) c.recording else c.text,
                        )
                    }
                    Text(
                        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(recording.createdAtEpochMillis)),
                        style = SignalType.monoCaption,
                        color = c.muted,
                    )
                    Text(
                        voxFormat(
                            "%lld durable chunks · %@",
                            recording.chunkCount,
                            recording.sessionID?.take(8).orEmpty(),
                        ),
                        style = SignalType.monoCaption,
                        color = c.faint,
                    )
                }
            }

            // Transcription status.
            when (transcription?.phase) {
                RecordingTranscriptionPhase.QUEUED -> RecoveryStatusLine(voxString("Waiting for the local model…"), c.muted)
                RecordingTranscriptionPhase.PROCESSING -> {
                    RecoveryProgressBar(transcription.progress)
                    RecoveryStatusLine(
                        voxFormat("Transcription %@ complete", voxFormat("%lld%%", (transcription.progress * 100).toInt())),
                        c.accentText,
                        mono = true,
                    )
                }
                RecordingTranscriptionPhase.FINALIZING -> {
                    RecoveryProgressBar(null)
                    RecoveryStatusLine(voxString("Finalizing transcript…"), c.accentText)
                }
                RecordingTranscriptionPhase.COMPLETED -> {
                    val transcript = transcription.preferredTranscript.orEmpty()
                    Text(
                        transcript,
                        style = MaterialTheme.typography.bodyMedium,
                        color = c.text,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(SignalMetrics.FieldRadius))
                            .background(c.bg)
                            .border(1.dp, c.divider, RoundedCornerShape(SignalMetrics.FieldRadius))
                            .padding(horizontal = 14.dp, vertical = 12.dp),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        SignalButton(
                            text = voxString(if (transcription.addedToDraft) "Added" else "Add to Draft"),
                            onClick = { addToDraft(transcript) },
                            enabled = transcript.isNotBlank() && !transcription.addedToDraft,
                            size = SignalButtonSize.MEDIUM,
                            icon = if (transcription.addedToDraft) Icons.Outlined.Check else Icons.AutoMirrored.Outlined.Send,
                            fillWidth = false,
                        )
                        SignalCircleButton(
                            icon = Icons.Outlined.ContentCopy,
                            contentDescription = voxString("Copy Last Transcript"),
                            onClick = { copyTranscript(transcript) },
                            enabled = transcript.isNotBlank(),
                        )
                        SignalButton(
                            text = voxString("Share"),
                            onClick = { shareTranscript(transcript) },
                            enabled = transcript.isNotBlank(),
                            variant = SignalButtonVariant.TERTIARY,
                            size = SignalButtonSize.MEDIUM,
                            icon = Icons.Outlined.Share,
                            fillWidth = false,
                        )
                    }
                }
                RecordingTranscriptionPhase.FAILED -> SignalBanner(
                    message = transcriptionFailureMessage(transcription.failureCode).localized(),
                    status = SignalStatus.WARNING,
                    icon = Icons.Outlined.ErrorOutline,
                )
                RecordingTranscriptionPhase.DISCARDED -> RecoveryStatusLine(
                    voxString("Processing discarded. The original audio is still safe."),
                    c.muted,
                )
                null -> RecoveryStatusLine(
                    voxString(if (canProcess) "Ready for private on-device transcription."
                    else "Install and select a local model to process this recording. Audio remains exportable."),
                    c.muted,
                )
            }

            // Live recording controls (only for the current session).
            if (recording.phase in setOf(RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED) && canControl) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                    SignalButton(
                        text = voxString("Resume"),
                        onClick = resume,
                        size = SignalButtonSize.MEDIUM,
                        icon = Icons.Outlined.PlayArrow,
                        fillWidth = false,
                    )
                    SignalButton(
                        text = voxString("Finish"),
                        onClick = finish,
                        variant = SignalButtonVariant.SECONDARY,
                        size = SignalButtonSize.MEDIUM,
                        icon = Icons.Outlined.Stop,
                        fillWidth = false,
                    )
                    Spacer(Modifier.weight(1f))
                    SignalCircleButton(
                        icon = Icons.Outlined.Delete,
                        contentDescription = voxString("Cancel voice recording"),
                        onClick = cancel,
                        contentColor = c.error,
                    )
                }
            } else if (recording.phase == RecordingPhase.RECORDING && canControl) {
                SignalButton(
                    text = voxString("Finish"),
                    onClick = finish,
                    variant = SignalButtonVariant.SECONDARY,
                    size = SignalButtonSize.MEDIUM,
                    icon = Icons.Outlined.Stop,
                    fillWidth = false,
                )
            }

            // Processing and audio actions.
            val processing = transcription?.phase in setOf(
                RecordingTranscriptionPhase.QUEUED,
                RecordingTranscriptionPhase.PROCESSING,
                RecordingTranscriptionPhase.FINALIZING,
            )
            FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SignalButton(
                    text = voxString(
                        if (processing) "Cancel Processing"
                        else if (transcription?.phase == RecordingTranscriptionPhase.FAILED) "Retry"
                        else "Process Now",
                    ),
                    onClick = if (processing) cancelProcessing else process,
                    enabled = hasAudio && recording.phase != RecordingPhase.RECORDING &&
                        transcription?.phase?.isTerminal != true && (canProcess || processing),
                    variant = if (processing) SignalButtonVariant.SECONDARY else SignalButtonVariant.PRIMARY,
                    size = SignalButtonSize.MEDIUM,
                    icon = if (transcription?.phase == RecordingTranscriptionPhase.FAILED && !processing) Icons.Outlined.Refresh else null,
                    fillWidth = false,
                )
                SignalButton(
                    text = voxString("Export Audio"),
                    onClick = export,
                    enabled = hasAudio && recording.phase != RecordingPhase.RECORDING,
                    loading = isExporting,
                    variant = SignalButtonVariant.SECONDARY,
                    size = SignalButtonSize.MEDIUM,
                    icon = Icons.Outlined.FileDownload,
                    fillWidth = false,
                )
                SignalButton(
                    text = voxString("Share Audio"),
                    onClick = shareAudio,
                    enabled = hasAudio && recording.phase != RecordingPhase.RECORDING && !isExporting,
                    variant = SignalButtonVariant.SECONDARY,
                    size = SignalButtonSize.MEDIUM,
                    icon = Icons.Outlined.Share,
                    fillWidth = false,
                )
            }

            if (reassignPresets.isNotEmpty()) {
                Box {
                    RecoveryMenuPill(voxString("Choose Preset"), onClick = { reassignMenuOpen = true })
                    RecoveryDropdownMenu(expanded = reassignMenuOpen, onDismissRequest = { reassignMenuOpen = false }) {
                        reassignPresets.forEach { preset ->
                            RecoveryDropdownItem(preset.name) {
                                reassignMenuOpen = false
                                reassign(preset)
                            }
                        }
                    }
                }
            }

            if (!recording.isActive) {
                SignalDivider()
                FlowRow(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box {
                        RecoveryMenuPill(
                            voxFormat("%@: %@", voxString("Processing"), processingPolicyUiText(policy.processing).localized()),
                            onClick = { processingMenuOpen = true },
                        )
                        RecoveryDropdownMenu(expanded = processingMenuOpen, onDismissRequest = { processingMenuOpen = false }) {
                            RecordingProcessingPolicy.entries.forEach { option ->
                                RecoveryDropdownItem(processingPolicyUiText(option).localized(), selected = option == policy.processing) {
                                    processingMenuOpen = false
                                    updatePolicy(policy.copy(processing = option))
                                }
                            }
                        }
                    }
                    Box {
                        RecoveryMenuPill(
                            voxFormat("%@: %@", voxString("Save Audio"), retentionPolicyUiText(policy).localized()),
                            onClick = { retentionMenuOpen = true },
                        )
                        RecoveryDropdownMenu(expanded = retentionMenuOpen, onDismissRequest = { retentionMenuOpen = false }) {
                            retentionOptions().forEach { (label, option) ->
                                RecoveryDropdownItem(label.localized()) {
                                    retentionMenuOpen = false
                                    updatePolicy(option.copy(processing = policy.processing))
                                }
                            }
                        }
                    }
                }
                TextButton(
                    onClick = delete,
                    enabled = !isExporting,
                    modifier = Modifier.heightIn(min = 48.dp),
                    colors = ButtonDefaults.textButtonColors(contentColor = c.error, disabledContentColor = c.faint),
                ) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.size(6.dp))
                    Text(voxString("Delete"), style = MaterialTheme.typography.labelMedium)
                }
            }
        }
    }
}

private fun processingPolicyUiText(policy: RecordingProcessingPolicy): VoxUiText = when (policy) {
    RecordingProcessingPolicy.IMMEDIATE -> voxUiText("Immediately")
    RecordingProcessingPolicy.WHEN_IDLE -> voxUiText("When Idle")
    RecordingProcessingPolicy.MANUAL -> voxUiText("Manually")
}

private fun retentionPolicyUiText(policy: RecordingJobPolicy): VoxUiText = when (policy.retention) {
    RecordingRetentionKind.DELETE_AFTER_SUCCESS -> voxUiText("Until Processed")
    RecordingRetentionKind.PERMANENT -> voxUiText("Forever")
    RecordingRetentionKind.TIMED -> when (policy.retentionMillis) {
        24L * 60 * 60 * 1_000 -> voxUiText("1 Day")
        30L * 24 * 60 * 60 * 1_000 -> voxUiText("30 Days")
        else -> voxUiText("7 Days")
    }
}

private fun retentionOptions(): List<Pair<VoxUiText, RecordingJobPolicy>> = listOf(
    voxUiText("Until Processed") to RecordingJobPolicy(retention = RecordingRetentionKind.DELETE_AFTER_SUCCESS),
    voxUiText("1 Day") to RecordingJobPolicy(retention = RecordingRetentionKind.TIMED, retentionMillis = 24L * 60 * 60 * 1_000),
    voxUiText("7 Days") to RecordingJobPolicy(retention = RecordingRetentionKind.TIMED, retentionMillis = 7L * 24 * 60 * 60 * 1_000),
    voxUiText("30 Days") to RecordingJobPolicy(retention = RecordingRetentionKind.TIMED, retentionMillis = 30L * 24 * 60 * 60 * 1_000),
    voxUiText("Forever") to RecordingJobPolicy(retention = RecordingRetentionKind.PERMANENT),
)

// endregion

// region Models

@Composable
internal fun ModelsScreen(navigateBack: () -> Unit) {
    val context = LocalContext.current
    var capability by remember { mutableStateOf(OnDeviceSpeechProbe.inspect(context)) }
    val manager = remember(context) { SpeechModelManager.get(context) }
    val modelState by manager.state.collectAsStateWithLifecycle()
    val speakerManager = remember(context) { SpeakerModelManager.get(context) }
    val speakerModelState by speakerManager.state.collectAsStateWithLifecycle()
    val autoStopStore = remember(context) { VoiceAutoStopSettingsStore.get(context) }
    val autoStopSettings by autoStopStore.state.collectAsStateWithLifecycle()
    var pendingImportModelID by remember { mutableStateOf<String?>(null) }
    val importer = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        val modelID = pendingImportModelID
        pendingImportModelID = null
        if (uri != null && modelID != null) {
            val input = runCatching { context.contentResolver.openInputStream(uri) }.getOrNull()
            if (input != null) manager.installImportedZip(modelID, input)
        }
    }
    ModelsScreenContent(
        capability = capability,
        modelState = modelState,
        speakerModelState = speakerModelState,
        autoStopSettings = autoStopSettings,
        navigateBack = navigateBack,
        refresh = {
            capability = OnDeviceSpeechProbe.inspect(context)
            manager.refresh()
            speakerManager.refresh()
        },
        updateAutoStop = { autoStopStore.update(it) },
        installSpeaker = speakerManager::install,
        cancelSpeaker = speakerManager::cancel,
        deleteSpeaker = speakerManager::delete,
        selectAutomatic = manager::selectAutomatic,
        installModel = { manager.install(it) },
        importModel = { modelID ->
            pendingImportModelID = modelID
            importer.launch(arrayOf("application/zip", "application/octet-stream"))
        },
        cancelModel = { manager.cancel(it) },
        selectModel = { manager.select(it) },
        deleteModel = { manager.delete(it) },
    )
}

/**
 * Stateless Signal layout of the Models screen. [ModelsScreen] owns the managers;
 * debug stories pass fixed states so every model state can be reviewed.
 */
@Composable
internal fun ModelsScreenContent(
    capability: OnDeviceSpeechCapability,
    modelState: SpeechModelManagerState,
    speakerModelState: SpeakerModelState,
    autoStopSettings: VoiceAutoStopSettings,
    navigateBack: () -> Unit,
    refresh: () -> Unit,
    updateAutoStop: (VoiceAutoStopSettings) -> Unit,
    installSpeaker: () -> Unit,
    cancelSpeaker: () -> Unit,
    deleteSpeaker: () -> Boolean,
    selectAutomatic: () -> Boolean,
    installModel: (String) -> Unit,
    importModel: (String) -> Unit,
    cancelModel: (String) -> Unit,
    selectModel: (String) -> Unit,
    deleteModel: (String) -> Unit,
    instructionModel: @Composable () -> Unit = { InstructionModelCard() },
) {
    val c = Signal.colors
    Scaffold(
        containerColor = c.bg,
        topBar = {
            RecoveryTopBar(
                title = "Models",
                navigateBack = navigateBack,
                action = {
                    SignalCircleButton(
                        icon = Icons.Outlined.Refresh,
                        contentDescription = voxString("Refresh Status"),
                        onClick = refresh,
                    )
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .verticalScroll(rememberScrollState())
                .padding(start = SignalMetrics.PageGutter, end = SignalMetrics.PageGutter, top = 4.dp, bottom = 32.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                voxString("Vox.md only enables transcription engines that can be selected explicitly for on-device processing."),
                style = MaterialTheme.typography.bodyMedium,
                color = c.muted,
            )
            SpeechCapabilityCard(capability)
            VoiceAutoStopCard(autoStopSettings, updateAutoStop)
            SpeakerModelCard(
                state = speakerModelState,
                install = installSpeaker,
                cancel = cancelSpeaker,
                delete = deleteSpeaker,
            )
            Column(
                modifier = Modifier.padding(start = 4.dp, end = 4.dp, top = 14.dp),
                verticalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                SignalSectionLabel(voxString("Local long-form transcription"))
                Text(
                    voxString("Whisper Small is included for immediate offline transcription. Download only the additional local models you need. Vosk ZIPs can also be imported manually. Every Whisper and Parakeet file is checked against its pinned size and SHA-256 before an atomic install."),
                    style = SignalType.caption,
                    color = c.muted,
                )
            }
            instructionModel()
            AutomaticSpeechModelCard(modelState, selectAutomatic)
            modelState.models.forEach { installState ->
                val id = installState.descriptor.id
                SpeechModelCard(
                    state = installState,
                    selected = modelState.selectionMode == SpeechModelSelectionMode.MANUAL &&
                        id == modelState.selectedModelID,
                    install = { installModel(id) },
                    import = if (installState.descriptor.engine == SpeechModelEngine.VOSK) {
                        { importModel(id) }
                    } else null,
                    cancel = { cancelModel(id) },
                    select = { selectModel(id) },
                    delete = { deleteModel(id) },
                )
            }
            SignalSectionLabel(voxString("Privacy"), Modifier.padding(start = 4.dp, top = 14.dp))
            SignalCard(modifier = Modifier.fillMaxWidth()) {
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
                    SignalIconTile(Icons.Outlined.Lock)
                    Text(
                        voxString("Audio and transcripts stay on this device. Vox.md does not send capture content to a hosted transcription service."),
                        style = MaterialTheme.typography.bodyMedium,
                        color = c.muted,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

@Composable
private fun AutomaticSpeechModelCard(
    state: SpeechModelManagerState,
    select: () -> Boolean,
) {
    val c = Signal.colors
    val selected = state.selectionMode == SpeechModelSelectionMode.AUTOMATIC
    val effective = state.selectedReadyModel?.descriptor
    RecoveryModelCard(selected = selected) {
        RecoveryCardHeader(
            icon = Icons.Outlined.AutoAwesome,
            iconPrimary = selected,
            title = voxString("Automatic"),
            subtitle = voxString("Chooses the best installed local model for this device language."),
            monoSubtitle = false,
            badge = {
                SignalStatusBadge(
                    voxString(if (selected) "Selected" else "Available"),
                    if (selected) SignalStatus.ACTIVE else SignalStatus.NEUTRAL,
                )
            },
        )
        Text(
            effective?.let { voxFormat("Using %@ · %@", it.displayName, it.languageTag) }
                ?: voxString("Install a local language model to make Automatic ready."),
            style = SignalType.monoCaption,
            color = if (effective == null) c.warningText else c.muted,
        )
        SignalButton(
            text = voxString(if (selected) "Selected" else "Use Automatic"),
            onClick = { select() },
            enabled = !selected,
            variant = SignalButtonVariant.SECONDARY,
            size = SignalButtonSize.MEDIUM,
            icon = if (selected) Icons.Outlined.Check else null,
            fillWidth = false,
        )
    }
}

@Composable
private fun SpeakerModelCard(
    state: SpeakerModelState,
    install: () -> Unit,
    cancel: () -> Unit,
    delete: () -> Boolean,
) {
    val c = Signal.colors
    RecoveryModelCard {
        RecoveryCardHeader(
            icon = Icons.Outlined.RecordVoiceOver,
            title = voxString("Speaker Identification"),
            subtitle = voxString("Vosk · all languages · optional"),
            badge = {
                SignalStatusBadge(
                    when (state.phase) {
                        SpeakerModelInstallPhase.READY -> "Installed"
                        else -> state.phase.name.lowercase(Locale.ROOT).replace('_', ' ').replaceFirstChar(Char::uppercase)
                    },
                    speakerModelStatus(state.phase),
                )
            },
        )
        Text(
            voxString("Adds best-effort anonymous speaker labels when a preset requests them. Recognition, vectors, and clustering stay on device; the normal transcript is kept if evidence is insufficient."),
            style = SignalType.caption,
            color = c.muted,
        )
        if (state.phase == SpeakerModelInstallPhase.DOWNLOADING) {
            RecoveryProgressBar(state.progress)
            RecoveryStatusLine(
                state.totalBytes?.let {
                    voxFormat("%@ of %@", formatBytes(state.downloadedBytes), formatBytes(it))
                } ?: formatBytes(state.downloadedBytes),
                c.accentText,
                mono = true,
            )
        }
        if (state.phase in setOf(SpeakerModelInstallPhase.VERIFYING, SpeakerModelInstallPhase.INSTALLING)) {
            RecoveryProgressBar(null)
            RecoveryStatusLine(
                voxString(if (state.phase == SpeakerModelInstallPhase.VERIFYING) "Verifying model checksum…" else "Installing model atomically…"),
                c.accentText,
            )
        }
        if (state.phase == SpeakerModelInstallPhase.FAILED) {
            SignalBanner(
                message = modelInstallFailureMessage(state.failureCode).localized(),
                status = SignalStatus.ERROR,
                icon = Icons.Outlined.ErrorOutline,
            )
        }
        when (state.phase) {
            SpeakerModelInstallPhase.NOT_INSTALLED, SpeakerModelInstallPhase.FAILED -> SignalButton(
                text = voxString(if (state.phase == SpeakerModelInstallPhase.FAILED) "Retry" else "Download 13 MB"),
                onClick = install,
                size = SignalButtonSize.MEDIUM,
                icon = if (state.phase == SpeakerModelInstallPhase.FAILED) Icons.Outlined.Refresh else Icons.Outlined.CloudDownload,
                fillWidth = false,
            )
            SpeakerModelInstallPhase.DOWNLOADING,
            SpeakerModelInstallPhase.VERIFYING,
            SpeakerModelInstallPhase.INSTALLING -> SignalButton(
                text = voxString("Cancel"),
                onClick = cancel,
                variant = SignalButtonVariant.SECONDARY,
                size = SignalButtonSize.MEDIUM,
                fillWidth = false,
            )
            SpeakerModelInstallPhase.READY -> Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    voxFormat("%@ · %@", formatBytes(state.installedBytes), voxString("Installed")),
                    style = SignalType.monoCaption,
                    color = c.muted,
                    modifier = Modifier.weight(1f),
                )
                RecoveryDeleteButton(onClick = { delete() })
            }
        }
    }
}

private fun speakerModelStatus(phase: SpeakerModelInstallPhase): SignalStatus = when (phase) {
    SpeakerModelInstallPhase.READY -> SignalStatus.SUCCESS
    SpeakerModelInstallPhase.NOT_INSTALLED -> SignalStatus.NEUTRAL
    SpeakerModelInstallPhase.FAILED -> SignalStatus.ERROR
    SpeakerModelInstallPhase.DOWNLOADING,
    SpeakerModelInstallPhase.VERIFYING,
    SpeakerModelInstallPhase.INSTALLING -> SignalStatus.ACTIVE
}

@Composable
internal fun VoiceAutoStopCard(
    settings: VoiceAutoStopSettings,
    update: (VoiceAutoStopSettings) -> Unit,
) {
    val c = Signal.colors
    var pauseMenuOpen by remember { mutableStateOf(false) }
    SignalCard(modifier = Modifier.fillMaxWidth(), padding = PaddingValues(0.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .toggleable(
                    value = settings.enabled,
                    role = Role.Switch,
                    onValueChange = { update(settings.copy(enabled = it)) },
                )
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SignalIconTile(Icons.Outlined.Timer, primary = settings.enabled)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(voxString("Voice Auto-Stop"), style = SignalType.rowTitle, color = c.text)
                Text(
                    voxString("Private pause detection for live recordings"),
                    style = SignalType.caption,
                    color = c.muted,
                )
            }
            SignalSwitch(checked = settings.enabled, onCheckedChange = null)
        }
        Column(
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(
                voxString("After speech begins, an on-device energy detector reacts to the configured silence. Final transcription always uses the complete durable audio."),
                style = SignalType.caption,
                color = c.muted,
            )
            if (settings.enabled) {
                SignalDivider()
                Box {
                    RecoveryMenuPill(
                        voxFormat("%@: %@", voxString("Pause"), formatPauseDuration(settings.pauseDurationMillis).localized()),
                        onClick = { pauseMenuOpen = true },
                    )
                    RecoveryDropdownMenu(expanded = pauseMenuOpen, onDismissRequest = { pauseMenuOpen = false }) {
                        listOf(500L, 750L, 1_000L, 1_500L, 2_000L).forEach { duration ->
                            RecoveryDropdownItem(
                                formatPauseDuration(duration).localized(),
                                selected = duration == settings.pauseDurationMillis,
                            ) {
                                pauseMenuOpen = false
                                update(settings.copy(pauseDurationMillis = duration))
                            }
                        }
                    }
                }
                SignalSectionLabel(voxString("On End of Speech"))
                RecoverySegmentedControl(
                    options = listOf(
                        voxString("Stop Recording") to VoiceAutoStopEndAction.STOP_RECORDING,
                        voxString("Keep Listening") to VoiceAutoStopEndAction.SAVE_SEGMENT_AND_CONTINUE,
                    ),
                    selected = settings.endAction,
                    onSelect = { update(settings.copy(endAction = it)) },
                )
                if (settings.endAction == VoiceAutoStopEndAction.SAVE_SEGMENT_AND_CONTINUE) {
                    Text(
                        voxString("Each detected thought becomes a transcript paragraph. Continuous listening keeps recording until you stop it."),
                        style = SignalType.caption,
                        color = c.muted,
                    )
                }
            }
        }
    }
}

private fun formatPauseDuration(durationMillis: Long): VoxUiText = when (durationMillis) {
    500L -> voxUiText("0.5 seconds")
    750L -> voxUiText("0.75 seconds")
    1_000L -> voxUiText("1 second")
    1_500L -> voxUiText("1.5 seconds")
    else -> voxUiText("2 seconds")
}

@Composable
private fun SpeechModelCard(
    state: SpeechModelInstallState,
    selected: Boolean,
    install: () -> Unit,
    import: (() -> Unit)?,
    cancel: () -> Unit,
    select: () -> Unit,
    delete: () -> Unit,
) {
    val c = Signal.colors
    RecoveryModelCard(selected = selected) {
        RecoveryCardHeader(
            icon = Icons.Outlined.GraphicEq,
            iconPrimary = selected,
            title = state.descriptor.displayName,
            subtitle = voxFormat("%@ · %@", state.descriptor.engine.displayName, state.descriptor.languageTag),
            badge = {
                SignalStatusBadge(
                    speechModelInstallStatusUiText(selected, state.phase).localized(),
                    speechModelStatus(selected, state.phase),
                )
            },
        )
        state.descriptor.modelDescription?.let { description ->
            Text(
                speechModelDescriptionUiText(description).localized(),
                style = SignalType.caption,
                color = c.muted,
            )
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                voxFormat("%@ · %@", formatBytes(state.descriptor.approximateBytes), state.descriptor.licenseName),
                style = SignalType.monoCaption,
                color = c.faint,
            )
            if (state.descriptor.minimumMemoryBytes > 0) {
                Text(
                    voxFormat("%@ RAM minimum", formatBytes(state.descriptor.minimumMemoryBytes)),
                    style = SignalType.monoCaption,
                    color = c.faint,
                )
            }
        }
        if (state.phase == SpeechModelInstallPhase.DOWNLOADING) {
            RecoveryProgressBar(state.progress)
            RecoveryStatusLine(
                state.totalBytes?.let {
                    voxFormat("%@ of %@", formatBytes(state.downloadedBytes), formatBytes(it))
                } ?: formatBytes(state.downloadedBytes),
                c.accentText,
                mono = true,
            )
        }
        if (state.phase in setOf(SpeechModelInstallPhase.VERIFYING, SpeechModelInstallPhase.INSTALLING)) {
            RecoveryProgressBar(null)
            RecoveryStatusLine(
                voxString(if (state.phase == SpeechModelInstallPhase.VERIFYING) "Verifying local model files…" else "Installing model atomically…"),
                c.accentText,
            )
        }
        if (state.phase == SpeechModelInstallPhase.FAILED) {
            SignalBanner(
                message = modelInstallFailureMessage(state.failureCode).localized(),
                status = SignalStatus.ERROR,
                icon = Icons.Outlined.ErrorOutline,
            )
        }
        when (state.phase) {
            SpeechModelInstallPhase.NOT_INSTALLED, SpeechModelInstallPhase.FAILED -> FlowRow(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                SignalButton(
                    text = if (state.phase == SpeechModelInstallPhase.FAILED) {
                        voxString("Retry")
                    } else {
                        voxFormat("Download %@", formatBytes(state.descriptor.approximateBytes))
                    },
                    onClick = install,
                    size = SignalButtonSize.MEDIUM,
                    icon = if (state.phase == SpeechModelInstallPhase.FAILED) Icons.Outlined.Refresh else Icons.Outlined.CloudDownload,
                    fillWidth = false,
                )
                import?.let { importModel ->
                    SignalButton(
                        text = voxString("Import ZIP"),
                        onClick = importModel,
                        variant = SignalButtonVariant.SECONDARY,
                        size = SignalButtonSize.MEDIUM,
                        icon = Icons.Outlined.FileDownload,
                        fillWidth = false,
                    )
                }
            }
            SpeechModelInstallPhase.DOWNLOADING,
            SpeechModelInstallPhase.VERIFYING,
            SpeechModelInstallPhase.INSTALLING -> SignalButton(
                text = voxString("Cancel"),
                onClick = cancel,
                variant = SignalButtonVariant.SECONDARY,
                size = SignalButtonSize.MEDIUM,
                fillWidth = false,
            )
            SpeechModelInstallPhase.READY -> Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SignalButton(
                    text = voxString(if (selected) "Selected" else "Use Model"),
                    onClick = select,
                    enabled = !selected,
                    variant = SignalButtonVariant.SECONDARY,
                    size = SignalButtonSize.MEDIUM,
                    icon = if (selected) Icons.Outlined.Check else null,
                    fillWidth = false,
                )
                Spacer(Modifier.weight(1f))
                if (!state.descriptor.bundledByDefault) {
                    RecoveryDeleteButton(onClick = delete)
                }
            }
        }
        if (state.phase == SpeechModelInstallPhase.READY) {
            Text(
                voxFormat("%@ · %@", formatBytes(state.installedBytes), voxString("Installed")),
                style = SignalType.monoCaption,
                color = c.muted,
            )
        }
    }
}

private fun speechModelStatus(selected: Boolean, phase: SpeechModelInstallPhase): SignalStatus = when {
    selected -> SignalStatus.ACTIVE
    phase == SpeechModelInstallPhase.READY -> SignalStatus.SUCCESS
    phase == SpeechModelInstallPhase.NOT_INSTALLED -> SignalStatus.NEUTRAL
    phase == SpeechModelInstallPhase.FAILED -> SignalStatus.ERROR
    else -> SignalStatus.ACTIVE
}

private fun speechModelDescriptionUiText(description: String): VoxUiText = when (description) {
    "Private multilingual transcription on this device." ->
        voxUiText("Private multilingual transcription on this device.")
    "Fast, punctuation-aware transcription in 25 languages." ->
        voxUiText("Fast, punctuation-aware transcription in 25 languages.")
    "Fast, punctuation-aware transcription optimized for English." ->
        voxUiText("Fast, punctuation-aware transcription optimized for English.")
    else -> voxUiText("Private transcription on this device.")
}

@Composable
private fun SpeechCapabilityCard(capability: OnDeviceSpeechCapability) {
    val c = Signal.colors
    val (status, detail) = when (capability.availability) {
        OnDeviceSpeechAvailability.AVAILABLE -> "Available" to
            "Android reports that an explicit on-device recognizer can be created for live speech."
        OnDeviceSpeechAvailability.NOT_AVAILABLE -> "Unavailable" to
            "This device does not currently provide an explicit on-device speech recognizer."
        OnDeviceSpeechAvailability.REQUIRES_ANDROID_12 -> "Unavailable" to
            "Explicit on-device recognition requires Android 12 or newer."
        OnDeviceSpeechAvailability.CHECK_FAILED -> "Check failed" to
            "Vox.md could not verify an explicit on-device recognizer, so it remains disabled."
    }
    val tone = when (capability.availability) {
        OnDeviceSpeechAvailability.AVAILABLE -> SignalStatus.SUCCESS
        OnDeviceSpeechAvailability.CHECK_FAILED -> SignalStatus.WARNING
        else -> SignalStatus.NEUTRAL
    }
    RecoveryModelCard {
        RecoveryCardHeader(
            icon = if (capability.canCreateExplicitOnDeviceRecognizer) Icons.Outlined.CheckCircle else Icons.Outlined.ErrorOutline,
            title = voxString("Android on-device speech"),
            subtitle = null,
            badge = { SignalStatusBadge(status, tone) },
        )
        Text(detail, style = MaterialTheme.typography.bodyMedium, color = c.muted)
        Text(
            voxFormat("%@ · %@", "Android API ${capability.platformAPI}", voxString("Live transcript, listening for speech")),
            style = SignalType.monoCaption,
            color = c.faint,
        )
    }
}

private fun formatBytes(bytes: Long): String = when {
    bytes >= 1_000_000_000 -> String.format(Locale.ROOT, "%.1f GB", bytes / 1_000_000_000.0)
    bytes >= 1_000_000 -> String.format(Locale.ROOT, "%.1f MB", bytes / 1_000_000.0)
    bytes >= 1_000 -> String.format(Locale.ROOT, "%.1f KB", bytes / 1_000.0)
    else -> "$bytes B"
}

private fun speechModelInstallStatusUiText(
    selected: Boolean,
    phase: SpeechModelInstallPhase,
): VoxUiText = when {
    selected -> voxUiText("Selected")
    phase == SpeechModelInstallPhase.READY -> voxUiText("Installed")
    phase == SpeechModelInstallPhase.NOT_INSTALLED -> voxUiText("Not Installed")
    phase == SpeechModelInstallPhase.DOWNLOADING -> voxUiText("Downloading")
    phase == SpeechModelInstallPhase.VERIFYING -> voxUiText("Verifying")
    phase == SpeechModelInstallPhase.INSTALLING -> voxUiText("Installing")
    else -> voxUiText("Failed")
}

private fun modelInstallFailureMessage(code: String?): VoxUiText = when (code) {
    "insufficientStorage" -> voxUiText("Not enough local storage is available for this model.")
    "insufficientDeviceMemory" -> voxUiText("This model needs more device memory. Choose a smaller local model.")
    "invalidModel" -> voxUiText("The archive is not a compatible Vosk model.")
    "modelTooLarge" -> voxUiText("The archive exceeded Vox.md’s safe model limits.")
    "unsafeArchive" -> voxUiText("The archive contained an unsafe path and was rejected.")
    "invalidModelArtifact", "invalidModelArtifactSize", "modelChecksumMismatch", "invalidModelManifest" ->
        voxUiText("A model file did not match the reviewed release and was rejected.")
    "invalidDownloadRange" -> voxUiText("The model host could not safely resume this download. Retry from the Models screen.")
    null -> voxUiText("The model could not be installed.")
    else -> if (code.startsWith("downloadHttp")) {
        voxUiText("The model host returned %@.", code.removePrefix("downloadHttp"))
    } else {
        voxUiText("The model could not be installed.")
    }
}

private fun transcriptionFailureMessage(code: String?): VoxUiText = when (code) {
    "modelNotInstalled" -> voxUiText("Install and select a local model, then retry.")
    "audioUnavailable" -> voxUiText("No complete audio chunks were available.")
    "noSpeech" -> voxUiText("No recognizable speech was found. The original audio is still safe.")
    "processInterrupted" -> voxUiText("Processing was interrupted. The original audio is safe; retry when ready.")
    "transcriptionQuotaReached" -> voxUiText("The free 15-minute transcription limit is reached. Upgrade to process more; the original audio is still safe.")
    else -> voxUiText("Local transcription failed. The original audio is still safe.")
}

private fun recordingQueueTitleUiText(phase: RecordingPhase): VoxUiText = when (phase) {
    RecordingPhase.RECORDING -> voxUiText("Recording")
    RecordingPhase.PAUSED -> voxUiText("Paused Recording")
    RecordingPhase.COMPLETED -> voxUiText("Queued Recording")
    RecordingPhase.INTERRUPTED -> voxUiText("Recovered Recording")
    RecordingPhase.FAILED -> voxUiText("Needs attention")
    RecordingPhase.DISCARDED -> voxUiText("Cancelled Recording")
    RecordingPhase.IDLE -> voxUiText("Recording")
}

private fun formatQueueElapsed(milliseconds: Long): String {
    val seconds = milliseconds.coerceAtLeast(0) / 1_000
    return "%d:%02d".format(seconds / 60, seconds % 60)
}

@Composable
internal fun InstructionModelCard() {
    val context = LocalContext.current
    val manager = remember(context) { InstructionModelManager.get(context) }
    val state by manager.state.collectAsStateWithLifecycle()
    InstructionModelCardContent(
        state = state,
        install = manager::install,
        cancel = manager::cancel,
        delete = manager::delete,
    )
}

/** Stateless Signal card for the optional Custom Instruction model. */
@Composable
internal fun InstructionModelCardContent(
    state: InstructionModelState,
    install: () -> Unit,
    cancel: () -> Unit,
    delete: () -> Unit,
) {
    val context = LocalContext.current
    val c = Signal.colors
    val modelSize = android.text.format.Formatter.formatShortFileSize(context, InstructionModel.BYTES)
    RecoveryModelCard {
        RecoveryCardHeader(
            icon = Icons.Outlined.AutoAwesome,
            title = voxString("Custom Instruction"),
            subtitle = voxFormat("%@ · %@", "Qwen2.5 1.5B", modelSize),
            badge = {
                SignalStatusBadge(
                    voxString(when (state.phase) {
                        InstructionModelPhase.ABSENT -> "Not Installed"
                        InstructionModelPhase.INSTALLING -> "Installing"
                        InstructionModelPhase.READY -> "Ready"
                        InstructionModelPhase.FAILED -> "Failed"
                    }),
                    when (state.phase) {
                        InstructionModelPhase.ABSENT -> SignalStatus.NEUTRAL
                        InstructionModelPhase.INSTALLING -> SignalStatus.ACTIVE
                        InstructionModelPhase.READY -> SignalStatus.SUCCESS
                        InstructionModelPhase.FAILED -> SignalStatus.ERROR
                    },
                )
            },
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(InstructionModel.SOURCE_LABEL, style = SignalType.monoCaption, color = c.faint, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(InstructionModel.VERIFICATION_DISCLOSURE, style = SignalType.monoCaption, color = c.faint)
            Text(
                voxFormat("%@ RAM minimum", android.text.format.Formatter.formatShortFileSize(context, 3_000_000_000L)),
                style = SignalType.monoCaption,
                color = c.faint,
            )
        }
        state.failureCode?.let {
            val message = if (it == "insufficientDeviceMemory") voxUiText("Local model unavailable; the original text was kept.") else modelInstallFailureMessage(it)
            SignalBanner(message = message.localized(), status = SignalStatus.ERROR, icon = Icons.Outlined.ErrorOutline)
        }
        if (state.phase == InstructionModelPhase.INSTALLING) {
            RecoveryProgressBar(state.progress)
            SignalButton(
                text = voxString("Cancel"),
                onClick = cancel,
                variant = SignalButtonVariant.SECONDARY,
                size = SignalButtonSize.MEDIUM,
                fillWidth = false,
            )
        } else if (state.phase == InstructionModelPhase.READY) {
            RecoveryDeleteButton(onClick = delete)
        } else {
            SignalButton(
                text = voxFormat("Download %@", modelSize),
                onClick = install,
                size = SignalButtonSize.MEDIUM,
                icon = Icons.Outlined.CloudDownload,
                fillWidth = false,
            )
        }
    }
}

// endregion

// region Recovery building blocks

@Composable
private fun RecoveryTopBar(title: String, navigateBack: () -> Unit, action: @Composable () -> Unit = {}) {
    md.vox.android.ui.SignalTopBar(
        title = title,
        navigateBack = navigateBack,
        backDescription = voxString("Back"),
        actions = { action() },
    )
}

/** White bordered model card; a selected card takes the 2dp indigo outline used on iOS. */
@Composable
private fun RecoveryModelCard(
    selected: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    val c = Signal.colors
    val shape = RoundedCornerShape(SignalMetrics.CardRadius)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.card)
            .border(if (selected) 2.dp else 1.dp, if (selected) c.accent else c.border, shape)
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        content = content,
    )
}

/** Leading icon tile, title with mono (or plain) subtitle, and a trailing status badge. */
@Composable
private fun RecoveryCardHeader(
    icon: ImageVector,
    title: String,
    subtitle: String?,
    iconPrimary: Boolean = false,
    monoSubtitle: Boolean = true,
    badge: @Composable () -> Unit = {},
) {
    val c = Signal.colors
    Row(verticalAlignment = Alignment.Top, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        SignalIconTile(icon, primary = iconPrimary)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, style = SignalType.rowTitle, color = c.text)
            if (subtitle != null) {
                Text(subtitle, style = if (monoSubtitle) SignalType.monoCaption else SignalType.caption, color = c.muted)
            }
        }
        Box(Modifier.padding(top = 2.dp)) { badge() }
    }
}

@Composable
private fun RecoveryStatusLine(text: String, color: Color, mono: Boolean = false) {
    Text(
        text,
        style = if (mono) SignalType.monoCaption else SignalType.caption,
        color = color,
        modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
    )
}

/** Thin rounded indigo progress bar on a neutral well; indeterminate when [progress] is null. */
@Composable
private fun RecoveryProgressBar(progress: Float?) {
    val c = Signal.colors
    val modifier = Modifier.fillMaxWidth().height(4.dp).clip(CircleShape)
    if (progress != null) {
        LinearProgressIndicator(
            progress = { progress },
            modifier = modifier,
            color = c.tint,
            trackColor = c.well,
            strokeCap = StrokeCap.Round,
            gapSize = 0.dp,
            drawStopIndicator = {},
        )
    } else {
        LinearProgressIndicator(
            modifier = modifier,
            color = c.tint,
            trackColor = c.well,
            strokeCap = StrokeCap.Round,
            gapSize = 0.dp,
        )
    }
}

/** Bordered capsule that opens a menu, e.g. "Save Audio: 7 Days ⌄". */
@Composable
private fun RecoveryMenuPill(text: String, onClick: () -> Unit) {
    val c = Signal.colors
    Row(
        modifier = Modifier
            .heightIn(min = SignalMetrics.ControlMedium)
            .clip(CircleShape)
            .background(c.card)
            .border(1.dp, c.border, CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(start = 14.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(text, style = MaterialTheme.typography.labelMedium, color = c.text, maxLines = 2, overflow = TextOverflow.Ellipsis)
        Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null, tint = c.muted, modifier = Modifier.size(18.dp))
    }
}

@Composable
private fun RecoveryDropdownMenu(
    expanded: Boolean,
    onDismissRequest: () -> Unit,
    content: @Composable ColumnScope.() -> Unit,
) {
    val c = Signal.colors
    DropdownMenu(
        expanded = expanded,
        onDismissRequest = onDismissRequest,
        shape = RoundedCornerShape(SignalMetrics.FieldRadius),
        containerColor = c.card,
        tonalElevation = 0.dp,
        shadowElevation = 2.dp,
        border = BorderStroke(1.dp, c.border),
        content = content,
    )
}

@Composable
private fun RecoveryDropdownItem(text: String, selected: Boolean = false, onClick: () -> Unit) {
    val c = Signal.colors
    DropdownMenuItem(
        text = { Text(text, style = MaterialTheme.typography.bodyLarge) },
        onClick = onClick,
        trailingIcon = if (selected) {
            { Icon(Icons.Outlined.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
        } else null,
        colors = MenuDefaults.itemColors(textColor = c.text, trailingIconColor = c.accentText),
    )
}

/** Two-option segmented control on a well track; the selected segment is a raised card. */
@Composable
private fun <T> RecoverySegmentedControl(
    options: List<Pair<String, T>>,
    selected: T,
    onSelect: (T) -> Unit,
) {
    val c = Signal.colors
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(CircleShape)
            .background(c.well)
            .padding(3.dp),
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
                    .selectable(
                        selected = isSelected,
                        enabled = !isSelected,
                        role = Role.RadioButton,
                        onClick = { onSelect(value) },
                    )
                    .padding(horizontal = 10.dp, vertical = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    label,
                    style = MaterialTheme.typography.labelMedium,
                    color = if (isSelected) c.text else c.muted,
                    textAlign = TextAlign.Center,
                )
            }
        }
    }
}

@Composable
private fun RecoveryDeleteButton(onClick: () -> Unit) {
    val c = Signal.colors
    TextButton(
        onClick = onClick,
        modifier = Modifier.heightIn(min = 48.dp),
        colors = ButtonDefaults.textButtonColors(contentColor = c.error),
    ) {
        Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(Modifier.size(6.dp))
        Text(voxString("Delete"), style = MaterialTheme.typography.labelMedium)
    }
}

@Composable
private fun RecoveryConfirmDialog(
    title: String,
    message: String,
    confirmLabel: String,
    dismissLabel: String,
    onDismiss: () -> Unit,
    onConfirm: () -> Unit,
) {
    val c = Signal.colors
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = c.card,
        titleContentColor = c.text,
        textContentColor = c.muted,
        tonalElevation = 0.dp,
        shape = RoundedCornerShape(SignalMetrics.CardRadius),
        title = { Text(title, style = MaterialTheme.typography.titleLarge) },
        text = { Text(message, style = MaterialTheme.typography.bodyMedium) },
        confirmButton = {
            TextButton(onClick = onConfirm, colors = ButtonDefaults.textButtonColors(contentColor = c.error)) {
                Text(confirmLabel, style = MaterialTheme.typography.labelLarge)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, colors = ButtonDefaults.textButtonColors(contentColor = c.text)) {
                Text(dismissLabel, style = MaterialTheme.typography.labelLarge)
            }
        },
    )
}

// endregion
