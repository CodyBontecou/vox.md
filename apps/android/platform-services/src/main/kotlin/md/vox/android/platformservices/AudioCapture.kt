package md.vox.android.platformservices

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import java.io.File
import java.io.FileOutputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs
import kotlin.math.max
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import md.vox.android.capturedomain.CapturePreset

internal const val MAX_RECORDING_DURATION_MILLIS = 24L * 60 * 60 * 1_000

internal fun reachedRecordingSafetyLimit(elapsedMillis: Long): Boolean =
    elapsedMillis >= MAX_RECORDING_DURATION_MILLIS

internal fun recordingCreatedAtEpochMillis(context: Context, sessionID: String): Long? =
    RecordingManifestStore.all(context)
        .firstOrNull { it.sessionID == sessionID }
        ?.createdAtEpochMillis
        ?.takeIf { it > 0 }

enum class RecordingPhase {
    IDLE,
    RECORDING,
    PAUSED,
    COMPLETED,
    INTERRUPTED,
    FAILED,
    DISCARDED,
}

data class RecordingStatus(
    val sessionID: String? = null,
    val phase: RecordingPhase = RecordingPhase.IDLE,
    val createdAtEpochMillis: Long = 0,
    val elapsedMillis: Long = 0,
    val level: Float = 0f,
    val chunkCount: Int = 0,
    val failureCode: String? = null,
) {
    val isActive: Boolean get() = phase == RecordingPhase.RECORDING || phase == RecordingPhase.PAUSED
}

sealed interface RecordingMediaImportResult {
    data class Imported(val recording: RecordingStatus) : RecordingMediaImportResult
    data class Failed(val code: String) : RecordingMediaImportResult
}

object RecordingStatusRegistry {
    private val mutableStatus = MutableStateFlow(RecordingStatus())
    val status: StateFlow<RecordingStatus> = mutableStatus.asStateFlow()

    internal fun publish(value: RecordingStatus) {
        mutableStatus.value = value
    }
}

/**
 * Optional application-owned hook for adding device-family notification metadata without
 * pulling Wear-only libraries into the phone artifact. Implementations are named through the
 * `md.vox.android.RECORDING_NOTIFICATION_EXTENDER` application manifest metadata entry.
 */
interface RecordingNotificationExtender {
    fun extend(
        context: Context,
        notificationID: Int,
        status: RecordingStatus,
        builder: NotificationCompat.Builder,
    )
}

class AudioCaptureClient(context: Context) {
    private val appContext = context.applicationContext

    init {
        RecordingManifestStore.recoverInterrupted(appContext)
        RecordingManifestStore.latest(appContext)?.let { persisted ->
            RecordingStatusRegistry.publish(persisted)
        }
    }

    fun start(preset: CapturePreset) = dispatch(
        AudioCaptureService.ACTION_START,
        foreground = true,
        presetSnapshot = RecordingPresetSnapshotCodec.encode(preset),
    )
    fun pause() = dispatch(AudioCaptureService.ACTION_PAUSE)
    fun resume() = dispatch(AudioCaptureService.ACTION_RESUME, foreground = true)
    fun stop() = dispatch(AudioCaptureService.ACTION_STOP)
    fun cancel() = dispatch(AudioCaptureService.ACTION_CANCEL)
    fun recordings(): List<RecordingStatus> = RecordingManifestStore.all(appContext)

    fun exportWav(sessionID: String, output: OutputStream): Boolean =
        RecordingManifestStore.exportWav(appContext, sessionID, output)

    fun deleteRecording(sessionID: String): Boolean {
        if (RecordingStatusRegistry.status.value.let { it.sessionID == sessionID && it.isActive }) return false
        val deleted = RecordingManifestStore.delete(appContext, sessionID)
        if (deleted && RecordingStatusRegistry.status.value.sessionID == sessionID) {
            RecordingStatusRegistry.publish(RecordingManifestStore.latest(appContext) ?: RecordingStatus())
        }
        return deleted
    }

    fun deleteRetainedAudio(sessionID: String): Boolean {
        if (RecordingStatusRegistry.status.value.let { it.sessionID == sessionID && it.isActive }) return false
        val updated = RecordingManifestStore.deleteAudio(appContext, sessionID) ?: return false
        if (RecordingStatusRegistry.status.value.sessionID == sessionID) RecordingStatusRegistry.publish(updated)
        return true
    }

    fun importWearRecording(
        sessionID: String,
        createdAtEpochMillis: Long,
        durationMillis: Long,
        chunkCount: Int,
        sourceDirectory: File,
        presetSnapshot: ByteArray,
    ): Boolean = RecordingManifestStore.importWearRecording(
        appContext,
        sessionID,
        createdAtEpochMillis,
        durationMillis,
        chunkCount,
        sourceDirectory,
        presetSnapshot,
    )

    fun isImportedFromWear(sessionID: String): Boolean = RecordingManifestStore.isImportedFromWear(appContext, sessionID)

    fun frozenPreset(sessionID: String): CapturePreset? =
        RecordingManifestStore.presetSnapshot(appContext, sessionID)?.let(RecordingPresetSnapshotCodec::decode)

