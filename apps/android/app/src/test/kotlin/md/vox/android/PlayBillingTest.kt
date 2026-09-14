package md.vox.android

import com.android.billingclient.api.Purchase
import org.junit.Assert.assertEquals
import org.junit.Test

class PlayBillingTest {
    @Test fun purchasedOwnershipWinsAndPendingNeverGrantsUnlimited() {
        assertEquals(VoxEntitlement.FREE, entitlementForPurchaseStates(emptyList()))
        assertEquals(
            VoxEntitlement.PENDING,
            entitlementForPurchaseStates(listOf(Purchase.PurchaseState.PENDING)),
        )
        assertEquals(
            VoxEntitlement.UNLIMITED,
            entitlementForPurchaseStates(
                listOf(Purchase.PurchaseState.PENDING, Purchase.PurchaseState.PURCHASED),
            ),
        )
    }

    @Test fun pendingPurchaseNeverErasesPreviouslyVerifiedUnlimitedAccess() {
        val decision = billingEntitlementDecision(
            priorEntitlement = VoxEntitlement.UNLIMITED,
            states = listOf(Purchase.PurchaseState.PENDING),
            authoritativeOwnershipQuery = true,
        )

        assertEquals(VoxEntitlement.UNLIMITED, decision.entitlement)
        assertEquals(true, decision.hasPendingPurchase)
        assertEquals(null, decision.authoritativeOwned)
    }

    @Test fun pendingPurchaseDoesNotGrantAFreeInstallationUnlimitedAccess() {
        val decision = billingEntitlementDecision(
            priorEntitlement = VoxEntitlement.FREE,
            states = listOf(Purchase.PurchaseState.PENDING),
            authoritativeOwnershipQuery = true,
        )

        assertEquals(VoxEntitlement.PENDING, decision.entitlement)
        assertEquals(true, decision.hasPendingPurchase)
        assertEquals(null, decision.authoritativeOwned)
    }

    @Test fun authoritativeEmptyOwnershipRevokesFutureUnlimitedAdmission() {
        val decision = billingEntitlementDecision(
            priorEntitlement = VoxEntitlement.UNLIMITED,
            states = emptyList(),
            authoritativeOwnershipQuery = true,
        )

        assertEquals(VoxEntitlement.FREE, decision.entitlement)
        assertEquals(false, decision.hasPendingPurchase)
        assertEquals(false, decision.authoritativeOwned)
    }

    @Test fun nonAuthoritativeEmptyUpdateCannotRevokeCachedOwnership() {
        val decision = billingEntitlementDecision(
            priorEntitlement = VoxEntitlement.UNLIMITED,
            states = emptyList(),
            authoritativeOwnershipQuery = false,
        )

        assertEquals(VoxEntitlement.UNLIMITED, decision.entitlement)
        assertEquals(false, decision.hasPendingPurchase)
        assertEquals(null, decision.authoritativeOwned)
    }

    @Test fun purchasedStateIsTheOnlyPositiveAuthority() {
        val decision = billingEntitlementDecision(
            priorEntitlement = VoxEntitlement.FREE,
            states = listOf(Purchase.PurchaseState.PENDING, Purchase.PurchaseState.PURCHASED),
            authoritativeOwnershipQuery = true,
        )

        assertEquals(VoxEntitlement.UNLIMITED, decision.entitlement)
        assertEquals(false, decision.hasPendingPurchase)
        assertEquals(true, decision.authoritativeOwned)
    }

    @Test fun staleCachedUnlimitedAccessIsExplainedToTheUser() {
        val message = billingMessage(
            BillingUiState(
                connectionPhase = BillingConnectionPhase.UNAVAILABLE,
                entitlement = VoxEntitlement.UNLIMITED,
                lastOutcome = BillingActionOutcome.UNAVAILABLE,
                isEntitlementStale = true,
            ),
        )

        assertEquals(
            "Unlimited is active from this installation’s last verified Google Play purchase. Connect to Play to refresh its status.",
            message?.source,
        )
    }

    @Test fun pendingPurchaseDoesNotHideExistingUnlimitedAccess() {
        val message = billingMessage(
            BillingUiState(
                entitlement = VoxEntitlement.UNLIMITED,
                hasPendingPurchase = true,
            ),
        )

        assertEquals(
            "Your existing Unlimited access remains active while Google Play processes the pending purchase.",
            message?.source,
        )
    }

    @Test fun productQueryCannotHideEntitlementIntegrityWarnings() {
        assertEquals(
            "entitlementCacheUnavailable",
            billingStatusAfterProductQuery(
                existingStatus = "entitlementCacheUnavailable",
                productStatus = null,
            ),
        )
        assertEquals(
            "unrecognizedPurchase",
            billingStatusAfterProductQuery(
                existingStatus = "unrecognizedPurchase",
                productStatus = "productNotConfigured",
            ),
        )
        assertEquals(
            "productQuery:2",
            billingStatusAfterProductQuery(
                existingStatus = "billingDisconnected",
                productStatus = "productQuery:2",
            ),
        )
    }
}
