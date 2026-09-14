package md.vox.android.platformservices

import android.app.ActivityManager
import android.content.Context
import android.util.AtomicFile
import java.io.BufferedInputStream
import java.io.File
import java.io.FileOutputStream
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Locale
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.ZipInputStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import com.k2fsa.sherpa.onnx.OfflineModelConfig
import com.k2fsa.sherpa.onnx.OfflineRecognizer
import com.k2fsa.sherpa.onnx.OfflineRecognizerConfig
import com.k2fsa.sherpa.onnx.OfflineTransducerModelConfig
import com.k2fsa.sherpa.onnx.OfflineWhisperModelConfig
import md.vox.android.capturedomain.LocalCaptureTextProcessor
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.SpeakerModel

/** A model download is always an explicit user action and never carries capture content. */
data class SpeechModelDescriptor(
    val id: String,
    val displayName: String,
    val languageTag: String,
    val archiveName: String,
    val approximateBytes: Long,
    val engine: SpeechModelEngine = SpeechModelEngine.VOSK,
    val remoteFiles: List<SpeechModelRemoteFile> = emptyList(),
    val modelStem: String? = null,
    val modelDescription: String? = null,
    val isMultilingual: Boolean = false,
    val automaticRank: Int = 100,
    val minimumMemoryBytes: Long = 0,
    val bundledByDefault: Boolean = false,
    val licenseName: String = "Apache 2.0",
    val licenseUrl: String = "https://alphacephei.com/vosk/",
) {
    val downloadUrl: String get() = "https://alphacephei.com/vosk/models/$archiveName.zip"

    fun supports(language: String): Boolean {
        if (isMultilingual) return true
        val normalized = language.replace('_', '-').lowercase(Locale.ROOT)
        val modelLanguage = languageTag.replace('_', '-').lowercase(Locale.ROOT)
        return modelLanguage == normalized || modelLanguage.substringBefore('-') == normalized.substringBefore('-')
    }
}

object SpeechModelCatalog {
    val models: List<SpeechModelDescriptor> = SherpaSpeechModelCatalog.models + listOf(
        SpeechModelDescriptor("vosk-small-en-us-0.15", "English (US)", "en-US", "vosk-model-small-en-us-0.15", 40_000_000),
        SpeechModelDescriptor("vosk-small-cn-0.22", "Chinese (Simplified)", "zh-CN", "vosk-model-small-cn-0.22", 42_000_000),
        SpeechModelDescriptor("vosk-small-de-0.15", "German", "de-DE", "vosk-model-small-de-0.15", 45_000_000),
        SpeechModelDescriptor("vosk-small-es-0.42", "Spanish", "es-ES", "vosk-model-small-es-0.42", 39_000_000),
        SpeechModelDescriptor("vosk-small-fr-0.22", "French", "fr-FR", "vosk-model-small-fr-0.22", 41_000_000),
        SpeechModelDescriptor("vosk-small-hi-0.22", "Hindi", "hi-IN", "vosk-model-small-hi-0.22", 42_000_000),
        SpeechModelDescriptor("vosk-small-it-0.22", "Italian", "it-IT", "vosk-model-small-it-0.22", 48_000_000),
        SpeechModelDescriptor("vosk-small-ja-0.22", "Japanese", "ja-JP", "vosk-model-small-ja-0.22", 48_000_000),
        SpeechModelDescriptor("vosk-small-ko-0.22", "Korean", "ko-KR", "vosk-model-small-ko-0.22", 82_000_000),
        SpeechModelDescriptor("vosk-small-nl-0.22", "Dutch", "nl-NL", "vosk-model-small-nl-0.22", 39_000_000),
        SpeechModelDescriptor("vosk-small-pt-0.3", "Portuguese", "pt-PT", "vosk-model-small-pt-0.3", 31_000_000),
        SpeechModelDescriptor("vosk-small-ru-0.22", "Russian", "ru-RU", "vosk-model-small-ru-0.22", 45_000_000),
        SpeechModelDescriptor("vosk-small-tr-0.3", "Turkish", "tr-TR", "vosk-model-small-tr-0.3", 35_000_000),
        SpeechModelDescriptor("vosk-small-uk-v3-nano", "Ukrainian", "uk-UA", "vosk-model-small-uk-v3-nano", 73_000_000),
        SpeechModelDescriptor("vosk-small-vn-0.4", "Vietnamese", "vi-VN", "vosk-model-small-vn-0.4", 32_000_000),
    )

    fun find(id: String): SpeechModelDescriptor? = models.firstOrNull { it.id == id }
}

enum class SpeechModelInstallPhase { NOT_INSTALLED, DOWNLOADING, VERIFYING, INSTALLING, READY, FAILED }

enum class SpeechModelSelectionMode { AUTOMATIC, MANUAL }

data class SpeechModelInstallState(
    val descriptor: SpeechModelDescriptor,
    val phase: SpeechModelInstallPhase,
    val downloadedBytes: Long = 0,
    val totalBytes: Long? = null,
    val installedBytes: Long = 0,
    val failureCode: String? = null,
) {
    val progress: Float?
        get() = totalBytes?.takeIf { it > 0 }?.let { (downloadedBytes.toDouble() / it).coerceIn(0.0, 1.0).toFloat() }
}

data class SpeechModelManagerState(
    val models: List<SpeechModelInstallState>,
    val selectedModelID: String?,
    val selectionMode: SpeechModelSelectionMode,
) {
    val selectedReadyModel: SpeechModelInstallState?
        get() = models.firstOrNull { it.descriptor.id == selectedModelID && it.phase == SpeechModelInstallPhase.READY }
}

internal fun automaticSpeechModelID(
    models: List<SpeechModelInstallState>,
    preferredLanguageTag: String,
): String? {
    val ready = models.filter { it.phase == SpeechModelInstallPhase.READY }
    val normalizedTag = preferredLanguageTag.replace('_', '-').lowercase(Locale.ROOT)
    val preferredLanguage = normalizedTag.substringBefore('-')
    return ready.filter {
        !it.descriptor.isMultilingual &&
            it.descriptor.languageTag.replace('_', '-').lowercase(Locale.ROOT) == normalizedTag
    }
        .maxByOrNull { it.descriptor.automaticRank }
        ?.descriptor?.id
        ?: ready.filter {
            !it.descriptor.isMultilingual &&
                it.descriptor.languageTag.substringBefore('-').lowercase(Locale.ROOT) == preferredLanguage
        }
        .maxByOrNull { it.descriptor.automaticRank }
        ?.descriptor?.id
        ?: ready.filter { it.descriptor.isMultilingual }
            .maxByOrNull { it.descriptor.automaticRank }
            ?.descriptor?.id
        ?: ready.filter { it.descriptor.supports("en-US") }
            .maxByOrNull { it.descriptor.automaticRank }
            ?.descriptor?.id
        ?: ready.maxByOrNull { it.descriptor.automaticRank }?.descriptor?.id
}

