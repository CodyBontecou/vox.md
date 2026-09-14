package md.vox.android

import android.content.Context
import android.net.Uri
import android.os.SystemClock
import android.provider.DocumentsContract
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlinx.coroutines.runBlocking
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.SpeechModelInstallPhase
import md.vox.android.platformservices.SpeechModelManager
import md.vox.android.platformservices.SpeechModelSelectionMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Runs only through connectedDebugAndroidTestLocalSpeech. The host installs exact-hash
 * model/audio fixtures, disables connectivity, and clears the application sandbox first.
 */
@RunWith(AndroidJUnit4::class)
class LocalSpeechInferenceInstrumentationTest {
    @Test
    fun installedModelTranscribesRealSpeechThroughTheProductionClientWhileOffline() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val qualification = File(context.filesDir, "local-speech-qualification")
        val modelArchive = File(qualification, "vosk-model-small-en-us-0.15.zip")
        val speechWav = File(qualification, "vosk-api-test.wav")
        assumeTrue(
            "exact-hash host fixtures are staged only by connectedDebugAndroidTestLocalSpeech",
            modelArchive.isFile && modelArchive.length() > 40_000_000 &&
                speechWav.isFile && speechWav.length() > 200_000,
        )

        val modelManager = SpeechModelManager.get(context)
        val audioClient = AudioCaptureClient(context)
        val transcriptionClient = RecordingTranscriptionClient.get(context)
        var sessionID: String? = null
        try {
            assertTrue(modelManager.state.value.models.none { it.phase == SpeechModelInstallPhase.READY })
            modelManager.installImportedZip(MODEL_ID, modelArchive.inputStream())
            val readyModel = awaitModel(modelManager)
            assertEquals(MODEL_ID, readyModel.descriptor.id)
            assertTrue(modelManager.selectAutomatic())
            assertEquals(SpeechModelSelectionMode.AUTOMATIC, modelManager.state.value.selectionMode)
            assertEquals(MODEL_ID, modelManager.selectedModelID())
            assertTrue(modelManager.select(MODEL_ID))
            assertEquals(SpeechModelSelectionMode.MANUAL, modelManager.state.value.selectionMode)
            assertEquals(MODEL_ID, modelManager.selectedModelID())
            assertTrue(
                File(requireNotNull(modelManager.selectedModelDirectory()), "vox-model.properties")
                    .readText()
                    .contains("archiveSha256=$MODEL_SHA256"),
            )

            val pcm = pcm16Mono16Khz(speechWav)
            val source = File(context.cacheDir, "local-speech-source").apply {
                deleteRecursively()
                assertTrue(mkdirs())
            }
            File(source, "chunk-000000.pcm").writeBytes(pcm)
            val id = SESSION_ID
            sessionID = id
            assertTrue(
                audioClient.importWearRecording(
                    sessionID = id,
                    createdAtEpochMillis = 1_700_000_000_000,
                    durationMillis = pcm.size * 1_000L / 32_000L,
                    chunkCount = 1,
                    sourceDirectory = source,
                    presetSnapshot = md.vox.android.platformservices.RecordingPresetSnapshotCodec
                        .encode(testPreset())
                        .toByteArray(),
                ),
            )
            source.deleteRecursively()

            transcriptionClient.process(id)
            val completed = awaitTranscription(transcriptionClient, id)
            assertEquals(RecordingTranscriptionPhase.COMPLETED, completed.phase)
            assertEquals(MODEL_ID, completed.modelID)
            val transcript = completed.transcript.orEmpty().lowercase()
            assertTrue("unexpected transcript: $transcript", "one zero zero zero one" in transcript)
            assertTrue("unexpected transcript: $transcript", "zero one eight zero three" in transcript)
        } finally {
            sessionID?.let { id ->
                transcriptionClient.clear(id)
                audioClient.deleteRecording(id)
            }
            modelManager.delete(MODEL_ID)
            context.getSharedPreferences("vox-transcription-quota-v1", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }

    @Test
    fun frozenWearPresetRoutesRealSpeechThroughPhoneLocalTranscriptionAndMarkdownDelivery() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val qualification = File(context.filesDir, "local-speech-qualification")
        val modelArchive = File(qualification, "vosk-model-small-en-us-0.15.zip")
        val speechWav = File(qualification, "vosk-api-test.wav")
        assumeTrue(
            "exact-hash host fixtures are staged only by connectedDebugAndroidTestLocalSpeech",
            modelArchive.isFile && modelArchive.length() > 40_000_000 &&
                speechWav.isFile && speechWav.length() > 200_000,
        )
        val treeUri = DocumentsContract.buildTreeDocumentUri(
            TestDocumentsProvider.AUTHORITY,
            TestDocumentsProvider.ROOT_ID,
        )
        val modelManager = SpeechModelManager.get(context)
        val audioClient = AudioCaptureClient(context)
        val transcriptionClient = RecordingTranscriptionClient.get(context)
        val repository = (context.applicationContext as VoxApplication).compositionRoot.captureRepository
        deleteDestinationDocuments(context, treeUri)
        try {
            modelManager.installImportedZip(MODEL_ID, modelArchive.inputStream())
            awaitModel(modelManager)
            assertTrue(modelManager.selectAutomatic())
            repository.saveDestination(treeUri.toString(), "Vox Test Documents")

            val pcm = pcm16Mono16Khz(speechWav)
            val source = File(context.cacheDir, "wear-transcript-source").apply {
                deleteRecursively()
                assertTrue(mkdirs())
            }
            File(source, "chunk-000000.pcm").writeBytes(pcm)
            assertTrue(
                audioClient.importWearRecording(
                    sessionID = WEAR_SESSION_ID,
                    createdAtEpochMillis = 1_700_000_000_000,
                    durationMillis = pcm.size * 1_000L / 32_000L,
                    chunkCount = 1,
                    sourceDirectory = source,
                    presetSnapshot = md.vox.android.platformservices.RecordingPresetSnapshotCodec
                        .encode(wearTranscriptPreset())
                        .toByteArray(),
                ),
            )
            source.deleteRecursively()

            val delivered = WearTranscriptDelivery(context, repository, audioClient, transcriptionClient)
                .deliver(WEAR_SESSION_ID, frontier = 1)
            assertTrue("unexpected route outcome: $delivered", delivered is WearTranscriptDeliveryResult.Delivered)
            delivered as WearTranscriptDeliveryResult.Delivered
            assertEquals(WEAR_SESSION_ID, delivered.requestID)
            assertTrue("one zero zero zero one" in delivered.transcript.lowercase())

            val noteUri = DocumentsContract.buildDocumentUriUsingTree(
                treeUri,
                "Watch/watch-$WEAR_SESSION_ID.md",
            )
            val markdown = context.contentResolver.openInputStream(noteUri)!!.bufferedReader().use { it.readText() }
            assertTrue("one zero zero zero one" in markdown.lowercase())
            assertTrue("zero one eight zero three" in markdown.lowercase())
            val history = repository.history().single { it.requestID == WEAR_SESSION_ID }
            assertEquals(CaptureState.COMPLETED, history.state)
            assertEquals(1, repository.activityStats().captureSources["wear"])
        } finally {
            transcriptionClient.clear(WEAR_SESSION_ID)
            audioClient.deleteRecording(WEAR_SESSION_ID)
            modelManager.delete(MODEL_ID)
            context.getSharedPreferences("vox-transcription-quota-v1", Context.MODE_PRIVATE).edit().clear().commit()
            deleteDestinationDocuments(context, treeUri)
        }
    }

