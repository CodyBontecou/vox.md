package md.vox.android

import java.text.NumberFormat
import java.util.Locale
import kotlin.math.roundToInt

/**
 * Every Google Play identifier Vox.md uses, in one place, so the Play Console catalog can
 * be created to match. Individual plans only: Play has no counterpart to Apple Family
 * Sharing, so the iOS Family products have no Android equivalent.
 *
 * | Play Console object              | ID                         | iOS counterpart                        |
 * |----------------------------------|----------------------------|----------------------------------------|
 * | One-time product (Lifetime)      | `vox_unlimited_lifetime`   | `bontecou.Voxboard.unlock`             |
 * | Subscription                     | `vox_unlimited_individual` | group "Vox.md Unlimited"               |
 * | Base plan, auto-renewing P1W     | `individual-weekly`        | `bontecou.Voxboard.individual.weekly`  |
 * | Base plan, auto-renewing P1Y     | `individual-yearly`        | `bontecou.Voxboard.individual.yearly`  |
 * | Offer on weekly: 7-day free trial| `individual-weekly-trial`  | intro offer `individual-weekly-trial`  |
 * | Offer on yearly: 7-day free trial| `individual-yearly-trial`  | intro offer `individual-yearly-trial`  |
 *
 * Prices, currencies, trial length and trial eligibility are never hard-coded: they come
 * only from the `ProductDetails` offers Play returns. Play omits a trial offer for a
 * customer who is not eligible (eligibility is configured on the offer as "new customers").
 */
object VoxPlayCatalog {
    const val LIFETIME_PRODUCT_ID = "vox_unlimited_lifetime"
    const val SUBSCRIPTION_PRODUCT_ID = "vox_unlimited_individual"
    const val WEEKLY_BASE_PLAN_ID = "individual-weekly"
    const val YEARLY_BASE_PLAN_ID = "individual-yearly"
    const val WEEKLY_TRIAL_OFFER_ID = "individual-weekly-trial"
    const val YEARLY_TRIAL_OFFER_ID = "individual-yearly-trial"

    /** Play's subscription center, scoped to the Vox.md subscription. */
    fun manageSubscriptionsUrl(packageName: String): String =
        "https://play.google.com/store/account/subscriptions?sku=$SUBSCRIPTION_PRODUCT_ID&package=$packageName"
}

/** What a person can buy, in the order the plans page lists them. */
enum class VoxPlan(val basePlanID: String?, val trialOfferID: String?) {
    YEARLY(VoxPlayCatalog.YEARLY_BASE_PLAN_ID, VoxPlayCatalog.YEARLY_TRIAL_OFFER_ID),
    WEEKLY(VoxPlayCatalog.WEEKLY_BASE_PLAN_ID, VoxPlayCatalog.WEEKLY_TRIAL_OFFER_ID),
    LIFETIME(null, null),
    ;

    val isSubscription: Boolean get() = basePlanID != null
}

/** Play-independent copy of one `ProductDetails.PricingPhase`. */
data class PlayPricingPhase(
    val formattedPrice: String,
    val priceAmountMicros: Long,
    val currencyCode: String,
    /** ISO-8601 period such as `P1W` or `P1Y`. */
    val billingPeriod: String,
    val billingCycleCount: Int,
    val isInfiniteRecurring: Boolean,
)

/** Play-independent copy of one `ProductDetails.SubscriptionOfferDetails`. */
data class PlaySubscriptionOffer(
    val basePlanID: String,
    val offerID: String?,
    val offerToken: String,
    val phases: List<PlayPricingPhase>,
)

/** A purchasable plan, priced from Play's own offers. */
data class VoxPlanOption(
    val plan: VoxPlan,
    val formattedPrice: String,
    val priceAmountMicros: Long,
    val currencyCode: String,
    /** ISO-8601 renewal period for subscriptions; null for Lifetime. */
    val billingPeriod: String?,
    /** ISO-8601 length of the free trial this customer is eligible for, if any. */
    val freeTrialPeriod: String?,
    val offerToken: String,
) {
    val hasFreeTrial: Boolean get() = freeTrialPeriod != null
}

/**
 * Picks, for each base plan, the eligible free-trial offer when Play returned one and
 * otherwise the plain base-plan offer, and prices it from its recurring phase.
 */
