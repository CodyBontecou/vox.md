package md.vox.android

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.CloudDownload
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Stop
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.ui.GeistMonoFontFamily
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
import java.text.DateFormat
import java.io.File
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
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

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            RecoveryTopBar(
                title = "Recording Queue",
                navigateBack = navigateBack,
                action = {
                    IconButton(onClick = ::refresh) {
                        Icon(Icons.Outlined.Refresh, contentDescription = voxString("Refresh recording queue"))
                    }
                },
            )
        },
    ) { padding ->
        LazyColumn(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            item {
                Text(voxString("Recordings are checkpointed on this device before transcription. Interrupted audio stays here for recovery."),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            item {
                RecordingQueueImportAction(
                    enabled = importPreset != null,
                    isImporting = isImporting,
                    importMedia = { mediaImporter.launch(arrayOf("audio/*", "video/*")) },
                )
            }
            operationMessage?.let { message ->
                item {
                    Card(
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                        shape = RoundedCornerShape(12.dp),
                    ) {
                        Text(message.localized(), modifier = Modifier.padding(12.dp), style = MaterialTheme.typography.bodyMedium)
                    }
                }
            }
            if (recordings.isEmpty()) {
                item { EmptyRecordingQueue() }
            } else {
                item {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(voxString("Recordings"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        Text(
                            recordings.size.toString(),
                            style = MaterialTheme.typography.labelLarge.copy(fontFamily = GeistMonoFontFamily),
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                val retryable = recordings.mapNotNull(RecordingStatus::sessionID).filter { id ->
                    transcriptionStates[id]?.phase in setOf(
                        RecordingTranscriptionPhase.FAILED,
                    )
                }
                if (retryable.isNotEmpty() && modelState.selectedReadyModel != null) {
                    item {
                        RecordingRetryAllAction(visible = true) { transcriptionClient.retryAll(retryable) }
                    }
                }
                items(recordings, key = { requireNotNull(it.sessionID) }) { recording ->
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
            }
        }
    }

    pendingDelete?.let { recording ->
        AlertDialog(
            onDismissRequest = { pendingDelete = null },
            title = { Text(voxString("Delete Recording?")) },
            text = { Text(voxString("This permanently removes the locally saved audio chunks. This cannot be undone.")) },
            confirmButton = {
                TextButton(
                    onClick = {
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
                ) { Text(voxString("Delete"), color = MaterialTheme.colorScheme.error) }
            },
            dismissButton = { TextButton(onClick = { pendingDelete = null }) { Text(voxString("Cancel")) } },
        )
    }
}

@Composable
internal fun RecordingRetryAllAction(visible: Boolean, retryAll: () -> Unit) {
    if (!visible) return
    OutlinedButton(onClick = retryAll) {
        Icon(Icons.Outlined.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Text(voxString("Retry All"))
    }
}

@Composable
internal fun RecordingQueueImportAction(
    enabled: Boolean,
    isImporting: Boolean,
    importMedia: () -> Unit,
) {
    OutlinedButton(onClick = importMedia, enabled = enabled && !isImporting) {
        if (isImporting) CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
        else Icon(Icons.Outlined.FileDownload, contentDescription = null, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(6.dp))
        Text(voxString(if (isImporting) "Importing…" else "Import Audio or Video"))
    }
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
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Outlined.CheckCircle, contentDescription = null, modifier = Modifier.size(28.dp))
            Text(voxString("No Recordings Yet"), style = MaterialTheme.typography.titleMedium)
            Text(voxString("Record audio to stage it here before transcription."),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
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
    val hasAudio = recording.chunkCount > 0
    var processingMenuOpen by remember(recording.sessionID) { mutableStateOf(false) }
    var retentionMenuOpen by remember(recording.sessionID) { mutableStateOf(false) }
    var reassignMenuOpen by remember(recording.sessionID) { mutableStateOf(false) }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    when (recording.phase) {
                        RecordingPhase.COMPLETED -> Icons.Outlined.CheckCircle
                        RecordingPhase.FAILED, RecordingPhase.INTERRUPTED -> Icons.Outlined.ErrorOutline
                        else -> Icons.Outlined.MicNone
                    },
                    contentDescription = null,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(Modifier.width(8.dp))
                Text(recordingQueueTitleUiText(recording.phase).localized(), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Text(formatQueueElapsed(recording.elapsedMillis), style = MaterialTheme.typography.labelLarge.copy(fontFamily = GeistMonoFontFamily))
            }
            Text(
                DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(recording.createdAtEpochMillis)),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                voxFormat(
                    if (recording.chunkCount == 1) "%lld durable chunk · %@" else "%lld durable chunks · %@",
                    recording.chunkCount,
                    recording.sessionID?.take(8).orEmpty(),
                ),
                style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (!recording.isActive) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Box {
                        TextButton(onClick = { processingMenuOpen = true }) {
                            Text(voxFormat("%@: %@", voxString("Processing"), processingPolicyUiText(policy.processing).localized()))
                            Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null, modifier = Modifier.size(18.dp))
                        }
                        DropdownMenu(expanded = processingMenuOpen, onDismissRequest = { processingMenuOpen = false }) {
                            RecordingProcessingPolicy.entries.forEach { option ->
                                DropdownMenuItem(
                                    text = { Text(processingPolicyUiText(option).localized()) },
                                    onClick = {
                                        processingMenuOpen = false
                                        updatePolicy(policy.copy(processing = option))
                                    },
                                )
                            }
                        }
                    }
                    Box {
                        TextButton(onClick = { retentionMenuOpen = true }) {
                            Text(voxFormat("%@: %@", voxString("Save Audio"), retentionPolicyUiText(policy).localized()))
                            Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null, modifier = Modifier.size(18.dp))
                        }
                        DropdownMenu(expanded = retentionMenuOpen, onDismissRequest = { retentionMenuOpen = false }) {
                            retentionOptions().forEach { (label, option) ->
                                DropdownMenuItem(
                                    text = { Text(label.localized()) },
                                    onClick = {
                                        retentionMenuOpen = false
                                        updatePolicy(option.copy(processing = policy.processing))
                                    },
                                )
                            }
                        }
                    }
                }
            }
            if (reassignPresets.isNotEmpty()) {
                Box {
                    OutlinedButton(onClick = { reassignMenuOpen = true }) {
                        Text(voxString("Choose Preset"))
                        Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null, modifier = Modifier.size(18.dp))
                    }
                    DropdownMenu(expanded = reassignMenuOpen, onDismissRequest = { reassignMenuOpen = false }) {
                        reassignPresets.forEach { preset ->
                            DropdownMenuItem(
                                text = { Text(preset.name) },
                                onClick = {
                                    reassignMenuOpen = false
                                    reassign(preset)
                                },
                            )
                        }
                    }
                }
            }
            if (recording.phase in setOf(RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED) && canControl) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = resume) {
                        Icon(Icons.Outlined.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Resume"))
                    }
                    OutlinedButton(onClick = finish) {
                        Icon(Icons.Outlined.Stop, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Finish"))
                    }
                    IconButton(onClick = cancel) {
                        Icon(Icons.Outlined.Delete, contentDescription = voxString("Cancel voice recording"))
                    }
                }
            } else if (recording.phase == RecordingPhase.RECORDING && canControl) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = finish) {
                        Icon(Icons.Outlined.Stop, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(voxString("Finish"))
                    }
                }
            }
            val processing = transcription?.phase in setOf(
                RecordingTranscriptionPhase.QUEUED,
                RecordingTranscriptionPhase.PROCESSING,
                RecordingTranscriptionPhase.FINALIZING,
            )
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(
                    onClick = if (processing) cancelProcessing else process,
                    enabled = hasAudio && recording.phase != RecordingPhase.RECORDING &&
                        transcription?.phase?.isTerminal != true && (canProcess || processing),
                ) {
                    Text(
                        voxString(if (processing) "Cancel Processing"
                        else if (transcription?.phase == RecordingTranscriptionPhase.FAILED) "Retry"
                        else "Process Now"),
                    )
                }
                OutlinedButton(
                    onClick = export,
                    enabled = hasAudio && recording.phase != RecordingPhase.RECORDING && !isExporting,
                ) {
                    if (isExporting) CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    else Icon(Icons.Outlined.FileDownload, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(voxString("Export Audio"))
                }
            }
            OutlinedButton(
                onClick = shareAudio,
                enabled = hasAudio && recording.phase != RecordingPhase.RECORDING && !isExporting,
            ) {
                Text(voxString("Share Audio"))
            }
            when (transcription?.phase) {
                RecordingTranscriptionPhase.QUEUED -> Text(voxString("Waiting for the local model…"), style = MaterialTheme.typography.bodySmall)
                RecordingTranscriptionPhase.PROCESSING -> {
                    LinearProgressIndicator(progress = { transcription.progress }, modifier = Modifier.fillMaxWidth())
                    Text(voxFormat("Transcription %@ complete", voxFormat("%lld%%", (transcription.progress * 100).toInt())),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                RecordingTranscriptionPhase.FINALIZING -> Text(
                    voxString("Finalizing transcript…"),
                    style = MaterialTheme.typography.bodySmall,
                )
                RecordingTranscriptionPhase.COMPLETED -> {
                    val transcript = transcription.preferredTranscript.orEmpty()
                    Text(transcript, style = MaterialTheme.typography.bodyMedium)
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                        Button(
                            onClick = { addToDraft(transcript) },
                            enabled = transcript.isNotBlank() && !transcription.addedToDraft,
                        ) { Text(voxString(if (transcription.addedToDraft) "Added" else "Add to Draft")) }
                        IconButton(onClick = { copyTranscript(transcript) }, enabled = transcript.isNotBlank()) {
                            Icon(Icons.Outlined.ContentCopy, contentDescription = voxString("Copy Last Transcript"))
                        }
                        TextButton(onClick = { shareTranscript(transcript) }, enabled = transcript.isNotBlank()) { Text(voxString("Share")) }
                    }
                }
                RecordingTranscriptionPhase.FAILED -> Text(
                    transcriptionFailureMessage(transcription.failureCode).localized(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.error,
                )
                RecordingTranscriptionPhase.DISCARDED -> Text(voxString("Processing discarded. The original audio is still safe."),
                    style = MaterialTheme.typography.bodySmall,
                )
                null -> Text(
                    voxString(if (canProcess) "Ready for private on-device transcription."
                    else "Install and select a local model to process this recording. Audio remains exportable."),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (!recording.isActive) {
                TextButton(onClick = delete, enabled = !isExporting) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.width(6.dp))
                    Text(voxString("Delete"), color = MaterialTheme.colorScheme.error)
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

@OptIn(ExperimentalMaterial3Api::class)
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
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            RecoveryTopBar(
                title = "Models",
                navigateBack = navigateBack,
                action = {
                    IconButton(onClick = {
                        capability = OnDeviceSpeechProbe.inspect(context)
                        manager.refresh()
                        speakerManager.refresh()
                    }) {
                        Icon(Icons.Outlined.Refresh, contentDescription = voxString("Refresh Status"))
                    }
                },
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(voxString("Vox.md only enables transcription engines that can be selected explicitly for on-device processing."),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            SpeechCapabilityCard(capability)
            VoiceAutoStopCard(autoStopSettings, autoStopStore::update)
            SpeakerModelCard(
                state = speakerModelState,
                install = speakerManager::install,
                cancel = speakerManager::cancel,
                delete = speakerManager::delete,
            )
            Text(voxString("Local long-form transcription"), style = MaterialTheme.typography.titleLarge)
            Text(voxString("Whisper Small is included for immediate offline transcription. Download only the additional local models you need. Vosk ZIPs can also be imported manually. Every Whisper and Parakeet file is checked against its pinned size and SHA-256 before an atomic install."),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            AutomaticSpeechModelCard(modelState, manager::selectAutomatic)
            modelState.models.forEach { installState ->
                SpeechModelCard(
                    state = installState,
                    selected = modelState.selectionMode == SpeechModelSelectionMode.MANUAL &&
                        installState.descriptor.id == modelState.selectedModelID,
                    install = { manager.install(installState.descriptor.id) },
                    import = if (installState.descriptor.engine == SpeechModelEngine.VOSK) {
                        {
                            pendingImportModelID = installState.descriptor.id
                            importer.launch(arrayOf("application/zip", "application/octet-stream"))
                        }
                    } else null,
                    cancel = { manager.cancel(installState.descriptor.id) },
                    select = { manager.select(installState.descriptor.id) },
                    delete = { manager.delete(installState.descriptor.id) },
                )
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outline, modifier = Modifier.padding(vertical = 8.dp))
            Text(voxString("Privacy"), style = MaterialTheme.typography.titleMedium)
            Text(voxString("Audio and transcripts stay on this device. Vox.md does not send capture content to a hosted transcription service."),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun AutomaticSpeechModelCard(
    state: SpeechModelManagerState,
    select: () -> Boolean,
) {
    val selected = state.selectionMode == SpeechModelSelectionMode.AUTOMATIC
    val effective = state.selectedReadyModel?.descriptor
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null)
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(voxString("Automatic"), style = MaterialTheme.typography.titleMedium)
                    Text(voxString("Chooses the best installed local model for this device language."),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    voxString(if (selected) "Selected" else "Available"),
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            Text(
                effective?.let { voxFormat("Using %@ · %@", it.displayName, it.languageTag) }
                    ?: voxString("Install a local language model to make Automatic ready."),
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = GeistMonoFontFamily),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Button(onClick = { select() }, enabled = !selected) {
                Text(voxString(if (selected) "Selected" else "Use Automatic"))
            }
        }
    }
}

@Composable
private fun SpeakerModelCard(
    state: SpeakerModelState,
    install: () -> Unit,
    cancel: () -> Unit,
    delete: () -> Boolean,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.MicNone, contentDescription = null)
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(voxString("Speaker Identification"), style = MaterialTheme.typography.titleMedium)
                    Text(voxString("Vosk · all languages · optional"),
                        style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    when (state.phase) {
                        SpeakerModelInstallPhase.READY -> "Installed"
                        else -> state.phase.name.lowercase(Locale.ROOT).replace('_', ' ').replaceFirstChar(Char::uppercase)
                    },
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            Text(voxString("Adds best-effort anonymous speaker labels when a preset requests them. Recognition, vectors, and clustering stay on device; the normal transcript is kept if evidence is insufficient."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (state.phase == SpeakerModelInstallPhase.DOWNLOADING) {
                state.progress?.let { LinearProgressIndicator(progress = { it }, modifier = Modifier.fillMaxWidth()) }
                    ?: LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                Text(
                    state.totalBytes?.let {
                        voxFormat("%@ of %@", formatBytes(state.downloadedBytes), formatBytes(it))
                    } ?: formatBytes(state.downloadedBytes),
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = GeistMonoFontFamily),
                )
            }
            if (state.phase in setOf(SpeakerModelInstallPhase.VERIFYING, SpeakerModelInstallPhase.INSTALLING)) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                Text(voxString(if (state.phase == SpeakerModelInstallPhase.VERIFYING) "Verifying model checksum…" else "Installing model atomically…"))
            }
            if (state.phase == SpeakerModelInstallPhase.FAILED) {
                Text(modelInstallFailureMessage(state.failureCode).localized(), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            when (state.phase) {
                SpeakerModelInstallPhase.NOT_INSTALLED, SpeakerModelInstallPhase.FAILED -> Button(onClick = install) {
                    Icon(Icons.Outlined.CloudDownload, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text(voxString(if (state.phase == SpeakerModelInstallPhase.FAILED) "Retry" else "Download 13 MB"))
                }
                SpeakerModelInstallPhase.DOWNLOADING,
                SpeakerModelInstallPhase.VERIFYING,
                SpeakerModelInstallPhase.INSTALLING -> OutlinedButton(onClick = cancel) { Text(voxString("Cancel")) }
                SpeakerModelInstallPhase.READY -> {
                    TextButton(onClick = { delete() }) { Text(voxString("Delete"), color = MaterialTheme.colorScheme.error) }
                    Text(voxFormat("%@ · %@", formatBytes(state.installedBytes), voxString("Installed")),
                        style = MaterialTheme.typography.bodySmall.copy(fontFamily = GeistMonoFontFamily),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
internal fun VoiceAutoStopCard(
    settings: VoiceAutoStopSettings,
    update: (VoiceAutoStopSettings) -> Unit,
) {
    var pauseMenuOpen by remember { mutableStateOf(false) }
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(voxString("Voice Auto-Stop"), style = MaterialTheme.typography.titleMedium)
                    Text(voxString("Private pause detection for live recordings"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Switch(
                    checked = settings.enabled,
                    onCheckedChange = { update(settings.copy(enabled = it)) },
                )
            }
            Text(voxString("After speech begins, an on-device energy detector reacts to the configured silence. Final transcription always uses the complete durable audio."),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (settings.enabled) {
                Box {
                    OutlinedButton(onClick = { pauseMenuOpen = true }) {
                        Text(voxFormat("%@: %@", voxString("Pause"), formatPauseDuration(settings.pauseDurationMillis).localized()))
                        Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = null, modifier = Modifier.size(18.dp))
                    }
                    DropdownMenu(expanded = pauseMenuOpen, onDismissRequest = { pauseMenuOpen = false }) {
                        listOf(500L, 750L, 1_000L, 1_500L, 2_000L).forEach { duration ->
                            DropdownMenuItem(
                                text = { Text(formatPauseDuration(duration).localized()) },
                                onClick = {
                                    pauseMenuOpen = false
                                    update(settings.copy(pauseDurationMillis = duration))
                                },
                            )
                        }
                    }
                }
                Text(voxString("On End of Speech"), style = MaterialTheme.typography.labelLarge)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(
                        onClick = { update(settings.copy(endAction = VoiceAutoStopEndAction.STOP_RECORDING)) },
                        enabled = settings.endAction != VoiceAutoStopEndAction.STOP_RECORDING,
                    ) { Text(voxString("Stop Recording")) }
                    OutlinedButton(
                        onClick = { update(settings.copy(endAction = VoiceAutoStopEndAction.SAVE_SEGMENT_AND_CONTINUE)) },
                        enabled = settings.endAction != VoiceAutoStopEndAction.SAVE_SEGMENT_AND_CONTINUE,
                    ) { Text(voxString("Keep Listening")) }
                }
                if (settings.endAction == VoiceAutoStopEndAction.SAVE_SEGMENT_AND_CONTINUE) {
                    Text(voxString("Each detected thought becomes a transcript paragraph. Continuous listening ends after 10 minutes."),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
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
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.MicNone, contentDescription = null)
                Spacer(Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text(state.descriptor.displayName, style = MaterialTheme.typography.titleMedium)
                    Text(voxFormat("%@ · %@", state.descriptor.engine.displayName, state.descriptor.languageTag),
                        style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily),
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Text(
                    speechModelInstallStatusUiText(selected, state.phase).localized(),
                    style = MaterialTheme.typography.labelMedium,
                )
            }
            state.descriptor.modelDescription?.let { description ->
                Text(
                    speechModelDescriptionUiText(description).localized(),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                voxFormat("%@ · %@", formatBytes(state.descriptor.approximateBytes), state.descriptor.licenseName),
                style = MaterialTheme.typography.labelSmall.copy(fontFamily = GeistMonoFontFamily),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (state.descriptor.minimumMemoryBytes > 0) {
                Text(
                    voxFormat("%@ RAM minimum", formatBytes(state.descriptor.minimumMemoryBytes)),
                    style = MaterialTheme.typography.labelSmall.copy(fontFamily = GeistMonoFontFamily),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (state.phase == SpeechModelInstallPhase.DOWNLOADING) {
                state.progress?.let { progress ->
                    LinearProgressIndicator(progress = { progress }, modifier = Modifier.fillMaxWidth())
                } ?: LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                Text(
                    state.totalBytes?.let {
                        voxFormat("%@ of %@", formatBytes(state.downloadedBytes), formatBytes(it))
                    } ?: formatBytes(state.downloadedBytes),
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = GeistMonoFontFamily),
                )
            }
            if (state.phase in setOf(SpeechModelInstallPhase.VERIFYING, SpeechModelInstallPhase.INSTALLING)) {
                LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                Text(voxString(if (state.phase == SpeechModelInstallPhase.VERIFYING) "Verifying local model files…" else "Installing model atomically…"))
            }
            if (state.phase == SpeechModelInstallPhase.FAILED) {
                Text(modelInstallFailureMessage(state.failureCode).localized(), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
            }
            when (state.phase) {
                SpeechModelInstallPhase.NOT_INSTALLED, SpeechModelInstallPhase.FAILED -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = install) {
                        Icon(Icons.Outlined.CloudDownload, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text(
                            if (state.phase == SpeechModelInstallPhase.FAILED) {
                                voxString("Retry")
                            } else {
                                voxFormat("Download %@", formatBytes(state.descriptor.approximateBytes))
                            },
                        )
                    }
                    import?.let { importModel ->
                        OutlinedButton(onClick = importModel) { Text(voxString("Import ZIP")) }
                    }
                }
                SpeechModelInstallPhase.DOWNLOADING,
                SpeechModelInstallPhase.VERIFYING,
                SpeechModelInstallPhase.INSTALLING -> OutlinedButton(onClick = cancel) { Text(voxString("Cancel")) }
                SpeechModelInstallPhase.READY -> Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = select, enabled = !selected) { Text(voxString(if (selected) "Selected" else "Use Model")) }
                    if (!state.descriptor.bundledByDefault) {
                        TextButton(onClick = delete) { Text(voxString("Delete"), color = MaterialTheme.colorScheme.error) }
                    }
                }
            }
            if (state.phase == SpeechModelInstallPhase.READY) {
                Text(voxFormat("%@ · %@", formatBytes(state.installedBytes), voxString("Installed")),
                    style = MaterialTheme.typography.bodySmall.copy(fontFamily = GeistMonoFontFamily),
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
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
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
        shape = RoundedCornerShape(16.dp),
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    if (capability.canCreateExplicitOnDeviceRecognizer) Icons.Outlined.CheckCircle else Icons.Outlined.ErrorOutline,
                    contentDescription = null,
                )
                Spacer(Modifier.width(10.dp))
                Text(voxString("Android on-device speech"), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                Text(status, style = MaterialTheme.typography.labelMedium)
            }
            Text(detail, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(voxFormat("%@ · %@", "Android API ${capability.platformAPI}", voxString("Live transcript, listening for speech")),
                style = MaterialTheme.typography.labelMedium.copy(fontFamily = GeistMonoFontFamily),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun RecoveryTopBar(title: String, navigateBack: () -> Unit, action: @Composable () -> Unit = {}) {
    TopAppBar(
        title = { Text(title, style = MaterialTheme.typography.titleLarge) },
        navigationIcon = {
            IconButton(onClick = navigateBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = voxString("Back"))
            }
        },
        actions = { action() },
        colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
    )
}
