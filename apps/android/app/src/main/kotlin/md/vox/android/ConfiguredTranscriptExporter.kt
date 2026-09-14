package md.vox.android

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import android.util.AtomicFile
import java.io.File
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureExportFileFormat
import md.vox.android.capturedomain.CaptureExportFileMode
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.platformservices.RecordingTranscriptionState

internal sealed interface ConfiguredTranscriptExportResult {
    data object Disabled : ConfiguredTranscriptExportResult
    data class Exported(val displayName: String, val documentUri: String) : ConfiguredTranscriptExportResult
    data class Failed(val reason: ConfiguredTranscriptExportFailure) : ConfiguredTranscriptExportResult
}

internal enum class ConfiguredTranscriptExportFailure {
    DESTINATION_REQUIRED,
    RETAINED_AUDIO_UNAVAILABLE,
    EXPORT_FAILED,
}

internal fun ConfiguredTranscriptExportFailure.uiText(): VoxUiText = when (this) {
    ConfiguredTranscriptExportFailure.DESTINATION_REQUIRED ->
        voxUiText("Choose an export folder in this Capture Preset.")
    ConfiguredTranscriptExportFailure.RETAINED_AUDIO_UNAVAILABLE ->
        voxUiText("The transcript was not exported because its retained audio could not be prepared.")
    ConfiguredTranscriptExportFailure.EXPORT_FAILED ->
        voxUiText("The configured transcript export failed.")
}

internal data class ConfiguredTranscriptExportPlan(
    val baseName: String,
    val extension: String,
    val mimeType: String,
    val content: String,
) {
    val displayName: String get() = "$baseName.$extension"
}

internal data class ConfiguredTranscriptAudioSource(
    val contentUri: String,
    val displayName: String,
    val saveMode: CaptureAudioSaveMode,
    val attachmentsFolder: String,
)

internal object ConfiguredTranscriptExportPlanner {
    private val invalidFilename = Regex("[/\\\\?%*|\"<>:\\p{Cntrl}]")

    fun plan(
        state: RecordingTranscriptionState,
        settings: CapturePresetExportSettings,
        markdownTemplate: String? = null,
        audioRelativePath: String? = null,
        nowEpochMillis: Long = System.currentTimeMillis(),
        randomUUID: () -> UUID = UUID::randomUUID,
    ): ConfiguredTranscriptExportPlan {
        val effectiveFormat = if (settings.markdownTemplateEnabled) {
            CaptureExportFileFormat.MARKDOWN
        } else settings.format
        val extension = when {
            effectiveFormat == CaptureExportFileFormat.YAML && settings.yamlUsesMarkdownExtension -> "md"
            effectiveFormat == CaptureExportFileFormat.TEXT -> "txt"
            effectiveFormat == CaptureExportFileFormat.MARKDOWN -> "md"
            effectiveFormat == CaptureExportFileFormat.JSON -> "json"
            else -> "yaml"
        }
        val rawBaseName = when (settings.mode) {
            CaptureExportFileMode.NEW_FILE -> renderFilenameTemplate(settings.newFileNameTemplate, state)
            CaptureExportFileMode.APPEND -> settings.appendFileName
        }
        val fallback = renderFilenameTemplate("voxboard-{timestamp}-{id8}", state)
        val renderedContent = when {
            settings.markdownTemplateEnabled && markdownTemplate != null ->
                MarkdownTranscriptTemplateRenderer.render(markdownTemplate, state, nowEpochMillis, randomUUID)
            settings.mode == CaptureExportFileMode.APPEND && (
                (effectiveFormat == CaptureExportFileFormat.MARKDOWN && settings.mdObsidianEnabled) ||
                    (effectiveFormat == CaptureExportFileFormat.YAML && settings.yamlUsesMarkdownExtension)
                ) -> renderFrontmatterMarkdownEntry(state)
            else -> TranscriptExporter.render(
                state = state,
                format = effectiveFormat.toUiFormat(),
                yamlProperties = settings.yamlProperties,
                yamlUsesMarkdownFrontmatter = effectiveFormat == CaptureExportFileFormat.YAML && settings.yamlUsesMarkdownExtension,
                markdownObsidianEnabled = effectiveFormat == CaptureExportFileFormat.MARKDOWN && settings.mdObsidianEnabled,
            )
        }
        val content = audioRelativePath?.takeIf(String::isNotBlank)?.let { relativePath ->
            applyAudioReference(renderedContent, effectiveFormat, extension, settings, relativePath)
        } ?: renderedContent
        return ConfiguredTranscriptExportPlan(
            baseName = sanitizeFilenameBase(rawBaseName, fallback),
            extension = extension,
            mimeType = when (extension) {
                "json" -> "application/json"
                "yaml" -> "application/yaml"
                "md" -> "text/markdown"
                else -> "text/plain"
            },
            content = content,
        )
    }