internal fun subscriptionPlanOptions(offers: Collection<PlaySubscriptionOffer>): List<VoxPlanOption> =
    listOf(VoxPlan.YEARLY, VoxPlan.WEEKLY).mapNotNull { plan ->
        val forPlan = offers.filter { it.basePlanID == plan.basePlanID && it.offerToken.isNotBlank() }
        val trial = forPlan.firstOrNull { it.offerID == plan.trialOfferID && freeTrialPhase(it) != null }
        val base = forPlan.firstOrNull { it.offerID == null }
        val chosen = trial ?: base ?: return@mapNotNull null
        val recurring = chosen.phases.lastOrNull { it.isInfiniteRecurring && it.priceAmountMicros > 0 }
            ?: return@mapNotNull null
        VoxPlanOption(
            plan = plan,
            formattedPrice = recurring.formattedPrice,
            priceAmountMicros = recurring.priceAmountMicros,
            currencyCode = recurring.currencyCode,
            billingPeriod = recurring.billingPeriod,
            freeTrialPeriod = trial?.let(::freeTrialPhase)?.billingPeriod,
            offerToken = chosen.offerToken,
        )
    }

private fun freeTrialPhase(offer: PlaySubscriptionOffer): PlayPricingPhase? =
    offer.phases.firstOrNull { it.priceAmountMicros == 0L && it.billingCycleCount >= 1 && !it.isInfiniteRecurring }

/** Length of an ISO-8601 period in days, for the common P{n}D / P{n}W / P{n}M / P{n}Y forms. */
internal fun isoPeriodDays(period: String?): Int? {
    val match = Regex("^P(\\d+)([DWMY])$").matchEntire(period ?: return null) ?: return null
    val count = match.groupValues[1].toIntOrNull() ?: return null
    return when (match.groupValues[2]) {
        "D" -> count
        "W" -> count * 7
        "M" -> count * 30
        "Y" -> count * 365
        else -> null
    }
}

/**
 * Percentage saved by paying yearly instead of 52 weekly renewals, from real Play prices.
 * Null when the currencies differ, a price is missing, or there is no saving to show.
 */
internal fun yearlySavingsPercent(weekly: VoxPlanOption?, yearly: VoxPlanOption?): Int? {
    if (weekly == null || yearly == null) return null
    if (weekly.currencyCode != yearly.currencyCode) return null
    if (isoPeriodDays(weekly.billingPeriod) != 7 || isoPeriodDays(yearly.billingPeriod) != 365) return null
    if (weekly.priceAmountMicros <= 0 || yearly.priceAmountMicros <= 0) return null
    val weeklyYear = weekly.priceAmountMicros.toDouble() * 52
    val percent = ((1 - yearly.priceAmountMicros / weeklyYear) * 100).roundToInt()
    return percent.takeIf { it in 1..99 }
}

internal fun formatSavingsPercent(percent: Int, locale: Locale = Locale.getDefault()): String =
    NumberFormat.getPercentInstance(locale).format(percent / 100.0)

/** How a selected plan would be bought from the current ownership. */
internal sealed interface VoxPurchaseRequest {
    data class Lifetime(val offerToken: String) : VoxPurchaseRequest
    data class NewSubscription(val offerToken: String) : VoxPurchaseRequest
    /** Switch the active base plan; Play prorates the remaining time. */
    data class ReplaceSubscription(val offerToken: String, val oldPurchaseToken: String) : VoxPurchaseRequest
    data class Blocked(val reason: String) : VoxPurchaseRequest
}

/**
 * Lifetime owners never buy again; an active subscriber switching base plans replaces the
 * existing subscription instead of opening a second one, and can still move to Lifetime.
 */
internal fun voxPurchaseRequest(
    option: VoxPlanOption?,
    ownsLifetime: Boolean,
    activeSubscriptionToken: String?,
    hasPendingPurchase: Boolean,
): VoxPurchaseRequest = when {
    option == null -> VoxPurchaseRequest.Blocked("productUnavailable")
    ownsLifetime -> VoxPurchaseRequest.Blocked("alreadyOwned")
    hasPendingPurchase -> VoxPurchaseRequest.Blocked("pending")
    option.plan == VoxPlan.LIFETIME -> VoxPurchaseRequest.Lifetime(option.offerToken)
    activeSubscriptionToken != null -> VoxPurchaseRequest.ReplaceSubscription(option.offerToken, activeSubscriptionToken)
    else -> VoxPurchaseRequest.NewSubscription(option.offerToken)
}
