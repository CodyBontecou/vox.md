package md.vox.android.wear

import android.content.Context
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import kotlinx.coroutines.runBlocking
import md.vox.android.capturedomain.WearProtocol
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WearDataBridgeInstrumentationTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val recordingID = "77777777-7777-4777-8777-777777777777"
    private val root get() = File(context.noBackupFilesDir, "recordings")

    @Before
    fun clearState() {
        deleteRecording()
        clearDataItems()
        WearQueueStore.load(context)
    }

    @After
    fun cleanState() {
        deleteRecording()
        clearDataItems()
        WearQueueStore.load(context)
    }

    @Test
    fun retryResumesAtAcknowledgedFrontierAndReusesIdempotentDataPaths() = runBlocking {
        val chunk0 = ByteArray(320) { 1 }
        val chunk1 = ByteArray(480) { index -> (index % 113).toByte() }
        val directory = File(root, recordingID).apply { mkdirs() }
        File(directory, "chunk-000000.pcm").writeBytes(chunk0)
        File(directory, "chunk-000001.pcm").writeBytes(chunk1)
        val snapshot = """{"id":"88888888-8888-4888-8888-888888888888","name":"Daily","symbol":"description","revision":1,"logicalFolder":"Daily","noteNameTemplate":"daily-{uuid}.md","metadataFields":[]}""".toByteArray()
        val preset = WearPreset("88888888-8888-4888-8888-888888888888", "Daily", "description", snapshot)
        requireNotNull(WearQueueStore.begin(context, recordingID, 1_700_000_000_000, preset))
        val local = requireNotNull(WearQueueStore.finish(context, recordingID, 20, 2))
        val initialSync = requireNotNull(WearQueueStore.startSync(context, local.recordingID))
        val receiving = requireNotNull(
            WearQueueStore.applyPhoneStatus(
                context,
                recordingID,
                WearProtocol.PHASE_RECEIVING,
                revision = initialSync.revision + 1,
                frontier = 1,
                message = null,
            ),
        )
        assertEquals(1, receiving.acknowledgedFrontier)
        requireNotNull(WearQueueStore.prepareRetry(context, recordingID))

        assertEquals(1, WearDataBridge.syncAll(context))
        val first = dataMapsForRecording()
        assertEquals(
            setOf(WearProtocol.manifestPath(recordingID), WearProtocol.chunkPath(recordingID, 1)),
            first.keys,
        )
        assertFalse(first.containsKey(WearProtocol.chunkPath(recordingID, 0)))
        val firstRevision = requireNotNull(first[WearProtocol.manifestPath(recordingID)]).getInt(WearProtocol.KEY_REVISION)
        assertEquals(2, first[WearProtocol.manifestPath(recordingID)]?.getInt(WearProtocol.KEY_CHUNK_COUNT))
        val asset = requireNotNull(first[WearProtocol.chunkPath(recordingID, 1)]?.getAsset(WearProtocol.KEY_ASSET))
        val response = Tasks.await(Wearable.getDataClient(context).getFdForAsset(asset))
        assertArrayEquals(chunk1, response.inputStream.use { it.readBytes() })

        requireNotNull(WearQueueStore.prepareRetry(context, recordingID))
        assertEquals(1, WearDataBridge.syncAll(context))
        val retried = dataMapsForRecording()
        assertEquals(first.keys, retried.keys)
        assertTrue(requireNotNull(retried[WearProtocol.manifestPath(recordingID)]).getInt(WearProtocol.KEY_REVISION) > firstRevision)
        assertEquals(1, requireNotNull(WearQueueStore.load(context).single()).acknowledgedFrontier)
    }

    private fun dataMapsForRecording(): Map<String, DataMap> {
        val buffer = Tasks.await(Wearable.getDataClient(context).dataItems)
        return try {
            buildMap {
                for (item in buffer) {
                    val path = item.uri.path.orEmpty()
                    if (path.contains(recordingID)) put(path, DataMapItem.fromDataItem(item).dataMap)
                }
            }
        } finally {
            buffer.release()
        }
    }

    private fun clearDataItems() {
        val client = Wearable.getDataClient(context)
        val buffer = Tasks.await(client.dataItems)
        val uris = try { buffer.map { it.uri } } finally { buffer.release() }
        uris.filter { it.path.orEmpty().contains(recordingID) }.forEach { uri -> Tasks.await(client.deleteDataItems(uri)) }
    }

    private fun deleteRecording() {
        val directory = File(root, recordingID).canonicalFile
        if (directory.parentFile == root.canonicalFile) directory.deleteRecursively()
    }
}
