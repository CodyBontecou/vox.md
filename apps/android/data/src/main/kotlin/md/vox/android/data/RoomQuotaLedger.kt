package md.vox.android.data

import md.vox.android.capturedomain.*
import java.util.UUID

sealed interface QuotaReservationResult {
    data class Reserved(val token: String) : QuotaReservationResult
    data class Existing(val token: String) : QuotaReservationResult
    data object AlreadyCommitted : QuotaReservationResult
    data object LimitReached : QuotaReservationResult
    data object InvalidInput : QuotaReservationResult
}

internal data class TombstoneDraft(
    val requestID: String, val installationID: String, val completedAtEpochMillis: Long,
    val destinationID: String, val receiptID: String, val packageVersion: Int, val journalVersion: Int,
    val requestContractVersion: Int, val finalJournalRevision: Int, val coreVersion: String,
    val rendererVersion: String, val profileID: String, val profileVersion: Int,
)

/** Terminal proof reconstructed from a verified completed package during crash recovery. */
internal data class VerifiedTerminalDraft(
    val requestID: String,
    val completedAtEpochMillis: Long,
    val destinationID: String,
    val receiptID: String,
    val packageVersion: Int,
    val journalVersion: Int,
    val requestContractVersion: Int,
    val finalJournalRevision: Int,
    val coreVersion: String,
    val rendererVersion: String,
    val profileID: String,
    val profileVersion: Int,
)

internal enum class TerminalQuotaResult { COMMITTED, IDENTICAL, CONFLICT, RESERVATION_LOST, INVALID }

class RoomQuotaLedger(private val database: CaptureDatabase) {
    private val dao get() = database.captureCoordinationDao()

    fun initializeInstallation(candidateID: String, nowEpochMillis: Long): String = transaction {
        require(LOWER_UUID.matches(candidateID) && nowEpochMillis >= 0) { "invalidInstallation" }
        val current = dao.readInstallation()
        if (current != null) return@transaction current.installationID
        dao.insertInstallation(InstallationIdentityEntity(1, candidateID, nowEpochMillis))
        checkNotNull(dao.readInstallation()).installationID
    }

    fun reserve(
        requestID: String,
        candidateToken: String,
        nowEpochMillis: Long,
        chargeFreeQuota: Boolean = true,
    ): QuotaReservationResult = transaction {
        if (!LOWER_UUID.matches(requestID) || !LOWER_UUID.matches(candidateToken) || nowEpochMillis < 0) return@transaction QuotaReservationResult.InvalidInput
        val installation = dao.readInstallation() ?: return@transaction QuotaReservationResult.InvalidInput
        val existing = dao.readReservation(requestID)
        val tombstones = dao.allTombstones()
        val reservations = dao.allReservations()
        val plan = if (chargeFreeQuota) {
            CaptureQuotaPlanner.reserve(
                requestID,
                QuotaSnapshot(
                    dao.committedUnits(),
                    reservations.filter { it.quotaUnits == 1 }.map { it.requestID }.toSet(),
                    tombstones.map { it.requestID }.toSet(),
                ),
            )
        } else when {
            requestID in tombstones.map { it.requestID }.toSet() -> QuotaPlan.AlreadyCommitted
            existing != null -> QuotaPlan.ExistingReservation
            else -> QuotaPlan.Reserve
        }
        when (plan) {
            QuotaPlan.AlreadyCommitted -> QuotaReservationResult.AlreadyCommitted
            QuotaPlan.ExistingReservation -> QuotaReservationResult.Existing(checkNotNull(existing).reservationToken)
            QuotaPlan.LimitReached -> QuotaReservationResult.LimitReached
            QuotaPlan.InvalidInput -> QuotaReservationResult.InvalidInput
            QuotaPlan.Reserve -> {
                val row = QuotaReservationEntity(
                    requestID,
                    candidateToken,
                    installation.installationID,
                    nowEpochMillis,
                    nowEpochMillis,
                    if (chargeFreeQuota) 1 else 0,
                )
                if (dao.insertReservation(row) != -1L) QuotaReservationResult.Reserved(candidateToken)
                else QuotaReservationResult.Existing(checkNotNull(dao.readReservation(requestID)).reservationToken)
            }
        }
    }

    /** Classification only: missing/corrupt and possibly committed frontiers are never auto-released. */
    fun classifyOrphanReservations(authoritativeSnapshots: Map<String, JournalSnapshot?>): Map<String, OrphanReservationDisposition> =
        dao.allReservations().associate { reservation ->
            reservation.requestID to if (authoritativeSnapshots.containsKey(reservation.requestID)) {
                OrphanReservationPlanner.classify(authoritativeSnapshots[reservation.requestID])
            } else OrphanReservationDisposition.CORRUPT_OR_MISSING
        }

    fun release(requestID: String, reservationToken: String): Boolean {
        if (!LOWER_UUID.matches(requestID) || !LOWER_UUID.matches(reservationToken)) return false
        val existing = dao.readReservation(requestID) ?: return true
        if (existing.reservationToken != reservationToken) return false
        return dao.releaseReservation(requestID, reservationToken) == 1
    }

