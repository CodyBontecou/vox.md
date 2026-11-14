package md.vox.android

import androidx.lifecycle.ViewModel
import md.vox.android.capturedomain.LiveTranscriptDraftPreview

/**
 * The live-speech span rendered into the Capture editor for the current recording.
 * Retained across rotation alongside the saved editor text, which still holds the span.
 * The words go where the cursor was when Speak was tapped (or at the end of the draft
 * for a recording started elsewhere), joined with a space rather than a new paragraph.
 */
internal class CaptureLiveTranscriptState : ViewModel() {
    private var insertionOffset: Int? = null
    private var sessionID: String? = null
    private val closedSessionIDs = mutableSetOf<String>()

    var preview: LiveTranscriptDraftPreview? = null
        private set

    /** Speak was tapped with the caret at [offset]; that recording's words go there. */
    fun begin(offset: Int) {
        if (preview?.isRendering == true) return
        preview = null
        sessionID = null
        insertionOffset = offset
    }

    /** True once this recording's words have somewhere to go (Speak tapped, or words shown). */
    val hasInsertionPoint: Boolean get() = insertionOffset != null || preview != null

    /** Renders the latest live speech; returns the draft, the caret after the words and where the span starts. */
    fun render(sessionID: String, committed: String, partial: String, draft: String): Triple<String, Int, Int>? {
        if (sessionID in closedSessionIDs) return null
        if (this.sessionID != sessionID) {
            this.sessionID = sessionID
            preview = null
        }
        if (committed.isBlank() && partial.isBlank() && preview == null) return null
        val current = preview ?: LiveTranscriptDraftPreview(insertionOffset).also { preview = it }
        val text = current.render(committed, partial, draft)
        return Triple(text, current.caretOffset ?: text.length, current.renderedLocation)
    }

    /** Swaps the live span (or the recording's cursor) for the final transcript; returns the draft and caret. */
    fun commit(transcript: String, draft: String): Pair<String, Int> {
        val current = preview
        val result = if (current != null) {
            val text = current.commit(transcript, draft)
            text to (current.caretOffset ?: text.length)
        } else {
            LiveTranscriptDraftPreview.inserting(transcript, draft, insertionOffset)
        }
        sessionID?.let(closedSessionIDs::add)
        preview = null
        insertionOffset = null
        return result
    }

    /** Removes the live span, keeping the cursor so a retried transcription lands there; null when none. */
    fun cancel(draft: String): String? {
        val current = preview ?: return null
        val text = current.cancel(draft)
        sessionID?.let(closedSessionIDs::add)
        insertionOffset = current.insertionOffset
        preview = null
        return text
    }

    /** Adds a whole line (moment marker, empty task) just ahead of where the words go. */
    fun insertLine(line: String, draft: String): Pair<String, Int?> {
        val current = preview
        if (current == null) {
            // No words yet: the line goes where this recording's words will.
            val placement = LiveTranscriptDraftPreview(insertionOffset)
            val text = placement.insertLine(line, draft)
            insertionOffset = placement.insertionOffset
            return text to insertionOffset
        }
        val text = current.insertLine(line, draft)
        return text to (current.caretOffset ?: current.insertionOffset)
    }
}
