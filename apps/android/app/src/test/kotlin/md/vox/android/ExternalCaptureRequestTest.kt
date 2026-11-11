package md.vox.android

import android.content.Intent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ExternalCaptureRequestTest {
    @Test fun sharedUppercaseSchemeIsNormalizedBeforeDraftAdmission() {
        val request = ExternalCaptureRequestParser.normalize(
            textValues = listOf(" HTTPS://example.com/Case "), title = null, presetID = null,
            action = ExternalCaptureAction.REVIEW, sourceLabel = "Shared content", attachmentUris = emptyList(),
        )
        assertEquals("https://example.com/Case", requireNotNull(request).url)
    }

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

    @Test fun freshLaunchParsesIntent() {
        assertTrue(ExternalCaptureRequestParser.shouldParseOnCreate(intentFlags = 0, restoredRequestHandled = null))
    }

    @Test fun recreatedActivityDoesNotReplayHandledRequest() {
        assertFalse(ExternalCaptureRequestParser.shouldParseOnCreate(intentFlags = 0, restoredRequestHandled = true))
    }

    @Test fun recreatedActivityRedeliversUnconsumedRequest() {
        assertTrue(ExternalCaptureRequestParser.shouldParseOnCreate(intentFlags = 0, restoredRequestHandled = false))
    }

    @Test fun launchFromRecentsDoesNotReplayRequest() {
        assertFalse(
            ExternalCaptureRequestParser.shouldParseOnCreate(
                intentFlags = Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY,
                restoredRequestHandled = null,
            ),
        )
    }

    @Test fun emptyWidgetOrShortcutRequestKeepsTypedDraft() {
        val merged = mergeExternalDraft("MY_IMPORTANT_DRAFT", null, incomingText = "", incomingURL = null)

        assertEquals("MY_IMPORTANT_DRAFT", merged.text)
        assertNull(merged.url)
    }

    @Test fun sharedTextIsAppendedToTypedDraft() {
        val merged = mergeExternalDraft("typed note\n", null, incomingText = "shared text", incomingURL = null)

        assertEquals("typed note\n\nshared text", merged.text)
    }

    @Test fun sharedTextFillsEmptyDraft() {
        val merged = mergeExternalDraft("", null, incomingText = "shared text", incomingURL = "https://example.com")

        assertEquals("shared text", merged.text)
        assertEquals("https://example.com", merged.url)
    }

    @Test fun repeatedShareDoesNotDuplicateText() {
        val merged = mergeExternalDraft("note\n\nshared text", null, incomingText = "shared text", incomingURL = null)

        assertEquals("note\n\nshared text", merged.text)
    }

    @Test fun differentIncomingURLKeepsExistingURLAndCarriesNewOneAsText() {
        val merged = mergeExternalDraft("note", "https://a.example", incomingText = "", incomingURL = "https://b.example")

        assertEquals("https://a.example", merged.url)
        assertEquals("note\n\nhttps://b.example", merged.text)
    }

    @Test fun mergedTextIsClampedToDraftLimit() {
        val merged = mergeExternalDraft("a".repeat(10), null, incomingText = "b".repeat(10), incomingURL = null, maxCharacters = 15)

        assertEquals(15, merged.text.length)
    }
}
