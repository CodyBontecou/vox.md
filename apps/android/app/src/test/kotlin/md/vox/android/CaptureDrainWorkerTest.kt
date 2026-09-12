package md.vox.android

import md.vox.android.capturedomain.CaptureDrainSummary
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureDrainWorkerTest {
    @Test
    fun retriesOnlyForTransientPendingWork() {
        assertTrue(shouldRetryCaptureDrain(CaptureDrainSummary(1, 0, 1, 0, 0)))
        assertFalse(shouldRetryCaptureDrain(CaptureDrainSummary(2, 0, 0, 1, 1)))
        assertFalse(shouldRetryCaptureDrain(CaptureDrainSummary(1, 1, 0, 0, 0)))
    }
}