class SpeechModelManager private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val root = File(appContext.noBackupFilesDir, "speech-models-v1").apply { mkdirs() }
    private val preferences = appContext.getSharedPreferences("vox-local-speech-v1", Context.MODE_PRIVATE)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val jobs = ConcurrentHashMap<String, Job>()
    private val mutableState = MutableStateFlow(buildState(emptyMap()))
    val state: StateFlow<SpeechModelManagerState> = mutableState.asStateFlow()

    init {
        SpeechModelCatalog.models.firstOrNull(SpeechModelDescriptor::bundledByDefault)?.let { descriptor ->
            install(descriptor.id)
        }
    }

    fun refresh() {
        mutableState.value = snapshot()
    }

    fun install(descriptorID: String) {
        val descriptor = SpeechModelCatalog.find(descriptorID) ?: return
        if (jobs[descriptorID]?.isActive == true || installedDirectory(descriptorID) != null) return
        val job = scope.launch {
            try {
                if (!installBundledModelIfAvailable(descriptor)) {
                    downloadAndInstall(descriptor)
                }
            } catch (cancelled: CancellationException) {
                update(descriptor, SpeechModelInstallPhase.NOT_INSTALLED)
                throw cancelled
            } catch (error: Throwable) {
                if (descriptor.remoteFiles.isEmpty()) cleanupInstalling(descriptor.id)
                update(descriptor, SpeechModelInstallPhase.FAILED, failureCode = modelFailureCode(error))
            } finally {
                jobs.remove(descriptorID)
            }
        }
        jobs[descriptorID] = job
    }

    fun installImportedZip(descriptorID: String, input: InputStream) {
        val descriptor = SpeechModelCatalog.find(descriptorID) ?: return
        if (descriptor.engine != SpeechModelEngine.VOSK) {
            runCatching { input.close() }
            return
        }
        if (jobs[descriptorID]?.isActive == true || installedDirectory(descriptorID) != null) return
        val job = scope.launch {
            val archive = archiveFile(descriptor.id)
            try {
                update(descriptor, SpeechModelInstallPhase.DOWNLOADING, totalBytes = null)
                copyBounded(input, archive, descriptor)
                installArchive(descriptor, archive)
            } catch (cancelled: CancellationException) {
                archive.delete()
                cleanupInstalling(descriptor.id)
                update(descriptor, SpeechModelInstallPhase.NOT_INSTALLED)
                throw cancelled
            } catch (error: Throwable) {
                archive.delete()
                cleanupInstalling(descriptor.id)
                update(descriptor, SpeechModelInstallPhase.FAILED, failureCode = modelFailureCode(error))
            } finally {
                runCatching { input.close() }
                jobs.remove(descriptorID)
            }
        }
        jobs[descriptorID] = job
    }

    fun cancel(descriptorID: String) {
        jobs.remove(descriptorID)?.cancel()
    }

    fun select(descriptorID: String): Boolean {
        if (installedDirectory(descriptorID) == null) return false
        if (!preferences.edit()
                .putString(KEY_SELECTED_MODEL, descriptorID)
                .putString(KEY_SELECTION_MODE, SpeechModelSelectionMode.MANUAL.name)
                .commit()
        ) return false
        refresh()
        return true
    }

    fun selectAutomatic(): Boolean {
        if (!preferences.edit().putString(KEY_SELECTION_MODE, SpeechModelSelectionMode.AUTOMATIC.name).commit()) return false
        refresh()
        return true
    }

    fun delete(descriptorID: String): Boolean {
        if (jobs[descriptorID]?.isActive == true) return false
        if (SpeechModelCatalog.find(descriptorID)?.bundledByDefault == true) return false
        val directory = installedDirectory(descriptorID) ?: return false
        if (!directory.deleteRecursively()) return false
        archiveFile(descriptorID).delete()
        cleanupInstalling(descriptorID)
        if (preferences.getString(KEY_SELECTED_MODEL, null) == descriptorID) {
            preferences.edit()
                .remove(KEY_SELECTED_MODEL)
                .putString(KEY_SELECTION_MODE, SpeechModelSelectionMode.AUTOMATIC.name)
                .commit()
        }
        refresh()
        return true
    }

    fun selectedModelDirectory(): File? = state.value.selectedReadyModel?.descriptor?.id?.let(::installedDirectory)

    fun selectedModelID(): String? = state.value.selectedReadyModel?.descriptor?.id

    /**
     * Install-time AI packs are exposed through AssetManager, while Sherpa requires ordinary
     * filesystem paths. Materialize the bundled default once into private no-backup storage,
     * verifying every pinned file before the directory becomes visible to selection/inference.
     */
    private suspend fun installBundledModelIfAvailable(descriptor: SpeechModelDescriptor): Boolean {
        if (!descriptor.bundledByDefault || descriptor.remoteFiles.isEmpty()) return false
        val assetRoot = "$BUNDLED_ASSET_ROOT/${descriptor.id}"
        val firstAsset = "$assetRoot/${descriptor.remoteFiles.first().relativePath}"
        val bundled = runCatching { appContext.assets.open(firstAsset).use { } }.isSuccess
        if (!bundled) return false

        val final = File(root, descriptor.id)
        if (final.exists()) check(final.deleteRecursively()) { "modelInstallDirectory" }
        val expectedTotal = descriptor.remoteFiles.sumOf(SpeechModelRemoteFile::expectedBytes)
        val storageHeadroom = maxOf(expectedTotal / 10L, MINIMUM_STORAGE_HEADROOM_BYTES)
        check(root.usableSpace >= expectedTotal + storageHeadroom) { "insufficientStorage" }
        val staging = File(root, "${descriptor.id}.installing")
        cleanupInstalling(descriptor.id)
        check(staging.mkdirs() || staging.isDirectory) { "modelStagingDirectory" }
        try {
            update(
                descriptor,
                SpeechModelInstallPhase.INSTALLING,
                totalBytes = expectedTotal,
            )
            installBundledSpeechModelFiles(
                descriptor = descriptor,
                staging = staging,
                openAsset = { relativePath -> appContext.assets.open("$assetRoot/$relativePath") },
                onProgress = { copied ->
                    update(
                        descriptor,
                        SpeechModelInstallPhase.INSTALLING,
                        downloadedBytes = copied,
                        totalBytes = expectedTotal,
                    )
                },
            )
            Files.move(staging.toPath(), final.toPath(), StandardCopyOption.ATOMIC_MOVE)
            update(
                descriptor,
                SpeechModelInstallPhase.READY,
                downloadedBytes = expectedTotal,
                totalBytes = expectedTotal,
                installedBytes = final.directorySize(),
            )
            refresh()
            return true
        } catch (error: Throwable) {
            staging.deleteRecursively()
            throw error
        }
    }

    private suspend fun downloadAndInstall(descriptor: SpeechModelDescriptor) {
        val memoryInfo = ActivityManager.MemoryInfo()
        (appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memoryInfo)
        check(isSpeechModelSupportedByMemory(descriptor, memoryInfo.totalMem)) { "insufficientDeviceMemory" }
        if (descriptor.remoteFiles.isNotEmpty()) {
            downloadAndInstallRemoteFiles(descriptor)
            return
        }
        check(root.usableSpace >= descriptor.approximateBytes * 5L) { "insufficientStorage" }
        val archive = archiveFile(descriptor.id)
        val existing = archive.length().coerceAtLeast(0)
        val connection = (URL(descriptor.downloadUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 30_000
            instanceFollowRedirects = false
            setRequestProperty("Accept-Encoding", "identity")
            if (existing > 0) setRequestProperty("Range", "bytes=$existing-")
        }
        try {
            connection.connect()
            val code = connection.responseCode
            if (code == 416 &&
                existing > 0 && connection.getHeaderField("Content-Range")?.substringAfterLast('/')?.toLongOrNull() == existing
            ) {
                update(descriptor, SpeechModelInstallPhase.DOWNLOADING, existing, existing)
                return installArchive(descriptor, archive)
            }
            check(code == HttpURLConnection.HTTP_OK || code == HttpURLConnection.HTTP_PARTIAL) { "downloadHttp$code" }
            val append = code == HttpURLConnection.HTTP_PARTIAL && existing > 0
            val downloaded = if (append) existing else 0L
            val announced = connection.contentLengthLong.takeIf { it > 0 }
            val total = announced?.plus(downloaded)
            check(total == null || total <= MAX_ARCHIVE_BYTES) { "modelArchiveTooLarge" }
            update(descriptor, SpeechModelInstallPhase.DOWNLOADING, downloaded, total)
            BufferedInputStream(connection.inputStream).use { input ->
                FileOutputStream(archive, append).use { output ->
                    val buffer = ByteArray(128 * 1_024)
                    var written = downloaded
                    var lastPublished = written
                    while (true) {
                        kotlinx.coroutines.currentCoroutineContext().ensureActive()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        written += count
                        check(written <= MAX_ARCHIVE_BYTES) { "modelArchiveTooLarge" }
                        if (written - lastPublished >= 512 * 1_024) {
                            update(descriptor, SpeechModelInstallPhase.DOWNLOADING, written, total)
                            lastPublished = written
                        }
                    }
                    output.flush()
                    output.fd.sync()
                    update(descriptor, SpeechModelInstallPhase.DOWNLOADING, written, total ?: written)
                }
            }
        } finally {
            connection.disconnect()
        }
        installArchive(descriptor, archive)
    }

    private suspend fun downloadAndInstallRemoteFiles(descriptor: SpeechModelDescriptor) {
        val expectedTotal = descriptor.remoteFiles.sumOf(SpeechModelRemoteFile::expectedBytes)
        check(expectedTotal == descriptor.approximateBytes && expectedTotal > 0) { "invalidModelManifest" }
        val storageHeadroom = maxOf(expectedTotal / 10L, MINIMUM_STORAGE_HEADROOM_BYTES)
        check(root.usableSpace >= expectedTotal + storageHeadroom) { "insufficientStorage" }
        val staging = File(root, "${descriptor.id}.installing")
        check(staging.mkdirs() || staging.isDirectory) { "modelStagingDirectory" }
        val canonicalStaging = staging.canonicalFile
        var completedBytes = 0L

        descriptor.remoteFiles.forEach { artifact ->
            val target = safeModelArchiveTarget(canonicalStaging, artifact.relativePath)
            val partial = File(target.parentFile, "${target.name}.part")
            if (target.exists() && !isRemoteModelFileValid(target, artifact)) {
                check(target.delete()) { "invalidModelArtifact" }
            }
            if (target.isFile) {
                partial.delete()
                completedBytes += artifact.expectedBytes
                update(descriptor, SpeechModelInstallPhase.DOWNLOADING, completedBytes, expectedTotal)
                return@forEach
            }
            val parent = target.parentFile
            check(parent != null && (parent.mkdirs() || parent.isDirectory)) { "modelDirectoryCreate" }
            if (partial.length() > artifact.expectedBytes) partial.delete()
            downloadRemoteModelFile(
                descriptor = descriptor,
                artifact = artifact,
                partial = partial,
                completedBefore = completedBytes,
                expectedTotal = expectedTotal,
            )
            update(
                descriptor,
                SpeechModelInstallPhase.VERIFYING,
                completedBytes + partial.length(),
                expectedTotal,
            )
            if (!isRemoteModelFileValid(partial, artifact)) {
                partial.delete()
                error("modelChecksumMismatch")
            }
            Files.move(
                partial.toPath(),
                target.toPath(),
                StandardCopyOption.ATOMIC_MOVE,
            )
            completedBytes += artifact.expectedBytes
            update(descriptor, SpeechModelInstallPhase.DOWNLOADING, completedBytes, expectedTotal)
        }

        update(descriptor, SpeechModelInstallPhase.VERIFYING, expectedTotal, expectedTotal)
        check(descriptor.remoteFiles.all { artifact ->
            isRemoteModelFileValid(File(staging, artifact.relativePath), artifact)
        }) { "invalidModelArtifact" }
        AtomicFile(File(staging, RECEIPT_NAME)).writeText(remoteModelReceipt(descriptor))
        update(descriptor, SpeechModelInstallPhase.INSTALLING, expectedTotal, expectedTotal)
        val final = File(root, descriptor.id)
        check(!final.exists()) { "modelAlreadyInstalled" }
        Files.move(staging.toPath(), final.toPath(), StandardCopyOption.ATOMIC_MOVE)
        update(descriptor, SpeechModelInstallPhase.READY, installedBytes = final.directorySize())
        refresh()
    }

    private suspend fun downloadRemoteModelFile(
        descriptor: SpeechModelDescriptor,
        artifact: SpeechModelRemoteFile,
        partial: File,
        completedBefore: Long,
        expectedTotal: Long,
    ) {
        val existing = partial.length().coerceAtLeast(0)
        if (existing == artifact.expectedBytes) return
        val connection = (URL(artifact.downloadUrl).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 30_000
            instanceFollowRedirects = true
            setRequestProperty("Accept-Encoding", "identity")
            setRequestProperty("User-Agent", "Vox.md Android model manager")
            if (existing > 0) setRequestProperty("Range", "bytes=$existing-")
        }
        try {
            connection.connect()
            val code = connection.responseCode
            if (code == 416 && existing == artifact.expectedBytes) {
                return
            }
            check(code == HttpURLConnection.HTTP_OK || code == HttpURLConnection.HTTP_PARTIAL) { "downloadHttp$code" }
            val append = code == HttpURLConnection.HTTP_PARTIAL && existing > 0
            if (append) {
                val rangeStart = connection.getHeaderField("Content-Range")
                    ?.substringAfter("bytes ")
                    ?.substringBefore('-')
                    ?.toLongOrNull()
                check(rangeStart == existing) { "invalidDownloadRange" }
            }
            val writtenBefore = if (append) existing else 0L
            val announced = connection.contentLengthLong.takeIf { it >= 0 }
            check(announced == null || announced + writtenBefore == artifact.expectedBytes) { "invalidModelArtifactSize" }
            update(
                descriptor,
                SpeechModelInstallPhase.DOWNLOADING,
                completedBefore + writtenBefore,
                expectedTotal,
            )
            BufferedInputStream(connection.inputStream).use { input ->
                FileOutputStream(partial, append).use { output ->
                    val buffer = ByteArray(128 * 1_024)
                    var written = writtenBefore
                    var lastPublished = written
                    while (true) {
                        kotlinx.coroutines.currentCoroutineContext().ensureActive()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        written += count
                        check(written <= artifact.expectedBytes) { "invalidModelArtifactSize" }
                        if (written - lastPublished >= 512 * 1_024) {
                            update(
                                descriptor,
                                SpeechModelInstallPhase.DOWNLOADING,
                                completedBefore + written,
                                expectedTotal,
                            )
                            lastPublished = written
                        }
                    }
                    output.flush()
                    output.fd.sync()
                }
            }
            check(partial.length() == artifact.expectedBytes) { "invalidModelArtifactSize" }
        } finally {
            connection.disconnect()
        }
    }

    private fun isRemoteModelFileValid(file: File, artifact: SpeechModelRemoteFile): Boolean =
        file.isFile &&
            !Files.isSymbolicLink(file.toPath()) &&
            file.length() == artifact.expectedBytes &&
            sha256(file) == artifact.sha256

    private fun remoteModelReceipt(descriptor: SpeechModelDescriptor): String {
        return "version=2\n" +
            "id=${descriptor.id}\n" +
            "engine=${descriptor.engine.name}\n" +
            "manifestSha256=${remoteSpeechModelManifestSha256(descriptor)}\n"
    }

    private suspend fun copyBounded(input: InputStream, archive: File, descriptor: SpeechModelDescriptor) {
        check(root.usableSpace >= descriptor.approximateBytes * 5L) { "insufficientStorage" }
        FileOutputStream(archive, false).use { output ->
            val buffer = ByteArray(128 * 1_024)
            var written = 0L
            while (true) {
                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                val count = input.read(buffer)
                if (count < 0) break
                output.write(buffer, 0, count)
                written += count
                check(written <= MAX_ARCHIVE_BYTES) { "modelArchiveTooLarge" }
                update(descriptor, SpeechModelInstallPhase.DOWNLOADING, written, null)
            }
            output.flush()
            output.fd.sync()
        }
    }

    private suspend fun installArchive(descriptor: SpeechModelDescriptor, archive: File) {
        check(archive.isFile && archive.length() > 0) { "emptyModelArchive" }
        update(descriptor, SpeechModelInstallPhase.VERIFYING, archive.length(), archive.length())
        val sha256 = sha256(archive)
        val staging = File(root, "${descriptor.id}.installing")
        cleanupInstalling(descriptor.id)
        check(staging.mkdir()) { "modelStagingDirectory" }
        try {
            update(descriptor, SpeechModelInstallPhase.INSTALLING, archive.length(), archive.length())
            unzipSafely(archive, staging)
            val extractedRoot = normalizedModelRoot(staging)
            check(File(extractedRoot, "conf/model.conf").isFile) { "invalidModelConfiguration" }
            check(File(extractedRoot, "am/final.mdl").isFile) { "invalidModelAcousticData" }
            val receipt = File(extractedRoot, RECEIPT_NAME)
            AtomicFile(receipt).writeText(
                "version=1\n" +
                    "id=${descriptor.id}\n" +
                    "languageTag=${descriptor.languageTag}\n" +
                    "archiveBytes=${archive.length()}\n" +
                    "archiveSha256=$sha256\n",
            )
            val final = File(root, descriptor.id)
            check(!final.exists()) { "modelAlreadyInstalled" }
            Files.move(extractedRoot.toPath(), final.toPath(), StandardCopyOption.ATOMIC_MOVE)
            if (extractedRoot != staging) staging.deleteRecursively()
            archive.delete()
            if (selectionMode() == SpeechModelSelectionMode.MANUAL && preferences.getString(KEY_SELECTED_MODEL, null) == null) {
                preferences.edit().putString(KEY_SELECTED_MODEL, descriptor.id).commit()
            }
            update(descriptor, SpeechModelInstallPhase.READY, installedBytes = final.directorySize())
            refresh()
        } catch (error: Throwable) {
            staging.deleteRecursively()
            throw error
        }
    }

    private suspend fun unzipSafely(archive: File, staging: File) {
        val canonicalRoot = staging.canonicalFile
        var fileCount = 0
        var extractedBytes = 0L
        ZipInputStream(BufferedInputStream(archive.inputStream())).use { zip ->
            while (true) {
                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                val entry = zip.nextEntry ?: break
                fileCount += 1
                check(fileCount <= MAX_MODEL_FILES) { "modelArchiveFileLimit" }
                val target = safeModelArchiveTarget(canonicalRoot, entry.name)
                if (entry.isDirectory) {
                    check(target.mkdirs() || target.isDirectory) { "modelDirectoryCreate" }
                } else {
                    val parent = target.parentFile
                    check(parent != null && (parent.mkdirs() || parent.isDirectory)) { "modelDirectoryCreate" }
                    FileOutputStream(target).use { output ->
                        val buffer = ByteArray(128 * 1_024)
                        while (true) {
                            val count = zip.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                            extractedBytes += count
                            check(extractedBytes <= MAX_EXTRACTED_BYTES) { "modelExpandedTooLarge" }
                        }
                        output.flush()
                        output.fd.sync()
                    }
                }
                zip.closeEntry()
            }
        }
    }

    private fun normalizedModelRoot(staging: File): File {
        val children = staging.listFiles().orEmpty().filterNot { it.name == ".DS_Store" }
        return if (children.size == 1 && children.single().isDirectory) children.single() else staging
    }

    private fun installedDirectory(id: String): File? {
        if (!SAFE_ID.matches(id)) return null
        val descriptor = SpeechModelCatalog.find(id) ?: return null
        val directory = File(root, id)
        return directory.takeIf { isInstalledSpeechModelDirectory(descriptor, it) }
    }

    private fun archiveFile(id: String): File = File(root, "$id.zip.part")

    private fun cleanupInstalling(id: String) {
        File(root, "$id.installing").deleteRecursively()
    }

    private fun snapshot(): SpeechModelManagerState = buildState(mutableState.value.models.associateBy { it.descriptor.id })

    private fun buildState(present: Map<String, SpeechModelInstallState>): SpeechModelManagerState {
        val models = SpeechModelCatalog.models.map { descriptor ->
                val ready = installedDirectory(descriptor.id)
                if (ready != null) {
                    SpeechModelInstallState(descriptor, SpeechModelInstallPhase.READY, installedBytes = ready.directorySize())
                } else {
                    present[descriptor.id]?.takeIf {
                        it.phase in setOf(
                            SpeechModelInstallPhase.DOWNLOADING,
                            SpeechModelInstallPhase.VERIFYING,
                            SpeechModelInstallPhase.INSTALLING,
                            SpeechModelInstallPhase.FAILED,
                        )
                    } ?: SpeechModelInstallState(descriptor, SpeechModelInstallPhase.NOT_INSTALLED)
                }
            }
        val mode = selectionMode()
        val selected = when (mode) {
            SpeechModelSelectionMode.AUTOMATIC -> automaticSpeechModelID(models, Locale.getDefault().toLanguageTag())
            SpeechModelSelectionMode.MANUAL -> preferences.getString(KEY_SELECTED_MODEL, null)
                ?.takeIf { id -> models.any { it.descriptor.id == id && it.phase == SpeechModelInstallPhase.READY } }
        }
        return SpeechModelManagerState(
            models = models,
            selectedModelID = selected,
            selectionMode = mode,
        )
    }

    private fun selectionMode(): SpeechModelSelectionMode {
        val stored = preferences.getString(KEY_SELECTION_MODE, null)
        return runCatching { stored?.let(SpeechModelSelectionMode::valueOf) }.getOrNull()
            ?: if (preferences.contains(KEY_SELECTED_MODEL)) SpeechModelSelectionMode.MANUAL else SpeechModelSelectionMode.AUTOMATIC
    }

    private fun update(
        descriptor: SpeechModelDescriptor,
        phase: SpeechModelInstallPhase,
        downloadedBytes: Long = 0,
        totalBytes: Long? = null,
        installedBytes: Long = 0,
        failureCode: String? = null,
    ) {
        mutableState.update { state ->
            state.copy(
                models = state.models.map {
                    if (it.descriptor.id == descriptor.id) {
                        SpeechModelInstallState(descriptor, phase, downloadedBytes, totalBytes, installedBytes, failureCode)
                    } else it
                },
            )
        }
    }

    companion object {
        @Volatile private var shared: SpeechModelManager? = null

        fun get(context: Context): SpeechModelManager = shared ?: synchronized(this) {
            shared ?: SpeechModelManager(context).also { shared = it }
        }

        private const val KEY_SELECTED_MODEL = "selected-model-id"
        private const val KEY_SELECTION_MODE = "selection-mode"
        private const val RECEIPT_NAME = "vox-model.properties"
        private const val MAX_ARCHIVE_BYTES = 1_000_000_000L
        private const val MAX_EXTRACTED_BYTES = 2_000_000_000L
        private const val MAX_MODEL_FILES = 20_000
        private const val MINIMUM_STORAGE_HEADROOM_BYTES = 128L * 1_024 * 1_024
        private const val BUNDLED_ASSET_ROOT = "speech-models"
        private val SAFE_ID = Regex("^[a-z0-9][a-z0-9.-]{1,79}$")
    }
}

