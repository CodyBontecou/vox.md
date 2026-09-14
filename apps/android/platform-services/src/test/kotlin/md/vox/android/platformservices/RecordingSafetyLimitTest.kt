package md.vox.android.platformservices

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordingSafetyLimitTest {
    @Test fun boundaryMatchesTheDurableSegmentRetentionLimit() {
        assertFalse(reachedRecordingSafetyLimit(MAX_RECORDING_DURATION_MILLIS - 1))
        assertTrue(reachedRecordingSafetyLimit(MAX_RECORDING_DURATION_MILLIS))
        assertTrue(reachedRecordingSafetyLimit(MAX_RECORDING_DURATION_MILLIS + 1))
    }
}
