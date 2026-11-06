package md.vox.android.data

import android.util.AtomicFile
import java.io.File
import kotlinx.serialization.json.*
import md.vox.android.capturedomain.CaptureDestination

/** Immutable native capability bindings, persisted before the hash-bound request references them. */
internal class CaptureDestinationBindings(private val directory: File) {
    @Synchronized fun save(destination: CaptureDestination) {
        require(UUID_PATTERN.matches(destination.id))
        directory.mkdirs()
        val file = AtomicFile(File(directory, "${destination.id}.json"))
        if (file.baseFile.exists()) {
            check(load(destination.id)?.treeUri == destination.treeUri) { "destinationRebinding" }
            return
        }
        val bytes = buildJsonObject {
            put("id", destination.id); put("name", destination.displayName); put("tree", destination.treeUri)
        }.toString().toByteArray()
        val output = file.startWrite()
        try {
            output.write(bytes); file.finishWrite(output)
            AndroidDurableFileOps().syncDirectory(directory)
            AndroidDurableFileOps().syncDirectory(directory.parentFile!!)
        } catch (error: Throwable) { file.failWrite(output); throw error }
    }

    @Synchronized fun load(id: String): CaptureDestination? {
        if (!UUID_PATTERN.matches(id)) return null
        return runCatching {
            val value = Json.parseToJsonElement(AtomicFile(File(directory, "$id.json")).readFully().toString(Charsets.UTF_8)).jsonObject
            CaptureDestination(value.getValue("id").jsonPrimitive.content, value.getValue("name").jsonPrimitive.content, value.getValue("tree").jsonPrimitive.content)
                .also { require(it.id == id && it.treeUri.startsWith("content://")) }
        }.getOrNull()
    }
}
