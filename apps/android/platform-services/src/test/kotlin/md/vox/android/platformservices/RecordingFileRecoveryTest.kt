package md.vox.android.platformservices

import java.nio.file.Files
import org.junit.Assert.*
import org.junit.Test

class RecordingFileRecoveryTest {
    @Test fun finalizedChunkAheadOfManifestAndCheckpointedPartialArePreserved() {
        val directory = Files.createTempDirectory("recording-recovery").toFile()
        try {
            val first = ByteArray(64_000) { 23 }
            val second = ByteArray(64_000) { 45 }
            val partial = ByteArray(16_000) { 67 }
            directory.resolve("chunk-000000.pcm").writeBytes(first)
            directory.resolve("chunk-000001.pcm").writeBytes(second)
            directory.resolve("chunk-000002.pcm.part").writeBytes(partial)
            val recovered = recoverRecordingFiles(directory, RecordingStatus(phase = RecordingPhase.RECORDING, chunkCount = 1, elapsedMillis = 2100))
            assertEquals(RecordingPhase.INTERRUPTED, recovered.phase)
            assertEquals(3, recovered.chunkCount)
            assertEquals(4500L, recovered.elapsedMillis)
            assertArrayEquals(first, directory.resolve("chunk-000000.pcm").readBytes())
            assertArrayEquals(second, directory.resolve("chunk-000001.pcm").readBytes())
            assertArrayEquals(partial, directory.resolve("chunk-000002.pcm").readBytes())
            assertEquals(recovered, recoverRecordingFiles(directory, recovered))
        } finally { directory.deleteRecursively() }
    }

    @Test fun gapsAndConflictingPartialsFailClosedWithoutDeletingOrOverwritingAudio() {
        val directory = Files.createTempDirectory("recording-conflict").toFile()
        try {
            directory.resolve("chunk-000000.pcm").writeBytes(byteArrayOf(1, 2))
            directory.resolve("chunk-000000.pcm.part").writeBytes(byteArrayOf(3, 4))
            val status = RecordingStatus(phase = RecordingPhase.RECORDING)
            assertEquals(RecordingPhase.FAILED, recoverRecordingFiles(directory, status).phase)
            assertArrayEquals(byteArrayOf(1, 2), directory.resolve("chunk-000000.pcm").readBytes())
            assertArrayEquals(byteArrayOf(3, 4), directory.resolve("chunk-000000.pcm.part").readBytes())
            directory.resolve("chunk-000000.pcm.part").delete()
            directory.resolve("chunk-000002.pcm").writeBytes(byteArrayOf(5, 6))
            assertEquals(RecordingPhase.FAILED, recoverRecordingFiles(directory, status).phase)
            assertArrayEquals(byteArrayOf(5, 6), directory.resolve("chunk-000002.pcm").readBytes())
            directory.resolve("chunk-000002.pcm").delete()
            assertEquals(RecordingPhase.FAILED, recoverRecordingFiles(directory, status.copy(chunkCount = 2)).phase)
        } finally { directory.deleteRecursively() }
    }
}
