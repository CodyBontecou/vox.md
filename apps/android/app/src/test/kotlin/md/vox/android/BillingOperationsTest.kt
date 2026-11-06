package md.vox.android

import org.junit.Assert.*
import org.junit.Test

class BillingOperationsTest {
    @Test fun lateEmptyOwnershipCannotRevokeANewerPurchaseUpdate() {
        val operations = BillingOperations()
        val oldQuery = operations.beginOwnershipQuery(false)
        operations.invalidateOwnershipQueries()
        assertNull(operations.finishOwnershipQuery(oldQuery))
        val refreshed = operations.beginOwnershipQuery(false)
        assertEquals(false,operations.finishOwnershipQuery(refreshed))
    }
    @Test fun anOwnershipResponseCanOnlyBeAppliedOnce() {
        val operations = BillingOperations()
        val query = operations.beginOwnershipQuery(true)
        assertEquals(true,operations.finishOwnershipQuery(query))
        assertNull(operations.finishOwnershipQuery(query))
    }
    @Test fun overlappingRefreshPreservesExplicitRestoreIntent() {
        val operations = BillingOperations()
        val restore = operations.beginOwnershipQuery(true)
        val foregroundRefresh = operations.beginOwnershipQuery(false)
        assertNull(operations.finishOwnershipQuery(restore))
        assertTrue(operations.isRestoring())
        assertEquals(true,operations.finishOwnershipQuery(foregroundRefresh))
        assertFalse(operations.isRestoring())
    }
    @Test fun purchaseCallbackDoesNotLoseAnOutstandingRestore() {
        val operations = BillingOperations()
        operations.beginOwnershipQuery(true)
        operations.invalidateOwnershipQueries()
        assertEquals(true,operations.finishOwnershipQuery(operations.beginOwnershipQuery(false)))
    }
    @Test fun duplicateCheckoutLaunchIsRejectedUntilTheFlowFinishes() {
        val operations = BillingOperations()
        assertTrue(operations.beginPurchase(VoxEntitlement.FREE,false))
        assertFalse(operations.beginPurchase(VoxEntitlement.FREE,false))
        operations.finishPurchase()
        assertTrue(operations.beginPurchase(VoxEntitlement.FREE,false))
    }
    @Test fun ownedPendingAndRestoringStatesNeverStartAnotherCheckout() {
        val operations = BillingOperations()
        assertFalse(operations.beginPurchase(VoxEntitlement.UNLIMITED,false))
        assertFalse(operations.beginPurchase(VoxEntitlement.PENDING,true))
        assertFalse(operations.beginPurchase(VoxEntitlement.FREE,true))
        operations.beginOwnershipQuery(true)
        assertFalse(operations.beginPurchase(VoxEntitlement.FREE,false))
    }
    @Test fun staleProductPricesCannotReplaceNewerOfferDetails() {
        val operations = BillingOperations()
        val old = operations.beginProductQuery()
        val current = operations.beginProductQuery()
        assertFalse(operations.isCurrentProductQuery(old))
        assertTrue(operations.isCurrentProductQuery(current))
    }
    @Test fun disconnectInvalidatesCallbacksAndReleasesCheckoutWithoutLosingRestoreIntent() {
        val operations = BillingOperations()
        assertTrue(operations.beginPurchase(VoxEntitlement.FREE,false))
        val query = operations.beginOwnershipQuery(true)
        val product = operations.beginProductQuery()
        assertTrue(operations.disconnected())
        assertNull(operations.finishOwnershipQuery(query))
        assertFalse(operations.isCurrentProductQuery(product))
        assertTrue(operations.beginPurchase(VoxEntitlement.FREE,false))
    }
    @Test fun screenEligibilityUsesStoreReadinessOwnershipAndOperationState() {
        val ready = BillingUiState(connectionPhase=BillingConnectionPhase.READY,productAvailable=true)
        assertTrue(ready.canPurchase())
        assertFalse(ready.copy(isPurchasing=true).canPurchase())
        assertFalse(ready.copy(isRestoring=true).canPurchase())
        assertFalse(ready.copy(entitlement=VoxEntitlement.UNLIMITED).canPurchase())
        assertFalse(ready.copy(hasPendingPurchase=true).canPurchase())
        assertFalse(ready.copy(connectionPhase=BillingConnectionPhase.UNAVAILABLE).canPurchase())
    }
}
