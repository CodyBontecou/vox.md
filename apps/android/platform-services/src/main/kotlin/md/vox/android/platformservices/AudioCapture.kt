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
import java.nio.charset.StandardCharsets
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.math.abs
import kotlin.math.max
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

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

object RecordingStatusRegistry {
    private val mutableStatus = MutableStateFlow(RecordingStatus())
    val status: StateFlow<RecordingStatus> = mutableStatus.asStateFlow()

    internal fun publish(value: RecordingStatus) {
        mutableStatus.value = value
    }
}

class AudioCaptureClient(context: Context) {
    private val appContext = context.applicationContext

    init {
        RecordingManifestStore.latest(appContext)?.let { persisted ->
            val recovered = recoverInterruptedRecording(persisted)
            if (recovered != persisted) RecordingManifestStore.write(appContext, recovered)
            RecordingStatusRegistry.publish(recovered)
        }
    }

    fun start() = dispatch(AudioCaptureService.ACTION_START, foreground = true)
    fun pause() = dispatch(AudioCaptureService.ACTION_PAUSE)
    fun resume() = dispatch(AudioCaptureService.ACTION_RESUME, foreground = true)
    fun stop() = dispatch(AudioCaptureService.ACTION_STOP)
    fun cancel() = dispatch(AudioCaptureService.ACTION_CANCEL)

    fun dismissResult() {
        if (!RecordingStatusRegistry.status.value.isActive) RecordingStatusRegistry.publish(RecordingStatus())
    }

    private fun dispatch(action: String, foreground: Boolean = false) {
        val intent = Intent(appContext, AudioCaptureService::class.java).setAction(action)
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

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        val recovered = RecordingManifestStore.latest(this)
        if (recovered != null && recovered.phase in setOf(RecordingPhase.RECORDING, RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED)) {
            session = Session(
                id = requireNotNull(recovered.sessionID),
                directory = File(noBackupFilesDir, "recordings/${recovered.sessionID}"),
                createdAtEpochMillis = recovered.createdAtEpochMillis,
                elapsedBeforeSegment = recovered.elapsedMillis,
                chunkCount = recovered.chunkCount,
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
            ACTION_START -> startNewSession()
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

    private fun startNewSession() {
        if (RecordingStatusRegistry.status.value.isActive || loopRunning.get()) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            publishFailure("microphonePermission")
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
        session = Session(id, directory, System.currentTimeMillis(), 0L, 0)
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
                val now = SystemClock.elapsedRealtime()
                val elapsed = current.elapsedBeforeSegment + (now - current.segmentStartedAtRealtime)
                val level = pcmLevel(buffer, read)
                RecordingStatusRegistry.publish(sessionStatus(RecordingPhase.RECORDING, elapsed, level))
                if (now - lastManifestAt >= MANIFEST_CHECKPOINT_MILLIS) {
                    checkNotNull(sink).sync()
                    RecordingManifestStore.write(this, sessionStatus(RecordingPhase.RECORDING, elapsed, level))
                    updateNotification(sessionStatus(RecordingPhase.RECORDING, elapsed, level))
                    lastManifestAt = now
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
            completeTransition(current, target, failure)
        }
    }

    private fun completeTransition(current: Session, phase: RecordingPhase, failure: String? = null) {
        desiredPhase.set(phase)
        val status = sessionStatus(phase, current.elapsedBeforeSegment, 0f, failure)
        RecordingManifestStore.write(this, status)
        RecordingStatusRegistry.publish(status)
        when (phase) {
            RecordingPhase.PAUSED -> updateNotification(status)
            RecordingPhase.RECORDING -> Unit
            else -> {
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
        return builder.build()
    }

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
        private const val CHANNEL_ID = "vox-voice-capture-v1"
        private const val NOTIFICATION_ID = 201
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

    fun latest(context: Context): RecordingStatus? {
        val root = File(context.noBackupFilesDir, "recordings")
        val pointer = File(root, "latest-session-id")
        val id = runCatching { pointer.readText().trim() }.getOrNull()?.takeIf(UUID_PATTERN::matches) ?: return null
        return read(File(root, "$id/session.properties"))
    }

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
        syncDirectory(directory)
        syncDirectory(root)
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