    fun mergeForAppend(
        existing: String,
        plan: ConfiguredTranscriptExportPlan,
        settings: CapturePresetExportSettings,
        transcriptID: String,
    ): String {
        if (existing.isBlank()) {
            return if (settings.format == CaptureExportFileFormat.JSON && !settings.markdownTemplateEnabled) {
                jsonArrayOf(plan.content)
            } else plan.content
        }
        if (settings.format == CaptureExportFileFormat.JSON && !settings.markdownTemplateEnabled) {
            val stableID = Regex("\"id\"\\s*:\\s*\"${Regex.escape(transcriptID)}\"", RegexOption.IGNORE_CASE)
            if (stableID.containsMatchIn(existing)) return existing
            val trimmed = existing.trim()
            require(trimmed.startsWith("[") && trimmed.endsWith("]")) { "The append destination is not a Vox.md JSON array." }
            val body = trimmed.removePrefix("[").removeSuffix("]").trim()
            val next = plan.content.trim().prependIndent("  ")
            return if (body.isEmpty()) "[\n$next\n]\n" else "[\n${body.prependIndent("  ")},\n$next\n]\n"
        }
        val isMarkdownDocument = settings.markdownTemplateEnabled ||
            settings.format == CaptureExportFileFormat.MARKDOWN ||
            (settings.format == CaptureExportFileFormat.YAML && settings.yamlUsesMarkdownExtension)
        if (isMarkdownDocument) {
            return mergeMarkdownDocument(
                existing = existing,
                incoming = plan.content,
                insertHorizontalRule = settings.format == CaptureExportFileFormat.MARKDOWN && !settings.mdObsidianEnabled,
            )
        }
        return existing + "\n\n---\n\n" + plan.content
    }

    private fun jsonArrayOf(objectContent: String): String = "[\n${objectContent.trim().prependIndent("  ")}\n]\n"

    private fun applyAudioReference(
        content: String,
        format: CaptureExportFileFormat,
        extension: String,
        settings: CapturePresetExportSettings,
        relativePath: String,
    ): String = when {
        format == CaptureExportFileFormat.JSON -> content
        format == CaptureExportFileFormat.TEXT -> content.trimEnd() + "\n\nAudio: $relativePath"
        extension == "md" -> {
            val withFrontmatter = mergeMarkdownDocument(
                existing = content,
                incoming = "---\naudio: ${yamlScalar(relativePath)}\n---",
                insertHorizontalRule = false,
            )
            if (settings.embedAudioInMarkdown) {
                applyMarkdownAudioEmbed(withFrontmatter, relativePath, settings.audioEmbedPlacement)
            } else withFrontmatter
        }
        format == CaptureExportFileFormat.YAML -> content.trimEnd() + "\naudio: ${yamlScalar(relativePath)}"
        else -> content
    }

