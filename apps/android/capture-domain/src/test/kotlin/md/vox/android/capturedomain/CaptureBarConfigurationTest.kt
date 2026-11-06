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

    @Test fun routePinsOverrideTheGlobalRowOnlyForTheirRoute() {
        val global = CaptureBarConfiguration(hiddenActions = setOf(CaptureBarAction.PASTE))
        val pins = listOf(CaptureBarAction.TIMESTAMP, CaptureBarAction.CHECKLIST, CaptureBarAction.TIMESTAMP)
        val configured = global.withRoutePins("meetings", pins)

        assertEquals(listOf(CaptureBarAction.TIMESTAMP, CaptureBarAction.CHECKLIST), configured.pinnedActions("meetings"))
        assertEquals(global.visibleActions, configured.pinnedActions("inbox"))
        assertEquals(global.visibleActions, configured.pinnedActions(null))
        assertTrue(configured.hasCustomPins("meetings"))
        assertFalse(configured.hasCustomPins("inbox"))
        assertEquals(listOf(CaptureBarAction.TIMESTAMP, CaptureBarAction.CHECKLIST), configured.forRoute("meetings").visibleActions)
        assertEquals(global.visibleActions, configured.forRoute("inbox").visibleActions)
        assertFalse(CaptureBarAction.TIMESTAMP in configured.unpinnedActions("meetings"))
        assertEquals(CaptureBarAction.entries.size - 2, configured.unpinnedActions("meetings").size)

        val emptied = configured.withRoutePins("meetings", emptyList())
        assertTrue(emptied.forRoute("meetings").visibleActions.isEmpty())
        val reset = emptied.withRoutePins("meetings", null)
        assertFalse(reset.hasCustomPins("meetings"))
        assertEquals(global, reset)
    }
}
