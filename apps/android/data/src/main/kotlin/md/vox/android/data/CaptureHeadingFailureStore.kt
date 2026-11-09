package md.vox.android.data

import kotlinx.serialization.json.*
import md.vox.android.capturedomain.*
import java.io.File
import java.util.UUID

/** Written only after the authoritative materializer returns HeadingNotFound, before USER_ACTION_REQUIRED. */
internal class CaptureHeadingFailureStore(base: File, private val ops: DurableFileOps = AndroidDurableFileOps()) {
    private val directory = File(base, "vox-heading-failures")
    fun save(requestID: String, requestBytes: ByteArray, preparingRevision: Int) {
        require(UUID_PATTERN.matches(requestID) && preparingRevision in 1..1022)
        val request = CapturePackageCodec.parseCanonical(requestBytes)
        val route = request.getValue("preset").jsonObject.getValue("routePolicy").jsonObject
        require(route["placement"]?.jsonPrimitive?.content == "beneathHeading" && route["missingHeadingBehavior"]?.jsonPrimitive?.content == "fail")
        val title = route.text("headingTitle"); val level = route.getValue("headingLevel").jsonPrimitive.int
        require(title.isNotBlank() && title.length <= 256 && level in 1..6)
        val bytes = CapturePackageCodec.canonical(buildJsonObject {
            put("version", 1); put("requestID", requestID); put("requestSHA256", CapturePackageCodec.sha256(requestBytes))
            put("preparingRevision", preparingRevision); put("title", title); put("level", level)
        })
        ops.ensureDirectory(directory); ops.syncDirectory(directory.parentFile!!)
        val target = File(directory, "$requestID.json"); val temp = File(directory, ".tmp-${UUID.randomUUID()}")
        ops.writeNewFileDurably(temp, bytes) {}
        check(ops.readBounded(temp, CONTROL_LIMIT_BYTES).contentEquals(bytes))
        if (ops.exists(target)) ops.replaceFileAtomically(temp, target) else ops.moveFileNoReplaceAtomically(temp, target)
        ops.syncDirectory(directory)
    }
    fun load(requestID: String, requestBytes: ByteArray, snapshot: JournalSnapshot): CaptureMissingHeading? = runCatching {
        if (!UUID_PATTERN.matches(requestID) || snapshot.state != CaptureState.NEEDS_USER_ACTION ||
            snapshot.events.last().code != JournalCode.USER_ACTION_REQUIRED) return null
        check(ops.isDirectoryNoFollow(directory) && !ops.isSymlink(directory))
        val root = CapturePackageCodec.parseCanonical(ops.readBounded(File(directory, "$requestID.json"), CONTROL_LIMIT_BYTES))
        check(root.getValue("version").jsonPrimitive.int == 1 && root.text("requestID") == requestID &&
            root.text("requestSHA256") == CapturePackageCodec.sha256(requestBytes) && root.getValue("preparingRevision").jsonPrimitive.int + 1 == snapshot.revision)
        val route = CapturePackageCodec.parseCanonical(requestBytes).getValue("preset").jsonObject.getValue("routePolicy").jsonObject
        val title = root.text("title"); val level = root.getValue("level").jsonPrimitive.int
        check(route.text("placement") == "beneathHeading" && route.text("missingHeadingBehavior") == "fail" &&
            title == route.text("headingTitle") && level == route.getValue("headingLevel").jsonPrimitive.int && title.isNotBlank() && level in 1..6)
        CaptureMissingHeading(title, level)
    }.getOrNull()
}
