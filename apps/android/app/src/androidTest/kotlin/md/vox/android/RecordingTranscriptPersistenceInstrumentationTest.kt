package md.vox.android

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.util.UUID
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingTranscriptionClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RecordingTranscriptPersistenceInstrumentationTest {
    @Test
    fun transcriptEditsPersistRawCleanedTitleTagsAndCategoryAcrossReload() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val sessionID = UUID.randomUUID().toString().lowercase()
        val directory = File(context.noBackupFilesDir, "recordings/$sessionID")
        val client = RecordingTranscriptionClient.get(context)
        try {
            writeFixture(directory, "original raw")
            client.reload()

            assertTrue(
                client.updateTranscriptDetails(
                    sessionID = sessionID,
                    transcript = " corrected raw words ",
                    cleanedTranscript = " Corrected clean text. ",
                    title = " Edited title ",
                    tags = listOf(" reviewed ", "launch", "reviewed"),
                    category = " Meeting ",
                ),
            )
            client.reload()

            val saved = requireNotNull(client.states.value[sessionID])
            assertEquals("corrected raw words", saved.transcript)
            assertEquals("Corrected clean text.", saved.cleanedTranscript)
            assertEquals("Corrected clean text.", saved.preferredTranscript)
            assertEquals("Edited title", saved.title)
            assertEquals(listOf("reviewed", "launch"), saved.tags)
            assertEquals("Meeting", saved.category)
            assertEquals("corrected raw words", File(directory, "transcript.txt").readText())
            assertEquals("Corrected clean text.", File(directory, "transcript-cleaned.txt").readText())

            assertTrue(client.updateTranscriptDetails(sessionID, "raw only", "", "", emptyList(), ""))
            client.reload()
            val rawOnly = requireNotNull(client.states.value[sessionID])
            assertEquals("raw only", rawOnly.preferredTranscript)
            assertNull(rawOnly.cleanedTranscript)
            assertFalse(File(directory, "transcript-cleaned.txt").exists())
        } finally {
            directory.deleteRecursively()
            client.reload()
        }
    }

    @Test
    fun clearingASelectedTranscriptLeavesOtherLocalHistoryUntouched() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val selectedID = UUID.randomUUID().toString().lowercase()
        val retainedID = UUID.randomUUID().toString().lowercase()
        val selected = File(context.noBackupFilesDir, "recordings/$selectedID")
        val retained = File(context.noBackupFilesDir, "recordings/$retainedID")
        val client = RecordingTranscriptionClient.get(context)
        try {
            writeFixture(selected, "filtered match")
            writeFixture(retained, "must remain")
            client.reload()

            client.clear(selectedID)
            client.reload()

            assertFalse(File(selected, "transcription.properties").exists())
            assertFalse(File(selected, "transcript.txt").exists())
            assertFalse(client.states.value.containsKey(selectedID))
            assertEquals("must remain", client.states.value[retainedID]?.transcript)
        } finally {
            selected.deleteRecursively()
            retained.deleteRecursively()
            client.reload()
        }
    }

    @Test
    fun reassigningFrozenPresetPersistsAndDeleteRemovesOnlyTheSelectedRecording() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val selectedID = UUID.randomUUID().toString().lowercase()
        val retainedID = UUID.randomUUID().toString().lowercase()
        val selected = File(context.noBackupFilesDir, "recordings/$selectedID")
        val retained = File(context.noBackupFilesDir, "recordings/$retainedID")
        val captureClient = AudioCaptureClient(context)
        val reassigned = preset("Reassigned")
        try {
            writeRecordingFixture(selected, selectedID)
            writeRecordingFixture(retained, retainedID)

            assertTrue(captureClient.reassignPreset(selectedID, reassigned))
            assertEquals(reassigned, captureClient.frozenPreset(selectedID))
            assertTrue(captureClient.deleteRecording(selectedID))
            assertFalse(selected.exists())
            assertTrue(retained.isDirectory)
            assertTrue(captureClient.recordings().any { it.sessionID == retainedID })
        } finally {
            selected.deleteRecursively()
            retained.deleteRecursively()
        }
    }

    private fun writeFixture(directory: File, transcript: String) {
        assertTrue(directory.mkdirs())
        File(directory, "transcription.properties").writeText(
            """version=5
phase=COMPLETED
progress=1.0
modelID=local-model
modelName=Local Model
languageTag=en-US
durationMillis=12000
recordedAtEpochMillis=1700000000000
completedAtEpochMillis=1700000012000
failureCode=
addedToDraft=false
speakerCount=0
""",
        )
        File(directory, "transcript.txt").writeText(transcript)
    }

    private fun writeRecordingFixture(directory: File, sessionID: String) {
        assertTrue(directory.mkdirs())
        File(directory, "session.properties").writeText(
            """version=1
sessionID=$sessionID
phase=INTERRUPTED
createdAtEpochMillis=1700000000000
elapsedMillis=12000
chunkCount=1
failureCode=
sampleRate=16000
channelCount=1
encoding=pcm16le
""",
        )
        File(directory, "chunk-000000.pcm").writeBytes(byteArrayOf(0, 0))
    }

    private fun preset(name: String) = CapturePreset(
        id = UUID.randomUUID().toString().lowercase(),
        name = name,
        symbol = "book",
        revision = 1,
        logicalFolder = "Journal",
        noteNameTemplate = "{date}",
        metadataFields = emptyList(),
    )
}
