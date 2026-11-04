package md.vox.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class AdaptiveLayoutTest {
    @Test
    fun `window width breakpoints follow Android adaptive guidance`() {
        assertEquals(VoxWindowWidthClass.COMPACT, classifyVoxWindowWidth(0))
        assertEquals(VoxWindowWidthClass.COMPACT, classifyVoxWindowWidth(599))
        assertEquals(VoxWindowWidthClass.MEDIUM, classifyVoxWindowWidth(600))
        assertEquals(VoxWindowWidthClass.MEDIUM, classifyVoxWindowWidth(839))
        assertEquals(VoxWindowWidthClass.EXPANDED, classifyVoxWindowWidth(840))
        assertEquals(VoxWindowWidthClass.EXPANDED, classifyVoxWindowWidth(2_400))
    }

    @Test
    fun `panes meet at a vertical hinge so neither crosses it`() {
        // 2208px inner display, rail ends at 264px, 40px-wide hinge centred on 1104px.
        val split = splitAroundFold(
            containerStartPx = 264,
            containerWidthPx = 1944,
            foldStartPx = 1084,
            foldEndPx = 1124,
            minPanePx = 600,
            minimumGapPx = 36,
        )
        assertEquals(1084 - 264 to 40, split)
        val (first, gap) = requireNotNull(split)
        assertEquals(1124, 264 + first + gap)
    }

    @Test
    fun `a flat fold still leaves the minimum gutter centred on the fold line`() {
        assertEquals(1086 to 36, splitAroundFold(0, 2208, 1104, 1104, 600, 36))
    }

    @Test
    fun `a hinge too close to an edge falls back to proportional panes`() {
        assertNull(splitAroundFold(containerStartPx = 900, containerWidthPx = 1308, foldStartPx = 1084, foldEndPx = 1124, minPanePx = 600, minimumGapPx = 36))
        assertNull(splitAroundFold(0, 0, 10, 20, 1, 1))
    }

    @Test
    fun `tabletop splits the height at the horizontal hinge`() {
        assertEquals(800 - 60 to 20, splitAroundHorizontalFold(60, 1700, 800, 820, 400))
        assertNull(splitAroundHorizontalFold(0, 1700, 200, 220, 400))
    }

    @Test
    fun `activity badge counts captures and transcripts that need the person`() {
        assertEquals(true, md.vox.android.capturedomain.CaptureState.NEEDS_PERMISSION.needsAttention())
        assertEquals(false, md.vox.android.capturedomain.CaptureState.COMMITTING.needsAttention())
        assertEquals(true, md.vox.android.capturedomain.CaptureState.COMMITTING.isInFlight())
        assertEquals(false, md.vox.android.capturedomain.CaptureState.COMPLETED.isInFlight())
    }
}
