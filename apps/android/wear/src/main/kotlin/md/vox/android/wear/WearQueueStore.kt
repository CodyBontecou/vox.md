package md.vox.android.wear

import android.content.Context
import android.system.Os
import android.system.OsConstants
import android.util.AtomicFile
import android.util.Base64
import java.io.File
import java.nio.charset.StandardCharsets
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import md.vox.android.capturedomain.WearProtocol

internal enum class WearQueuePhase {
    LOCAL,
    SYNC_QUEUED,
    PHONE_QUEUED,
    PHONE_TRANSCRIBING,
    PHONE_DELIVERING,
    PHONE_RECEIVING,
    PHONE_INGESTED,
    DELIVERED,
    FAILED,
    TRANSPORT_FAILED,
}

internal data class WearQueueItem(
    val recordingID: String,
    val createdAtEpochMillis: Long,
    val durationMillis: Long,
    val chunkCount: Int,
    val presetID: String,
    val presetName: String,
    val presetSnapshot: ByteArray,
    val phase: WearQueuePhase,
    val revision: Int,
    val acknowledgedFrontier: Int,
    val message: String?,
) {
    override fun equals(other: Any?): Boolean = other is WearQueueItem &&
        recordingID == other.recordingID &&
        createdAtEpochMillis == other.createdAtEpochMillis &&
        durationMillis == other.durationMillis &&
        chunkCount == other.chunkCount &&
        presetID == other.presetID &&
        presetName == other.presetName &&
        presetSnapshot.contentEquals(other.presetSnapshot) &&
        phase == other.phase && revision == other.revision &&
        acknowledgedFrontier == other.acknowledgedFrontier && message == other.message

    override fun hashCode(): Int = recordingID.hashCode()
}

internal data class WearTerminalReceipt(
    val recordingID: String,
    val phase: String,
    val revision: Int,
    val frontier: Int,
    val recordedAtEpochMillis: Long,
)

internal object WearQueueStore {
    private const val VERSION = 1
    private const val FILE_NAME = "wear-queue.properties"
    private const val MAX_PRESET_SNAPSHOT_BYTES = 65_536
    private val mutableItems = MutableStateFlow<List<WearQueueItem>>(emptyList())
    val items: StateFlow<List<WearQueueItem>> = mutableItems.asStateFlow()

    @Synchronized
    fun load(context: Context): List<WearQueueItem> {
        val root = recordingsRoot(context)
        recoverAuthorizedDeletions(context, root)
        return root.listFiles().orEmpty().asSequence()
            .filter { it.isDirectory && WearProtocol.recordingIDPattern.matches(it.name) }
            .mapNotNull(::read)
            .sortedBy(WearQueueItem::createdAtEpochMillis)
            .toList()
            .also { mutableItems.value = it }
    }

    @Synchronized
    fun begin(
        context: Context,
        recordingID: String,
        createdAtEpochMillis: Long,
        preset: WearPreset,
    ): WearQueueItem? {
        if (!WearProtocol.recordingIDPattern.matches(recordingID)) return null
        if (preset.snapshot.size !in 1..MAX_PRESET_SNAPSHOT_BYTES) return null
        val directory = File(recordingsRoot(context), recordingID)
        if (!directory.isDirectory) return null
        read(directory)?.let { return it }
        val item = WearQueueItem(
            recordingID = recordingID,
            createdAtEpochMillis = createdAtEpochMillis.coerceAtLeast(0),
            durationMillis = 0,
            chunkCount = 0,
            presetID = preset.id,
            presetName = preset.name,
            presetSnapshot = preset.snapshot,
            phase = WearQueuePhase.LOCAL,
            revision = 0,
            acknowledgedFrontier = 0,
            message = null,
        )
        write(directory, item)
        load(context)
        return item
    }

    @Synchronized
    fun finish(context: Context, recordingID: String, durationMillis: Long, chunkCount: Int): WearQueueItem? =
        update(context, recordingID) { item ->
            item.copy(
                durationMillis = durationMillis.coerceAtLeast(0),
                chunkCount = chunkCount.coerceIn(0, 100_000),
                phase = WearQueuePhase.LOCAL,
                message = null,
            )
        }

