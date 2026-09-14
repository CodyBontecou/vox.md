package md.vox.android

import android.content.Context
import com.google.android.gms.wearable.DataMap
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.ByteArrayInputStream
import java.io.File
import java.security.MessageDigest
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.capturedomain.WearProtocol
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingPresetSnapshotCodec
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class PhoneWearInboxInstrumentationTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val recordingID = "55555555-5555-4555-8555-555555555555"

    @Before
    fun clearState() = deleteFixtureState()

    @After
    fun cleanState() = deleteFixtureState()

    @Test
    fun phoneAcknowledgesIngestedOnlyAfterEveryVerifiedChunkIsDurable() {
        val preset = preset()
        assertTrue(WearRecordingInbox.storeManifest(context, recordingID, manifest(preset, chunkCount = 1)))

        val beforeChunk = WearRecordingInbox.reconcile(context, recordingID)
        assertFalse(beforeChunk.ingested)
        assertEquals(0, beforeChunk.frontier)
        assertFalse(AudioCaptureClient(context).recordings().any { it.sessionID == recordingID })

        val audio = ByteArray(640) { index -> (index % 97).toByte() }
        assertTrue(WearRecordingInbox.storeChunk(context, recordingID, chunk(audio), ByteArrayInputStream(audio)))
        val ingested = WearRecordingInbox.reconcile(context, recordingID)

        assertTrue(ingested.ingested)
        assertEquals(1, ingested.frontier)
        val recording = AudioCaptureClient(context).recordings().single { it.sessionID == recordingID }
        assertEquals(RecordingPhase.COMPLETED, recording.phase)
        assertEquals(1, recording.chunkCount)
        assertTrue(AudioCaptureClient(context).isImportedFromWear(recordingID))
        val frozen = AudioCaptureClient(context).frozenPreset(recordingID)
        assertEquals(preset.id, frozen?.id)
        assertEquals(CaptureWatchOutputMode.RECORDING_ONLY, frozen?.watchOutputMode)
        assertEquals(preset.exportSettings.destinationTreeUri, frozen?.exportSettings?.destinationTreeUri)

        val retried = WearRecordingInbox.reconcile(context, recordingID)
        assertTrue(retried.ingested)
        assertEquals(1, AudioCaptureClient(context).recordings().count { it.sessionID == recordingID })
    }

    @Test
    fun corruptChunkNeverAdvancesFrontierOrCreatesPhoneRecording() {
        assertTrue(WearRecordingInbox.storeManifest(context, recordingID, manifest(preset(), chunkCount = 1)))
        val audio = ByteArray(640) { 7 }
        val invalid = chunk(audio).apply { putString(WearProtocol.KEY_SHA256, "0".repeat(64)) }

        assertFalse(WearRecordingInbox.storeChunk(context, recordingID, invalid, ByteArrayInputStream(audio)))
        assertEquals(0, WearRecordingInbox.frontier(context, recordingID))
        assertFalse(WearRecordingInbox.reconcile(context, recordingID).ingested)
        assertFalse(AudioCaptureClient(context).recordings().any { it.sessionID == recordingID })
        assertNull(File(inboxDirectory(), "chunk-000000.pcm.part").takeIf(File::exists))
    }

    private fun preset() = CapturePreset(
        id = "66666666-6666-4666-8666-666666666666",
        name = "Watch Raw",
        symbol = "waveform",
        revision = 4,
        logicalFolder = "Watch/Raw",
        noteNameTemplate = "watch-{uuid}.md",
        metadataFields = emptyList(),
        watchOutputMode = CaptureWatchOutputMode.RECORDING_ONLY,
        exportSettings = CapturePresetExportSettings(
            usesCustomExportSettings = true,
            destinationTreeUri = "content://md.vox.android.test.documents/root",
            destinationName = "Watch destination",
            newFileNameTemplate = "watch-{date}-{id8}",
        ),
    )

    private fun manifest(preset: CapturePreset, chunkCount: Int) = DataMap().apply {
        putInt(WearProtocol.KEY_PROTOCOL_VERSION, WearProtocol.VERSION)
        putString(WearProtocol.KEY_RECORDING_ID, recordingID)
        putLong(WearProtocol.KEY_CREATED_AT, 1_704_205_645_000)
        putLong(WearProtocol.KEY_DURATION, 20)
        putInt(WearProtocol.KEY_CHUNK_COUNT, chunkCount)
        putInt(WearProtocol.KEY_REVISION, 3)
        putString(WearProtocol.KEY_PRESET_ID, preset.id)
        putString(WearProtocol.KEY_PRESET_NAME, preset.name)
        putByteArray(WearProtocol.KEY_PRESET_SNAPSHOT, RecordingPresetSnapshotCodec.encode(preset).toByteArray())
    }

    private fun chunk(bytes: ByteArray) = DataMap().apply {
        putString(WearProtocol.KEY_RECORDING_ID, recordingID)
        putInt(WearProtocol.KEY_CHUNK_INDEX, 0)
        putInt(WearProtocol.KEY_CHUNK_COUNT, 1)
        putLong(WearProtocol.KEY_CHUNK_LENGTH, bytes.size.toLong())
        putString(WearProtocol.KEY_SHA256, sha256(bytes))
        putInt(WearProtocol.KEY_REVISION, 3)
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { byte -> "%02x".format(byte) }

    private fun inboxDirectory() = File(context.noBackupFilesDir, "wear-inbox/$recordingID")

    private fun deleteFixtureState() {
        listOf(
            inboxDirectory(),
            File(context.noBackupFilesDir, "recordings/$recordingID"),
            File(context.noBackupFilesDir, "recordings/$recordingID.wear.part"),
        ).forEach { file ->
            if (file.canonicalFile.toPath().startsWith(context.noBackupFilesDir.canonicalFile.toPath())) {
                file.deleteRecursively()
            }
        }
    }
}
