package md.vox.android

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.capturedomain.CaptureWatchOutputMode
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WearRecordingOnlySafInstrumentationTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val recordingID = "11111111-1111-4111-8111-111111111111"
    private val treeUri: Uri
        get() = DocumentsContract.buildTreeDocumentUri(TestDocumentsProvider.AUTHORITY, TestDocumentsProvider.ROOT_ID)

    @Before
    fun clearState() {
        deleteProviderDocuments()
        recordingDirectory().deleteRecursively()
    }

    @After
    fun cleanState() {
        deleteProviderDocuments()
        recordingDirectory().deleteRecursively()
    }

    @Test
    fun recordingOnlyWritesVerifiedWavToFrozenFolderWithoutTranscriptArtifacts() {
        val payload = ByteArray(128) { index -> (index and 0xff).toByte() }.also {
            "RIFF".toByteArray().copyInto(it)
            "WAVE".toByteArray().copyInto(it, 8)
        }
        val exporter = AndroidWearRecordingOnlyExporter(context)

        val firstResult = exporter.export(recordingID, 1_704_205_645_000, preset()) { output ->
            output.write(payload)
            true
        }
        assertTrue(firstResult.toString(), firstResult is WearRecordingOnlyExportResult.Exported)
        val first = firstResult as WearRecordingOnlyExportResult.Exported
        val secondResult = exporter.export(recordingID, 1_704_205_645_000, preset()) { output ->
            output.write(payload)
            true
        }
        assertTrue(secondResult.toString(), secondResult is WearRecordingOnlyExportResult.Exported)
        val second = secondResult as WearRecordingOnlyExportResult.Exported

        assertEquals("unattended-2024-01-02-11111111.wav", first.displayName)
        assertEquals("unattended-2024-01-02-11111111-2.wav", second.displayName)
        assertEquals("Watch/Raw/${first.displayName}", DocumentsContract.getDocumentId(Uri.parse(first.documentUri)))
        assertArrayEquals(payload, readDocument(Uri.parse(first.documentUri)))
        assertEquals(payload.size.toLong(), first.byteCount)
        assertTrue(first.sha256.matches(Regex("^[0-9a-f]{64}$")))
        assertTrue(allDocumentIDs().count { it.endsWith(".wav") } == 2)
        assertFalse(allDocumentIDs().any { it.endsWith(".md") || it.endsWith(".txt") })

        val directory = recordingDirectory().apply { mkdirs() }
        val store = WearRecordingOnlyReceiptStore(context)
        assertTrue(store.write(recordingID, first))
        assertEquals(WearRecordingOnlyReceipt(first.byteCount, first.sha256), store.read(recordingID))
        val receiptText = File(directory, "wear-recording-only-delivery.receipt").readText()
        assertFalse(receiptText.contains(first.displayName))
        assertFalse(receiptText.contains(first.documentUri))
    }

    @Test
    fun failedWriteRemovesPartialAudioAndDoesNotAuthorizeDelivery() {
        val exporter = AndroidWearRecordingOnlyExporter(context)
        val result = exporter.export(recordingID, 0, preset()) { output ->
            output.write(ByteArray(80) { 7 })
            false
        }

        assertTrue(result is WearRecordingOnlyExportResult.Failed)
        assertFalse(allDocumentIDs().any { it.endsWith(".wav") })
        recordingDirectory().mkdirs()
        assertNull(WearRecordingOnlyReceiptStore(context).read(recordingID))
    }

    @Test
    fun recordingOnlyRequiresItsModeAndAContentDestination() {
        val exporter = AndroidWearRecordingOnlyExporter(context)
        val transcriptMode = preset().copy(watchOutputMode = CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE)
        val noDestination = preset().copy(exportSettings = preset().exportSettings.copy(destinationTreeUri = null))

        assertEquals(
            WearRecordingOnlyExportResult.Failed("outputMode"),
            exporter.export(recordingID, 0, transcriptMode) { true },
        )
        assertEquals(
            WearRecordingOnlyExportResult.Failed("destinationRequired"),
            exporter.export(recordingID, 0, noDestination) { true },
        )
        assertTrue(allDocumentIDs().isEmpty())
    }

    private fun preset() = CapturePreset(
        id = "watch-recording-only",
        name = "Unattended Audio",
        symbol = "waveform",
        revision = 9,
        logicalFolder = "Watch/Raw",
        noteNameTemplate = "unused-{uuid}.md",
        metadataFields = emptyList(),
        watchOutputMode = CaptureWatchOutputMode.RECORDING_ONLY,
        exportSettings = CapturePresetExportSettings(
            usesCustomExportSettings = true,
            exportEnabled = true,
            destinationTreeUri = treeUri.toString(),
            destinationName = "Test Documents",
            newFileNameTemplate = "unattended-{date}-{id8}",
        ),
    )

    private fun recordingDirectory() = File(context.noBackupFilesDir, "recordings/$recordingID")

    private fun readDocument(uri: Uri): ByteArray = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }

    private fun allDocumentIDs(parentID: String = TestDocumentsProvider.ROOT_ID): List<String> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, parentID)
        val rows = context.contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.getString(0) to cursor.getString(1))
            }
        }.orEmpty()
        return rows.flatMap { (id, mimeType) ->
            listOf(id) + if (mimeType == DocumentsContract.Document.MIME_TYPE_DIR) allDocumentIDs(id) else emptyList()
        }
    }

    private fun deleteProviderDocuments() {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, TestDocumentsProvider.ROOT_ID)
        val ids = context.contentResolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
            null,
            null,
            null,
        )?.use { cursor -> buildList { while (cursor.moveToNext()) add(cursor.getString(0)) } }.orEmpty()
        ids.forEach { id ->
            DocumentsContract.deleteDocument(
                context.contentResolver,
                DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
            )
        }
    }
}