    /** No production call site exists; future verified-receipt orchestration must be separately governed. */
    internal fun commitTerminal(reservationToken: String, draft: TombstoneDraft): TerminalQuotaResult = transaction {
        if (!validDraft(reservationToken, draft)) return@transaction TerminalQuotaResult.INVALID
        val existing = dao.readTombstone(draft.requestID)
        if (existing != null) {
            val proposed = draft.entity(existing.quotaUnits)
            return@transaction if (existing.sameAs(proposed)) TerminalQuotaResult.IDENTICAL else TerminalQuotaResult.CONFLICT
        }
        val reservation = dao.readReservation(draft.requestID)
        val proposed = draft.entity(reservation?.quotaUnits ?: return@transaction TerminalQuotaResult.RESERVATION_LOST)
        if (reservation.reservationToken != reservationToken || reservation.installationID != draft.installationID) return@transaction TerminalQuotaResult.RESERVATION_LOST
        if (dao.insertTombstone(proposed) == -1L) return@transaction TerminalQuotaResult.CONFLICT
        check(dao.releaseReservation(draft.requestID, reservationToken) == 1) { "terminalReservationDelete" }
        TerminalQuotaResult.COMMITTED
    }

    /**
     * Finishes accounting after the provider receipt and COMPLETED journal are durable.
     * The reservation identity is read inside the transaction so a process restart does
     * not need to retain an in-memory token. Existing terminal proof is accepted only
     * when every stable receipt/package field still matches.
     */
    internal fun commitVerifiedTerminal(draft: VerifiedTerminalDraft): TerminalQuotaResult = transaction {
        if (!validVerifiedDraft(draft)) return@transaction TerminalQuotaResult.INVALID
        val existing = dao.readTombstone(draft.requestID)
        if (existing != null) {
            return@transaction if (existing.matches(draft)) TerminalQuotaResult.IDENTICAL else TerminalQuotaResult.CONFLICT
        }
        val reservation = dao.readReservation(draft.requestID)
            ?: return@transaction TerminalQuotaResult.RESERVATION_LOST
        val proposed = draft.entity(reservation.installationID, reservation.quotaUnits)
        if (dao.insertTombstone(proposed) == -1L) return@transaction TerminalQuotaResult.CONFLICT
        check(dao.releaseReservation(draft.requestID, reservation.reservationToken) == 1) { "terminalReservationDelete" }
        TerminalQuotaResult.COMMITTED
    }

    private fun validDraft(token: String, d: TombstoneDraft) = LOWER_UUID.matches(token) && listOf(d.requestID, d.installationID, d.destinationID, d.receiptID).all(LOWER_UUID::matches) && d.completedAtEpochMillis >= 0 && d.packageVersion == 1 && d.journalVersion == 1 && d.requestContractVersion == 1 && d.finalJournalRevision in 1..1023 && d.coreVersion == "0.1.0-alpha.1" && d.rendererVersion == "swift-legacy-m0" && d.profileID == "apple-parity-v1" && d.profileVersion == 1
    private fun validVerifiedDraft(d: VerifiedTerminalDraft) = listOf(d.requestID, d.destinationID, d.receiptID).all(LOWER_UUID::matches) && d.completedAtEpochMillis >= 0 && d.packageVersion == 1 && d.journalVersion == 1 && d.requestContractVersion == 1 && d.finalJournalRevision in 1..1023 && d.coreVersion == "0.1.0-alpha.1" && d.rendererVersion == "swift-legacy-m0" && d.profileID == "apple-parity-v1" && d.profileVersion == 1
    private fun TombstoneDraft.entity(quotaUnits: Int) = CaptureTombstoneEntity(requestID, installationID, "COMPLETED", completedAtEpochMillis, destinationID, receiptID, packageVersion, journalVersion, requestContractVersion, finalJournalRevision, coreVersion, rendererVersion, profileID, profileVersion, quotaUnits)
    private fun VerifiedTerminalDraft.entity(installationID: String, quotaUnits: Int) = CaptureTombstoneEntity(requestID, installationID, "COMPLETED", completedAtEpochMillis, destinationID, receiptID, packageVersion, journalVersion, requestContractVersion, finalJournalRevision, coreVersion, rendererVersion, profileID, profileVersion, quotaUnits)
    private fun CaptureTombstoneEntity.matches(d: VerifiedTerminalDraft) = requestID==d.requestID && state=="COMPLETED" && destinationID==d.destinationID && receiptID==d.receiptID && packageVersion==d.packageVersion && journalVersion==d.journalVersion && requestContractVersion==d.requestContractVersion && finalJournalRevision==d.finalJournalRevision && coreVersion==d.coreVersion && rendererVersion==d.rendererVersion && profileID==d.profileID && profileVersion==d.profileVersion
    private fun CaptureTombstoneEntity.sameAs(o: CaptureTombstoneEntity) = requestID==o.requestID && installationID==o.installationID && state==o.state && completedAtEpochMillis==o.completedAtEpochMillis && destinationID==o.destinationID && receiptID==o.receiptID && packageVersion==o.packageVersion && journalVersion==o.journalVersion && requestContractVersion==o.requestContractVersion && finalJournalRevision==o.finalJournalRevision && coreVersion==o.coreVersion && rendererVersion==o.rendererVersion && profileID==o.profileID && profileVersion==o.profileVersion && quotaUnits==o.quotaUnits
    private fun <T> transaction(block: () -> T): T { var value: T? = null; database.runInTransaction { value = block() }; @Suppress("UNCHECKED_CAST") return value as T }
    private companion object { val LOWER_UUID = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$") }
}