internal suspend fun installBundledSpeechModelFiles(
    descriptor: SpeechModelDescriptor,
    staging: File,
    openAsset: (String) -> InputStream,
    onProgress: (Long) -> Unit = {},
) {
    check(descriptor.remoteFiles.isNotEmpty()) { "invalidModelManifest" }
    val canonicalStaging = staging.canonicalFile
    check(canonicalStaging.mkdirs() || canonicalStaging.isDirectory) { "modelStagingDirectory" }
    var totalCopied = 0L
    var lastPublished = 0L
    descriptor.remoteFiles.forEach { artifact ->
        val target = safeModelArchiveTarget(canonicalStaging, artifact.relativePath)
        check(target.parentFile?.let { it.mkdirs() || it.isDirectory } == true) { "modelDirectoryCreate" }
        val digest = MessageDigest.getInstance("SHA-256")
        var fileBytes = 0L
        openAsset(artifact.relativePath).buffered().use { input ->
            FileOutputStream(target, false).use { output ->
                val buffer = ByteArray(128 * 1_024)
                while (true) {
                    kotlinx.coroutines.currentCoroutineContext().ensureActive()
                    val count = input.read(buffer)
                    if (count < 0) break
                    fileBytes += count
                    check(fileBytes <= artifact.expectedBytes) { "invalidModelArtifactSize" }
                    output.write(buffer, 0, count)
                    digest.update(buffer, 0, count)
                    totalCopied += count
                    if (totalCopied - lastPublished >= 512L * 1_024) {
                        onProgress(totalCopied)
                        lastPublished = totalCopied
                    }
                }
                output.flush()
                output.fd.sync()
            }
        }
        val actualSha256 = digest.digest().joinToString("") { byte ->
            "%02x".format(Locale.ROOT, byte)
        }
        check(fileBytes == artifact.expectedBytes) { "invalidModelArtifactSize" }
        check(actualSha256 == artifact.sha256) { "modelChecksumMismatch" }
    }
    onProgress(totalCopied)
    val receipt = File(canonicalStaging, "vox-model.properties")
    FileOutputStream(receipt, false).use { output ->
        output.write(
            (
                "version=2\n" +
                    "id=${descriptor.id}\n" +
                    "engine=${descriptor.engine.name}\n" +
                    "manifestSha256=${remoteSpeechModelManifestSha256(descriptor)}\n"
            ).toByteArray(StandardCharsets.UTF_8),
        )
        output.flush()
        output.fd.sync()
    }
}

