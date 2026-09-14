package md.vox.android

import android.content.Context
import java.io.File
import java.time.Instant

/**
 * A small operational log that deliberately cannot accept capture content.
 *
 * Callers select a closed event and may attach only bounded counters or closed
 * enum-like values. The log lives in no-backup storage and rotates before it
 * can grow beyond [MAX_BYTES].
 */
internal object PrivacySafeDebugLog {
    private const val DIRECTORY_NAME = "diagnostics"
    private const val FILE_NAME = "operational.log"
    private const val MAX_BYTES = 256 * 1024L
    private const val RETAINED_BYTES = 128 * 1024
    private val lock = Any()

    enum class Event(val persistedName: String) {
        APP_STARTED("app.started"),
        EXTERNAL_CAPTURE_RECEIVED("capture.external_received"),
        RECORDING_PHASE_CHANGED("recording.phase_changed"),
        HISTORY_CLEARED("history.completed_cleared"),
        APP_LANGUAGE_CHANGED("settings.app_language_changed"),
        BILLING_RESTORE_CHECKED("billing.restore_checked"),
        DEBUG_LOG_CLEARED("debug.log_cleared"),
    }

    fun record(context: Context, event: Event, fields: Map<String, String> = emptyMap()) {
        val safeFields = fields.entries
            .sortedBy(Map.Entry<String, String>::key)
            .joinToString(separator = " ") { (key, value) ->
                "${sanitizeToken(key)}=${sanitizeToken(value)}"
            }
        val line = buildString {
            append(Instant.now())
            append(' ')
            append(event.persistedName)
            if (safeFields.isNotEmpty()) {
                append(' ')
                append(safeFields)
            }
            append('\n')
        }
        synchronized(lock) {
            val file = logFile(context)
            file.parentFile?.mkdirs()
            rotateIfNeeded(file, line.toByteArray().size)
            file.appendText(line, Charsets.UTF_8)
        }
    }

    fun read(context: Context): String = synchronized(lock) {
        val file = logFile(context)
        if (!file.isFile) "" else file.readText(Charsets.UTF_8)
    }

    fun clear(context: Context) = synchronized(lock) {
        val file = logFile(context)
        if (file.exists()) file.writeText("", Charsets.UTF_8)
    }

    private fun logFile(context: Context): File =
        File(File(context.noBackupFilesDir, DIRECTORY_NAME), FILE_NAME)

    private fun rotateIfNeeded(file: File, incomingBytes: Int) {
        if (!file.isFile || file.length() + incomingBytes <= MAX_BYTES) return
        val bytes = file.readBytes()
        val start = (bytes.size - RETAINED_BYTES).coerceAtLeast(0)
        var lineStart = start
        while (lineStart < bytes.size && bytes[lineStart] != '\n'.code.toByte()) lineStart += 1
        if (lineStart < bytes.size) lineStart += 1
        file.writeBytes(bytes.copyOfRange(lineStart, bytes.size))
    }

    private fun sanitizeToken(value: String): String = value
        .take(64)
        .map { character ->
            when {
                character.isLetterOrDigit() -> character
                character in "._-" -> character
                else -> '_'
            }
        }
        .joinToString(separator = "")
        .ifBlank { "unknown" }
}
