package md.vox.android.capturedomain

/**
 * Live Notes: the composer is the file. Once the composer has words, the note is written to
 * the preset's planned file and the composer stays bound to that file; every later edit
 * replaces the whole file after a version check. This file holds the platform-free model:
 * the binding, the status the pill shows, the version/conflict rules and the first-write
 * rebase. The SAF reads and writes live behind [LiveNoteFileStore] in the data module.
 */

/** A vault file addressed by its destination grant and vault-relative path ("Inbox/Note.md"). */
data class LiveNoteLocation(
    val destinationID: String,
    val treeUri: String,
    val relativePath: String,
) {
    val segments: List<String> get() = relativePath.split('/').filter(String::isNotEmpty)
    val fileName: String get() = segments.lastOrNull().orEmpty()
    val folderSegments: List<String> get() = segments.dropLast(1)
    val title: String get() = fileName.removeMarkdownExtension()

    fun sibling(fileName: String): LiveNoteLocation =
        copy(relativePath = (folderSegments + fileName).joinToString("/"))
}

/** What the app last saw of a file: its content hash, length and provider modified time. */
data class LiveNoteVersion(
    val sha256: String,
    val byteCount: Long,
    val lastModifiedEpochMillis: Long? = null,
) {
    /** Content identity. Providers are free to touch modified times, so the hash decides. */
    fun sameContentAs(other: LiveNoteVersion): Boolean = sha256 == other.sha256 && byteCount == other.byteCount
}

data class LiveNoteFile(
    val location: LiveNoteLocation,
    val text: String,
    val version: LiveNoteVersion,
)

sealed interface LiveNoteReadResult {
    data class Found(val file: LiveNoteFile) : LiveNoteReadResult
    data object Missing : LiveNoteReadResult
    data class Unreachable(val reason: String) : LiveNoteReadResult
}

sealed interface LiveNoteWriteResult {
    data class Written(val version: LiveNoteVersion) : LiveNoteWriteResult
    /** The file no longer matches the expected version; nothing was written. */
    data class Changed(val current: LiveNoteFile) : LiveNoteWriteResult
    /** The file is gone and the write did not ask to create it. */
    data object Missing : LiveNoteWriteResult
    data class Unreachable(val reason: String) : LiveNoteWriteResult
}

sealed interface LiveNoteCopyResult {
    data class Created(val location: LiveNoteLocation, val version: LiveNoteVersion) : LiveNoteCopyResult
    data class Unreachable(val reason: String) : LiveNoteCopyResult
}

/** Whole-file IO for a bound note. Implementations run off the main thread. */
interface LiveNoteFileStore {
    suspend fun read(location: LiveNoteLocation): LiveNoteReadResult

    /**
     * Replaces the whole file with [text] only while its bytes still match [expected]. A null
     * [expected] means the caller believes the file is absent: create it, or report [LiveNoteWriteResult.Changed]
     * when something now occupies the name.
     */
    suspend fun replace(location: LiveNoteLocation, text: String, expected: LiveNoteVersion?): LiveNoteWriteResult

    /** Writes [text] to a new sibling named "<name> (Vox).md" (numbered when that is taken). */
    suspend fun createCopy(location: LiveNoteLocation, text: String): LiveNoteCopyResult
}

/** The composer's link to its file. Kept until New note releases it. */
data class LiveNoteBinding(
    val location: LiveNoteLocation,
    val presetID: String?,
    val presetName: String?,
    /** Capture request that made the first write; correlates Activity and recovery. */
    val requestID: String?,
    /** Rolling or fixed note: the editor shows the whole file with the new entry highlighted. */
    val isAppendTarget: Boolean,
    val version: LiveNoteVersion,
    /** The text the file held at [version], as far as this app knows. */
    val savedText: String,
)

/** A first write that is admitted to the durable queue but not yet confirmed in the vault. */
data class LiveNotePendingWrite(
    val requestID: String,
    val submittedText: String,
    val presetID: String?,
    val presetName: String?,
    val isAppendTarget: Boolean,
    val prefersLastOccurrence: Boolean,
    val plannedPath: String?,
)

