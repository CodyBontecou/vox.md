package md.vox.android

/**
 * Obsidian-style live preview for the formatted composer: YAML frontmatter becomes a
 * Properties panel and embeds on their own line become audio, image or video viewers. Pure
 * model only (parsing, classification, reveal rule, resolver candidates); the file text is
 * never changed, the editor just draws these blocks over hidden source.
 */
internal sealed interface PreviewBlock {
    /** First character of the block's source. */
    val start: Int
    /** End of the block's last line, exclusive (the following newline is not part of it). */
    val end: Int
}

internal data class FrontmatterProperty(val key: String, val values: List<String>, val isList: Boolean)

internal data class FrontmatterBlock(
    override val start: Int,
    override val end: Int,
    val properties: List<FrontmatterProperty>,
) : PreviewBlock

internal enum class EmbedKind { AUDIO, IMAGE, VIDEO }

internal data class EmbedBlock(
    override val start: Int,
    override val end: Int,
    /** As written: "Recording-1.wav", "attachments/photo.jpg", URL-decoded for Markdown links. */
    val target: String,
    val kind: EmbedKind,
) : PreviewBlock {
    val fileName: String get() = target.substringAfterLast('/')
}

internal object LivePreview {
    private val audio = setOf("wav", "m4a", "mp3", "aac", "ogg", "flac", "caf")
    private val image = setOf("png", "jpg", "jpeg", "gif", "heic", "webp")
    private val video = setOf("mp4", "mov", "m4v", "webm")
    private val wikiEmbed = Regex("^!\\[\\[([^\\]|#]+)(?:[|#][^\\]]*)?]]$")
    private val markdownEmbed = Regex("^!\\[[^\\]]*]\\((<[^>]+>|[^)\\s]+)(?:\\s+\"[^\"]*\")?\\)$")

    fun kindOf(target: String): EmbedKind? {
        val extension = target.substringAfterLast('/').substringAfterLast('.', "").lowercase()
        return when (extension) {
            in audio -> EmbedKind.AUDIO
            in image -> EmbedKind.IMAGE
            in video -> EmbedKind.VIDEO
            else -> null
        }
    }

    /** Frontmatter, then every embed line outside it and outside fenced code. */
    fun blocks(text: String): List<PreviewBlock> {
        if (text.isEmpty() || text.length > 200_000) return emptyList()
        val frontmatter = frontmatter(text)
        return listOfNotNull(frontmatter) + embeds(text, from = frontmatter?.end ?: 0)
    }

    /** `---` on the first line, closed by a later `---` (or `...`) line. */
    fun frontmatter(text: String): FrontmatterBlock? {
        val firstEnd = text.indexOf('\n').takeIf { it >= 0 } ?: return null
        if (text.substring(0, firstEnd).trimEnd('\r').trim() != "---") return null
        var offset = firstEnd + 1
        val body = mutableListOf<String>()
        while (offset <= text.length) {
            val lineEnd = text.indexOf('\n', offset).let { if (it < 0) text.length else it }
            val line = text.substring(offset, lineEnd).trimEnd('\r')
            if (line.trim() == "---" || line.trim() == "...") {
                return FrontmatterBlock(0, lineEnd, properties(body))
            }
            body += line
            if (lineEnd >= text.length) break
            offset = lineEnd + 1
        }
        return null
    }

    /** A forgiving reading of the YAML Obsidian writes: scalars, flow lists and block lists. */
    fun properties(lines: List<String>): List<FrontmatterProperty> {
        val result = mutableListOf<FrontmatterProperty>()
        var key: String? = null
        var items = mutableListOf<String>()
        fun flush() {
            key?.let { result += FrontmatterProperty(it, items.toList(), isList = true) }
            key = null
            items = mutableListOf()
        }
        for (raw in lines) {
            if (raw.isBlank() || raw.trimStart().startsWith("#")) continue
            val trimmed = raw.trim()
            if (key != null && (raw.startsWith(" ") || raw.startsWith("\t") || trimmed.startsWith("- ")) && trimmed.startsWith("-")) {
                items += unquote(trimmed.removePrefix("-").trim())
                continue
            }
            flush()
            val colon = raw.indexOf(':')
            if (colon <= 0 || raw.startsWith(" ")) continue
            val name = raw.substring(0, colon).trim()
            val value = raw.substring(colon + 1).trim()
            when {
                value.isEmpty() -> key = name
                value.startsWith("[") && value.endsWith("]") -> result += FrontmatterProperty(
                    name,
                    value.removePrefix("[").removeSuffix("]").split(',').map { unquote(it.trim()) }.filter(String::isNotEmpty),
                    isList = true,
                )
                else -> result += FrontmatterProperty(name, listOf(unquote(value)), isList = false)
            }
        }
        flush()
        return result
    }

    fun embeds(text: String, from: Int = 0): List<EmbedBlock> {
        val result = mutableListOf<EmbedBlock>()
        var offset = from
        var inFence = false
        while (offset < text.length) {
            val lineEnd = text.indexOf('\n', offset).let { if (it < 0) text.length else it }
            val line = text.substring(offset, lineEnd).trimEnd('\r')
            val trimmed = line.trim()
            if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) inFence = !inFence
            else if (!inFence) embedTarget(trimmed)?.let { target ->
                kindOf(target)?.let { kind -> result += EmbedBlock(offset, lineEnd, target, kind) }
            }
            offset = lineEnd + 1
        }
        return result
    }

    private fun embedTarget(line: String): String? {
        wikiEmbed.matchEntire(line)?.let { return it.groupValues[1].trim() }
        markdownEmbed.matchEntire(line)?.let { match ->
            val raw = match.groupValues[1].removePrefix("<").removeSuffix(">")
            if (raw.contains("://")) return null
            return runCatching { java.net.URLDecoder.decode(raw.replace("+", "%2B"), "UTF-8") }.getOrDefault(raw)
        }
        return null
    }

    /** Like Obsidian, a block shows its source while the caret or selection touches it. */
    fun isRevealed(block: PreviewBlock, selectionStart: Int, selectionEnd: Int): Boolean {
        val min = minOf(selectionStart, selectionEnd)
        val max = maxOf(selectionStart, selectionEnd)
        return min <= block.end && max >= block.start
    }

    /**
     * Vault-relative paths to try for an embed, in order: the attachments folder captures write
     * to, the note's folder, the vault root. A miss falls back to a bounded search by file name.
     */
    fun candidates(noteRelativePath: String?, target: String, attachmentsFolders: List<String> = listOf("attachments")): List<String> {
        val clean = target.trim().trimStart('/')
        if (clean.isEmpty() || clean.split('/').any { it == ".." }) return emptyList()
        val noteFolder = noteRelativePath?.substringBeforeLast('/', "").orEmpty()
        return buildList {
            attachmentsFolders.map { it.trim('/') }.filter(String::isNotEmpty).forEach { add("$it/$clean") }
            if (noteFolder.isNotEmpty()) add("$noteFolder/$clean")
            add(clean)
        }.distinct()
    }

    private fun unquote(value: String): String {
        val v = value.trim()
        return if (v.length >= 2 && ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith('\'') && v.endsWith('\'')))) v.substring(1, v.length - 1) else v
    }
}
