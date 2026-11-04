package md.vox.android

import java.text.NumberFormat
import java.util.Locale

/**
 * Every Google Play identifier Vox.md uses, in one place, matching the live Play Console
 * catalog. Individual plans only: Play has no counterpart to Apple Family Sharing, so the
 * iOS Family products have no Android equivalent.
 *
 * | Play Console object                   | ID                       | iOS counterpart                       |
 * |---------------------------------------|--------------------------|---------------------------------------|
 * | One-time product (Lifetime)           | `vox_unlimited_lifetime` | `bontecou.Voxboard.unlock`            |
 * | Subscription product (Weekly)         | `vox_unlimited_weekly`   | `bontecou.Voxboard.individual.weekly` |
 * |   base plan, auto-renewing P1W        | `weekly`                 |                                       |
 * |   offer: 1 week free                  | `free-trial-1w`          | intro offer `individual-weekly-trial` |
 * | Subscription product (Yearly)         | `vox_unlimited_yearly`   | `bontecou.Voxboard.individual.yearly` |
 * |   base plan, auto-renewing P1Y        | `yearly`                 |                                       |
 * |   offer: 1 week free                  | `free-trial-1w`          | intro offer `individual-yearly-trial` |
 *
 * The two subscription products correspond to the iOS "Vox.md Unlimited" subscription
 * group; moving between them replaces the active subscription. Prices, currencies, trial
 * length and trial eligibility are never hard-coded: they come only from the
 * `ProductDetails` offers Play returns, and Play omits a trial offer for a customer who is
 * not eligible.
 */
object VoxPlayCatalog {
    const val LIFETIME_PRODUCT_ID = "vox_unlimited_lifetime"
    const val WEEKLY_PRODUCT_ID = "vox_unlimited_weekly"
    const val YEARLY_PRODUCT_ID = "vox_unlimited_yearly"
    const val WEEKLY_BASE_PLAN_ID = "weekly"
    const val YEARLY_BASE_PLAN_ID = "yearly"
    const val FREE_TRIAL_OFFER_ID = "free-trial-1w"
    val SUBSCRIPTION_PRODUCT_IDS: List<String> = listOf(YEARLY_PRODUCT_ID, WEEKLY_PRODUCT_ID)

    /** Play's subscription center, scoped to the active subscription product when known. */
    fun manageSubscriptionsUrl(packageName: String, subscriptionProductID: String?): String =
        if (subscriptionProductID != null && subscriptionProductID in SUBSCRIPTION_PRODUCT_IDS) {
            "https://play.google.com/store/account/subscriptions?sku=$subscriptionProductID&package=$packageName"
        } else {
            "https://play.google.com/store/account/subscriptions?package=$packageName"
        }
}

/** What a person can buy, in the order the plans page lists them. */
enum class VoxPlan(val productID: String, val basePlanID: String?, val trialOfferID: String?) {
    YEARLY(VoxPlayCatalog.YEARLY_PRODUCT_ID, VoxPlayCatalog.YEARLY_BASE_PLAN_ID, VoxPlayCatalog.FREE_TRIAL_OFFER_ID),
    WEEKLY(VoxPlayCatalog.WEEKLY_PRODUCT_ID, VoxPlayCatalog.WEEKLY_BASE_PLAN_ID, VoxPlayCatalog.FREE_TRIAL_OFFER_ID),
    LIFETIME(VoxPlayCatalog.LIFETIME_PRODUCT_ID, null, null),
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
    val productID: String,
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
        val forPlan = offers.filter {
            it.productID == plan.productID && it.basePlanID == plan.basePlanID && it.offerToken.isNotBlank()
        }
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
            freeTrialPeriod = trial?.let(::freeTrialPhase)?.let(::totalTrialPeriod),
            offerToken = chosen.offerToken,
        )
    }

private fun freeTrialPhase(offer: PlaySubscriptionOffer): PlayPricingPhase? =
    offer.phases.firstOrNull { it.priceAmountMicros == 0L && it.billingCycleCount >= 1 && !it.isInfiniteRecurring }

