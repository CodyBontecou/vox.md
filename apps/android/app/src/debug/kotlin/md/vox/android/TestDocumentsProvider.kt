package md.vox.android

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException

class TestDocumentsProvider : DocumentsProvider() {
    override fun onCreate(): Boolean = true

    override fun queryRoots(projection: Array<out String>?): Cursor = cursor(projection, ROOT_COLUMNS).apply {
        newRow().apply {
            add(DocumentsContract.Root.COLUMN_ROOT_ID, ROOT_ID)
            add(DocumentsContract.Root.COLUMN_DOCUMENT_ID, ROOT_ID)
            add(DocumentsContract.Root.COLUMN_TITLE, "Vox Test Documents")
            add(DocumentsContract.Root.COLUMN_FLAGS, DocumentsContract.Root.FLAG_LOCAL_ONLY or DocumentsContract.Root.FLAG_SUPPORTS_CREATE)
            add(DocumentsContract.Root.COLUMN_MIME_TYPES, "*/*")
        }
    }

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor =
        cursor(projection, DOCUMENT_COLUMNS).also { includeDocument(it, documentId) }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor {
        val parent = document(parentDocumentId)
        if (!parent.isDirectory) throw FileNotFoundException(parentDocumentId)
        return cursor(projection, DOCUMENT_COLUMNS).also { result ->
            parent.listFiles().orEmpty().sortedBy(File::getName).forEach {
                includeDocument(result, documentId(it))
            }
        }
    }

    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
        if (displayName.isBlank() || displayName in setOf(".", "..") || displayName.contains('/') || displayName.contains('\\')) {
            throw FileNotFoundException("Invalid test document target")
        }
        val parent = document(parentDocumentId)
        if (!parent.isDirectory) throw FileNotFoundException(parentDocumentId)
        val file = File(parent, displayName)
        val created = if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) file.mkdir() else file.createNewFile()
        if (!created) throw FileNotFoundException("Document already exists")
        return documentId(file)
    }

    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean = runCatching {
        val parent = document(parentDocumentId).canonicalFile
        val child = document(documentId).canonicalFile
        child != parent && child.path.startsWith(parent.path + File.separator)
    }.getOrDefault(false)

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor {
        val file = document(documentId)
        if (!file.isFile) throw FileNotFoundException(documentId)
        val flags = when {
            mode.contains('w') && mode.contains('t') ->
                ParcelFileDescriptor.MODE_READ_WRITE or ParcelFileDescriptor.MODE_TRUNCATE
            mode.contains('w') -> ParcelFileDescriptor.MODE_READ_WRITE
            else -> ParcelFileDescriptor.MODE_READ_ONLY
        }
        return ParcelFileDescriptor.open(file, flags)
    }

    override fun deleteDocument(documentId: String) {
        val file = document(documentId)
        if (file == root() || !file.deleteRecursively()) throw FileNotFoundException(documentId)
    }

    private fun includeDocument(cursor: MatrixCursor, documentId: String) {
        if (documentId == ROOT_ID) {
            cursor.newRow().apply {
                add(DocumentsContract.Document.COLUMN_DOCUMENT_ID, ROOT_ID)
                add(DocumentsContract.Document.COLUMN_DISPLAY_NAME, "Vox Test Documents")
                add(DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.MIME_TYPE_DIR)
                add(DocumentsContract.Document.COLUMN_FLAGS, DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE)
            }
            return
        }
        val file = document(documentId)
        if (!file.exists()) throw FileNotFoundException(documentId)
        cursor.newRow().apply {
            add(DocumentsContract.Document.COLUMN_DOCUMENT_ID, documentId)
            add(DocumentsContract.Document.COLUMN_DISPLAY_NAME, file.name)
            add(
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                if (file.isDirectory) DocumentsContract.Document.MIME_TYPE_DIR else mimeType(file.name),
            )
            add(
                DocumentsContract.Document.COLUMN_FLAGS,
                if (file.isDirectory) {
                    DocumentsContract.Document.FLAG_DIR_SUPPORTS_CREATE or DocumentsContract.Document.FLAG_SUPPORTS_DELETE
                } else {
                    DocumentsContract.Document.FLAG_SUPPORTS_WRITE or DocumentsContract.Document.FLAG_SUPPORTS_DELETE
                },
            )
            add(DocumentsContract.Document.COLUMN_SIZE, file.length())
            add(DocumentsContract.Document.COLUMN_LAST_MODIFIED, file.lastModified())
        }
    }

    private fun document(documentId: String): File {
        if (documentId == ROOT_ID) return root()
        val segments = documentId.split('/')
        if (segments.isEmpty() || segments.any { it.isBlank() || it in setOf(".", "..") || it.contains('\\') }) {
            throw FileNotFoundException(documentId)
        }
        val root = root().canonicalFile
        val file = File(root, segments.joinToString(File.separator)).canonicalFile
        if (!file.path.startsWith(root.path + File.separator)) throw FileNotFoundException(documentId)
        return file
    }

    private fun documentId(file: File): String {
        val root = root().canonicalFile
        val resolved = file.canonicalFile
        if (!resolved.path.startsWith(root.path + File.separator)) throw FileNotFoundException(file.path)
        return resolved.relativeTo(root).path.replace(File.separatorChar, '/')
    }

    private fun root(): File = File(requireNotNull(context).filesDir, ROOT_DIRECTORY).apply { mkdirs() }

    private fun cursor(projection: Array<out String>?, defaults: Array<String>) =
        MatrixCursor(projection?.map(String::toString)?.toTypedArray() ?: defaults)

    private fun mimeType(name: String): String = when (name.substringAfterLast('.', "").lowercase()) {
        "json" -> "application/json"
        "yaml", "yml" -> "application/yaml"
        "md", "markdown" -> "text/markdown"
        "m4a" -> "audio/mp4"
        "mp3" -> "audio/mpeg"
        "ogg", "opus" -> "audio/ogg"
        "flac" -> "audio/flac"
        "wav" -> "audio/wav"
        else -> "text/plain"
    }

    companion object {
        const val AUTHORITY = "md.vox.android.test.documents"
        const val ROOT_ID = "root"
        private const val ROOT_DIRECTORY = "vox-test-documents"
        private val ROOT_COLUMNS = arrayOf(
            DocumentsContract.Root.COLUMN_ROOT_ID,
            DocumentsContract.Root.COLUMN_DOCUMENT_ID,
            DocumentsContract.Root.COLUMN_TITLE,
            DocumentsContract.Root.COLUMN_FLAGS,
            DocumentsContract.Root.COLUMN_MIME_TYPES,
        )
        private val DOCUMENT_COLUMNS = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_FLAGS,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
    }
}
