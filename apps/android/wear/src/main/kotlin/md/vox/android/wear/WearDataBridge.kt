package md.vox.android.wear

import android.content.Context
import android.os.ParcelFileDescriptor
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.Asset
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import md.vox.android.capturedomain.WearProtocol
import org.json.JSONObject

internal object WearDataBridge {
    suspend fun syncAll(context: Context): Int = withContext(Dispatchers.IO) {
        WearQueueStore.load(context).count { item -> syncOne(context, item) }
    }

    private fun syncOne(context: Context, present: WearQueueItem): Boolean = runCatching {
        if (present.phase in setOf(
                WearQueuePhase.PHONE_QUEUED,
                WearQueuePhase.PHONE_TRANSCRIBING,
                WearQueuePhase.PHONE_DELIVERING,
                WearQueuePhase.PHONE_INGESTED,
                WearQueuePhase.DELIVERED,
            )
        ) return@runCatching true
        val item = WearQueueStore.startSync(context, present.recordingID) ?: return@runCatching false
        val chunks = WearQueueStore.recordingChunks(context, item)
        require(item.chunkCount > 0 && chunks.size == item.chunkCount) { "Local audio is incomplete" }
        val client = Wearable.getDataClient(context)

        val manifest = PutDataMapRequest.create(WearProtocol.manifestPath(item.recordingID)).apply {
            dataMap.putInt(WearProtocol.KEY_PROTOCOL_VERSION, WearProtocol.VERSION)
            dataMap.putString(WearProtocol.KEY_RECORDING_ID, item.recordingID)
            dataMap.putLong(WearProtocol.KEY_CREATED_AT, item.createdAtEpochMillis)
            dataMap.putLong(WearProtocol.KEY_DURATION, item.durationMillis)
            dataMap.putInt(WearProtocol.KEY_CHUNK_COUNT, item.chunkCount)
            dataMap.putString(WearProtocol.KEY_PRESET_ID, item.presetID)
            dataMap.putString(WearProtocol.KEY_PRESET_NAME, item.presetName)
            dataMap.putByteArray(WearProtocol.KEY_PRESET_SNAPSHOT, item.presetSnapshot)
            dataMap.putInt(WearProtocol.KEY_REVISION, item.revision)
        }.asPutDataRequest().setUrgent()
        Tasks.await(client.putDataItem(manifest))

        chunks.drop(item.acknowledgedFrontier).forEachIndexed { offset, chunk ->
            val index = item.acknowledgedFrontier + offset
            val descriptor = ParcelFileDescriptor.open(chunk, ParcelFileDescriptor.MODE_READ_ONLY)
            try {
                val request = PutDataMapRequest.create(WearProtocol.chunkPath(item.recordingID, index)).apply {
                    dataMap.putInt(WearProtocol.KEY_PROTOCOL_VERSION, WearProtocol.VERSION)
                    dataMap.putString(WearProtocol.KEY_RECORDING_ID, item.recordingID)
                    dataMap.putInt(WearProtocol.KEY_CHUNK_INDEX, index)
                    dataMap.putInt(WearProtocol.KEY_CHUNK_COUNT, item.chunkCount)
                    dataMap.putLong(WearProtocol.KEY_CHUNK_LENGTH, chunk.length())
                    dataMap.putString(WearProtocol.KEY_SHA256, sha256(chunk))
                    dataMap.putInt(WearProtocol.KEY_REVISION, item.revision)
                    dataMap.putAsset(WearProtocol.KEY_ASSET, Asset.createFromFd(descriptor))
                }.asPutDataRequest().setUrgent()
                Tasks.await(client.putDataItem(request))
            } finally {
                descriptor.close()
            }
        }
        true
    }.onFailure { error ->
        WearQueueStore.fail(context, present.recordingID, error.message ?: "Wear transfer failed")
    }.getOrDefault(false)

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { byte -> "%02x".format(byte) }
    }
}

class WearDataListenerService : WearableListenerService() {
    override fun onCreate() {
        super.onCreate()
        WearPresetStore.load(this)
        WearQueueStore.load(this)
    }

    override fun onDataChanged(dataEvents: DataEventBuffer) {
        dataEvents.filter { it.type == DataEvent.TYPE_CHANGED }.forEach { event ->
            val path = event.dataItem.uri.path.orEmpty()
            val map = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull() ?: return@forEach
            when {
                path == WearProtocol.PHONE_PRESETS_PATH -> applyPresets(map)
                path.startsWith(WearProtocol.PHONE_STATUS_PREFIX) && path.endsWith(WearProtocol.STATUS_SUFFIX) -> {
                    val id = WearProtocol.recordingIDFromPhoneStatusPath(path) ?: return@forEach
                    if (map.getInt(WearProtocol.KEY_PROTOCOL_VERSION) != WearProtocol.VERSION) return@forEach
                    WearQueueStore.applyPhoneStatus(
                        this,
                        recordingID = id,
                        phase = map.getString(WearProtocol.KEY_PHASE).orEmpty(),
                        revision = map.getInt(WearProtocol.KEY_REVISION),
                        frontier = map.getInt(WearProtocol.KEY_FRONTIER),
                        message = map.getString(WearProtocol.KEY_MESSAGE),
                    )
                }
            }
        }
    }

    private fun applyPresets(map: com.google.android.gms.wearable.DataMap) {
        if (map.getInt(WearProtocol.KEY_PROTOCOL_VERSION) != WearProtocol.VERSION) return
        val presets = map.getStringArrayList(WearProtocol.KEY_PRESETS).orEmpty().mapNotNull { encoded ->
            runCatching {
                val json = JSONObject(encoded)
                WearPreset(
                    id = json.getString("id").also { require(it.length in 1..128) },
                    name = json.getString("name").take(128),
                    symbol = json.optString("symbol", "description").take(64),
                    snapshot = encoded.toByteArray().also { require(it.size <= 65_536) },
                )
            }.getOrNull()
        }
        if (presets.isNotEmpty()) {
            WearPresetStore.replace(
                this,
                presets,
                map.getString(WearProtocol.KEY_ACTIVE_PRESET_ID) ?: presets.first().id,
            )
        }
    }
}
