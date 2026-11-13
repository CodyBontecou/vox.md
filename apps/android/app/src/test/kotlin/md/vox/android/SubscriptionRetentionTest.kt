package md.vox.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Lapse detection, the tagged Weekly -> Yearly offer, and the retention copy, on fake Play data. */
class SubscriptionRetentionTest {
    private val weekly = VoxPlayCatalog.WEEKLY_PRODUCT_ID
    private val yearly = VoxPlayCatalog.YEARLY_PRODUCT_ID
    private val lifetime = VoxPlayCatalog.LIFETIME_PRODUCT_ID

    // region Lapse detection

    @Test fun signedNegativeSubscriptionEvidenceIsALapseOfThatPlan() {
        assertEquals(SubscriptionLapse(true, yearly), subscriptionLapseFromEvidence(CachedPlayEntitlement(yearly, false, 1L)))
        assertEquals(SubscriptionLapse(true, weekly), subscriptionLapseFromEvidence(CachedPlayEntitlement(weekly, false, 1L)))
    }

    @Test fun ownedLifetimeOrMissingEvidenceIsNotALapse() {
        assertEquals(SubscriptionLapse.None, subscriptionLapseFromEvidence(null))
        assertEquals(SubscriptionLapse.None, subscriptionLapseFromEvidence(CachedPlayEntitlement(weekly, true, 1L)))
        // A refunded Lifetime or a never-subscribed install records the Lifetime ID: free, not lapsed.
        assertEquals(SubscriptionLapse.None, subscriptionLapseFromEvidence(CachedPlayEntitlement(lifetime, false, 1L)))
    }

    @Test fun authoritativeLossOfAnActiveSubscriptionRecordsTheLapsedPlan() {
        assertEquals(
            SubscriptionLapse(true, weekly),
            subscriptionLapseAfterOwnershipQuery(SubscriptionLapse.None, weekly, authoritativeOwned = false),
        )
    }

    @Test fun incompleteObservationsNeitherCreateNorClearALapse() {
        assertEquals(SubscriptionLapse.None, subscriptionLapseAfterOwnershipQuery(SubscriptionLapse.None, weekly, authoritativeOwned = null))
        val ended = SubscriptionLapse(true, yearly)
        assertEquals(ended, subscriptionLapseAfterOwnershipQuery(ended, null, authoritativeOwned = null))
    }

    @Test fun laterNegativeQueriesKeepTheOriginalLapsedPlan() {
        val ended = SubscriptionLapse(true, yearly)
        assertEquals(ended, subscriptionLapseAfterOwnershipQuery(ended, null, authoritativeOwned = false))
    }

    @Test fun neverSubscribedUsersDoNotLapse() {
        assertEquals(SubscriptionLapse.None, subscriptionLapseAfterOwnershipQuery(SubscriptionLapse.None, null, authoritativeOwned = false))
    }

    @Test fun anyVerifiedPurchaseClearsTheLapse() {
        assertEquals(SubscriptionLapse.None, subscriptionLapseAfterOwnershipQuery(SubscriptionLapse(true, weekly), null, authoritativeOwned = true))
    }

    // endregion

    // region Offer selection

    private fun phase(price: String, micros: Long, period: String, cycles: Int = 0, infinite: Boolean = true, currency: String = "USD") =
        PlayPricingPhase(price, micros, currency, period, cycles, infinite)

    private val firstYear = phase("$19.99", 19_990_000L, "P1Y", cycles = 1, infinite = false)
    private val yearlyBase = phase("$29.99", 29_990_000L, "P1Y")

    private fun switchOffer(
        productID: String = yearly,
        basePlanID: String = VoxPlayCatalog.YEARLY_BASE_PLAN_ID,
        offerID: String? = VoxPlayCatalog.SWITCH_YEARLY_OFFER_ID,
        token: String = "switch-token",
        phases: List<PlayPricingPhase> = listOf(firstYear, yearlyBase),
        tags: List<String> = listOf(VoxPlayCatalog.RETENTION_IN_APP_OFFER_TAG),
    ) = PlaySubscriptionOffer(productID, basePlanID, offerID, token, phases, tags)

    private val catalog = listOf(
        PlaySubscriptionOffer(yearly, "yearly", null, "yearly-base", listOf(yearlyBase)),
        PlaySubscriptionOffer(weekly, "weekly", null, "weekly-base", listOf(phase("$0.99", 990_000L, "P1W"))),
    )

    @Test fun taggedSwitchOfferIsPricedFromItsOwnPhases() {
        assertEquals(
            VoxYearlySwitchOffer("switch-token", "$19.99", "$29.99"),
            yearlySwitchOffer(catalog + switchOffer()),
        )
    }

    @Test fun offerWithoutTheRetentionTagIsIgnored() {
        assertNull(yearlySwitchOffer(catalog + switchOffer(tags = emptyList())))
        assertNull(yearlySwitchOffer(catalog + switchOffer(tags = listOf("paywall"))))
    }

