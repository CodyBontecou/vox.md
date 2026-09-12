package md.vox.android.platformservices

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AudioCaptureTest {
    @Test
    fun pcmMeterUsesThePeakSignedSixteenBitSample() {
        assertEquals(0f, pcmLevel(byteArrayOf(0, 0, 0, 0), 4))
        assertTrue(pcmLevel(byteArrayOf(0xff.toByte(), 0x7f), 2) > 0.99f)
    }

    @Test
    fun phasesExposeOnlyLiveCaptureAsActive() {
        assertTrue(RecordingStatus(phase = RecordingPhase.RECORDING).isActive)
        assertTrue(RecordingStatus(phase = RecordingPhase.PAUSED).isActive)
        assertFalse(RecordingStatus(phase = RecordingPhase.INTERRUPTED).isActive)
        assertFalse(RecordingStatus(phase = RecordingPhase.COMPLETED).isActive)
    }

    @Test
    fun notificationElapsedTimeIsStable() {
        assertEquals("0:00", formatElapsed(0))
        assertEquals("1:05", formatElapsed(65_999))
    }

    @Test
    fun aPersistedLiveRecordingBecomesAnInterruptedRecoveryChoice() {
        val live = RecordingStatus(
            sessionID = "21c56d70-e82a-4b4c-b97b-329f2f85cf2f",
            phase = RecordingPhase.RECORDING,
            elapsedMillis = 2_500,
            level = 0.8f,
            chunkCount = 1,
        )

        assertEquals(
            live.copy(phase = RecordingPhase.INTERRUPTED, level = 0f, failureCode = "processInterrupted"),
            recoverInterruptedRecording(live),
        )
        assertEquals(
            live.copy(phase = RecordingPhase.PAUSED),
            recoverInterruptedRecording(live.copy(phase = RecordingPhase.PAUSED)),
        )
    }
}
