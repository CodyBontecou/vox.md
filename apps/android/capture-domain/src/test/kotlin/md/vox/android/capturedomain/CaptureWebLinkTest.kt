package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CaptureWebLinkTest {
    @Test fun rejectsMalformedOrUnsupportedLinks() {
        listOf("https://", "http:///path", "https://example.com/has space", "https://example.com/%zz", "file:///tmp/a", "mailto:a@example.com", "").forEach {
            assertNull(it, CaptureWebLink.normalize(it))
        }
        assertNull(CaptureWebLink.normalize("https://example.com/" + "a".repeat(8_192)))
    }

    @Test fun normalizesOnlySurroundingWhitespaceAndScheme() {
        assertEquals("https://Example.com/Case/%2f?q=%25#Part", CaptureWebLink.normalize("  HTTPS://Example.com/Case/%2f?q=%25#Part\n"))
        assertEquals("http://localhost:8080/a", CaptureWebLink.normalize("HtTp://localhost:8080/a"))
    }
}
