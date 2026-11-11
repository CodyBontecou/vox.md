package md.vox.android.data

import kotlinx.serialization.json.*
import md.vox.android.capturedomain.*
import java.io.File
import java.util.UUID

internal data class CaptureRecoveryIntent(
    val intentID: String,
    val sourceID: String,
    val sourceSHA256: String,
    val sourceRevision: Int,
    val sourceState: CaptureState,
    val confirmedAt: Long,
    val choice: String,
    val replacementBytes: ByteArray,
) {
    val replacementID: String get() = intentID
    fun retirementEvent() = JournalEvent(sourceRevision + 1, sourceState, CaptureState.DISCARDED, JournalCode.USER_DISCARDED, confirmedAt)
}

/** Immutable intent authority, separate from governed package layout. All mutations use the package root lock. */
internal class CaptureRecoveryIntentStore(
    base: File,
    private val ops: DurableFileOps = AndroidDurableFileOps(),
) {
    private val directory = File(base, "vox-capture-recoveries")
    fun exists(sourceID: String): Boolean {
        if (!UUID_PATTERN.matches(sourceID) || !ops.exists(directory)) return false
        check(ops.isDirectoryNoFollow(directory) && !ops.isSymlink(directory))
        return ops.exists(file(sourceID))
    }
    fun sourceIDs(): List<String> {
        if (!ops.exists(directory)) return emptyList()
        check(ops.isDirectoryNoFollow(directory) && !ops.isSymlink(directory))
        return ops.list(directory).filter { UUID_PATTERN.matches(it.nameWithoutExtension) && it.extension == "json" }.map { it.nameWithoutExtension }.also { check(it.size <= 4096) }
    }
    fun read(sourceID: String): CaptureRecoveryIntent? {
        require(UUID_PATTERN.matches(sourceID))
        if (!exists(sourceID)) return null
        check(ops.isDirectoryNoFollow(directory) && !ops.isSymlink(directory))
        val bytes = ops.readBounded(file(sourceID), MAX_BYTES)
        val root = CapturePackageCodec.parseCanonical(bytes)
        check(root.keys == setOf("version", "intentID", "sourceID", "sourceSHA256", "sourceRevision", "sourceState", "confirmedAt", "choice", "replacement", "replacementSHA256"))
        check(root.getValue("version").jsonPrimitive.int == 1)
        val replacement = CapturePackageCodec.canonical(root.getValue("replacement").jsonObject)
        val result = CaptureRecoveryIntent(root.text("intentID"), root.text("sourceID"), root.text("sourceSHA256"), root.getValue("sourceRevision").jsonPrimitive.int,
            CaptureState.valueOf(root.text("sourceState")), root.getValue("confirmedAt").jsonPrimitive.long, root.text("choice"), replacement)
        validate(result)
        check(result.sourceID == sourceID && root.text("replacementSHA256") == CapturePackageCodec.sha256(replacement))
        return result
    }
    fun persist(intent: CaptureRecoveryIntent) {
        validate(intent)
        ops.ensureDirectory(directory)
        ops.syncDirectory(directory.parentFile!!)
        val bytes = encode(intent)
        check(bytes.size <= MAX_BYTES)
        if (exists(intent.sourceID)) {
            check(ops.readBounded(file(intent.sourceID), MAX_BYTES).contentEquals(bytes)) { "recoveryIntentConflict" }
            ops.syncDirectory(directory)
            return
        }
        val temp = File(directory, ".tmp-${UUID.randomUUID()}")
        ops.writeNewFileDurably(temp, bytes) { ops.checkpoint("$it:recoveryIntent") }
        check(ops.readBounded(temp, MAX_BYTES).contentEquals(bytes))
        ops.checkpoint("beforeRecoveryIntentPromote")
        ops.moveFileNoReplaceAtomically(temp, file(intent.sourceID))
        ops.checkpoint("afterRecoveryIntentPromote")
        ops.syncDirectory(directory)
        ops.checkpoint("afterRecoveryIntentSync")
    }
    private fun encode(i: CaptureRecoveryIntent): ByteArray = CapturePackageCodec.canonical(buildJsonObject {
        put("version", 1); put("intentID", i.intentID); put("sourceID", i.sourceID); put("sourceSHA256", i.sourceSHA256)
        put("sourceRevision", i.sourceRevision); put("sourceState", i.sourceState.name); put("confirmedAt", i.confirmedAt); put("choice", i.choice)
        put("replacement", CapturePackageCodec.parseCanonical(i.replacementBytes)); put("replacementSHA256", CapturePackageCodec.sha256(i.replacementBytes))
    })
    private fun validate(i: CaptureRecoveryIntent) {
        require(UUID_PATTERN.matches(i.intentID) && UUID_PATTERN.matches(i.sourceID) && i.intentID != i.sourceID)
        require(Regex("[0-9a-f]{64}").matches(i.sourceSHA256) && i.sourceRevision in 0..1022 && i.confirmedAt >= 0 && i.choice.length in 1..512)
        val request = CapturePackageCodec.parseCanonical(i.replacementBytes)
        require(request.text("requestID") == i.intentID)
        CapturePackageCodec.decodeHistoricalRequest(i.replacementBytes)
    }
    private fun file(id: String) = File(directory, "$id.json")
    companion object { private const val MAX_BYTES = 1_048_576 }
}

internal fun JsonObject.text(key: String): String = getValue(key).jsonPrimitive.content
