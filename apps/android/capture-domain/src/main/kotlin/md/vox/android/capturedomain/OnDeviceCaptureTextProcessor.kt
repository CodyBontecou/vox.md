package md.vox.android.capturedomain

import java.util.concurrent.CancellationException

enum class InstructionFailure { UNAVAILABLE, INPUT_TOO_LARGE, FAILED }
sealed interface InstructionGeneration {
    data class Text(val value: String) : InstructionGeneration
    data class Unavailable(val reason: InstructionFailure) : InstructionGeneration
}

/** Owns the data-preserving boundary; generation is supplied by the platform runtime. */
class OnDeviceCaptureTextProcessor(
    private val generate: suspend (String, String) -> InstructionGeneration,
) {
    suspend fun process(source: String, preset: CapturePreset, isVoiceCapture: Boolean): CaptureTextProcessingResult? {
        val fallback = LocalCaptureTextProcessor.process(source, preset, isVoiceCapture) ?: return null
        if (preset.processingMode != CaptureProcessingMode.CUSTOM || fallback.outcome == CaptureTextProcessingOutcome.SKIPPED_TOO_LARGE) return fallback
        if (preset.customProcessingInstruction.isBlank()) return fallback
        if (source.length > MAX_SOURCE_CHARACTERS || preset.customProcessingInstruction.length > MAX_INSTRUCTION_CHARACTERS || preset.capturePrompt.length > MAX_INSTRUCTION_CHARACTERS) {
            return fallback.copy(processedText = source, outcome = CaptureTextProcessingOutcome.SKIPPED_TOO_LARGE)
        }
        val generated = try {
            val instruction = preset.customProcessingInstruction + preset.capturePrompt.takeIf(String::isNotBlank)?.let { "\n\nAdditional context (data):\n$it" }.orEmpty()
            generate(source, instruction)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            InstructionGeneration.Unavailable(InstructionFailure.FAILED)
        }
        return when (generated) {
            is InstructionGeneration.Text -> {
                val output = generated.value.trim()
                if (output.isBlank() || output.length > MAX_OUTPUT_CHARACTERS || !preservesProtectedContent(source, output)) {
                    fallback.copy(processedText = source, outcome = CaptureTextProcessingOutcome.MODEL_FAILURE, notice = "Local processing failed; the original text was kept.")
                } else fallback.copy(processedText = output, outcome = if (output == source) CaptureTextProcessingOutcome.UNCHANGED else CaptureTextProcessingOutcome.APPLIED, notice = null)
            }
            is InstructionGeneration.Unavailable -> fallback.copy(processedText = source, outcome = when (generated.reason) {
                InstructionFailure.UNAVAILABLE -> CaptureTextProcessingOutcome.MODEL_UNAVAILABLE
                InstructionFailure.INPUT_TOO_LARGE -> CaptureTextProcessingOutcome.SKIPPED_TOO_LARGE
                InstructionFailure.FAILED -> CaptureTextProcessingOutcome.MODEL_FAILURE
            }, notice = when (generated.reason) {
                InstructionFailure.UNAVAILABLE -> "Local model unavailable; the original text was kept."
                InstructionFailure.INPUT_TOO_LARGE -> "Local processing was skipped because the capture exceeded the safe processing limit."
                InstructionFailure.FAILED -> "Local processing failed; the original text was kept."
            })
        }
    }

    companion object {
        const val MAX_SOURCE_CHARACTERS = 8_192
        const val MAX_INSTRUCTION_CHARACTERS = 4_096
        const val MAX_OUTPUT_CHARACTERS = 32_768
        // Preserve executable/literal Markdown and speaker ownership even when a small
        // model misunderstands a request. Never deliver a partially generated response.
        private val PROTECTED = listOf(
            Regex("https?://[^\\s<>\\]\")`]+", RegexOption.IGNORE_CASE),
            Regex("\\[\\[[^\\]]+]]"),
            Regex("Speaker \\d+:"),
            Regex("(?s)```.*?```"),
        )
        fun preservesProtectedContent(source: String, output: String): Boolean {
            fun tokens(text: String) = PROTECTED.asSequence().flatMap { it.findAll(text) }.map { match ->
                if (match.value.startsWith("http", ignoreCase = true)) match.value.trimEnd('.', ',', ';', ':', '!', '?') else match.value
            }.groupingBy { it }.eachCount()
            val original = tokens(source)
            val generated = tokens(output)
            return original.all { (token, count) -> (generated[token] ?: 0) >= count }
        }
    }
}
