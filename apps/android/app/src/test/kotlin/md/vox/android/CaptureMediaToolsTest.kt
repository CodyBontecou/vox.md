package md.vox.android

import java.nio.charset.StandardCharsets
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureMediaToolsTest {
    @Test
    fun documentScanPreservesEveryPageBeforeItsGeneratedPdf() {
        val assets = documentScanAssetSpecs(
            pageUris = listOf("content://scan/page-1", "content://scan/page-2"),
            pdfUri = "content://scan/document.pdf",
        )

        assertEquals(
            listOf("Scanned page 01.jpg", "Scanned page 02.jpg", "Scanned document.pdf"),
            assets.map(DocumentScanAssetSpec::displayName),
        )
        assertEquals(listOf("image/jpeg", "image/jpeg", "application/pdf"), assets.map(DocumentScanAssetSpec::mediaType))
        assertTrue(assets.all(DocumentScanAssetSpec::includeInMarkdown))
    }

    @Test
    fun ocrIsASeparateBoundedHiddenArtifactAndNeverReplacesTheScan() {
        val payload = requireNotNull(scanOcrPayload("  <!-- Page 1 -->\nInvoice 42  "))

        assertEquals("<!-- Page 1 -->\nInvoice 42\n", payload.bytes.toString(StandardCharsets.UTF_8))
        assertEquals("text/plain; charset=utf-8", payload.mediaType)
        assertFalse(payload.includeInMarkdown)
        assertNull(scanOcrPayload("  \n "))
    }

    @Test
    fun screenshotFilterUsesScreenshotMetadataWithoutAcceptingSimilarWords() {
        assertTrue(screenshotMetadataMatches("Screenshot_20260913.png", null, null))
        assertTrue(screenshotMetadataMatches("image.png", "Pictures/Screenshots/", null))
        assertTrue(screenshotMetadataMatches("Screen_Capture 17.png", null, "Camera"))
        assertFalse(screenshotMetadataMatches("screening-notes.png", "Pictures/Camera/", "Camera"))
        assertFalse(screenshotMetadataMatches("photo.png", null, null))
    }

    @Test
    fun sketchSourceIsVersionedDeterministicAndBoundsEveryRecordedPoint() {
        val encoded = encodeSketchDocument(
            listOf(
                listOf(
                    SketchPoint(-1f, 0.25f, 0f),
                    SketchPoint(0.75f, 2f, 0.5f),
                ),
            ),
        ).toString(StandardCharsets.UTF_8)

        assertEquals(
            "{\"canvas\":{\"height\":720,\"width\":1080},\"strokes\":[[{\"p\":0.1500,\"x\":0.000000,\"y\":0.250000},{\"p\":0.5000,\"x\":0.750000,\"y\":1.000000}]],\"version\":1}\n",
            encoded,
        )
    }
}
