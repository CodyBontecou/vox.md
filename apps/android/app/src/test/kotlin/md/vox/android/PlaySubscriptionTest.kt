package md.vox.android

import com.android.billingclient.api.Purchase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Subscription catalog, pricing and ownership rules exercised against fake Play data:
 * offers and purchases are built by hand, so no BillingClient or store account is touched.
 */
class PlaySubscriptionTest {
    private fun phase(price: String, micros: Long, period: String, cycles: Int = 0, infinite: Boolean = true) =
        PlayPricingPhase(price, micros, "USD", period, cycles, infinite)

    private val freeWeek = phase("Free", 0L, "P1W", cycles = 1, infinite = false)

    private fun fakeOffers(trialEligible: Boolean) = buildList {
        add(PlaySubscriptionOffer(VoxPlayCatalog.YEARLY_BASE_PLAN_ID, null, "yearly-base", listOf(phase("$29.99", 29_990_000L, "P1Y"))))
        add(PlaySubscriptionOffer(VoxPlayCatalog.WEEKLY_BASE_PLAN_ID, null, "weekly-base", listOf(phase("$0.99", 990_000L, "P1W"))))
        if (trialEligible) {
            add(PlaySubscriptionOffer(VoxPlayCatalog.YEARLY_BASE_PLAN_ID, VoxPlayCatalog.YEARLY_TRIAL_OFFER_ID, "yearly-trial",
                listOf(freeWeek, phase("$29.99", 29_990_000L, "P1Y"))))
            add(PlaySubscriptionOffer(VoxPlayCatalog.WEEKLY_BASE_PLAN_ID, VoxPlayCatalog.WEEKLY_TRIAL_OFFER_ID, "weekly-trial",
                listOf(freeWeek, phase("$0.99", 990_000L, "P1W"))))
        }
        // An unrelated base plan Play might return must never become a Vox.md plan.
        add(PlaySubscriptionOffer("legacy-monthly", null, "monthly", listOf(phase("$4.99", 4_990_000L, "P1M"))))
    }

    @Test fun eligibleCustomersGetTheTrialOfferPricedFromItsRecurringPhase() {
        val plans = subscriptionPlanOptions(fakeOffers(trialEligible = true))
        assertEquals(listOf(VoxPlan.YEARLY, VoxPlan.WEEKLY), plans.map { it.plan })
        val yearly = plans.first()
        assertEquals("yearly-trial", yearly.offerToken)
        assertEquals("$29.99", yearly.formattedPrice)
        assertEquals("P1W", yearly.freeTrialPeriod)
        assertEquals(7, isoPeriodDays(yearly.freeTrialPeriod))
    }

    @Test fun ineligibleCustomersFallBackToTheBasePlanWithoutATrial() {
        val plans = subscriptionPlanOptions(fakeOffers(trialEligible = false))
        assertEquals(listOf("yearly-base", "weekly-base"), plans.map { it.offerToken })
        assertTrue(plans.none { it.hasFreeTrial })
    }

    @Test fun missingBasePlansAreOmittedInsteadOfInvented() {
        val plans = subscriptionPlanOptions(fakeOffers(trialEligible = true).filter { it.basePlanID != VoxPlayCatalog.WEEKLY_BASE_PLAN_ID })
        assertEquals(listOf(VoxPlan.YEARLY), plans.map { it.plan })
        assertTrue(subscriptionPlanOptions(emptyList()).isEmpty())
    }

    @Test fun yearlySavingsComeFromRealPricesAndRefuseMixedCurrencies() {
        val plans = subscriptionPlanOptions(fakeOffers(trialEligible = false))
        val weekly = plans.first { it.plan == VoxPlan.WEEKLY }
        val yearly = plans.first { it.plan == VoxPlan.YEARLY }
        // $29.99 a year against 52 x $0.99 = $51.48 saves 41.7%.
        assertEquals(42, yearlySavingsPercent(weekly, yearly))
        assertNull(yearlySavingsPercent(weekly, yearly.copy(currencyCode = "EUR")))
        assertNull(yearlySavingsPercent(weekly, yearly.copy(priceAmountMicros = 60_000_000L)))
        assertNull(yearlySavingsPercent(null, yearly))
    }

    @Test fun isoPeriodsCoverTheTrialAndRenewalLengthsPlayUses() {
        assertEquals(7, isoPeriodDays("P7D"))
        assertEquals(7, isoPeriodDays("P1W"))
        assertEquals(365, isoPeriodDays("P1Y"))
        assertNull(isoPeriodDays("P1W2D"))
        assertNull(isoPeriodDays(null))
    }

    @Test fun trialEndDateIsTheOffersTrialLengthFromNow() {
        val yearly = subscriptionPlanOptions(fakeOffers(trialEligible = true)).first()
        assertEquals(1_000L + 7 * 86_400_000L, trialEndEpochMillis(yearly, 1_000L))
        assertNull(trialEndEpochMillis(yearly.copy(freeTrialPeriod = null), 1_000L))
    }

