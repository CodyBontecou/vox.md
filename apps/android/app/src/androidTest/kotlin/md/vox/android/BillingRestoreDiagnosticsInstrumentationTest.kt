package md.vox.android

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.Purchase
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BillingRestoreDiagnosticsInstrumentationTest {
    private val context get() = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Before fun clearLogBeforeTest() = PrivacySafeDebugLog.clear(context)

    @After fun clearLogAfterTest() = PrivacySafeDebugLog.clear(context)

    @Test fun restoreDiagnosticsExcludeEveryAccountAndTransactionIdentifier() {
        val purchase = Purchase(
            """{
                "orderId":"secret-order-123",
                "packageName":"md.vox.android",
                "productId":"vox_unlimited_lifetime",
                "productIds":["vox_unlimited_lifetime"],
                "purchaseTime":1723456789000,
                "purchaseState":0,
                "purchaseToken":"secret-token-456",
                "acknowledged":false,
                "obfuscatedAccountId":"secret-account-789",
                "obfuscatedProfileId":"secret-profile-012"
            }""".trimIndent(),
            "secret-signature-345",
        )

        val diagnostics = billingRestoreDiagnosticsFromPurchases(
            responseCode = BillingClient.BillingResponseCode.OK,
            requestedProductIDs = listOf(PlayBillingManager.PRODUCT_ID),
            loadedProductIDs = listOf(PlayBillingManager.PRODUCT_ID),
            purchases = listOf(purchase),
        )
        recordBillingRestoreDiagnostics(context, diagnostics)

        assertTrue(diagnostics.syncSucceeded)
        assertEquals(null, diagnostics.syncError)
        assertEquals(listOf(PlayBillingManager.PRODUCT_ID), diagnostics.requestedProductIDs)
        assertEquals(listOf(PlayBillingManager.PRODUCT_ID), diagnostics.loadedProductIDs)
        assertEquals("purchased", diagnostics.observations.single().purchaseState)
        assertTrue(diagnostics.observations.single().isRecognized)
        assertFalse(diagnostics.observations.single().isAcknowledged)

        val retainedEvidence = diagnostics.summary + "\n" + PrivacySafeDebugLog.read(context)
        assertTrue(retainedEvidence.contains("billing.restore_checked"))
        assertTrue(retainedEvidence.contains("vox_unlimited_lifetime"))
        assertTrue(retainedEvidence.contains("purchased"))
        listOf(
            "secret-order-123",
            "secret-token-456",
            "secret-account-789",
            "secret-profile-012",
            "secret-signature-345",
            "1723456789000",
        ).forEach { secret -> assertFalse(secret, retainedEvidence.contains(secret)) }
    }
}
