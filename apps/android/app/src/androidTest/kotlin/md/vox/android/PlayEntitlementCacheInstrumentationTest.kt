package md.vox.android

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PlayEntitlementCacheInstrumentationTest {
    private val context get() = ApplicationProvider.getApplicationContext<Context>()
    private val preferencesName = "play-entitlement-cache-instrumentation"
    private val keyAlias = "md.vox.android.play-entitlement-instrumentation"
    private val cache by lazy {
        PlayEntitlementCache(
            context = context,
            productID = PlayBillingManager.PRODUCT_ID,
            preferencesName = preferencesName,
            keyAlias = keyAlias,
        )
    }

    @Before fun resetBeforeTest() = reset()

    @After fun resetAfterTest() = reset()

    @Test fun signedOwnershipRoundTripsAndTamperingFailsClosed() {
        val checkedAt = 1_723_456_789_000L
        assertTrue(cache.write(isOwned = true, checkedAtEpochMillis = checkedAt))
        assertEquals(
            CachedPlayEntitlement(
                productID = PlayBillingManager.PRODUCT_ID,
                isOwned = true,
                checkedAtEpochMillis = checkedAt,
            ),
            cache.read(),
        )

        preferences().edit()
            .putBoolean(PlayEntitlementCache.KEY_OWNED, false)
            .commit()

        assertNull(cache.read())
        assertTrue(preferences().all.isEmpty())
    }

    @Test fun signedEvidenceIsBoundToTheProductAndInstallationKey() {
        assertTrue(cache.write(isOwned = true, checkedAtEpochMillis = 1_723_456_789_000L))

        val otherProduct = PlayEntitlementCache(
            context = context,
            productID = "another_product",
            preferencesName = preferencesName,
            keyAlias = keyAlias,
        )
        assertNull(otherProduct.read())
        assertTrue(preferences().all.isEmpty())

        assertTrue(cache.write(isOwned = true, checkedAtEpochMillis = 1_723_456_789_001L))
        cache.deleteTestKey()
        assertNull(cache.read())
        assertTrue(preferences().all.isEmpty())
    }

    private fun preferences() = context.getSharedPreferences(preferencesName, Context.MODE_PRIVATE)

    private fun reset() {
        cache.clear()
        cache.deleteTestKey()
    }
}
