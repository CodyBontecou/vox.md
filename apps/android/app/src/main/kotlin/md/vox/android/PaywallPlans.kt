package md.vox.android

import java.time.Period
import java.time.format.DateTimeParseException

/** The three Unlimited plans the paywall can sell, in display order. */
enum class PaywallPlanKind(val productID: String, val isSubscription: Boolean) {
    YEARLY(PlayBillingManager.YEARLY_PRODUCT_ID, isSubscription = true),
    WEEKLY(PlayBillingManager.WEEKLY_PRODUCT_ID, isSubscription = true),
    LIFETIME(PlayBillingManager.LIFETIME_PRODUCT_ID, isSubscription = false),
    ;

    companion object {
        fun forProductID(productID: String): PaywallPlanKind? = entries.firstOrNull { it.productID == productID }
    }
}

/**
 * A plan as loaded from Play ProductDetails. Prices are Play's localized strings and micros;
 * nothing here is hardcoded. [offerToken] is required to launch a subscription purchase.
 */
data class PaywallPlan(
    val kind: PaywallPlanKind,
    /** The recurring (or one-time) price, already localized by Play. */
    val formattedPrice: String,
    val priceAmountMicros: Long,
    val currencyCode: String,
    val offerToken: String? = null,
    /** Non-null only when Play returned an eligible offer with a free pricing phase. */
    val freeTrialDays: Int? = null,
) {
    val hasFreeTrial: Boolean get() = freeTrialDays != null && freeTrialDays > 0
}

/** Play-independent mirror of `ProductDetails.PricingPhase`, so offer selection is unit-testable. */
data class PaywallPricingPhase(
    val priceAmountMicros: Long,
    val formattedPrice: String,
    val currencyCode: String,
    /** ISO-8601 period such as P1W, P7D, P1Y. */
    val billingPeriod: String,
    val billingCycleCount: Int,
    val recurrenceMode: Int,
)

/** Play-independent mirror of `ProductDetails.SubscriptionOfferDetails`. */
data class PaywallOfferCandidate(
    val basePlanID: String,
    /** Null for the base-plan offer itself. */
    val offerID: String?,
    val offerToken: String,
    val phases: List<PaywallPricingPhase>,
)

data class SelectedSubscriptionOffer(
    val offerToken: String,
    val recurringPhase: PaywallPricingPhase,
    val freeTrialDays: Int?,
)

/** `ProductDetails.RecurrenceMode.INFINITE_RECURRING`. */
internal const val RECURRENCE_INFINITE = 1

/**
 * Picks the offer to sell. Play only returns offers the account is eligible for, so an offer with a
 * free pricing phase is an eligible free trial; otherwise the base plan (no offer ID) is used.
 */
internal fun selectSubscriptionOffer(candidates: List<PaywallOfferCandidate>): SelectedSubscriptionOffer? {
    val usable = candidates.filter { candidate ->
        candidate.offerToken.isNotBlank() && recurringPhase(candidate.phases) != null
    }
    if (usable.isEmpty()) return null
    val trial = usable.firstNotNullOfOrNull { candidate ->
        val freePhase = candidate.phases.firstOrNull { it.priceAmountMicros == 0L } ?: return@firstNotNullOfOrNull null
        val days = freeTrialDays(freePhase) ?: return@firstNotNullOfOrNull null
        candidate to days
    }
    if (trial != null) {
        val (candidate, days) = trial
        return SelectedSubscriptionOffer(candidate.offerToken, requireNotNull(recurringPhase(candidate.phases)), days)
    }
    val base = usable.firstOrNull { it.offerID == null } ?: usable.first()
    return SelectedSubscriptionOffer(base.offerToken, requireNotNull(recurringPhase(base.phases)), freeTrialDays = null)
}

private fun recurringPhase(phases: List<PaywallPricingPhase>): PaywallPricingPhase? =
    phases.lastOrNull { it.recurrenceMode == RECURRENCE_INFINITE && it.priceAmountMicros > 0 }
        ?: phases.lastOrNull { it.priceAmountMicros > 0 }

/** Length of a free phase in days (period × cycle count), or null when it is not parseable. */
internal fun freeTrialDays(phase: PaywallPricingPhase): Int? {
    val days = isoPeriodDays(phase.billingPeriod) ?: return null
    val total = days * phase.billingCycleCount.coerceAtLeast(1)
    return total.takeIf { it > 0 }
}

internal fun isoPeriodDays(period: String): Int? = try {
    val parsed = Period.parse(period)
    parsed.years * 365 + parsed.months * 30 + parsed.days
} catch (_: DateTimeParseException) {
    null
}.takeIf { it != null && it > 0 }

/**
 * Yearly savings versus paying weekly for 52 weeks, as a whole percent rounded down:
 * `floor((1 - yearly / (weekly × 52)) × 100)`. Null when either price is missing, the currencies
 * differ, or yearly does not save anything, so the badge is hidden.
 */