data class LiveNoteRange(val start: Int, val end: Int)

enum class LiveNoteDiffKind { ADDED, REMOVED }

data class LiveNoteDiffLine(val kind: LiveNoteDiffKind, val text: String)

data class LiveNoteConflict(
    val theirs: LiveNoteFile,
    val mine: String,
    val summary: List<LiveNoteDiffLine>,
)

/** What the status pill says. */
enum class LiveNoteStatus {
    /** Nothing written yet: "Saves as you go". */
    BLANK,
    /** A write is due or in flight: "Saving…". */
    SAVING,
    /** The file matches the editor: "Saved". */
    SAVED,
    /** The file changed elsewhere while there were local edits: "Not saved", saving paused. */
    CONFLICT,
    /** The vault cannot be reached; edits are kept on the phone: "On this phone only". */
    OFFLINE,
}

/**
 * The composer's whole live-note state. Persisted locally so a process death or an
 * unreachable vault never loses edits; the vault file is written whenever it can be.
 */
data class LiveNoteSession(
    val binding: LiveNoteBinding? = null,
    val pending: LiveNotePendingWrite? = null,
    val localText: String = "",
    val conflict: LiveNoteConflict? = null,
    val isUnreachable: Boolean = false,
    val isWriting: Boolean = false,
    val highlight: LiveNoteRange? = null,
    /** Released notes whose last edits could not be written yet; finished in the background. */
    val parked: List<LiveNoteParked> = emptyList(),
) {
    val isBound: Boolean get() = binding != null
    val isStarted: Boolean get() = binding != null || pending != null

    val hasUnsavedEdits: Boolean
        get() = when {
            binding != null -> localText != binding.savedText
            pending != null -> localText != pending.submittedText
            else -> localText.isNotBlank()
        }

    val status: LiveNoteStatus
        get() = when {
            conflict != null -> LiveNoteStatus.CONFLICT
            isUnreachable -> LiveNoteStatus.OFFLINE
            !isStarted && localText.isBlank() -> LiveNoteStatus.BLANK
            isWriting || hasUnsavedEdits || pending != null -> LiveNoteStatus.SAVING
            else -> LiveNoteStatus.SAVED
        }

    /** Vault-relative path for the breadcrumb: the bound file, else the queued plan. */
    val relativePath: String? get() = binding?.location?.relativePath ?: pending?.plannedPath

    /** New note: what the toast names, and the blank session that replaces this one. */
    fun released(): LiveNoteRelease = LiveNoteRelease(
        title = binding?.location?.title ?: pending?.plannedPath?.substringAfterLast('/')?.removeMarkdownExtension(),
        presetName = binding?.presetName ?: pending?.presetName,
        relativePath = relativePath,
        binding = binding,
        next = LiveNoteSession(
            parked = (parked + listOfNotNull(
                LiveNoteParked(binding, pending, localText).takeIf { isStarted && hasUnsavedEdits },
            )).takeLast(MAX_PARKED),
        ),
    )

    private companion object {
        const val MAX_PARKED = 16
    }
}

/**
 * A note released with New note (or another preset) before its last edits reached the vault:
 * the vault was unreachable, its first write was still queued, or it was in a conflict.
 */
data class LiveNoteParked(
    val binding: LiveNoteBinding?,
    val pending: LiveNotePendingWrite?,
    val localText: String,
)

data class LiveNoteRelease(
    val title: String?,
    val presetName: String?,
    val relativePath: String?,
    /** Kept so the toast's Reopen can bind the same file again. */
    val binding: LiveNoteBinding?,
    val next: LiveNoteSession,
)

sealed interface LiveNoteSyncOutcome {
    /** Nothing to do: the file and the editor already agree. */
    data object Unchanged : LiveNoteSyncOutcome
    data class Saved(val binding: LiveNoteBinding) : LiveNoteSyncOutcome
    /** The file changed elsewhere and there were no local edits: show theirs. */
    data class Reloaded(val binding: LiveNoteBinding, val text: String) : LiveNoteSyncOutcome
    data class Conflicted(val conflict: LiveNoteConflict) : LiveNoteSyncOutcome
    data object Unreachable : LiveNoteSyncOutcome
}

