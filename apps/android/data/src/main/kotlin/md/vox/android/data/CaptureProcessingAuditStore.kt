package md.vox.android.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureTextProcessingOutcome
import md.vox.android.capturedomain.CaptureTextProcessingResult
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID

internal data class CaptureProcessingAudit(
    val requestID: String,
    val createdAtEpochMillis: Long,
    val presetID: String,
    val presetRevision: Int,
    val originRecordingID: String?,
    val originalText: String,
    val processedText: String,
    val mode: CaptureProcessingMode,
    val outcome: CaptureTextProcessingOutcome,
    val notice: String?,
)

/** Stores private, lossless pre-processing text separately from the canonical export request. */
internal class CaptureProcessingAuditStore(private val rootDirectory: File) {
    fun save(
        requestID: String,
        createdAtEpochMillis: Long,
        presetID: String,
        presetRevision: Int,
        originRecordingID: String?,
        result: CaptureTextProcessingResult,
    ): Boolean = runCatching {
        require(REQUEST_ID.matches(requestID))
        require(originRecordingID == null || REQUEST_ID.matches(originRecordingID))
        require(result.originalText.length <= MAX_TEXT_CHARACTERS)
        require(result.processedText.length <= MAX_TEXT_CHARACTERS)
        require(rootDirectory.mkdirs() || rootDirectory.isDirectory)
        val bytes = buildJsonObject {
            put("version", VERSION)
            put("requestID", requestID)
            put("createdAtEpochMillis", createdAtEpochMillis)
            put("presetID", presetID.take(MAX_PRESET_ID_CHARACTERS))
            put("presetRevision", presetRevision)
            originRecordingID?.let { put("originRecordingID", it) }
            put("originalText", result.originalText)
            put("processedText", result.processedText)
            put("mode", result.mode.name)
            put("outcome", result.outcome.name)
            result.notice?.take(MAX_NOTICE_CHARACTERS)?.let { put("notice", it) }
        }.toString().toByteArray(StandardCharsets.UTF_8)
        require(bytes.size <= MAX_FILE_BYTES)
        val destination = fileFor(requestID)
        val temporary = File(rootDirectory, ".$requestID-${UUID.randomUUID()}.tmp")
        try {
            FileOutputStream(temporary).use { output ->
                output.write(bytes)
                output.flush()
                output.fd.sync()
            }
            try {
                Files.move(
                    temporary.toPath(),
                    destination.toPath(),
                    StandardCopyOption.ATOMIC_MOVE,
                    StandardCopyOption.REPLACE_EXISTING,
                )
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(temporary.toPath(), destination.toPath(), StandardCopyOption.REPLACE_EXISTING)
            }
        } finally {
            temporary.delete()
        }
        true
    }.getOrDefault(false)

    fun load(requestID: String): CaptureProcessingAudit? = runCatching {
        if (!REQUEST_ID.matches(requestID)) return null
        val file = fileFor(requestID)
        if (!file.isFile || file.length() !in 1..MAX_FILE_BYTES.toLong()) return null
        val root = Json.parseToJsonElement(file.readText(StandardCharsets.UTF_8)).jsonObject
        if (root.getValue("version").jsonPrimitive.content.toInt() != VERSION) return null
        if (root.getValue("requestID").jsonPrimitive.content != requestID) return null
        CaptureProcessingAudit(
            requestID = requestID,
            createdAtEpochMillis = root.getValue("createdAtEpochMillis").jsonPrimitive.content.toLong(),
            presetID = root.getValue("presetID").jsonPrimitive.content,
            presetRevision = root.getValue("presetRevision").jsonPrimitive.content.toInt(),
            originRecordingID = root["originRecordingID"]?.jsonPrimitive?.content,
            originalText = root.getValue("originalText").jsonPrimitive.content,
            processedText = root.getValue("processedText").jsonPrimitive.content,
            mode = CaptureProcessingMode.valueOf(root.getValue("mode").jsonPrimitive.content),
            outcome = CaptureTextProcessingOutcome.valueOf(root.getValue("outcome").jsonPrimitive.content),
            notice = root["notice"]?.jsonPrimitive?.content,
        ).also { audit ->
            require(audit.originalText.length <= MAX_TEXT_CHARACTERS)
            require(audit.processedText.length <= MAX_TEXT_CHARACTERS)
            require(audit.presetID.length <= MAX_PRESET_ID_CHARACTERS)
            require(audit.notice == null || audit.notice.length <= MAX_NOTICE_CHARACTERS)
        }
    }.getOrNull()

    fun delete(requestID: String): Boolean = REQUEST_ID.matches(requestID) && (!fileFor(requestID).exists() || fileFor(requestID).delete())

    private fun fileFor(requestID: String) = File(rootDirectory, "$requestID.json")

    companion object {
        private const val VERSION = 1
        private const val MAX_TEXT_CHARACTERS = 65_536
        private const val MAX_NOTICE_CHARACTERS = 512
        private const val MAX_PRESET_ID_CHARACTERS = 128
        private const val MAX_FILE_BYTES = 300_000
        private val REQUEST_ID = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    }
}
