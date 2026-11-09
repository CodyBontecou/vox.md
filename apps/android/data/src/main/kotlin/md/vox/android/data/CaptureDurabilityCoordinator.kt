package md.vox.android.data

import md.vox.android.capturedomain.*

/** Production-unwired coordinator. Scheduling and TTL policy deliberately remain absent. */
internal class CaptureDurabilityCoordinator(
    private val store: DurableCapturePackageStore,
    private val leases: CaptureLeasePersistence,
) {
    fun acquire(requestID: String, candidateToken: String, nowEpochMillis: Long, durationMillis: Long): LeasePlan =
        store.withRootMutationLock { leases.acquire(requestID, candidateToken, nowEpochMillis, durationMillis) }

    fun renew(requestID: String, token: String, nowEpochMillis: Long, durationMillis: Long): LeasePlan =
        store.withRootMutationLock { leases.renew(requestID, token, nowEpochMillis, durationMillis) }

    fun release(requestID: String, token: String): Boolean =
        store.withRootMutationLock { leases.release(requestID, token) }

    fun isCurrent(requestID: String, token: String, nowEpochMillis: Long): LeasePlan =
        store.withRootMutationLock { leases.isCurrent(requestID, token, nowEpochMillis) }

    /** The store keeps one root lock continuous across fence check, CAS, replace, fsync, and projection. */
    fun mutate(command: JournalMutationCommand, nowEpochMillis: Long): JournalMutationResult =
        store.mutateJournal(command) { candidate ->
            command.leaseToken == candidate && leases.isCurrent(command.requestID, candidate, nowEpochMillis) is LeasePlan.Current
        }

    /** Cleanup and read share the root lock with the current-fence check. */
    fun recoverJournal(requestID: String, token: String, nowEpochMillis: Long): JournalSnapshot? =
        store.recoverJournal(requestID) {
            leases.isCurrent(requestID, token, nowEpochMillis) is LeasePlan.Current
        }

    /** Recovery intent admission must share the package lock with its worker-fence check. */
    fun <T> withCurrentLease(requestID: String, token: String, now: Long, action: () -> T): T? =
        store.withRootMutationLock {
            if (leases.isCurrent(requestID, token, now) is LeasePlan.Current) action() else null
        }

    /** Expiry clears only Room ownership. It never appends a journal event. */
    fun clearExpiredLeases(nowEpochMillis: Long): LeaseClearResult =
        store.withRootMutationLock { leases.clearExpired(nowEpochMillis) }
}