internal fun yearlySavingsPercent(yearly: PaywallPlan?, weekly: PaywallPlan?): Int? {
    if (yearly == null || weekly == null) return null
    if (yearly.currencyCode != weekly.currencyCode) return null
    return yearlySavingsPercent(yearly.priceAmountMicros, weekly.priceAmountMicros)
}

internal fun yearlySavingsPercent(yearlyMicros: Long, weeklyMicros: Long): Int? {
    if (yearlyMicros <= 0L || weeklyMicros <= 0L) return null
    val weeklyAnnual = weeklyMicros.toBigInteger() * 52.toBigInteger()
    val saved = weeklyAnnual - yearlyMicros.toBigInteger()
    if (saved.signum() <= 0) return null
    val percent = (saved * 100.toBigInteger() / weeklyAnnual).toInt()
    return percent.takeIf { it > 0 }
}

/** Default selection: Yearly, then Weekly, then Lifetime, whichever loaded first. */
internal fun defaultPaywallPlanKind(plans: List<PaywallPlan>): PaywallPlanKind =
    PaywallPlanKind.entries.firstOrNull { kind -> plans.any { it.kind == kind } } ?: PaywallPlanKind.YEARLY

/** Plan the trial timeline describes: the selected one if it has a trial, else any plan with a trial. */
internal fun trialTimelinePlan(plans: List<PaywallPlan>, selected: PaywallPlanKind): PaywallPlan? =
    plans.firstOrNull { it.kind == selected && it.hasFreeTrial }
        ?: PaywallPlanKind.entries.firstNotNullOfOrNull { kind -> plans.firstOrNull { it.kind == kind && it.hasFreeTrial } }

/** One-line billing summary under the page dots. Null when the plan did not load. */
internal fun paywallSummary(plan: PaywallPlan?): VoxUiText? {
    plan ?: return null
    val trialDays = plan.freeTrialDays?.takeIf { it > 0 }
    return when (plan.kind) {
        PaywallPlanKind.LIFETIME -> voxUiText("%@, once. No subscription.", plan.formattedPrice)
        PaywallPlanKind.YEARLY -> if (trialDays != null) {
            voxUiText("%lld days free, then %@/yr. Auto-renews.", trialDays, plan.formattedPrice)
        } else {
            voxUiText("%@/yr, renews automatically", plan.formattedPrice)
        }
        PaywallPlanKind.WEEKLY -> if (trialDays != null) {
            voxUiText("%lld days free, then %@/wk. Auto-renews.", trialDays, plan.formattedPrice)
        } else {
            voxUiText("%@/wk, renews automatically", plan.formattedPrice)
        }
    }
}

/** Primary button label for a free installation. */
internal fun paywallCallToAction(plan: PaywallPlan?, entitlement: VoxEntitlement): VoxUiText = when {
    entitlement == VoxEntitlement.UNLIMITED -> voxUiText("Unlimited Active")
    entitlement == VoxEntitlement.PENDING -> voxUiText("Purchase Pending")
    plan == null -> voxUiText("Unlock Unlimited")
    plan.kind == PaywallPlanKind.LIFETIME -> voxUiText("Unlock for %@", plan.formattedPrice)
    plan.hasFreeTrial -> voxUiText("Start %lld-day free trial", requireNotNull(plan.freeTrialDays))
    else -> voxUiText("Subscribe")
}

/** Secondary line inside a plan row. */
internal fun paywallPlanNote(kind: PaywallPlanKind, plan: PaywallPlan?): VoxUiText {
    if (plan == null) return voxUiText("Not available right now")
    val trialDays = plan.freeTrialDays?.takeIf { it > 0 }
    return when (kind) {
        PaywallPlanKind.LIFETIME -> voxUiText("One purchase, no renewals")
        PaywallPlanKind.YEARLY -> if (trialDays != null) {
            voxUiText("%lld days free, then %@/yr", trialDays, plan.formattedPrice)
        } else {
            voxUiText("%@/yr, renews automatically", plan.formattedPrice)
        }
        PaywallPlanKind.WEEKLY -> if (trialDays != null) {
            voxUiText("%lld days free, then %@/wk", trialDays, plan.formattedPrice)
        } else {
            voxUiText("%@/wk, renews automatically", plan.formattedPrice)
        }
    }
}

internal fun paywallPlanTitle(kind: PaywallPlanKind): VoxUiText = when (kind) {
    PaywallPlanKind.YEARLY -> voxUiText("Yearly")
    PaywallPlanKind.WEEKLY -> voxUiText("Weekly")
    PaywallPlanKind.LIFETIME -> voxUiText("Lifetime")
}

/** Day the reminder fires: two days before the trial ends (day 5 of a 7-day trial). */
internal fun trialReminderDay(trialDays: Int): Int? = (trialDays - TRIAL_REMINDER_LEAD_DAYS).takeIf { it >= 1 }

internal const val TRIAL_REMINDER_LEAD_DAYS = 2
