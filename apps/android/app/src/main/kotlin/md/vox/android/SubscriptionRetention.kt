package md.vox.android

/*
 * Subscription retention: lapse detection, the in-app Weekly -> Yearly switch offer, and the
 * copy shown on Settings > Subscription, the "Before you go" sheet and the "Subscription ended"
 * state. Everything here is pure so it can be unit tested without Play or Compose.
 *
 * The copy states what the app actually does after a lapse. Once Play authoritatively reports
 * that a previously verified subscription is gone, `hasSubscriptionAccessEnded` is set and:
 * - AndroidCaptureRepository rejects every new capture ("new work must not use a fresh free
 *   allowance after authoritative subscription loss"), whichever surface submitted it;
 * - the Capture tab, recording start and keyboard voice input are blocked;
 * - transcript editing and "Add to draft" are disabled (TranscriptDetailScreen isReadOnly);
 * - Library keeps read, search, copy (Copy Markdown), export, share and delete;
 * - captures already saved on the phone keep delivering, and recordings that have not been
 *   transcribed keep their audio (retention only deletes audio after a completed transcript).
 * So a lapsed subscriber does not get the free allowance back. If that gate changes, change
 * [lapseStops] and the Ended screen with it.
 */

// region Lapse detection

/**
 * Whether paid subscription access has ended, and which subscription it was. Persisted through
 * the signed [PlayEntitlementCache]: a negative record keeps the last verified subscription
 * product ID, so the state survives restarts without trusting an unsigned flag.
 */
internal data class SubscriptionLapse(
    val hasEnded: Boolean,
    /** Weekly or Yearly product that lapsed, when known. */
    val endedProductID: String? = null,
) {
    companion object {
        val None = SubscriptionLapse(hasEnded = false)
    }
}

/** Cold-start lapse state from the signed evidence of the last authoritative Play query. */
internal fun subscriptionLapseFromEvidence(evidence: CachedPlayEntitlement?): SubscriptionLapse =
    if (evidence != null && !evidence.isOwned && evidence.productID in VoxPlayCatalog.SUBSCRIPTION_PRODUCT_IDS) {
        SubscriptionLapse(hasEnded = true, endedProductID = evidence.productID)
    } else {
        SubscriptionLapse.None
    }

/**
 * Lapse state after an ownership observation. Only a complete, authoritative "not owned" answer
 * can end access, and only for someone who had a verified subscription before; an incomplete
 * answer (null) keeps the previous state; any owned purchase clears it.
 */
internal fun subscriptionLapseAfterOwnershipQuery(
    prior: SubscriptionLapse,
    priorActiveSubscriptionProductID: String?,
    authoritativeOwned: Boolean?,
): SubscriptionLapse {
    val ended = subscriptionAccessEnded(
        previouslyEnded = prior.hasEnded,
        previouslyOwnedSubscription = priorActiveSubscriptionProductID != null,
        authoritativeOwned = authoritativeOwned,
    )
    if (!ended) return SubscriptionLapse.None
    val product = if (authoritativeOwned == false) {
        priorActiveSubscriptionProductID ?: prior.endedProductID
    } else {
        prior.endedProductID
    }
    return SubscriptionLapse(true, product?.takeIf { it in VoxPlayCatalog.SUBSCRIPTION_PRODUCT_IDS })
}

// endregion

// region Weekly -> Yearly switch offer

/** The app-funded Yearly offer for Weekly subscribers, priced only from Play's ProductDetails. */
data class VoxYearlySwitchOffer(
    val offerToken: String,
    /** First-year price of the offer phase. */
    val introductoryFormattedPrice: String,
    /** Yearly base price that applies after the first year. */
    val recurringFormattedPrice: String,
)

/**
 * Picks the `switch-yearly-1y` offer on the Yearly base plan when Play returned it with the
 * `retention-in-app` tag. The copy promises "for the first year, then the Yearly price", so the
 * offer must be exactly one discounted P1Y phase followed by the recurring Yearly price in the
 * same currency; anything else hides the card rather than misdescribing it.
 */
internal fun yearlySwitchOffer(offers: Collection<PlaySubscriptionOffer>): VoxYearlySwitchOffer? {
    val offer = offers.firstOrNull {
        it.productID == VoxPlayCatalog.YEARLY_PRODUCT_ID &&
            it.basePlanID == VoxPlayCatalog.YEARLY_BASE_PLAN_ID &&
            it.offerID == VoxPlayCatalog.SWITCH_YEARLY_OFFER_ID &&
            VoxPlayCatalog.RETENTION_IN_APP_OFFER_TAG in it.offerTags &&
            it.offerToken.isNotBlank()
    } ?: return null
    if (offer.phases.size != 2) return null
    val (intro, recurring) = offer.phases
    if (intro.isInfiniteRecurring || intro.billingCycleCount != 1 || isoPeriodDays(intro.billingPeriod) != 365) return null
    if (!recurring.isInfiniteRecurring || isoPeriodDays(recurring.billingPeriod) != 365) return null
    if (intro.currencyCode != recurring.currencyCode) return null
    if (intro.priceAmountMicros <= 0 || intro.priceAmountMicros >= recurring.priceAmountMicros) return null
    return VoxYearlySwitchOffer(offer.offerToken, intro.formattedPrice, recurring.formattedPrice)
}

/**
 * The switch offer this person may take now: an active, verified Weekly subscriber with nothing
 * pending or scheduled, while Play is connected. Lifetime owners, Yearly subscribers and lapsed
 * or free users never see it.
 */