    private fun applyMarkdownAudioEmbed(
        markdown: String,
        relativePath: String,
        placement: CaptureAudioEmbedPlacement,
    ): String {
        val embed = "![[${relativePath.replace("]", "\\]")}]]"
        if (embed in markdown) return markdown
        val trimmed = markdown.trim()
        return when (placement) {
            CaptureAudioEmbedPlacement.BEFORE_TEXT -> {
                val parts = splitLeadingFrontmatter(trimmed)
                if (parts.frontmatter == null) "$embed\n\n$trimmed"
                else "---\n${parts.frontmatter.joinToString("\n")}\n---\n\n$embed\n\n${parts.body.trim()}".trimEnd()
            }
            CaptureAudioEmbedPlacement.AFTER_TEXT -> if (trimmed.isEmpty()) embed else "$trimmed\n\n$embed"
        }
    }

    private data class MarkdownParts(val frontmatter: List<String>?, val body: String)

    private fun renderFrontmatterMarkdownEntry(state: RecordingTranscriptionState): String {
        val frontmatter = buildList {
            state.category?.takeIf(String::isNotEmpty)?.let { add("category: ${yamlScalar(it)}") }
            if (state.tags.isNotEmpty()) {
                add("tags: ${state.tags.joinToString(prefix = "[", postfix = "]") { yamlScalar(it) }}")
            }
            state.title?.takeIf(String::isNotEmpty)?.let { add("title: ${yamlScalar(it)}") }
        }
        val body = TranscriptExporter.render(state, TranscriptExportFormat.MARKDOWN)
        return if (frontmatter.isEmpty()) body else "---\n${frontmatter.joinToString("\n")}\n---\n\n$body"
    }

    private fun mergeMarkdownDocument(existing: String, incoming: String, insertHorizontalRule: Boolean): String {
        val destination = splitLeadingFrontmatter(existing)
        val entry = splitLeadingFrontmatter(incoming)
        val frontmatter = mergeFrontmatter(destination.frontmatter, entry.frontmatter)
        val entryBody = entry.body.trim('\n')
        val captureBlock = if (insertHorizontalRule && entryBody.isNotBlank()) "---\n\n$entryBody" else entryBody
        val body = listOf(destination.body.trim('\n'), captureBlock)
            .filter(String::isNotBlank)
            .joinToString("\n\n")
        return when {
            frontmatter == null -> body
            body.isBlank() -> "---\n${frontmatter.joinToString("\n")}\n---"
            else -> "---\n${frontmatter.joinToString("\n")}\n---\n\n$body"
        }
    }

    private fun splitLeadingFrontmatter(markdown: String): MarkdownParts {
        val normalized = markdown.replace("\r\n", "\n")
        val lines = normalized.split('\n')
        if (lines.firstOrNull() != "---") return MarkdownParts(null, normalized)
        val closing = lines.indices.drop(1).firstOrNull { lines[it] == "---" }
            ?: return MarkdownParts(null, normalized)
        val frontmatter = lines.subList(1, closing)
        if (frontmatter.none { frontmatterEntry(it) != null }) return MarkdownParts(null, normalized)
        return MarkdownParts(frontmatter, lines.drop(closing + 1).joinToString("\n"))
    }

    private fun mergeFrontmatter(existing: List<String>?, incoming: List<String>?): List<String>? {
        if (incoming == null) return existing
        if (existing == null) return incoming
        val merged = existing.toMutableList()
        incoming.forEach { line ->
            val entry = frontmatterEntry(line)
            if (entry == null) {
                if (line !in merged) merged += line
            } else {
                val present = merged.indexOfFirst { frontmatterEntry(it)?.first == entry.first }
                if (present < 0) {
                    merged += line
                } else if (entry.first in setOf("tags", "tag", "audio")) {
                    val values = (frontmatterValues(frontmatterEntry(merged[present])!!.second) + frontmatterValues(entry.second)).distinct()
                    merged[present] = "${entry.first}: [${values.joinToString(", ") { yamlScalar(it) }}]"
                }
            }
        }
        return merged
    }

    private fun frontmatterEntry(line: String): Pair<String, String>? {
        if (line.startsWith(' ') || line.startsWith('\t') || line.startsWith('#')) return null
        val separator = line.indexOf(':')
        if (separator <= 0) return null
        return line.substring(0, separator).trim() to line.substring(separator + 1).trim()
    }

    private fun frontmatterValues(raw: String): List<String> = raw
        .trim()
        .removePrefix("[")
        .removeSuffix("]")
        .split(',')
        .map { it.trim().trim('"', '\'') }
        .filter(String::isNotEmpty)

    private fun yamlScalar(value: String): String = "\"${value.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n")}\""

    private fun renderFilenameTemplate(template: String, state: RecordingTranscriptionState): String {
        val timestamp = DateTimeFormatter.ofPattern("yyyy-MM-dd-HHmmss", Locale.US)
            .withZone(ZoneId.systemDefault())
            .format(Instant.ofEpochMilli(state.recordedAtEpochMillis ?: state.completedAtEpochMillis ?: 0L))
        val id = state.sessionID.lowercase(Locale.ROOT)
        return template
            .replace("{timestamp}", timestamp)
            .replace("{date}", timestamp.take(10))
            .replace("{YR}", timestamp.take(4).takeLast(2))
            .replace("{time}", timestamp.takeLast(6))
            .replace("{id}", id)
            .replace("{id8}", id.take(8))
            .replace("{model}", state.modelName ?: state.modelID.orEmpty())
            .replace("{language}", state.languageTag.orEmpty())
    }

    private fun sanitizeFilenameBase(raw: String, fallback: String): String {
        fun clean(value: String): String {
            val trimmed = value.trim()
            val lastSlash = maxOf(trimmed.lastIndexOf('/'), trimmed.lastIndexOf('\\'))
            val lastDot = trimmed.lastIndexOf('.')
            val withoutExtension = if (lastDot > lastSlash + 1 && lastDot < trimmed.lastIndex) {
                trimmed.substring(0, lastDot)
            } else trimmed
            return withoutExtension
                .replace(invalidFilename, "-")
                .replace(" ", "-")
                .trim('-', '.', '_')
        }
        return clean(raw).ifEmpty { clean(fallback).ifEmpty { "voxboard-transcript" } }
    }

    private fun CaptureExportFileFormat.toUiFormat(): TranscriptExportFormat = when (this) {
        CaptureExportFileFormat.TEXT -> TranscriptExportFormat.TEXT
        CaptureExportFileFormat.MARKDOWN -> TranscriptExportFormat.MARKDOWN
        CaptureExportFileFormat.JSON -> TranscriptExportFormat.JSON
        CaptureExportFileFormat.YAML -> TranscriptExportFormat.YAML
    }
}