/** A free phase repeated for several cycles (for example 2 x P1W) as one ISO period. */
private fun totalTrialPeriod(phase: PlayPricingPhase): String {
    val cycles = phase.billingCycleCount.coerceAtLeast(1)
    if (cycles == 1) return phase.billingPeriod
    return isoPeriodDays(phase.billingPeriod)?.let { "P${it * cycles}D" } ?: phase.billingPeriod
}

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
    // Rounded down, as on iOS, so the badge never overstates the saving.
    val percent = kotlin.math.floor((1 - yearly.priceAmountMicros / weeklyYear) * 100).toInt()
    return percent.takeIf { it in 1..99 }
}

internal fun formatSavingsPercent(percent: Int, locale: Locale = Locale.getDefault()): String =
    NumberFormat.getPercentInstance(locale).format(percent / 100.0)

/** How a selected plan would be bought from the current ownership. */
internal sealed interface VoxPurchaseRequest {
    data class Lifetime(val offerToken: String) : VoxPurchaseRequest
    data class NewSubscription(val offerToken: String) : VoxPurchaseRequest
    /** Move to the other subscription product with [mode]. */
    data class ReplaceSubscription(
        val offerToken: String,
        val oldPurchaseToken: String,
        val mode: VoxReplacementMode = VoxReplacementMode.WITH_TIME_PRORATION,
    ) : VoxPurchaseRequest
    data class Blocked(val reason: String) : VoxPurchaseRequest
}

/**
 * How a Weekly <-> Yearly switch replaces the active purchase: moving up to Yearly takes
 * effect now and credits the unused weekly time; moving down to Weekly waits for the next
 * yearly renewal, so nothing already paid for is cut short.
 */
enum class VoxReplacementMode { WITH_TIME_PRORATION, DEFERRED }

internal fun replacementModeFor(fromProductID: String?, to: VoxPlan): VoxReplacementMode =
    if (fromProductID == VoxPlayCatalog.YEARLY_PRODUCT_ID && to == VoxPlan.WEEKLY) {
        VoxReplacementMode.DEFERRED
    } else {
        VoxReplacementMode.WITH_TIME_PRORATION
    }

/** Days before the end of a free trial that the reminder notification is sent. */
internal const val TRIAL_REMINDER_LEAD_DAYS = 2

/** Trial day on which the reminder fires; null when the trial is too short for one. */
internal fun trialReminderDay(trialDays: Int): Int? = (trialDays - TRIAL_REMINDER_LEAD_DAYS).takeIf { it >= 1 }

/**
 * Lifetime owners never buy again; an active subscriber switching between Weekly and
 * Yearly replaces the existing subscription instead of opening a second one, cannot buy
 * the product they already have (or have already scheduled), and can still move to Lifetime.
 */
internal fun voxPurchaseRequest(
    option: VoxPlanOption?,
    ownsLifetime: Boolean,
    activeSubscriptionToken: String?,
    hasPendingPurchase: Boolean,
    activeSubscriptionProductID: String? = null,
    scheduledSubscriptionProductID: String? = null,
): VoxPurchaseRequest = when {
    option == null -> VoxPurchaseRequest.Blocked("productUnavailable")
    ownsLifetime -> VoxPurchaseRequest.Blocked("alreadyOwned")
    hasPendingPurchase -> VoxPurchaseRequest.Blocked("pending")
    option.plan == VoxPlan.LIFETIME -> VoxPurchaseRequest.Lifetime(option.offerToken)
    activeSubscriptionToken != null && option.plan.productID == scheduledSubscriptionProductID ->
        VoxPurchaseRequest.Blocked("alreadyScheduled")
    activeSubscriptionToken != null && option.plan.productID == activeSubscriptionProductID ->
        VoxPurchaseRequest.Blocked("alreadySubscribed")
    activeSubscriptionToken != null -> VoxPurchaseRequest.ReplaceSubscription(
        option.offerToken,
        activeSubscriptionToken,
        replacementModeFor(activeSubscriptionProductID, option.plan),
    )
    else -> VoxPurchaseRequest.NewSubscription(option.offerToken)
}