    /** Replaces the frozen route only for a retained, inactive recording selected in recovery UI. */
    fun reassignPreset(sessionID: String, preset: CapturePreset): Boolean {
        if (RecordingStatusRegistry.status.value.let { it.sessionID == sessionID && it.isActive }) return false
        if (recordings().none { it.sessionID == sessionID }) return false
        return RecordingManifestStore.writePresetSnapshot(
            appContext,
            sessionID,
            RecordingPresetSnapshotCodec.encode(preset),
        )
    }

    fun importMedia(contentUri: String, preset: CapturePreset): RecordingMediaImportResult {
        val uri = Uri.parse(contentUri)
        if (uri.scheme != "content") return RecordingMediaImportResult.Failed("invalidMediaUri")
        val sessionID = UUID.randomUUID().toString().lowercase()
        val root = File(appContext.noBackupFilesDir, "recordings").apply { mkdirs() }
        val staging = File(root, ".$sessionID.import.part")
        return when (val decoded = ImportedMediaDecoder.decode(appContext, uri, staging)) {
            is ImportedMediaDecodeResult.Failure -> RecordingMediaImportResult.Failed(decoded.code)
            is ImportedMediaDecodeResult.Success -> {
                val status = RecordingStatus(
                    sessionID = sessionID,
                    phase = RecordingPhase.COMPLETED,
                    createdAtEpochMillis = System.currentTimeMillis(),
                    elapsedMillis = decoded.durationMillis,
                    chunkCount = decoded.chunkCount,
                    failureCode = "mediaImported",
                )
                val promoted = RecordingManifestStore.importDecodedMedia(
                    appContext,
                    staging,
                    status,
                    RecordingPresetSnapshotCodec.encode(preset),
                )
                if (promoted) {
                    RecordingStatusRegistry.publish(status)
                    RecordingMediaImportResult.Imported(status)
                } else {
                    staging.deleteRecursively()
                    RecordingMediaImportResult.Failed("mediaPromotion")
                }
            }
        }
    }

    fun dismissResult() {
        if (!RecordingStatusRegistry.status.value.isActive) RecordingStatusRegistry.publish(RecordingStatus())
    }

    private fun dispatch(action: String, foreground: Boolean = false, presetSnapshot: String? = null) {
        val intent = Intent(appContext, AudioCaptureService::class.java).setAction(action).apply {
            presetSnapshot?.let { putExtra(AudioCaptureService.EXTRA_PRESET_SNAPSHOT, it) }
        }
        if (foreground) ContextCompat.startForegroundService(appContext, intent) else appContext.startService(intent)
    }
}

class AudioCaptureService : Service() {
    private val executor = Executors.newSingleThreadExecutor()
    private val desiredPhase = AtomicReference(RecordingPhase.IDLE)
    private val loopRunning = AtomicBoolean(false)
    @Volatile private var recorder: AudioRecord? = null
    @Volatile private var session: Session? = null
    @Volatile private var destroyed = false
    private val notificationExtender: RecordingNotificationExtender? by lazy(::loadNotificationExtender)

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val recovered = RecordingManifestStore.latest(this)
        if (recovered != null && recovered.phase in setOf(RecordingPhase.RECORDING, RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED)) {
            val recoveredDirectory = File(noBackupFilesDir, "recordings/${recovered.sessionID}")
            val autoStopSettings = RecordingAutoStopSnapshot.read(recoveredDirectory) ?: VoiceAutoStopSettings()
            session = Session(
                id = requireNotNull(recovered.sessionID),
                directory = recoveredDirectory,
                createdAtEpochMillis = recovered.createdAtEpochMillis,
                elapsedBeforeSegment = recovered.elapsedMillis,
                chunkCount = recovered.chunkCount,
                autoStopSettings = autoStopSettings,
                autoStop = autoStopSettings.takeIf(VoiceAutoStopSettings::enabled)?.let {
                    VoicePauseDetector(it.pauseDurationMillis)
                },
            )
            val interrupted = if (recovered.phase == RecordingPhase.RECORDING) {
                recovered.copy(phase = RecordingPhase.INTERRUPTED, level = 0f, failureCode = "processInterrupted")
            } else recovered
            desiredPhase.set(interrupted.phase)
            RecordingManifestStore.write(this, interrupted)
            RecordingStatusRegistry.publish(interrupted)
        } else if (recovered != null) {
            RecordingStatusRegistry.publish(recovered)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startNewSession(intent.getStringExtra(EXTRA_PRESET_SNAPSHOT))
            ACTION_PAUSE -> requestTransition(RecordingPhase.PAUSED)
            ACTION_RESUME -> resumeSession()
            ACTION_STOP -> requestTransition(RecordingPhase.COMPLETED)
            ACTION_CANCEL -> requestTransition(RecordingPhase.DISCARDED)
            else -> if (session == null) stopSelf()
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        destroyed = true
        if (desiredPhase.get() == RecordingPhase.RECORDING) desiredPhase.set(RecordingPhase.INTERRUPTED)
        runCatching { recorder?.stop() }
        executor.shutdown()
        super.onDestroy()
    }