internal object MarkdownTranscriptTemplateRenderer {
    private val expression = Regex("<%\\s*(.+?)\\s*%>")

    fun render(
        template: String,
        state: RecordingTranscriptionState,
        nowEpochMillis: Long,
        randomUUID: () -> UUID,
    ): String {
        val normalized = template.replace("\r\n", "\n")
        val resolved = expression.replace(normalized) { match ->
            evaluate(match.groupValues[1].trim(), nowEpochMillis, randomUUID) ?: match.value
        }
        val enriched = fillFrontmatter(resolved, state)
        return listOf(enriched.trim(), state.preferredTranscript.orEmpty().trim())
            .filter(String::isNotEmpty)
            .joinToString("\n\n") + "\n"
    }

    private fun evaluate(expression: String, nowEpochMillis: Long, randomUUID: () -> UUID): String? = when {
        expression.startsWith("tp.date.now") || expression.startsWith("tp.file.creation_date") -> {
            val requested = Regex("[\\\"']([^\\\"']+)[\\\"']").find(expression)?.groupValues?.get(1)
                ?: if (expression.startsWith("tp.date.now")) "YYYY-MM-DD" else "YYYY-MM-DD HH:mm:ss"
            val javaPattern = requested.replace("YYYY", "yyyy").replace("DD", "dd")
            runCatching {
                DateTimeFormatter.ofPattern(javaPattern, Locale.US).withZone(ZoneId.systemDefault())
                    .format(Instant.ofEpochMilli(nowEpochMillis))
            }.getOrNull()
        }
        expression.startsWith("crypto.randomUUID") -> randomUUID().toString().lowercase(Locale.ROOT)
        else -> null
    }

