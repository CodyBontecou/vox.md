package md.vox.android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import com.google.android.play.core.ktx.launchReview
import com.google.android.play.core.ktx.requestReview
import com.google.android.play.core.review.ReviewManager
import com.google.android.play.core.review.ReviewManagerFactory
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.withTimeout
import md.vox.android.capturedomain.ActivityDay

/**
 * When Vox.md may ask Google Play for a rating. Same rules as iOS
 * (`Voxboard App Shared/ReviewPromptManager.swift`); change both together.
 *
 * - At least 5 delivered captures, on at least 2 different local days.
 * - Active access: a subscription, trial or lifetime purchase. Read-only
 *   users whose access ended are never asked.
 * - At most once per app version, and never within 90 days of the last request.
 * - Only right after an in-app success the user saw, once nothing else is on
 *   screen. Otherwise the moment is skipped; the next success can try.
 *
 * There is no custom pre-prompt: Play decides whether its card shows.
 */
internal object ReviewPromptPolicy {
    const val DELIVERED_CAPTURE_THRESHOLD = 5
    const val DELIVERY_DAY_THRESHOLD = 2
    const val COOLDOWN_MILLIS = 90L * 24 * 60 * 60 * 1000

    data class State(
        val deliveredCaptureCount: Int,
        val deliveryDayCount: Int,
        val lastRequestedAtEpochMillis: Long?,
        val lastRequestedVersion: String?,
    )

    /** What is true at the moment a prompt would be shown. */
    data class Moment(
        val hasActiveAccess: Boolean,
        val appVersion: String,
        /** Nothing else is on screen and the user just saw an in-app success. */
        val isPresentationClear: Boolean,
    )

    enum class SkipReason {
        TOO_FEW_DELIVERED_CAPTURES,
        TOO_FEW_DELIVERY_DAYS,
        NO_ACTIVE_ACCESS,
        ALREADY_REQUESTED_THIS_VERSION,
        COOLING_DOWN,
        PRESENTATION_BLOCKED,
    }

    sealed interface Decision {
        data object Request : Decision
        data class Skip(val reason: SkipReason) : Decision
    }

    fun decide(state: State, moment: Moment, nowEpochMillis: Long): Decision {
        if (state.deliveredCaptureCount < DELIVERED_CAPTURE_THRESHOLD) return Decision.Skip(SkipReason.TOO_FEW_DELIVERED_CAPTURES)
        if (state.deliveryDayCount < DELIVERY_DAY_THRESHOLD) return Decision.Skip(SkipReason.TOO_FEW_DELIVERY_DAYS)
        if (!moment.hasActiveAccess) return Decision.Skip(SkipReason.NO_ACTIVE_ACCESS)
        if (state.lastRequestedVersion != null && state.lastRequestedVersion == moment.appVersion) {
            return Decision.Skip(SkipReason.ALREADY_REQUESTED_THIS_VERSION)
        }
        val last = state.lastRequestedAtEpochMillis
        // A future timestamp (clock moved back) counts as recent: fail closed.
        if (last != null && (last > nowEpochMillis || nowEpochMillis - last < COOLDOWN_MILLIS)) {
            return Decision.Skip(SkipReason.COOLING_DOWN)
        }
        if (!moment.isPresentationClear) return Decision.Skip(SkipReason.PRESENTATION_BLOCKED)
        return Decision.Request
    }
}

/**
 * When the last request was made, and the local days with a delivered capture. The capture count
 * itself comes from the activity ledger (every source). The ledger only reports its last seven days,
 * so the days seen there are kept here, the most recent [MAXIMUM_STORED_DELIVERY_DAYS] of them.
 */
internal interface ReviewPromptStore {
    val lastRequestedAtEpochMillis: Long?
    val lastRequestedVersion: String?
    fun recordRequested(atEpochMillis: Long, version: String)
    var deliveryEpochDays: Set<Long>

    /** Adds the days in [lastSevenDays] that had a delivered capture; returns how many days are known. */
    fun recordDeliveryDays(lastSevenDays: List<ActivityDay>): Int {
        val merged = mergeDeliveryDays(deliveryEpochDays, lastSevenDays)
        if (merged != deliveryEpochDays) deliveryEpochDays = merged
        return merged.size
    }

    companion object {
        const val MAXIMUM_STORED_DELIVERY_DAYS = 14

        fun mergeDeliveryDays(stored: Set<Long>, lastSevenDays: List<ActivityDay>): Set<Long> =
            (stored + lastSevenDays.filter { it.captureCount > 0 }.map(ActivityDay::epochDay))
                .sortedDescending()
                .take(MAXIMUM_STORED_DELIVERY_DAYS)
                .toSet()
    }
}

internal class PreferencesReviewPromptStore(context: Context) : ReviewPromptStore {
    private val preferences = context.applicationContext.getSharedPreferences("vox_review_prompt", Context.MODE_PRIVATE)
    override val lastRequestedAtEpochMillis: Long?
        get() = preferences.getLong(KEY_LAST_REQUESTED_AT, 0L).takeIf { it > 0L }
    override val lastRequestedVersion: String?
        get() = preferences.getString(KEY_LAST_REQUESTED_VERSION, null)

    override var deliveryEpochDays: Set<Long>
        get() = preferences.getStringSet(KEY_DELIVERY_DAYS, emptySet()).orEmpty().mapNotNull(String::toLongOrNull).toSet()
        set(value) {
            preferences.edit().putStringSet(KEY_DELIVERY_DAYS, value.map(Long::toString).toSet()).apply()
        }

    override fun recordRequested(atEpochMillis: Long, version: String) {
        preferences.edit()
            .putLong(KEY_LAST_REQUESTED_AT, atEpochMillis)
            .putString(KEY_LAST_REQUESTED_VERSION, version)
            .apply()
    }

