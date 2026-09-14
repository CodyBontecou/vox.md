package md.vox.android

import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutomaticTranscriptionPolicyTest {
    @Test
    fun completedRecordingWithSelectedModelStartsOnlyWithoutAnExistingJob() {
        val completed = RecordingStatus(sessionID = "recording", phase = RecordingPhase.COMPLETED, chunkCount = 1)

        assertTrue(shouldStartAutomaticTranscription(completed, null, hasSelectedModel = true))
        assertFalse(
            shouldStartAutomaticTranscription(
                completed,
                RecordingTranscriptionPhase.PROCESSING,
                hasSelectedModel = true,
            ),
        )
        assertFalse(
            shouldStartAutomaticTranscription(
                completed,
                RecordingTranscriptionPhase.COMPLETED,
                hasSelectedModel = true,
            ),
        )
    }

    @Test
    fun missingModelOrIncompleteRecordingNeverStarts() {
        val completed = RecordingStatus(sessionID = "recording", phase = RecordingPhase.COMPLETED, chunkCount = 1)
        val active = completed.copy(phase = RecordingPhase.RECORDING)

        assertFalse(shouldStartAutomaticTranscription(completed, null, hasSelectedModel = false))
        assertFalse(shouldStartAutomaticTranscription(active, null, hasSelectedModel = true))
        assertFalse(shouldStartAutomaticTranscription(RecordingStatus(), null, hasSelectedModel = true))
    }
}
