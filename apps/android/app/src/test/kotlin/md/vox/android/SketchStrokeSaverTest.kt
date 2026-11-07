package md.vox.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class SketchStrokeSaverTest {
    @Test fun strokesRoundTripThroughSavedState() {
        val strokes = listOf(
            listOf(SketchPoint(0.1f, 0.2f, 0.3f), SketchPoint(0.4f, 0.5f, 1f)),
            listOf(SketchPoint(0.9f, 0.8f, 0.5f)),
        )

        assertEquals(strokes, decodeSketchStrokes(encodeSketchStrokes(strokes)))
    }

    @Test fun emptySketchRoundTrips() {
        assertTrue(decodeSketchStrokes(encodeSketchStrokes(emptyList())).isEmpty())
    }
}
