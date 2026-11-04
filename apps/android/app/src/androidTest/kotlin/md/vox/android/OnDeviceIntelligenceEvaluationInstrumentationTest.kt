package md.vox.android

import android.content.Context
import android.os.SystemClock
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.security.MessageDigest
import java.util.zip.ZipInputStream
import kotlinx.coroutines.runBlocking
import md.vox.android.capturedomain.*
import md.vox.android.platformservices.*
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.SpeakerModel

class OnDeviceIntelligenceEvaluationInstrumentationTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val fixtures get() = File(context.filesDir, "local-intelligence-qualification")
    private fun corpusText() = InstrumentationRegistry.getInstrumentation().context.assets.open("corpus.json").bufferedReader().use { it.readText() }

    @Test @ProvisionedModelTest fun pinnedModelRunsSharedInstructionsOffline() = runBlocking {
        val archive = File(fixtures, "instruction-model.gguf")
        assertTrue("host must stage the exact-hash GGUF", archive.isFile)
        val models = InstructionModelManager.get(context)
        models.installImported(archive.inputStream())
        assertEquals(InstructionModelPhase.READY, models.state.value.phase)
        assertNotNull(models.verifiedModel())
        val results = JSONArray()
        for (case in IntelligenceEvaluation.instructionCases(corpusText())) {
            val started = SystemClock.elapsedRealtime()
            val preset = preset(case.instruction)
            val result = requireNotNull(LocalIntelligenceProcessor.get(context).process(case.source, preset, false))
            val passed = result.outcome in setOf(CaptureTextProcessingOutcome.APPLIED, CaptureTextProcessingOutcome.UNCHANGED) &&
                IntelligenceEvaluation.passes(case, result.processedText)
            val row = JSONObject().put("id", case.id).put("response", result.processedText)
            if (result.outcome == CaptureTextProcessingOutcome.MODEL_FAILURE) {
                row.put("rejectedCandidate", InstructionEvaluationProbe.candidate(context, case.source, case.instruction))
            }
            results.put(row
                .put("outcome", result.outcome.name).put("passed", passed)
                .put("elapsedSeconds", (SystemClock.elapsedRealtime() - started) / 1000.0))
        }
        val report = JSONObject().put("schemaVersion", 1).put("corpusID", "vox-local-intelligence-v1")
            .put("platform", "android").put("runtime", "llama.cpp-b5046-cpu")
            .put("modelID", InstructionModel.ID).put("modelSHA256", InstructionModel.SHA256)
            .put("results", results)
        File(context.filesDir, "instruction-evaluation.json").writeText(report.toString(2))
        models.installImported("invalid model bytes".byteInputStream())
        assertEquals(InstructionModelPhase.READY, models.state.value.phase)
        assertNotNull(models.verifiedModel())
        assertFalse(File(context.noBackupFilesDir, "instruction-model-v1/model.installing").exists())
        for (index in 0 until results.length()) assertTrue(results.getJSONObject(index).toString(), results.getJSONObject(index).getBoolean("passed"))
        val test = IntelligenceEvaluation.instructionCases(corpusText()).first()
        val repository = (context.applicationContext as VoxApplication).compositionRoot.captureRepository
        val tree = android.provider.DocumentsContract.buildTreeDocumentUri(TestDocumentsProvider.AUTHORITY, TestDocumentsProvider.ROOT_ID)
        repository.saveDestination(tree.toString(), "Vox Test Documents")
        val id = "c1c1c1c1-c1c1-41c1-81c1-c1c1c1c1c1c1"
        val delivered = repository.submitRecording(test.source, null, id, null, null,
            preset(test.instruction).copy(logicalFolder = "Intelligence", noteNameTemplate = "instruction-{id}.md", audioSaveMode = CaptureAudioSaveMode.OFF), "app")
        assertTrue("production repository delivery failed: $delivered", delivered is CaptureSubmitResult.Delivered)
        val note = android.provider.DocumentsContract.buildDocumentUriUsingTree(tree, "Intelligence/instruction-$id.md")
        val markdown = context.contentResolver.openInputStream(note)!!.bufferedReader().use { it.readText() }
        assertTrue(markdown, markdown.contains("Arun\nMaya\nZoe"))
        models.delete()
        val deletedAt = SystemClock.elapsedRealtime() + 10_000
        while (models.state.value.phase != InstructionModelPhase.ABSENT) {
            check(SystemClock.elapsedRealtime() < deletedAt); kotlinx.coroutines.delay(20)
        }
        assertTrue(repository.retry(id) is CaptureSubmitResult.Delivered)
        assertEquals(markdown, context.contentResolver.openInputStream(note)!!.bufferedReader().use { it.readText() })
        report.put("repositoryDeliveryVerified", true).put("retryWithoutModelVerified", true)
        File(context.filesDir, "instruction-evaluation.json").writeText(report.toString(2))
    }

    @Test @ProvisionedModelTest fun realSpeechSpeakerAttributionBenchmark() {
        val archive = File(fixtures, "vosk-model-small-en-us-0.15.zip")
        assertTrue("host must stage the exact-hash Vosk model", archive.isFile)
        val manager = SpeechModelManager.get(context)
        manager.installImportedZip("vosk-small-en-us-0.15", archive.inputStream())
        val deadline = SystemClock.elapsedRealtime() + 120_000
        while (manager.state.value.models.none { it.descriptor.id == "vosk-small-en-us-0.15" && it.phase == SpeechModelInstallPhase.READY }) {
            check(SystemClock.elapsedRealtime() < deadline) { "speech fixture install timed out" }
            SystemClock.sleep(50)
        }
        assertTrue(manager.select("vosk-small-en-us-0.15"))
        val speakerArchive = File(fixtures, "vosk-model-spk-0.4.zip")
        assertEquals("a74d8f51144484813e16af689bb0f916b7a111e2347f467c4933c1166097b5a7", sha256(speakerArchive.readBytes()))
        val speakerRoot = File(context.cacheDir, "speaker-benchmark-model").apply { deleteRecursively(); mkdirs() }
        ZipInputStream(speakerArchive.inputStream()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val target = File(speakerRoot, entry.name)
                require(target.canonicalPath.startsWith(speakerRoot.canonicalPath + File.separator))
                if (entry.isDirectory) target.mkdirs() else { target.parentFile!!.mkdirs(); target.outputStream().use { zip.copyTo(it) } }
                zip.closeEntry()
            }
        }
        val corpus = JSONObject(corpusText())
        val audio = corpus.getJSONArray("speakerAudio")
        val sequence = corpus.getJSONArray("speakerSequence")
        val observations = mutableListOf<SpeakerObservation>()
        val reference = mutableListOf<String>()
        val weights = mutableListOf<Double>()
        val started = SystemClock.elapsedRealtime()
        Model(requireNotNull(manager.selectedModelDirectory()).absolutePath).use { model ->
            SpeakerModel(File(speakerRoot, "vosk-model-spk-0.4").absolutePath).use { speaker ->
                for (index in 0 until sequence.length()) {
                    val clip = (0 until audio.length()).map(audio::getJSONObject).single { it.getString("id") == sequence.getString(index) }
                    val bytes = InstrumentationRegistry.getInstrumentation().context.assets.open(clip.getString("file")).use { it.readBytes() }
                    assertEquals(clip.getString("sha256"), sha256(bytes))
                    val pcm = wavPcm(bytes)
                    val clipObservations = mutableListOf<SpeakerObservation>()
                    Recognizer(model, 16_000f, speaker).use { recognizer ->
                        for (offset in pcm.indices step 4096) {
                            val chunk = pcm.copyOfRange(offset, minOf(offset + 4096, pcm.size))
                            if (recognizer.acceptWaveForm(chunk, chunk.size)) jsonSpeakerObservation(recognizer.result, index)?.let(clipObservations::add)
                        }
                        jsonSpeakerObservation(recognizer.finalResult, index)?.let(clipObservations::add)
                    }
                    assertTrue("no acoustic speaker vector for ${clip.getString("id")}", clipObservations.any { it.vector != null && it.frameCount >= 100 })
                    for (observation in clipObservations) {
                        observations += observation
                        reference += clip.getString("speaker")
                        weights += clip.getDouble("durationSeconds") / clipObservations.size
                    }
                }
            }
        }
        val result = LocalSpeakerDiarizer.diarize(observations, observations.joinToString(" ") { it.text })
        val predicted = result.speakerAssignments.map(Int::toString)
        val error = IntelligenceEvaluation.speakerAttributionError(reference, predicted, weights)
        val report = JSONObject().put("schemaVersion", 1).put("corpusID", "vox-local-intelligence-v1")
            .put("platform", "android").put("runtime", "Vosk-spk-0.4 / LocalSpeakerDiarizer")
            .put("metric", "known-turn-duration-weighted-attribution-error")
            .put("reference", JSONArray(reference)).put("predicted", JSONArray(predicted)).put("durations", JSONArray(weights))
            .put("speakerCount", result.speakerCount).put("attributionError", error)
            .put("elapsedSeconds", (SystemClock.elapsedRealtime() - started) / 1000.0)
        File(context.filesDir, "speaker-evaluation.json").writeText(report.toString(2))
        assertTrue(observations.all { it.text in result.transcript })
        assertEquals(2, result.speakerCount)
        assertEquals(0.0, error, 0.000001)
        speakerRoot.deleteRecursively()
    }

    private fun preset(instruction: String) = CapturePreset(id = "abababab-abab-4bab-8bab-abababababab", name = "Evaluation", symbol = "sparkles", revision = 1,
        logicalFolder = "Inbox", noteNameTemplate = "evaluation-{id}", metadataFields = emptyList(), processingEnabled = true, processingMode = CaptureProcessingMode.CUSTOM,
        customProcessingInstruction = instruction)

    private fun sha256(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    private fun wavPcm(bytes: ByteArray): ByteArray {
        require(bytes.copyOfRange(0, 4).decodeToString() == "RIFF")
        var offset = 12
        while (offset + 8 <= bytes.size) {
            val size = java.nio.ByteBuffer.wrap(bytes, offset + 4, 4).order(java.nio.ByteOrder.LITTLE_ENDIAN).int
            require(size >= 0 && offset + 8L + size <= bytes.size)
            if (bytes.copyOfRange(offset, offset + 4).decodeToString() == "data") return bytes.copyOfRange(offset + 8, offset + 8 + size)
            offset += 8 + size + (size and 1)
        }
        error("missing WAV data")
    }
}