    @Synchronized
    fun startSync(context: Context, recordingID: String): WearQueueItem? = update(context, recordingID) { item ->
        item.copy(
            phase = WearQueuePhase.SYNC_QUEUED,
            revision = if (item.revision == Int.MAX_VALUE) 1 else item.revision + 1,
            message = null,
        )
    }

    @Synchronized
    fun applyPhoneStatus(
        context: Context,
        recordingID: String,
        phase: String,
        revision: Int,
        frontier: Int,
        message: String?,
    ): WearQueueItem? {
        val present = load(context).firstOrNull { it.recordingID == recordingID } ?: return null
        if (revision < present.revision) return present
        val remotePhase = md.vox.android.capturedomain.WearRemoteRecordingPhase.fromWireValue(phase) ?: return present
        if (remotePhase.terminal) {
            if (remotePhase.wireValue == WearProtocol.PHASE_DELIVERED &&
                (present.chunkCount <= 0 || frontier < present.chunkCount)
            ) {
                return update(context, recordingID) { item ->
                    item.copy(
                        phase = WearQueuePhase.TRANSPORT_FAILED,
                        revision = maxOf(item.revision, revision),
                        message = "Phone delivery acknowledgement was incomplete",
                    )
                }
            }
            val directory = recordingDirectory(context, recordingID) ?: return null
            WearTerminalReceiptStore.write(
                context,
                WearTerminalReceipt(
                    recordingID = recordingID,
                    phase = remotePhase.wireValue,
                    revision = revision,
                    frontier = frontier.coerceAtLeast(0),
                    recordedAtEpochMillis = System.currentTimeMillis(),
                ),
            )
            if (directory.deleteRecursively()) syncDirectory(recordingsRoot(context))
            load(context)
            return null
        }
        return update(context, recordingID) { item ->
            item.copy(
                phase = when (phase) {
                    WearProtocol.PHASE_RECEIVING -> WearQueuePhase.PHONE_RECEIVING
                    WearProtocol.PHASE_INGESTED -> WearQueuePhase.PHONE_INGESTED
                    WearProtocol.PHASE_QUEUED -> WearQueuePhase.PHONE_QUEUED
                    WearProtocol.PHASE_TRANSCRIBING -> WearQueuePhase.PHONE_TRANSCRIBING
                    WearProtocol.PHASE_DELIVERING -> WearQueuePhase.PHONE_DELIVERING
                    WearProtocol.PHASE_FAILED -> WearQueuePhase.FAILED
                    WearProtocol.PHASE_TRANSPORT_FAILED -> WearQueuePhase.TRANSPORT_FAILED
                    else -> item.phase
                },
                revision = maxOf(item.revision, revision),
                acknowledgedFrontier = maxOf(item.acknowledgedFrontier, frontier.coerceAtMost(item.chunkCount)),
                message = message?.take(160),
            )
        }
    }

    @Synchronized
    fun fail(context: Context, recordingID: String, message: String): WearQueueItem? =
        update(context, recordingID) { it.copy(phase = WearQueuePhase.FAILED, message = message.take(160)) }

    @Synchronized
    fun prepareRetry(context: Context, recordingID: String): WearQueueItem? = update(context, recordingID) { item ->
        item.copy(phase = WearQueuePhase.LOCAL, message = null)
    }

    /** Persists the user's destructive intent before removing any queued media. */
    @Synchronized
    fun discard(context: Context, recordingID: String): Boolean {
        val present = load(context).firstOrNull { it.recordingID == recordingID } ?: return false
        WearTerminalReceiptStore.write(
            context,
            WearTerminalReceipt(
                recordingID = recordingID,
                phase = WearProtocol.PHASE_DISCARDED,
                revision = present.revision,
                frontier = present.acknowledgedFrontier,
                recordedAtEpochMillis = System.currentTimeMillis(),
            ),
        )
        val directory = recordingDirectory(context, recordingID) ?: return false
        val deleted = directory.deleteRecursively()
        if (deleted) syncDirectory(recordingsRoot(context))
        load(context)
        return deleted
    }

    fun terminalReceipt(context: Context, recordingID: String): WearTerminalReceipt? =
        WearTerminalReceiptStore.read(context, recordingID)

    fun recordingChunks(context: Context, item: WearQueueItem): List<File> {
        val directory = recordingDirectory(context, item.recordingID) ?: return emptyList()
        return directory.listFiles().orEmpty()
            .filter { it.isFile && it.name.matches(Regex("^chunk-[0-9]{6}\\.pcm$")) }
            .sortedBy(File::getName)
    }

