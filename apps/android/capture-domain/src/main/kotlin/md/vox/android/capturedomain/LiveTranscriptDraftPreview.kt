package md.vox.android.capturedomain

import java.text.BreakIterator

/**
 * Reconciles a replaceable live-transcription span with an editable Capture draft
 * (port of iOS `LiveTranscriptDraftPreview`).
 *
 * Speech lands where the writer's cursor was when recording started (or at the end
 * of the draft), joined to the surrounding text with a space rather than a new
 * paragraph. On-device live speech revises its partial words, so the span is
 * replaced in place as recognition progresses. Committing swaps that same span for
 * the final transcript instead of inserting a duplicate.
 *
 * Offsets are UTF-16 code units, matching Compose `TextRange`.
 */
class LiveTranscriptDraftPreview(insertionOffset: Int? = null) {
    /** Where the transcript goes in the draft *without* the rendered span; null means the end. */
    var insertionOffset: Int? = insertionOffset?.coerceAtLeast(0)
        private set

    /** The text currently rendered into the draft, separators included. */
    private var renderedBlock = ""

    /** Location of [renderedBlock] in the draft it was rendered into. */
    var renderedLocation: Int = 0
        private set
    private var transcript = ""

    /** Offset just past the transcript (before any trailing separator) in the last returned draft. */
    var caretOffset: Int? = null
        private set

    val isRendering: Boolean get() = renderedBlock.isNotEmpty()

    fun render(finalizedText: String, volatileText: String?, currentDraft: String): String {
        val base = removingRenderedBlock(currentDraft)
        transcript = merged(finalizedText, volatileText)
        return place(base)
    }

    fun commit(transcript: String, currentDraft: String): String {
        val base = removingRenderedBlock(currentDraft)
        this.transcript = transcript.trim()
        val result = place(base)
        renderedBlock = ""
        return result
    }

    fun cancel(currentDraft: String): String {
        val base = removingRenderedBlock(currentDraft)
        renderedBlock = ""
        caretOffset = null
        return base
    }

    /** The draft without the live span, leaving this preview untouched (for persistence). */
    fun withoutLiveSpan(currentDraft: String): String {
        if (renderedBlock.isEmpty()) return currentDraft
        val range = locateRenderedBlock(currentDraft) ?: return currentDraft
        return currentDraft.removeRange(range)
    }

    /** Inserts a whole line (moment marker, empty task) just ahead of the live span. */
    fun insertLine(line: String, currentDraft: String): String {
        val base = removingRenderedBlock(currentDraft)
        val at = clampedOffset(insertionOffset, base)
        val insertion = if (line.endsWith("\n")) line else line + "\n"
        val before = characterBefore(at, base)
        val joined = (if (before == null || before == "\n") "" else "\n") + insertion
        val updated = base.substring(0, at) + joined + base.substring(at)
        insertionOffset = at + joined.length
        return place(updated)
    }

    private fun place(base: String): String {
        if (transcript.isEmpty()) {
            renderedBlock = ""
            caretOffset = null
            return base
        }
        val at = clampedOffset(insertionOffset, base)
        val leading = if (needsLeadingSpace(characterBefore(at, base))) " " else ""
        val trailing = if (needsTrailingSpace(characterAt(at, base))) " " else ""
        val block = leading + transcript + trailing
        renderedBlock = block
        renderedLocation = at
        caretOffset = at + leading.length + transcript.length
        return base.substring(0, at) + block + base.substring(at)
    }

    private fun removingRenderedBlock(draft: String): String {
        if (renderedBlock.isEmpty()) return draft
        // Preserve user edits if the span itself was manually changed.
        val range = locateRenderedBlock(draft) ?: return draft
        if (insertionOffset != null) insertionOffset = range.first
        return draft.removeRange(range)
    }

    /** The span where it was rendered, or the occurrence nearest to it after edits shifted it. */
    private fun locateRenderedBlock(draft: String): IntRange? {
        val length = renderedBlock.length
        if (renderedLocation + length <= draft.length &&
            draft.regionMatches(renderedLocation, renderedBlock, 0, length)
        ) {
            return renderedLocation until renderedLocation + length
        }
        var best: Int? = null
        var index = draft.indexOf(renderedBlock)
        while (index >= 0) {
            if (best == null || kotlin.math.abs(index - renderedLocation) < kotlin.math.abs(best - renderedLocation)) {
                best = index
            }
            index = draft.indexOf(renderedBlock, index + 1)
        }
        return best?.let { it until it + length }
    }

    companion object {
        /** One-shot insertion for a transcript that never had a live span. */
        fun inserting(transcript: String, text: String, offset: Int?): Pair<String, Int> {
            val preview = LiveTranscriptDraftPreview(offset)
            val result = preview.commit(transcript, text)
            return result to (preview.caretOffset ?: result.length)
        }

        private fun merged(finalizedText: String, volatileText: String?): String =
            listOf(finalizedText.trim(), volatileText.orEmpty().trim())
                .filter(String::isNotEmpty)
                .joinToString(" ")

        /** Clamps to the text and snaps back to a character boundary so an emoji is never split. */
        private fun clampedOffset(offset: Int?, text: String): Int {
            if (offset == null || offset >= text.length) return text.length
            if (offset <= 0) return 0
            val iterator = BreakIterator.getCharacterInstance().apply { setText(text) }
            return if (iterator.isBoundary(offset)) offset else iterator.preceding(offset)
        }

        private fun characterBefore(offset: Int, text: String): String? {
            if (offset <= 0) return null
            val iterator = BreakIterator.getCharacterInstance().apply { setText(text) }
            return text.substring(iterator.preceding(offset), offset)
        }

        private fun characterAt(offset: Int, text: String): String? {
            if (offset >= text.length) return null
            val iterator = BreakIterator.getCharacterInstance().apply { setText(text) }
            return text.substring(offset, iterator.following(offset))
        }

        private fun needsLeadingSpace(before: String?): Boolean {
            if (before == null) return false
            return !before.isBlank() && before !in listOf("(", "[", "{", "\"", "'", "“", "‘")
        }

        private fun needsTrailingSpace(after: String?): Boolean {
            if (after == null) return false
            return !after.isBlank() && after !in listOf(".", ",", ";", ":", "!", "?", ")", "]", "}", "\"", "'", "”", "’", "…")
        }
    }
}