    private fun fillFrontmatter(template: String, state: RecordingTranscriptionState): String {
        if (!template.startsWith("---\n")) {
            val frontmatter = enrichmentFrontmatter(state)
            return if (frontmatter.isEmpty()) template else "---\n${frontmatter.joinToString("\n")}\n---\n\n$template"
        }
        val closing = template.indexOf("\n---", startIndex = 4)
        if (closing < 0) return template
        val frontmatter = template.substring(4, closing).lines().map { line ->
            val separator = line.indexOf(':')
            if (separator <= 0) return@map line
            val key = line.substring(0, separator).trim().lowercase(Locale.ROOT)
            val value = line.substring(separator + 1).trim()
            val replacement = when (key) {
                "title" -> if (value.isEmpty()) state.title?.let(::yamlScalar) else null
                "category" -> if (value.isEmpty()) state.category?.let(::yamlScalar) else null
                "tags" -> if (value.isEmpty() || value == "[]") state.tags.takeIf(List<String>::isNotEmpty)
                    ?.joinToString(prefix = "[", postfix = "]") { yamlQuotedScalar(it) } else null
                "summary", "description" -> if (value.isEmpty()) state.preferredTranscript?.takeIf(String::isNotBlank)?.let(::yamlScalar) else null
                else -> null
            }
            if (replacement == null) line else line.substring(0, separator + 1) + " " + replacement
        }.toMutableList()
        val existingKeys = frontmatter.mapNotNull { line ->
            line.substringBefore(':', missingDelimiterValue = "").trim().lowercase(Locale.ROOT).takeIf(String::isNotEmpty)
        }.toSet()
        val tagsIndex = frontmatter.indexOfFirst {
            it.substringBefore(':', missingDelimiterValue = "").trim().equals("tags", ignoreCase = true)
        }
        if (tagsIndex >= 0 && state.tags.isNotEmpty()) {
            val present = frontmatter[tagsIndex].substringAfter(':').trim()
                .removePrefix("[").removeSuffix("]")
                .split(',')
                .map { it.trim().trim('"', '\'') }
                .filter(String::isNotEmpty)
            val merged = (present + state.tags).distinct()
            frontmatter[tagsIndex] = "tags: ${merged.joinToString(prefix = "[", postfix = "]") { yamlQuotedScalar(it) }}"
        }
        frontmatter += enrichmentFrontmatter(state).filter { line ->
            line.substringBefore(':').lowercase(Locale.ROOT) !in existingKeys
        }
        return "---\n${frontmatter.joinToString("\n")}" + template.substring(closing)
    }

    private fun enrichmentFrontmatter(state: RecordingTranscriptionState): List<String> = buildList {
        state.category?.takeIf(String::isNotEmpty)?.let { add("category: ${yamlScalar(it)}") }
        if (state.tags.isNotEmpty()) {
            add("tags: ${state.tags.joinToString(prefix = "[", postfix = "]") { yamlQuotedScalar(it) }}")
        }
        state.title?.takeIf(String::isNotEmpty)?.let { add("title: ${yamlScalar(it)}") }
    }

    private fun yamlScalar(value: String): String = if (value.any { it == ':' || it == '#' || it == '"' }) {
        yamlQuotedScalar(value)
    } else value

    private fun yamlQuotedScalar(value: String): String =
        "\"${value.replace("\\", "\\\\").replace("\"", "\\\"")}\""
}

internal class AndroidConfiguredTranscriptExporter(context: Context) {
    private val resolver = context.applicationContext.contentResolver

    fun export(
        state: RecordingTranscriptionState,
        settings: CapturePresetExportSettings,
        audioSource: ConfiguredTranscriptAudioSource? = null,
    ): ConfiguredTranscriptExportResult {
        if (!settings.usesCustomExportSettings || !settings.exportEnabled) return ConfiguredTranscriptExportResult.Disabled
        val tree = settings.destinationTreeUri?.let(Uri::parse)
            ?: return ConfiguredTranscriptExportResult.Failed(ConfiguredTranscriptExportFailure.DESTINATION_REQUIRED)
        var publishedAudio: Uri? = null
        return runCatching {
            val template = if (settings.markdownTemplateEnabled) readTemplate(settings) else null
            val parent = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
            val initialPlan = ConfiguredTranscriptExportPlanner.plan(state, settings, template)
            val audio = audioSource?.takeIf { it.saveMode != CaptureAudioSaveMode.OFF }?.let { source ->
                publishAudio(tree, parent, initialPlan, state, settings.mode, source).also { publishedAudio = it.uri }
            }
            val plan = ConfiguredTranscriptExportPlanner.plan(
                state = state,
                settings = settings,
                markdownTemplate = template,
                audioRelativePath = audio?.relativePath,
            )
            val target = when (settings.mode) {
                CaptureExportFileMode.NEW_FILE -> createUnique(parent, tree, plan)
                CaptureExportFileMode.APPEND -> findChild(tree, parent, plan.displayName)
                    ?: requireNotNull(DocumentsContract.createDocument(resolver, parent, plan.mimeType, plan.displayName))
            }
            val content = if (settings.mode == CaptureExportFileMode.APPEND) {
                ConfiguredTranscriptExportPlanner.mergeForAppend(readText(target), plan, settings, state.sessionID)
            } else plan.content
            writeAndVerify(target, content)
            ConfiguredTranscriptExportResult.Exported(queryDisplayName(target) ?: plan.displayName, target.toString())
        }.getOrElse {
            publishedAudio?.let { runCatching { DocumentsContract.deleteDocument(resolver, it) } }
            ConfiguredTranscriptExportResult.Failed(ConfiguredTranscriptExportFailure.EXPORT_FAILED)
        }
    }

