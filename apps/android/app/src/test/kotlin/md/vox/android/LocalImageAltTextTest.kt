package md.vox.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LocalImageAltTextTest {
    @Test
    fun `formats only strong distinct labels without markdown delimiters`() {
        val result = formatImageAltText(
            listOf(
                " Dog " to 0.91f,
                "dog" to 0.88f,
                "Pet|animal]" to 0.82f,
                "blur" to 0.40f,
            ),
        )

        assertEquals("Image may contain: Dog, Pet animal.", result)
    }

    @Test
    fun `returns no description without sufficiently strong evidence`() {
        assertNull(formatImageAltText(listOf("uncertain" to 0.20f)))
    }
}
