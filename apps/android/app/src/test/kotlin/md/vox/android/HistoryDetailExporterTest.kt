package md.vox.android

import md.vox.android.capturedomain.CaptureHistoryDetail
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureTextProcessingOutcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HistoryDetailExporterTest {
    private val detail = CaptureHistoryDetail(
        requestID = "11111111-1111-4111-8111-111111111111",
        createdAtEpochMillis = 42,
        state = CaptureState.COMPLETED,
        capturedText = "Line one\nLine \"two\"",
        capturedURL = "https://example.com/a",
        presetID = "33333333-3333-4333-8333-333333333333",
        logicalPath = "Inbox/capture.md",
        preparedMarkdown = "# Prepared\n",
        originalCapturedText = "Line   one\nLine \"two\"",
        processingMode = CaptureProcessingMode.CLEAN,
        processingOutcome = CaptureTextProcessingOutcome.APPLIED,
    )

    @Test fun markdownReturnsExactPreparedBytesAsText() {
        assertEquals("# Prepared\n", HistoryDetailExporter.render(detail, HistoryExportFormat.MARKDOWN))
    }

    @Test fun plainTextKeepsTextBeforeLink() {
        assertEquals("Line one\nLine \"two\"\n\nhttps://example.com/a\n", HistoryDetailExporter.render(detail, HistoryExportFormat.TEXT))
    }

    @Test fun jsonEscapesControlAndQuoteCharacters() {
        val result = HistoryDetailExporter.render(detail, HistoryExportFormat.JSON)
        assertTrue(result.contains("Line one\\nLine \\\"two\\\""))
        assertTrue(result.contains("\"processingMode\": \"clean\""))
        assertTrue(result.contains("Line   one"))
        assertTrue(result.endsWith("}\n"))
    }

    @Test fun yamlUsesLiteralBlockForCapturedText() {
        val result = HistoryDetailExporter.render(detail, HistoryExportFormat.YAML)
        assertTrue(result.contains("text: |-\n  Line one\n  Line \"two\"\n"))
        assertTrue(result.contains("logicalPath: 'Inbox/capture.md'"))
        assertTrue(result.contains("processingOutcome: 'applied'"))
    }
}
