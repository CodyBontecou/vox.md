package md.vox.android

import android.content.Context
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import android.util.Base64
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.capturedomain.WearProtocol
import md.vox.android.capturedomain.WearRemoteRecordingPhase
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingPresetSnapshotCodec

internal object PhoneWearBridge {
    suspend fun publishPresets(context: Context, collection: CapturePresetCollection) = withContext(Dispatchers.IO) {
        runCatching {
            val encoded = collection.presets.take(32).map(RecordingPresetSnapshotCodec::encode)
            require(encoded.sumOf(String::length) <= 90_000)
            val request = PutDataMapRequest.create(WearProtocol.PHONE_PRESETS_PATH).apply {
                dataMap.putInt(WearProtocol.KEY_PROTOCOL_VERSION, WearProtocol.VERSION)
                dataMap.putString(WearProtocol.KEY_ACTIVE_PRESET_ID, collection.activePresetID)
                dataMap.putStringArrayList(WearProtocol.KEY_PRESETS, ArrayList(encoded))
                dataMap.putLong("publishedAtEpochMillis", System.currentTimeMillis())
            }.asPutDataRequest().setUrgent()
            Tasks.await(Wearable.getDataClient(context).putDataItem(request))
        }
    }

    fun postStatus(
        context: Context,
        recordingID: String,
        phase: WearRemoteRecordingPhase,
        minimumRevision: Int,
        frontier: Int,
        message: String? = null,
    ): Boolean = runCatching {
        require(WearProtocol.recordingIDPattern.matches(recordingID))
        val revision = PhoneWearStatusRevisionStore.next(context, recordingID, minimumRevision)
        val request = PutDataMapRequest.create(WearProtocol.statusPath(recordingID)).apply {
            dataMap.putInt(WearProtocol.KEY_PROTOCOL_VERSION, WearProtocol.VERSION)
            dataMap.putString(WearProtocol.KEY_RECORDING_ID, recordingID)
            dataMap.putString(WearProtocol.KEY_PHASE, phase.wireValue)
            dataMap.putInt(WearProtocol.KEY_REVISION, revision)
            dataMap.putInt(WearProtocol.KEY_FRONTIER, frontier.coerceAtLeast(0))
            dataMap.putLong("updatedAtEpochMillis", System.currentTimeMillis())
            message?.take(160)?.let { dataMap.putString(WearProtocol.KEY_MESSAGE, it) }
        }.asPutDataRequest().setUrgent()
        Tasks.await(Wearable.getDataClient(context).putDataItem(request))
        true
    }.getOrDefault(false)

}

private object PhoneWearStatusRevisionStore {
    private const val FILE_NAME = "wear-remote-status-revisions-v1"

    @Synchronized
    fun next(context: Context, recordingID: String, minimumRevision: Int): Int {
        require(minimumRevision >= 0)
        val preferences = context.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)
        val current = preferences.getInt(recordingID, 0)
        val next = WearProtocol.nextRemoteRevision(current, minimumRevision)
        check(preferences.edit().putInt(recordingID, next).commit()) { "remoteRevisionPersistence" }
        return next
    }
}

class PhoneWearDataListenerService : WearableListenerService() {
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        dataEvents.filter { it.type == DataEvent.TYPE_CHANGED }.forEach { event ->
            val path = event.dataItem.uri.path.orEmpty()
            if (!path.startsWith(WearProtocol.WATCH_RECORDING_PREFIX)) return@forEach
            val recordingID = WearProtocol.recordingIDFromWatchPath(path) ?: return@forEach
            val map = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull() ?: return@forEach
            if (map.getInt(WearProtocol.KEY_PROTOCOL_VERSION) != WearProtocol.VERSION) {
                PhoneWearBridge.postStatus(this, recordingID, WearRemoteRecordingPhase.TRANSPORT_FAILED, 0, 0, "Unsupported protocol")
                return@forEach
            }
            val stored = when {
                path.endsWith(WearProtocol.MANIFEST_SUFFIX) -> WearRecordingInbox.storeManifest(this, recordingID, map)
                path.contains(WearProtocol.CHUNKS_SEGMENT) -> storeChunkAsset(recordingID, path, map)
                else -> false
            }
            if (!stored) {
                PhoneWearBridge.postStatus(
                    this,
                    recordingID,
                    WearRemoteRecordingPhase.TRANSPORT_FAILED,
                    map.getInt(WearProtocol.KEY_REVISION).coerceAtLeast(0),
                    WearRecordingInbox.frontier(this, recordingID),
                    "Transfer validation failed",
                )
                return@forEach
            }
            val result = WearRecordingInbox.reconcile(this, recordingID)
            PhoneWearBridge.postStatus(
                this,
                recordingID,
                phase = if (result.ingested) WearRemoteRecordingPhase.INGESTED else WearRemoteRecordingPhase.RECEIVING,
                minimumRevision = result.revision,
                frontier = result.frontier,
            )
            if (result.ingested) {
                if (AudioCaptureClient(this).frozenPreset(recordingID)?.watchOutputMode == CaptureWatchOutputMode.RECORDING_ONLY) {
                    WearRecordingOnlyDeliveryWorker.enqueue(this, recordingID, result.frontier)
                } else {
                    WearTranscriptDeliveryWorker.enqueue(this, recordingID, result.frontier)
                }
            }
        }
    }

    private fun storeChunkAsset(recordingID: String, path: String, map: DataMap): Boolean {
        val pathIndex = WearProtocol.chunkIndexFromWatchPath(path) ?: return false
        if (pathIndex != map.getInt(WearProtocol.KEY_CHUNK_INDEX)) return false
        val asset = map.getAsset(WearProtocol.KEY_ASSET) ?: return false
        val response = runCatching { Tasks.await(Wearable.getDataClient(this).getFdForAsset(asset)) }.getOrNull()
            ?: return false
        return response.inputStream.use { input ->
            WearRecordingInbox.storeChunk(this, recordingID, map, input)
        }
    }
}

