package md.vox.android.platformservices

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Test

class VoiceAutoStopTest {
    @Test fun silenceCannotStopBeforeMeaningfulSpeech() {
        val detector = VoicePauseDetector(750)
        repeat(20) { assertEquals(VoicePauseEvent.NONE, detector.accept(0.001f, 100)) }
    }

    @Test fun sustainedSpeechThenConfiguredPauseEndsSpeech() {
        val detector = VoicePauseDetector(750)
        repeat(3) { assertEquals(VoicePauseEvent.NONE, detector.accept(0.08f, 100)) }
        repeat(7) { assertEquals(VoicePauseEvent.NONE, detector.accept(0.001f, 100)) }
        assertEquals(VoicePauseEvent.END_OF_SPEECH, detector.accept(0.001f, 50))
        detector.reset()
        assertEquals(VoicePauseEvent.NONE, detector.accept(0.001f, 1_000))
    }

    @Test fun pauseDurationIsBoundedAndPersistentModeKeepsDetectedThoughtsSeparate() {
        assertEquals(500, VoiceAutoStopSettings(pauseDurationMillis = 1).normalized().pauseDurationMillis)
        assertEquals(2_000, VoiceAutoStopSettings(pauseDurationMillis = 9_999).normalized().pauseDurationMillis)
        val chunks = (0..4).map { File("chunk-${it.toString().padStart(6, '0')}.pcm") }
        assertEquals(
            listOf(listOf(chunks[0], chunks[1]), listOf(chunks[2], chunks[3]), listOf(chunks[4])),
            groupRecordingChunks(chunks, setOf(2, 4)),
        )
    }
}