    private fun update(context: Context, recordingID: String, transform: (WearQueueItem) -> WearQueueItem): WearQueueItem? {
        val directory = recordingDirectory(context, recordingID) ?: return null
        val current = read(directory) ?: return null
        val updated = transform(current)
        write(directory, updated)
        load(context)
        return updated
    }

    private fun read(directory: File): WearQueueItem? = runCatching {
        val values = File(directory, FILE_NAME).readLines().associate { line ->
            val split = line.indexOf('=')
            require(split > 0)
            line.substring(0, split) to line.substring(split + 1)
        }
        require(values["version"]?.toInt() == VERSION)
        val id = requireNotNull(values["recordingID"]).also {
            require(it == directory.name && WearProtocol.recordingIDPattern.matches(it))
        }
        val presetID = requireNotNull(values["presetID"]).also { require(it.length <= 128) }
        val presetName = decodeString(requireNotNull(values["presetName"])).also { require(it.length <= 128) }
        val snapshot = Base64.decode(requireNotNull(values["presetSnapshot"]), Base64.NO_WRAP).also {
            require(it.size in 1..MAX_PRESET_SNAPSHOT_BYTES)
        }
        WearQueueItem(
            recordingID = id,
            createdAtEpochMillis = requireNotNull(values["createdAtEpochMillis"]).toLong().also { require(it >= 0) },
            durationMillis = requireNotNull(values["durationMillis"]).toLong().also { require(it >= 0) },
            chunkCount = requireNotNull(values["chunkCount"]).toInt().also { require(it in 0..100_000) },
            presetID = presetID,
            presetName = presetName,
            presetSnapshot = snapshot,
            phase = WearQueuePhase.valueOf(requireNotNull(values["phase"])),
            revision = requireNotNull(values["revision"]).toInt().also { require(it >= 0) },
            acknowledgedFrontier = requireNotNull(values["acknowledgedFrontier"]).toInt().also { require(it >= 0) },
            message = values["message"]?.takeIf(String::isNotBlank)?.let(::decodeString),
        )
    }.getOrNull()

    private fun write(directory: File, item: WearQueueItem) {
        val atomic = AtomicFile(File(directory, FILE_NAME))
        val bytes = buildString {
            append("version=").append(VERSION).append('\n')
            append("recordingID=").append(item.recordingID).append('\n')
            append("createdAtEpochMillis=").append(item.createdAtEpochMillis).append('\n')
            append("durationMillis=").append(item.durationMillis).append('\n')
            append("chunkCount=").append(item.chunkCount).append('\n')
            append("presetID=").append(item.presetID).append('\n')
            append("presetName=").append(encodeString(item.presetName)).append('\n')
            append("presetSnapshot=").append(Base64.encodeToString(item.presetSnapshot, Base64.NO_WRAP)).append('\n')
            append("phase=").append(item.phase.name).append('\n')
            append("revision=").append(item.revision).append('\n')
            append("acknowledgedFrontier=").append(item.acknowledgedFrontier).append('\n')
            append("message=").append(item.message?.let(::encodeString).orEmpty()).append('\n')
        }.toByteArray(StandardCharsets.UTF_8)
        val output = atomic.startWrite()
        try {
            output.write(bytes)
            output.flush()
            output.fd.sync()
            atomic.finishWrite(output)
            syncDirectory(directory)
        } catch (error: Exception) {
            atomic.failWrite(output)
            throw error
        }
    }

    private fun recordingsRoot(context: Context): File = File(context.noBackupFilesDir, "recordings").apply { mkdirs() }

    private fun recordingDirectory(context: Context, recordingID: String): File? {
        if (!WearProtocol.recordingIDPattern.matches(recordingID)) return null
        val root = recordingsRoot(context).canonicalFile
        return File(root, recordingID).canonicalFile.takeIf { it.parentFile == root && it.isDirectory }
    }

    private fun encodeString(value: String): String =
        Base64.encodeToString(value.toByteArray(StandardCharsets.UTF_8), Base64.NO_WRAP)
    private fun decodeString(value: String): String =
        String(Base64.decode(value, Base64.NO_WRAP), StandardCharsets.UTF_8)

