package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LocalCaptureTextProcessorTest {
    @Test
    fun `none keeps the original deterministic text`() {
        val source = "Keep   this text exactly.\n- [x] Including Markdown"
        assertNull(
            LocalCaptureTextProcessor.process(
                source,
                preset(CaptureProcessingMode.NONE),
                isVoiceCapture = true,
            ),
        )
    }

    @Test
    fun `clean applies only to matching scope and preserves original`() {
        val preset = preset(CaptureProcessingMode.CLEAN).copy(processingScope = CaptureProcessingScope.VOICE_ONLY)

        assertNull(LocalCaptureTextProcessor.process("hello   world", preset, isVoiceCapture = false))
        val result = requireNotNull(LocalCaptureTextProcessor.process("hello   world", preset, isVoiceCapture = true))

        assertEquals("hello   world", result.originalText)
        assertEquals("Hello world.", result.processedText)
        assertEquals(CaptureTextProcessingOutcome.APPLIED, result.outcome)
    }

    @Test
    fun `todo mode produces grounded checklist without dropping lines`() {
        val result = requireNotNull(
            LocalCaptureTextProcessor.process(
                "Call Sam\n- [x] Send notes\nBook a room",
                preset(CaptureProcessingMode.TODO_LIST),
                isVoiceCapture = false,
            ),
        )

        assertEquals("- [ ] Call Sam\n- [x] Send notes\n- [ ] Book a room", result.processedText)
    }

    @Test
    fun `meeting mode creates action section only from matching source fragments`() {
        val result = requireNotNull(
            LocalCaptureTextProcessor.process(
                "Discussed launch date. Maya will send the final copy. Budget is unchanged.",
                preset(CaptureProcessingMode.MEETING_NOTES),
                isVoiceCapture = true,
            ),
        )

        assertTrue(result.processedText.contains("## Notes"))
        assertTrue(result.processedText.contains("- [ ] Maya will send the final copy."))
        assertTrue(result.processedText.contains("Budget is unchanged."))
    }

    @Test
    fun `unsupported custom instruction is visible and leaves text unchanged`() {
        val preset = preset(CaptureProcessingMode.CUSTOM).copy(customProcessingInstruction = "Rewrite as a sonnet")
        val result = requireNotNull(LocalCaptureTextProcessor.process("Keep every word", preset, isVoiceCapture = false))

        assertEquals("Keep every word", result.processedText)
        assertEquals(CaptureTextProcessingOutcome.UNSUPPORTED_CUSTOM_INSTRUCTION, result.outcome)
        assertTrue(result.notice.orEmpty().contains("not supported"))
    }

    @Test
    fun `supported custom instruction performs the requested grounded transformation`() {
        val preset = preset(CaptureProcessingMode.CUSTOM).copy(customProcessingInstruction = "Make a bullet list")
        val result = requireNotNull(
            LocalCaptureTextProcessor.process("First point. Second point.", preset, isVoiceCapture = false),
        )

        assertEquals("- First point.\n- Second point.", result.processedText)
        assertEquals(CaptureTextProcessingOutcome.APPLIED, result.outcome)
    }

    private fun preset(mode: CaptureProcessingMode) = CapturePreset(
        id = "default",
        name = "Default",
        symbol = "mic",
        revision = 1,
        logicalFolder = "",
        noteNameTemplate = "Capture",
        metadataFields = emptyList(),
        processingEnabled = true,
        processingMode = mode,
    )
}
