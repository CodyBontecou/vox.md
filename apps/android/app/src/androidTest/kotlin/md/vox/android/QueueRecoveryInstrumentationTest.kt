package md.vox.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class QueueRecoveryInstrumentationTest {
    private val context = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun relaunchRecoversEveryOrphanAndInterruptedFinalizationWithoutDeletingAudio() {
        val recordingID = "71000000-0000-4000-8000-000000000001"
        val orphanID = "71000000-0000-4000-8000-000000000002"
        val pausedID = "71000000-0000-4000-8000-000000000003"
        val finalizingID = "71000000-0000-4000-8000-000000000004"
        val ids = listOf(recordingID, orphanID, pausedID, finalizingID)
        val root = File(context.noBackupFilesDir, "recordings").apply { mkdirs() }
        try {
            writeRecording(root, recordingID, RecordingPhase.RECORDING, 4_000)
            writeRecording(root, orphanID, RecordingPhase.RECORDING, 3_000)
            writeRecording(root, pausedID, RecordingPhase.PAUSED, 2_000)
            writeRecording(root, finalizingID, RecordingPhase.COMPLETED, 1_000)
            File(root, "latest-session-id").writeText(recordingID)
            File(root, "$finalizingID/transcription.properties").writeText(
                "version=5\nphase=FINALIZING\nprogress=1.0\n",
            )

            val client = AudioCaptureClient(context)
            val recordings = client.recordings().filter { it.sessionID in ids }.associateBy { it.sessionID }

            assertEquals(RecordingPhase.INTERRUPTED, recordings.getValue(recordingID).phase)
            assertEquals("processInterrupted", recordings.getValue(recordingID).failureCode)
            assertEquals(RecordingPhase.INTERRUPTED, recordings.getValue(orphanID).phase)
            assertEquals("processInterrupted", recordings.getValue(orphanID).failureCode)
            assertEquals(RecordingPhase.PAUSED, recordings.getValue(pausedID).phase)
            ids.forEach { id -> assertTrue(File(root, "$id/chunk-000000.pcm").isFile) }

            val transcription = RecordingTranscriptionClient.get(context)
            transcription.reload()
            val recoveredFinalization = transcription.states.value.getValue(finalizingID)
            assertEquals(RecordingTranscriptionPhase.FAILED, recoveredFinalization.phase)
            assertEquals("processInterrupted", recoveredFinalization.failureCode)
            assertTrue(File(root, "$finalizingID/chunk-000000.pcm").isFile)
        } finally {
            ids.forEach { File(root, it).deleteRecursively() }
            if (File(root, "latest-session-id").readTextOrNull() in ids) File(root, "latest-session-id").delete()
        }
    }

    private fun writeRecording(root: File, id: String, phase: RecordingPhase, createdAt: Long) {
        val directory = File(root, id).apply { mkdirs() }
        File(directory, "chunk-000000.pcm").writeBytes(byteArrayOf(1, 0, 2, 0))
        File(directory, "session.properties").writeText(
            buildString {
                append("version=1\n")
                append("sessionID=").append(id).append('\n')
                append("phase=").append(phase.name).append('\n')
                append("createdAtEpochMillis=").append(createdAt).append('\n')
                append("elapsedMillis=1000\n")
                append("chunkCount=1\n")
                append("failureCode=\n")
                append("sampleRate=16000\n")
                append("channelCount=1\n")
                append("encoding=pcm16le\n")
            },
        )
    }

    private fun File.readTextOrNull(): String? = runCatching { readText().trim() }.getOrNull()
}
