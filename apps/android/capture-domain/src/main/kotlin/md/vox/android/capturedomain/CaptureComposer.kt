package md.vox.android.capturedomain

import java.text.BreakIterator
import java.text.Normalizer
import java.util.Locale

data class CaptureTextSelection(val start: Int, val end: Int) {
    val minimum: Int get() = minOf(start, end)
    val maximum: Int get() = maxOf(start, end)
    val length: Int get() = maximum - minimum
}

data class CaptureTextEditResult(
    val text: String,
    val selection: CaptureTextSelection,
)

sealed interface CaptureComposerCommand {
    data object ToggleBold : CaptureComposerCommand
    data object ToggleItalic : CaptureComposerCommand
    data object InsertHashtag : CaptureComposerCommand
    data class Heading(val level: Int) : CaptureComposerCommand
    data object TaskCheckbox : CaptureComposerCommand
    data object Bullet : CaptureComposerCommand
    data class MarkdownLink(val destination: String? = null) : CaptureComposerCommand
    data class WikiLink(val target: String? = null) : CaptureComposerCommand
    data class ReplaceSelection(val replacement: String) : CaptureComposerCommand
    data object Lowercase : CaptureComposerCommand
    data object Uppercase : CaptureComposerCommand
    data object SentenceCase : CaptureComposerCommand
    data object CapitalizeWords : CaptureComposerCommand
    data object Slugify : CaptureComposerCommand
}

/**
 * Selection-aware Markdown editing shared by the Android composer and its tests.
 * Kotlin and Compose string offsets are UTF-16 offsets, matching the Apple editor contract.
 */
class CaptureComposerTextEditor {
    fun apply(
        command: CaptureComposerCommand,
        text: String,
        selection: CaptureTextSelection,
    ): CaptureTextEditResult {
        val input = normalizedInput(text, selection)
        return when (command) {
            CaptureComposerCommand.ToggleBold -> toggle("**", input)
            CaptureComposerCommand.ToggleItalic -> toggle("*", input)
            CaptureComposerCommand.InsertHashtag -> insertHashtag(input)
            is CaptureComposerCommand.Heading -> if (command.level in 1..6) {
                applyLinePrefix(input, "#".repeat(command.level) + " ", headingPrefix)
            } else input.result()
            CaptureComposerCommand.TaskCheckbox -> applyLinePrefix(input, "- [ ] ", listPrefix)
            CaptureComposerCommand.Bullet -> applyLinePrefix(input, "- ", listPrefix)
            is CaptureComposerCommand.MarkdownLink -> insertMarkdownLink(input, command.destination)
            is CaptureComposerCommand.WikiLink -> insertWikiLink(input, command.target)
            is CaptureComposerCommand.ReplaceSelection -> replaceSelection(input, normalizeNewlines(command.replacement))
            CaptureComposerCommand.Lowercase -> transform(input) { it.lowercase(Locale.ROOT) }
            CaptureComposerCommand.Uppercase -> transform(input) { it.uppercase(Locale.ROOT) }
            CaptureComposerCommand.SentenceCase -> transform(input, ::sentenceCase)
            CaptureComposerCommand.CapitalizeWords -> transform(input, ::capitalizeWords)
            CaptureComposerCommand.Slugify -> transform(input, ::slugify)
        }
    }

    private data class Input(val text: String, val selection: CaptureTextSelection) {
        fun result() = CaptureTextEditResult(text, selection)
    }

    private data class Edit(val start: Int, val end: Int, val replacement: String)

