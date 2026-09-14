package md.vox.android.data

internal data class CaptureCompletion(
    val requestID: String,
    val completedAtEpochMillis: Long,
)

/** Durable, content-free history of completed inbox requests. */
internal class RoomCaptureCompletionLedger(private val database: CaptureDatabase) {
    private val dao get() = database.captureActivityDao()

    fun record(requestID: String, completedAtEpochMillis: Long): Boolean {
        if (!UUID_PATTERN.matches(requestID) || completedAtEpochMillis < 0) return false
        val inserted = dao.insertCompletion(CaptureCompletionEntity(requestID, completedAtEpochMillis))
        if (inserted != -1L) return true
        return dao.readCompletion(requestID)?.completedAtEpochMillis == completedAtEpochMillis
    }

    fun read(requestID: String): CaptureCompletion? =
        requestID.takeIf(UUID_PATTERN::matches)
            ?.let(dao::readCompletion)
            ?.let { CaptureCompletion(it.requestID, it.completedAtEpochMillis) }

    fun all(): List<CaptureCompletion> = dao.allCompletions().map {
        CaptureCompletion(it.requestID, it.completedAtEpochMillis)
    }

    fun delete(requestID: String): Boolean =
        UUID_PATTERN.matches(requestID) && dao.deleteCompletion(requestID) == 1
}
