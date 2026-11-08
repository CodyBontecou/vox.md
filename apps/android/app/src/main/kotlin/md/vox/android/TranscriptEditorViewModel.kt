package md.vox.android

import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.ViewModel
import md.vox.android.platformservices.RecordingTranscriptionState

/** Large editable transcripts stay out of Android's saved-state transaction. */
internal class TranscriptEditorViewModel : ViewModel() {
    private var currentToken: String? = null
    private var currentDraft: TranscriptEditorDraft? = null
    private var currentSessionID: String? = null

    fun editor(token: String, source: RecordingTranscriptionState?, initialEditing: Boolean): TranscriptEditorDraft {
        if (currentToken != token ||
            (source != null && currentSessionID != null && currentSessionID != source.sessionID)
        ) {
            currentToken = token
            currentSessionID = source?.sessionID
            currentDraft = TranscriptEditorDraft(source, initialEditing)
        }
        if (source != null) currentSessionID = source.sessionID
        return requireNotNull(currentDraft).also { it.sync(source) }
    }
}

internal class TranscriptEditorDraft(source: RecordingTranscriptionState?, initialEditing: Boolean) {
    private var original = source
    val editing = mutableStateOf(initialEditing)
    val rawText = mutableStateOf(source?.transcript.orEmpty())
    val cleanedText = mutableStateOf(source?.cleanedTranscript.orEmpty())
    val title = mutableStateOf(source?.title.orEmpty())
    val tags = mutableStateOf(source?.tags.orEmpty().joinToString(", "))
    val category = mutableStateOf(source?.category.orEmpty())

    fun sync(source: RecordingTranscriptionState?) {
        if (source == null || original == source) return
        // Populate a later transcription result without replacing unsaved edits.
        if (rawText.value == original?.transcript.orEmpty()) rawText.value = source?.transcript.orEmpty()
        if (cleanedText.value == original?.cleanedTranscript.orEmpty()) cleanedText.value = source?.cleanedTranscript.orEmpty()
        if (title.value == original?.title.orEmpty()) title.value = source?.title.orEmpty()
        if (tags.value == original?.tags.orEmpty().joinToString(", ")) tags.value = source?.tags.orEmpty().joinToString(", ")
        if (category.value == original?.category.orEmpty()) category.value = source?.category.orEmpty()
        original = source
    }
}
