package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureBarConfigurationTest {
    @Test fun normalizationKeepsCustomOrderAndMigratesMissingActionsExactlyOnce() {
        val normalized = CaptureBarConfiguration(
            orderedActions = listOf(
                CaptureBarAction.DATE,
                CaptureBarAction.CHECKLIST,
                CaptureBarAction.DATE,
            ),
            hiddenActions = setOf(CaptureBarAction.ADD_MEDIA),
            usesTwentyFourHourTimestamps = true,
        ).normalized()

        assertEquals(CaptureBarAction.DATE, normalized.orderedActions[0])
        assertEquals(CaptureBarAction.CHECKLIST, normalized.orderedActions[1])
        assertEquals(CaptureBarAction.entries.size, normalized.orderedActions.size)
        assertEquals(CaptureBarAction.entries.size, normalized.orderedActions.distinct().size)
        assertFalse(CaptureBarAction.ADD_MEDIA in normalized.visibleActions)
        assertTrue(normalized.usesTwentyFourHourTimestamps)
    }
}
