package md.vox.android.platformservices

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordingJobPhaseTest {
    @Test fun representsTheExactIosRecordingJobPhases() {
        assertEquals(
            listOf("QUEUED", "PROCESSING", "FINALIZING", "COMPLETED", "FAILED", "DISCARDED"),
            RecordingTranscriptionPhase.entries.map(RecordingTranscriptionPhase::name),
        )
    }

    @Test fun onlyCompletedAndDiscardedAreTerminal() {
        RecordingTranscriptionPhase.entries.forEach { phase ->
            assertEquals(
                phase in setOf(RecordingTranscriptionPhase.COMPLETED, RecordingTranscriptionPhase.DISCARDED),
                phase.isTerminal,
            )
        }
    }

    @Test fun lifecycleRequiresProcessingAndFinalizingBeforeCompletion() {
        assertTrue(recordingJobTransitionAllowed(null, RecordingTranscriptionPhase.QUEUED))
        assertTrue(recordingJobTransitionAllowed(RecordingTranscriptionPhase.QUEUED, RecordingTranscriptionPhase.PROCESSING))
        assertTrue(recordingJobTransitionAllowed(RecordingTranscriptionPhase.PROCESSING, RecordingTranscriptionPhase.FINALIZING))
        assertTrue(recordingJobTransitionAllowed(RecordingTranscriptionPhase.FINALIZING, RecordingTranscriptionPhase.COMPLETED))
        assertFalse(recordingJobTransitionAllowed(RecordingTranscriptionPhase.QUEUED, RecordingTranscriptionPhase.COMPLETED))
        assertFalse(recordingJobTransitionAllowed(RecordingTranscriptionPhase.COMPLETED, RecordingTranscriptionPhase.QUEUED))
        assertFalse(recordingJobTransitionAllowed(RecordingTranscriptionPhase.DISCARDED, RecordingTranscriptionPhase.QUEUED))
    }

    @Test fun failedJobsAreRecoverableAndDiscardedJobsRemainTerminal() {
        assertTrue(recordingJobTransitionAllowed(RecordingTranscriptionPhase.PROCESSING, RecordingTranscriptionPhase.FAILED))
        assertTrue(recordingJobTransitionAllowed(RecordingTranscriptionPhase.FAILED, RecordingTranscriptionPhase.QUEUED))
        assertTrue(recordingJobTransitionAllowed(RecordingTranscriptionPhase.PROCESSING, RecordingTranscriptionPhase.DISCARDED))
        assertFalse(recordingJobTransitionAllowed(RecordingTranscriptionPhase.DISCARDED, RecordingTranscriptionPhase.FAILED))
    }

    @Test fun legacyPhaseNamesMigrateWithoutRevivingTerminalJobs() {
        assertEquals(RecordingTranscriptionPhase.QUEUED, parseRecordingTranscriptionPhase("NOT_STARTED"))
        assertEquals(RecordingTranscriptionPhase.PROCESSING, parseRecordingTranscriptionPhase("TRANSCRIBING"))
        assertEquals(RecordingTranscriptionPhase.DISCARDED, parseRecordingTranscriptionPhase("CANCELLED"))
        assertEquals(RecordingTranscriptionPhase.FINALIZING, parseRecordingTranscriptionPhase("FINALIZING"))
    }
}