internal fun isInstalledSpeechModelDirectory(descriptor: SpeechModelDescriptor, directory: File): Boolean {
    if (!directory.isDirectory || Files.isSymbolicLink(directory.toPath())) return false
    val receipt = File(directory, "vox-model.properties")
    if (!receipt.isFile || Files.isSymbolicLink(receipt.toPath())) return false
    if (descriptor.engine == SpeechModelEngine.VOSK) {
        return File(directory, "conf/model.conf").isFile && File(directory, "am/final.mdl").isFile
    }
    val receiptText = runCatching { receipt.readText(StandardCharsets.UTF_8) }.getOrNull() ?: return false
    if (!receiptText.lineSequence().any { it == "version=2" } ||
        !receiptText.lineSequence().any { it == "id=${descriptor.id}" } ||
        !receiptText.lineSequence().any { it == "engine=${descriptor.engine.name}" } ||
        !receiptText.lineSequence().any { it == "manifestSha256=${remoteSpeechModelManifestSha256(descriptor)}" }
    ) return false
    return descriptor.remoteFiles.isNotEmpty() && descriptor.remoteFiles.all { artifact ->
        val file = runCatching { safeModelArchiveTarget(directory.canonicalFile, artifact.relativePath) }.getOrNull()
            ?: return@all false
        file.isFile && !Files.isSymbolicLink(file.toPath()) && file.length() == artifact.expectedBytes
    }
}