    private fun readTemplate(settings: CapturePresetExportSettings): String {
        val uri = settings.markdownTemplateUri?.let(Uri::parse)
            ?: error("Choose a Markdown template in this Capture Preset.")
        return readText(uri, MAX_TEMPLATE_BYTES)
    }

    private fun createUnique(parent: Uri, tree: Uri, plan: ConfiguredTranscriptExportPlan): Uri {
        repeat(1_000) { index ->
            val suffix = if (index == 0) "" else "-${index + 1}"
            val displayName = "${plan.baseName}$suffix.${plan.extension}"
            if (findChild(tree, parent, displayName) == null) {
                return requireNotNull(DocumentsContract.createDocument(resolver, parent, plan.mimeType, displayName))
            }
        }
        error("The export folder has too many files with this name.")
    }

    private fun findChild(tree: Uri, parent: Uri, displayName: String, mimeType: String? = null): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, DocumentsContract.getDocumentId(parent))
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
        )
        return resolver.query(children, projection, null, null, null)?.use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val typeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            var found: Uri? = null
            while (cursor.moveToNext()) {
                if (cursor.getString(nameColumn) == displayName && (mimeType == null || cursor.getString(typeColumn) == mimeType)) {
                    check(found == null) { "The export destination contains duplicate filenames." }
                    found = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(idColumn))
                }
            }
            found
        }
    }

    private data class PublishedAudio(val uri: Uri, val relativePath: String)

    private fun publishAudio(
        tree: Uri,
        transcriptParent: Uri,
        plan: ConfiguredTranscriptExportPlan,
        state: RecordingTranscriptionState,
        mode: CaptureExportFileMode,
        source: ConfiguredTranscriptAudioSource,
    ): PublishedAudio {
        val bytes = readBytes(Uri.parse(source.contentUri), MAX_AUDIO_BYTES)
        require(bytes.isNotEmpty()) { "The retained recording audio is empty." }
        val extension = source.displayName.substringAfterLast('.', "wav").lowercase(Locale.ROOT)
            .filter(Char::isLetterOrDigit).take(12).ifEmpty { "wav" }
        val folderSegments = if (source.saveMode == CaptureAudioSaveMode.ATTACHMENTS_FOLDER) {
            source.attachmentsFolder.split('/').map(String::trim).filter(String::isNotEmpty)
        } else emptyList()
        require(folderSegments.size <= 31 && folderSegments.all { it !in setOf(".", "..") && '/' !in it && '\\' !in it }) {
            "The audio export folder is invalid."
        }
        val parent = resolveOrCreateFolder(tree, transcriptParent, folderSegments)
        val suffix = if (mode == CaptureExportFileMode.APPEND) "-${state.sessionID.take(8).lowercase(Locale.ROOT)}" else ""
        val target = createUniqueDocument(tree, parent, plan.baseName + suffix, extension, audioMimeType(extension))
        writeBytesAndVerify(target, bytes)
        val displayName = queryDisplayName(target) ?: error("The audio export name could not be verified.")
        return PublishedAudio(target, (folderSegments + displayName).joinToString("/"))
    }

    private fun resolveOrCreateFolder(tree: Uri, root: Uri, segments: List<String>): Uri =
        segments.fold(root) { parent, segment ->
            findChild(tree, parent, segment, DocumentsContract.Document.MIME_TYPE_DIR)
                ?: requireNotNull(DocumentsContract.createDocument(
                    resolver,
                    parent,
                    DocumentsContract.Document.MIME_TYPE_DIR,
                    segment,
                ))
        }

    private fun createUniqueDocument(
        tree: Uri,
        parent: Uri,
        baseName: String,
        extension: String,
        mimeType: String,
    ): Uri {
        repeat(1_000) { index ->
            val suffix = if (index == 0) "" else "-${index + 1}"
            val displayName = "$baseName$suffix.$extension"
            if (findChild(tree, parent, displayName) == null) {
                return requireNotNull(DocumentsContract.createDocument(resolver, parent, mimeType, displayName))
            }
        }
        error("The audio export folder has too many files with this name.")
    }

    private fun audioMimeType(extension: String): String = when (extension) {
        "m4a" -> "audio/mp4"
        "mp3" -> "audio/mpeg"
        "ogg", "opus" -> "audio/ogg"
        "flac" -> "audio/flac"
        else -> "audio/wav"
    }

    private fun readText(uri: Uri, maxBytes: Int = MAX_APPEND_BYTES): String {
        return readBytes(uri, maxBytes).toString(Charsets.UTF_8)
    }

    private fun readBytes(uri: Uri, maxBytes: Int): ByteArray =
        resolver.openInputStream(uri)?.use { input ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(32 * 1_024)
            var total = 0
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                total += count
                require(total <= maxBytes) { "The existing export file is too large to update safely." }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        } ?: error("Vox.md can no longer read the selected document.")

    private fun writeAndVerify(uri: Uri, content: String) {
        val bytes = content.toByteArray(Charsets.UTF_8)
        resolver.openOutputStream(uri, "wt")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: error("Vox.md could not open the export file for writing.")
        val readBack = readBytes(uri, bytes.size + 1)
        require(readBack.size == bytes.size && sha256(readBack).contentEquals(sha256(bytes))) {
            "The document provider did not preserve the exported bytes."
        }
    }

    private fun writeBytesAndVerify(uri: Uri, bytes: ByteArray) {
        require(bytes.size <= MAX_AUDIO_BYTES) { "The configured audio is too large." }
        resolver.openOutputStream(uri, "wt")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: error("Vox.md could not open the audio export file for writing.")
        val readBack = readBytes(uri, bytes.size + 1)
        require(readBack.contentEquals(bytes)) { "The document provider did not preserve the exported audio bytes." }
    }

    private fun queryDisplayName(uri: Uri): String? = resolver.query(
        uri,
        arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
        null,
        null,
        null,
    )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    private fun sha256(bytes: ByteArray): ByteArray = MessageDigest.getInstance("SHA-256").digest(bytes)

    private companion object {
        const val MAX_TEMPLATE_BYTES = 1_048_576
        const val MAX_APPEND_BYTES = 16 * 1_048_576
        const val MAX_AUDIO_BYTES = 100 * 1_048_576
    }
}