    private fun toggle(marker: String, input: Input): CaptureTextEditResult {
        val start = input.selection.minimum
        val end = input.selection.maximum
        val selected = input.text.substring(start, end)
        val markerLength = marker.length
        if (start == end) {
            val prefix = start - markerLength
            val suffixEnd = start + markerLength
            if (prefix >= 0 && suffixEnd <= input.text.length &&
                input.text.substring(prefix, start) == marker &&
                input.text.substring(start, suffixEnd) == marker &&
                exactMarkerRun(input.text, marker, prefix, suffixEnd)
            ) {
                return replace(input, prefix, suffixEnd, "", CaptureTextSelection(prefix, prefix))
            }
            return replace(
                input,
                start,
                end,
                marker + marker,
                CaptureTextSelection(start + markerLength, start + markerLength),
            )
        }
        if (selected.length >= markerLength * 2 && selected.startsWith(marker) &&
            selected.endsWith(marker) && exactFullWrapper(selected, marker)
        ) {
            val inner = selected.substring(markerLength, selected.length - markerLength)
            return replace(input, start, end, inner, CaptureTextSelection(start, start + inner.length))
        }
        val prefix = start - markerLength
        val suffixEnd = end + markerLength
        if (prefix >= 0 && suffixEnd <= input.text.length &&
            input.text.substring(prefix, start) == marker &&
            input.text.substring(end, suffixEnd) == marker &&
            exactMarkerRun(input.text, marker, prefix, suffixEnd)
        ) {
            return replace(input, prefix, suffixEnd, selected, CaptureTextSelection(prefix, prefix + selected.length))
        }
        return replace(
            input,
            start,
            end,
            marker + selected + marker,
            CaptureTextSelection(start + markerLength, start + markerLength + selected.length),
        )
    }

    private fun exactMarkerRun(text: String, marker: String, prefix: Int, suffixEnd: Int): Boolean {
        if (!marker.startsWith('*')) return true
        return (prefix == 0 || text[prefix - 1] != '*') && (suffixEnd == text.length || text[suffixEnd] != '*')
    }

    private fun exactFullWrapper(value: String, marker: String): Boolean = when (marker) {
        "*" -> !value.startsWith("**") && !value.endsWith("**")
        "**" -> !value.startsWith("***") && !value.endsWith("***")
        else -> true
    }

    private fun insertHashtag(input: Input): CaptureTextEditResult {
        val start = input.selection.minimum
        val end = input.selection.maximum
        val selected = input.text.substring(start, end)
        val selection = if (start == end) CaptureTextSelection(start + 1, start + 1)
        else CaptureTextSelection(start + 1, end + 1)
        return replace(input, start, end, "#$selected", selection)
    }

    private fun insertMarkdownLink(input: Input, destination: String?): CaptureTextEditResult {
        val start = input.selection.minimum
        val end = input.selection.maximum
        val hasLabel = start != end
        val label = if (hasLabel) escapeMarkdownLabel(input.text.substring(start, end)) else "link text"
        val normalizedDestination = destination?.let(::normalizeNewlines)?.trim().orEmpty()
        val hasDestination = normalizedDestination.isNotEmpty()
        val linkDestination = if (hasDestination) escapeMarkdownDestination(normalizedDestination) else "url"
        val replacement = "[$label]($linkDestination)"
        val selection = when {
            hasLabel && !hasDestination -> {
                val destinationStart = start + 1 + label.length + 2
                CaptureTextSelection(destinationStart, destinationStart + linkDestination.length)
            }
            !hasLabel -> CaptureTextSelection(start + 1, start + 1 + label.length)
            else -> CaptureTextSelection(start + replacement.length, start + replacement.length)
        }
        return replace(input, start, end, replacement, selection)
    }

    private fun insertWikiLink(input: Input, target: String?): CaptureTextEditResult {
        val start = input.selection.minimum
        val end = input.selection.maximum
        val normalizedTarget = target?.let(::normalizeNewlines)?.trim().orEmpty()
        val hasTarget = normalizedTarget.isNotEmpty()
        val body = when {
            start != end -> input.text.substring(start, end)
            hasTarget -> normalizedTarget
            else -> "Note"
        }
        val replacement = "[[$body]]"
        val selection = if (start != end || !hasTarget) CaptureTextSelection(start + 2, start + 2 + body.length)
        else CaptureTextSelection(start + replacement.length, start + replacement.length)
        return replace(input, start, end, replacement, selection)
    }

