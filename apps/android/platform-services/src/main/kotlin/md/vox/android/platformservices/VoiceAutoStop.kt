package md.vox.android.platformservices

import android.content.Context
import android.util.AtomicFile
import java.io.File
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class VoiceAutoStopEndAction { STOP_RECORDING, SAVE_SEGMENT_AND_CONTINUE }

data class VoiceAutoStopSettings(
    val enabled: Boolean = false,
    val pauseDurationMillis: Long = DEFAULT_PAUSE_MILLIS,
    val endAction: VoiceAutoStopEndAction = VoiceAutoStopEndAction.STOP_RECORDING,
) {
    fun normalized(): VoiceAutoStopSettings = copy(
        pauseDurationMillis = pauseDurationMillis.coerceIn(MIN_PAUSE_MILLIS, MAX_PAUSE_MILLIS),
    )
}

class VoiceAutoStopSettingsStore private constructor(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
    private val mutableState = MutableStateFlow(read())
    val state: StateFlow<VoiceAutoStopSettings> = mutableState.asStateFlow()

    fun update(settings: VoiceAutoStopSettings): VoiceAutoStopSettings {
        val normalized = settings.normalized()
        preferences.edit()
            .putBoolean(KEY_ENABLED, normalized.enabled)
            .putLong(KEY_PAUSE_MILLIS, normalized.pauseDurationMillis)
            .putString(KEY_END_ACTION, normalized.endAction.name)
            .apply()
        mutableState.value = normalized
        return normalized
    }

    private fun read(): VoiceAutoStopSettings = VoiceAutoStopSettings(
        enabled = preferences.getBoolean(KEY_ENABLED, false),
        pauseDurationMillis = preferences.getLong(KEY_PAUSE_MILLIS, DEFAULT_PAUSE_MILLIS),
        endAction = preferences.getString(KEY_END_ACTION, null)?.let {
            runCatching { VoiceAutoStopEndAction.valueOf(it) }.getOrNull()
        } ?: VoiceAutoStopEndAction.STOP_RECORDING,
    ).normalized()

    companion object {
        private const val PREFERENCES_NAME = "voice-auto-stop-v1"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_PAUSE_MILLIS = "pauseDurationMillis"
        private const val KEY_END_ACTION = "endAction"
        @Volatile private var shared: VoiceAutoStopSettingsStore? = null

        fun get(context: Context): VoiceAutoStopSettingsStore = shared ?: synchronized(this) {
            shared ?: VoiceAutoStopSettingsStore(context).also { shared = it }
        }
    }
}

internal enum class VoicePauseEvent { NONE, END_OF_SPEECH }

/** Conservative energy fallback. It requires real speech before silence can end a recording. */
internal class VoicePauseDetector(
    private val pauseDurationMillis: Long,
    private val speechThreshold: Float = 0.018f,
    private val minimumSpeechMillis: Long = 250L,
) {
    private var speechMillis = 0L
    private var silenceMillis = 0L

    fun accept(level: Float, frameDurationMillis: Long): VoicePauseEvent {
        val duration = frameDurationMillis.coerceIn(0L, 1_000L)
        if (level >= speechThreshold) {
            speechMillis += duration
            silenceMillis = 0
            return VoicePauseEvent.NONE
        }
        if (speechMillis < minimumSpeechMillis) return VoicePauseEvent.NONE
        silenceMillis += duration
        return if (silenceMillis >= pauseDurationMillis) VoicePauseEvent.END_OF_SPEECH else VoicePauseEvent.NONE
    }

    fun reset() {
        speechMillis = 0
        silenceMillis = 0
    }
}

internal object RecordingSegmentStore {
    private const val FILE_NAME = "segments.properties"
    private const val MAX_BOUNDARIES = 10_000

    fun appendBoundary(recordingDirectory: File, nextChunkIndex: Int): Boolean {
        if (nextChunkIndex !in 1..999_999) return false
        val updated = (boundaries(recordingDirectory) + nextChunkIndex).distinct().sorted().take(MAX_BOUNDARIES)
        val atomic = AtomicFile(File(recordingDirectory, FILE_NAME))
        val output = runCatching { atomic.startWrite() }.getOrNull() ?: return false
        return try {
            val value = "version=1\nboundaries=${updated.joinToString(",")}\n"
            output.write(value.toByteArray(StandardCharsets.UTF_8))
            output.flush()
            output.fd.sync()
            atomic.finishWrite(output)
            true
        } catch (_: Throwable) {
            atomic.failWrite(output)
            false
        }
    }

    fun boundaries(recordingDirectory: File): Set<Int> = runCatching {
        val file = File(recordingDirectory, FILE_NAME)
        if (!file.isFile || file.length() !in 1..128_000L) return emptySet()
        val values = file.readLines().associate { line ->
            val split = line.indexOf('=')
            require(split > 0)
            line.substring(0, split) to line.substring(split + 1)
        }
        require(values["version"] == "1")
        values["boundaries"].orEmpty().split(',').filter(String::isNotBlank)
            .map { it.toInt() }
            .filter { it in 1..999_999 }
            .distinct()
            .take(MAX_BOUNDARIES)
            .toSet()
    }.getOrDefault(emptySet())
}

internal object RecordingAutoStopSnapshot {
    private const val FILE_NAME = "auto-stop.properties"

    fun write(recordingDirectory: File, settings: VoiceAutoStopSettings): Boolean {
        val normalized = settings.normalized()
        val atomic = AtomicFile(File(recordingDirectory, FILE_NAME))
        val output = runCatching { atomic.startWrite() }.getOrNull() ?: return false
        return try {
            val value = buildString {
                append("version=1\n")
                append("enabled=").append(normalized.enabled).append('\n')
                append("pauseDurationMillis=").append(normalized.pauseDurationMillis).append('\n')
                append("endAction=").append(normalized.endAction.name).append('\n')
            }
            output.write(value.toByteArray(StandardCharsets.UTF_8))
            output.flush()
            output.fd.sync()
            atomic.finishWrite(output)
            true
        } catch (_: Throwable) {
            atomic.failWrite(output)
            false
        }
    }

    fun read(recordingDirectory: File): VoiceAutoStopSettings? = runCatching {
        val values = File(recordingDirectory, FILE_NAME).readLines().associate { line ->
            val split = line.indexOf('=')
            require(split > 0)
            line.substring(0, split) to line.substring(split + 1)
        }
        require(values["version"] == "1")
        VoiceAutoStopSettings(
            enabled = values["enabled"]?.toBooleanStrictOrNull() ?: false,
            pauseDurationMillis = requireNotNull(values["pauseDurationMillis"]).toLong(),
            endAction = VoiceAutoStopEndAction.valueOf(requireNotNull(values["endAction"])),
        ).normalized()
    }.getOrNull()
}

internal const val MIN_PAUSE_MILLIS = 500L
internal const val DEFAULT_PAUSE_MILLIS = 750L
internal const val MAX_PAUSE_MILLIS = 2_000L
internal const val CONTINUOUS_LISTENING_LIMIT_MILLIS = 10L * 60 * 1_000
