package md.vox.android

import android.app.ActivityManager
import android.content.Context
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingPresetSnapshotCodec
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.SpeechModelCatalog
import md.vox.android.platformservices.SpeechModelEngine
import md.vox.android.platformservices.SpeechModelInstallPhase
import md.vox.android.platformservices.SpeechModelManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Host-orchestrated qualification for one immutable Whisper or Parakeet package at a time. */
@RunWith(AndroidJUnit4::class)
class NamedModelInferenceInstrumentationTest {
    @Test
    fun undersizedDeviceRejectsMediumBeforeDownload() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val memoryInfo = ActivityManager.MemoryInfo()
        (context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memoryInfo)
        val descriptor = requireNotNull(SpeechModelCatalog.find("ggml-medium"))
        assumeTrue(
            "this assertion runs on the standard-memory qualification device",
            memoryInfo.totalMem < descriptor.minimumMemoryBytes,
        )
        val manager = SpeechModelManager.get(context)

        manager.install(descriptor.id)
        val failed = awaitModelFailure(manager, descriptor.id)

        assertEquals("insufficientDeviceMemory", failed.failureCode)
        assertTrue(
            !File(context.noBackupFilesDir, "speech-models-v1/${descriptor.id}.installing").exists(),
        )
    }

    @Test
    fun downloadsVerifiesInstallsAndSelectsRequestedModel() {
        val modelID = requestedModelID()
        assumeTrue("named-model qualification requires -e voxModelID", modelID != null)
        val context = ApplicationProvider.getApplicationContext<Context>()
        val manager = SpeechModelManager.get(context)
        val descriptor = requireNotNull(SpeechModelCatalog.find(requireNotNull(modelID)))
        assertTrue(descriptor.engine != SpeechModelEngine.VOSK)
        assertTrue(descriptor.remoteFiles.isNotEmpty())

        manager.install(descriptor.id)
        val ready = awaitModel(manager, descriptor.id)
        assertEquals(descriptor.id, ready.descriptor.id)
        assertEquals(descriptor.approximateBytes, descriptor.remoteFiles.sumOf { it.expectedBytes })
        assertTrue(manager.select(descriptor.id))
        assertEquals(descriptor.id, manager.selectedModelID())
        val directory = requireNotNull(manager.selectedModelDirectory())
        val receipt = File(directory, "vox-model.properties").readText()
        assertTrue(receipt.contains("version=2"))
        assertTrue(receipt.contains("id=${descriptor.id}"))
        assertTrue(receipt.contains("engine=${descriptor.engine.name}"))
        descriptor.remoteFiles.forEach { artifact ->
            assertEquals(artifact.expectedBytes, File(directory, artifact.relativePath).length())
        }
    }

    @Test
    fun selectedRequestedModelTranscribesRealSpeechOfflineThroughProductionClient() {
        val modelID = requestedModelID()
        assumeTrue("named-model qualification requires -e voxModelID", modelID != null)
        val context = ApplicationProvider.getApplicationContext<Context>()
        val speechWav = File(context.filesDir, "local-speech-qualification/vosk-api-test.wav")
        assumeTrue("exact-hash speech fixture is staged only by the host gate", speechWav.length() > 200_000)
        val manager = SpeechModelManager.get(context)
        val descriptor = requireNotNull(SpeechModelCatalog.find(requireNotNull(modelID)))
        val ready = manager.state.value.models.single { it.descriptor.id == descriptor.id }
        assertEquals(SpeechModelInstallPhase.READY, ready.phase)
        assertTrue(manager.select(descriptor.id))

        val audioClient = AudioCaptureClient(context)
        val transcriptionClient = RecordingTranscriptionClient.get(context)
        val source = File(context.cacheDir, "named-model-speech-source").apply {
            deleteRecursively()
            assertTrue(mkdirs())
        }
        val pcm = pcm16Mono16Khz(speechWav)
        File(source, "chunk-000000.pcm").writeBytes(pcm)
        try {
            assertTrue(
                audioClient.importWearRecording(
                    sessionID = SESSION_ID,
                    createdAtEpochMillis = 1_700_000_000_000,
                    durationMillis = pcm.size * 1_000L / 32_000L,
                    chunkCount = 1,
                    sourceDirectory = source,
                    presetSnapshot = RecordingPresetSnapshotCodec.encode(testPreset()).toByteArray(),
                ),
            )
            transcriptionClient.process(SESSION_ID)
            val completed = awaitTranscription(transcriptionClient, descriptor.id)
            assertEquals(RecordingTranscriptionPhase.COMPLETED, completed.phase)
            assertEquals(descriptor.id, completed.modelID)
            val transcript = completed.transcript.orEmpty().lowercase()
            val recognizedDigits = spokenDigits(transcript)
            assertTrue("unexpected transcript: $transcript", recognizedDigits.length >= 5)
            assertTrue(
                "transcript does not match the reviewed number-sequence fixture: $transcript",
                longestCommonSubsequenceLength(EXPECTED_DIGITS, recognizedDigits) >= 6,
            )
        } finally {
            source.deleteRecursively()
            transcriptionClient.clear(SESSION_ID)
            audioClient.deleteRecording(SESSION_ID)
            manager.delete(descriptor.id)
            context.getSharedPreferences("vox-transcription-quota-v1", Context.MODE_PRIVATE).edit().clear().commit()
        }
    }

    private fun requestedModelID(): String? = InstrumentationRegistry.getArguments()
        .getString("voxModelID")
        ?.takeIf { it in QUALIFIED_MODEL_IDS }

    private fun awaitModel(
        manager: SpeechModelManager,
        modelID: String,
        timeoutMillis: Long = 45L * 60 * 1_000,
    ): md.vox.android.platformservices.SpeechModelInstallState {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            val state = manager.state.value.models.single { it.descriptor.id == modelID }
            if (state.phase == SpeechModelInstallPhase.READY) return state
            if (state.phase == SpeechModelInstallPhase.FAILED) error("model install failed: ${state.failureCode}")
            SystemClock.sleep(250)
        }
        error("timed out installing $modelID")
    }

    private fun awaitTranscription(
        client: RecordingTranscriptionClient,
        modelID: String,
        timeoutMillis: Long = 30L * 60 * 1_000,
    ): md.vox.android.platformservices.RecordingTranscriptionState {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            client.states.value[SESSION_ID]?.let { state ->
                if (state.phase == RecordingTranscriptionPhase.COMPLETED) return state
                if (state.phase == RecordingTranscriptionPhase.FAILED) {
                    error("local transcription failed: ${state.failureCode}")
                }
            }
            SystemClock.sleep(250)
        }
        error("timed out running $modelID local transcription")
    }

    private fun awaitModelFailure(
        manager: SpeechModelManager,
        modelID: String,
        timeoutMillis: Long = 5_000,
    ): md.vox.android.platformservices.SpeechModelInstallState {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            val state = manager.state.value.models.single { it.descriptor.id == modelID }
            if (state.phase == SpeechModelInstallPhase.FAILED) return state
            SystemClock.sleep(50)
        }
        error("timed out waiting for $modelID memory preflight")
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

    private fun spokenDigits(transcript: String): String = DIGIT_TOKEN
        .findAll(transcript.lowercase())
        .mapNotNull { match ->
            val token = match.value
            if (token.length == 1 && token[0].isDigit()) token else NUMBER_WORDS[token]
        }
        .joinToString(separator = "")

    private fun longestCommonSubsequenceLength(expected: String, actual: String): Int {
        val lengths = IntArray(actual.length + 1)
        expected.forEach { expectedCharacter ->
            var diagonal = 0
            actual.forEachIndexed { index, actualCharacter ->
                val above = lengths[index + 1]
                lengths[index + 1] = if (expectedCharacter == actualCharacter) {
                    diagonal + 1
                } else {
                    maxOf(lengths[index], above)
                }
                diagonal = above
            }
        }
        return lengths.last()
    }

    private fun testPreset() = CapturePreset(
        id = "96969696-9696-4969-8969-969696969696",
        name = "Named model qualification",
        symbol = "waveform",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "named-model-{id}",
        metadataFields = emptyList(),
    )

    private companion object {
        const val SESSION_ID = "95959595-9595-4959-8959-959595959595"
        const val EXPECTED_DIGITS = "1000190201803"
        val DIGIT_TOKEN = Regex("[a-z]+|\\d")
        val NUMBER_WORDS = mapOf(
            "zero" to "0",
            "oh" to "0",
            "one" to "1",
            "two" to "2",
            "three" to "3",
            "four" to "4",
            "five" to "5",
            "six" to "6",
            "seven" to "7",
            "eight" to "8",
            "nine" to "9",
        )
        val QUALIFIED_MODEL_IDS = setOf(
            "parakeet-v2",
            "parakeet-v3",
            "ggml-tiny",
            "ggml-base",
            "ggml-small",
            "ggml-medium",
            "ggml-large-v3-turbo",
        )
    }
}