    private fun replaceSelection(input: Input, replacement: String): CaptureTextEditResult {
        val start = input.selection.minimum
        val caret = start + replacement.length
        return replace(input, start, input.selection.maximum, replacement, CaptureTextSelection(caret, caret))
    }

    private fun applyLinePrefix(
        input: Input,
        replacement: String,
        existingPrefix: (String, Int) -> Int,
    ): CaptureTextEditResult {
        val start = input.selection.minimum
        val end = input.selection.maximum
        val firstLine = lineStart(input.text, start)
        val lastSelectedOffset = if (end > start) maxOf(start, end - 1) else start
        val lastLine = lineStart(input.text, lastSelectedOffset)
        val edits = mutableListOf<Edit>()
        var cursor = firstLine
        while (cursor <= lastLine) {
            val lineEnd = lineEnd(input.text, cursor)
            val line = input.text.substring(cursor, lineEnd)
            val indent = line.indexOfFirst { it != ' ' && it != '\t' }.let { if (it < 0) line.length else it }
            val length = existingPrefix(line, indent)
            edits += Edit(cursor + indent, cursor + indent + length, replacement)
            if (lineEnd >= input.text.length) break
            cursor = lineEnd + 1
        }
        val mappedStart = mapOffset(start, edits)
        val mappedEnd = mapOffset(end, edits)
        val result = StringBuilder(input.text)
        edits.asReversed().forEach { result.replace(it.start, it.end, it.replacement) }
        return CaptureTextEditResult(result.toString(), CaptureTextSelection(mappedStart, maxOf(mappedStart, mappedEnd)))
    }

    private fun lineStart(text: String, offset: Int): Int = if (offset <= 0) 0 else text.lastIndexOf('\n', offset - 1).let { if (it < 0) 0 else it + 1 }
    private fun lineEnd(text: String, offset: Int): Int = text.indexOf('\n', offset).let { if (it < 0) text.length else it }

    private fun mapOffset(offset: Int, edits: List<Edit>): Int {
        var delta = 0
        for (edit in edits) {
            if (offset < edit.start) break
            if (edit.end > edit.start && offset < edit.end) return edit.start + delta + edit.replacement.length
            delta += edit.replacement.length - (edit.end - edit.start)
        }
        return offset + delta
    }

    private fun transform(input: Input, operation: (String) -> String): CaptureTextEditResult {
        val start = input.selection.minimum
        val end = input.selection.maximum
        if (start == end) return input.result()
        val transformed = operation(input.text.substring(start, end))
        return replace(input, start, end, transformed, CaptureTextSelection(start, start + transformed.length))
    }

    private fun sentenceCase(value: String): String {
        val lowered = value.lowercase(Locale.ROOT)
        val result = StringBuilder()
        var sentenceStart = true
        forEachCodePoint(lowered) { codePoint ->
            val token = String(Character.toChars(codePoint))
            if (sentenceStart && Character.isLetter(codePoint)) {
                result.append(token.uppercase(Locale.ROOT))
                sentenceStart = false
            } else {
                result.append(token)
                if (Character.isLetterOrDigit(codePoint)) sentenceStart = false
            }
            if (codePoint == '.'.code || codePoint == '!'.code || codePoint == '?'.code || codePoint == '\n'.code) sentenceStart = true
        }
        return result.toString()
    }

    private fun capitalizeWords(value: String): String {
        val lowered = value.lowercase(Locale.ROOT)
        val result = StringBuilder()
        var wordStart = true
        var insideWord = false
        forEachCodePoint(lowered) { codePoint ->
            val token = String(Character.toChars(codePoint))
            val isLetter = Character.isLetter(codePoint)
            val isNumber = Character.isDigit(codePoint)
            if (wordStart && isLetter) {
                result.append(token.uppercase(Locale.ROOT))
                wordStart = false
                insideWord = true
            } else {
                result.append(token)
                when {
                    isLetter || isNumber -> { wordStart = false; insideWord = true }
                    codePoint == '\''.code || codePoint == '’'.code -> wordStart = !insideWord
                    else -> { wordStart = true; insideWord = false }
                }
            }
        }
        return result.toString()
    }

