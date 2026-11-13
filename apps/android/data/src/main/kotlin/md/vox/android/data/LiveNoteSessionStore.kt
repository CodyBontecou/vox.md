package md.vox.android.data

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import md.vox.android.capturedomain.LiveNoteBinding
import md.vox.android.capturedomain.LiveNoteLocation
import md.vox.android.capturedomain.LiveNoteParked
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.buildJsonArray
import md.vox.android.capturedomain.LiveNotePendingWrite
import md.vox.android.capturedomain.LiveNoteRange
import md.vox.android.capturedomain.LiveNoteSession
import md.vox.android.capturedomain.LiveNoteVersion
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * App-private persistence for Live Notes: the composer's session (binding, queued first write
 * and the editor text, so unsaved or offline edits survive process death) and a small ledger
 * of which vault file each delivered capture wrote. Lives in no-backup storage next to the
 * capture packages; nothing here is ever sent anywhere.
 */
internal class LiveNoteSessionStore(private val directory: File) {
    private val sessionFile get() = File(directory, "session.json")
    private val ledgerDirectory get() = File(directory, "committed")

    @Synchronized fun loadSession(): LiveNoteSession? = runCatching {
        if (!sessionFile.isFile) return null
        val value = Json.parseToJsonElement(sessionFile.readText(Charsets.UTF_8)).jsonObject
        LiveNoteSession(
            binding = (value["binding"] as? JsonObject)?.let(::decodeBinding),
            pending = (value["pending"] as? JsonObject)?.let(::decodePending),
            localText = value.string("text").orEmpty(),
            highlight = (value["highlight"] as? JsonObject)?.let { range ->
                val start = range.long("start")?.toInt() ?: return@let null
                val end = range.long("end")?.toInt() ?: return@let null
                LiveNoteRange(start, end)
            },
            parked = (value["parked"] as? JsonArray).orEmpty().mapNotNull { element ->
                val item = element as? JsonObject ?: return@mapNotNull null
                LiveNoteParked(
                    binding = (item["binding"] as? JsonObject)?.let(::decodeBinding),
                    pending = (item["pending"] as? JsonObject)?.let(::decodePending),
                    localText = item.string("text") ?: return@mapNotNull null,
                ).takeIf { it.binding != null || it.pending != null }
            },
        )
    }.getOrNull()

    @Synchronized fun saveSession(session: LiveNoteSession) {
        if (!session.isStarted && session.localText.isEmpty() && session.parked.isEmpty()) {
            sessionFile.delete()
            return
        }
        val json = buildJsonObject {
            session.binding?.let { put("binding", encodeBinding(it)) }
            session.pending?.let { put("pending", encodePending(it)) }
            put("text", session.localText)
            session.highlight?.let { range -> put("highlight", buildJsonObject { put("start", range.start); put("end", range.end) }) }
            if (session.parked.isNotEmpty()) put("parked", buildJsonArray {
                session.parked.forEach { parked ->
                    add(buildJsonObject {
                        parked.binding?.let { put("binding", encodeBinding(it)) }
                        parked.pending?.let { put("pending", encodePending(it)) }
                        put("text", parked.localText)
                    })
                }
            })
        }
        writeAtomically(sessionFile, json.toString().toByteArray(Charsets.UTF_8))
    }

    @Synchronized fun committedLocation(requestID: String): LiveNoteLocation? = runCatching {
        if (!UUID_PATTERN.matches(requestID)) return null
        val file = File(ledgerDirectory, "$requestID.json")
        if (!file.isFile) return null
        decodeLocation(Json.parseToJsonElement(file.readText(Charsets.UTF_8)).jsonObject)
    }.getOrNull()

    @Synchronized fun saveCommittedLocation(requestID: String, location: LiveNoteLocation) {
        require(UUID_PATTERN.matches(requestID))
        writeAtomically(File(ledgerDirectory, "$requestID.json"), encodeLocation(location).toString().toByteArray(Charsets.UTF_8))
        prune()
    }

