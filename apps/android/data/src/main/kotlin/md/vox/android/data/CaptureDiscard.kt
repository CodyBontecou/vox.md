package md.vox.android.data

import md.vox.android.capturedomain.*
import java.util.UUID

/** Never abandon a provider write whose absence has not been proved. */
internal fun canDiscardCapture(snapshot: JournalSnapshot, marker: CommitMarker?): Boolean =
    marker?.state != CommitMarker.MarkerState.ACTIVE && when (snapshot.state) {
        CaptureState.QUEUED, CaptureState.PREPARING, CaptureState.MATERIALIZED,
        CaptureState.RETRYABLE_FAILURE, CaptureState.NEEDS_USER_ACTION -> true
        CaptureState.NEEDS_PERMISSION -> snapshot.resumeState in setOf(CaptureState.PREPARING, CaptureState.MATERIALIZED)
        else -> false
    }

/** Fences workers before reading the frontier and persists only the governed USER_DISCARDED event.
 * Source bytes, prepared artifacts and receipts stay intact. False never means delivered or deleted.
 */
internal class CaptureDiscard(
    private val store: DurableCapturePackageStore,
    private val coordinator: CaptureDurabilityCoordinator,
    private val clock: () -> Long,
) {
    fun discard(requestID: String): Boolean {
        if (!Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$").matches(requestID)) return false
        val token = UUID.randomUUID().toString().lowercase()
        if (coordinator.acquire(requestID, token, clock(), 60_000) !is LeasePlan.Grant) return false
        try {
            val snapshot = coordinator.recoverJournal(requestID, token, clock()) ?: return false
            val command = if (snapshot.state == CaptureState.DISCARDED) {
                // Replay the exact event to re-sync the rename after an uncertain prior result.
                JournalMutationCommand(requestID, snapshot.revision - 1, snapshot.events.last(), token)
            } else {
                if (!canDiscardCapture(snapshot, store.readCommitMarker(requestID))) return false
                JournalMutationCommand(requestID, snapshot.revision,
                    JournalEvent(snapshot.revision + 1, snapshot.state, CaptureState.DISCARDED, JournalCode.USER_DISCARDED, clock()), token)
            }
            return when (coordinator.mutate(command, clock())) {
                is JournalMutationResult.Applied, is JournalMutationResult.AlreadyApplied,
                is JournalMutationResult.PersistedIndexPending -> true
                else -> false
            }
        } finally {
            coordinator.release(requestID, token)
        }
    }
}