    private fun syncDirectory(directory: File) {
        val descriptor = Os.open(directory.absolutePath, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        try { Os.fsync(descriptor) } finally { Os.close(descriptor) }
    }

    private fun recoverAuthorizedDeletions(context: Context, root: File) {
        WearTerminalReceiptStore.all(context).forEach { receipt ->
            val directory = File(root, receipt.recordingID).canonicalFile
            if (directory.parentFile != root.canonicalFile || !directory.isDirectory) return@forEach
            val item = read(directory) ?: return@forEach
            val authorizesDelete = when (receipt.phase) {
                WearProtocol.PHASE_DISCARDED -> receipt.revision >= item.revision
                WearProtocol.PHASE_DELIVERED -> receipt.revision >= item.revision &&
                    item.chunkCount > 0 && receipt.frontier >= item.chunkCount
                else -> false
            }
            if (authorizesDelete && directory.deleteRecursively()) syncDirectory(root)
        }
    }
}

private object WearTerminalReceiptStore {
    private const val VERSION = 1
    private const val MAX_RECEIPTS = 10_000

    fun write(context: Context, receipt: WearTerminalReceipt) {
        require(WearProtocol.recordingIDPattern.matches(receipt.recordingID))
        require(receipt.phase in setOf(WearProtocol.PHASE_DELIVERED, WearProtocol.PHASE_DISCARDED))
        require(receipt.revision >= 0 && receipt.frontier >= 0 && receipt.recordedAtEpochMillis >= 0)
        val directory = directory(context)
        val file = AtomicFile(File(directory, "${receipt.recordingID}.properties"))
        val bytes = buildString {
            append("version=").append(VERSION).append('\n')
            append("recordingID=").append(receipt.recordingID).append('\n')
            append("phase=").append(receipt.phase).append('\n')
            append("revision=").append(receipt.revision).append('\n')
            append("frontier=").append(receipt.frontier).append('\n')
            append("recordedAtEpochMillis=").append(receipt.recordedAtEpochMillis).append('\n')
        }.toByteArray(StandardCharsets.UTF_8)
        val output = file.startWrite()
        try {
            output.write(bytes)
            output.flush()
            output.fd.sync()
            file.finishWrite(output)
            syncDirectory(directory)
        } catch (error: Exception) {
            file.failWrite(output)
            throw error
        }
        prune(directory)
    }

    fun read(context: Context, recordingID: String): WearTerminalReceipt? {
        if (!WearProtocol.recordingIDPattern.matches(recordingID)) return null
        return read(File(directory(context), "$recordingID.properties"))
    }

    fun all(context: Context): List<WearTerminalReceipt> = directory(context)
        .listFiles().orEmpty()
        .filter(File::isFile)
        .mapNotNull(::read)

    private fun read(file: File): WearTerminalReceipt? = runCatching {
        val values = file.readLines().associate { line ->
            val split = line.indexOf('=')
            require(split > 0)
            line.substring(0, split) to line.substring(split + 1)
        }
        require(values["version"]?.toInt() == VERSION)
        val recordingID = requireNotNull(values["recordingID"])
        require(file.name == "$recordingID.properties" && WearProtocol.recordingIDPattern.matches(recordingID))
        val phase = requireNotNull(values["phase"])
        require(phase in setOf(WearProtocol.PHASE_DELIVERED, WearProtocol.PHASE_DISCARDED))
        WearTerminalReceipt(
            recordingID = recordingID,
            phase = phase,
            revision = requireNotNull(values["revision"]).toInt().also { require(it >= 0) },
            frontier = requireNotNull(values["frontier"]).toInt().also { require(it >= 0) },
            recordedAtEpochMillis = requireNotNull(values["recordedAtEpochMillis"]).toLong().also { require(it >= 0) },
        )
    }.getOrNull()

    private fun directory(context: Context): File = File(context.noBackupFilesDir, "wear/terminal-receipts").apply { mkdirs() }

    private fun prune(directory: File) {
        directory.listFiles().orEmpty()
            .filter(File::isFile)
            .sortedByDescending(File::lastModified)
            .drop(MAX_RECEIPTS)
            .forEach(File::delete)
    }

