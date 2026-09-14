package md.vox.android.platformservices

import org.junit.Assert.assertEquals
import org.junit.Test

class LiveSpeechTest {
    @Test fun mergesCommittedAndPartialTextWithoutSyntheticContent() {
        assertEquals("already final still speaking", mergeLiveSpeechText("already final", "still speaking"))
        assertEquals("still speaking", mergeLiveSpeechText("", "still speaking"))
        assertEquals("already final", mergeLiveSpeechText("already final", ""))
    }
}