    @Test fun onlyTheSwitchOfferIdOnTheYearlyBasePlanQualifies() {
        assertNull(yearlySwitchOffer(catalog))
        assertNull(yearlySwitchOffer(catalog + switchOffer(offerID = VoxPlayCatalog.FREE_TRIAL_OFFER_ID)))
        assertNull(yearlySwitchOffer(catalog + switchOffer(offerID = null)))
        assertNull(yearlySwitchOffer(catalog + switchOffer(productID = weekly, basePlanID = "weekly")))
        assertNull(yearlySwitchOffer(catalog + switchOffer(basePlanID = "monthly")))
        assertNull(yearlySwitchOffer(catalog + switchOffer(token = " ")))
    }

    @Test fun offerShapesTheCopyCannotDescribeAreHidden() {
        // Not "one discounted year, then the Yearly price".
        assertNull(yearlySwitchOffer(catalog + switchOffer(phases = listOf(yearlyBase))))
        assertNull(yearlySwitchOffer(catalog + switchOffer(phases = listOf(phase("$1.99", 1_990_000L, "P1M", cycles = 12, infinite = false), yearlyBase))))
        assertNull(yearlySwitchOffer(catalog + switchOffer(phases = listOf(phase("$19.99", 19_990_000L, "P1Y", cycles = 2, infinite = false), yearlyBase))))
        assertNull(yearlySwitchOffer(catalog + switchOffer(phases = listOf(phase("Free", 0L, "P1Y", cycles = 1, infinite = false), yearlyBase))))
        assertNull(yearlySwitchOffer(catalog + switchOffer(phases = listOf(phase("$39.99", 39_990_000L, "P1Y", cycles = 1, infinite = false), yearlyBase))))
        assertNull(yearlySwitchOffer(catalog + switchOffer(phases = listOf(phase("€19.99", 19_990_000L, "P1Y", cycles = 1, infinite = false, currency = "EUR"), yearlyBase))))
    }

    // endregion

    // region Eligibility

    private val offer = VoxYearlySwitchOffer("switch-token", "$19.99", "$29.99")

    private fun weeklySubscriber() = BillingUiState(
        connectionPhase = BillingConnectionPhase.READY,
        entitlement = VoxEntitlement.UNLIMITED,
        productAvailable = true,
        hasActiveSubscription = true,
        activeSubscriptionProductID = weekly,
        yearlySwitchOffer = offer,
    )

    @Test fun activeWeeklySubscriberIsEligible() {
        assertEquals(offer, weeklySubscriber().eligibleYearlySwitchOffer())
    }

    @Test fun everyoneElseIsIneligible() {
        val base = weeklySubscriber()
        listOf(
            base.copy(yearlySwitchOffer = null),
            base.copy(activeSubscriptionProductID = yearly),
            base.copy(ownsLifetime = true),
            base.copy(hasPendingPurchase = true),
            base.copy(isPurchasing = true),
            base.copy(scheduledSubscriptionProductID = weekly),
            base.copy(isEntitlementStale = true),
            base.copy(connectionPhase = BillingConnectionPhase.UNAVAILABLE),
            base.copy(entitlement = VoxEntitlement.FREE, hasActiveSubscription = false, activeSubscriptionProductID = null),
            base.copy(entitlement = VoxEntitlement.FREE, hasActiveSubscription = false, activeSubscriptionProductID = null,
                hasSubscriptionAccessEnded = true, endedSubscriptionProductID = weekly),
        ).forEach { state -> assertNull(state.toString(), state.eligibleYearlySwitchOffer()) }
    }

    // endregion

    // region Copy state mapping

    private fun plan(plan: VoxPlan, price: String) = VoxPlanOption(plan, price, 1L, "USD", null, null, "token-${plan.name}")
    private val priced = listOf(plan(VoxPlan.YEARLY, "$29.99"), plan(VoxPlan.WEEKLY, "$0.99"), plan(VoxPlan.LIFETIME, "$49.99"))

    @Test fun statusFollowsOwnership() {
        assertEquals(
            SubscriptionStatus.Active(VoxPlan.WEEKLY, "$0.99", weeklyScheduled = false),
            subscriptionStatus(weeklySubscriber().copy(plans = priced)),
        )
        assertEquals(
            SubscriptionStatus.Active(VoxPlan.YEARLY, "$29.99", weeklyScheduled = true),
            subscriptionStatus(weeklySubscriber().copy(plans = priced, activeSubscriptionProductID = yearly, scheduledSubscriptionProductID = weekly)),
        )
        assertEquals(
            SubscriptionStatus.Lifetime("$49.99"),
            subscriptionStatus(weeklySubscriber().copy(plans = priced, ownsLifetime = true)),
        )
        assertEquals(
            SubscriptionStatus.Ended(VoxPlan.YEARLY),
            subscriptionStatus(BillingUiState(hasSubscriptionAccessEnded = true, endedSubscriptionProductID = yearly)),
        )
        assertEquals(SubscriptionStatus.Ended(null), subscriptionStatus(BillingUiState(hasSubscriptionAccessEnded = true)))
        assertEquals(SubscriptionStatus.Free, subscriptionStatus(BillingUiState()))
        // Prices are only ever Play's; a missing ProductDetails leaves the price out.
        assertEquals(SubscriptionStatus.Active(VoxPlan.WEEKLY, null, false), subscriptionStatus(weeklySubscriber()))
    }