/** Content-free terminal receipt for automatic configured transcript exports. */
internal class ConfiguredTranscriptExportReceiptStore(context: Context) {
    private val recordingsRoot = File(context.applicationContext.noBackupFilesDir, "recordings")

    fun wasExported(sessionID: String): Boolean {
        val file = receiptFile(sessionID) ?: return false
        return runCatching { file.readText(StandardCharsets.UTF_8) == RECEIPT_CONTENT }.getOrDefault(false)
    }

    fun markExported(sessionID: String): Boolean {
        val file = receiptFile(sessionID) ?: return false
        val atomic = AtomicFile(file)
        val output = runCatching { atomic.startWrite() }.getOrNull() ?: return false
        return try {
            output.write(RECEIPT_CONTENT.toByteArray(StandardCharsets.UTF_8))
            output.flush()
            output.fd.sync()
            atomic.finishWrite(output)
            true
        } catch (_: Throwable) {
            atomic.failWrite(output)
            false
        }
    }

    private fun receiptFile(sessionID: String): File? {
        if (!UUID_PATTERN.matches(sessionID)) return null
        val root = runCatching { recordingsRoot.canonicalFile }.getOrNull() ?: return null
        val directory = runCatching { File(root, sessionID).canonicalFile }.getOrNull() ?: return null
        if (directory.parentFile != root || !directory.isDirectory || Files.isSymbolicLink(directory.toPath())) return null
        return File(directory, FILE_NAME)
    }

    private companion object {
        const val FILE_NAME = "configured-export.receipt"
        const val RECEIPT_CONTENT = "version=1\nstatus=exported\n"
        val UUID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    }
}
