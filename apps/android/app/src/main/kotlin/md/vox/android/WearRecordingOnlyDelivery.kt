package md.vox.android

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.util.AtomicFile
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.io.File
import java.io.FilterOutputStream
import java.io.OutputStream
import java.nio.charset.StandardCharsets
import java.security.DigestOutputStream
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.capturedomain.WearRemoteRecordingPhase
import md.vox.android.platformservices.AudioCaptureClient

internal sealed interface WearRecordingOnlyExportResult {
    data class Exported(
        val displayName: String,
        val documentUri: String,
        val byteCount: Long,
        val sha256: String,
    ) : WearRecordingOnlyExportResult

    data class Failed(val code: String) : WearRecordingOnlyExportResult
}

/** Copies a Watch recording directly to its frozen SAF route and verifies the provider read-back. */
internal class AndroidWearRecordingOnlyExporter(context: Context) {
    private val resolver = context.applicationContext.contentResolver

    fun export(
        sessionID: String,
        recordedAtEpochMillis: Long,
        preset: CapturePreset,
        writeAudio: (OutputStream) -> Boolean,
    ): WearRecordingOnlyExportResult {
        if (!sessionID.matches(RECORDING_ID_PATTERN)) return WearRecordingOnlyExportResult.Failed("recordingID")
        if (preset.watchOutputMode != CaptureWatchOutputMode.RECORDING_ONLY) {
            return WearRecordingOnlyExportResult.Failed("outputMode")
        }
        val tree = preset.exportSettings.destinationTreeUri?.let(Uri::parse)
            ?: return WearRecordingOnlyExportResult.Failed("destinationRequired")
        if (tree.scheme != "content") return WearRecordingOnlyExportResult.Failed("destinationRequired")
        var createdTarget: Uri? = null
        return runCatching {
            val root = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val folderSegments = safeFolderSegments(preset.logicalFolder)
            val parent = resolveOrCreateFolder(tree, root, folderSegments)
            val baseName = recordingOnlyBaseName(
                template = preset.exportSettings.newFileNameTemplate,
                sessionID = sessionID,
                recordedAtEpochMillis = recordedAtEpochMillis,
            )
            val target = createUniqueDocument(tree, parent, baseName).also { createdTarget = it }
            val digest = MessageDigest.getInstance("SHA-256")
            var written = 0L
            val output = resolver.openOutputStream(target, "wt") ?: error("destinationWrite")
            output.use { raw ->
                val counted = object : FilterOutputStream(DigestOutputStream(raw, digest)) {
                    override fun write(value: Int) {
                        out.write(value)
                        written += 1
                        require(written <= MAX_AUDIO_BYTES) { "audioSizeLimit" }
                    }

                    override fun write(bytes: ByteArray, offset: Int, length: Int) {
                        out.write(bytes, offset, length)
                        written += length
                        require(written <= MAX_AUDIO_BYTES) { "audioSizeLimit" }
                    }
                }
                check(writeAudio(counted)) { "recordingExport" }
                counted.flush()
            }
            require(written > WAV_HEADER_BYTES) { "recordingEmpty" }
            val expectedSHA = digest.digest().toHex()
            val verified = verify(target, written, expectedSHA)
            require(verified) { "providerVerification" }
            WearRecordingOnlyExportResult.Exported(
                displayName = queryDisplayName(target) ?: "$baseName.wav",
                documentUri = target.toString(),
                byteCount = written,
                sha256 = expectedSHA,
            )
        }.getOrElse { error ->
            createdTarget?.let { target ->
                runCatching { DocumentsContract.deleteDocument(resolver, target) }
            }
            WearRecordingOnlyExportResult.Failed(error.message?.take(64) ?: "recordingOnlyExport")
        }
    }

    private fun safeFolderSegments(value: String): List<String> = value
        .split('/')
        .map(String::trim)
        .filter(String::isNotEmpty)
        .also { segments ->
            require(segments.size <= 31 && segments.all { it !in setOf(".", "..") && '\\' !in it && it.length <= 128 }) {
                "recordingFolder"
            }
        }

