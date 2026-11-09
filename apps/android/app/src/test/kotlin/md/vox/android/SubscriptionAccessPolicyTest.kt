package md.vox.android

import org.junit.Assert.assertEquals
import org.junit.Test

class SubscriptionAccessPolicyTest {
    @Test fun onlyAuthoritativeLossEndsVerifiedSubscription() {
        assertEquals(true, subscriptionAccessEnded(false, true, false))
        assertEquals(false, subscriptionAccessEnded(false, true, null))
        assertEquals(false, subscriptionAccessEnded(false, false, false))
    }

    @Test fun offlineAndPendingUpdatesPreserveEndedEvidence() {
        assertEquals(true, subscriptionAccessEnded(true, false, null))
        assertEquals(true, subscriptionAccessEnded(true, false, false))
    }

    @Test fun verifiedPurchaseRestoresEditing() {
        assertEquals(false, subscriptionAccessEnded(true, false, true))
        assertEquals(false, subscriptionAccessEnded(false, true, true))
    }
}