    private fun awaitModel(manager: SpeechModelManager, timeoutMillis: Long = 90_000): md.vox.android.platformservices.SpeechModelInstallState {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            val state = manager.state.value.models.single { it.descriptor.id == MODEL_ID }
            if (state.phase == SpeechModelInstallPhase.READY) return state
            if (state.phase == SpeechModelInstallPhase.FAILED) error("model install failed: ${state.failureCode}")
            SystemClock.sleep(100)
        }
        error("timed out installing local model")
    }

    private fun awaitTranscription(
        client: RecordingTranscriptionClient,
        sessionID: String,
        timeoutMillis: Long = 120_000,
    ): md.vox.android.platformservices.RecordingTranscriptionState {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            client.states.value[sessionID]?.let { state ->
                if (state.phase == RecordingTranscriptionPhase.COMPLETED) return state
                if (state.phase == RecordingTranscriptionPhase.FAILED) {
                    error("local transcription failed: ${state.failureCode}")
                }
            }
            SystemClock.sleep(100)
        }
        error("timed out running local transcription")
    }

    private fun pcm16Mono16Khz(file: File): ByteArray {
        val bytes = file.readBytes()
        require(bytes.size > 44 && bytes.copyOfRange(0, 4).decodeToString() == "RIFF")
        require(bytes.copyOfRange(8, 12).decodeToString() == "WAVE")
        var offset = 12
        var formatVerified = false
        while (offset + 8 <= bytes.size) {
            val name = bytes.copyOfRange(offset, offset + 4).decodeToString()
            val size = littleEndianInt(bytes, offset + 4)
            require(size >= 0 && offset + 8L + size <= bytes.size)
            val payload = offset + 8
            when (name) {
                "fmt " -> {
                    require(size >= 16)
                    val format = ByteBuffer.wrap(bytes, payload, 16).slice().order(ByteOrder.LITTLE_ENDIAN)
                    require(format.short.toInt() == 1)
                    require(format.short.toInt() == 1)
                    require(format.int == 16_000)
                    format.position(14)
                    require(format.short.toInt() == 16)
                    formatVerified = true
                }
                "data" -> {
                    require(formatVerified && size > 0 && size % 2 == 0)
                    return bytes.copyOfRange(payload, payload + size)
                }
            }
            offset = payload + size + (size and 1)
        }
        error("WAV data chunk is missing")
    }

    private fun littleEndianInt(bytes: ByteArray, offset: Int): Int =
        ByteBuffer.wrap(bytes, offset, 4).order(ByteOrder.LITTLE_ENDIAN).int

    private fun testPreset() = CapturePreset(
        id = "92929292-9292-4929-8929-929292929292",
        name = "Offline inference",
        symbol = "waveform",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "offline-{id}",
        metadataFields = emptyList(),
        watchOutputMode = CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE,
    )

    private fun wearTranscriptPreset() = CapturePreset(
        id = "93939393-9393-4939-8939-939393939393",
        name = "Watch transcript",
        symbol = "waveform",
        revision = 4,
        logicalFolder = "Watch",
        noteNameTemplate = "watch-{id}.md",
        metadataFields = emptyList(),
        audioSaveMode = CaptureAudioSaveMode.OFF,
        watchOutputMode = CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE,
    )

    private fun deleteDestinationDocuments(context: Context, treeUri: Uri) {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            treeUri,
            DocumentsContract.getTreeDocumentId(treeUri),
        )
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

    private companion object {
        const val MODEL_ID = "vosk-small-en-us-0.15"
        const val MODEL_SHA256 = "30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498"
        const val SESSION_ID = "91919191-9191-4919-8919-919191919191"
        const val WEAR_SESSION_ID = "92929292-9292-4929-8929-929292929292"
    }
}
