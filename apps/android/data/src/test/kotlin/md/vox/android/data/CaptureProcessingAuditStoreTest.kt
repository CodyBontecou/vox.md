package md.vox.android.data

import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureTextProcessingOutcome
import md.vox.android.capturedomain.CaptureTextProcessingResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class CaptureProcessingAuditStoreTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `round trips lossless processing audit and deletes it`() {
        val store = CaptureProcessingAuditStore(temporaryFolder.newFolder("audit"))
        val requestID = "123e4567-e89b-42d3-a456-426614174000"
        val result = CaptureTextProcessingResult(
            originalText = "raw   words",
            processedText = "Raw words.",
            mode = CaptureProcessingMode.CLEAN,
            outcome = CaptureTextProcessingOutcome.APPLIED,
            notice = null,
        )

        assertTrue(store.save(requestID, 42L, "default", 3, null, result))
        val loaded = requireNotNull(store.load(requestID))
        assertEquals("raw   words", loaded.originalText)
        assertEquals("Raw words.", loaded.processedText)
        assertEquals(CaptureTextProcessingOutcome.APPLIED, loaded.outcome)
        assertTrue(store.delete(requestID))
        assertNull(store.load(requestID))
    }

    @Test
    fun `rejects invalid identifiers without creating a file`() {
        val directory = temporaryFolder.newFolder("audit-invalid")
        val store = CaptureProcessingAuditStore(directory)
        val result = CaptureTextProcessingResult(
            originalText = "a",
            processedText = "A.",
            mode = CaptureProcessingMode.CLEAN,
            outcome = CaptureTextProcessingOutcome.APPLIED,
        )

        assertFalse(store.save("../outside", 42L, "default", 1, null, result))
        assertEquals(emptyList<String>(), directory.list()?.toList())
    }
}
