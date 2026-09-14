package md.vox.android.platformservices

import android.content.Context
import android.util.AtomicFile
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicReference
import java.util.zip.ZipInputStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

enum class SpeakerModelInstallPhase { NOT_INSTALLED, DOWNLOADING, VERIFYING, INSTALLING, READY, FAILED }

data class SpeakerModelState(
    val phase: SpeakerModelInstallPhase,
    val downloadedBytes: Long = 0,
    val totalBytes: Long? = null,
    val installedBytes: Long = 0,
    val failureCode: String? = null,
) {
    val progress: Float?
        get() = totalBytes?.takeIf { it > 0 }?.let { (downloadedBytes.toDouble() / it).coerceIn(0.0, 1.0).toFloat() }
}

/** Explicit, content-free lifecycle for Vosk's all-language speaker-vector model. */
class SpeakerModelManager private constructor(context: Context) {
    private val root = File(context.applicationContext.noBackupFilesDir, "speaker-model-v1").apply { mkdirs() }
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val activeJob = AtomicReference<Job?>(null)
    private val mutableState = MutableStateFlow(
        installedDirectory()?.let {
            SpeakerModelState(SpeakerModelInstallPhase.READY, installedBytes = it.speakerDirectorySize())
        } ?: SpeakerModelState(SpeakerModelInstallPhase.NOT_INSTALLED),
    )
    val state: StateFlow<SpeakerModelState> = mutableState.asStateFlow()

    fun refresh() {
        mutableState.value = snapshot()
    }

    fun install() {
        if (activeJob.get() != null || installedDirectory() != null) return
        val job = scope.launch(start = CoroutineStart.LAZY) {
            try {
                downloadAndInstall()
            } catch (cancelled: CancellationException) {
                cleanupInstalling()
                update(SpeakerModelInstallPhase.NOT_INSTALLED)
                throw cancelled
            } catch (error: Throwable) {
                cleanupInstalling()
                update(SpeakerModelInstallPhase.FAILED, failureCode = speakerModelFailureCode(error))
            } finally {
                activeJob.set(null)
            }
        }
        if (activeJob.compareAndSet(null, job)) job.start() else job.cancel()
    }

    fun cancel() {
        activeJob.get()?.cancel()
    }

    fun delete(): Boolean {
        if (activeJob.get()?.isActive == true) return false
        val installed = installedDirectory() ?: return false
        val deleted = installed.deleteRecursively()
        if (deleted) {
            archiveFile.delete()
            refresh()
        }
        return deleted
    }

    fun modelDirectory(): File? = installedDirectory()