    private fun syncDirectory(directory: File) {
        val descriptor = Os.open(directory.absolutePath, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        try { Os.fsync(descriptor) } finally { Os.close(descriptor) }
    }
}

internal data class WearPreset(val id: String, val name: String, val symbol: String, val snapshot: ByteArray) {
    override fun equals(other: Any?): Boolean = other is WearPreset &&
        id == other.id && name == other.name && symbol == other.symbol && snapshot.contentEquals(other.snapshot)
    override fun hashCode(): Int = id.hashCode()
}

internal object WearPresetStore {
    private val defaultPreset = WearPreset(
        id = "33333333-3333-4333-8333-333333333333",
        name = "Daily",
        symbol = "description",
        snapshot = "{\"id\":\"33333333-3333-4333-8333-333333333333\",\"name\":\"Daily\",\"revision\":1,\"logicalFolder\":\"Daily\",\"noteNameTemplate\":\"daily-{uuid}.md\",\"metadataFields\":[]}".toByteArray(),
    )
    private val mutablePresets = MutableStateFlow(listOf(defaultPreset))
    val presets: StateFlow<List<WearPreset>> = mutablePresets.asStateFlow()
    private val mutableSelection = MutableStateFlow(defaultPreset.id)
    val selection: StateFlow<String> = mutableSelection.asStateFlow()

    fun load(context: Context) {
        val parsed = File(context.noBackupFilesDir, "wear/presets.txt").takeIf(File::isFile)
            ?.readLines().orEmpty().mapNotNull(::decodePreset)
            .distinctBy(WearPreset::id)
            .take(32)
        mutablePresets.value = parsed.ifEmpty { listOf(defaultPreset) }
        val selected = File(context.noBackupFilesDir, "wear/selected-preset-id").takeIf(File::isFile)
            ?.readText()?.trim()
        mutableSelection.value = selected?.takeIf { id -> mutablePresets.value.any { it.id == id } }
            ?: mutablePresets.value.first().id
    }

    fun replace(context: Context, presets: List<WearPreset>, activePresetID: String) {
        val bounded = presets.distinctBy(WearPreset::id).take(32).ifEmpty { listOf(defaultPreset) }
        val directory = File(context.noBackupFilesDir, "wear").apply { mkdirs() }
        AtomicFile(File(directory, "presets.txt")).let { atomic ->
            val output = atomic.startWrite()
            try {
                output.write(bounded.joinToString("\n", postfix = "\n", transform = ::encodePreset).toByteArray())
                output.flush()
                output.fd.sync()
                atomic.finishWrite(output)
            } catch (error: Exception) {
                atomic.failWrite(output)
                throw error
            }
        }
        mutablePresets.value = bounded
        select(context, activePresetID.takeIf { id -> bounded.any { it.id == id } } ?: bounded.first().id)
    }

    fun select(context: Context, presetID: String) {
        if (mutablePresets.value.none { it.id == presetID }) return
        val file = AtomicFile(File(context.noBackupFilesDir, "wear/selected-preset-id"))
        file.baseFile.parentFile?.mkdirs()
        val output = file.startWrite()
        try {
            output.write(presetID.toByteArray())
            output.flush()
            output.fd.sync()
            file.finishWrite(output)
            mutableSelection.value = presetID
        } catch (error: Exception) {
            file.failWrite(output)
        }
    }

    fun selected(): WearPreset = mutablePresets.value.firstOrNull { it.id == mutableSelection.value }
        ?: mutablePresets.value.firstOrNull()
        ?: defaultPreset

    private fun encodePreset(preset: WearPreset): String = listOf(
        preset.id,
        encode(preset.name),
        encode(preset.symbol),
        Base64.encodeToString(preset.snapshot, Base64.NO_WRAP),
    ).joinToString("|")

    private fun decodePreset(value: String): WearPreset? = runCatching {
        val parts = value.split('|')
        require(parts.size == 4 && parts[0].length in 1..128)
        WearPreset(
            id = parts[0],
            name = decode(parts[1]).take(128),
            symbol = decode(parts[2]).take(64),
            snapshot = Base64.decode(parts[3], Base64.NO_WRAP).also { require(it.size in 1..65_536) },
        )
    }.getOrNull()

    private fun encode(value: String): String = Base64.encodeToString(value.toByteArray(), Base64.NO_WRAP)
    private fun decode(value: String): String = String(Base64.decode(value, Base64.NO_WRAP))
}