    private fun resolveOrCreateFolder(tree: Uri, root: Uri, segments: List<String>): Uri =
        segments.fold(root) { parent, segment ->
            findChild(tree, parent, segment, DocumentsContract.Document.MIME_TYPE_DIR)
                ?: requireNotNull(
                    DocumentsContract.createDocument(
                        resolver,
                        parent,
                        DocumentsContract.Document.MIME_TYPE_DIR,
                        segment,
                    ),
                )
        }

    private fun createUniqueDocument(tree: Uri, parent: Uri, baseName: String): Uri {
        repeat(1_000) { index ->
            val suffix = if (index == 0) "" else "-${index + 1}"
            val displayName = "$baseName$suffix.wav"
            if (findChild(tree, parent, displayName) == null) {
                return requireNotNull(DocumentsContract.createDocument(resolver, parent, "audio/wav", displayName))
            }
        }
        error("recordingFolderFull")
    }

    private fun findChild(tree: Uri, parent: Uri, displayName: String, mimeType: String? = null): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(parent))
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        return resolver.query(children, projection, null, null, null)?.use { cursor ->
            val id = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val name = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val type = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            var found: Uri? = null
            while (cursor.moveToNext()) {
                if (cursor.getString(name) == displayName && (mimeType == null || cursor.getString(type) == mimeType)) {
                    check(found == null) { "duplicateDestination" }
                    found = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(id))
                }
            }
            found
        }
    }

    private fun verify(uri: Uri, expectedLength: Long, expectedSHA: String): Boolean {
        val digest = MessageDigest.getInstance("SHA-256")
        var total = 0L
        resolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(64 * 1_024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                if (total > MAX_AUDIO_BYTES) return false
                digest.update(buffer, 0, count)
            }
        } ?: return false
        return total == expectedLength && digest.digest().toHex() == expectedSHA
    }

    private fun queryDisplayName(uri: Uri): String? = resolver.query(
        uri,
        arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    private fun ByteArray.toHex(): String = joinToString("") { byte -> "%02x".format(byte) }

    private companion object {
        val RECORDING_ID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        const val MAX_AUDIO_BYTES = 2L * 1024 * 1024 * 1024
        const val WAV_HEADER_BYTES = 44L
    }
}