internal fun BillingUiState.eligibleYearlySwitchOffer(): VoxYearlySwitchOffer? = yearlySwitchOffer?.takeIf {
    hasUnlimitedAccess &&
        hasActiveSubscription &&
        !ownsLifetime &&
        activeSubscriptionProductID == VoxPlayCatalog.WEEKLY_PRODUCT_ID &&
        scheduledSubscriptionProductID == null &&
        !isEntitlementStale &&
        canPurchase()
}

// endregion

// region Copy state

/** What Settings > Subscription shows. */
internal sealed interface SubscriptionStatus {
    /** Weekly or Yearly, renewing through Google Play. */
    data class Active(val plan: VoxPlan, val formattedPrice: String?, val weeklyScheduled: Boolean) : SubscriptionStatus
    data class Lifetime(val formattedPrice: String?) : SubscriptionStatus
    /** A previously verified subscription has lapsed; [plan] is null when the product is unknown. */
    data class Ended(val plan: VoxPlan?) : SubscriptionStatus
    data object Free : SubscriptionStatus
}

internal fun subscriptionStatus(state: BillingUiState): SubscriptionStatus {
    fun price(plan: VoxPlan) = state.plans.firstOrNull { it.plan == plan }?.formattedPrice
    val active = VoxPlan.entries.firstOrNull { it.isSubscription && it.productID == state.activeSubscriptionProductID }
    return when {
        state.ownsLifetime -> SubscriptionStatus.Lifetime(price(VoxPlan.LIFETIME))
        state.hasUnlimitedAccess && active != null -> SubscriptionStatus.Active(
            plan = active,
            formattedPrice = price(active),
            weeklyScheduled = state.scheduledSubscriptionProductID == VoxPlayCatalog.WEEKLY_PRODUCT_ID && active != VoxPlan.WEEKLY,
        )
        state.hasSubscriptionAccessEnded -> SubscriptionStatus.Ended(
            VoxPlan.entries.firstOrNull { it.isSubscription && it.productID == state.endedSubscriptionProductID },
        )
        else -> SubscriptionStatus.Free
    }
}

/** Opens Settings > Subscription instead of the paywall once there is a purchase to show. */
internal fun opensSubscriptionScreen(state: BillingUiState): Boolean =
    subscriptionStatus(state) != SubscriptionStatus.Free || state.hasActiveSubscription

internal fun planNameText(plan: VoxPlan): VoxUiText = when (plan) {
    VoxPlan.WEEKLY -> voxUiText("Weekly")
    VoxPlan.YEARLY -> voxUiText("Yearly")
    VoxPlan.LIFETIME -> voxUiText("Lifetime")
}

/** "$4.99 / week", "$29.99 / year", or the Lifetime price as is. */
internal fun planPriceText(plan: VoxPlan, formattedPrice: String): VoxUiText = when (plan) {
    VoxPlan.WEEKLY -> voxUiText("%@ / week", formattedPrice)
    VoxPlan.YEARLY -> voxUiText("%@ / year", formattedPrice)
    VoxPlan.LIFETIME -> voxUiText("%@, once. No subscription.", formattedPrice)
}

/** What a lapse stops, as enforced by the access-ended gates (see the file header). */
internal val lapseStops: List<VoxUiText> = listOf(
    voxUiText("New captures and recordings, until you subscribe again. The free allowance doesn’t restart."),
    voxUiText("Captures from the keyboard, widget, Quick Settings and Wear OS stop too."),
    voxUiText("Editing transcripts and adding them to a draft."),
)

/** What a lapse keeps. Library actions match the read-only Library gate. */
internal val lapseKeeps: List<VoxUiText> = listOf(
    voxUiText("Every note already delivered. It’s plain Markdown in your folder."),
    voxUiText("Library: read, search, copy, export and delete."),
    voxUiText("Captures already saved on this phone finish delivering."),
    voxUiText("Recordings not yet transcribed keep their audio on this phone."),
)

internal data class BeforeYouGoCopy(
    val lead: VoxUiText,
    val stops: List<VoxUiText>,
    val keeps: List<VoxUiText>,
    /** Shown only to Weekly subscribers with an eligible offer from Play. */
    val switchOffer: VoxYearlySwitchOffer?,
)

/** "Before you go" for a renewing subscription; null for Lifetime, which has nothing to cancel. */
internal fun beforeYouGoCopy(plan: VoxPlan, eligibleSwitchOffer: VoxYearlySwitchOffer?): BeforeYouGoCopy? = when (plan) {
    VoxPlan.LIFETIME -> null
    VoxPlan.WEEKLY -> BeforeYouGoCopy(
        lead = voxUiText("Cancelling stops the next renewal. Unlimited stays on until the end of the week you’ve paid for; Google Play shows the date."),
        stops = lapseStops,
        keeps = lapseKeeps,
        switchOffer = eligibleSwitchOffer,
    )
    VoxPlan.YEARLY -> BeforeYouGoCopy(
        lead = voxUiText("Cancelling stops the next renewal. Unlimited stays on until the end of the year you’ve paid for; Google Play shows the date."),
        stops = lapseStops,
        keeps = lapseKeeps,
        switchOffer = null,
    )
}

internal fun switchOfferTitle(offer: VoxYearlySwitchOffer): VoxUiText =
    voxUiText("Yearly at %@ for the first year", offer.introductoryFormattedPrice)

internal fun switchOfferDetail(offer: VoxYearlySwitchOffer): VoxUiText =
    voxUiText("Then %@ a year. Starts now; your unused weekly time is credited. Price from Google Play.", offer.recurringFormattedPrice)

/** Second line of the ended card: "Vox.md Unlimited · Yearly", or just the product name. */
internal fun endedPlanText(plan: VoxPlan?): VoxUiText =
    plan?.let { voxUiText("%@ · %@", voxUiText("Vox.md Unlimited"), planNameText(it)) } ?: voxUiText("Vox.md Unlimited")

// endregion
