package md.vox.android

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.os.Debug
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.util.AtomicFile
import android.widget.TextView
import java.io.File
import java.io.OutputStream
import java.security.MessageDigest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.job
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.*
import org.json.JSONArray
import org.json.JSONObject

/** Debug-only, isolated hardware harness. Reports contain metadata/hashes, never microphone audio.
 * Shell commands are accepted only by the separate qualification application ID.
 */
class PhysicalQualificationActivity : Activity() {
    private lateinit var audio: AudioCaptureClient
    private lateinit var label: TextView
    private val worker = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val handler = Handler(Looper.getMainLooper())
    private val safetyStop = Runnable { audio.stop() }
    private val root get() = File(filesDir, "physical-qualification").apply { mkdirs() }
    private val ticker = object : Runnable {
        override fun run() { worker.launch { report("status", false) }; handler.postDelayed(this, 10_000) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        check(packageName == "md.vox.android.qualification") { "Separate qualification installation required" }
        label = TextView(this).apply { text = "Physical qualification · private audio stays on this device"; textSize = 20f }
        setContentView(label)
        audio = AudioCaptureClient(this)
        write("build", JSONObject(assets.open("physical-build.json").bufferedReader().use { it.readText() }))
        write("model-build", JSONObject(assets.open("physical-model-build.json").bufferedReader().use { it.readText() }))
        handler.post(ticker)
        command(intent)
    }

    override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); command(intent) }
    override fun onDestroy() { handler.removeCallbacks(ticker); super.onDestroy() }

    private fun command(intent: Intent) {
        val action = intent.getStringExtra("command") ?: "status"
        label.text = "Physical qualification · $action\nMicrophone recordings stay private on this device."
        when (action) {
            "start" -> {
                if (RecordingStatusRegistry.status.value.isActive) {
                    write("start-refused", JSONObject().put("reason", "recordingAlreadyActive"))
                    return
                }
                VoiceAutoStopSettingsStore.get(this).update(VoiceAutoStopSettings(enabled = false))
                audio.start(preset())
                armSafetyStop()
            }
            "resume" -> { audio.resume(); armSafetyStop() }
            "pause" -> audio.pause()
            "stop" -> { handler.removeCallbacks(safetyStop); audio.stop() }
            "checkpoint", "status" -> worker.launch { report(action, action == "checkpoint") }
            "finalize" -> worker.launch {
                val deadline = SystemClock.elapsedRealtime() + 30_000
                while (RecordingStatusRegistry.status.value.isActive && SystemClock.elapsedRealtime() < deadline) Thread.sleep(100)
                check(!RecordingStatusRegistry.status.value.isActive) { "Recording still active" }
                report("final", true)
            }
            "instructions" -> launchCommand("instructions") { runInstructions() }
            "speech" -> launchCommand("speech") { runSpeech() }
            "provider-capture" -> launchCommand("provider-capture") { runProviderCapture() }
            "provider-retry" -> launchCommand("provider-retry") { retryProviderCapture() }
            "provider-revoke" -> {
                val uri = android.net.Uri.parse(File(root, "provider-uri").readText())
                contentResolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                write("provider-revoke", JSONObject().put("authority", uri.authority).put("revoked", true))
            }
            "choose-provider" -> startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                File(root, "provider-uri").takeIf(File::isFile)?.let {
                    putExtra(android.provider.DocumentsContract.EXTRA_INITIAL_URI, android.net.Uri.parse(it.readText()))
                }
            }, 41)
            else -> error("Unknown qualification command")
        }
    }

    private fun armSafetyStop() {
        handler.removeCallbacks(safetyStop)
        handler.postDelayed(safetyStop, 65 * 60_000L)
    }

    private fun launchCommand(name: String, block: suspend () -> Unit) = worker.launch {
        try { kotlinx.coroutines.withTimeout(15 * 60_000L) { block() } }
        catch (error: Exception) {
            // Platform/provider exceptions can contain private tree URIs. Keep only the type.
            write(name, JSONObject().put("status", "failed").put("failureType", error.javaClass.simpleName))
        }
    }

    @Deprecated("Platform activity result used by the debug-only harness")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 41) return
        val uri = data?.data
        if (resultCode == RESULT_OK && uri != null) {
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            contentResolver.takePersistableUriPermission(uri, flags)
            // The URI may contain an account identifier; it stays device-private.
            File(root, "provider-uri").writeText(uri.toString())
            File(root, "provider-approved").delete()
            write("provider-selection", JSONObject().put("authority", uri.authority).put("persisted", true))
            label.text = "Physical qualification · test folder granted"
        } else {
            write("provider-selection", JSONObject().put("persisted", false))
            label.text = "Physical qualification · folder permission not granted"
        }
    }

    private fun report(name: String, hashes: Boolean) {
        val state = RecordingStatusRegistry.status.value
        val memory = Debug.MemoryInfo().also(Debug::getMemoryInfo)
        val value = JSONObject().put("schemaVersion", 1).put("package", packageName)
            .put("uptimeMillis", SystemClock.elapsedRealtime()).put("phase", state.phase.name)
            .put("sessionID", state.sessionID).put("elapsedMillis", state.elapsedMillis)
            .put("chunkCount", state.chunkCount).put("failureCode", state.failureCode)
            .put("pssKiB", memory.totalPss).put("nativeHeapBytes", Debug.getNativeHeapAllocatedSize())
            .put("thermalStatus", if (android.os.Build.VERSION.SDK_INT >= 29) getSystemService(PowerManager::class.java).currentThermalStatus else -1)
        val directory = state.sessionID?.let { File(noBackupFilesDir, "recordings/$it") }
        val chunks = directory?.listFiles().orEmpty().filter { it.name.matches(Regex("chunk-[0-9]{6}\\.pcm")) }.sortedBy { it.name }
        value.put("finalizedBytes", chunks.sumOf(File::length)).put("finalizedChunks", chunks.size)
        if (hashes) {
            value.put("chunks", JSONArray(chunks.map { JSONObject().put("name", it.name).put("bytes", it.length()).put("sha256", hash(it)) }))
            if (state.phase != RecordingPhase.RECORDING && chunks.isNotEmpty()) {
                val digest = MessageDigest.getInstance("SHA-256")
                var count = 0L
                val header = ByteArray(44)
                var headerLength = 0
                val sink = object : OutputStream() {
                    override fun write(b: Int) {
                        if (headerLength < 44) header[headerLength++] = b.toByte()
                        digest.update(b.toByte()); count++
                    }
                    override fun write(b: ByteArray, offset: Int, length: Int) {
                        val copied = minOf(44-headerLength,length)
                        if (copied > 0) { b.copyInto(header,headerLength,offset,offset+copied); headerLength += copied }
                        digest.update(b, offset, length); count += length
                    }
                }
                value.put("wavExportVerified", audio.exportWav(requireNotNull(state.sessionID), sink))
                    .put("wavBytes", count).put("wavSHA256", digest.digest().joinToString("") { "%02x".format(it) })
                    .put("wavHeaderVerified", headerLength == 44 && validWavHeader(header,count))
            }
        }
        write(name, value)
    }

    private fun validWavHeader(header: ByteArray, count: Long): Boolean {
        val values = java.nio.ByteBuffer.wrap(header).order(java.nio.ByteOrder.LITTLE_ENDIAN)
        return header.copyOfRange(0,4).decodeToString()=="RIFF" && header.copyOfRange(8,16).decodeToString()=="WAVEfmt " &&
            header.copyOfRange(36,40).decodeToString()=="data" && (values.getInt(4).toLong() and 0xffffffffL)==count-8 &&
            values.getInt(16)==16 && values.getShort(20).toInt()==1 && values.getShort(22).toInt()==1 &&
            values.getInt(24)==16000 && values.getInt(28)==32000 && values.getShort(32).toInt()==2 &&
            values.getShort(34).toInt()==16 && (values.getInt(40).toLong() and 0xffffffffL)==count-44
    }

    private suspend fun runInstructions() {
        check(!RecordingStatusRegistry.status.value.isActive) { "Finish recording before model measurements" }
        val model = File(root, "instruction-model.gguf")
        InstructionModelManager.get(this).installImported(model.inputStream())
        val corpus = File(root, "corpus.json").readText()
        val cases = IntelligenceEvaluation.instructionCases(corpus)
        val rows = JSONArray()
        val sampler = sampleModel("instruction-memory", currentCoroutineContext().job)
        try { repeat(3) { round -> for (case in cases) {
            check(thermalStatus() < 3) { "physicalThermalStop" }
            val started = SystemClock.elapsedRealtime()
            val result = LocalIntelligenceProcessor.get(this).process(case.source, preset().copy(
                processingEnabled = true, processingMode = md.vox.android.capturedomain.CaptureProcessingMode.CUSTOM,
                customProcessingInstruction = case.instruction), false)
            val response = result?.processedText.orEmpty()
            rows.put(JSONObject().put("round", round).put("id", case.id).put("passed", result?.outcome == md.vox.android.capturedomain.CaptureTextProcessingOutcome.APPLIED && IntelligenceEvaluation.passes(case, response))
                .put("elapsedMillis", SystemClock.elapsedRealtime() - started))
        } } } finally { sampler.cancelAndJoin() }
        write("instructions", JSONObject().put("modelSHA256", InstructionModel.SHA256).put("results", rows))
    }

    private fun thermalStatus(): Int = if (android.os.Build.VERSION.SDK_INT >= 29)
        getSystemService(PowerManager::class.java).currentThermalStatus else -1

    private fun sampleModel(name: String, owner: kotlinx.coroutines.Job) = worker.launch {
        val file = File(root, "$name.ndjson")
        file.outputStream().bufferedWriter().use { output ->
            while (isActive) {
                val memory = Debug.MemoryInfo().also(Debug::getMemoryInfo)
                val deviceMemory = android.app.ActivityManager.MemoryInfo()
                getSystemService(android.app.ActivityManager::class.java).getMemoryInfo(deviceMemory)
                output.appendLine(JSONObject().put("uptimeMillis", SystemClock.elapsedRealtime()).put("pssKiB", memory.totalPss)
                    .put("nativeHeapBytes", Debug.getNativeHeapAllocatedSize()).put("availableMemoryBytes", deviceMemory.availMem)
                    .put("lowMemory", deviceMemory.lowMemory).put("thermalStatus", thermalStatus()).toString())
                output.flush()
                if (thermalStatus() >= 4 || deviceMemory.lowMemory) {
                    write("$name-guard", JSONObject().put("aborted", true).put("thermalStatus", thermalStatus()).put("lowMemory", deviceMemory.lowMemory))
                    owner.cancel(CancellationException("Physical safety guard"))
                    break
                }
                delay(1000)
            }
        }
    }

    private suspend fun runSpeech() {
        check(!RecordingStatusRegistry.status.value.isActive)
        val archive = File(root, "vosk-model-small-en-us-0.15.zip")
        check(hash(archive) == "30f26242c4eb449f948e42cb302dd7a686cb29a3423a8367f99ff41780942498")
        val manager = SpeechModelManager.get(this)
        manager.installImportedZip("vosk-small-en-us-0.15", archive.inputStream())
        val deadline = SystemClock.elapsedRealtime() + 120_000
        while (manager.state.value.models.none { it.descriptor.id == "vosk-small-en-us-0.15" && it.phase == SpeechModelInstallPhase.READY }) {
            check(SystemClock.elapsedRealtime() < deadline); delay(50)
        }
        check(manager.select("vosk-small-en-us-0.15"))
        val wav = File(root, "vosk-api-test.wav")
        check(hash(wav) == "dcfea5712c43a43ba7ae8083afb39d36993e5a69c46e88b68aaa72b65cb615bb")
        val pcm = wavPcm(wav.readBytes())
        val results = JSONArray()
        val sampler = sampleModel("speech-memory", currentCoroutineContext().job)
        try { repeat(3) { round ->
            val id = java.util.UUID.randomUUID().toString()
            val source = File(cacheDir, "physical-speech-$id").apply { mkdirs() }
            File(source, "chunk-000000.pcm").writeBytes(pcm)
            check(audio.importWearRecording(id, System.currentTimeMillis(), pcm.size * 1000L / 32000,
                1, source, RecordingPresetSnapshotCodec.encode(preset()).toByteArray()))
            val client = RecordingTranscriptionClient.get(this)
            val started = SystemClock.elapsedRealtime()
            client.process(id)
            while (client.states.value[id]?.phase !in setOf(RecordingTranscriptionPhase.COMPLETED, RecordingTranscriptionPhase.FAILED)) {
                check(SystemClock.elapsedRealtime() - started < 120_000); delay(50)
            }
            val result = requireNotNull(client.states.value[id])
            val transcript = result.transcript.orEmpty().lowercase()
            results.put(JSONObject().put("round", round).put("elapsedMillis", SystemClock.elapsedRealtime()-started)
                .put("passed", result.phase == RecordingTranscriptionPhase.COMPLETED && listOf("one", "zero", "nine").all(transcript::contains)))
            source.deleteRecursively()
            client.clear(id); audio.dismissResult(); audio.deleteRecording(id)
        } } finally { sampler.cancelAndJoin() }
        write("speech", JSONObject().put("modelID", "vosk-small-en-us-0.15").put("results", results))
    }

    private suspend fun runProviderCapture() {
        val uri = android.net.Uri.parse(File(root, "provider-uri").readText())
        check(android.provider.DocumentsContract.isTreeUri(uri))
        val providerPackage = packageManager.resolveContentProvider(requireNotNull(uri.authority), 0)?.packageName
        check(providerPackage in setOf("com.google.android.apps.docs", "com.microsoft.skydrive"))
        val approval = File(root, "provider-approved")
        if (!approval.isFile || approval.readText() != uri.toString()) {
            val document = android.provider.DocumentsContract.buildDocumentUriUsingTree(uri, android.provider.DocumentsContract.getTreeDocumentId(uri))
            contentResolver.query(document, arrayOf("_display_name"), null, null, null)!!.use {
                check(it.moveToFirst() && it.getString(0) == "Vox-Qualification-20261101") { "Dedicated qualification folder required" }
            }
            approval.writeText(uri.toString())
        }
        val repository = (application as VoxApplication).compositionRoot.captureRepository
        repository.saveDestination(uri.toString(), "Physical qualification folder")
        val id = java.util.UUID.randomUUID().toString()
        File(root, "provider-request-id").writeText(id)
        val result = repository.submitRecording("Vox.md physical qualification. Synthetic test content only.", null,
            id, null, null, preset().copy(logicalFolder = "Inbox", noteNameTemplate = "qualification-{id}.md"), "app")
        writeProviderResult("provider-capture", id, result)
    }

    private suspend fun retryProviderCapture() {
        val id = File(root, "provider-request-id").readText()
        val result = (application as VoxApplication).compositionRoot.captureRepository.retry(id)
        writeProviderResult("provider-retry", id, result)
    }

    private suspend fun writeProviderResult(name: String, id: String, result: md.vox.android.capturedomain.CaptureSubmitResult) {
        val uri = android.net.Uri.parse(File(root, "provider-uri").readText())
        val treeID = android.provider.DocumentsContract.getTreeDocumentId(uri)
        val fileName = "qualification-$id.md"
        val matching = mutableListOf<String>()
        try {
            val folders = mutableListOf<String>()
            contentResolver.query(android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(uri,treeID),
                arrayOf("document_id","_display_name"),null,null,null)?.use { cursor ->
                while (cursor.moveToNext()) if (cursor.getString(1)=="Inbox") folders.add(cursor.getString(0))
            }
            check(folders.size <= 1) { "Ambiguous test folder" }
            val parentID = folders.singleOrNull() ?: treeID
            val children = android.provider.DocumentsContract.buildChildDocumentsUriUsingTree(uri, parentID)
            contentResolver.query(children, arrayOf("document_id", "_display_name"), null, null, null)?.use { cursor ->
            while (cursor.moveToNext()) if (cursor.getString(1) == fileName) matching.add(cursor.getString(0))
        } } catch (_: SecurityException) { /* Expected while this app's tree grant is revoked. */ }
        val digests = matching.map { documentID ->
            val document = android.provider.DocumentsContract.buildDocumentUriUsingTree(uri, documentID)
            val digest = MessageDigest.getInstance("SHA-256")
            contentResolver.openInputStream(document)!!.use { input ->
                val buffer = ByteArray(8192); while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer,0,count) }
            }
            digest.digest().joinToString("") { "%02x".format(it) }
        }
        write(name, JSONObject().put("authority", uri.authority).put("result", result.javaClass.simpleName)
            .put("durablySaved", (application as VoxApplication).compositionRoot.captureRepository.hasDurableCapture(id))
            .put("providerPackage", packageManager.resolveContentProvider(requireNotNull(uri.authority), 0)?.packageName)
            .put("requestID", id).put("matchingDocumentCount", matching.size).put("sha256", JSONArray(digests)))
    }

    private fun wavPcm(bytes: ByteArray): ByteArray {
        check(bytes.copyOfRange(0,4).decodeToString() == "RIFF" && bytes.copyOfRange(8,12).decodeToString() == "WAVE")
        var offset = 12
        var formatVerified = false
        while (offset + 8 <= bytes.size) {
            val name = bytes.copyOfRange(offset,offset+4).decodeToString()
            val size = java.nio.ByteBuffer.wrap(bytes,offset+4,4).order(java.nio.ByteOrder.LITTLE_ENDIAN).int
            check(size >= 0 && offset + 8L + size <= bytes.size)
            val payload = offset + 8
            if (name == "fmt ") {
                check(size >= 16)
                val format = java.nio.ByteBuffer.wrap(bytes,payload,16).slice().order(java.nio.ByteOrder.LITTLE_ENDIAN)
                check(format.short.toInt() == 1 && format.short.toInt() == 1 && format.int == 16000)
                format.position(14); check(format.short.toInt() == 16); formatVerified = true
            }
            if (name == "data") { check(formatVerified && size > 0 && size % 2 == 0); return bytes.copyOfRange(payload,payload+size) }
            offset = payload + size + (size and 1)
        }
        error("Missing WAV PCM")
    }

    private fun write(name: String, value: JSONObject) {
        val atomic = AtomicFile(File(root, "$name.json"))
        val stream = atomic.startWrite()
        try { stream.write(value.toString(2).toByteArray()); atomic.finishWrite(stream) }
        catch (error: Exception) { atomic.failWrite(stream); throw error }
    }

    private fun hash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input -> val buffer = ByteArray(64 * 1024); while (true) {
            val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count)
        } }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun preset() = CapturePreset(id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc", name = "Physical qualification",
        symbol = "mic", revision = 1, logicalFolder = "Vox-Qualification", noteNameTemplate = "qualification-{id}", metadataFields = emptyList())
}
