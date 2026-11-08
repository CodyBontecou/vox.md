package md.vox.android

import androidx.compose.runtime.mutableStateListOf
import androidx.compose.ui.text.input.TextFieldValue
import androidx.lifecycle.ViewModel

/** Retain edits across rotation without putting up to 100 full drafts into the saved-state Bundle. */
internal class CaptureUndoViewModel : ViewModel() {
    val entries = mutableStateListOf<TextFieldValue>()
}