    private fun startNewSession(encodedPreset: String?) {
        if (RecordingStatusRegistry.status.value.isActive || loopRunning.get()) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            publishFailure("microphonePermission")
            stopSelf()
            return
        }
        val preset = encodedPreset?.let(RecordingPresetSnapshotCodec::decode)
        if (preset == null) {
            publishFailure("presetSnapshot")
            stopSelf()
            return
        }
        val id = UUID.randomUUID().toString().lowercase()
        val directory = File(noBackupFilesDir, "recordings/$id")
        if (!directory.mkdirs() || !directory.isDirectory) {
            publishFailure("recordingDirectory")
            stopSelf()
            return
        }
        syncDirectory(directory.parentFile ?: noBackupFilesDir)
        if (!RecordingManifestStore.writePresetSnapshot(this, id, RecordingPresetSnapshotCodec.encode(preset))) {
            directory.deleteRecursively()
            publishFailure("presetSnapshot")
            stopSelf()
            return
        }
        val autoStopSettings = VoiceAutoStopSettingsStore.get(this).state.value
        if (!RecordingAutoStopSnapshot.write(directory, autoStopSettings)) {
            directory.deleteRecursively()
            publishFailure("autoStopSnapshot")
            stopSelf()
            return
        }
        session = Session(
            id,
            directory,
            System.currentTimeMillis(),
            0L,
            0,
            liveSpeech = RecorderLiveSpeechProvider.create(this, id),
            autoStopSettings = autoStopSettings,
            autoStop = autoStopSettings.takeIf(VoiceAutoStopSettings::enabled)?.let {
                VoicePauseDetector(it.pauseDurationMillis)
            },
        )
        desiredPhase.set(RecordingPhase.RECORDING)
        val initial = sessionStatus(RecordingPhase.RECORDING)
        RecordingManifestStore.write(this, initial)
        RecordingStatusRegistry.publish(initial)
        startForegroundNotification(initial)
        beginCaptureLoop()
    }

    private fun resumeSession() {
        val current = session ?: return
        if (desiredPhase.get() !in setOf(RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED) || loopRunning.get()) return
        desiredPhase.set(RecordingPhase.RECORDING)
        current.liveSpeech = current.liveSpeech ?: RecorderLiveSpeechProvider.create(this, current.id)
        current.liveSpeech?.resume()
        current.autoStop?.reset()
        current.segmentStartedAtRealtime = SystemClock.elapsedRealtime()
        val resumed = sessionStatus(RecordingPhase.RECORDING)
        RecordingManifestStore.write(this, resumed)
        RecordingStatusRegistry.publish(resumed)
        startForegroundNotification(resumed)
        beginCaptureLoop()
    }

    private fun requestTransition(target: RecordingPhase) {
        val current = session ?: return
        val present = desiredPhase.get()
        if (present !in setOf(RecordingPhase.RECORDING, RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED)) return
        desiredPhase.set(target)
        if (present == RecordingPhase.PAUSED || !loopRunning.get()) {
            completeTransition(current, target)
        } else {
            runCatching { recorder?.stop() }
        }
    }

    private fun beginCaptureLoop() {
        val current = session ?: return
        if (!loopRunning.compareAndSet(false, true)) return
        current.segmentStartedAtRealtime = SystemClock.elapsedRealtime()
        executor.execute { capture(current) }
    }

    @Suppress("MissingPermission")
    private fun capture(current: Session) {
        var audio: AudioRecord? = null
        var sink: ChunkSink? = null
        var failure: String? = null
        var completionCode: String? = null
        try {
            val minimum = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_ENCODING)
            if (minimum <= 0) throw IllegalStateException("unsupportedAudioFormat")
            val bufferSize = max(minimum, READ_BUFFER_BYTES * 2)
            audio = AudioRecord(
                MediaRecorder.AudioSource.VOICE_RECOGNITION,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_ENCODING,
                bufferSize,
            )
            if (audio.state != AudioRecord.STATE_INITIALIZED) throw IllegalStateException("audioRecordInitialization")
            recorder = audio
            audio.startRecording()
            sink = ChunkSink(current.directory, current.chunkCount)
            val buffer = ByteArray(READ_BUFFER_BYTES)
            var lastManifestAt = SystemClock.elapsedRealtime()
            while (!destroyed && desiredPhase.get() == RecordingPhase.RECORDING) {
                val read = audio.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                if (read <= 0) {
                    if (desiredPhase.get() == RecordingPhase.RECORDING) failure = "audioRead"
                    break
                }
                var offset = 0
                while (offset < read) {
                    val activeSink = checkNotNull(sink)
                    val written = activeSink.write(buffer, offset, read - offset)
                    offset += written
                    if (activeSink.isFull) {
                        activeSink.finish()
                        current.chunkCount += 1
                        sink = ChunkSink(current.directory, current.chunkCount)
                    }
                }
                current.liveSpeech?.offer(buffer, read)
                val now = SystemClock.elapsedRealtime()
                val elapsed = current.elapsedBeforeSegment + (now - current.segmentStartedAtRealtime)
                val level = pcmLevel(buffer, read)
                val frameDurationMillis = (read * 1_000L) / (SAMPLE_RATE * 2L)
                if (current.autoStop?.accept(level, frameDurationMillis) == VoicePauseEvent.END_OF_SPEECH) {
                    when (current.autoStopSettings.endAction) {
                        VoiceAutoStopEndAction.STOP_RECORDING -> {
                            desiredPhase.compareAndSet(RecordingPhase.RECORDING, RecordingPhase.COMPLETED)
                            completionCode = "voiceAutoStop"
                        }
                        VoiceAutoStopEndAction.SAVE_SEGMENT_AND_CONTINUE -> {
                            val activeSink = checkNotNull(sink)
                            if (activeSink.length > 0) {
                                activeSink.finish()
                                current.chunkCount += 1
                            } else {
                                activeSink.discardEmpty()
                            }
                            sink = null
                            if (!RecordingSegmentStore.appendBoundary(current.directory, current.chunkCount)) {
                                desiredPhase.compareAndSet(RecordingPhase.RECORDING, RecordingPhase.COMPLETED)
                                completionCode = "segmentBoundaryPersistence"
                            } else {
                                sink = ChunkSink(current.directory, current.chunkCount)
                                current.autoStop?.reset()
                                RecordingManifestStore.write(this, sessionStatus(RecordingPhase.RECORDING, elapsed, level))
                            }
                        }
                    }
                }
                RecordingStatusRegistry.publish(sessionStatus(RecordingPhase.RECORDING, elapsed, level))
                if (now - lastManifestAt >= MANIFEST_CHECKPOINT_MILLIS) {
                    checkNotNull(sink).sync()
                    RecordingManifestStore.write(this, sessionStatus(RecordingPhase.RECORDING, elapsed, level))
                    updateNotification(sessionStatus(RecordingPhase.RECORDING, elapsed, level))
                    lastManifestAt = now
                }
                if (current.autoStopSettings.endAction == VoiceAutoStopEndAction.SAVE_SEGMENT_AND_CONTINUE &&
                    elapsed >= CONTINUOUS_LISTENING_LIMIT_MILLIS
                ) {
                    desiredPhase.compareAndSet(RecordingPhase.RECORDING, RecordingPhase.COMPLETED)
                    completionCode = "continuousListeningLimitReached"
                } else if (reachedRecordingSafetyLimit(elapsed)) {
                    desiredPhase.compareAndSet(RecordingPhase.RECORDING, RecordingPhase.COMPLETED)
                    completionCode = "safetyLimitReached"
                }
            }
        } catch (_: SecurityException) {
            failure = "microphonePermission"
        } catch (error: Exception) {
            if (desiredPhase.get() == RecordingPhase.RECORDING) failure = error.message ?: "audioCapture"
        } finally {
            runCatching { audio?.stop() }
            runCatching { audio?.release() }
            recorder = null
            runCatching {
                if (sink != null && sink.length > 0) {
                    sink.finish()
                    current.chunkCount += 1
                } else sink?.discardEmpty()
            }.onFailure { failure = "chunkFinalize" }
            current.elapsedBeforeSegment += (SystemClock.elapsedRealtime() - current.segmentStartedAtRealtime).coerceAtLeast(0)
            loopRunning.set(false)
            val target = when {
                failure != null -> RecordingPhase.FAILED
                destroyed -> RecordingPhase.INTERRUPTED
                else -> desiredPhase.get()
            }
            completeTransition(current, target, failure ?: completionCode)
        }
    }

    private fun completeTransition(current: Session, phase: RecordingPhase, failure: String? = null) {
        desiredPhase.set(phase)
        val status = sessionStatus(phase, current.elapsedBeforeSegment, 0f, failure)
        RecordingManifestStore.write(this, status)
        RecordingStatusRegistry.publish(status)
        when (phase) {
            RecordingPhase.PAUSED -> {
                current.autoStop?.reset()
                current.liveSpeech?.pause()
                updateNotification(status)
            }
            RecordingPhase.RECORDING -> Unit
            else -> {
                current.liveSpeech?.finish(shouldDiscard = phase == RecordingPhase.DISCARDED)
                current.liveSpeech = null
                ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun publishFailure(code: String) {
        val status = RecordingStatus(phase = RecordingPhase.FAILED, failureCode = code)
        RecordingStatusRegistry.publish(status)
    }

    private fun sessionStatus(
        phase: RecordingPhase,
        elapsed: Long = session?.let { it.elapsedBeforeSegment + (SystemClock.elapsedRealtime() - it.segmentStartedAtRealtime).coerceAtLeast(0) } ?: 0,
        level: Float = 0f,
        failure: String? = null,
    ): RecordingStatus {
        val current = session ?: return RecordingStatus(phase = phase, failureCode = failure)
        return RecordingStatus(current.id, phase, current.createdAtEpochMillis, elapsed, level, current.chunkCount, failure)
    }

    private fun startForegroundNotification(status: RecordingStatus) {
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification(status),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0,
        )
    }

    private fun updateNotification(status: RecordingStatus) {
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification(status))
    }

    private fun notification(status: RecordingStatus): Notification {
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(this, 10, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle(if (status.phase == RecordingPhase.PAUSED) "Voice capture paused" else "Recording voice capture")
            .setContentText(formatElapsed(status.elapsedMillis))
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setContentIntent(contentIntent)
        val pauseAction = if (status.phase == RecordingPhase.PAUSED) ACTION_RESUME else ACTION_PAUSE
        val pauseLabel = if (status.phase == RecordingPhase.PAUSED) "Resume" else "Pause"
        builder.addAction(0, pauseLabel, servicePendingIntent(pauseAction, 11))
        builder.addAction(0, "Stop", servicePendingIntent(ACTION_STOP, 12))
        builder.addAction(0, "Cancel", servicePendingIntent(ACTION_CANCEL, 13))
        notificationExtender?.let { extender ->
            runCatching { extender.extend(this, NOTIFICATION_ID, status, builder) }
        }
        return builder.build()
    }

    @Suppress("DEPRECATION")
    private fun loadNotificationExtender(): RecordingNotificationExtender? = runCatching {
        val applicationInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.getApplicationInfo(
                packageName,
                android.content.pm.PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong()),
            )
        } else {
            packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
        }
        val className = applicationInfo.metaData?.getString(RECORDING_NOTIFICATION_EXTENDER_METADATA)
            ?.takeIf(String::isNotBlank)
            ?: return@runCatching null
        val candidate = Class.forName(className).getDeclaredConstructor().newInstance()
        candidate as? RecordingNotificationExtender
    }.getOrNull()

    private fun servicePendingIntent(action: String, requestCode: Int): PendingIntent = PendingIntent.getService(
        this,
        requestCode,
        Intent(this, AudioCaptureService::class.java).setAction(action),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    private fun createNotificationChannel() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Voice captures", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Keeps active Vox.md voice captures visible and controllable."
                setSound(null, null)
            },
        )
    }

    private data class Session(
        val id: String,
        val directory: File,
        val createdAtEpochMillis: Long,
        var elapsedBeforeSegment: Long,
        var chunkCount: Int,
        var segmentStartedAtRealtime: Long = SystemClock.elapsedRealtime(),
        var liveSpeech: RecorderLiveSpeechSession? = null,
        val autoStopSettings: VoiceAutoStopSettings = VoiceAutoStopSettings(),
        var autoStop: VoicePauseDetector? = null,
    )

    private class ChunkSink(private val directory: File, index: Int) {
        private val temporary = File(directory, "chunk-${index.toString().padStart(6, '0')}.pcm.part")
        private val finished = File(directory, "chunk-${index.toString().padStart(6, '0')}.pcm")
        private val stream = FileOutputStream(temporary)
        var length: Int = 0
            private set
        val isFull: Boolean get() = length >= CHUNK_BYTES

        fun write(bytes: ByteArray, offset: Int, count: Int): Int {
            val writable = minOf(count, CHUNK_BYTES - length)
            stream.write(bytes, offset, writable)
            length += writable
            return writable
        }

        fun sync() {
            stream.flush()
            stream.fd.sync()
        }

        fun finish() {
            sync()
            stream.close()
            if (!temporary.renameTo(finished)) throw IllegalStateException("chunkPromotion")
            syncDirectory(directory)
        }

        fun discardEmpty() {
            stream.close()
            temporary.delete()
        }
    }

    companion object {
        const val ACTION_START = "md.vox.android.action.RECORDING_START"
        const val ACTION_PAUSE = "md.vox.android.action.RECORDING_PAUSE"
        const val ACTION_RESUME = "md.vox.android.action.RECORDING_RESUME"
        const val ACTION_STOP = "md.vox.android.action.RECORDING_STOP"
        const val ACTION_CANCEL = "md.vox.android.action.RECORDING_CANCEL"
        const val EXTRA_PRESET_SNAPSHOT = "md.vox.android.extra.RECORDING_PRESET_SNAPSHOT"
        private const val CHANNEL_ID = "vox-voice-capture-v1"
        private const val NOTIFICATION_ID = 201
        private const val RECORDING_NOTIFICATION_EXTENDER_METADATA =
            "md.vox.android.RECORDING_NOTIFICATION_EXTENDER"
        private const val SAMPLE_RATE = 16_000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_ENCODING = AudioFormat.ENCODING_PCM_16BIT
        private const val READ_BUFFER_BYTES = 3_200
        private const val CHUNK_BYTES = SAMPLE_RATE * 2 * 2
        private const val MANIFEST_CHECKPOINT_MILLIS = 1_000L
    }
}

