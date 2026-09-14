package md.vox.android.platformservices

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class TranscriptionUsageState(
    val usedMillis: Long,
    val limitMillis: Long = FREE_TRANSCRIPTION_LIMIT_MILLIS,
) {
    val remainingMillis: Long get() = (limitMillis - usedMillis).coerceAtLeast(0)
}

internal object TranscriptionQuotaPolicy {
    fun canReserve(
        committedMillis: Long,
        activeMillis: Long,
        requestedMillis: Long,
        unlimited: Boolean,
    ): Boolean {
        if (committedMillis < 0 || activeMillis < 0 || requestedMillis <= 0) return false
        if (unlimited) return true
        return committedMillis + activeMillis <= FREE_TRANSCRIPTION_LIMIT_MILLIS &&
            requestedMillis <= FREE_TRANSCRIPTION_LIMIT_MILLIS - committedMillis - activeMillis
    }
}

/** Content-free, process-local reservation layer backed by an idempotent local ledger. */
internal class TranscriptionQuotaLedger(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val committed = loadCommitted().toMutableMap()
    private val active = mutableMapOf<String, Long>()
    private val mutableUsage = MutableStateFlow(snapshot())
    val usage: StateFlow<TranscriptionUsageState> = mutableUsage.asStateFlow()

    @Synchronized
    fun reserve(sessionID: String, durationMillis: Long, unlimited: Boolean): Boolean {
        if (!UUID_PATTERN.matches(sessionID) || durationMillis <= 0) return false
        if (sessionID in committed || sessionID in active) return true
        val charge = if (unlimited) 0L else durationMillis
        if (!TranscriptionQuotaPolicy.canReserve(committed.values.sum(), active.values.sum(), durationMillis, unlimited)) {
            return false
        }
        active[sessionID] = charge
        return true
    }

    @Synchronized
    fun commit(sessionID: String): Boolean {
        if (sessionID in committed) {
            active.remove(sessionID)
            return true
        }
        val charge = active.remove(sessionID) ?: return false
        committed[sessionID] = charge
        val saved = preferences.edit().putStringSet(KEY_ENTRIES, encode(committed)).commit()
        if (!saved) {
            committed.remove(sessionID)
            return false
        }
        mutableUsage.value = snapshot()
        return true
    }

    @Synchronized
    fun release(sessionID: String) {
        active.remove(sessionID)
    }

    /** Migrates successful transcripts produced before the quota ledger existed. */
    @Synchronized
    fun backfill(sessionID: String, durationMillis: Long) {
        if (!UUID_PATTERN.matches(sessionID) || durationMillis <= 0 || sessionID in committed) return
        committed[sessionID] = durationMillis
        if (!preferences.edit().putStringSet(KEY_ENTRIES, encode(committed)).commit()) {
            committed.remove(sessionID)
        }
        mutableUsage.value = snapshot()
    }

    private fun snapshot() = TranscriptionUsageState(committed.values.sum().coerceAtLeast(0))

    private fun loadCommitted(): Map<String, Long> = preferences.getStringSet(KEY_ENTRIES, emptySet()).orEmpty()
        .mapNotNull { entry ->
            val separator = entry.indexOf('=')
            if (separator <= 0) return@mapNotNull null
            val id = entry.substring(0, separator)
            val duration = entry.substring(separator + 1).toLongOrNull()
            if (!UUID_PATTERN.matches(id) || duration == null || duration < 0) null else id to duration
        }
        .toMap()

    private fun encode(values: Map<String, Long>): Set<String> = values.mapTo(mutableSetOf()) { (id, duration) -> "$id=$duration" }

    private companion object {
        const val PREFERENCES = "vox-transcription-quota-v1"
        const val KEY_ENTRIES = "completed-session-duration"
        val UUID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    }
}

const val FREE_TRANSCRIPTION_LIMIT_MILLIS = 15L * 60 * 1_000