    private suspend fun downloadAndInstall() {
        check(root.usableSpace >= REQUIRED_FREE_BYTES) { "insufficientStorage" }
        val existing = archiveFile.length().coerceAtLeast(0)
        val connection = (URL(DOWNLOAD_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 30_000
            instanceFollowRedirects = false
            setRequestProperty("Accept-Encoding", "identity")
            if (existing > 0) setRequestProperty("Range", "bytes=$existing-")
        }
        try {
            connection.connect()
            val code = connection.responseCode
            if (code == 416 && existing == EXPECTED_ARCHIVE_BYTES) {
                update(SpeakerModelInstallPhase.DOWNLOADING, existing, EXPECTED_ARCHIVE_BYTES)
            } else {
                check(code == HttpURLConnection.HTTP_OK || code == HttpURLConnection.HTTP_PARTIAL) { "downloadHttp$code" }
                val append = code == HttpURLConnection.HTTP_PARTIAL && existing > 0
                var written = if (append) existing else 0L
                val announced = connection.contentLengthLong.takeIf { it > 0 }
                val total = announced?.plus(written)
                check(total == null || total <= MAX_ARCHIVE_BYTES) { "modelArchiveTooLarge" }
                update(SpeakerModelInstallPhase.DOWNLOADING, written, total)
                BufferedInputStream(connection.inputStream).use { input ->
                    FileOutputStream(archiveFile, append).use { output ->
                        val buffer = ByteArray(128 * 1_024)
                        while (true) {
                            kotlinx.coroutines.currentCoroutineContext().ensureActive()
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                            written += count
                            check(written <= MAX_ARCHIVE_BYTES) { "modelArchiveTooLarge" }
                            update(SpeakerModelInstallPhase.DOWNLOADING, written, total)
                        }
                        output.flush()
                        output.fd.sync()
                    }
                }
            }
        } finally {
            connection.disconnect()
        }
        installArchive()
    }

    private suspend fun installArchive() {
        check(archiveFile.length() == EXPECTED_ARCHIVE_BYTES) { "invalidModelArchive" }
        update(SpeakerModelInstallPhase.VERIFYING, archiveFile.length(), EXPECTED_ARCHIVE_BYTES)
        check(speakerSha256(archiveFile) == EXPECTED_ARCHIVE_SHA256) { "invalidModelChecksum" }
        cleanupInstalling()
        check(installingDirectory.mkdir()) { "modelStagingDirectory" }
        try {
            update(SpeakerModelInstallPhase.INSTALLING, archiveFile.length(), EXPECTED_ARCHIVE_BYTES)
            var fileCount = 0
            var expandedBytes = 0L
            ZipInputStream(BufferedInputStream(archiveFile.inputStream())).use { zip ->
                while (true) {
                    kotlinx.coroutines.currentCoroutineContext().ensureActive()
                    val entry = zip.nextEntry ?: break
                    fileCount += 1
                    check(fileCount <= MAX_FILES) { "modelArchiveFileLimit" }
                    val target = safeModelArchiveTarget(installingDirectory, entry.name)
                    if (entry.isDirectory) {
                        check(target.mkdirs() || target.isDirectory) { "modelDirectoryCreate" }
                    } else {
                        check(target.parentFile?.let { it.mkdirs() || it.isDirectory } == true) { "modelDirectoryCreate" }
                        FileOutputStream(target).use { output ->
                            val buffer = ByteArray(128 * 1_024)
                            while (true) {
                                val count = zip.read(buffer)
                                if (count < 0) break
                                output.write(buffer, 0, count)
                                expandedBytes += count
                                check(expandedBytes <= MAX_EXPANDED_BYTES) { "modelExpandedTooLarge" }
                            }
                            output.flush()
                            output.fd.sync()
                        }
                    }
                    zip.closeEntry()
                }
            }
            val children = installingDirectory.listFiles().orEmpty().filterNot { it.name == ".DS_Store" }
            val unpacked = if (children.size == 1 && children.single().isDirectory) children.single() else installingDirectory
            check(validateModel(unpacked)) { "invalidModelArchive" }
            AtomicFile(File(unpacked, RECEIPT_NAME)).writeSpeakerReceipt(
                "version=1\narchiveBytes=${archiveFile.length()}\narchiveSha256=$EXPECTED_ARCHIVE_SHA256\n",
            )
            check(!finalDirectory.exists()) { "modelAlreadyInstalled" }
            Files.move(unpacked.toPath(), finalDirectory.toPath(), StandardCopyOption.ATOMIC_MOVE)
            if (unpacked != installingDirectory) installingDirectory.deleteRecursively()
            archiveFile.delete()
            update(SpeakerModelInstallPhase.READY, installedBytes = finalDirectory.speakerDirectorySize())
        } catch (error: Throwable) {
            cleanupInstalling()
            throw error
        }
    }

    private fun installedDirectory(): File? = finalDirectory.takeIf {
        it.isDirectory && validateModel(it, requireReceipt = true)
    }

    private fun validateModel(directory: File, requireReceipt: Boolean = false): Boolean {
        val valid = REQUIRED_FILES.all { File(directory, it).isFile }
        if (!valid) return false
        return !requireReceipt || File(directory, RECEIPT_NAME).isFile
    }

    private fun cleanupInstalling() {
        installingDirectory.deleteRecursively()
    }

    private fun snapshot(): SpeakerModelState = installedDirectory()?.let {
        SpeakerModelState(SpeakerModelInstallPhase.READY, installedBytes = it.speakerDirectorySize())
    } ?: mutableState.value.takeIf {
        it.phase in setOf(
            SpeakerModelInstallPhase.DOWNLOADING,
            SpeakerModelInstallPhase.VERIFYING,
            SpeakerModelInstallPhase.INSTALLING,
            SpeakerModelInstallPhase.FAILED,
        )
    } ?: SpeakerModelState(SpeakerModelInstallPhase.NOT_INSTALLED)

    private fun update(
        phase: SpeakerModelInstallPhase,
        downloadedBytes: Long = 0,
        totalBytes: Long? = null,
        installedBytes: Long = 0,
        failureCode: String? = null,
    ) {
        mutableState.value = SpeakerModelState(phase, downloadedBytes, totalBytes, installedBytes, failureCode)
    }

    private val archiveFile get() = File(root, "$MODEL_ID.zip.part")
    private val installingDirectory get() = File(root, "$MODEL_ID.installing")
    private val finalDirectory get() = File(root, MODEL_ID)

    companion object {
        private const val MODEL_ID = "vosk-model-spk-0.4"
        private const val DOWNLOAD_URL = "https://alphacephei.com/vosk/models/vosk-model-spk-0.4.zip"
        private const val EXPECTED_ARCHIVE_BYTES = 13_869_103L
        private const val EXPECTED_ARCHIVE_SHA256 = "a74d8f51144484813e16af689bb0f916b7a111e2347f467c4933c1166097b5a7"
        private const val REQUIRED_FREE_BYTES = 80_000_000L
        private const val MAX_ARCHIVE_BYTES = 32_000_000L
        private const val MAX_EXPANDED_BYTES = 64_000_000L
        private const val MAX_FILES = 32
        private const val RECEIPT_NAME = "vox-speaker-model.properties"
        private val REQUIRED_FILES = setOf("mfcc.conf", "final.ext.raw", "mean.vec", "transform.mat")
        @Volatile private var shared: SpeakerModelManager? = null

        fun get(context: Context): SpeakerModelManager = shared ?: synchronized(this) {
            shared ?: SpeakerModelManager(context).also { shared = it }
        }
    }
}

data class SpeakerObservation(
    val text: String,
    val vector: DoubleArray?,
    val frameCount: Int,
    val paragraph: Int,
)

data class SpeakerDiarizationResult(
    val transcript: String,
    val speakerCount: Int,
    val skipReason: String? = null,
)

/** Conservative online clustering over Vosk x-vectors; it never drops recognized text. */
object LocalSpeakerDiarizer {
    fun diarize(observations: List<SpeakerObservation>, fallbackTranscript: String): SpeakerDiarizationResult {
        val usable = observations.mapIndexedNotNull { index, observation ->
            observation.vector?.takeIf { vector ->
                observation.frameCount >= MIN_FRAMES && vector.size >= MIN_VECTOR_SIZE && vector.all(Double::isFinite)
            }?.let { index to it }
        }
        if (usable.isEmpty()) {
            return SpeakerDiarizationResult(
                transcript = fallbackTranscript,
                speakerCount = 0,
                skipReason = "Speaker evidence was too short or unavailable, so the normal transcript was preserved.",
            )
        }

        val centroids = mutableListOf<DoubleArray>()
        val counts = mutableListOf<Int>()
        val assignments = arrayOfNulls<Int>(observations.size)
        usable.forEach { (index, vector) ->
            val nearest = centroids.indices.minByOrNull { cosineDistance(centroids[it], vector) }
            val speaker = if (
                nearest != null && (centroids.size >= MAX_SPEAKERS || cosineDistance(centroids[nearest], vector) <= MAX_SAME_SPEAKER_DISTANCE)
            ) nearest else centroids.size
            if (speaker == centroids.size) {
                centroids += vector.copyOf()
                counts += 1
            } else {
                val nextCount = counts[speaker] + 1
                centroids[speaker].indices.forEach { component ->
                    centroids[speaker][component] += (vector[component] - centroids[speaker][component]) / nextCount
                }
                counts[speaker] = nextCount
            }
            assignments[index] = speaker
        }

        observations.indices.forEach { index ->
            if (assignments[index] == null) {
                assignments[index] = (index - 1 downTo 0).firstNotNullOfOrNull { assignments[it] }
                    ?: (index + 1 until observations.size).firstNotNullOfOrNull { assignments[it] }
                    ?: 0
            }
        }
        val rendered = mutableListOf<RenderedSpeakerTurn>()
        observations.forEachIndexed { index, observation ->
            val speaker = requireNotNull(assignments[index])
            val previous = rendered.lastOrNull()
            if (previous != null && previous.speaker == speaker && previous.paragraph == observation.paragraph) {
                rendered[rendered.lastIndex] = previous.copy(text = "${previous.text} ${observation.text}".trim())
            } else {
                rendered += RenderedSpeakerTurn(speaker, observation.paragraph, observation.text.trim())
            }
        }
        val transcript = rendered.joinToString("\n\n") { "Speaker ${it.speaker + 1}: ${it.text}" }.trim()
        return SpeakerDiarizationResult(
            transcript = transcript.ifBlank { fallbackTranscript },
            speakerCount = centroids.size.coerceAtLeast(1),
        )
    }

