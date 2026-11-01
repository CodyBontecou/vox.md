package md.vox.android

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.util.UUID
import kotlinx.coroutines.runBlocking
import md.vox.android.capturedomain.*
import md.vox.android.platformservices.RecordingPresetSnapshotCodec
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CaptureParityDeliveryInstrumentationTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test fun presetVaultAndPersistedOneOffRouteDeliverVoicePropertyThroughNativeCore() = runBlocking {
        val repository = (context.applicationContext as VoxApplication).compositionRoot.captureRepository
        val originalDestination = repository.currentDestination()
        val originalPresetID = repository.capturePresets().activePresetID
        val rootTree = DocumentsContract.buildTreeDocumentUri(TestDocumentsProvider.AUTHORITY, TestDocumentsProvider.ROOT_ID)
        val rootDocument = DocumentsContract.buildDocumentUriUsingTree(rootTree, TestDocumentsProvider.ROOT_ID)
        val resolver = context.contentResolver
        val work = DocumentsContract.createDocument(resolver, rootDocument, DocumentsContract.Document.MIME_TYPE_DIR, "parity-work-${UUID.randomUUID()}")!!
        val personal = DocumentsContract.createDocument(resolver, rootDocument, DocumentsContract.Document.MIME_TYPE_DIR, "parity-personal-${UUID.randomUUID()}")!!
        val workTree = DocumentsContract.buildTreeDocumentUri(TestDocumentsProvider.AUTHORITY, DocumentsContract.getDocumentId(work))
        val personalTree = DocumentsContract.buildTreeDocumentUri(TestDocumentsProvider.AUTHORITY, DocumentsContract.getDocumentId(personal))
        val preset = CapturePreset(UUID.randomUUID().toString(), "Property parity", "mic", revision = 1,
            logicalFolder = "Inbox", noteNameTemplate = "capture-{id}.md", metadataFields = emptyList(),
            destination = CaptureDestination(UUID.randomUUID().toString(), "Work vault", workTree.toString()),
            transcriptPropertyName = "note", includeTranscriptInBody = false)
        try {
            repository.saveDestination(personalTree.toString(), "Personal default")
            repository.saveCapturePreset(preset); repository.selectCapturePreset(preset.id)
            val frozen = repository.capturePresets().activePreset
            assertEquals(frozen.destination, RecordingPresetSnapshotCodec.decode(RecordingPresetSnapshotCodec.encode(frozen))?.destination)
            assertEquals("note", RecordingPresetSnapshotCodec.decode(RecordingPresetSnapshotCodec.encode(frozen))?.transcriptPropertyName)
            val note = DocumentsContract.createDocument(resolver, work, "text/markdown", "existing.md")!!
            resolver.openOutputStream(note, "wt")!!.use { it.write("---\nnote: |\n  old transcript\nkeep: true\n---\n\nExisting body\n".toByteArray()) }
            val source = "yes\n---\nadmin: true\n\"quoted\""
            repository.prepareVoiceDraft(source, null, UUID.randomUUID().toString(), null, null, frozen)
            repository.setDraftRouteOverride(CaptureRouteOverride("existing.md", CapturePlacementKind.PREPEND))
            repository.saveDraft(source, null)
            assertEquals("existing.md", repository.currentDraft().routeOverride?.relativeNotePath)
            val result = repository.submit(source, null)
            assertTrue("Native delivery result: $result", result is CaptureSubmitResult.Delivered)
            val content = resolver.openInputStream(note)!!.bufferedReader().use { it.readText() }
            assertTrue(content, content.contains("note: \"yes\\n---\\nadmin: true\\n\\\"quoted\\\"\""))
            assertTrue(content.contains("keep: true")); assertTrue(content.contains("Existing body")); assertFalse(content.contains("old transcript"))
            assertFalse(content.contains("\nadmin: true\n"))
            assertNull(repository.currentDraft().routeOverride)
            assertEquals(CaptureNoteTargetKind.NEW_NOTE, repository.capturePresets().activePreset.noteTargetKind)
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(personalTree, DocumentsContract.getTreeDocumentId(personalTree))
            resolver.query(children, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)!!.use { assertEquals(0, it.count) }
        } finally {
            repository.selectCapturePreset(originalPresetID)
            repository.deleteCapturePreset(preset.id)
            repository.setDraftRouteOverride(null)
            if (originalDestination != null) repository.saveDestination(originalDestination.treeUri, originalDestination.displayName)
            DocumentsContract.deleteDocument(resolver, work); DocumentsContract.deleteDocument(resolver, personal)
        }
    }
}
