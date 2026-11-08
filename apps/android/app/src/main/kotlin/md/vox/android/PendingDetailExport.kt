package md.vox.android

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Freeze bytes before the picker opens; restored callbacks need only a small UUID and format. */
@Composable
internal fun rememberDetailExport(
    completed: (format: String, written: Boolean) -> Unit,
): (format: String, text: String, filename: String) -> Unit {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val pending = rememberPendingDocumentRequest()
    val store = remember(context) { PendingTextExportStore(File(context.noBackupFilesDir, "pending-detail-exports")) }
    val onCompleted by rememberUpdatedState(completed)
    var staging by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("*/*")) { uri ->
        val request = pending.consume()
        if (request != null) {
            val (format, key) = request.split(':', limit = 2)
            scope.launch {
                val written = withContext(Dispatchers.IO) {
                    runCatching {
                        if (uri == null) {
                            store.discard(key)
                            false
                        } else store.consume(key) { input ->
                            context.contentResolver.openOutputStream(uri, "w")?.use { output ->
                                input.copyTo(output)
                                output.flush()
                                true
                            } ?: false
                        }
                    }.getOrDefault(false)
                }
                if (uri != null) onCompleted(format, written)
            }
        }
    }
    return { format, text, filename ->
        if (!staging) {
            staging = true
            scope.launch {
                try {
                    val key = withContext(Dispatchers.IO) { runCatching { store.stage(text) }.getOrNull() }
                    if (key == null) onCompleted(format, false) else {
                        pending.begin("$format:$key")
                        runCatching { picker.launch(filename) }.onFailure {
                            pending.consume()
                            withContext(Dispatchers.IO) { store.discard(key) }
                            onCompleted(format, false)
                        }
                    }
                } finally { staging = false }
            }
        }
    }
}