    /** Only recent captures can still be bound or reopened; keep the ledger small. */
    private fun prune() {
        val files = ledgerDirectory.listFiles()?.filter { it.name.endsWith(".json") } ?: return
        if (files.size <= MAX_LEDGER_ENTRIES) return
        files.sortedBy(File::lastModified).take(files.size - MAX_LEDGER_ENTRIES).forEach(File::delete)
    }

    private fun writeAtomically(target: File, bytes: ByteArray) {
        target.parentFile?.mkdirs()
        val temporary = File(target.parentFile, ".${target.name}.tmp")
        temporary.outputStream().use { stream ->
            stream.write(bytes)
            stream.fd.sync()
        }
        Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }

    private fun encodeLocation(location: LiveNoteLocation) = buildJsonObject {
        put("destinationID", location.destinationID)
        put("tree", location.treeUri)
        put("path", location.relativePath)
    }

    private fun decodeLocation(value: JsonObject): LiveNoteLocation? {
        val location = LiveNoteLocation(
            destinationID = value.string("destinationID") ?: return null,
            treeUri = value.string("tree")?.takeIf { it.startsWith("content://") } ?: return null,
            relativePath = value.string("path")?.takeIf(String::isNotBlank) ?: return null,
        )
        return location.takeIf { it.segments.none { segment -> segment == ".." || segment == "." } }
    }

    private fun encodeBinding(binding: LiveNoteBinding) = buildJsonObject {
        put("location", encodeLocation(binding.location))
        binding.presetID?.let { put("presetID", it) }
        binding.presetName?.let { put("presetName", it) }
        binding.requestID?.let { put("requestID", it) }
        put("append", binding.isAppendTarget)
        put("sha256", binding.version.sha256)
        put("bytes", binding.version.byteCount)
        binding.version.lastModifiedEpochMillis?.let { put("modified", it) }
        put("saved", binding.savedText)
    }

    private fun decodeBinding(value: JsonObject): LiveNoteBinding? = LiveNoteBinding(
        location = (value["location"] as? JsonObject)?.let(::decodeLocation) ?: return null,
        presetID = value.string("presetID"),
        presetName = value.string("presetName"),
        requestID = value.string("requestID"),
        isAppendTarget = value["append"]?.jsonPrimitive?.booleanOrNull ?: false,
        version = LiveNoteVersion(
            sha256 = value.string("sha256") ?: return null,
            byteCount = value.long("bytes") ?: return null,
            lastModifiedEpochMillis = value.long("modified"),
        ),
        savedText = value.string("saved") ?: return null,
    )

    private fun encodePending(pending: LiveNotePendingWrite) = buildJsonObject {
        put("requestID", pending.requestID)
        put("submitted", pending.submittedText)
        pending.presetID?.let { put("presetID", it) }
        pending.presetName?.let { put("presetName", it) }
        put("append", pending.isAppendTarget)
        put("last", pending.prefersLastOccurrence)
        pending.plannedPath?.let { put("planned", it) }
    }

    private fun decodePending(value: JsonObject): LiveNotePendingWrite? = LiveNotePendingWrite(
        requestID = value.string("requestID")?.takeIf(UUID_PATTERN::matches) ?: return null,
        submittedText = value.string("submitted") ?: return null,
        presetID = value.string("presetID"),
        presetName = value.string("presetName"),
        isAppendTarget = value["append"]?.jsonPrimitive?.booleanOrNull ?: false,
        prefersLastOccurrence = value["last"]?.jsonPrimitive?.booleanOrNull ?: true,
        plannedPath = value.string("planned"),
    )

    private fun JsonObject.string(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull
    private fun JsonObject.long(key: String): Long? = this[key]?.jsonPrimitive?.longOrNull

    private companion object {
        const val MAX_LEDGER_ENTRIES = 256
    }
}
