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

    // region Offer selection

    private fun phase(micros: Long, period: String, cycles: Int = 0, recurrence: Int = RECURRENCE_INFINITE) =
        PaywallPricingPhase(
            priceAmountMicros = micros,
            formattedPrice = if (micros == 0L) "Free" else "P$micros",
            currencyCode = "USD",
            billingPeriod = period,
            billingCycleCount = cycles,
            recurrenceMode = recurrence,
        )

    private val basePlan = PaywallOfferCandidate(
        basePlanID = "yearly",
        offerID = null,
        offerToken = "base-token",
        phases = listOf(phase(29_990_000L, "P1Y")),
    )

    private val trialOffer = PaywallOfferCandidate(
        basePlanID = "yearly",
        offerID = "free-trial-7d",
        offerToken = "trial-token",
        phases = listOf(phase(0L, "P1W", cycles = 1, recurrence = 2), phase(29_990_000L, "P1Y")),
    )

    @Test fun eligibleFreeTrialOfferIsPreferredOverBasePlan() {
        val selected = selectSubscriptionOffer(listOf(basePlan, trialOffer))
        assertEquals("trial-token", selected?.offerToken)
        assertEquals(7, selected?.freeTrialDays)
        assertEquals(29_990_000L, selected?.recurringPhase?.priceAmountMicros)
    }

    @Test fun basePlanIsUsedWhenNoFreePhaseIsOffered() {
        val introductoryPaid = PaywallOfferCandidate(
            basePlanID = "yearly",
            offerID = "intro",
            offerToken = "intro-token",
            phases = listOf(phase(9_990_000L, "P1Y", cycles = 1, recurrence = 2), phase(29_990_000L, "P1Y")),
        )
        val selected = selectSubscriptionOffer(listOf(introductoryPaid, basePlan))
        assertEquals("base-token", selected?.offerToken)
        assertNull(selected?.freeTrialDays)
    }

    @Test fun ineligibleUserWithOnlyBasePlanGetsNoTrial() {
        val selected = selectSubscriptionOffer(listOf(basePlan))
        assertEquals("base-token", selected?.offerToken)
        assertNull(selected?.freeTrialDays)
        assertNull(selectSubscriptionOffer(emptyList()))
    }

    @Test fun trialLengthUnderstandsDayAndWeekPeriods() {
        assertEquals(7, freeTrialDays(phase(0L, "P7D", cycles = 1)))
        assertEquals(7, freeTrialDays(phase(0L, "P1W", cycles = 1)))
        assertEquals(14, freeTrialDays(phase(0L, "P1W", cycles = 2)))
        assertNull(freeTrialDays(phase(0L, "not-a-period", cycles = 1)))
        assertEquals(365, isoPeriodDays("P1Y"))
    }

    // endregion

    // region Savings and copy

    private val yearly = PaywallPlan(PaywallPlanKind.YEARLY, "$29.99", 29_990_000L, "USD", "y", freeTrialDays = 7)
    private val weekly = PaywallPlan(PaywallPlanKind.WEEKLY, "$0.99", 990_000L, "USD", "w", freeTrialDays = 7)
    private val lifetime = PaywallPlan(PaywallPlanKind.LIFETIME, "$49.99", 49_990_000L, "USD")

    @Test fun savingsPercentIsRoundedDown() {
        // 1 - 29.99 / (0.99 × 52) = 41.74 %
        assertEquals(41, yearlySavingsPercent(yearly, weekly))
        assertEquals(50, yearlySavingsPercent(26_000_000L, 1_000_000L))
        assertNull(yearlySavingsPercent(52_000_000L, 1_000_000L))
    }

    @Test fun savingsBadgeIsHiddenWhenAPriceIsMissingOrCurrenciesDiffer() {
        assertNull(yearlySavingsPercent(yearly, null))
        assertNull(yearlySavingsPercent(null, weekly))
        assertNull(yearlySavingsPercent(yearly, weekly.copy(currencyCode = "EUR")))
        assertNull(yearlySavingsPercent(0L, 990_000L))
    }

    @Test fun summaryUsesTrialCopyOnlyWithAnEligibleTrial() {
        assertEquals(
            voxUiText("%lld days free, then %@/yr. Auto-renews.", 7, "$29.99"),
            paywallSummary(yearly),
        )
        assertEquals(
            voxUiText("%@/yr, renews automatically", "$29.99"),
            paywallSummary(yearly.copy(freeTrialDays = null)),
        )
        assertEquals(
            voxUiText("%lld days free, then %@/wk. Auto-renews.", 7, "$0.99"),
            paywallSummary(weekly),
        )
        assertEquals(
            voxUiText("%@/wk, renews automatically", "$0.99"),
            paywallSummary(weekly.copy(freeTrialDays = null)),
        )
        assertEquals(voxUiText("%@, once. No subscription.", "$49.99"), paywallSummary(lifetime))
        assertNull(paywallSummary(null))
    }

    @Test fun callToActionMatchesPlanAndEntitlement() {
        assertEquals(voxUiText("Start %lld-day free trial", 7), paywallCallToAction(yearly, VoxEntitlement.FREE))
        assertEquals(voxUiText("Subscribe"), paywallCallToAction(weekly.copy(freeTrialDays = null), VoxEntitlement.FREE))
        assertEquals(voxUiText("Unlock for %@", "$49.99"), paywallCallToAction(lifetime, VoxEntitlement.FREE))
        assertEquals(voxUiText("Unlock Unlimited"), paywallCallToAction(null, VoxEntitlement.FREE))
        assertEquals(voxUiText("Purchase Pending"), paywallCallToAction(yearly, VoxEntitlement.PENDING))
    }

    @Test fun selectionAndTimelineFollowLoadedPlans() {
        assertEquals(PaywallPlanKind.YEARLY, defaultPaywallPlanKind(listOf(lifetime, weekly, yearly)))
        assertEquals(PaywallPlanKind.LIFETIME, defaultPaywallPlanKind(listOf(lifetime)))
        assertEquals(PaywallPlanKind.WEEKLY, trialTimelinePlan(listOf(yearly, weekly), PaywallPlanKind.WEEKLY)?.kind)
        assertEquals(PaywallPlanKind.YEARLY, trialTimelinePlan(listOf(yearly, lifetime), PaywallPlanKind.LIFETIME)?.kind)
        assertNull(trialTimelinePlan(listOf(lifetime, yearly.copy(freeTrialDays = null)), PaywallPlanKind.LIFETIME))
        assertEquals(5, trialReminderDay(7))
        assertNull(trialReminderDay(2))
    }

    @Test fun planNotesExplainUnavailablePlans() {
        assertEquals(voxUiText("Not available right now"), paywallPlanNote(PaywallPlanKind.WEEKLY, null))
        assertEquals(voxUiText("%lld days free, then %@/yr", 7, "$29.99"), paywallPlanNote(PaywallPlanKind.YEARLY, yearly))
        assertEquals(voxUiText("One purchase, no renewals"), paywallPlanNote(PaywallPlanKind.LIFETIME, lifetime))
    }

    // endregion
}
