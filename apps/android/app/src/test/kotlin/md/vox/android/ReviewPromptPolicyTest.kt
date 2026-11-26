package md.vox.android

import kotlinx.coroutines.runBlocking
import md.vox.android.capturedomain.ActivityDay
import md.vox.android.ReviewPromptPolicy.Decision
import md.vox.android.ReviewPromptPolicy.SkipReason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The Play rating rules, mirrored from iOS `ReviewPromptManagerTests`. No Play services are touched. */
class ReviewPromptPolicyTest {
    private val now = 1_800_000_000_000L
    private val day = 24L * 60 * 60 * 1000

    private fun state(captures: Int = 5, days: Int = 2, lastAt: Long? = null, lastVersion: String? = null) =
        ReviewPromptPolicy.State(captures, days, lastAt, lastVersion)

    private fun moment(access: Boolean = true, version: String = "3.0.5", clear: Boolean = true) =
        ReviewPromptPolicy.Moment(access, version, clear)

    @Test
    fun asksAtFiveDeliveredCapturesOnTwoDays() {
        assertEquals(Decision.Request, ReviewPromptPolicy.decide(state(), moment(), now))
    }

    @Test
    fun needsFiveCapturesAndTwoDays() {
        assertEquals(Decision.Skip(SkipReason.TOO_FEW_DELIVERED_CAPTURES), ReviewPromptPolicy.decide(state(captures = 4), moment(), now))
        assertEquals(Decision.Skip(SkipReason.TOO_FEW_DELIVERY_DAYS), ReviewPromptPolicy.decide(state(captures = 40, days = 1), moment(), now))
    }

    @Test
    fun neverAsksWithoutActiveAccess() {
        assertEquals(Decision.Skip(SkipReason.NO_ACTIVE_ACCESS), ReviewPromptPolicy.decide(state(), moment(access = false), now))
    }

    @Test
    fun asksOncePerVersionAndNotWithinNinetyDays() {
        assertEquals(
            Decision.Skip(SkipReason.ALREADY_REQUESTED_THIS_VERSION),
            ReviewPromptPolicy.decide(state(lastAt = now - 200 * day, lastVersion = "3.0.5"), moment(), now),
        )
        assertEquals(
            Decision.Skip(SkipReason.COOLING_DOWN),
            ReviewPromptPolicy.decide(state(lastAt = now - 89 * day, lastVersion = "3.0.4"), moment(), now),
        )
        assertEquals(
            Decision.Request,
            ReviewPromptPolicy.decide(state(lastAt = now - 90 * day, lastVersion = "3.0.4"), moment(), now),
        )
    }

    @Test
    fun aFutureRequestTimeFailsClosed() {
        assertEquals(
            Decision.Skip(SkipReason.COOLING_DOWN),
            ReviewPromptPolicy.decide(state(lastAt = now + day, lastVersion = "3.0.4"), moment(), now),
        )
    }

    @Test
    fun aCoveredScreenSkipsTheMoment() {
        assertEquals(Decision.Skip(SkipReason.PRESENTATION_BLOCKED), ReviewPromptPolicy.decide(state(), moment(clear = false), now))
    }

    private class MemoryStore(
        override var lastRequestedAtEpochMillis: Long? = null,
        override var lastRequestedVersion: String? = null,
        override var deliveryEpochDays: Set<Long> = emptySet(),
    ) : ReviewPromptStore {
        override fun recordRequested(atEpochMillis: Long, version: String) {
            lastRequestedAtEpochMillis = atEpochMillis
            lastRequestedVersion = version
        }
    }

    private class Offer(
        var counts: Pair<Int, Int> = 5 to 2,
        var access: Boolean = true,
        var feedbackPolls: Int = 0,
        var clear: Boolean = true,
        var prepared: Boolean = true,
    ) {
        val store = MemoryStore()
        var prepares = 0
        var launches = 0
        val sleeps = mutableListOf<Long>()

        fun run(now: Long = 1_800_000_000_000L): Decision? = runBlocking {
            offerReviewAfterVisibleSuccess(
                store = store,
                appVersion = "3.0.5",
                deliveryCounts = { counts },
                hasActiveAccess = { access },
                isShowingSuccessFeedback = { feedbackPolls-- > 0 },
                isPresentationClear = { clear },
                flow = {
                    prepares++
                    if (prepared) ReviewFlowLaunch { launches++ } else null
                },
                now = { now },
                sleep = { sleeps += it },
            )
        }
    }

