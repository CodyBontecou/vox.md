package md.vox.android.platformservices

import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/** Reconcile durable PCM before choosing the next index; never replace retained audio.
 * Called only without a live recorder, including sticky service recreation.
 */
internal fun recoverRecordingFiles(directory: File, status: RecordingStatus): RecordingStatus {
    if (status.phase !in setOf(RecordingPhase.RECORDING, RecordingPhase.PAUSED, RecordingPhase.INTERRUPTED)) return status
    return try {
        val chunks = directory.listFiles().orEmpty().filter { it.name.matches(Regex("chunk-[0-9]{6}\\.pcm")) }.sortedBy { it.name }
        check(chunks.size >= status.chunkCount) { "Missing finalized audio" }
        check(chunks.withIndex().all { (index, file) -> file.name == "chunk-${index.toString().padStart(6, '0')}.pcm" &&
            file.isFile && !Files.isSymbolicLink(file.toPath()) && file.length() % 2L == 0L })
        val parts = directory.listFiles().orEmpty().filter { it.name.matches(Regex("chunk-[0-9]{6}\\.pcm\\.part")) }
        check(parts.size <= 1)
        parts.singleOrNull()?.let { part ->
            check(part.name == "chunk-${chunks.size.toString().padStart(6, '0')}.pcm.part" && part.isFile &&
                !Files.isSymbolicLink(part.toPath()) && part.length() % 2L == 0L)
            if (part.length() == 0L) check(part.delete()) else {
                val target = File(directory, part.name.removeSuffix(".part"))
                check(!target.exists())
                java.io.FileOutputStream(part, true).use { it.fd.sync() }
                Files.move(part.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
            }
        }
        val retained = directory.listFiles().orEmpty().filter { it.name.matches(Regex("chunk-[0-9]{6}\\.pcm")) }
        recoverInterruptedRecording(status).copy(chunkCount = retained.size,
            elapsedMillis = retained.sumOf(File::length) * 1000L / 32_000L)
    } catch (_: Exception) {
        status.copy(phase = RecordingPhase.FAILED, level = 0f, failureCode = "recordingRecovery")
    }
}
