package md.vox.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExternalCaptureRequestTest {
    @Test fun sharedHttpURLKeepsTitleAsNote() {
        val request = ExternalCaptureRequestParser.normalize(
            textValues = listOf("https://example.com/story"),
            title = "A useful story",
            presetID = null,
            action = ExternalCaptureAction.REVIEW,
            sourceLabel = "Shared content",
            attachmentUris = emptyList(),
        )

        requireNotNull(request)
        assertEquals("A useful story", request.text)
        assertEquals("https://example.com/story", request.url)
        assertEquals("share", request.captureSource)
    }

    @Test fun multipleTextValuesKeepOrderAndSeparation() {
        val request = ExternalCaptureRequestParser.normalize(
            textValues = listOf(" first ", "second"),
            title = "Ignored title",
            presetID = null,
            action = ExternalCaptureAction.REVIEW,
            sourceLabel = "Shared content",
            attachmentUris = emptyList(),
        )

        assertEquals("first\n\nsecond", requireNotNull(request).text)
        assertNull(request.url)
    }

    @Test fun emptyShareIsRejectedButAttachmentIsRepresented() {
        assertNull(
            ExternalCaptureRequestParser.normalize(
                textValues = emptyList(),
                title = null,
                presetID = null,
                action = ExternalCaptureAction.REVIEW,
                sourceLabel = "Shared content",
                attachmentUris = emptyList(),
            ),
        )
        val attachment = ExternalCaptureRequestParser.normalize(
            textValues = emptyList(),
            title = null,
            presetID = null,
            action = ExternalCaptureAction.REVIEW,
            sourceLabel = "Shared content",
            attachmentUris = listOf("content://one", "content://two"),
        )
        assertEquals(2, requireNotNull(attachment).attachmentUris.size)
    }

    @Test fun textBudgetIsEnforcedAtBoundary() {
        val request = ExternalCaptureRequestParser.normalize(
            textValues = listOf("x".repeat(70_000)),
            title = null,
            presetID = null,
            action = ExternalCaptureAction.REVIEW,
            sourceLabel = "Selected text",
            attachmentUris = emptyList(),
        )
        assertEquals(65_536, requireNotNull(request).text.length)
        assertEquals("share", request.captureSource)
        assertTrue(request.correlationID.isNotBlank())
    }

    @Test fun unsupportedSourceCannotEscapeTheAdmissionVocabulary() {
        val request = ExternalCaptureRequestParser.normalize(
            textValues = listOf("text"),
            title = null,
            presetID = null,
            action = ExternalCaptureAction.REVIEW,
            sourceLabel = "External",
            captureSource = "future-surface",
            attachmentUris = emptyList(),
        )

        assertEquals("share", requireNotNull(request).captureSource)
    }
}