/** Result of binding the composer after its first write landed. */
data class LiveNoteFirstWrite(
    val binding: LiveNoteBinding,
    /** Whole file as the editor should now show it (including edits made while it was queued). */
    val editorText: String,
    /** The user's entry inside [editorText]; null when it could not be located. */
    val entryRange: LiveNoteRange?,
    /** True when [editorText] differs from the file and must be written. */
    val needsSave: Boolean,
)

object LiveNoteSync {
    /** Writes [localText] over the bound file when it still holds what we last saw. */
    suspend fun save(store: LiveNoteFileStore, binding: LiveNoteBinding, localText: String): LiveNoteSyncOutcome {
        if (localText == binding.savedText) return LiveNoteSyncOutcome.Unchanged
        return when (val write = store.replace(binding.location, localText, binding.version)) {
            is LiveNoteWriteResult.Written -> LiveNoteSyncOutcome.Saved(binding.copy(version = write.version, savedText = localText))
            is LiveNoteWriteResult.Changed -> changedElsewhere(binding, localText, write.current)
            // Deleted elsewhere while being edited here: the person is still writing it, so put it back.
            LiveNoteWriteResult.Missing -> when (val created = store.replace(binding.location, localText, expected = null)) {
                is LiveNoteWriteResult.Written -> LiveNoteSyncOutcome.Saved(binding.copy(version = created.version, savedText = localText))
                is LiveNoteWriteResult.Changed -> changedElsewhere(binding, localText, created.current)
                LiveNoteWriteResult.Missing, is LiveNoteWriteResult.Unreachable -> LiveNoteSyncOutcome.Unreachable
            }
            is LiveNoteWriteResult.Unreachable -> LiveNoteSyncOutcome.Unreachable
        }
    }

    /**
     * Resume/refresh check (SAF has no change notifications): reload silently when only the
     * file changed, save when only the editor changed, conflict when both did.
     */
    suspend fun refresh(store: LiveNoteFileStore, binding: LiveNoteBinding, localText: String): LiveNoteSyncOutcome =
        when (val read = store.read(binding.location)) {
            is LiveNoteReadResult.Unreachable -> LiveNoteSyncOutcome.Unreachable
            LiveNoteReadResult.Missing -> if (localText != binding.savedText) save(store, binding, localText) else LiveNoteSyncOutcome.Unchanged
            is LiveNoteReadResult.Found -> when {
                read.file.version.sameContentAs(binding.version) ->
                    if (localText != binding.savedText) save(store, binding, localText) else LiveNoteSyncOutcome.Unchanged
                else -> changedElsewhere(binding, localText, read.file)
            }
        }

    /** Use theirs: adopt the file as it is now; local edits are dropped. */
    fun useTheirs(binding: LiveNoteBinding, conflict: LiveNoteConflict): LiveNoteSyncOutcome.Reloaded =
        LiveNoteSyncOutcome.Reloaded(
            binding.copy(version = conflict.theirs.version, savedText = conflict.theirs.text),
            conflict.theirs.text,
        )

    /** Keep mine: overwrite the version that is in the vault now (and only that version). */
    suspend fun keepMine(store: LiveNoteFileStore, binding: LiveNoteBinding, conflict: LiveNoteConflict): LiveNoteSyncOutcome =
        save(store, binding.copy(version = conflict.theirs.version, savedText = conflict.theirs.text), conflict.mine)

    /** Save copy: mine goes to "<name> (Vox).md" and the composer follows it; theirs stays put. */
    suspend fun saveCopy(store: LiveNoteFileStore, binding: LiveNoteBinding, conflict: LiveNoteConflict): LiveNoteSyncOutcome =
        when (val copy = store.createCopy(binding.location, conflict.mine)) {
            is LiveNoteCopyResult.Created -> LiveNoteSyncOutcome.Saved(
                binding.copy(
                    location = copy.location,
                    requestID = null,
                    isAppendTarget = false,
                    version = copy.version,
                    savedText = conflict.mine,
                ),
            )
            is LiveNoteCopyResult.Unreachable -> LiveNoteSyncOutcome.Unreachable
        }

