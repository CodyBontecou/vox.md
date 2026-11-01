package md.vox.android

/** Orders asynchronous Play responses without retaining purchases or transaction identifiers. */
internal class BillingOperations {
    private var ownershipGeneration = 0L
    private var productGeneration = 0L
    private var restorePending = false
    private var purchasing = false

    @Synchronized fun beginOwnershipQuery(restoring: Boolean): Long {
        restorePending = restorePending || restoring
        return ++ownershipGeneration
    }
    /** Null means stale; otherwise the result identifies a coalesced explicit restore. */
    @Synchronized fun finishOwnershipQuery(generation: Long): Boolean? {
        if (generation != ownershipGeneration) return null
        ownershipGeneration++
        return restorePending.also { restorePending = false }
    }
    @Synchronized fun invalidateOwnershipQueries() { ownershipGeneration++ }
    @Synchronized fun isRestoring(): Boolean = restorePending
    @Synchronized fun beginProductQuery(): Long = ++productGeneration
    @Synchronized fun isCurrentProductQuery(generation: Long): Boolean = generation == productGeneration
    @Synchronized fun beginPurchase(entitlement: VoxEntitlement, pending: Boolean): Boolean {
        if (purchasing || restorePending || entitlement != VoxEntitlement.FREE || pending) return false
        purchasing = true
        return true
    }
    @Synchronized fun finishPurchase() { purchasing = false }
    @Synchronized fun disconnected(): Boolean {
        ownershipGeneration++; productGeneration++; purchasing = false
        return restorePending.also { restorePending = false }
    }
}

internal fun BillingUiState.canPurchase(): Boolean = productAvailable &&
    entitlement == VoxEntitlement.FREE && !hasPendingPurchase && !isPurchasing && !isRestoring &&
    connectionPhase == BillingConnectionPhase.READY
