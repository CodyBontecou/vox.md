package md.vox.android

import java.io.File
import java.io.InputStream
import java.util.UUID

/** Keep export snapshots out of Android's size-limited saved-instance-state Bundle. */
internal class PendingTextExportStore(private val directory: File) {
    fun stage(text: String): String {
        directory.mkdirs()
        val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1_000L
        directory.listFiles()?.filter { it.lastModified() < cutoff }?.forEach(File::delete)
        val key = UUID.randomUUID().toString()
        file(key).writeText(text, Charsets.UTF_8)
        return key
    }

    fun consume(key: String, write: (InputStream) -> Boolean): Boolean {
        val file = file(key)
        return try {
            if (file.isFile) file.inputStream().use(write) else false
        } finally {
            file.delete()
        }
    }

    fun discard(key: String) { file(key).delete() }

    private fun file(key: String): File {
        require(UUID.fromString(key).toString() == key)
        return File(directory, "$key.md")
    }
}
