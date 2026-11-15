package md.vox.android

import md.vox.android.platformservices.RecordingPhase
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CaptureComposerRecordingStatusTest {
    @Test
    fun recordingStatusHoldsTheTranscriptLineUntilWordsArrive() {
        assertEquals(voxUiText("Listening for speech…"), composerRecordingStatusUiText("", RecordingPhase.RECORDING))
        assertEquals(voxUiText("Paused"), composerRecordingStatusUiText("", RecordingPhase.PAUSED))
        assertNull(composerRecordingStatusUiText("Hello", RecordingPhase.RECORDING))
        assertNull(composerRecordingStatusUiText("Hello", RecordingPhase.PAUSED))
    }

    @Test
    fun recordingStatusClearsWhenNoRecordingIsRunning() {
        RecordingPhase.entries
            .filterNot { it == RecordingPhase.RECORDING || it == RecordingPhase.PAUSED }
            .forEach { assertNull(it.name, composerRecordingStatusUiText("", it)) }
    }
}
