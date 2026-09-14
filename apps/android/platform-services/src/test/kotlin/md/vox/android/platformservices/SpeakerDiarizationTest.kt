package md.vox.android.platformservices

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SpeakerDiarizationTest {
    @Test fun clustersSimilarVectorsAndLabelsDistinctSpeakersWithoutDroppingText() {
        val first = DoubleArray(16).also { it[0] = 1.0 }
        val same = DoubleArray(16).also { it[0] = 0.98; it[1] = 0.02 }
        val second = DoubleArray(16).also { it[1] = 1.0 }

        val result = LocalSpeakerDiarizer.diarize(
            observations = listOf(
                SpeakerObservation("hello", first, 200, 0),
                SpeakerObservation("there", same, 200, 0),
                SpeakerObservation("good morning", second, 200, 0),
            ),
            fallbackTranscript = "hello there good morning",
        )

        assertEquals(2, result.speakerCount)
        assertEquals("Speaker 1: hello there\n\nSpeaker 2: good morning", result.transcript)
        assertNull(result.skipReason)
    }

    @Test fun shortUnlabeledTurnsFollowNearbySpeakerAndRemainInTranscript() {
        val voice = DoubleArray(16).also { it[3] = 1.0 }
        val result = LocalSpeakerDiarizer.diarize(
            listOf(
                SpeakerObservation("brief intro", null, 0, 0),
                SpeakerObservation("long enough", voice, 180, 0),
            ),
            "brief intro long enough",
        )

        assertEquals(1, result.speakerCount)
        assertEquals("Speaker 1: brief intro long enough", result.transcript)
    }

    @Test fun fallsBackLosslesslyWhenNoReliableSpeakerVectorExists() {
        val original = "keep every recognized word"
        val result = LocalSpeakerDiarizer.diarize(
            listOf(SpeakerObservation(original, DoubleArray(16) { 1.0 }, 20, 0)),
            original,
        )

        assertEquals(original, result.transcript)
        assertEquals(0, result.speakerCount)
        assertTrue(result.skipReason?.contains("normal transcript") == true)
    }
}