    /**
     * Binds the composer to the file its first write produced. The entry the user typed is
     * found inside the rendered file; edits made while the write was queued replace it there,
     * so nothing typed in the meantime is lost and the rest of the file is kept as it is.
     */
    fun bindFirstWrite(pending: LiveNotePendingWrite, file: LiveNoteFile, currentText: String): LiveNoteFirstWrite {
        val submitted = pending.submittedText.trimEnd()
        val fileText = file.text
        val index = when {
            submitted.isEmpty() -> -1
            pending.prefersLastOccurrence -> fileText.lastIndexOf(submitted)
            else -> fileText.indexOf(submitted)
        }
        val binding = LiveNoteBinding(
            location = file.location,
            presetID = pending.presetID,
            presetName = pending.presetName,
            requestID = pending.requestID,
            isAppendTarget = pending.isAppendTarget,
            version = file.version,
            savedText = fileText,
        )
        if (index >= 0) {
            val before = fileText.substring(0, index)
            val after = fileText.substring(index + submitted.length)
            val unchanged = currentText.trimEnd() == submitted && currentText.length == submitted.length
            val replacement = when {
                unchanged -> submitted
                after.startsWith("\n") -> currentText.trimEnd('\n', '\r')
                else -> currentText
            }
            val editor = before + replacement + after
            return LiveNoteFirstWrite(binding, editor, LiveNoteRange(index, index + replacement.length), editor != fileText)
        }
        // Processing or a template reshaped the entry: keep the file and add what came after.
        val editor = when {
            currentText.trimEnd() == submitted -> fileText
            currentText.startsWith(submitted) -> fileText.trimEnd() + currentText.removePrefix(submitted).trimEnd() + "\n"
            else -> fileText.trimEnd() + "\n\n" + currentText.trimEnd() + "\n"
        }
        return LiveNoteFirstWrite(binding, editor, null, editor != fileText)
    }

    /** A line-level summary of what changed elsewhere: lines theirs added, then lines removed. */
    fun summarizeChange(base: String, theirs: String, limit: Int = 3): List<LiveNoteDiffLine> {
        val baseLines = base.lines().filter(String::isNotBlank)
        val theirLines = theirs.lines().filter(String::isNotBlank)
        val remainingBase = baseLines.groupingBy { it }.eachCount().toMutableMap()
        val added = theirLines.filter { line ->
            val count = remainingBase[line] ?: 0
            if (count > 0) { remainingBase[line] = count - 1; false } else true
        }
        val remainingTheirs = theirLines.groupingBy { it }.eachCount().toMutableMap()
        val removed = baseLines.filter { line ->
            val count = remainingTheirs[line] ?: 0
            if (count > 0) { remainingTheirs[line] = count - 1; false } else true
        }
        return (added.map { LiveNoteDiffLine(LiveNoteDiffKind.ADDED, it.trim()) } +
            removed.map { LiveNoteDiffLine(LiveNoteDiffKind.REMOVED, it.trim()) }).take(limit)
    }

    private fun changedElsewhere(binding: LiveNoteBinding, localText: String, current: LiveNoteFile): LiveNoteSyncOutcome =
        if (localText == binding.savedText) {
            LiveNoteSyncOutcome.Reloaded(binding.copy(version = current.version, savedText = current.text), current.text)
        } else {
            LiveNoteSyncOutcome.Conflicted(LiveNoteConflict(current, localText, summarizeChange(binding.savedText, current.text)))
        }
}

/** Path planning shown before the first write ("Inbox/{title}.md") and the append decision. */
object LiveNotePlan {
    fun isAppendTarget(preset: CapturePreset?, route: CaptureRouteOverride?): Boolean =
        route?.relativeNotePath != null || (preset != null && preset.noteTargetKind != CaptureNoteTargetKind.NEW_NOTE)

    /** Where an entry lands inside the file: append presets search for the last occurrence. */
    fun prefersLastOccurrence(preset: CapturePreset?, route: CaptureRouteOverride?): Boolean {
        val placement = route?.placement ?: preset?.placement ?: CapturePlacementKind.APPEND
        return placement != CapturePlacementKind.PREPEND
    }