internal fun remoteSpeechModelManifestSha256(descriptor: SpeechModelDescriptor): String {
    val manifest = descriptor.remoteFiles.joinToString("\n") {
        "${it.relativePath}:${it.expectedBytes}:${it.sha256}"
    }
    return MessageDigest.getInstance("SHA-256")
        .digest(manifest.toByteArray(StandardCharsets.UTF_8))
        .joinToString("") { byte -> "%02x".format(byte) }
}

enum class RecordingTranscriptionPhase(val isTerminal: Boolean = false) {
    QUEUED,
    PROCESSING,
    FINALIZING,
    COMPLETED(isTerminal = true),
    FAILED,
    DISCARDED(isTerminal = true),
}

data class RecordingTranscriptionState(
    val sessionID: String,
    val phase: RecordingTranscriptionPhase = RecordingTranscriptionPhase.QUEUED,
    val progress: Float = 0f,
    val modelID: String? = null,
    val modelName: String? = null,
    val languageTag: String? = null,
    val durationMillis: Long = 0,
    val recordedAtEpochMillis: Long? = null,
    val completedAtEpochMillis: Long? = null,
    val transcript: String? = null,
    val cleanedTranscript: String? = null,
    val failureCode: String? = null,
    val addedToDraft: Boolean = false,
    val title: String? = null,
    val tags: List<String> = emptyList(),
    val category: String? = null,
    val speakerCount: Int = 0,
    val diarizationSkipReason: String? = null,
) {
    val preferredTranscript: String?
        get() = cleanedTranscript?.takeIf(String::isNotBlank) ?: transcript
}

class RecordingTranscriptionClient private constructor(context: Context) {
    private val appContext = context.applicationContext
    private val modelManager = SpeechModelManager.get(appContext)
    private val quotaLedger = TranscriptionQuotaLedger(appContext)
    private val root = File(appContext.noBackupFilesDir, "recordings")
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val jobs = ConcurrentHashMap<String, Job>()
    private val mutableStates = MutableStateFlow(loadStates())
    val states: StateFlow<Map<String, RecordingTranscriptionState>> = mutableStates.asStateFlow()
    val usage: StateFlow<TranscriptionUsageState> = quotaLedger.usage

    init {
        mutableStates.value.values
            .filter { it.phase == RecordingTranscriptionPhase.COMPLETED }
            .forEach { state ->
                recordingDurationMillis(state.sessionID)?.let { quotaLedger.backfill(state.sessionID, it) }
            }
    }

    fun process(sessionID: String) {
        if (!UUID_PATTERN.matches(sessionID) || jobs[sessionID]?.isActive == true) return
        if (mutableStates.value[sessionID]?.phase?.isTerminal == true) return
        val modelID = modelManager.selectedModelID()
        val modelDirectory = modelManager.selectedModelDirectory()
        val descriptor = modelManager.state.value.selectedReadyModel?.descriptor
        if (modelID == null || modelDirectory == null || descriptor == null) {
            persist(RecordingTranscriptionState(sessionID, RecordingTranscriptionPhase.FAILED, failureCode = "modelNotInstalled"))
            return
        }
        val chunks = pcmChunks(sessionID)
        if (chunks.isEmpty()) {
            persist(RecordingTranscriptionState(sessionID, RecordingTranscriptionPhase.FAILED, failureCode = "audioUnavailable"))
            return
        }
        val durationMillis = pcmDurationMillis(chunks)
        val unlimited = UnlimitedAccessRegistry.hasUnlimitedAccess()
        if (!quotaLedger.reserve(sessionID, durationMillis, unlimited)) {
            persist(RecordingTranscriptionState(sessionID, RecordingTranscriptionPhase.FAILED, failureCode = "transcriptionQuotaReached"))
            return
        }
        val job = scope.launch {
            val base = RecordingTranscriptionState(
                sessionID = sessionID,
                phase = RecordingTranscriptionPhase.QUEUED,
                modelID = modelID,
                modelName = descriptor.displayName,
                languageTag = descriptor.languageTag,
                durationMillis = durationMillis,
                recordedAtEpochMillis = recordingCreatedAtEpochMillis(appContext, sessionID),
            )
            persist(base)
            try {
                val diarizationRequested = recordingPreset(sessionID)?.speakerDiarizationEnabled == true
                val transcription = transcribe(
                    base = base,
                    descriptor = descriptor,
                    modelDirectory = modelDirectory,
                    chunks = chunks,
                    diarizationRequested = diarizationRequested,
                    speakerModelDirectory = if (diarizationRequested) SpeakerModelManager.get(appContext).modelDirectory() else null,
                )
                val transcript = transcription.transcript
                val cleanedTranscript = recordingPreset(sessionID)
                    ?.let { preset -> LocalCaptureTextProcessor.process(transcript, preset, isVoiceCapture = true) }
                    ?.processedText
                    ?.takeIf { it.isNotBlank() && it != transcript }
                val metadata = DeterministicTranscriptEnrichment.enrich(cleanedTranscript ?: transcription.plainTranscript)
                val finalizing = base.copy(
                    phase = RecordingTranscriptionPhase.FINALIZING,
                    progress = 1f,
                    transcript = transcript,
                    cleanedTranscript = cleanedTranscript,
                    title = metadata.title,
                    tags = metadata.tags,
                    category = metadata.category,
                    speakerCount = transcription.speakerCount,
                    diarizationSkipReason = transcription.diarizationSkipReason,
                )
                persist(finalizing)
                check(quotaLedger.commit(sessionID)) { "transcriptionQuotaCommit" }
                writeTranscript(sessionID, transcript)
                writeCleanedTranscript(sessionID, cleanedTranscript)
                persist(finalizing.copy(
                    phase = RecordingTranscriptionPhase.COMPLETED,
                    completedAtEpochMillis = System.currentTimeMillis(),
                ))
            } catch (cancelled: CancellationException) {
                quotaLedger.release(sessionID)
                persist(base.copy(phase = RecordingTranscriptionPhase.DISCARDED))
                throw cancelled
            } catch (error: Throwable) {
                quotaLedger.release(sessionID)
                persist(
                    base.copy(
                        phase = RecordingTranscriptionPhase.FAILED,
                        failureCode = transcriptionFailureCode(error),
                    ),
                )
            } finally {
                jobs.remove(sessionID)
            }
        }
        jobs[sessionID] = job
    }

    fun cancel(sessionID: String) {
        jobs.remove(sessionID)?.cancel()
    }

    fun retryAll(sessionIDs: Collection<String>) {
        sessionIDs.forEach(::process)
    }

    /** Reconciles transcript history after another local component has changed its files. */
    fun reload() {
        mutableStates.value = loadStates()
    }

    fun markAddedToDraft(sessionID: String) {
        val present = mutableStates.value[sessionID] ?: return
        if (present.phase == RecordingTranscriptionPhase.COMPLETED) persist(present.copy(addedToDraft = true))
    }

    fun updateTranscript(sessionID: String, transcript: String): Boolean {
        if (!UUID_PATTERN.matches(sessionID)) return false
        val normalized = transcript.trim().take(MAX_TRANSCRIPT_CHARACTERS)
        if (normalized.isBlank()) return false
        val present = mutableStates.value[sessionID]
            ?.takeIf { it.phase == RecordingTranscriptionPhase.COMPLETED }
            ?: return false
        return runCatching {
            writeTranscript(sessionID, normalized)
            persist(present.copy(transcript = normalized))
            true
        }.getOrDefault(false)
    }