internal data class InboxReconciliation(val revision: Int, val frontier: Int, val ingested: Boolean)

internal object WearRecordingInbox {
    private const val MAX_CHUNK_BYTES = 2L * 1024 * 1024
    private const val MAX_CHUNKS = 100_000
    private const val MAX_PRESET_BYTES = 65_536

    fun storeManifest(context: Context, recordingID: String, map: DataMap): Boolean = runCatching {
        require(map.getString(WearProtocol.KEY_RECORDING_ID) == recordingID)
        val chunkCount = map.getInt(WearProtocol.KEY_CHUNK_COUNT).also { require(it in 1..MAX_CHUNKS) }
        val createdAt = map.getLong(WearProtocol.KEY_CREATED_AT).also { require(it >= 0) }
        val duration = map.getLong(WearProtocol.KEY_DURATION).also { require(it >= 0) }
        val revision = map.getInt(WearProtocol.KEY_REVISION).also { require(it >= 0) }
        val presetID = requireNotNull(map.getString(WearProtocol.KEY_PRESET_ID)).also { require(it.length in 1..128) }
        val presetName = requireNotNull(map.getString(WearProtocol.KEY_PRESET_NAME)).also { require(it.length <= 128) }
        val snapshot = requireNotNull(map.getByteArray(WearProtocol.KEY_PRESET_SNAPSHOT)).also {
            require(it.size in 1..MAX_PRESET_BYTES)
        }
        val directory = inboxDirectory(context, recordingID, create = true) ?: error("Invalid inbox")
        val present = readManifest(directory)
        if (present != null && present.revision > revision) return@runCatching true
        val bytes = buildString {
            append("recordingID=").append(recordingID).append('\n')
            append("createdAtEpochMillis=").append(createdAt).append('\n')
            append("durationMillis=").append(duration).append('\n')
            append("chunkCount=").append(chunkCount).append('\n')
            append("revision=").append(revision).append('\n')
            append("presetID=").append(presetID).append('\n')
            append("presetName=").append(Base64.encodeToString(presetName.toByteArray(), Base64.NO_WRAP)).append('\n')
            append("presetSnapshot=").append(Base64.encodeToString(snapshot, Base64.NO_WRAP)).append('\n')
        }.toByteArray(StandardCharsets.UTF_8)
        writeAtomic(File(directory, "manifest.properties"), bytes)
        syncDirectory(directory)
        true
    }.getOrDefault(false)