    fun plannedPath(preset: CapturePreset?, route: CaptureRouteOverride?): String? {
        route?.relativeNotePath?.takeIf(String::isNotBlank)?.let { return it }
        preset ?: return null
        if (preset.noteTargetKind == CaptureNoteTargetKind.EXISTING_NOTE) return preset.existingNotePath.takeIf(String::isNotBlank)
        val name = preset.noteNameTemplate.trim().ifEmpty { "{title}" }
        val file = if (name.endsWith(".md", ignoreCase = true)) name else "$name.md"
        return listOf(preset.logicalFolder.trim('/'), file).filter(String::isNotBlank).joinToString("/")
    }

    /** "<name> (Vox).md", then "<name> (Vox 2).md" … for the first free name. */
    fun copyName(fileName: String, occupied: Set<String>): String {
        val base = fileName.removeMarkdownExtension()
        val first = "$base (Vox).md"
        if (first !in occupied) return first
        var index = 2
        while ("$base (Vox $index).md" in occupied) index += 1
        return "$base (Vox $index).md"
    }
}

private fun String.removeMarkdownExtension(): String =
    if (endsWith(".md", ignoreCase = true)) dropLast(3) else this

/** One row of the Files tree: a folder or file directly inside a vault folder. */
data class VaultEntry(
    val name: String,
    /** Vault-relative path ("Daily/2026-11-13.md"). */
    val relativePath: String,
    val isFolder: Boolean,
    val lastModifiedEpochMillis: Long? = null,
    val byteCount: Long? = null,
    /** Direct children, for folders whose listing was counted. */
    val childCount: Int? = null,
) {
    val isMarkdown: Boolean get() = !isFolder && name.endsWith(".md", ignoreCase = true)
}

sealed interface VaultListing {
    data class Listed(val entries: List<VaultEntry>) : VaultListing
    data object Missing : VaultListing
    data class Unreachable(val reason: String) : VaultListing
}

/** Read-only listings of a vault (SAF has no change notifications: callers refresh on resume). */
interface VaultBrowser {
    suspend fun list(destination: CaptureDestination, relativeFolder: String, countChildren: Boolean = true): VaultListing
}

/** Files-tab ordering and the preset badges drawn on the folder or file each preset writes to. */
object VaultTree {
    /** Folders first, then files newest first; dot-files are hidden. */
    fun sorted(entries: List<VaultEntry>): List<VaultEntry> = entries
        .filterNot { it.name.startsWith(".") }
        .sortedWith(
            compareByDescending<VaultEntry> { it.isFolder }
                .thenComparator { a, b ->
                    if (a.isFolder && b.isFolder) a.name.compareTo(b.name, ignoreCase = true)
                    else (b.lastModifiedEpochMillis ?: 0L).compareTo(a.lastModifiedEpochMillis ?: 0L)
                },
        )

    /** The vault-relative folder or file a preset writes to, for presets that use [destination]. */
    fun presetTargets(presets: List<CapturePreset>, destination: CaptureDestination?): Map<String, List<CapturePreset>> =
        presets.filter { it.isEnabled && (it.destination == null || it.destination.id == destination?.id) }
            .mapNotNull { preset ->
                val target = when (preset.noteTargetKind) {
                    CaptureNoteTargetKind.EXISTING_NOTE -> preset.existingNotePath.trim('/')
                    else -> preset.logicalFolder.trim('/')
                }
                target.takeIf(String::isNotBlank)?.let { it to preset }
            }
            .groupBy({ it.first }, { it.second })

    fun matches(entry: VaultEntry, query: String): Boolean =
        query.isBlank() || entry.name.contains(query.trim(), ignoreCase = true)
}

/** Finds an embedded file (audio, image, video) in a vault for the live preview. */
interface VaultMediaResolver {
    /**
     * Returns a readable content URI for the first of [candidates] (vault-relative paths) that
     * exists, else for a file named [fileName] found by a bounded search of the vault.
     */
    suspend fun resolveMedia(destinationID: String, treeUri: String, candidates: List<String>, fileName: String): String?
}