    private fun slugify(value: String): String {
        val folded = Normalizer.normalize(value, Normalizer.Form.NFKD).lowercase(Locale.ROOT)
        val result = StringBuilder()
        var separator = false
        forEachCodePoint(folded) { codePoint ->
            when {
                Character.getType(codePoint) == Character.NON_SPACING_MARK.toInt() -> Unit
                Character.isLetterOrDigit(codePoint) -> {
                    if (separator && result.isNotEmpty()) result.append('-')
                    result.appendCodePoint(codePoint)
                    separator = false
                }
                result.isNotEmpty() -> separator = true
            }
        }
        return result.toString()
    }

    private fun normalizedInput(text: String, selection: CaptureTextSelection): Input {
        val start = selection.minimum.coerceIn(0, text.length)
        val end = selection.maximum.coerceIn(start, text.length)
        val normalized = normalizeNewlines(text)
        val translated = CaptureTextSelection(
            normalizedOffset(text, start),
            normalizedOffset(text, end),
        )
        return Input(normalized, graphemeSafe(normalized, translated))
    }

    private fun normalizedOffset(text: String, offset: Int): Int {
        var source = 0
        var normalized = 0
        while (source < offset) {
            if (text[source] == '\r' && source + 1 < text.length && text[source + 1] == '\n') {
                if (offset == source + 1) return normalized + 1
                source += 2
            } else source += 1
            normalized += 1
        }
        return normalized
    }

    private fun graphemeSafe(text: String, selection: CaptureTextSelection): CaptureTextSelection {
        if (text.isEmpty()) return CaptureTextSelection(0, 0)
        val iterator = BreakIterator.getCharacterInstance(Locale.ROOT).apply { setText(text) }
        fun lowerBoundary(offset: Int): Int = if (iterator.isBoundary(offset)) offset else iterator.preceding(offset).coerceAtLeast(0)
        fun upperBoundary(offset: Int): Int = if (iterator.isBoundary(offset)) offset else iterator.following(offset).let { if (it == BreakIterator.DONE) text.length else it }
        return if (selection.length == 0) {
            val position = lowerBoundary(selection.minimum)
            CaptureTextSelection(position, position)
        } else CaptureTextSelection(lowerBoundary(selection.minimum), upperBoundary(selection.maximum))
    }

    private fun replace(
        input: Input,
        start: Int,
        end: Int,
        replacement: String,
        selection: CaptureTextSelection,
    ): CaptureTextEditResult = CaptureTextEditResult(
        input.text.replaceRange(start, end, replacement),
        selection,
    )

    private fun normalizeNewlines(value: String) = value.replace("\r\n", "\n").replace('\r', '\n')
    private fun escapeMarkdownLabel(value: String) = value.replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]")
    private fun escapeMarkdownDestination(value: String) = value.replace("\\", "\\\\").replace(")", "\\)").replace("\n", "")

    private fun forEachCodePoint(value: String, block: (Int) -> Unit) {
        var index = 0
        while (index < value.length) {
            val codePoint = value.codePointAt(index)
            block(codePoint)
            index += Character.charCount(codePoint)
        }
    }

    private companion object {
        val headingPrefix: (String, Int) -> Int = { line, indent ->
            var cursor = indent
            while (cursor < line.length && line[cursor] == '#') cursor += 1
            val count = cursor - indent
            if (count !in 1..6 || (cursor < line.length && line[cursor] != ' ' && line[cursor] != '\t')) 0
            else {
                while (cursor < line.length && (line[cursor] == ' ' || line[cursor] == '\t')) cursor += 1
                cursor - indent
            }
        }
        val listPrefix: (String, Int) -> Int = { line, indent ->
            listPrefixPattern.find(line.substring(indent))?.range?.let { it.last + 1 } ?: 0
        }
        val listPrefixPattern = Regex("^(?:[-+*][ \\t]+(?:\\[[ xX]\\](?:[ \\t]+|$))?|[0-9]+[.)][ \\t]+)")
    }
}
