package md.vox.android.platformservices

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files

enum class RecordingProcessingPolicy { IMMEDIATE, WHEN_IDLE, MANUAL }

enum class RecordingRetentionKind { DELETE_AFTER_SUCCESS, TIMED, PERMANENT }

data class RecordingJobPolicy(
    val processing: RecordingProcessingPolicy = RecordingProcessingPolicy.IMMEDIATE,
    val retention: RecordingRetentionKind = RecordingRetentionKind.TIMED,
    val retentionMillis: Long = DEFAULT_RECORDING_RETENTION_MILLIS,
) {
    fun normalized(): RecordingJobPolicy = copy(
        retentionMillis = retentionMillis.coerceIn(MIN_RECORDING_RETENTION_MILLIS, MAX_RECORDING_RETENTION_MILLIS),
    )
}

internal const val MIN_RECORDING_RETENTION_MILLIS = 60_000L
internal const val DEFAULT_RECORDING_RETENTION_MILLIS = 7L * 24 * 60 * 60 * 1_000
internal const val MAX_RECORDING_RETENTION_MILLIS = 365L * 24 * 60 * 60 * 1_000

fun shouldProcessRecordingAutomatically(
    policy: RecordingProcessingPolicy,
    appIsIdle: Boolean,
): Boolean = when (policy) {
    RecordingProcessingPolicy.IMMEDIATE -> true
    RecordingProcessingPolicy.WHEN_IDLE -> appIsIdle
    RecordingProcessingPolicy.MANUAL -> false
}

fun shouldDeleteRecordingAudio(
    policy: RecordingJobPolicy,
    transcriptionCompleted: Boolean,
    completedAtEpochMillis: Long?,
    nowEpochMillis: Long,
): Boolean {
    if (!transcriptionCompleted) return false
    return when (policy.retention) {
        RecordingRetentionKind.DELETE_AFTER_SUCCESS -> true
        RecordingRetentionKind.PERMANENT -> false
        RecordingRetentionKind.TIMED -> completedAtEpochMillis != null &&
            nowEpochMillis >= completedAtEpochMillis + policy.normalized().retentionMillis
    }
}

fun recordingRetentionDeadlineEpochMillis(
    policy: RecordingJobPolicy,
    transcriptionCompletedAtEpochMillis: Long?,
): Long? = when (policy.retention) {
    RecordingRetentionKind.PERMANENT -> null
    RecordingRetentionKind.DELETE_AFTER_SUCCESS -> transcriptionCompletedAtEpochMillis
    RecordingRetentionKind.TIMED -> transcriptionCompletedAtEpochMillis?.let { completedAt ->
        val duration = policy.normalized().retentionMillis
        if (completedAt > Long.MAX_VALUE - duration) Long.MAX_VALUE else completedAt + duration
    }
}

class RecordingJobPolicyStore private constructor(context: Context) {
    private val root = File(context.applicationContext.noBackupFilesDir, "recordings")

    fun policy(sessionID: String): RecordingJobPolicy {
        val directory = recordingDirectory(sessionID) ?: return RecordingJobPolicy()
        val values = runCatching {
            File(directory, FILE_NAME).readLines().associate { line ->
                val separator = line.indexOf('=')
                require(separator > 0)
                line.substring(0, separator) to line.substring(separator + 1)
            }
        }.getOrNull() ?: return RecordingJobPolicy()
        if (values["version"] != "1") return RecordingJobPolicy()
        return RecordingJobPolicy(
            processing = values["processing"]?.let { runCatching { RecordingProcessingPolicy.valueOf(it) }.getOrNull() }
                ?: RecordingProcessingPolicy.IMMEDIATE,
            retention = values["retention"]?.let { runCatching { RecordingRetentionKind.valueOf(it) }.getOrNull() }
                ?: RecordingRetentionKind.TIMED,
            retentionMillis = values["retentionMillis"]?.toLongOrNull() ?: DEFAULT_RECORDING_RETENTION_MILLIS,
        ).normalized()
    }

    fun update(sessionID: String, policy: RecordingJobPolicy): Boolean {
        val directory = recordingDirectory(sessionID) ?: return false
        val normalized = policy.normalized()
        val encoded = buildString {
            append("version=1\n")
            append("processing=").append(normalized.processing.name).append('\n')
            append("retention=").append(normalized.retention.name).append('\n')
            append("retentionMillis=").append(normalized.retentionMillis).append('\n')
        }
        val atomic = AtomicFile(File(directory, FILE_NAME))
        val output = runCatching { atomic.startWrite() }.getOrNull() ?: return false
        return try {
            output.write(encoded.toByteArray(StandardCharsets.UTF_8))
            output.flush()
            output.fd.sync()
            atomic.finishWrite(output)
            true
        } catch (_: Throwable) {
            atomic.failWrite(output)
            false
        }
    }

    private fun recordingDirectory(sessionID: String): File? {
        if (!UUID_PATTERN.matches(sessionID)) return null
        val canonicalRoot = runCatching { root.canonicalFile }.getOrNull() ?: return null
        val directory = runCatching { File(root, sessionID).canonicalFile }.getOrNull() ?: return null
        return directory.takeIf { it.parentFile == canonicalRoot && it.isDirectory && !Files.isSymbolicLink(it.toPath()) }
    }

    companion object {
        private const val FILE_NAME = "job-policy.properties"
        private val UUID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        @Volatile private var shared: RecordingJobPolicyStore? = null

        fun get(context: Context): RecordingJobPolicyStore = shared ?: synchronized(this) {
            shared ?: RecordingJobPolicyStore(context).also { shared = it }
        }
    }
}
