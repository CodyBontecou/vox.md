package md.vox.android

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.runBlocking
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The composer's Discard promises "The audio and live transcript are deleted"; on Android it
 * only marked the session DISCARDED and kept its chunks (found in device QA, 2026-11-26).
 */
class ConfirmedRecordingDiscardTest {
    private val id = "4a01a88a-cf4c-45cb-bb27-600dfd5a6dff"

    @Test
    fun deletesTheAudioOnceTheRecorderMarksTheSessionDiscarded() = runBlocking {
        val status = MutableStateFlow(RecordingStatus(sessionID = id, phase = RecordingPhase.RECORDING, chunkCount = 17))
        val deleted = mutableListOf<String>()
        val result = ConfirmedRecordingDiscard.discard(
            sessionID = id,
            // The service publishes DISCARDED after flushing the last chunk.
            cancel = { status.value = status.value.copy(phase = RecordingPhase.DISCARDED) },
            status = status,
            deleteAudio = { deleted += it; true },
        )
        assertTrue(result)
        assertEquals(listOf(id), deleted)
    }

    @Test
    fun neverDeletesWhileTheSessionIsStillRecording() = runBlocking {
        val status = MutableStateFlow(RecordingStatus(sessionID = id, phase = RecordingPhase.RECORDING))
        var cancelled = 0
        val deleted = mutableListOf<String>()
        val result = ConfirmedRecordingDiscard.discard(
            sessionID = id,
            cancel = { cancelled += 1 },
            status = status,
            deleteAudio = { deleted += it; true },
            timeoutMillis = 50,
        )
        assertFalse(result)
        assertEquals(1, cancelled)
        assertTrue(deleted.isEmpty())
    }

    @Test
    fun anotherSessionBeingDiscardedIsNotThisOne() = runBlocking {
        val status = MutableStateFlow(RecordingStatus(sessionID = "other", phase = RecordingPhase.DISCARDED))
        val deleted = mutableListOf<String>()
        val result = ConfirmedRecordingDiscard.discard(
            sessionID = id,
            cancel = {},
            status = status,
            deleteAudio = { deleted += it; true },
            timeoutMillis = 50,
        )
        assertFalse(result)
        assertTrue(deleted.isEmpty())
    }

    @Test
    fun withoutASessionItStillCancelsButDeletesNothing() = runBlocking {
        var cancelled = 0
        val result = ConfirmedRecordingDiscard.discard(
            sessionID = null,
            cancel = { cancelled += 1 },
            status = MutableStateFlow(RecordingStatus()),
            deleteAudio = { error("nothing to delete") },
        )
        assertFalse(result)
        assertEquals(1, cancelled)
    }
}
