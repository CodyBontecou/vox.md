package md.vox.android

import org.junit.Assert.assertEquals
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
}