    fun updateTranscriptDetails(
        sessionID: String,
        transcript: String,
        cleanedTranscript: String,
        title: String,
        tags: List<String>,
        category: String,
    ): Boolean {
        if (!UUID_PATTERN.matches(sessionID)) return false
        val normalizedTranscript = transcript.trim().take(MAX_TRANSCRIPT_CHARACTERS)
        if (normalizedTranscript.isBlank()) return false
        val normalizedCleanedTranscript = cleanedTranscript.trim().take(MAX_TRANSCRIPT_CHARACTERS)
            .takeIf(String::isNotBlank)
        val present = mutableStates.value[sessionID]
            ?.takeIf { it.phase == RecordingTranscriptionPhase.COMPLETED }
            ?: return false
        val normalizedTags = tags.map(String::trim).filter(String::isNotBlank).distinct().take(20).map { it.take(64) }
        return runCatching {
            writeTranscript(sessionID, normalizedTranscript)
            writeCleanedTranscript(sessionID, normalizedCleanedTranscript)
            persist(
                present.copy(
                    transcript = normalizedTranscript,
                    cleanedTranscript = normalizedCleanedTranscript,
                    title = title.trim().take(128).takeIf(String::isNotBlank),
                    tags = normalizedTags,
                    category = category.trim().take(64).takeIf(String::isNotBlank),
                ),
            )
            true
        }.getOrDefault(false)
    }

    fun clear(sessionID: String) {
        jobs.remove(sessionID)?.cancel()
        transcriptionFile(sessionID).delete()
        transcriptFile(sessionID).delete()
        cleanedTranscriptFile(sessionID).delete()
        mutableStates.update { it - sessionID }
    }

    private suspend fun transcribe(
        base: RecordingTranscriptionState,
        descriptor: SpeechModelDescriptor,
        modelDirectory: File,
        chunks: List<File>,
        diarizationRequested: Boolean,
        speakerModelDirectory: File?,
    ): PrivateTranscriptionResult {
        if (descriptor.engine != SpeechModelEngine.VOSK) {
            return transcribeWithSherpa(
                base = base,
                descriptor = descriptor,
                modelDirectory = modelDirectory,
                chunks = chunks,
                diarizationRequested = diarizationRequested,
            )
        }
        val totalBytes = chunks.sumOf(File::length).coerceAtLeast(1)
        var consumed = 0L
        val paragraphs = mutableListOf<String>()
        val speakerObservations = mutableListOf<SpeakerObservation>()
        val recordingDirectory = chunks.firstOrNull()?.parentFile
        val boundaries = recordingDirectory?.let(RecordingSegmentStore::boundaries).orEmpty()
        val groups = groupRecordingChunks(chunks, boundaries)
        val speakerModel = if (diarizationRequested && speakerModelDirectory != null) {
            runCatching { SpeakerModel(speakerModelDirectory.absolutePath) }.getOrNull()
        } else null
        var speakerRecognizerUnavailable = false
        try {
            Model(modelDirectory.absolutePath).use { model ->
                persist(base.copy(phase = RecordingTranscriptionPhase.PROCESSING))
                groups.forEachIndexed { paragraph, group ->
                    val segmentResults = mutableListOf<String>()
                    val recognizer = if (speakerModel != null) {
                        runCatching { Recognizer(model, SAMPLE_RATE.toFloat(), speakerModel) }.getOrElse {
                            speakerRecognizerUnavailable = true
                            Recognizer(model, SAMPLE_RATE.toFloat())
                        }
                    } else Recognizer(model, SAMPLE_RATE.toFloat())
                    recognizer.use {
                    val buffer = ByteArray(64 * 1_024)
                    group.forEach { chunk ->
                        chunk.inputStream().use { input ->
                            while (true) {
                                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                                val count = input.read(buffer)
                                if (count < 0) break
                                if (recognizer.acceptWaveForm(buffer, count)) {
                                    jsonSpeakerObservation(recognizer.result, paragraph)?.let { observation ->
                                        segmentResults += observation.text
                                        speakerObservations += observation
                                    }
                                }
                                consumed += count
                                persist(
                                    base.copy(
                                        phase = RecordingTranscriptionPhase.PROCESSING,
                                        progress = (consumed.toDouble() / totalBytes).coerceIn(0.0, 1.0).toFloat(),
                                    ),
                                    writeDisk = false,
                                )
                            }
                        }
                    }
                        jsonSpeakerObservation(recognizer.finalResult, paragraph)?.let { observation ->
                            segmentResults += observation.text
                            speakerObservations += observation
                        }
                    }
                    segmentResults.joinToString(" ").trim().takeIf(String::isNotBlank)?.let(paragraphs::add)
                }
            }
        } finally {
            runCatching { speakerModel?.close() }
        }
        val transcript = paragraphs.joinToString("\n\n").trim()
        check(transcript.isNotEmpty()) { "noSpeech" }
        if (!diarizationRequested) return PrivateTranscriptionResult(transcript)
        if (speakerModelDirectory == null) {
            return PrivateTranscriptionResult(
                transcript,
                diarizationSkipReason = "Download the on-device Speaker Identification model to label speakers. The normal transcript was preserved.",
            )
        }
        if (speakerModel == null || speakerRecognizerUnavailable) {
            return PrivateTranscriptionResult(
                transcript,
                diarizationSkipReason = "Speaker identification could not start, so the normal transcript was preserved.",
            )
        }
        val diarized = LocalSpeakerDiarizer.diarize(speakerObservations, transcript)
        return PrivateTranscriptionResult(
            transcript = diarized.transcript,
            speakerCount = diarized.speakerCount,
            diarizationSkipReason = diarized.skipReason,
            plainTranscript = transcript,
        )
    }

