package md.vox.android

import com.android.billingclient.api.Purchase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class PaywallPlansTest {
    // region Entitlement evaluation

    private fun purchase(
        productID: String,
        state: Int = Purchase.PurchaseState.PURCHASED,
        acknowledged: Boolean = true,
        suspended: Boolean = false,
        autoRenewing: Boolean = true,
    ) = PlayPurchaseSnapshot(listOf(productID), state, acknowledged, suspended, autoRenewing)

    @Test fun activeAcknowledgedSubscriptionGrantsUnlimited() {
        val result = unlimitedEntitlementDecision(
            priorEntitlement = VoxEntitlement.FREE,
            purchases = listOf(purchase(PlayBillingManager.YEARLY_PRODUCT_ID)),
            authoritativeOwnershipQuery = true,
        )
        assertEquals(VoxEntitlement.UNLIMITED, result.decision.entitlement)
        assertEquals(true, result.decision.authoritativeOwned)
        assertEquals(PlayBillingManager.YEARLY_PRODUCT_ID, result.grantingProductID)
    }

    @Test fun expiredSubscriptionIsAbsentFromPlayAndDropsAccessOnAuthoritativeQuery() {
        val result = unlimitedEntitlementDecision(
            priorEntitlement = VoxEntitlement.UNLIMITED,
            purchases = emptyList(),
            authoritativeOwnershipQuery = true,
        )
        assertEquals(VoxEntitlement.FREE, result.decision.entitlement)
        assertEquals(false, result.decision.authoritativeOwned)
        assertNull(result.grantingProductID)
    }

    @Test fun unavailablePlayKeepsCachedSubscriptionAccess() {
        val result = unlimitedEntitlementDecision(
            priorEntitlement = VoxEntitlement.UNLIMITED,
            purchases = emptyList(),
            authoritativeOwnershipQuery = false,
        )
        assertEquals(VoxEntitlement.UNLIMITED, result.decision.entitlement)
        assertNull(result.decision.authoritativeOwned)
    }

    @Test fun pendingSubscriptionNeverGrantsUnlimited() {
        val result = unlimitedEntitlementDecision(
            priorEntitlement = VoxEntitlement.FREE,
            purchases = listOf(purchase(PlayBillingManager.WEEKLY_PRODUCT_ID, state = Purchase.PurchaseState.PENDING)),
            authoritativeOwnershipQuery = true,
        )
        assertEquals(VoxEntitlement.PENDING, result.decision.entitlement)
        assertTrue(result.decision.hasPendingPurchase)
        assertNull(result.grantingProductID)
    }

    @Test fun unacknowledgedSubscriptionWaitsForAcknowledgement() {
        val result = unlimitedEntitlementDecision(
            priorEntitlement = VoxEntitlement.FREE,
            purchases = listOf(purchase(PlayBillingManager.YEARLY_PRODUCT_ID, acknowledged = false)),
            authoritativeOwnershipQuery = true,
        )
        assertEquals(VoxEntitlement.PENDING, result.decision.entitlement)
        assertNull(result.decision.authoritativeOwned)
        assertNull(result.grantingProductID)
    }

    @Test fun suspendedSubscriptionDoesNotGrantUnlimited() {
        val result = unlimitedEntitlementDecision(
            priorEntitlement = VoxEntitlement.UNLIMITED,
            purchases = listOf(purchase(PlayBillingManager.YEARLY_PRODUCT_ID, suspended = true)),
            authoritativeOwnershipQuery = true,
        )
        assertEquals(VoxEntitlement.FREE, result.decision.entitlement)
        assertEquals(false, result.decision.authoritativeOwned)
        assertTrue(result.hasRecognizedPurchase)
    }

    @Test fun lifetimePurchaseGrantsEvenBeforeAcknowledgementAndWinsOverSubscriptions() {
        val lifetimeOnly = unlimitedEntitlementDecision(
            priorEntitlement = VoxEntitlement.FREE,
            purchases = listOf(purchase(PlayBillingManager.LIFETIME_PRODUCT_ID, acknowledged = false)),
            authoritativeOwnershipQuery = true,
        )
        assertEquals(VoxEntitlement.UNLIMITED, lifetimeOnly.decision.entitlement)
        assertEquals(PlayBillingManager.LIFETIME_PRODUCT_ID, lifetimeOnly.grantingProductID)

        val both = unlimitedEntitlementDecision(
            priorEntitlement = VoxEntitlement.FREE,
            purchases = listOf(
                purchase(PlayBillingManager.WEEKLY_PRODUCT_ID),
                purchase(PlayBillingManager.LIFETIME_PRODUCT_ID),
            ),
            authoritativeOwnershipQuery = true,
        )
        assertEquals(PlayBillingManager.LIFETIME_PRODUCT_ID, both.grantingProductID)
    }

    @Test fun unrecognizedProductsNeverUnlock() {
        val result = unlimitedEntitlementDecision(
            priorEntitlement = VoxEntitlement.FREE,
            purchases = listOf(purchase("some_other_app_product")),
            authoritativeOwnershipQuery = true,
        )
        assertEquals(VoxEntitlement.FREE, result.decision.entitlement)
        assertFalse(result.hasRecognizedPurchase)
    }

    @Test fun reminderIsKeptOnlyWhileASubscriptionStillRenews() {
        assertTrue(hasRenewingSubscription(listOf(purchase(PlayBillingManager.YEARLY_PRODUCT_ID))))
        assertFalse(hasRenewingSubscription(listOf(purchase(PlayBillingManager.YEARLY_PRODUCT_ID, autoRenewing = false))))
        assertFalse(hasRenewingSubscription(listOf(purchase(PlayBillingManager.LIFETIME_PRODUCT_ID))))
        assertFalse(hasRenewingSubscription(emptyList()))
    }

    @Test fun productStatusOnlyReportsMisconfigurationWhenNothingLoaded() {
        assertNull(productStatusAfterQueries(loadedPlanCount = 1, failedResponseCodes = listOf(3)))
        assertEquals("productQuery:3", productStatusAfterQueries(loadedPlanCount = 0, failedResponseCodes = listOf(3)))
        assertEquals("productNotConfigured", productStatusAfterQueries(loadedPlanCount = 0, failedResponseCodes = emptyList()))
    }

    // endregion

    // region Offer selection, trial length and reminder (VoxPlayCatalog)

    private fun phase(micros: Long, period: String, cycles: Int = 0, infinite: Boolean = true) =
        PlayPricingPhase(if (micros == 0L) "Free" else "P$micros", micros, "USD", period, cycles, infinite)

    private val basePlan = PlaySubscriptionOffer(
        productID = PlayBillingManager.YEARLY_PRODUCT_ID,
        basePlanID = "yearly",
        offerID = null,
        offerToken = "base-token",
        phases = listOf(phase(29_990_000L, "P1Y")),
    )

    private val trialOffer = basePlan.copy(
        offerID = "free-trial-1w",
        offerToken = "trial-token",
        phases = listOf(phase(0L, "P1W", cycles = 1, infinite = false), phase(29_990_000L, "P1Y")),
    )

    @Test fun eligibleFreeTrialOfferIsPreferredOverBasePlan() {
        val selected = subscriptionPlanOptions(listOf(basePlan, trialOffer)).single()
        assertEquals("trial-token", selected.offerToken)
        assertEquals(7, isoPeriodDays(selected.freeTrialPeriod))
        assertEquals(29_990_000L, selected.priceAmountMicros)
    }

    @Test fun basePlanIsUsedWhenNoFreePhaseIsOffered() {
        val introductoryPaid = basePlan.copy(
            offerID = "free-trial-1w",
            offerToken = "intro-token",
            phases = listOf(phase(9_990_000L, "P1Y", cycles = 1, infinite = false), phase(29_990_000L, "P1Y")),
        )
        val selected = subscriptionPlanOptions(listOf(introductoryPaid, basePlan)).single()
        assertEquals("base-token", selected.offerToken)
        assertNull(selected.freeTrialPeriod)
    }

    @Test fun ineligibleUserWithOnlyBasePlanGetsNoTrial() {
        val selected = subscriptionPlanOptions(listOf(basePlan)).single()
        assertEquals("base-token", selected.offerToken)
        assertFalse(selected.hasFreeTrial)
        assertTrue(subscriptionPlanOptions(emptyList()).isEmpty())
    }

    @Test fun trialLengthUnderstandsDayAndWeekPeriodsAndRepeatedCycles() {
        assertEquals(7, isoPeriodDays("P7D"))
        assertEquals(7, isoPeriodDays("P1W"))
        assertNull(isoPeriodDays("not-a-period"))
        val twoWeeks = trialOffer.copy(phases = listOf(phase(0L, "P1W", cycles = 2, infinite = false), phase(29_990_000L, "P1Y")))
        assertEquals(14, isoPeriodDays(subscriptionPlanOptions(listOf(twoWeeks)).single().freeTrialPeriod))
    }

    @Test fun reminderDayIsTwoDaysBeforeTheTrialEnds() {
        assertEquals(5, trialReminderDay(7))
        assertNull(trialReminderDay(2))
        val trial = subscriptionPlanOptions(listOf(trialOffer)).single()
        assertEquals(1_000L + 5 * 86_400_000L, trialReminderEpochMillis(trial, 1_000L))
        assertNull(trialReminderEpochMillis(trial.copy(freeTrialPeriod = "P2D"), 1_000L))
        assertNull(trialReminderEpochMillis(trial.copy(freeTrialPeriod = null), 1_000L))
    }

    // endregion

    // region Savings

    private val yearly = VoxPlanOption(VoxPlan.YEARLY, "$29.99", 29_990_000L, "USD", "P1Y", "P1W", "y")
    private val weekly = VoxPlanOption(VoxPlan.WEEKLY, "$0.99", 990_000L, "USD", "P1W", "P1W", "w")

    @Test fun savingsPercentIsRoundedDown() {
        // 1 - 29.99 / (0.99 x 52) = 41.74 %
        assertEquals(41, yearlySavingsPercent(weekly, yearly))
        assertEquals(50, yearlySavingsPercent(weekly.copy(priceAmountMicros = 1_000_000L), yearly.copy(priceAmountMicros = 26_000_000L)))
        assertNull(yearlySavingsPercent(weekly.copy(priceAmountMicros = 1_000_000L), yearly.copy(priceAmountMicros = 52_000_000L)))
    }

    @Test fun savingsBadgeIsHiddenWhenAPriceIsMissingOrCurrenciesDiffer() {
        assertNull(yearlySavingsPercent(null, yearly))
        assertNull(yearlySavingsPercent(weekly, null))
        assertNull(yearlySavingsPercent(weekly.copy(currencyCode = "EUR"), yearly))
        assertNull(yearlySavingsPercent(weekly, yearly.copy(priceAmountMicros = 0L)))
    }

    // endregion
}