private object RecordingManifestStore {
    private const val VERSION = 1
    private const val SAMPLE_RATE = 16_000
    private const val CHANNEL_COUNT = 1
    private const val BITS_PER_SAMPLE = 16

    fun latest(context: Context): RecordingStatus? {
        val root = File(context.noBackupFilesDir, "recordings")
        val pointer = File(root, "latest-session-id")
        val id = runCatching { pointer.readText().trim() }.getOrNull()?.takeIf(UUID_PATTERN::matches) ?: return null
        return read(File(root, "$id/session.properties"))
    }

    fun all(context: Context): List<RecordingStatus> {
        val root = File(context.noBackupFilesDir, "recordings")
        return root.listFiles().orEmpty().asSequence()
            .filter { it.isDirectory && UUID_PATTERN.matches(it.name) }
            .mapNotNull { read(File(it, "session.properties")) }
            .sortedByDescending(RecordingStatus::createdAtEpochMillis)
            .toList()
    }

    /**
     * Recovers every abandoned active manifest, not only the latest pointer target.
     * Paused recordings remain resumable; RECORDING means the owning process vanished
     * and is converted to an explicit, audio-preserving interrupted state.
     */
    fun recoverInterrupted(context: Context): List<RecordingStatus> {
        val root = File(context.noBackupFilesDir, "recordings")
        val statuses = all(context)
        var changed = false
        val recovered = statuses.map { status ->
            recoverInterruptedRecording(status).also { next ->
                if (next != status) {
                    val id = requireNotNull(next.sessionID)
                    val directory = File(root, id)
                    writeStatusFile(directory, next)
                    syncDirectory(directory)
                    changed = true
                }
            }
        }
        if (changed) syncDirectory(root)
        return recovered
    }