    @Test fun settingsOpensSubscriptionOnlyWhenThereIsSomethingToShow() {
        assertFalse(opensSubscriptionScreen(BillingUiState()))
        assertTrue(opensSubscriptionScreen(weeklySubscriber()))
        assertTrue(opensSubscriptionScreen(BillingUiState(hasSubscriptionAccessEnded = true)))
        assertTrue(opensSubscriptionScreen(BillingUiState(entitlement = VoxEntitlement.UNLIMITED, ownsLifetime = true)))
    }

    @Test fun beforeYouGoNamesThePaidPeriodAndOffersTheSwitchToWeeklyOnly() {
        val weeklyCopy = assertNotNullCopy(beforeYouGoCopy(VoxPlan.WEEKLY, offer))
        assertEquals(
            voxUiText("Cancelling stops the next renewal. Unlimited stays on until the end of the week you’ve paid for; Google Play shows the date."),
            weeklyCopy.lead,
        )
        assertEquals(offer, weeklyCopy.switchOffer)
        assertNull(assertNotNullCopy(beforeYouGoCopy(VoxPlan.WEEKLY, null)).switchOffer)

        val yearlyCopy = assertNotNullCopy(beforeYouGoCopy(VoxPlan.YEARLY, offer))
        assertEquals(
            voxUiText("Cancelling stops the next renewal. Unlimited stays on until the end of the year you’ve paid for; Google Play shows the date."),
            yearlyCopy.lead,
        )
        assertNull(yearlyCopy.switchOffer)
        assertNull("Lifetime has no cancel path", beforeYouGoCopy(VoxPlan.LIFETIME, offer))
    }

    @Test fun lapseCopyMatchesTheAccessEndedGates() {
        val copy = assertNotNullCopy(beforeYouGoCopy(VoxPlan.YEARLY, null))
        assertEquals(lapseStops, copy.stops)
        assertEquals(lapseKeeps, copy.keeps)
        // A lapse does not restore the free allowance (AndroidCaptureRepository rejects new work).
        assertTrue(lapseStops.first().source.contains("free allowance doesn’t restart"))
        assertTrue(lapseStops.none { it.source.contains("%") })
        assertTrue(lapseKeeps.contains(voxUiText("Library: read, search, copy, export and delete.")))
        assertTrue(lapseStops.contains(voxUiText("Editing transcripts and adding them to a draft.")))
    }

    @Test fun pricesAndPlanNamesAreFormattedFromPlay() {
        assertEquals(voxUiText("%@ / week", "$0.99"), planPriceText(VoxPlan.WEEKLY, "$0.99"))
        assertEquals(voxUiText("%@ / year", "$29.99"), planPriceText(VoxPlan.YEARLY, "$29.99"))
        assertEquals(voxUiText("%@, once. No subscription.", "$49.99"), planPriceText(VoxPlan.LIFETIME, "$49.99"))
        assertEquals(voxUiText("Yearly at %@ for the first year", "$19.99"), switchOfferTitle(offer))
        assertEquals(
            voxUiText("Then %@ a year. Starts now; your unused weekly time is credited. Price from Google Play.", "$29.99"),
            switchOfferDetail(offer),
        )
        assertEquals(voxUiText("%@ · %@", voxUiText("Vox.md Unlimited"), voxUiText("Yearly")), endedPlanText(VoxPlan.YEARLY))
        assertEquals(voxUiText("Vox.md Unlimited"), endedPlanText(null))
    }

    @Test fun manageLinkTargetsTheSubscriptionAndPackage() {
        assertEquals(
            "https://play.google.com/store/account/subscriptions?sku=vox_unlimited_weekly&package=md.vox.android",
            VoxPlayCatalog.manageSubscriptionsUrl("md.vox.android", weekly),
        )
        assertEquals(
            "https://play.google.com/store/account/subscriptions?package=md.vox.android",
            VoxPlayCatalog.manageSubscriptionsUrl("md.vox.android", lifetime),
        )
    }

    // endregion

    private fun assertNotNullCopy(copy: BeforeYouGoCopy?): BeforeYouGoCopy {
        assertNotNull(copy)
        return copy!!
    }
}
