package md.vox.android.data

import kotlinx.coroutines.runBlocking
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.LiveNoteCopyResult
import md.vox.android.capturedomain.LiveNoteLocation
import md.vox.android.capturedomain.LiveNoteReadResult
import md.vox.android.capturedomain.LiveNoteWriteResult
import md.vox.android.capturedomain.VaultDestination
import md.vox.android.capturedomain.VaultListing
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.security.MessageDigest

class SafLiveNoteFileStoreTest {
    private val destinationID = "22222222-2222-4222-8222-222222222222"
    private val note = LiveNoteLocation(destinationID, "content://vault/tree", "Inbox/Radiator.md")

    @Test fun replaceChecksTheVersionWritesTruncatingAndVerifies() = runBlocking {
        val gateway = MemoryGateway().apply { files["Inbox/Radiator.md"] = "a long original body\n".toByteArray() }
        val store = SafLiveNoteFileStore(gateway)
        val read = store.read(note) as LiveNoteReadResult.Found
        val written = store.replace(note, "short\n", read.file.version) as LiveNoteWriteResult.Written
        assertEquals("short\n", gateway.text("Inbox/Radiator.md"))
        assertEquals(6L, written.version.byteCount)
        assertEquals(1_700L, written.version.lastModifiedEpochMillis)
    }

    @Test fun replaceRefusesWhenTheFileChangedElsewhere() = runBlocking {
        val gateway = MemoryGateway().apply { files["Inbox/Radiator.md"] = "base\n".toByteArray() }
        val store = SafLiveNoteFileStore(gateway)
        val base = (store.read(note) as LiveNoteReadResult.Found).file.version
        gateway.files["Inbox/Radiator.md"] = "theirs\n".toByteArray()
        val result = store.replace(note, "mine\n", base) as LiveNoteWriteResult.Changed
        assertEquals("theirs\n", result.current.text)
        assertEquals("theirs\n", gateway.text("Inbox/Radiator.md"))
    }

    @Test fun lostGrantIsUnreachableAndMissingFilesAreReported() = runBlocking {
        val gateway = MemoryGateway()
        val store = SafLiveNoteFileStore(gateway)
        assertEquals(LiveNoteReadResult.Missing, store.read(note))
        gateway.grantValid = false
        assertTrue(store.read(note) is LiveNoteReadResult.Unreachable)
        assertTrue(store.replace(note, "x", null) is LiveNoteWriteResult.Unreachable)
    }

    @Test fun copiesAreWrittenBesideTheFileWithAFreeName() = runBlocking {
        val gateway = MemoryGateway().apply {
            files["Inbox/Radiator.md"] = "theirs\n".toByteArray()
            files["Inbox/Radiator (Vox).md"] = "older copy\n".toByteArray()
        }
        val copy = SafLiveNoteFileStore(gateway).createCopy(note, "mine\n") as LiveNoteCopyResult.Created
        assertEquals("Inbox/Radiator (Vox 2).md", copy.location.relativePath)
        assertEquals("mine\n", gateway.text("Inbox/Radiator (Vox 2).md"))
    }

    @Test fun listsFoldersWithCounts() = runBlocking {
        val gateway = MemoryGateway().apply {
            files["Inbox/a.md"] = "a".toByteArray()
            files["Inbox/b.md"] = "b".toByteArray()
            files["Tasks.md"] = "t".toByteArray()
        }
        val listing = SafLiveNoteFileStore(gateway).list(CaptureDestination(destinationID, "Vox Notes", "content://vault/tree"), "") as VaultListing.Listed
        val inbox = listing.entries.single { it.name == "Inbox" }
        assertTrue(inbox.isFolder)
        assertEquals(2, inbox.childCount)
        assertTrue(listing.entries.single { it.name == "Tasks.md" }.isMarkdown)
    }