    private suspend fun transcribeWithSherpa(
        base: RecordingTranscriptionState,
        descriptor: SpeechModelDescriptor,
        modelDirectory: File,
        chunks: List<File>,
        diarizationRequested: Boolean,
    ): PrivateTranscriptionResult {
        val modelConfig = when (descriptor.engine) {
            SpeechModelEngine.SHERPA_WHISPER -> {
                val stem = descriptor.modelStem ?: error("invalidModelManifest")
                OfflineModelConfig(
                    whisper = OfflineWhisperModelConfig(
                        encoder = File(modelDirectory, "$stem-encoder.int8.onnx").absolutePath,
                        decoder = File(modelDirectory, "$stem-decoder.int8.onnx").absolutePath,
                        language = Locale.getDefault().language.takeIf(String::isNotBlank) ?: "en",
                        task = "transcribe",
                    ),
                    tokens = File(modelDirectory, "$stem-tokens.txt").absolutePath,
                    numThreads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4),
                )
            }
            SpeechModelEngine.SHERPA_PARAKEET -> OfflineModelConfig(
                transducer = OfflineTransducerModelConfig(
                    encoder = File(modelDirectory, "encoder.int8.onnx").absolutePath,
                    decoder = File(modelDirectory, "decoder.int8.onnx").absolutePath,
                    joiner = File(modelDirectory, "joiner.int8.onnx").absolutePath,
                ),
                tokens = File(modelDirectory, "tokens.txt").absolutePath,
                numThreads = Runtime.getRuntime().availableProcessors().coerceIn(1, 4),
                modelType = "nemo_transducer",
            )
            SpeechModelEngine.VOSK -> error("invalidModelEngine")
        }
        val totalBytes = chunks.sumOf(File::length).coerceAtLeast(1)
        var consumedBytes = 0L
        val recordingDirectory = chunks.firstOrNull()?.parentFile
        val boundaries = recordingDirectory?.let(RecordingSegmentStore::boundaries).orEmpty()
        val groups = groupRecordingChunks(chunks, boundaries)
        val paragraphs = mutableListOf<String>()
        val recognizer = OfflineRecognizer(config = OfflineRecognizerConfig(modelConfig = modelConfig))
        try {
            persist(base.copy(phase = RecordingTranscriptionPhase.PROCESSING))
            groups.forEach { group ->
                val stream = recognizer.createStream()
                try {
                    group.forEach { chunk ->
                        check(chunk.length() % 2L == 0L) { "invalidPcmAudio" }
                        chunk.inputStream().buffered().use { input ->
                            val bytes = ByteArray(64 * 1_024)
                            var carriedLowByte: Int? = null
                            while (true) {
                                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                                val count = input.read(bytes)
                                if (count < 0) break
                                val samples = FloatArray((count + if (carriedLowByte == null) 0 else 1) / 2)
                                var byteIndex = 0
                                var sampleIndex = 0
                                carriedLowByte?.let { low ->
                                    if (count > 0) {
                                        val high = bytes[0].toInt() shl 8
                                        samples[sampleIndex++] = (low or high).toShort().toFloat() / 32_768f
                                        byteIndex = 1
                                        carriedLowByte = null
                                    }
                                }
                                while (byteIndex + 1 < count) {
                                    val low = bytes[byteIndex].toInt() and 0xff
                                    val high = bytes[byteIndex + 1].toInt() shl 8
                                    samples[sampleIndex++] = (low or high).toShort().toFloat() / 32_768f
                                    byteIndex += 2
                                }
                                if (byteIndex < count) carriedLowByte = bytes[byteIndex].toInt() and 0xff
                                if (sampleIndex > 0) {
                                    stream.acceptWaveform(
                                        if (sampleIndex == samples.size) samples else samples.copyOf(sampleIndex),
                                        SAMPLE_RATE,
                                    )
                                }
                                consumedBytes += count
                                persist(
                                    base.copy(
                                        phase = RecordingTranscriptionPhase.PROCESSING,
                                        progress = (consumedBytes.toDouble() / totalBytes)
                                            .coerceIn(0.0, 1.0)
                                            .toFloat(),
                                    ),
                                    writeDisk = false,
                                )
                            }
                            check(carriedLowByte == null) { "invalidPcmAudio" }
                        }
                    }
                    recognizer.decode(stream)
                    recognizer.getResult(stream).text.trim().takeIf(String::isNotBlank)?.let(paragraphs::add)
                } finally {
                    stream.release()
                }
            }
        } finally {
            recognizer.release()
        }
        val transcript = paragraphs.joinToString("\n\n").trim()
        check(transcript.isNotEmpty()) { "noSpeech" }
        return PrivateTranscriptionResult(
            transcript = transcript,
            diarizationSkipReason = if (diarizationRequested) {
                "Speaker identification is unavailable for this model, so the normal transcript was preserved."
            } else null,
        )
    }

    private fun pcmChunks(sessionID: String): List<File> {
        val directory = recordingDirectory(sessionID) ?: return emptyList()
        return directory.listFiles().orEmpty()
            .filter { it.isFile && CHUNK_PATTERN.matches(it.name) && !Files.isSymbolicLink(it.toPath()) }
            .sortedBy(File::getName)
    }

    private fun recordingDurationMillis(sessionID: String): Long? {
        val chunks = pcmChunks(sessionID)
        return if (chunks.isEmpty()) null else pcmDurationMillis(chunks)
    }

    private fun pcmDurationMillis(chunks: List<File>): Long {
        val bytes = chunks.sumOf(File::length).coerceAtLeast(1)
        return ((bytes * 1_000L) + PCM_BYTES_PER_SECOND - 1) / PCM_BYTES_PER_SECOND
    }

    private fun recordingDirectory(sessionID: String): File? {
        if (!UUID_PATTERN.matches(sessionID)) return null
        val expected = runCatching { root.canonicalFile }.getOrNull() ?: return null
        val directory = runCatching { File(root, sessionID).canonicalFile }.getOrNull() ?: return null
        return directory.takeIf { it.parentFile == expected && it.isDirectory && !Files.isSymbolicLink(it.toPath()) }
    }

    private fun persist(state: RecordingTranscriptionState, writeDisk: Boolean = true) {
        val prior = mutableStates.value[state.sessionID]?.phase
        check(recordingJobTransitionAllowed(prior, state.phase)) { "invalidRecordingJobTransition" }
        mutableStates.update { it + (state.sessionID to state) }
        if (!writeDisk) return
        val file = transcriptionFile(state.sessionID)
        val encoded = buildString {
            append("version=5\n")
            append("phase=").append(state.phase.name).append('\n')
            append("progress=").append(state.progress.coerceIn(0f, 1f)).append('\n')
            append("modelID=").append(state.modelID.orEmpty()).append('\n')
            append("modelName=").append(state.modelName.orEmpty()).append('\n')
            append("languageTag=").append(state.languageTag.orEmpty()).append('\n')
            append("durationMillis=").append(state.durationMillis.coerceAtLeast(0)).append('\n')
            append("recordedAtEpochMillis=").append(state.recordedAtEpochMillis ?: 0).append('\n')
            append("completedAtEpochMillis=").append(state.completedAtEpochMillis ?: 0).append('\n')
            append("failureCode=").append(state.failureCode.orEmpty()).append('\n')
            append("addedToDraft=").append(state.addedToDraft).append('\n')
            append("titleBase64=").append(encodeProperty(state.title.orEmpty())).append('\n')
            append("tagsBase64=").append(encodeProperty(state.tags.joinToString("\u0000"))).append('\n')
            append("categoryBase64=").append(encodeProperty(state.category.orEmpty())).append('\n')
            append("speakerCount=").append(state.speakerCount.coerceIn(0, 32)).append('\n')
            append("diarizationSkipReasonBase64=").append(encodeProperty(state.diarizationSkipReason.orEmpty())).append('\n')
        }
        AtomicFile(file).writeText(encoded)
    }

    private fun writeTranscript(sessionID: String, transcript: String) {
        AtomicFile(transcriptFile(sessionID)).writeText(transcript)
    }

    private fun writeCleanedTranscript(sessionID: String, transcript: String?) {
        val file = cleanedTranscriptFile(sessionID)
        if (transcript == null) {
            file.delete()
        } else {
            AtomicFile(file).writeText(transcript)
        }
    }

    private fun loadStates(): Map<String, RecordingTranscriptionState> = root.listFiles().orEmpty()
        .asSequence()
        .filter(File::isDirectory)
        .mapNotNull { directory ->
            if (!UUID_PATTERN.matches(directory.name)) return@mapNotNull null
            val values = runCatching {
                File(directory, TRANSCRIPTION_FILE).readLines().associate { line ->
                    val split = line.indexOf('=')
                    require(split > 0)
                    line.substring(0, split) to line.substring(split + 1)
                }
            }.getOrNull() ?: return@mapNotNull null
            val version = values["version"]?.toIntOrNull() ?: return@mapNotNull null
            if (version !in 1..5) return@mapNotNull null
            val phase = parseRecordingTranscriptionPhase(requireNotNull(values["phase"]))
                ?: return@mapNotNull null
            val transcript = File(directory, TRANSCRIPT_FILE).takeIf(File::isFile)?.let { runCatching { it.readText() }.getOrNull() }
            val cleanedTranscript = File(directory, CLEANED_TRANSCRIPT_FILE).takeIf(File::isFile)
                ?.let { runCatching { it.readText() }.getOrNull() }
                ?.takeIf(String::isNotBlank)
            RecordingTranscriptionState(
                sessionID = directory.name,
                phase = if (phase in setOf(
                        RecordingTranscriptionPhase.QUEUED,
                        RecordingTranscriptionPhase.PROCESSING,
                        RecordingTranscriptionPhase.FINALIZING,
                    )
                ) {
                    RecordingTranscriptionPhase.FAILED
                } else phase,
                progress = values["progress"]?.toFloatOrNull()?.coerceIn(0f, 1f) ?: 0f,
                modelID = values["modelID"]?.takeIf(String::isNotBlank),
                modelName = values["modelName"]?.takeIf(String::isNotBlank),
                languageTag = values["languageTag"]?.takeIf(String::isNotBlank),
                durationMillis = values["durationMillis"]?.toLongOrNull()?.coerceAtLeast(0)
                    ?: recordingDurationMillis(directory.name).orEmptyDuration(),
                recordedAtEpochMillis = values["recordedAtEpochMillis"]?.toLongOrNull()?.takeIf { it > 0 }
                    ?: recordingCreatedAtEpochMillis(appContext, directory.name),
                completedAtEpochMillis = values["completedAtEpochMillis"]?.toLongOrNull()?.takeIf { it > 0 }
                    ?: File(directory, TRANSCRIPT_FILE).takeIf(File::isFile)?.lastModified()?.takeIf { it > 0 },
                transcript = transcript,
                cleanedTranscript = cleanedTranscript,
                failureCode = if (phase in setOf(
                        RecordingTranscriptionPhase.QUEUED,
                        RecordingTranscriptionPhase.PROCESSING,
                        RecordingTranscriptionPhase.FINALIZING,
                    )
                ) {
                    "processInterrupted"
                } else values["failureCode"]?.takeIf(String::isNotBlank),
                addedToDraft = values["addedToDraft"]?.toBooleanStrictOrNull() ?: false,
                title = values["titleBase64"]?.let(::decodeProperty)?.takeIf(String::isNotBlank),
                tags = values["tagsBase64"]?.let(::decodeProperty)?.split('\u0000')
                    ?.map(String::trim)?.filter(String::isNotBlank)?.distinct()?.take(20).orEmpty(),
                category = values["categoryBase64"]?.let(::decodeProperty)?.takeIf(String::isNotBlank),
                speakerCount = values["speakerCount"]?.toIntOrNull()?.coerceIn(0, 32) ?: 0,
                diarizationSkipReason = values["diarizationSkipReasonBase64"]?.let(::decodeProperty)?.takeIf(String::isNotBlank),
            ).let { it.sessionID to it }
        }
        .toMap()

    private fun transcriptionFile(sessionID: String): File = File(root, "$sessionID/$TRANSCRIPTION_FILE")
    private fun transcriptFile(sessionID: String): File = File(root, "$sessionID/$TRANSCRIPT_FILE")
    private fun cleanedTranscriptFile(sessionID: String): File = File(root, "$sessionID/$CLEANED_TRANSCRIPT_FILE")

    private fun recordingPreset(sessionID: String) = recordingDirectory(sessionID)?.let { directory ->
        listOf("preset-snapshot.json", "wear-preset.json").asSequence()
            .map(directory::resolve)
            .firstOrNull(File::isFile)
            ?.let { runCatching { it.readText(StandardCharsets.UTF_8) }.getOrNull() }
            ?.let(RecordingPresetSnapshotCodec::decode)
    }

    companion object {
        @Volatile private var shared: RecordingTranscriptionClient? = null
        fun get(context: Context): RecordingTranscriptionClient = shared ?: synchronized(this) {
            shared ?: RecordingTranscriptionClient(context).also { shared = it }
        }

        private const val SAMPLE_RATE = 16_000
        private const val PCM_BYTES_PER_SECOND = SAMPLE_RATE * 2L
        private const val TRANSCRIPTION_FILE = "transcription.properties"
        private const val TRANSCRIPT_FILE = "transcript.txt"
        private const val CLEANED_TRANSCRIPT_FILE = "transcript-cleaned.txt"
        private const val MAX_TRANSCRIPT_CHARACTERS = 500_000
        private val CHUNK_PATTERN = Regex("^chunk-[0-9]{6}\\.pcm$")
        private val UUID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    }
}

