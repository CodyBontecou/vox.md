package md.vox.android

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.Saver
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue

/** A picker result belongs to the request launched before activity recreation. */
internal class PendingDocumentRequest(initialKey: String? = null) {
    private var key by mutableStateOf(initialKey)

    fun begin(key: String) {
        require(key.isNotEmpty())
        this.key = key
    }

    /** Also consume canceled results so a later picker cannot reuse an old target. */
    fun consume(): String? = key.also { key = null }

    companion object {
        val Saver = Saver<PendingDocumentRequest, String>(
            save = { it.key.orEmpty() },
            restore = { PendingDocumentRequest(it.takeIf(String::isNotEmpty)) },
        )
    }
}

@Composable
internal fun rememberPendingDocumentRequest(): PendingDocumentRequest =
    rememberSaveable(saver = PendingDocumentRequest.Saver) { PendingDocumentRequest() }