    fun exportWav(context: Context, sessionID: String, output: OutputStream): Boolean = runCatching {
        val directory = recordingDirectory(context, sessionID) ?: return@runCatching false
        val status = read(File(directory, "session.properties")) ?: return@runCatching false
        if (status.phase == RecordingPhase.RECORDING) return@runCatching false
        val chunks = directory.listFiles().orEmpty()
            .filter { it.isFile && it.name.matches(CHUNK_PATTERN) }
            .sortedBy(File::getName)
        if (chunks.isEmpty()) return@runCatching false
        val audioBytes = chunks.sumOf(File::length)
        require(audioBytes <= UINT32_MAX - 36L)
        writeWavHeader(output, audioBytes)
        val buffer = ByteArray(64 * 1_024)
        chunks.forEach { chunk ->
            chunk.inputStream().use { input ->
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    output.write(buffer, 0, count)
                }
            }
        }
        output.flush()
        true
    }.getOrDefault(false)

    fun delete(context: Context, sessionID: String): Boolean {
        val directory = recordingDirectory(context, sessionID) ?: return false
        if (Files.isSymbolicLink(directory.toPath())) return false
        if (!directory.deleteRecursively()) return false
        val root = File(context.noBackupFilesDir, "recordings")
        val pointer = File(root, "latest-session-id")
        if (runCatching { pointer.readText().trim() }.getOrNull() == sessionID) {
            val next = all(context).firstOrNull()
            if (next == null) {
                pointer.delete()
            } else {
                writeLatestPointer(root, requireNotNull(next.sessionID))
            }
        }
        syncDirectory(root)
        return true
    }

    fun deleteAudio(context: Context, sessionID: String): RecordingStatus? {
        val directory = recordingDirectory(context, sessionID) ?: return null
        if (Files.isSymbolicLink(directory.toPath())) return null
        val status = read(File(directory, "session.properties")) ?: return null
        if (status.isActive) return null
        val chunks = directory.listFiles().orEmpty().filter { it.isFile && CHUNK_PATTERN.matches(it.name) }
        if (chunks.any { !it.delete() }) return null
        val updated = status.copy(chunkCount = 0, level = 0f)
        write(context, updated)
        syncDirectory(directory)
        return updated
    }

    fun isImportedFromWear(context: Context, sessionID: String): Boolean =
        recordingDirectory(context, sessionID)?.resolve("wear-preset.json")?.isFile == true

    fun writePresetSnapshot(context: Context, sessionID: String, snapshot: String): Boolean = runCatching {
        require(snapshot.toByteArray(StandardCharsets.UTF_8).size in 1..65_536)
        val directory = recordingDirectory(context, sessionID) ?: return@runCatching false
        val target = AtomicFile(File(directory, PRESET_SNAPSHOT_FILE))
        val output = target.startWrite()
        try {
            output.write(snapshot.toByteArray(StandardCharsets.UTF_8))
            output.flush()
            output.fd.sync()
            target.finishWrite(output)
        } catch (error: Throwable) {
            target.failWrite(output)
            throw error
        }
        syncDirectory(directory)
        true
    }.getOrDefault(false)

    fun presetSnapshot(context: Context, sessionID: String): String? {
        val directory = recordingDirectory(context, sessionID) ?: return null
        val file = listOf(PRESET_SNAPSHOT_FILE, "wear-preset.json")
            .map(directory::resolve)
            .firstOrNull(File::isFile)
            ?: return null
        return runCatching {
            require(file.length() in 1..65_536)
            file.readText(StandardCharsets.UTF_8)
        }.getOrNull()
    }

    fun importWearRecording(
        context: Context,
        sessionID: String,
        createdAtEpochMillis: Long,
        durationMillis: Long,
        chunkCount: Int,
        sourceDirectory: File,
        presetSnapshot: ByteArray,
    ): Boolean = runCatching {
        require(UUID_PATTERN.matches(sessionID))
        require(createdAtEpochMillis >= 0 && durationMillis >= 0)
        require(chunkCount in 1..100_000)
        require(presetSnapshot.size in 1..65_536)
        val sourceRoot = sourceDirectory.canonicalFile
        require(sourceRoot.isDirectory && !Files.isSymbolicLink(sourceRoot.toPath()))
        val sources = sourceRoot.listFiles().orEmpty()
            .filter { it.isFile && it.name.matches(CHUNK_PATTERN) && !Files.isSymbolicLink(it.toPath()) }
            .sortedBy(File::getName)
        require(sources.size == chunkCount)

        val root = File(context.noBackupFilesDir, "recordings").apply { mkdirs() }
        val finalDirectory = File(root, sessionID)
        if (finalDirectory.isDirectory) {
            val present = read(File(finalDirectory, "session.properties"))
            return@runCatching present?.phase == RecordingPhase.COMPLETED && present.chunkCount == chunkCount
        }
        val staging = File(root, "$sessionID.wear.part")
        if (staging.exists()) staging.deleteRecursively()
        require(staging.mkdir())
        sources.forEachIndexed { index, source ->
            val target = File(staging, "chunk-${index.toString().padStart(6, '0')}.pcm")
            Files.copy(source.toPath(), target.toPath(), StandardCopyOption.COPY_ATTRIBUTES)
            FileOutputStream(target, true).use { it.fd.sync() }
        }
        File(staging, "wear-preset.json").let { target ->
            FileOutputStream(target).use { output ->
                output.write(presetSnapshot)
                output.flush()
                output.fd.sync()
            }
        }
        val status = RecordingStatus(
            sessionID = sessionID,
            phase = RecordingPhase.COMPLETED,
            createdAtEpochMillis = createdAtEpochMillis,
            elapsedMillis = durationMillis,
            chunkCount = chunkCount,
            failureCode = "wearImported",
        )
        writeStatusFile(staging, status)
        syncDirectory(staging)
        require(staging.renameTo(finalDirectory))
        syncDirectory(root)
        writeLatestPointer(root, sessionID)
        true
    }.getOrDefault(false)

    fun importDecodedMedia(
        context: Context,
        stagingDirectory: File,
        status: RecordingStatus,
        presetSnapshot: String,
    ): Boolean = runCatching {
        val sessionID = requireNotNull(status.sessionID).also { require(UUID_PATTERN.matches(it)) }
        require(status.phase == RecordingPhase.COMPLETED && status.chunkCount > 0 && status.elapsedMillis > 0)
        require(presetSnapshot.toByteArray(StandardCharsets.UTF_8).size in 1..65_536)
        val root = File(context.noBackupFilesDir, "recordings").apply { mkdirs() }.canonicalFile
        val staging = stagingDirectory.canonicalFile
        require(staging.parentFile == root && staging.name == ".$sessionID.import.part" && !Files.isSymbolicLink(staging.toPath()))
        val chunks = staging.listFiles().orEmpty()
            .filter { it.isFile && CHUNK_PATTERN.matches(it.name) && !Files.isSymbolicLink(it.toPath()) }
            .sortedBy(File::getName)
        require(chunks.size == status.chunkCount)
        chunks.forEachIndexed { index, chunk ->
            require(chunk.name == "chunk-${index.toString().padStart(6, '0')}.pcm" && chunk.length() > 0)
        }
        AtomicFile(File(staging, PRESET_SNAPSHOT_FILE)).let { target ->
            val output = target.startWrite()
            try {
                output.write(presetSnapshot.toByteArray(StandardCharsets.UTF_8))
                output.flush()
                output.fd.sync()
                target.finishWrite(output)
            } catch (error: Throwable) {
                target.failWrite(output)
                throw error
            }
        }
        require(RecordingAutoStopSnapshot.write(staging, VoiceAutoStopSettings()))
        writeStatusFile(staging, status)
        syncDirectory(staging)
        val destination = File(root, sessionID)
        require(!destination.exists() && staging.renameTo(destination))
        syncDirectory(root)
        writeLatestPointer(root, sessionID)
        true
    }.getOrDefault(false)

    fun write(context: Context, status: RecordingStatus) {
        val id = status.sessionID ?: return
        val root = File(context.noBackupFilesDir, "recordings")
        val directory = File(root, id)
        if (!directory.isDirectory) return
        val manifest = AtomicFile(File(directory, "session.properties"))
        val bytes = encode(status).toByteArray(StandardCharsets.UTF_8)
        val output = manifest.startWrite()
        try {
            output.write(bytes)
            output.flush()
            output.fd.sync()
            manifest.finishWrite(output)
        } catch (error: Exception) {
            manifest.failWrite(output)
            throw error
        }
        writeLatestPointer(root, id)
        syncDirectory(directory)
        syncDirectory(root)
    }

    private fun writeStatusFile(directory: File, status: RecordingStatus) {
        val manifest = AtomicFile(File(directory, "session.properties"))
        val bytes = encode(status).toByteArray(StandardCharsets.UTF_8)
        val output = manifest.startWrite()
        try {
            output.write(bytes)
            output.flush()
            output.fd.sync()
            manifest.finishWrite(output)
        } catch (error: Exception) {
            manifest.failWrite(output)
            throw error
        }
    }

    private fun writeLatestPointer(root: File, id: String) {
        val pointer = AtomicFile(File(root, "latest-session-id"))
        val pointerOutput = pointer.startWrite()
        try {
            pointerOutput.write(id.toByteArray(StandardCharsets.UTF_8))
            pointerOutput.flush()
            pointerOutput.fd.sync()
            pointer.finishWrite(pointerOutput)
        } catch (error: Exception) {
            pointer.failWrite(pointerOutput)
            throw error
        }
    }

    private fun recordingDirectory(context: Context, sessionID: String): File? {
        if (!UUID_PATTERN.matches(sessionID)) return null
        val root = File(context.noBackupFilesDir, "recordings")
        val directory = File(root, sessionID)
        val expectedParent = runCatching { root.canonicalFile }.getOrNull() ?: return null
        val canonical = runCatching { directory.canonicalFile }.getOrNull() ?: return null
        return canonical.takeIf { it.parentFile == expectedParent && it.isDirectory }
    }

    private fun writeWavHeader(output: OutputStream, audioBytes: Long) {
        fun ascii(value: String) = output.write(value.toByteArray(StandardCharsets.US_ASCII))
        fun littleEndian(value: Long, byteCount: Int) {
            repeat(byteCount) { shift -> output.write(((value shr (shift * 8)) and 0xff).toInt()) }
        }
        val byteRate = SAMPLE_RATE * CHANNEL_COUNT * BITS_PER_SAMPLE / 8
        val blockAlign = CHANNEL_COUNT * BITS_PER_SAMPLE / 8
        ascii("RIFF")
        littleEndian(36L + audioBytes, 4)
        ascii("WAVEfmt ")
        littleEndian(16, 4)
        littleEndian(1, 2)
        littleEndian(CHANNEL_COUNT.toLong(), 2)
        littleEndian(SAMPLE_RATE.toLong(), 4)
        littleEndian(byteRate.toLong(), 4)
        littleEndian(blockAlign.toLong(), 2)
        littleEndian(BITS_PER_SAMPLE.toLong(), 2)
        ascii("data")
        littleEndian(audioBytes, 4)
    }

    private fun read(file: File): RecordingStatus? = runCatching {
        val values = file.readLines().associate { line ->
            val split = line.indexOf('=')
            require(split > 0)
            line.substring(0, split) to line.substring(split + 1)
        }
        require(values["version"]?.toInt() == VERSION)
        val id = requireNotNull(values["sessionID"]).also { require(UUID_PATTERN.matches(it)) }
        RecordingStatus(
            sessionID = id,
            phase = RecordingPhase.valueOf(requireNotNull(values["phase"])),
            createdAtEpochMillis = requireNotNull(values["createdAtEpochMillis"]).toLong().also { require(it >= 0) },
            elapsedMillis = requireNotNull(values["elapsedMillis"]).toLong().also { require(it >= 0) },
            level = 0f,
            chunkCount = requireNotNull(values["chunkCount"]).toInt().also { require(it >= 0) },
            failureCode = values["failureCode"]?.takeIf(String::isNotBlank),
        )
    }.getOrNull()

    private fun encode(status: RecordingStatus): String = buildString {
        append("version=").append(VERSION).append('\n')
        append("sessionID=").append(status.sessionID).append('\n')
        append("phase=").append(status.phase.name).append('\n')
        append("createdAtEpochMillis=").append(status.createdAtEpochMillis.coerceAtLeast(0)).append('\n')
        append("elapsedMillis=").append(status.elapsedMillis.coerceAtLeast(0)).append('\n')
        append("chunkCount=").append(status.chunkCount.coerceAtLeast(0)).append('\n')
        append("failureCode=").append(status.failureCode.orEmpty()).append('\n')
        append("sampleRate=").append(16_000).append('\n')
        append("channelCount=1\n")
        append("encoding=pcm16le\n")
    }

    private val CHUNK_PATTERN = Regex("^chunk-[0-9]{6}\\.pcm$")
    private const val UINT32_MAX = 0xffff_ffffL
    private const val PRESET_SNAPSHOT_FILE = "preset-snapshot.json"
}

internal fun pcmLevel(bytes: ByteArray, length: Int): Float {
    var peak = 0
    var index = 0
    while (index + 1 < length) {
        val sample = (bytes[index].toInt() and 0xff) or (bytes[index + 1].toInt() shl 8)
        peak = max(peak, abs(sample.toShort().toInt()))
        index += 2
    }
    return (peak / 32768f).coerceIn(0f, 1f)
}

internal fun formatElapsed(milliseconds: Long): String {
    val seconds = milliseconds.coerceAtLeast(0) / 1_000
    return "%d:%02d".format(seconds / 60, seconds % 60)
}

internal fun recoverInterruptedRecording(status: RecordingStatus): RecordingStatus =
    if (status.phase == RecordingPhase.RECORDING) {
        status.copy(phase = RecordingPhase.INTERRUPTED, level = 0f, failureCode = "processInterrupted")
    } else {
        status
    }

private fun syncDirectory(directory: File) {
    val descriptor = Os.open(directory.absolutePath, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
    try {
        Os.fsync(descriptor)
    } finally {
        Os.close(descriptor)
    }
}

private val UUID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