internal fun recordingOnlyBaseName(
    template: String,
    sessionID: String,
    recordedAtEpochMillis: Long,
    zoneID: ZoneId = ZoneId.systemDefault(),
): String {
    require(sessionID.matches(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"))) {
        "recordingID"
    }
    val time = Instant.ofEpochMilli(recordedAtEpochMillis.coerceAtLeast(0)).atZone(zoneID)
    val rendered = template.trim().ifEmpty { "watch-{id8}" }
        .replace(Regex("(?i)\\.(wav|md)$"), "")
        .replace("{timestamp}", time.format(DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss", Locale.ROOT)))
        .replace("{date}", time.format(DateTimeFormatter.ISO_LOCAL_DATE))
        .replace("{YR}", time.format(DateTimeFormatter.ofPattern("yyyy", Locale.ROOT)))
        .replace("{time}", time.format(DateTimeFormatter.ofPattern("HHmmss", Locale.ROOT)))
        .replace("{id}", sessionID.lowercase(Locale.ROOT))
        .replace("{uuid}", sessionID.lowercase(Locale.ROOT))
        .replace("{id8}", sessionID.take(8).lowercase(Locale.ROOT))
        .replace(Regex("\\{[^}]+\\}"), "")
        .replace(Regex("[\\p{Cntrl}/\\\\:]"), "-")
        .replace(Regex("\\s+"), "-")
        .replace(Regex("-+"), "-")
        .trim(' ', '.', '-')
        .take(120)
    return rendered.ifEmpty { "watch-${sessionID.take(8).lowercase(Locale.ROOT)}" }
}

internal data class WearRecordingOnlyReceipt(val byteCount: Long, val sha256: String)

internal class WearRecordingOnlyReceiptStore(context: Context) {
    private val recordingsRoot = File(context.applicationContext.noBackupFilesDir, "recordings").canonicalFile

    fun read(sessionID: String): WearRecordingOnlyReceipt? = receiptFile(sessionID)?.takeIf(File::isFile)?.let { file ->
        runCatching {
            val values = file.readLines().associate { line ->
                val split = line.indexOf('=')
                require(split > 0)
                line.substring(0, split) to line.substring(split + 1)
            }
            require(values["version"] == "1")
            val byteCount = requireNotNull(values["byteCount"]).toLong().also { require(it > 44) }
            val sha256 = requireNotNull(values["sha256"]).also { require(it.matches(Regex("^[0-9a-f]{64}$"))) }
            WearRecordingOnlyReceipt(byteCount, sha256)
        }.getOrNull()
    }

    fun write(sessionID: String, result: WearRecordingOnlyExportResult.Exported): Boolean {
        val file = receiptFile(sessionID) ?: return false
        val atomic = AtomicFile(file)
        val output = runCatching { atomic.startWrite() }.getOrNull() ?: return false
        return try {
            val content = "version=1\nbyteCount=${result.byteCount}\nsha256=${result.sha256}\n"
            output.write(content.toByteArray(StandardCharsets.UTF_8))
            output.flush()
            output.fd.sync()
            atomic.finishWrite(output)
            true
        } catch (_: Throwable) {
            atomic.failWrite(output)
            false
        }
    }

    private fun receiptFile(sessionID: String): File? {
        if (!sessionID.matches(Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"))) return null
        val directory = File(recordingsRoot, sessionID).canonicalFile
        if (directory.parentFile != recordingsRoot || !directory.isDirectory) return null
        return File(directory, "wear-recording-only-delivery.receipt")
    }
}

class WearRecordingOnlyDeliveryWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val recordingID = inputData.getString(KEY_RECORDING_ID) ?: return Result.failure()
        val frontier = inputData.getInt(KEY_FRONTIER, 0)
        val client = AudioCaptureClient(applicationContext)
        val recording = client.recordings().firstOrNull { it.sessionID == recordingID } ?: return Result.failure()
        if (frontier <= 0 || frontier != recording.chunkCount) {
            PhoneWearBridge.postStatus(
                applicationContext,
                recordingID,
                WearRemoteRecordingPhase.TRANSPORT_FAILED,
                minimumRevision = 0,
                frontier = frontier,
                message = "Incomplete recording frontier",
            )
            return Result.failure(Data.Builder().putString(KEY_FAILURE, "incompleteFrontier").build())
        }
        val preset = client.frozenPreset(recordingID) ?: return Result.failure()
        if (preset.watchOutputMode != CaptureWatchOutputMode.RECORDING_ONLY) return Result.failure()
        val receiptStore = WearRecordingOnlyReceiptStore(applicationContext)
        val delivered = if (receiptStore.read(recordingID) != null) {
            true
        } else {
            when (val exported = AndroidWearRecordingOnlyExporter(applicationContext).export(
                recordingID,
                recording.createdAtEpochMillis,
                preset,
                writeAudio = { output -> client.exportWav(recordingID, output) },
            )) {
                is WearRecordingOnlyExportResult.Exported -> receiptStore.write(recordingID, exported)
                is WearRecordingOnlyExportResult.Failed -> {
                    PhoneWearBridge.postStatus(
                        applicationContext,
                        recordingID,
                        WearRemoteRecordingPhase.FAILED,
                        minimumRevision = 0,
                        frontier = frontier,
                        message = exported.code,
                    )
                    return Result.failure(Data.Builder().putString(KEY_FAILURE, exported.code).build())
                }
            }
        }
        if (!delivered) return Result.retry()
        return if (PhoneWearBridge.postStatus(
                applicationContext,
                recordingID,
                WearRemoteRecordingPhase.DELIVERED,
                minimumRevision = 0,
                frontier = frontier,
            )
        ) Result.success() else Result.retry()
    }

    companion object {
        private const val KEY_RECORDING_ID = "recordingID"
        private const val KEY_FRONTIER = "frontier"
        private const val KEY_FAILURE = "failure"

        fun enqueue(context: Context, recordingID: String, frontier: Int) {
            val request = OneTimeWorkRequestBuilder<WearRecordingOnlyDeliveryWorker>()
                .setInputData(
                    Data.Builder()
                        .putString(KEY_RECORDING_ID, recordingID)
                        .putInt(KEY_FRONTIER, frontier.coerceAtLeast(0))
                        .build(),
                )
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "wear-recording-only-$recordingID",
                ExistingWorkPolicy.KEEP,
                request,
            )
        }
    }
}
