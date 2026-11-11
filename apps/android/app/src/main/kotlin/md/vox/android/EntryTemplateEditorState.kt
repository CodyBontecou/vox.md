package md.vox.android

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.listSaver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import md.vox.android.capturedomain.CaptureEntryTemplate

/** Owned above the compact/expanded list branches so resizing cannot discard the editor. */
internal class EntryTemplateEditorState(
    templateID: String? = null,
    name: String = "",
    prefix: String = "",
    suffix: String = "",
) {
    var templateID by mutableStateOf(templateID)
        private set
    var name by mutableStateOf(name)
    var prefix by mutableStateOf(prefix)
    var suffix by mutableStateOf(suffix)

    fun edit(template: CaptureEntryTemplate?) {
        templateID = template?.id ?: "new"
        name = template?.name.orEmpty()
        prefix = template?.entryPrefix.orEmpty()
        suffix = template?.entrySuffix.orEmpty()
    }

    fun dismiss() {
        templateID = null
        name = ""
        prefix = ""
        suffix = ""
    }

    companion object {
        val Saver = listSaver<EntryTemplateEditorState, String>(
            save = { listOf(it.templateID.orEmpty(), it.name, it.prefix, it.suffix) },
            restore = { EntryTemplateEditorState(it[0].ifEmpty { null }, it[1], it[2], it[3]) },
        )
    }
}

@Composable
internal fun rememberEntryTemplateEditorState(): EntryTemplateEditorState =
    rememberSaveable(saver = EntryTemplateEditorState.Saver) { EntryTemplateEditorState() }
