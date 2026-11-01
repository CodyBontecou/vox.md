package md.vox.android

import org.junit.Assert.*
import org.junit.Test

class DraftPreviewTest {
    @Test fun headingsTasksQuotesAndFencedTextStayLocal() {
        val lines=previewLines("# Heading\n- [ ] Task\n> Quote\n```md\n# Code\n```\n![remote](https://example.invalid/image)")
        assertEquals(1,lines[0].heading)
        assertEquals("☐ Task",lines[1].text)
        assertTrue(lines[2].quote)
        assertTrue(lines[4].code)
        assertEquals("# Code",lines[4].text)
        assertEquals("![remote](https://example.invalid/image)",lines.last().text)
        assertEquals("Bold label",previewInline("**Bold** [label](https://example.invalid)").text)
    }
}
