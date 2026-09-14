package md.vox.android.capturedomain

enum class WearRemoteRecordingPhase(val wireValue: String, val terminal: Boolean = false) {
    RECEIVING("receiving"),
    INGESTED("ingested"),
    QUEUED("queued"),
    TRANSCRIBING("transcribing"),
    DELIVERING("delivering"),
    DELIVERED("delivered", terminal = true),
    FAILED("failed"),
    TRANSPORT_FAILED("transportFailed"),
    DISCARDED("discarded", terminal = true),
    ;

    companion object {
        fun fromWireValue(value: String): WearRemoteRecordingPhase? = entries.firstOrNull { it.wireValue == value }
    }
}

/** Versioned paths and bounded fields shared by the phone and Wear OS apps. */
object WearProtocol {
    const val VERSION = 1
    const val WATCH_RECORDING_PREFIX = "/vox/wear/v1/recordings/"
    const val PHONE_STATUS_PREFIX = "/vox/phone/v1/recordings/"
    const val PHONE_PRESETS_PATH = "/vox/phone/v1/presets"
    const val MANIFEST_SUFFIX = "/manifest"
    const val STATUS_SUFFIX = "/status"
    const val CHUNKS_SEGMENT = "/chunks/"

    const val KEY_PROTOCOL_VERSION = "protocolVersion"
    const val KEY_RECORDING_ID = "recordingID"
    const val KEY_CREATED_AT = "createdAtEpochMillis"
    const val KEY_DURATION = "durationMillis"
    const val KEY_CHUNK_COUNT = "chunkCount"
    const val KEY_CHUNK_INDEX = "chunkIndex"
    const val KEY_CHUNK_LENGTH = "chunkLength"
    const val KEY_SHA256 = "sha256"
    const val KEY_ASSET = "audio"
    const val KEY_REVISION = "revision"
    const val KEY_PHASE = "phase"
    const val KEY_FRONTIER = "frontier"
    const val KEY_MESSAGE = "message"
    const val KEY_PRESET_ID = "presetID"
    const val KEY_PRESET_NAME = "presetName"
    const val KEY_PRESET_SNAPSHOT = "presetSnapshot"
    const val KEY_ACTIVE_PRESET_ID = "activePresetID"
    const val KEY_PRESETS = "presets"

    const val PHASE_RECEIVING = "receiving"
    const val PHASE_INGESTED = "ingested"
    const val PHASE_QUEUED = "queued"
    const val PHASE_TRANSCRIBING = "transcribing"
    const val PHASE_DELIVERING = "delivering"
    const val PHASE_DELIVERED = "delivered"
    const val PHASE_FAILED = "failed"
    const val PHASE_TRANSPORT_FAILED = "transportFailed"
    const val PHASE_DISCARDED = "discarded"

    val recordingIDPattern = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    val checksumPattern = Regex("^[0-9a-f]{64}$")

    fun manifestPath(recordingID: String): String = "$WATCH_RECORDING_PREFIX$recordingID$MANIFEST_SUFFIX"
    fun chunkPath(recordingID: String, index: Int): String =
        "$WATCH_RECORDING_PREFIX$recordingID$CHUNKS_SEGMENT${index.toString().padStart(6, '0')}"
    fun statusPath(recordingID: String): String = "$PHONE_STATUS_PREFIX$recordingID$STATUS_SUFFIX"

    fun recordingIDFromWatchPath(path: String): String? {
        if (!path.startsWith(WATCH_RECORDING_PREFIX)) return null
        val remainder = path.removePrefix(WATCH_RECORDING_PREFIX)
        val recordingID = remainder.substringBefore('/')
        val suffix = remainder.removePrefix(recordingID)
        if (!recordingIDPattern.matches(recordingID)) return null
        if (suffix != MANIFEST_SUFFIX && !suffix.matches(Regex("^/chunks/[0-9]{6}$"))) return null
        return recordingID
    }

    fun chunkIndexFromWatchPath(path: String): Int? {
        val recordingID = recordingIDFromWatchPath(path) ?: return null
        val prefix = "$WATCH_RECORDING_PREFIX$recordingID$CHUNKS_SEGMENT"
        if (!path.startsWith(prefix)) return null
        return path.removePrefix(prefix).toIntOrNull()?.takeIf { it in 0..999_999 }
    }

    fun recordingIDFromPhoneStatusPath(path: String): String? {
        if (!path.startsWith(PHONE_STATUS_PREFIX) || !path.endsWith(STATUS_SUFFIX)) return null
        val recordingID = path.removePrefix(PHONE_STATUS_PREFIX).removeSuffix(STATUS_SUFFIX)
        return recordingID.takeIf(recordingIDPattern::matches)
    }

    fun nextRemoteRevision(current: Int, minimum: Int): Int = when {
        current < 0 || minimum < 0 -> throw IllegalArgumentException("remoteRevisionBounds")
        current == Int.MAX_VALUE -> Int.MAX_VALUE
        else -> maxOf(current + 1, minimum)
    }
}