    private companion object {
        // Same names as the iOS defaults keys.
        const val KEY_LAST_REQUESTED_AT = "reviewPrompt.lastPromptAttemptAt.v1"
        const val KEY_LAST_REQUESTED_VERSION = "reviewPrompt.lastRequestedVersion.v2"
        const val KEY_DELIVERY_DAYS = "reviewPrompt.deliveryEpochDays.v1"
    }
}

/** How long a success moment waits before it may ask (same values as iOS). */
internal data class ReviewPromptTiming(
    /** Lets the success feedback land first. */
    val initialDelayMillis: Long = 2_000,
    /** Longest wait for the success Snackbar or "New note" toast to go before the moment is skipped. */
    val maximumFeedbackWaitMillis: Long = 8_000,
    val pollIntervalMillis: Long = 250,
    /** Lets the feedback's exit animation finish. */
    val settleDelayMillis: Long = 600,
)

/** Play's two-step flow: prepare returns null when no card can be requested now. */
internal fun interface ReviewFlow {
    suspend fun prepare(): ReviewFlowLaunch?
}

internal fun interface ReviewFlowLaunch {
    suspend fun launch()
}

/**
 * Follows an in-app success the user saw. Waits for its feedback to go, then asks once
 * if the policy allows it and nothing else is on screen. A blocked moment is skipped,
 * never queued. The request is recorded right before Play's flow is launched; Play may
 * still suppress the card and never says whether it showed. Returns the decision, or
 * null when Play could not prepare a request.
 */
internal suspend fun offerReviewAfterVisibleSuccess(
    store: ReviewPromptStore,
    appVersion: String,
    deliveryCounts: suspend () -> Pair<Int, Int>,
    hasActiveAccess: () -> Boolean,
    isShowingSuccessFeedback: () -> Boolean,
    isPresentationClear: () -> Boolean,
    flow: ReviewFlow,
    now: () -> Long = System::currentTimeMillis,
    timing: ReviewPromptTiming = ReviewPromptTiming(),
    sleep: suspend (Long) -> Unit = { delay(it) },
): ReviewPromptPolicy.Decision? {
    suspend fun decide(presentationClear: Boolean): ReviewPromptPolicy.Decision {
        val (captures, days) = deliveryCounts()
        return ReviewPromptPolicy.decide(
            ReviewPromptPolicy.State(captures, days, store.lastRequestedAtEpochMillis, store.lastRequestedVersion),
            ReviewPromptPolicy.Moment(hasActiveAccess(), appVersion, presentationClear),
            now(),
        )
    }
    // Nothing to wait for when this success can't lead to a prompt.
    val eligibility = decide(presentationClear = true)
    if (eligibility != ReviewPromptPolicy.Decision.Request) return eligibility
    sleep(timing.initialDelayMillis)
    var waited = 0L
    while (isShowingSuccessFeedback() && waited < timing.maximumFeedbackWaitMillis) {
        sleep(timing.pollIntervalMillis)
        waited += timing.pollIntervalMillis
    }
    sleep(timing.settleDelayMillis)
    val decision = decide(!isShowingSuccessFeedback() && isPresentationClear())
    if (decision != ReviewPromptPolicy.Decision.Request) return decision
    val launch = flow.prepare() ?: return null
    // Preparing takes a round trip to Play: check the screen again before showing anything.
    if (isShowingSuccessFeedback() || !isPresentationClear()) {
        return ReviewPromptPolicy.Decision.Skip(ReviewPromptPolicy.SkipReason.PRESENTATION_BLOCKED)
    }
    store.recordRequested(now(), appVersion)
    launch.launch()
    return decision
}

internal object PlayReviews {
    const val PLAY_STORE_PACKAGE = "com.android.vending"

    /** Play only serves the in-app review card to apps it installed. */
    fun installedFromPlay(context: Context): Boolean = runCatching {
        val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.packageManager.getInstallSourceInfo(context.packageName).installingPackageName
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getInstallerPackageName(context.packageName)
        }
        installer == PLAY_STORE_PACKAGE
    }.getOrDefault(false)

    /** The activity is resumed and its window has focus (no dialog, sheet or Play purchase flow over it). */
    fun activityIsUncovered(activity: Activity): Boolean =
        !activity.isFinishing && !activity.isDestroyed && activity.hasWindowFocus() &&
            (activity as? LifecycleOwner)?.lifecycle?.currentState?.isAtLeast(Lifecycle.State.RESUMED) == true

    fun appVersion(context: Context): String =
        runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: "0"

    /** Store listing for the manual "Rate" row: the Play app, else the web page. */
    fun openListing(context: Context) {
        val market = Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val web = Intent(Intent.ACTION_VIEW, Uri.parse("https://play.google.com/store/apps/details?id=${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(market) }
            .recoverCatching { context.startActivity(web) }
    }
}

/** [ReviewFlow] over Play's [ReviewManager]. Null when the app didn't come from Play or Play refused. */
internal class PlayReviewFlow(
    private val activity: Activity,
    private val manager: ReviewManager = ReviewManagerFactory.create(activity.applicationContext),
    private val enabled: Boolean = PlayReviews.installedFromPlay(activity),
) : ReviewFlow {
    override suspend fun prepare(): ReviewFlowLaunch? {
        if (!enabled) return null
        val info = try {
            withTimeout(10_000) { manager.requestReview() }
        } catch (cancelled: CancellationException) {
            if (cancelled is kotlinx.coroutines.TimeoutCancellationException) return null
            throw cancelled
        } catch (_: Exception) {
            return null
        }
        return ReviewFlowLaunch {
            try {
                manager.launchReview(activity, info)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // Play owns the card; a failed launch changes nothing for the person.
            }
        }
    }
}
