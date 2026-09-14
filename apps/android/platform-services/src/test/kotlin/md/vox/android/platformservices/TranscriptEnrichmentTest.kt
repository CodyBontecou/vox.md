package md.vox.android.platformservices

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscriptEnrichmentTest {
    @Test fun derivesGroundedMetadataDeterministically() {
        val result = DeterministicTranscriptEnrichment.enrich(
            "Meeting discussed launch launch timeline. Maya should send launch copy tomorrow.",
        )

        assertEquals("Meeting discussed launch launch timeline.", result.title)
        assertEquals("Tasks", result.category)
        assertEquals("launch", result.tags.first())
        assertTrue(result.tags.all { it in "meeting discussed launch timeline maya should send copy tomorrow" })
    }
}
