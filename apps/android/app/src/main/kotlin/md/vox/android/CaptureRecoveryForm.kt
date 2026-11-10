package md.vox.android

import md.vox.android.capturedomain.*

/** Small saved-state representation of the exact decision reviewed. Never stores capture bodies or assets. */
internal data class CaptureRecoveryForm(
    val intentID: String,
    val stage: String = "closed",
    val sourceID: String = "",
    val sourceHash: String = "",
    val sourceRevision: Int = -1,
    val sourceDestination: String = "",
    val kind: String = "",
    val routeID: String = "",
    val routeRevision: Int = -1,
    val destinationID: String = "",
    val title: String = "",
    val level: Int = 2,
    val create: Boolean = false,
    val destinationName: String = "",
    val targetName: String = "",
) {
    fun review(context: CaptureRecoveryContext, target: CaptureRecoveryTarget): CaptureRecoveryForm = copy(
        stage = "confirm", sourceID = context.requestID, sourceHash = context.requestSHA256, sourceRevision = context.revision,
        sourceDestination = context.sourceDestinationID.orEmpty(), kind = when (target) {
            is CaptureRecoveryTarget.Inbox -> "inbox"
            is CaptureRecoveryTarget.Route -> "route"
            is CaptureRecoveryTarget.Heading -> "heading"
        }, routeID = (target as? CaptureRecoveryTarget.Route)?.presetID.orEmpty(),
        routeRevision = (target as? CaptureRecoveryTarget.Route)?.revision ?: -1,
        destinationID = when (target) {
            is CaptureRecoveryTarget.Inbox -> target.destinationID
            is CaptureRecoveryTarget.Route -> target.destinationID
            is CaptureRecoveryTarget.Heading -> context.sourceDestinationID.orEmpty()
        }, title = (target as? CaptureRecoveryTarget.Heading)?.title.orEmpty(),
        level = (target as? CaptureRecoveryTarget.Heading)?.level ?: 2,
        create = (target as? CaptureRecoveryTarget.Heading)?.createIfMissing ?: false,
        destinationName = context.sourceDestinationName.orEmpty(),
    )
    fun commandOrNull(): CaptureRecoveryCommand? {
        if (stage != "confirm" || destinationName.isBlank() || !UUID.matches(intentID) || !UUID.matches(sourceID) || !UUID.matches(destinationID) ||
            !Regex("[0-9a-f]{64}").matches(sourceHash) || sourceRevision !in 0..1022) return null
        val target = when (kind) {
            "inbox" -> CaptureRecoveryTarget.Inbox(destinationID)
            "route" -> if (UUID.matches(routeID) && routeRevision >= 1) CaptureRecoveryTarget.Route(routeID, routeRevision, destinationID) else return null
            "heading" -> if (title.isNotBlank() && title.length <= 256 && level in 1..6) CaptureRecoveryTarget.Heading(title, level, create) else return null
            else -> return null
        }
        return CaptureRecoveryCommand(intentID, CaptureRecoveryContext(sourceID, sourceHash, sourceRevision, sourceDestination.takeIf(String::isNotEmpty), true), target)
    }
    fun cancel() = copy(stage = "closed")
    fun encode(): List<String> = listOf(intentID, stage, sourceID, sourceHash, sourceRevision.toString(), sourceDestination, kind,
        routeID, routeRevision.toString(), destinationID, title, level.toString(), create.toString(), destinationName, targetName)
    companion object {
        private val UUID = Regex("[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}")
        fun decode(values: List<String>): CaptureRecoveryForm? = runCatching {
            require(values.size == 15 && values.all { it.length <= 512 } && UUID.matches(values[0]))
            CaptureRecoveryForm(values[0], values[1], values[2], values[3], values[4].toInt(), values[5], values[6], values[7],
                values[8].toInt(), values[9], values[10], values[11].toInt(), values[12].toBooleanStrict(), values[13], values[14])
        }.getOrNull()
    }
}
