package md.vox.android.capturedomain

enum class CaptureTextProcessingOutcome {
    APPLIED,
    UNCHANGED,
    UNSUPPORTED_CUSTOM_INSTRUCTION,
    SKIPPED_TOO_LARGE,
}

data class CaptureTextProcessingResult(
    val originalText: String,
    val processedText: String,
    val mode: CaptureProcessingMode,
    val outcome: CaptureTextProcessingOutcome,
    val notice: String? = null,
)

/**
 * A deterministic, offline-safe fallback for preset processing.
 *
 * The processor only restructures text already present in the capture. It never calls a
 * network service, invents content, or silently applies an unsupported custom instruction.
 */
object LocalCaptureTextProcessor {
    const val MAX_PROCESSABLE_CHARACTERS = 65_536

    fun process(
        originalText: String,
        preset: CapturePreset,
        isVoiceCapture: Boolean,
    ): CaptureTextProcessingResult? {
        if (!preset.processingEnabled || preset.processingMode == CaptureProcessingMode.NONE || originalText.isBlank()) {
            return null
        }
        val scopeMatches = when (preset.processingScope) {
            CaptureProcessingScope.BOTH -> true
            CaptureProcessingScope.VOICE_ONLY -> isVoiceCapture
            CaptureProcessingScope.TEXT_ONLY -> !isVoiceCapture
        }
        if (!scopeMatches) return null
        if (originalText.length > MAX_PROCESSABLE_CHARACTERS) {
            return CaptureTextProcessingResult(
                originalText = originalText,
                processedText = originalText,
                mode = preset.processingMode,
                outcome = CaptureTextProcessingOutcome.SKIPPED_TOO_LARGE,
                notice = "Local processing was skipped because the capture exceeded the safe processing limit.",
            )
        }

        val transformation = when (preset.processingMode) {
            CaptureProcessingMode.NONE -> return null
            CaptureProcessingMode.CLEAN -> Transformation(clean(originalText))
            CaptureProcessingMode.TODO_LIST -> Transformation(todoList(originalText))
            CaptureProcessingMode.MEETING_NOTES -> Transformation(meetingNotes(originalText))
            CaptureProcessingMode.CUSTOM -> custom(originalText, preset.customProcessingInstruction)
        }
        val outcome = when {
            transformation.unsupported -> CaptureTextProcessingOutcome.UNSUPPORTED_CUSTOM_INSTRUCTION
            transformation.text == originalText -> CaptureTextProcessingOutcome.UNCHANGED
            else -> CaptureTextProcessingOutcome.APPLIED
        }
        return CaptureTextProcessingResult(
            originalText = originalText,
            processedText = transformation.text,
            mode = preset.processingMode,
            outcome = outcome,
            notice = transformation.notice,
        )
    }

    private data class Transformation(
        val text: String,
        val unsupported: Boolean = false,
        val notice: String? = null,
    )

    private fun clean(source: String): String {
        val cleanedLines = source.replace("\r\n", "\n").replace('\r', '\n').lines().map { rawLine ->
            val line = rawLine.trim().replace(HORIZONTAL_WHITESPACE, " ")
            if (line.isEmpty() || isMarkdownStructure(line)) {
                line
            } else {
                val capitalized = line.replaceFirstChar { character ->
                    if (character.isLowerCase()) character.titlecase() else character.toString()
                }
                if (capitalized.lastOrNull()?.isLetterOrDigit() == true) "$capitalized." else capitalized
            }
        }
        return cleanedLines.joinToString("\n").replace(EXCESS_BLANK_LINES, "\n\n").trim()
    }

    private fun todoList(source: String): String = meaningfulFragments(source).joinToString("\n") { fragment ->
        val existingTask = TASK_PREFIX.find(fragment)
        if (existingTask != null) {
            val checked = existingTask.groupValues[1].equals("x", ignoreCase = true)
            "- [${if (checked) "x" else " "}] ${fragment.substring(existingTask.range.last + 1).trim()}"
        } else {
            "- [ ] ${stripListPrefix(fragment)}"
        }
    }

    private fun bulletList(source: String): String = meaningfulFragments(source)
        .joinToString("\n") { "- ${stripListPrefix(it)}" }

    private fun meetingNotes(source: String): String {
        val fragments = meaningfulFragments(source)
        if (fragments.isEmpty()) return source
        val actionItems = fragments.filter(::looksLikeActionItem)
        return buildString {
            append("## Notes\n\n")
            fragments.forEach { append("- ").append(stripListPrefix(it)).append('\n') }
            if (actionItems.isNotEmpty()) {
                append("\n## Action Items\n\n")
                actionItems.forEach { append("- [ ] ").append(stripListPrefix(it)).append('\n') }
            }
        }.trimEnd()
    }

    private fun custom(source: String, instruction: String): Transformation {
        val normalized = instruction.trim().lowercase()
        return when {
            normalized.contains("checklist") || normalized.contains("todo list") || normalized.contains("task list") ->
                Transformation(todoList(source))
            normalized.contains("bullet list") || normalized == "use bullets" || normalized == "make bullets" ->
                Transformation(bulletList(source))
            normalized.contains("meeting notes") || normalized.contains("meeting-note") ->
                Transformation(meetingNotes(source))
            normalized.contains("clean") || normalized.contains("polish") || normalized.contains("punctuation") ->
                Transformation(clean(source))
            normalized == "uppercase" || normalized == "convert to uppercase" ->
                Transformation(source.uppercase())
            normalized == "lowercase" || normalized == "convert to lowercase" ->
                Transformation(source.lowercase())
            else -> Transformation(
                text = source,
                unsupported = true,
                notice = "This custom instruction is not supported by the offline processor, so the original text was kept.",
            )
        }
    }

    private fun meaningfulFragments(source: String): List<String> {
        val normalized = source.replace("\r\n", "\n").replace('\r', '\n').trim()
        if (normalized.isEmpty()) return emptyList()
        val lines = normalized.lines().map(String::trim).filter(String::isNotEmpty)
        if (lines.size > 1) return lines
        return normalized.split(SENTENCE_BOUNDARY).map(String::trim).filter(String::isNotEmpty)
    }

    private fun stripListPrefix(value: String): String = value
        .replaceFirst(TASK_PREFIX, "")
        .replaceFirst(LIST_PREFIX, "")
        .trim()

    private fun looksLikeActionItem(value: String): Boolean {
        val normalized = value.lowercase()
        return ACTION_MARKERS.any(normalized::contains)
    }

    private fun isMarkdownStructure(value: String): Boolean =
        value.startsWith("#") || value.startsWith("- ") || value.startsWith("* ") ||
            value.startsWith(">") || value.startsWith("```") || value.startsWith("[")

    private val ACTION_MARKERS = listOf(
        "action item", "todo", "to-do", "follow up", "follow-up", "need to", "needs to",
        "must ", "should ", "will ", "assigned to", "deadline", "due ",
    )
    private val HORIZONTAL_WHITESPACE = Regex("[\\t \\u00a0]+")
    private val EXCESS_BLANK_LINES = Regex("\\n{3,}")
    private val SENTENCE_BOUNDARY = Regex("(?<=[.!?])\\s+")
    private val TASK_PREFIX = Regex("^[-*+]\\s*\\[([ xX])]\\s*")
    private val LIST_PREFIX = Regex("^([-*+]\\s+|\\d+[.)]\\s+)")
}