    @Test
    fun anEligibleMomentWaitsForTheFeedbackThenRecordsAndLaunches() {
        val offer = Offer(feedbackPolls = 3)
        assertEquals(Decision.Request, offer.run())
        assertEquals(listOf(2_000L, 250L, 250L, 250L, 600L), offer.sleeps)
        assertEquals(1, offer.launches)
        assertEquals("3.0.5", offer.store.lastRequestedVersion)
        assertEquals(1_800_000_000_000L, offer.store.lastRequestedAtEpochMillis)
    }

    @Test
    fun anIneligibleMomentReturnsAtOnceWithoutWaitingOrAskingPlay() {
        val offer = Offer(counts = 4 to 3)
        assertEquals(Decision.Skip(SkipReason.TOO_FEW_DELIVERED_CAPTURES), offer.run())
        assertEquals(emptyList<Long>(), offer.sleeps)
        assertEquals(0, offer.prepares)
        assertNull(offer.store.lastRequestedVersion)
    }

    @Test
    fun feedbackThatOutlastsTheWaitSkipsTheMoment() {
        val offer = Offer(feedbackPolls = 1_000)
        assertEquals(Decision.Skip(SkipReason.PRESENTATION_BLOCKED), offer.run())
        assertEquals(0, offer.prepares)
        assertNull(offer.store.lastRequestedAtEpochMillis)
    }

    @Test
    fun aCoveredScreenIsNotRecordedAsARequest() {
        val offer = Offer(clear = false)
        assertEquals(Decision.Skip(SkipReason.PRESENTATION_BLOCKED), offer.run())
        assertEquals(0, offer.launches)
        assertNull(offer.store.lastRequestedVersion)
    }

    @Test
    fun whenPlayCannotPrepareNothingIsRecorded() {
        val offer = Offer(prepared = false)
        assertNull(offer.run())
        assertEquals(1, offer.prepares)
        assertEquals(0, offer.launches)
        assertNull(offer.store.lastRequestedVersion)
    }

    @Test
    fun aSecondSuccessOnTheSameVersionDoesNotAskAgain() {
        val offer = Offer()
        assertEquals(Decision.Request, offer.run())
        assertEquals(Decision.Skip(SkipReason.ALREADY_REQUESTED_THIS_VERSION), offer.run(now = 1_800_000_000_000L + 100L * 24 * 60 * 60 * 1000))
        assertEquals(1, offer.launches)
    }

    @Test
    fun deliveryDaysAccumulateAcrossWeeksAndKeepTheLatestFourteen() {
        val store = MemoryStore()
        fun week(firstDay: Long, captures: List<Int>) = captures.mapIndexed { index, count -> ActivityDay(firstDay + index, count, 0) }
        assertEquals(1, store.recordDeliveryDays(week(100, listOf(0, 0, 3, 0, 0, 0, 0))))
        // A week later only the new day is in the ledger's window; the earlier one is remembered.
        assertEquals(2, store.recordDeliveryDays(week(107, listOf(0, 1, 0, 0, 0, 0, 0))))
        assertEquals(setOf(102L, 108L), store.deliveryEpochDays)
        // Reading the same window again never double-counts.
        assertEquals(2, store.recordDeliveryDays(week(107, listOf(0, 1, 0, 0, 0, 0, 0))))
        repeat(3) { store.recordDeliveryDays(week(200L + it * 7, List(7) { 1 })) }
        assertEquals(ReviewPromptStore.MAXIMUM_STORED_DELIVERY_DAYS, store.deliveryEpochDays.size)
        assertEquals(220L, store.deliveryEpochDays.max())
        assertEquals(207L, store.deliveryEpochDays.min())
    }
}