/** Deterministic paragraph groups frozen by durable auto-stop segment boundaries. */
internal fun groupRecordingChunks(chunks: List<File>, boundaries: Set<Int>): List<List<File>> = buildList {
    var current = mutableListOf<File>()
    chunks.forEach { chunk ->
        val index = chunk.name.removePrefix("chunk-").removeSuffix(".pcm").toIntOrNull()
        if (current.isNotEmpty() && index in boundaries) {
            add(current)
            current = mutableListOf()
        }
        current += chunk
    }
    if (current.isNotEmpty()) add(current)
}

internal fun parseRecordingTranscriptionPhase(value: String): RecordingTranscriptionPhase? = when (value) {
    "NOT_STARTED" -> RecordingTranscriptionPhase.QUEUED
    "TRANSCRIBING" -> RecordingTranscriptionPhase.PROCESSING
    "CANCELLED" -> RecordingTranscriptionPhase.DISCARDED
    else -> runCatching { RecordingTranscriptionPhase.valueOf(value) }.getOrNull()
}

internal fun recordingJobTransitionAllowed(
    from: RecordingTranscriptionPhase?,
    to: RecordingTranscriptionPhase,
): Boolean = when {
    from == null || from == to -> true
    from == RecordingTranscriptionPhase.QUEUED -> to in setOf(
        RecordingTranscriptionPhase.PROCESSING,
        RecordingTranscriptionPhase.FAILED,
        RecordingTranscriptionPhase.DISCARDED,
    )
    from == RecordingTranscriptionPhase.PROCESSING -> to in setOf(
        RecordingTranscriptionPhase.FINALIZING,
        RecordingTranscriptionPhase.FAILED,
        RecordingTranscriptionPhase.DISCARDED,
    )
    from == RecordingTranscriptionPhase.FINALIZING -> to in setOf(
        RecordingTranscriptionPhase.COMPLETED,
        RecordingTranscriptionPhase.FAILED,
        RecordingTranscriptionPhase.DISCARDED,
    )
    from == RecordingTranscriptionPhase.FAILED -> to == RecordingTranscriptionPhase.QUEUED
    else -> false
}

private data class PrivateTranscriptionResult(
    val transcript: String,
    val speakerCount: Int = 0,
    val diarizationSkipReason: String? = null,
    val plainTranscript: String = transcript,
)

private fun encodeProperty(value: String): String = Base64.getUrlEncoder().withoutPadding()
    .encodeToString(value.toByteArray(StandardCharsets.UTF_8))

private fun decodeProperty(value: String): String? = runCatching {
    String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8)
}.getOrNull()

private fun Long?.orEmptyDuration(): Long = this ?: 0L

private fun AtomicFile.writeText(value: String) {
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

private fun File.directorySize(): Long = walkTopDown().filter(File::isFile).sumOf(File::length)

private fun sha256(file: File): String {
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().use { input ->
        val buffer = ByteArray(128 * 1_024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
    }
    return digest.digest().joinToString("") { "%02x".format(Locale.ROOT, it) }
}

private fun jsonText(json: String): String = runCatching { JSONObject(json).optString("text").trim() }.getOrDefault("")

private fun jsonSpeakerObservation(json: String, paragraph: Int): SpeakerObservation? = runCatching {
    val root = JSONObject(json)
    val text = root.optString("text").trim()
    if (text.isEmpty()) return@runCatching null
    val array = root.optJSONArray("spk")
    val vector = array?.takeIf { it.length() in 16..512 }?.let {
        DoubleArray(it.length()) { index -> it.getDouble(index) }
    }
    SpeakerObservation(
        text = text,
        vector = vector,
        frameCount = root.optInt("spk_frames", 0).coerceAtLeast(0),
        paragraph = paragraph,
    )
}.getOrNull()

internal fun safeModelArchiveTarget(root: File, entryName: String): File {
    require(
        entryName.isNotBlank() &&
            '\u0000' !in entryName &&
            !entryName.startsWith('/') &&
            !entryName.startsWith('\\') &&
            '\\' !in entryName,
    ) { "unsafeModelArchivePath" }
    val canonicalRoot = root.canonicalFile
    val target = File(canonicalRoot, entryName).canonicalFile
    require(target.path.startsWith(canonicalRoot.path + File.separator)) { "unsafeModelArchivePath" }
    return target
}

private fun modelFailureCode(error: Throwable): String = when (val message = error.message.orEmpty()) {
    "insufficientStorage", "insufficientDeviceMemory" -> message
    "emptyModelArchive", "invalidModelConfiguration", "invalidModelAcousticData" -> "invalidModel"
    "modelArchiveTooLarge", "modelExpandedTooLarge", "modelArchiveFileLimit" -> "modelTooLarge"
    "unsafeModelArchivePath" -> "unsafeArchive"
    "invalidModelArtifact", "invalidModelArtifactSize", "modelChecksumMismatch", "invalidModelManifest",
    "invalidDownloadRange" -> message
    else -> if (message.startsWith("downloadHttp")) message else "modelInstallFailed"
}

internal fun isSpeechModelSupportedByMemory(
    descriptor: SpeechModelDescriptor,
    totalMemoryBytes: Long,
): Boolean = totalMemoryBytes >= descriptor.minimumMemoryBytes

private fun transcriptionFailureCode(error: Throwable): String = when (error.message) {
    "noSpeech" -> "noSpeech"
    else -> "localTranscriptionFailed"
}
