package md.vox.android.data

import kotlinx.serialization.json.*
import md.vox.android.capturedomain.*

/** Retargets immutable captured content, never reprocesses text or recollects location. */
internal fun recoveryRequest(
    sourceBytes: ByteArray,
    replacementID: String,
    destinationID: String,
    preset: CapturePreset? = null,
    heading: CaptureRecoveryTarget.Heading? = null,
): ByteArray {
    require(UUID_PATTERN.matches(replacementID) && UUID_PATTERN.matches(destinationID))
    val source = CapturePackageCodec.parseCanonical(sourceBytes)
    require(source.text("requestID") != replacementID)
    val frozen = source.getValue("preset").jsonObject
    val originalRoute = frozen.getValue("routePolicy").jsonObject
    require((preset == null) != (heading == null))
    val route = if (preset != null) {
        JsonObject(captureRoutePolicyFor(preset).toMutableMap().apply {
            // The source text may already contain attachment links and formatting choices.
            for (key in listOf("attachmentFolder", "entryPrefix", "entrySuffix")) originalRoute[key]?.let { put(key, it) }
        })
    } else {
        require(originalRoute.text("placement") == "beneathHeading")
        require(heading!!.title.isNotBlank() && heading.title.length <= 256 && heading.level in 1..6)
        JsonObject(originalRoute.toMutableMap().apply {
            put("headingTitle", JsonPrimitive(heading.title)); put("headingLevel", JsonPrimitive(heading.level))
            put("missingHeadingBehavior", JsonPrimitive(if (heading.createIfMissing) "create" else "fail"))
        })
    }
    val policy = JsonObject(frozen.getValue("destinationPolicy").jsonObject.toMutableMap().apply { put("capabilityReference", JsonPrimitive(destinationID)) })
    var snapshot = JsonObject(frozen.toMutableMap().apply {
        put("routePolicy", route); put("destinationPolicy", policy)
        if (preset != null) { put("id", JsonPrimitive(preset.id)); put("revision", JsonPrimitive(preset.revision)) }
        put("snapshotHash", JsonPrimitive("0".repeat(64)))
    })
    snapshot = JsonObject(snapshot.toMutableMap().apply { put("snapshotHash", JsonPrimitive(CapturePackageCodec.sha256(CapturePackageCodec.canonical(snapshot)))) })
    val result = CapturePackageCodec.canonical(JsonObject(source.toMutableMap().apply {
        put("requestID", JsonPrimitive(replacementID)); put("preset", snapshot)
        if (preset != null) put("operation", JsonPrimitive(captureOperationFor(preset)))
    }))
    CapturePackageCodec.admitRequest(result)
    return result
}

internal fun recoveryChoice(target: CaptureRecoveryTarget): String = when (target) {
    is CaptureRecoveryTarget.Inbox -> "inbox:${target.destinationID}"
    is CaptureRecoveryTarget.Route -> "route:${target.presetID}:${target.revision}:${target.destinationID}"
    is CaptureRecoveryTarget.Heading -> "heading:${target.level}:${target.createIfMissing}:${target.title}"
}