    private data class RenderedSpeakerTurn(val speaker: Int, val paragraph: Int, val text: String)

    private fun cosineDistance(left: DoubleArray, right: DoubleArray): Double {
        if (left.size != right.size || left.isEmpty()) return 1.0
        var dot = 0.0
        var leftMagnitude = 0.0
        var rightMagnitude = 0.0
        left.indices.forEach { index ->
            dot += left[index] * right[index]
            leftMagnitude += left[index] * left[index]
            rightMagnitude += right[index] * right[index]
        }
        if (leftMagnitude == 0.0 || rightMagnitude == 0.0) return 1.0
        return 1.0 - dot / kotlin.math.sqrt(leftMagnitude * rightMagnitude)
    }

    private const val MIN_FRAMES = 100
    private const val MIN_VECTOR_SIZE = 16
    private const val MAX_SPEAKERS = 8
    private const val MAX_SAME_SPEAKER_DISTANCE = 0.45
}

private fun AtomicFile.writeSpeakerReceipt(value: String) {
    val output = startWrite()
    try {
        output.write(value.toByteArray(StandardCharsets.UTF_8))
        output.flush()
        output.fd.sync()
        finishWrite(output)
    } catch (error: Throwable) {
        failWrite(output)
        throw error
    }
}

private fun File.speakerDirectorySize(): Long = walkTopDown().filter(File::isFile).sumOf(File::length)

private fun speakerSha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(128 * 1_024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(it) }
}

private fun speakerModelFailureCode(error: Throwable): String = when (val message = error.message.orEmpty()) {
    "insufficientStorage" -> message
    "invalidModelArchive", "invalidModelChecksum" -> "invalidModel"
    "modelArchiveTooLarge", "modelExpandedTooLarge", "modelArchiveFileLimit" -> "modelTooLarge"
    "unsafeModelArchivePath" -> "unsafeArchive"
    else -> if (message.startsWith("downloadHttp")) message else "modelInstallFailed"
}
