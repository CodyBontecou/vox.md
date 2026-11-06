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

    private val yearlyProduct = VoxPlayCatalog.YEARLY_PRODUCT_ID
    private val weeklyProduct = VoxPlayCatalog.WEEKLY_PRODUCT_ID

    /** Mirrors the live catalog: two subscription products, one base plan each, one trial offer each. */
    private fun fakeOffers(trialEligible: Boolean) = buildList {
        add(PlaySubscriptionOffer(yearlyProduct, "yearly", null, "yearly-base", listOf(phase("$29.99", 29_990_000L, "P1Y"))))
        add(PlaySubscriptionOffer(weeklyProduct, "weekly", null, "weekly-base", listOf(phase("$0.99", 990_000L, "P1W"))))
        if (trialEligible) {
            add(PlaySubscriptionOffer(yearlyProduct, "yearly", "free-trial-1w", "yearly-trial",
                listOf(freeWeek, phase("$29.99", 29_990_000L, "P1Y"))))
            add(PlaySubscriptionOffer(weeklyProduct, "weekly", "free-trial-1w", "weekly-trial",
                listOf(freeWeek, phase("$0.99", 990_000L, "P1W"))))
        }
        // An unrelated base plan Play might return must never become a Vox.md plan.
        add(PlaySubscriptionOffer(yearlyProduct, "legacy-monthly", null, "monthly", listOf(phase("$4.99", 4_990_000L, "P1M"))))
        // A base plan ID on the wrong product must not be mistaken for the other plan.
        add(PlaySubscriptionOffer(weeklyProduct, "yearly", null, "misplaced", listOf(phase("$9.99", 9_990_000L, "P1Y"))))
    }

    @Test fun catalogMatchesTheLivePlayConsoleProducts() {
        assertEquals("vox_unlimited_lifetime", VoxPlan.LIFETIME.productID)
        assertEquals("vox_unlimited_weekly", VoxPlan.WEEKLY.productID)
        assertEquals("weekly", VoxPlan.WEEKLY.basePlanID)
        assertEquals("vox_unlimited_yearly", VoxPlan.YEARLY.productID)
        assertEquals("yearly", VoxPlan.YEARLY.basePlanID)
        assertEquals("free-trial-1w", VoxPlan.YEARLY.trialOfferID)
        assertEquals("free-trial-1w", VoxPlan.WEEKLY.trialOfferID)
        assertEquals(listOf("vox_unlimited_yearly", "vox_unlimited_weekly"), VoxPlayCatalog.SUBSCRIPTION_PRODUCT_IDS)
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
        val plans = subscriptionPlanOptions(fakeOffers(trialEligible = true).filter { it.productID != weeklyProduct })
        assertEquals(listOf(VoxPlan.YEARLY), plans.map { it.plan })
        assertTrue(subscriptionPlanOptions(emptyList()).isEmpty())
    }

    @Test fun yearlySavingsComeFromRealPricesAndRefuseMixedCurrencies() {
        val plans = subscriptionPlanOptions(fakeOffers(trialEligible = false))
        val weekly = plans.first { it.plan == VoxPlan.WEEKLY }
        val yearly = plans.first { it.plan == VoxPlan.YEARLY }
        // $29.99 a year against 52 x $0.99 = $51.48 saves 41.7%, shown rounded down.
        assertEquals(41, yearlySavingsPercent(weekly, yearly))
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
        val yearly = plans.first { it.plan == VoxPlan.YEARLY }
        // Yearly -> Weekly waits for the next yearly renewal (DEFERRED), across products.
        assertEquals(
            VoxPurchaseRequest.ReplaceSubscription("weekly-base", "yearly-token", VoxReplacementMode.DEFERRED),
            voxPurchaseRequest(weekly, false, "yearly-token", false, activeSubscriptionProductID = yearlyProduct),
        )
        // Weekly -> Yearly switches now and credits the unused weekly time.
        assertEquals(
            VoxPurchaseRequest.ReplaceSubscription("yearly-base", "weekly-token", VoxReplacementMode.WITH_TIME_PRORATION),
            voxPurchaseRequest(yearly, false, "weekly-token", false, activeSubscriptionProductID = weeklyProduct),
        )
        // Once Weekly is scheduled, choosing it again does not open a second flow.
        assertEquals(
            VoxPurchaseRequest.Blocked("alreadyScheduled"),
            voxPurchaseRequest(weekly, false, "yearly-token", false, yearlyProduct, scheduledSubscriptionProductID = weeklyProduct),
        )
        // Buying the product already held is refused instead of opening a duplicate flow.
        assertEquals(
            VoxPurchaseRequest.Blocked("alreadySubscribed"),
            voxPurchaseRequest(weekly, false, "weekly-token", false, activeSubscriptionProductID = weeklyProduct),
        )
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
        val subscription = listOf(weeklyProduct)
        val subscribed = voxOwnershipFrom(listOf(Triple(subscription, Purchase.PurchaseState.PURCHASED, "sub-token")))
        assertFalse(subscribed.ownsLifetime)
        assertEquals("sub-token", subscribed.activeSubscriptionToken)
        assertEquals(weeklyProduct, subscribed.activeSubscriptionProductID)
        val yearly = voxOwnershipFrom(listOf(Triple(listOf(yearlyProduct), Purchase.PurchaseState.PURCHASED, "yearly-token")))
        assertEquals(yearlyProduct, yearly.activeSubscriptionProductID)
        val unrelated = voxOwnershipFrom(listOf(Triple(listOf("other_app_sub"), Purchase.PurchaseState.PURCHASED, "x")))
        assertNull(unrelated.activeSubscriptionToken)
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

    @Test fun replacementModesFollowTheDirectionOfTheSwitch() {
        assertEquals(VoxReplacementMode.DEFERRED, replacementModeFor(yearlyProduct, VoxPlan.WEEKLY))
        assertEquals(VoxReplacementMode.WITH_TIME_PRORATION, replacementModeFor(weeklyProduct, VoxPlan.YEARLY))
        assertEquals(VoxReplacementMode.WITH_TIME_PRORATION, replacementModeFor(null, VoxPlan.YEARLY))
    }

    @Test fun deferredSwitchStaysScheduledUntilPlayShowsTheNewProduct() {
        assertEquals(weeklyProduct, scheduledPlanAfterQuery(weeklyProduct, activeSubscriptionProductID = yearlyProduct))
        assertNull(scheduledPlanAfterQuery(weeklyProduct, activeSubscriptionProductID = weeklyProduct))
        // Canceled or expired: nothing is scheduled any more.
        assertNull(scheduledPlanAfterQuery(weeklyProduct, activeSubscriptionProductID = null))
        assertNull(scheduledPlanAfterQuery(null, activeSubscriptionProductID = yearlyProduct))
    }

    @Test fun manageSubscriptionsLinkTargetsTheActiveProduct() {
        assertEquals(
            "https://play.google.com/store/account/subscriptions?sku=vox_unlimited_yearly&package=md.vox.android",
            VoxPlayCatalog.manageSubscriptionsUrl("md.vox.android", "vox_unlimited_yearly"),
        )
        assertEquals(
            "https://play.google.com/store/account/subscriptions?sku=vox_unlimited_weekly&package=md.vox.android",
            VoxPlayCatalog.manageSubscriptionsUrl("md.vox.android", "vox_unlimited_weekly"),
        )
        assertEquals(
            "https://play.google.com/store/account/subscriptions?package=md.vox.android",
            VoxPlayCatalog.manageSubscriptionsUrl("md.vox.android", null),
        )
    }

    @Test fun handBuiltLifetimeStatesStillOfferLifetime() {
        val state = BillingUiState(productAvailable = true, formattedPrice = "$4.99")
        assertEquals(listOf(VoxPlan.LIFETIME), state.purchasablePlans.map { it.plan })
        assertTrue(BillingUiState(formattedPrice = "$4.99").purchasablePlans.isEmpty())
    }
}
