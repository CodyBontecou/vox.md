package md.vox.android.data

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.LiveNoteCopyResult
import md.vox.android.capturedomain.LiveNoteFile
import md.vox.android.capturedomain.LiveNoteFileStore
import md.vox.android.capturedomain.LiveNoteLocation
import md.vox.android.capturedomain.LiveNotePlan
import md.vox.android.capturedomain.LiveNoteReadResult
import md.vox.android.capturedomain.LiveNoteVersion
import md.vox.android.capturedomain.LiveNoteWriteResult
import md.vox.android.capturedomain.VaultBrowser
import md.vox.android.capturedomain.VaultEntry
import md.vox.android.capturedomain.VaultListing
import md.vox.android.capturedomain.VaultDestination
import java.security.MessageDigest

/**
 * Whole-file reads and version-checked replaces for a bound live note, plus the Files-tree
 * listings, over the same [SafDocumentsGateway] the capture commit uses. Every write is
 * verified by reading the bytes back, like the durable commit. All work runs on IO.
 */
class SafLiveNoteFileStore internal constructor(
    private val gateway: SafDocumentsGateway,
    private val maximumBytes: Long = MAX_NOTE_BYTES,
) : LiveNoteFileStore, VaultBrowser, md.vox.android.capturedomain.VaultMediaResolver {
    constructor(context: Context) : this(AndroidSafDocumentsGateway(context))

    override suspend fun read(location: LiveNoteLocation): LiveNoteReadResult = withContext(Dispatchers.IO) {
        val destination = vault(location) ?: return@withContext LiveNoteReadResult.Unreachable("invalidDestination")
        if (!gateway.revalidateGrant(destination)) return@withContext LiveNoteReadResult.Unreachable("permissionLost")
        when (val found = locate(destination, location, createFolders = false)) {
            Located.Missing -> LiveNoteReadResult.Missing
            is Located.Unreachable -> LiveNoteReadResult.Unreachable(found.reason)
            is Located.Found -> when (val file = readFile(location, found.handle)) {
                null -> LiveNoteReadResult.Unreachable("readFailed")
                else -> LiveNoteReadResult.Found(file)
            }
            is Located.Absent -> LiveNoteReadResult.Missing
        }
    }

    override suspend fun replace(location: LiveNoteLocation, text: String, expected: LiveNoteVersion?): LiveNoteWriteResult =
        withContext(Dispatchers.IO) {
            val destination = vault(location) ?: return@withContext LiveNoteWriteResult.Unreachable("invalidDestination")
            if (!gateway.revalidateGrant(destination)) return@withContext LiveNoteWriteResult.Unreachable("permissionLost")
            val bytes = text.toByteArray(Charsets.UTF_8)
            if (bytes.size > maximumBytes) return@withContext LiveNoteWriteResult.Unreachable("tooLarge")
            when (val found = locate(destination, location, createFolders = expected == null)) {
                Located.Missing -> if (expected != null) LiveNoteWriteResult.Missing else LiveNoteWriteResult.Unreachable("folderUnavailable")
                is Located.Unreachable -> LiveNoteWriteResult.Unreachable(found.reason)
                is Located.Absent -> {
                    if (expected != null) return@withContext LiveNoteWriteResult.Missing
                    val created = (gateway.createLiveNoteDocument(found.folder, location.fileName, MARKDOWN) as? SafResult.Success)?.value
                        ?: return@withContext LiveNoteWriteResult.Unreachable("createFailed")
                    writeVerified(created, bytes)
                }
                is Located.Found -> {
                    val current = readFile(location, found.handle) ?: return@withContext LiveNoteWriteResult.Unreachable("readFailed")
                    if (expected == null || !current.version.sameContentAs(expected)) {
                        return@withContext LiveNoteWriteResult.Changed(current)
                    }
                    writeVerified(found.handle, bytes)
                }
            }
        }

    override suspend fun createCopy(location: LiveNoteLocation, text: String): LiveNoteCopyResult = withContext(Dispatchers.IO) {
        val destination = vault(location) ?: return@withContext LiveNoteCopyResult.Unreachable("invalidDestination")
        if (!gateway.revalidateGrant(destination)) return@withContext LiveNoteCopyResult.Unreachable("permissionLost")
        val folder = gateway.resolveFolder(destination, location.folderSegments, createMissing = true)
            ?: return@withContext LiveNoteCopyResult.Unreachable("folderUnavailable")
        val occupied = gateway.listChildDisplayNames(folder)?.toSet()
            ?: return@withContext LiveNoteCopyResult.Unreachable("listFailed")
        val target = location.sibling(LiveNotePlan.copyName(location.fileName, occupied))
        val created = (gateway.createLiveNoteDocument(folder, target.fileName, MARKDOWN) as? SafResult.Success)?.value
            ?: return@withContext LiveNoteCopyResult.Unreachable("createFailed")
        when (val written = writeVerified(created, text.toByteArray(Charsets.UTF_8))) {
            is LiveNoteWriteResult.Written -> LiveNoteCopyResult.Created(target, written.version)
            else -> LiveNoteCopyResult.Unreachable("writeFailed")
        }
    }

    override suspend fun list(destination: CaptureDestination, relativeFolder: String, countChildren: Boolean): VaultListing =
        withContext(Dispatchers.IO) {
            val vault = runCatching { VaultDestination(destination.id, destination.treeUri) }.getOrNull()
                ?: return@withContext VaultListing.Unreachable("invalidDestination")
            if (!gateway.revalidateGrant(vault)) return@withContext VaultListing.Unreachable("permissionLost")
            val segments = relativeFolder.split('/').filter(String::isNotEmpty)
            val folder = gateway.resolveFolder(vault, segments, createMissing = false)
                ?: return@withContext if (gateway.resolveFolder(vault, emptyList(), createMissing = false) == null) {
                    VaultListing.Unreachable("rootUnavailable")
                } else VaultListing.Missing
            val children = gateway.listChildren(folder) ?: return@withContext VaultListing.Unreachable("listFailed")
            var counted = 0
            VaultListing.Listed(children.map { child ->
                val path = (segments + child.displayName).joinToString("/")
                val count = if (countChildren && child.isFolder && counted < MAX_COUNTED_FOLDERS) {
                    counted += 1
                    child.folder?.let { gateway.listChildren(it)?.count { entry -> !entry.displayName.startsWith(".") } }
                } else null
                VaultEntry(
                    name = child.displayName,
                    relativePath = path,
                    isFolder = child.isFolder,
                    lastModifiedEpochMillis = child.lastModifiedEpochMillis,
                    byteCount = child.byteCount,
                    childCount = count,
                )
            })
        }

    override suspend fun resolveMedia(destinationID: String, treeUri: String, candidates: List<String>, fileName: String): String? =
        withContext(Dispatchers.IO) {
            val vault = runCatching { VaultDestination(destinationID, treeUri) }.getOrNull() ?: return@withContext null
            if (!gateway.revalidateGrant(vault)) return@withContext null
            for (path in candidates) {
                val segments = path.split('/').filter(String::isNotEmpty)
                if (segments.isEmpty()) continue
                val folder = gateway.resolveFolder(vault, segments.dropLast(1), createMissing = false) ?: continue
                gateway.findChildByDisplayName(folder, segments.last()).firstOrNull()?.let { return@withContext it.key }
            }
            // Bounded breadth-first search by file name, skipping hidden folders (.obsidian, .trash).
            val root = gateway.resolveFolder(vault, emptyList(), createMissing = false) ?: return@withContext null
            val queue = ArrayDeque(listOf(root to 0))
            var visited = 0
            while (queue.isNotEmpty() && visited < MAX_SEARCHED_FOLDERS) {
                val (folder, depth) = queue.removeFirst()
                visited += 1
                val children = gateway.listChildren(folder) ?: continue
                children.firstOrNull { !it.isFolder && it.displayName == fileName }?.let { return@withContext it.document.key }
                if (depth < MAX_SEARCH_DEPTH) children.filter { it.isFolder && !it.displayName.startsWith(".") }
                    .forEach { child -> child.folder?.let { queue.addLast(it to depth + 1) } }
            }
            null
        }

    private sealed interface Located {
        data class Found(val handle: SafDocumentHandle) : Located
        /** The folder exists and holds no file of that name. */
        data class Absent(val folder: SafFolderHandle) : Located
        /** The folder chain is gone but the vault root is reachable. */
        data object Missing : Located
        data class Unreachable(val reason: String) : Located
    }

    private fun locate(destination: VaultDestination, location: LiveNoteLocation, createFolders: Boolean): Located {
        if (location.fileName.isEmpty()) return Located.Unreachable("invalidPath")
        val folder = gateway.resolveFolder(destination, location.folderSegments, createMissing = createFolders)
            ?: return if (gateway.resolveFolder(destination, emptyList(), createMissing = false) == null) {
                Located.Unreachable("rootUnavailable")
            } else Located.Missing
        val matches = gateway.findChildByDisplayName(folder, location.fileName)
        return when (matches.size) {
            0 -> Located.Absent(folder)
            1 -> Located.Found(matches.single())
            else -> Located.Unreachable("ambiguousName")
        }
    }

    private fun readFile(location: LiveNoteLocation, handle: SafDocumentHandle): LiveNoteFile? {
        val bytes = (gateway.readDocument(handle, maximumBytes) as? SafResult.Success)?.value ?: return null
        val stat = (gateway.statDocument(handle) as? SafResult.Success)?.value
        return LiveNoteFile(location, bytes.toString(Charsets.UTF_8), versionOf(bytes, stat?.lastModifiedEpochMillis))
    }

    private fun writeVerified(handle: SafDocumentHandle, bytes: ByteArray): LiveNoteWriteResult {
        val written = gateway.replaceDocument(handle, bytes)
        if (written is SafResult.Error) {
            return LiveNoteWriteResult.Unreachable(written.code)
        }
        val verified = (gateway.readBackDocument(handle) as? SafResult.Success)?.value
            ?: return LiveNoteWriteResult.Unreachable("readBackFailed")
        val expected = versionOf(bytes, null)
        if (verified.first != expected.byteCount || verified.second != expected.sha256) {
            return LiveNoteWriteResult.Unreachable("readBackMismatch")
        }
        val stat = (gateway.statDocument(handle) as? SafResult.Success)?.value
        return LiveNoteWriteResult.Written(expected.copy(lastModifiedEpochMillis = stat?.lastModifiedEpochMillis))
    }

    private fun vault(location: LiveNoteLocation): VaultDestination? =
        runCatching { VaultDestination(location.destinationID, location.treeUri) }.getOrNull()

    internal companion object {
        const val MARKDOWN = "text/markdown; charset=utf-8"
        /** Notes larger than this open read-only elsewhere; the editor is for notes, not archives. */
        const val MAX_NOTE_BYTES = 2L * 1024 * 1024
        const val MAX_COUNTED_FOLDERS = 64
        const val MAX_SEARCHED_FOLDERS = 200
        const val MAX_SEARCH_DEPTH = 6

        fun versionOf(bytes: ByteArray, lastModified: Long?): LiveNoteVersion {
            val hash = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
            return LiveNoteVersion(hash, bytes.size.toLong(), lastModified)
        }
    }
}