    fun storeChunk(context: Context, recordingID: String, map: DataMap, input: java.io.InputStream): Boolean = runCatching {
        require(map.getString(WearProtocol.KEY_RECORDING_ID) == recordingID)
        val index = map.getInt(WearProtocol.KEY_CHUNK_INDEX).also { require(it in 0 until MAX_CHUNKS) }
        val count = map.getInt(WearProtocol.KEY_CHUNK_COUNT).also { require(it in 1..MAX_CHUNKS && index < it) }
        val expectedLength = map.getLong(WearProtocol.KEY_CHUNK_LENGTH).also { require(it in 1..MAX_CHUNK_BYTES) }
        val expectedSHA = requireNotNull(map.getString(WearProtocol.KEY_SHA256)).also {
            require(WearProtocol.checksumPattern.matches(it))
        }
        val directory = inboxDirectory(context, recordingID, create = true) ?: error("Invalid inbox")
        val target = File(directory, "chunk-${index.toString().padStart(6, '0')}.pcm")
        if (target.isFile && target.length() == expectedLength && sha256(target) == expectedSHA) return@runCatching true
        val temporary = File(directory, "${target.name}.part")
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        FileOutputStream(temporary).use { output ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                total += read
                require(total <= MAX_CHUNK_BYTES)
                output.write(buffer, 0, read)
                digest.update(buffer, 0, read)
            }
            output.flush()
            output.fd.sync()
        }
        require(total == expectedLength)
        val actualSHA = digest.digest().joinToString("") { byte -> "%02x".format(byte) }
        require(actualSHA == expectedSHA)
        if (target.exists()) require(target.delete())
        require(temporary.renameTo(target))
        syncDirectory(directory)
        true
    }.getOrElse {
        inboxDirectory(context, recordingID, create = false)?.listFiles()?.filter { file -> file.name.endsWith(".part") }?.forEach(File::delete)
        false
    }

    fun reconcile(context: Context, recordingID: String): InboxReconciliation {
        val directory = inboxDirectory(context, recordingID, create = false)
            ?: return InboxReconciliation(0, 0, false)
        val manifest = readManifest(directory) ?: return InboxReconciliation(0, frontier(context, recordingID), false)
        val contiguous = frontier(context, recordingID)
        if (contiguous < manifest.chunkCount) return InboxReconciliation(manifest.revision, contiguous, false)
        if (File(directory, "ingested").isFile) return InboxReconciliation(manifest.revision, contiguous, true)
        val ingested = AudioCaptureClient(context).importWearRecording(
            sessionID = recordingID,
            createdAtEpochMillis = manifest.createdAtEpochMillis,
            durationMillis = manifest.durationMillis,
            chunkCount = manifest.chunkCount,
            sourceDirectory = directory,
            presetSnapshot = manifest.presetSnapshot,
        )
        if (ingested) writeAtomic(File(directory, "ingested"), "1\n".toByteArray())
        return InboxReconciliation(manifest.revision, contiguous, ingested)
    }

    fun frontier(context: Context, recordingID: String): Int {
        val directory = inboxDirectory(context, recordingID, create = false) ?: return 0
        var index = 0
        while (File(directory, "chunk-${index.toString().padStart(6, '0')}.pcm").isFile) index += 1
        return index
    }

    private data class Manifest(
        val createdAtEpochMillis: Long,
        val durationMillis: Long,
        val chunkCount: Int,
        val revision: Int,
        val presetSnapshot: ByteArray,
    )

    private fun readManifest(directory: File): Manifest? = runCatching {
        val values = File(directory, "manifest.properties").readLines().associate { line ->
            val split = line.indexOf('=')
            require(split > 0)
            line.substring(0, split) to line.substring(split + 1)
        }
        Manifest(
            createdAtEpochMillis = requireNotNull(values["createdAtEpochMillis"]).toLong(),
            durationMillis = requireNotNull(values["durationMillis"]).toLong(),
            chunkCount = requireNotNull(values["chunkCount"]).toInt().also { require(it in 1..MAX_CHUNKS) },
            revision = requireNotNull(values["revision"]).toInt().also { require(it >= 0) },
            presetSnapshot = Base64.decode(requireNotNull(values["presetSnapshot"]), Base64.NO_WRAP).also {
                require(it.size in 1..MAX_PRESET_BYTES)
            },
        )
    }.getOrNull()

    private fun inboxDirectory(context: Context, recordingID: String, create: Boolean): File? {
        if (!WearProtocol.recordingIDPattern.matches(recordingID)) return null
        val root = File(context.noBackupFilesDir, "wear-inbox").apply { if (create) mkdirs() }.canonicalFile
        val directory = File(root, recordingID).canonicalFile
        if (directory.parentFile != root) return null
        if (create) directory.mkdirs()
        return directory.takeIf { it.isDirectory && !Files.isSymbolicLink(it.toPath()) }
    }

    private fun writeAtomic(file: File, bytes: ByteArray) {
        val atomic = AtomicFile(file)
        val output = atomic.startWrite()
        try {
            output.write(bytes)
            output.flush()
            output.fd.sync()
            atomic.finishWrite(output)
        } catch (error: Exception) {
            atomic.failWrite(output)
            throw error
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }

    private fun syncDirectory(directory: File) {
        val descriptor = Os.open(directory.absolutePath, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        try { Os.fsync(descriptor) } finally { Os.close(descriptor) }
    }
}
