package md.vox.android.platformservices

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscriptionQuotaPolicyTest {
    @Test fun freeAllowanceIsBoundedAndPaidAccessBypassesIt() {
        assertTrue(TranscriptionQuotaPolicy.canReserve(0, 0, FREE_TRANSCRIPTION_LIMIT_MILLIS, false))
        assertFalse(TranscriptionQuotaPolicy.canReserve(FREE_TRANSCRIPTION_LIMIT_MILLIS, 0, 1, false))
        assertFalse(TranscriptionQuotaPolicy.canReserve(10 * 60_000L, 4 * 60_000L, 2 * 60_000L, false))
        assertTrue(TranscriptionQuotaPolicy.canReserve(FREE_TRANSCRIPTION_LIMIT_MILLIS, 0, 60 * 60_000L, true))
    }

    @Test fun invalidDurationsAreRejectedEvenForPaidAccess() {
        assertFalse(TranscriptionQuotaPolicy.canReserve(0, 0, 0, true))
        assertFalse(TranscriptionQuotaPolicy.canReserve(-1, 0, 1, false))
    }
}