    @Test fun activeSubscribersReplaceTheirPlanAndLifetimeOwnersCannotBuyAgain() {
        val plans = subscriptionPlanOptions(fakeOffers(trialEligible = false))
        val weekly = plans.first { it.plan == VoxPlan.WEEKLY }
        val lifetime = VoxPlanOption(VoxPlan.LIFETIME, "$49.99", 49_990_000L, "USD", null, null, "lifetime")
        assertEquals(VoxPurchaseRequest.NewSubscription("weekly-base"), voxPurchaseRequest(weekly, false, null, false))
        assertEquals(
            VoxPurchaseRequest.ReplaceSubscription("weekly-base", "old-token"),
            voxPurchaseRequest(weekly, ownsLifetime = false, activeSubscriptionToken = "old-token", hasPendingPurchase = false),
        )
        assertEquals(VoxPurchaseRequest.Lifetime("lifetime"), voxPurchaseRequest(lifetime, false, "old-token", false))
        assertEquals(VoxPurchaseRequest.Blocked("alreadyOwned"), voxPurchaseRequest(weekly, true, null, false))
        assertEquals(VoxPurchaseRequest.Blocked("pending"), voxPurchaseRequest(weekly, false, null, true))
        assertEquals(VoxPurchaseRequest.Blocked("productUnavailable"), voxPurchaseRequest(null, false, null, false))
    }

    @Test fun unlimitedIsAnActiveSubscriptionOrLifetimeAndPendingGrantsNothing() {
        val lifetime = listOf(VoxPlayCatalog.LIFETIME_PRODUCT_ID)
        val subscription = listOf(VoxPlayCatalog.SUBSCRIPTION_PRODUCT_ID)
        val subscribed = voxOwnershipFrom(listOf(Triple(subscription, Purchase.PurchaseState.PURCHASED, "sub-token")))
        assertFalse(subscribed.ownsLifetime)
        assertEquals("sub-token", subscribed.activeSubscriptionToken)
        val both = voxOwnershipFrom(listOf(
            Triple(lifetime, Purchase.PurchaseState.PURCHASED, "life-token"),
            Triple(subscription, Purchase.PurchaseState.PURCHASED, "sub-token"),
        ))
        assertTrue(both.ownsLifetime)
        val pending = voxOwnershipFrom(listOf(Triple(subscription, Purchase.PurchaseState.PENDING, "sub-token")))
        assertNull(pending.activeSubscriptionToken)
        assertEquals(
            VoxEntitlement.UNLIMITED,
            billingEntitlementDecision(VoxEntitlement.FREE, listOf(Purchase.PurchaseState.PURCHASED), authoritativeOwnershipQuery = true).entitlement,
        )
        // An expired subscription disappears from Play's query: an authoritative empty result revokes access.
        assertEquals(
            VoxEntitlement.FREE,
            billingEntitlementDecision(VoxEntitlement.UNLIMITED, emptyList(), authoritativeOwnershipQuery = true).entitlement,
        )
    }

    @Test fun subscribersMaySwitchPlansWhileLifetimeAndPendingStatesStayLocked() {
        val subscriber = BillingUiState(
            connectionPhase = BillingConnectionPhase.READY,
            entitlement = VoxEntitlement.UNLIMITED,
            productAvailable = true,
            hasActiveSubscription = true,
        )
        assertTrue(subscriber.canPurchase())
        assertFalse(subscriber.copy(ownsLifetime = true).canPurchase())
        assertFalse(subscriber.copy(hasActiveSubscription = false).canPurchase())
        val operations = BillingOperations()
        assertFalse(operations.beginPurchase(VoxEntitlement.UNLIMITED, pending = false))
        assertTrue(operations.beginPurchase(VoxEntitlement.UNLIMITED, pending = false, upgradeAllowed = true))
        assertFalse(operations.beginPurchase(VoxEntitlement.FREE, pending = false))
        operations.finishPurchase()
        assertFalse(operations.beginPurchase(VoxEntitlement.PENDING, pending = true, upgradeAllowed = true))
    }

    @Test fun manageSubscriptionsLinkTargetsTheVoxSubscription() {
        assertEquals(
            "https://play.google.com/store/account/subscriptions?sku=vox_unlimited_individual&package=md.vox.android",
            VoxPlayCatalog.manageSubscriptionsUrl("md.vox.android"),
        )
    }

    @Test fun handBuiltLifetimeStatesStillOfferLifetime() {
        val state = BillingUiState(productAvailable = true, formattedPrice = "$4.99")
        assertEquals(listOf(VoxPlan.LIFETIME), state.purchasablePlans.map { it.plan })
        assertTrue(BillingUiState(formattedPrice = "$4.99").purchasablePlans.isEmpty())
    }
}
