package md.vox.android

import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.widget.Toast
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.FileProvider
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.LiveNoteLocation
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import java.io.File

/**
 * Share and export for Files: notes are read from the vault, copied into the app cache,
 * then handed to the share sheet (FileProvider URIs) or written into a folder the user
 * picks with the system folder picker. The vault files themselves are never moved.
 */
@Stable
internal class VaultSharing(
    private val context: Context,
    private val scope: CoroutineScope,
    private val destination: CaptureDestination,
    private val read: suspend (LiveNoteLocation) -> String?,
    private val pickFolder: () -> Unit,
) {
    var isPreparing by mutableStateOf(false)
        private set
    private var pendingExport: List<File> = emptyList()

    fun share(paths: List<String>) = prepare(paths) { files ->
        val uris = files.map { FileProvider.getUriForFile(context, "${context.packageName}.files", it) }
        val send = if (uris.size == 1) {
            Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uris.first())
        } else {
            Intent(Intent.ACTION_SEND_MULTIPLE).putParcelableArrayListExtra(Intent.EXTRA_STREAM, ArrayList(uris))
        }.apply {
            type = "text/markdown"
            clipData = ClipData.newRawUri(null, uris.first()).also { clip -> uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) } }
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(send, null))
    }

    fun export(paths: List<String>) = prepare(paths) { files ->
        pendingExport = files
        pickFolder()
    }

    /** Called with the folder the user picked (null when they backed out). */
    fun finishExport(tree: Uri?) {
        val files = pendingExport
        pendingExport = emptyList()
        if (tree == null || files.isEmpty()) return
        scope.launch {
            isPreparing = true
            val written = withContext(Dispatchers.IO) {
                val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
                files.count { file ->
                    runCatching {
                        val created = DocumentsContract.createDocument(context.contentResolver, parent, "text/markdown", file.name)
                            ?: return@runCatching false
                        context.contentResolver.openOutputStream(created, "wt")?.use { it.write(file.readBytes()) } != null
                    }.getOrDefault(false)
                }
            }
            isPreparing = false
            val message = when {
                written == 0 -> voxStringRaw(context, "Couldn't export the notes.")
                written == 1 -> voxStringRaw(context, "Exported 1 note.")
                else -> voxStringRaw(context, "Exported %@ notes.").replace("%@", written.toString())
            }
            Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
        }
    }

    private fun prepare(paths: List<String>, then: (List<File>) -> Unit) {
        if (paths.isEmpty() || isPreparing) return
        scope.launch {
            isPreparing = true
            val files = copyToCache(paths)
            isPreparing = false
            if (files.isEmpty()) {
                Toast.makeText(context, voxStringRaw(context, "Couldn't read the selected notes."), Toast.LENGTH_SHORT).show()
            } else {
                then(files)
            }
        }
    }

    private suspend fun copyToCache(paths: List<String>): List<File> {
        val texts = paths.map { path -> path to read(LiveNoteLocation(destination.id, destination.treeUri, path)) }
        return withContext(Dispatchers.IO) {
            val shareRoot = File(context.cacheDir, "vault-shares")
            // Earlier shares are finished by the time a new one starts.
            shareRoot.deleteRecursively()
            val folder = File(shareRoot, System.currentTimeMillis().toString()).apply { mkdirs() }
            val used = mutableSetOf<String>()
            texts.mapNotNull { (path, text) ->
                text ?: return@mapNotNull null
                val name = uniqueShareName(path.substringAfterLast('/'), used)
                runCatching { File(folder, name).apply { writeText(text) } }.getOrNull()
            }
        }
    }
}

/** Same-named notes from different folders get " (2)", " (3)"… */
internal fun uniqueShareName(name: String, used: MutableSet<String>): String {
    if (used.add(name.lowercase())) return name
    val dot = name.lastIndexOf('.')
    val stem = if (dot > 0) name.substring(0, dot) else name
    val ext = if (dot > 0) name.substring(dot) else ""
    var index = 2
    while (true) {
        val candidate = "$stem ($index)$ext"
        if (used.add(candidate.lowercase())) return candidate
        index += 1
    }
}

private fun voxStringRaw(context: Context, source: String): String {
    val locale = context.resources.configuration.locales[0] ?: java.util.Locale.ENGLISH
    return runCatching { RuntimeLocalization.translate(context, locale, source) }.getOrDefault(source)
}

@Composable
internal fun rememberVaultSharing(destination: CaptureDestination, read: suspend (LiveNoteLocation) -> String?): VaultSharing {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var holder by remember { mutableStateOf<VaultSharing?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri -> holder?.finishExport(uri) }
    return remember(destination.id, destination.treeUri) {
        VaultSharing(context, scope, destination, read) { picker.launch(null) }.also { holder = it }
    }
}

/** Header while selecting: Select all on the left, count, Done on the right. */
@Composable
internal fun VaultSelectionHeader(selectedCount: Int, allSelected: Boolean, onToggleAll: () -> Unit, onDone: () -> Unit) {
    val c = Signal.colors
    Row(
        Modifier.fillMaxWidth().statusBarsPadding().padding(start = 12.dp, end = 12.dp, top = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SignalButton(
            text = if (allSelected) voxString("Deselect all") else voxString("Select all"),
            onClick = onToggleAll,
            variant = SignalButtonVariant.SECONDARY,
            size = SignalButtonSize.MEDIUM,
            modifier = Modifier.testTag("files-select-all"),
        )
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Text(
                if (selectedCount == 0) voxString("Select notes") else voxFormat("%@ selected", selectedCount.toString()),
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Medium),
                color = c.text,
            )
        }
        SignalButton(
            text = voxString("Done"),
            onClick = onDone,
            size = SignalButtonSize.MEDIUM,
            modifier = Modifier.testTag("files-select-done"),
        )
    }
}

/** Bottom bar while selecting: Share and Export. */
@Composable
internal fun VaultSelectionBar(selectedCount: Int, isPreparing: Boolean, onShare: () -> Unit, onExport: () -> Unit, modifier: Modifier = Modifier) {
    val c = Signal.colors
    val enabled = selectedCount > 0 && !isPreparing
    Box(modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp), contentAlignment = Alignment.Center) {
        Row(Modifier.fillMaxWidth().alpha(if (selectedCount == 0) 0.5f else 1f), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            BarButton(voxString("Share"), Icons.Outlined.Share, filled = true, enabled = enabled, onClick = onShare, modifier = Modifier.weight(1f).testTag("files-share"))
            BarButton(voxString("Export"), Icons.Outlined.Folder, filled = false, enabled = enabled, onClick = onExport, modifier = Modifier.weight(1f).testTag("files-export"))
        }
        if (isPreparing) CircularProgressIndicator(Modifier.size(22.dp), color = c.tint, trackColor = c.well, strokeWidth = 2.dp)
    }
}

@Composable
private fun BarButton(label: String, icon: ImageVector, filled: Boolean, enabled: Boolean, onClick: () -> Unit, modifier: Modifier) {
    val c = Signal.colors
    val content = if (filled) c.bg else c.text
    Row(
        modifier
            .height(56.dp)
            .clip(CircleShape)
            .background(if (filled) c.text else c.card)
            .then(if (filled) Modifier else Modifier.border(1.dp, c.border, CircleShape))
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Icon(icon, contentDescription = null, tint = content, modifier = Modifier.size(19.dp))
        Text(label, style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold), color = content, modifier = Modifier.padding(start = 8.dp))
    }
}
