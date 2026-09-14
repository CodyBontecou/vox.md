package md.vox.android.platformservices

import org.junit.Assert.assertFalse
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordingJobPolicyTest {
    @Test fun processingPolicyRequiresTheDeclaredTrigger() {
        assertTrue(shouldProcessRecordingAutomatically(RecordingProcessingPolicy.IMMEDIATE, appIsIdle = false))
        assertFalse(shouldProcessRecordingAutomatically(RecordingProcessingPolicy.WHEN_IDLE, appIsIdle = false))
        assertTrue(shouldProcessRecordingAutomatically(RecordingProcessingPolicy.WHEN_IDLE, appIsIdle = true))
        assertFalse(shouldProcessRecordingAutomatically(RecordingProcessingPolicy.MANUAL, appIsIdle = true))
    }

    @Test
    fun `retention deadline supports immediate timed and permanent policies`() {
        assertEquals(
            1_000L,
            recordingRetentionDeadlineEpochMillis(
                RecordingJobPolicy(retention = RecordingRetentionKind.DELETE_AFTER_SUCCESS),
                1_000L,
            ),
        )
        assertEquals(
            61_000L,
            recordingRetentionDeadlineEpochMillis(
                RecordingJobPolicy(retention = RecordingRetentionKind.TIMED, retentionMillis = 60_000L),
                1_000L,
            ),
        )
        assertNull(
            recordingRetentionDeadlineEpochMillis(
                RecordingJobPolicy(retention = RecordingRetentionKind.PERMANENT),
                1_000L,
            ),
        )
    }

    @Test fun retentionNeverDeletesBeforeSuccessfulTranscription() {
        val immediate = RecordingJobPolicy(retention = RecordingRetentionKind.DELETE_AFTER_SUCCESS)
        assertFalse(shouldDeleteRecordingAudio(immediate, false, 100, 1_000_000))
        assertTrue(shouldDeleteRecordingAudio(immediate, true, 100, 100))
        val timed = RecordingJobPolicy(retention = RecordingRetentionKind.TIMED, retentionMillis = 60_000)
        assertFalse(shouldDeleteRecordingAudio(timed, true, 100, 60_099))
        assertTrue(shouldDeleteRecordingAudio(timed, true, 100, 60_100))
        assertFalse(shouldDeleteRecordingAudio(timed.copy(retention = RecordingRetentionKind.PERMANENT), true, 100, Long.MAX_VALUE))
    }
}