    @Test fun mediaResolvesCandidatesInOrderThenSearchesByName() = runBlocking {
        val gateway = MemoryGateway().apply {
            files["attachments/a.wav"] = "x".toByteArray()
            files["Inbox/a.wav"] = "y".toByteArray()
            files["Deep/er/b.png"] = "z".toByteArray()
            files[".obsidian/c.png"] = "h".toByteArray()
        }
        val store = SafLiveNoteFileStore(gateway)
        assertEquals("attachments/a.wav", store.resolveMedia(destinationID, "content://vault/tree", listOf("attachments/a.wav", "Inbox/a.wav", "a.wav"), "a.wav"))
        assertEquals("Inbox/a.wav", store.resolveMedia(destinationID, "content://vault/tree", listOf("Attachments/a.wav", "Inbox/a.wav"), "a.wav"))
        assertEquals("Deep/er/b.png", store.resolveMedia(destinationID, "content://vault/tree", listOf("attachments/b.png"), "b.png"))
        assertEquals(null, store.resolveMedia(destinationID, "content://vault/tree", emptyList(), "c.png"))
    }

    /** Flat path → bytes map standing in for a SAF tree; folders are implied by paths. */
    private class MemoryGateway : SafDocumentsGateway {
        val files = linkedMapOf<String, ByteArray>()
        var grantValid = true

        fun text(path: String) = files[path]?.toString(Charsets.UTF_8)

        override fun revalidateGrant(destination: VaultDestination) = grantValid
        override fun listChildDisplayNames(parent: SafFolderHandle): List<String>? = listChildren(parent)?.map { it.displayName }
        override fun resolveFolder(destination: VaultDestination, segments: List<String>, createMissing: Boolean): SafFolderHandle? =
            if (grantValid) SafFolderHandle(segments.joinToString("/")) else null
        override fun createDocument(marker: DurableMarkerToken, parent: SafFolderHandle, displayName: String, mediaType: String): SafResult<SafDocumentHandle> =
            error("durable creates are not used by live notes")
        override fun writeDocument(handle: SafDocumentHandle, bytes: ByteArray, expectedLength: Long): SafResult<Unit> =
            error("live notes replace with truncation")
        override fun readBackDocument(handle: SafDocumentHandle): SafResult<Pair<Long, String>> {
            val bytes = files[handle.key] ?: return SafResult.error("providerFailure")
            return SafResult.success(bytes.size.toLong() to MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) })
        }
        override fun readDocument(handle: SafDocumentHandle, maximumBytes: Long): SafResult<ByteArray> =
            files[handle.key]?.let { SafResult.success(it.copyOf()) } ?: SafResult.error("providerFailure")
        override fun findChildByDisplayName(parent: SafFolderHandle, displayName: String): List<SafDocumentHandle> {
            val path = listOf(parent.key, displayName).filter(String::isNotEmpty).joinToString("/")
            return if (path in files) listOf(SafDocumentHandle(path)) else emptyList()
        }
        override fun listChildren(parent: SafFolderHandle): List<SafChildEntry>? {
            if (!grantValid) return null
            val prefix = if (parent.key.isEmpty()) "" else parent.key + "/"
            return files.keys.filter { it.startsWith(prefix) }
                .map { it.removePrefix(prefix).substringBefore('/') to it.removePrefix(prefix).contains('/') }
                .distinct()
                .map { (name, isFolder) ->
                    val path = prefix + name
                    SafChildEntry(name, isFolder, 1_700L, if (isFolder) null else files[path]?.size?.toLong(), SafDocumentHandle(path), if (isFolder) SafFolderHandle(path) else null)
                }
        }
        override fun statDocument(handle: SafDocumentHandle): SafResult<SafDocumentStat> =
            files[handle.key]?.let { SafResult.success(SafDocumentStat(it.size.toLong(), 1_700L)) } ?: SafResult.error("providerFailure")
        override fun replaceDocument(handle: SafDocumentHandle, bytes: ByteArray): SafResult<Unit> {
            files[handle.key] = bytes.copyOf()
            return SafResult.success(Unit)
        }
        override fun createLiveNoteDocument(parent: SafFolderHandle, displayName: String, mediaType: String): SafResult<SafDocumentHandle> {
            val path = listOf(parent.key, displayName).filter(String::isNotEmpty).joinToString("/")
            if (path in files) return SafResult.error("providerFailure")
            files[path] = ByteArray(0)
            return SafResult.success(SafDocumentHandle(path))
        }
    }
}
