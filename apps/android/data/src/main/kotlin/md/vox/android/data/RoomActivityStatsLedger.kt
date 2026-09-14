package md.vox.android.data

import md.vox.android.capturedomain.ActivityDay
import md.vox.android.capturedomain.ActivityStats
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

/** Idempotent, content-free activity ledger retained independently from History packages. */
internal class RoomActivityStatsLedger(private val database: CaptureDatabase) {
    private val dao get() = database.captureActivityDao()

    fun recordCapture(requestID: String, completedAtEpochMillis: Long, source: String, attachmentCount: Int): Boolean {
        if (!UUID_PATTERN.matches(requestID) || completedAtEpochMillis < 0 || source !in CAPTURE_SOURCES || attachmentCount !in 0..128) return false
        val inserted = dao.insert(CaptureActivityEntity(requestID, completedAtEpochMillis, source, attachmentCount))
        return inserted != -1L || dao.all().any { it.requestID == requestID }
    }

    fun recordRecording(sessionID: String, completedAtEpochMillis: Long, durationMillis: Long): Boolean {
        if (!UUID_PATTERN.matches(sessionID) || completedAtEpochMillis < 0 || durationMillis !in 0..MAX_RECORDING_DURATION_MILLIS) return false
        val inserted = dao.insertRecording(RecordingActivityEntity(sessionID, completedAtEpochMillis, durationMillis))
        return inserted != -1L || dao.allRecordings().any { it.sessionID == sessionID }
    }

    fun snapshot(nowEpochMillis: Long, zone: ZoneId = ZoneId.systemDefault()): ActivityStats {
        val rows = dao.all()
        val recordings = dao.allRecordings()
        val today = Instant.ofEpochMilli(nowEpochMillis.coerceAtLeast(0)).atZone(zone).toLocalDate()
        val counts = rows.groupingBy { epochDay(it.completedAtEpochMillis, zone) }.eachCount()
        val recordingCounts = recordings.groupingBy { epochDay(it.completedAtEpochMillis, zone) }.eachCount()
        val days = (6 downTo 0).map { offset ->
            val day = today.minusDays(offset.toLong())
            ActivityDay(day.toEpochDay(), counts[day.toEpochDay()] ?: 0, recordingCounts[day.toEpochDay()] ?: 0)
        }
        val sources = rows.groupingBy(CaptureActivityEntity::source).eachCount().toSortedMap()
        return ActivityStats(
            recordingCount = recordings.size,
            captureCount = rows.size,
            recordedDurationMillis = recordings.sumOf(RecordingActivityEntity::durationMillis),
            attachmentCount = rows.sumOf(CaptureActivityEntity::attachmentCount),
            lastSevenDays = days,
            captureSources = sources,
        )
    }

    private fun epochDay(epochMillis: Long, zone: ZoneId): Long =
        Instant.ofEpochMilli(epochMillis).atZone(zone).toLocalDate().toEpochDay()

    private companion object {
        val CAPTURE_SOURCES = setOf("app", "share", "keyboard", "widget", "shortcut", "watch", "wear")
        const val MAX_RECORDING_DURATION_MILLIS = 24L * 60 * 60 * 1_000
    }
}
