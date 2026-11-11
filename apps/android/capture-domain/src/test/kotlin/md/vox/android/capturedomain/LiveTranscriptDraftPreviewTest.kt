package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

/** Mirrors iOS `LiveTranscriptDraftPreviewTests`. */
class LiveTranscriptDraftPreviewTest {
    @Test fun renderPlacesLiveSpeechInsideEmptyDraft() {
        assertEquals("Hello world", LiveTranscriptDraftPreview().render("Hello", "world", ""))
    }

    @Test fun renderAppendsToExistingDraftWithSpace() {
        assertEquals("Typed note Spoken text", LiveTranscriptDraftPreview().render("Spoken text", null, "Typed note"))
    }

    @Test fun laterPartialResultReplacesEarlierPreview() {
        val preview = LiveTranscriptDraftPreview()
        val first = preview.render("", "A rough phrase", "Typed note")
        assertEquals("Typed note A corrected phrase", preview.render("A corrected", "phrase", first))
    }

    @Test fun renderPreservesTypingAddedBeforePreview() {
        val preview = LiveTranscriptDraftPreview()
        val first = preview.render("Live words", null, "Typed")
        val edited = first.replace("Typed", "Typed more")
        assertEquals("Typed more Live words continue", preview.render("Live words continue", null, edited))
    }

    @Test fun commitReplacesPreviewWithoutDuplicatingTranscript() {
        val preview = LiveTranscriptDraftPreview()
        val live = preview.render("Hello", "world", "Typed note")
        assertEquals("Typed note Hello world.", preview.commit("Hello world.", live))
        assertFalse(preview.isRendering)
    }

    @Test fun cancelRemovesOnlyLivePreview() {
        val preview = LiveTranscriptDraftPreview()
        val live = preview.render("Temporary speech", null, "Keep this")
        assertEquals("Keep this", preview.cancel(live))
        assertFalse(preview.isRendering)
    }

    @Test fun withoutLiveSpanLeavesPreviewRendering() {
        val preview = LiveTranscriptDraftPreview(5)
        val live = preview.render("big", null, "Hello world")
        assertEquals("Hello world", preview.withoutLiveSpan(live))
        assertEquals("Hello big bright world", preview.render("big bright", null, live))
    }

    @Test fun renderAfterTrailingNewlineAddsNoSeparator() {
        assertEquals("Line\nSpoken", LiveTranscriptDraftPreview().render("Spoken", null, "Line\n"))
    }

    @Test fun renderInsertsAtCursorBetweenWords() {
        val preview = LiveTranscriptDraftPreview(5)
        val first = preview.render("", "big", "Hello world")
        assertEquals("Hello big world", first)
        assertEquals(9, preview.caretOffset)
        val revised = preview.render("big", "wide", first)
        assertEquals("Hello big wide world", revised)
        assertEquals("Hello Big, wide world", preview.commit("Big, wide", revised))
        assertEquals(15, preview.caretOffset)
    }

    @Test fun renderAtCursorBeforePunctuationAddsNoTrailingSpace() {
        assertEquals("Hello there.", LiveTranscriptDraftPreview(5).render("there", null, "Hello."))
    }

    @Test fun renderAtStartOfLineAddsNoLeadingSpace() {
        assertEquals("Hello\nSpoken\nNext", LiveTranscriptDraftPreview(6).render("Spoken", null, "Hello\n\nNext"))
    }

    @Test fun typingBeforeCursorSpanKeepsSpanInPlace() {
        val preview = LiveTranscriptDraftPreview(5)
        val first = preview.render("big", null, "Hello world")
        assertEquals("Oh, Hello big bright world", preview.render("big bright", null, "Oh, $first"))
    }

    @Test fun cancelAtCursorRestoresOriginalText() {
        val preview = LiveTranscriptDraftPreview(5)
        val live = preview.render("big", null, "Hello world")
        assertEquals("Hello world", preview.cancel(live))
    }

    @Test fun insertLineGoesAheadOfLiveSpan() {
        val preview = LiveTranscriptDraftPreview()
        val live = preview.render("Talking", null, "Note")
        val withTask = preview.insertLine("- [ ] ", live)
        assertEquals("Note\n- [ ] \nTalking", withTask)
        assertEquals("Note\n- [ ] \nTalking more", preview.render("Talking more", null, withTask))
    }

    @Test fun oneShotInsertionUsesCursor() {
        assertEquals("Hello big world" to 9, LiveTranscriptDraftPreview.inserting("big", "Hello world", 5))
    }

    @Test fun cursorInsideEmojiSnapsToCharacterBoundary() {
        val text = "Hi 👋 there"
        val (result, _) = LiveTranscriptDraftPreview.inserting("wave", text, 4)
        assertEquals("Hi wave 👋 there", result)
    }
}
