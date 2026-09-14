package md.vox.android

import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureSubmitResult
import md.vox.android.capturedomain.WearRemoteRecordingPhase
import md.vox.android.platformservices.RecordingTranscriptionPhase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WearRemoteDeliveryPolicyTest {
    @Test
    fun transcriptionLifecyclePublishesOnlyTheGovernedRemotePhases() {
        assertEquals(WearRemoteRecordingPhase.QUEUED, remotePhaseForTranscription(RecordingTranscriptionPhase.QUEUED))
        assertEquals(WearRemoteRecordingPhase.TRANSCRIBING, remotePhaseForTranscription(RecordingTranscriptionPhase.PROCESSING))
        assertEquals(WearRemoteRecordingPhase.TRANSCRIBING, remotePhaseForTranscription(RecordingTranscriptionPhase.FINALIZING))
        assertNull(remotePhaseForTranscription(RecordingTranscriptionPhase.COMPLETED))
        assertEquals(WearRemoteRecordingPhase.FAILED, remotePhaseForTranscription(RecordingTranscriptionPhase.FAILED))
        assertEquals(WearRemoteRecordingPhase.DISCARDED, remotePhaseForTranscription(RecordingTranscriptionPhase.DISCARDED))
    }

    @Test
    fun deliveryResultsUseContentFreeRemoteStatesAndRetainDurableFailures() {
        val delivered = CaptureSubmitResult.Delivered("request")
        val retry = CaptureSubmitResult.SavedForRetry("request", "providerUnavailable")
        val unpersisted = CaptureSubmitResult.SavedForRetry("request", "audioPreparationFailed", durablySaved = false)

        assertTrue(recordingCaptureWasAccepted(delivered))
        assertTrue(recordingCaptureWasAccepted(retry))
        assertFalse(recordingCaptureWasAccepted(unpersisted))
        assertEquals(WearRemoteRecordingPhase.DELIVERED, remotePhaseForCaptureResult(delivered))
        assertEquals(WearRemoteRecordingPhase.FAILED, remotePhaseForCaptureResult(retry))
        assertEquals("providerUnavailable", remoteMessageForCaptureResult(retry))
        assertEquals("invalidCapture", remoteMessageForCaptureResult(CaptureSubmitResult.InvalidInput("secret transcript")))
    }

    @Test
    fun journalLifecycleTerminatesWatchStorageOnlyForCompletionOrDiscard() {
        val inFlight = listOf(
            CaptureState.QUEUED,
            CaptureState.PREPARING,
            CaptureState.MATERIALIZED,
            CaptureState.COMMITTING,
            CaptureState.UNKNOWN_OUTCOME,
        )
        val failed = listOf(
            CaptureState.RETRYABLE_FAILURE,
            CaptureState.NEEDS_PERMISSION,
            CaptureState.NEEDS_USER_ACTION,
            CaptureState.PERMANENT_FAILURE,
        )

        inFlight.forEach { assertEquals(WearRemoteRecordingPhase.DELIVERING, remotePhaseForCaptureState(it)) }
        failed.forEach { assertEquals(WearRemoteRecordingPhase.FAILED, remotePhaseForCaptureState(it)) }
        assertEquals(WearRemoteRecordingPhase.DELIVERED, remotePhaseForCaptureState(CaptureState.COMPLETED))
        assertEquals(WearRemoteRecordingPhase.DISCARDED, remotePhaseForCaptureState(CaptureState.DISCARDED))
    }
}
