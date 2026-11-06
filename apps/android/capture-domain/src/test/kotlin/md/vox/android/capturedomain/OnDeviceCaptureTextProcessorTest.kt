package md.vox.android.capturedomain

import java.util.concurrent.CancellationException
import kotlin.coroutines.*
import org.junit.Assert.*
import org.junit.Test

class OnDeviceCaptureTextProcessorTest {
    @Test fun arbitraryInstructionsReachTheModelAndKeepTheOriginalAuditText() = immediate {
        var calls = 0
        val processor = OnDeviceCaptureTextProcessor { source, instruction ->
            calls++; assertEquals("Maya, Zoe, Arun", source); assertEquals("Sort these names alphabetically", instruction)
            InstructionGeneration.Text("Arun, Maya, Zoe")
        }
        val result = requireNotNull(processor.process("Maya, Zoe, Arun", preset(), false))
        assertEquals(1, calls); assertEquals("Maya, Zoe, Arun", result.originalText)
        assertEquals("Arun, Maya, Zoe", result.processedText); assertEquals(CaptureTextProcessingOutcome.APPLIED, result.outcome)
    }
    @Test fun missingOrFailedModelPreservesSourceInsteadOfApplyingAPartialKeywordMatch() = immediate {
        for (reason in InstructionFailure.entries) {
            val processor = OnDeviceCaptureTextProcessor { _, _ -> InstructionGeneration.Unavailable(reason) }
            val source = "keep   this Exactly"
            val result = requireNotNull(processor.process(source, preset("Clean this and translate to Spanish"), false))
            assertEquals(source, result.processedText); assertEquals(source, result.originalText)
            assertNotEquals(CaptureTextProcessingOutcome.APPLIED, result.outcome)
        }
    }
    @Test fun disabledWrongScopeBlankAndOversizedInputNeverStartInference() = immediate {
        val processor = OnDeviceCaptureTextProcessor { _, _ -> error("must not start") }
        assertNull(processor.process("text", preset().copy(processingEnabled = false), false))
        assertNull(processor.process("text", preset().copy(processingScope = CaptureProcessingScope.VOICE_ONLY), false))
        assertEquals(CaptureTextProcessingOutcome.UNSUPPORTED_CUSTOM_INSTRUCTION, processor.process("text", preset(""), false)!!.outcome)
        val source = "a".repeat(OnDeviceCaptureTextProcessor.MAX_SOURCE_CHARACTERS + 1)
        val result = processor.process(source, preset(), false)!!
        assertEquals(source, result.processedText); assertEquals(CaptureTextProcessingOutcome.SKIPPED_TOO_LARGE, result.outcome)
    }
    @Test fun lostLinksCodeWikiLinksOrRepeatedSpeakerOwnershipRejectTheEntireResponse() = immediate {
        val sources = listOf("See https://example.com/Exact?id=42", "Keep [[Launch]]", "```yaml\na: 1\n```", "Speaker 1: approve\nSpeaker 1: send")
        for (source in sources) {
            val processor = OnDeviceCaptureTextProcessor { _, _ -> InstructionGeneration.Text("rewritten without protected data") }
            val result = processor.process(source, preset(), false)!!
            assertEquals(source, result.processedText); assertEquals(CaptureTextProcessingOutcome.MODEL_FAILURE, result.outcome)
        }
        assertFalse(OnDeviceCaptureTextProcessor.preservesProtectedContent(sources.last(), "Speaker 1: approve and send"))
    }
    @Test fun sentencePunctuationAfterAUrlDoesNotMakeTheOriginalLinkDisappear() {
        assertTrue(OnDeviceCaptureTextProcessor.preservesProtectedContent("See https://example.com/Exact?id=42", "See https://example.com/Exact?id=42."))
        assertFalse(OnDeviceCaptureTextProcessor.preservesProtectedContent("See https://example.com/Exact?id=42", "See https://example.com/Exact?id=43."))
    }
    @Test fun markdownEmphasisDoesNotRemoveThePreservedSpeakerLabel() {
        assertTrue(OnDeviceCaptureTextProcessor.preservesProtectedContent("Speaker 1: words", "**Speaker 1:** words"))
    }
    @Test fun aNewCodeFenceCannotHidePreservedLinksOrSpeakerMarkersFromTheGuard() {
        assertTrue(OnDeviceCaptureTextProcessor.preservesProtectedContent("Speaker 1: See https://example.com/a", "```text\nSpeaker 1: See https://example.com/a\n```"))
        assertFalse(OnDeviceCaptureTextProcessor.preservesProtectedContent("Speaker 1: See https://example.com/a", "```text\nSpeaker 2: See https://example.com/a\n```"))
    }
    @Test fun emptyAndOversizedResponsesAreNotDelivered() = immediate {
        for (response in listOf(" ", "a".repeat(OnDeviceCaptureTextProcessor.MAX_OUTPUT_CHARACTERS + 1))) {
            val result = OnDeviceCaptureTextProcessor { _, _ -> InstructionGeneration.Text(response) }.process("original", preset(), true)!!
            assertEquals("original", result.processedText); assertEquals(CaptureTextProcessingOutcome.MODEL_FAILURE, result.outcome)
        }
    }
    @Test fun frozenPresetContextReachesTheModelWithoutChangingTheCaptureSource() = immediate {
        val processor = OnDeviceCaptureTextProcessor { source, instruction ->
            assertEquals("Keep this", source); assertTrue(instruction.contains("Maya is the owner"))
            InstructionGeneration.Text("Keep this for Maya")
        }
        assertEquals("Keep this", processor.process("Keep this",preset().copy(capturePrompt="Maya is the owner"),false)!!.originalText)
    }
    @Test fun cancellationPropagatesWithoutProducingADeliveryResult() {
        try { immediate { OnDeviceCaptureTextProcessor { _, _ -> throw CancellationException() }.process("original", preset(), false) }; fail() }
        catch (_: CancellationException) { }
    }
    private fun preset(instruction: String = "Sort these names alphabetically") = CapturePreset(
        id="abababab-abab-4bab-8bab-abababababab", name="Test", symbol="sparkles", revision=1,
        logicalFolder="Inbox", noteNameTemplate="capture-{id}", metadataFields=emptyList(),
        processingEnabled=true, processingMode=CaptureProcessingMode.CUSTOM, customProcessingInstruction=instruction)
    private fun <T> immediate(block: suspend () -> T): T {
        var outcome: Result<T>? = null
        block.startCoroutine(object : Continuation<T> { override val context = EmptyCoroutineContext
            override fun resumeWith(result: Result<T>) { outcome = result } })
        return requireNotNull(outcome).getOrThrow()
    }
}
