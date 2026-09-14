package md.vox.android.data

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Two-phase qualification driven by the root connectedDebugAndroidTestReinstall task.
 * The host uninstalls the test application between these methods. Running either phase
 * without that uninstall is intentionally insufficient evidence for the product adjustment.
 */
@RunWith(AndroidJUnit4::class)
class ReinstallAdjustmentInstrumentationTest {
    @Test
    fun seedExhaustedFreeQuotaBeforeUninstall() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = CaptureDatabase.create(context)
        try {
            val quota = RoomQuotaLedger(database)
            assertEquals(OLD_INSTALLATION, quota.initializeInstallation(OLD_INSTALLATION, 1_700_000_000_000))

            repeat(FREE_CAPTURE_LIMIT) { index ->
                assertTrue(
                    quota.reserve(request(index), token(index), 1_700_000_000_100 + index) is
                        QuotaReservationResult.Reserved,
                )
            }
            assertEquals(
                QuotaReservationResult.LimitReached,
                quota.reserve(EXTRA_REQUEST, EXTRA_TOKEN, 1_700_000_001_000),
            )
            assertEquals(FREE_CAPTURE_LIMIT, database.captureCoordinationDao().allReservations().size)
        } finally {
            database.close()
        }
    }

    @Test
    fun freshInstallHasNewIdentityAndEmptyFreeQuota() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val database = CaptureDatabase.create(context)
        try {
            val dao = database.captureCoordinationDao()
            assertNull("the pre-uninstall installation identity survived", dao.readInstallation())
            assertEquals(0, dao.committedUnits())
            assertTrue(dao.allReservations().isEmpty())
            assertTrue(dao.allTombstones().isEmpty())

            val quota = RoomQuotaLedger(database)
            assertEquals(NEW_INSTALLATION, quota.initializeInstallation(NEW_INSTALLATION, 1_700_000_002_000))
            assertTrue(
                quota.reserve(FRESH_REQUEST, FRESH_TOKEN, 1_700_000_002_100) is
                    QuotaReservationResult.Reserved,
            )
            assertEquals(1, dao.allReservations().size)
        } finally {
            database.close()
        }
    }

    private fun request(index: Int) = "10000000-0000-4000-8000-${(index + 1).toString().padStart(12, '0')}"
    private fun token(index: Int) = "20000000-0000-4000-8000-${(index + 1).toString().padStart(12, '0')}"

    private companion object {
        const val FREE_CAPTURE_LIMIT = 10
        const val OLD_INSTALLATION = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        const val NEW_INSTALLATION = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        const val EXTRA_REQUEST = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        const val EXTRA_TOKEN = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        const val FRESH_REQUEST = "eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"
        const val FRESH_TOKEN = "ffffffff-ffff-4fff-8fff-ffffffffffff"
    }
}
