package md.vox.android.wear

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import md.vox.android.capturedomain.WearProtocol
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WearQueueStoreInstrumentationTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val recordingsRoot get() = File(context.noBackupFilesDir, "recordings")
    private val terminalReceiptsRoot get() = File(context.noBackupFilesDir, "wear/terminal-receipts")

    @Before
    fun clearFixtureState() = cleanFixtureState()

    @After
    fun restoreFixtureState() = cleanFixtureState()

    @Test
    fun frozenPresetAndQueueStateReloadFromDurableFiles() {
        val recordingID = "11111111-1111-4111-8111-111111111111"
        val snapshot = presetSnapshot("Original route")
        createChunks(recordingID, 2)
        val preset = WearPreset(recordingID, "Original", "description", snapshot)

        assertNotNull(WearQueueStore.begin(context, recordingID, 1_700_000_000_000, preset))
        assertNotNull(WearQueueStore.finish(context, recordingID, 8_500, 2))
        assertNotNull(WearQueueStore.fail(context, recordingID, "Phone unavailable"))
        assertNotNull(WearQueueStore.prepareRetry(context, recordingID))

        val reloaded = WearQueueStore.load(context).single()
        assertEquals(recordingID, reloaded.recordingID)
        assertEquals(8_500, reloaded.durationMillis)
        assertEquals(2, reloaded.chunkCount)
        assertEquals(WearQueuePhase.LOCAL, reloaded.phase)
        assertNull(reloaded.message)
        assertArrayEquals(snapshot, reloaded.presetSnapshot)
        assertEquals(listOf("chunk-000000.pcm", "chunk-000001.pcm"), WearQueueStore.recordingChunks(context, reloaded).map(File::getName))
    }

    @Test
    fun phoneIngestedFrontierRetainsAudioUntilACompleteNewerTerminalAuthorization() {
        val recordingID = "22222222-2222-4222-8222-222222222222"
        val item = queued(recordingID, chunkCount = 2)
        val syncing = requireNotNull(WearQueueStore.startSync(context, item.recordingID))

        val receiving = requireNotNull(
            WearQueueStore.applyPhoneStatus(
                context,
                recordingID,
                WearProtocol.PHASE_RECEIVING,
                revision = syncing.revision + 1,
                frontier = 1,
                message = null,
            ),
        )
        assertEquals(WearQueuePhase.PHONE_RECEIVING, receiving.phase)
        assertEquals(1, receiving.acknowledgedFrontier)

        val ingested = requireNotNull(
            WearQueueStore.applyPhoneStatus(
                context,
                recordingID,
                WearProtocol.PHASE_INGESTED,
                revision = receiving.revision + 1,
                frontier = 2,
                message = null,
            ),
        )
        assertEquals(WearQueuePhase.PHONE_INGESTED, ingested.phase)
        assertEquals(2, ingested.acknowledgedFrontier)
        assertTrue(File(recordingsRoot, recordingID).isDirectory)
        assertNull(WearQueueStore.terminalReceipt(context, recordingID))

        val incomplete = requireNotNull(
            WearQueueStore.applyPhoneStatus(
                context,
                recordingID,
                WearProtocol.PHASE_DELIVERED,
                revision = ingested.revision + 1,
                frontier = 1,
                message = null,
            ),
        )
        assertEquals(WearQueuePhase.TRANSPORT_FAILED, incomplete.phase)
        assertTrue(File(recordingsRoot, recordingID).isDirectory)

        assertNull(
            WearQueueStore.applyPhoneStatus(
                context,
                recordingID,
                WearProtocol.PHASE_DELIVERED,
                revision = incomplete.revision + 1,
                frontier = 2,
                message = null,
            ),
        )
        assertFalse(File(recordingsRoot, recordingID).exists())
        assertTrue(WearQueueStore.load(context).isEmpty())
        val receipt = requireNotNull(WearQueueStore.terminalReceipt(context, recordingID))
        assertEquals(WearProtocol.PHASE_DELIVERED, receipt.phase)
        assertEquals(2, receipt.frontier)
        assertTrue(receipt.revision > incomplete.revision)
    }

    @Test
    fun stalePhoneStateCannotRegressTheDurableQueue() {
        val recordingID = "33333333-3333-4333-8333-333333333333"
        val syncing = requireNotNull(WearQueueStore.startSync(context, queued(recordingID).recordingID))
        val transcribing = requireNotNull(
            WearQueueStore.applyPhoneStatus(
                context,
                recordingID,
                WearProtocol.PHASE_TRANSCRIBING,
                revision = syncing.revision + 3,
                frontier = 1,
                message = "Local model",
            ),
        )
        val stale = requireNotNull(
            WearQueueStore.applyPhoneStatus(
                context,
                recordingID,
                WearProtocol.PHASE_QUEUED,
                revision = syncing.revision + 1,
                frontier = 0,
                message = null,
            ),
        )
        assertEquals(WearQueuePhase.PHONE_TRANSCRIBING, stale.phase)
        assertEquals(transcribing.revision, stale.revision)
        assertEquals(1, stale.acknowledgedFrontier)
    }

    @Test
    fun explicitDiscardIsDurablyReceiptedBeforeAudioRemoval() {
        val recordingID = "44444444-4444-4444-8444-444444444444"
        queued(recordingID)

        assertTrue(WearQueueStore.discard(context, recordingID))
        assertFalse(File(recordingsRoot, recordingID).exists())
        assertTrue(WearQueueStore.load(context).isEmpty())
        val receipt = requireNotNull(WearQueueStore.terminalReceipt(context, recordingID))
        assertEquals(WearProtocol.PHASE_DISCARDED, receipt.phase)
        assertEquals(recordingID, receipt.recordingID)
    }

    private fun queued(recordingID: String, chunkCount: Int = 1): WearQueueItem {
        createChunks(recordingID, chunkCount)
        val preset = WearPreset(recordingID, "Daily", "description", presetSnapshot("Daily"))
        requireNotNull(WearQueueStore.begin(context, recordingID, 1_700_000_000_000, preset))
        return requireNotNull(WearQueueStore.finish(context, recordingID, 5_000, chunkCount))
    }

    private fun createChunks(recordingID: String, count: Int) {
        val directory = File(recordingsRoot, recordingID).apply { mkdirs() }
        repeat(count) { index ->
            File(directory, "chunk-${index.toString().padStart(6, '0')}.pcm").writeBytes(ByteArray(320) { index.toByte() })
        }
    }

    private fun presetSnapshot(name: String): ByteArray =
        """{"id":"33333333-3333-4333-8333-333333333333","name":"$name","symbol":"description","revision":1,"logicalFolder":"Daily","noteNameTemplate":"daily-{uuid}.md","metadataFields":[]}"""
            .toByteArray()

    private fun cleanFixtureState() {
        listOf(recordingsRoot, terminalReceiptsRoot).forEach { root ->
            if (root.canonicalFile.toPath().startsWith(context.noBackupFilesDir.canonicalFile.toPath())) {
                root.deleteRecursively()
            }
        }
        WearQueueStore.load(context)
    }
}
