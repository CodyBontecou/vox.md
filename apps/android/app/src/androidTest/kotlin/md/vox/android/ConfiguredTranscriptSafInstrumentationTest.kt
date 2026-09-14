package md.vox.android

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureExportFileFormat
import md.vox.android.capturedomain.CaptureExportFileMode
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ConfiguredTranscriptSafInstrumentationTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val treeUri: Uri
        get() = DocumentsContract.buildTreeDocumentUri(TestDocumentsProvider.AUTHORITY, TestDocumentsProvider.ROOT_ID)

    @Before
    fun clearProvider() {
        deleteProviderDocuments()
    }

    @After
    fun cleanProvider() {
        deleteProviderDocuments()
    }

    @Test
    fun newFileExportCreatesUniqueVerifiedSafDocuments() {
        val exporter = AndroidConfiguredTranscriptExporter(context)
        val settings = settings(format = CaptureExportFileFormat.MARKDOWN)

        val first = exporter.export(state(), settings) as ConfiguredTranscriptExportResult.Exported
        val second = exporter.export(state(), settings) as ConfiguredTranscriptExportResult.Exported

        assertEquals("planning-2024-01-01.md", first.displayName)
        assertEquals("planning-2024-01-01-2.md", second.displayName)
        val content = context.contentResolver.openInputStream(Uri.parse(first.documentUri))!!.bufferedReader().use { it.readText() }
        assertTrue(content.startsWith("## Transcript - 2024-01-01"))
        assertTrue(content.contains("First line\nSecond line"))
    }

    @Test
    fun appendExportReadsMergesWritesAndVerifiesThroughSaf() {
        val exporter = AndroidConfiguredTranscriptExporter(context)
        val settings = settings(
            format = CaptureExportFileFormat.TEXT,
            mode = CaptureExportFileMode.APPEND,
            appendFileName = "daily",
        )

        val first = exporter.export(state(), settings) as ConfiguredTranscriptExportResult.Exported
        exporter.export(
            state().copy(
                sessionID = "22222222-2222-4222-8222-222222222222",
                transcript = "Follow-up",
                tags = listOf("next"),
            ),
            settings,
        ) as ConfiguredTranscriptExportResult.Exported

        val content = context.contentResolver.openInputStream(Uri.parse(first.documentUri))!!.bufferedReader().use { it.readText() }
        assertTrue(content.contains("First line\nSecond line\n\nTags: work, voice-note"))
        assertTrue(content.contains("\n\n---\n\nFollow-up\n\nTags: next"))
    }

    @Test
    fun obsidianAppendKeepsOneFrontmatterDocumentAndMergesTags() {
        val exporter = AndroidConfiguredTranscriptExporter(context)
        val settings = settings(
            format = CaptureExportFileFormat.MARKDOWN,
            mode = CaptureExportFileMode.APPEND,
            appendFileName = "obsidian",
            mdObsidianEnabled = true,
        )

        val first = exporter.export(state(), settings) as ConfiguredTranscriptExportResult.Exported
        exporter.export(
            state().copy(
                sessionID = "22222222-2222-4222-8222-222222222222",
                transcript = "Follow-up",
                title = "Second title",
                category = "Different category",
                tags = listOf("voice-note", "next"),
            ),
            settings,
        ) as ConfiguredTranscriptExportResult.Exported

        val content = context.contentResolver.openInputStream(Uri.parse(first.documentUri))!!.bufferedReader().use { it.readText() }
        assertTrue(content.startsWith("---\ncategory: \"Meetings\""))
        assertEquals(1, Regex("(?m)^category:").findAll(content).count())
        assertEquals(1, Regex("(?m)^title:").findAll(content).count())
        assertTrue(content.contains("tags: [\"work\", \"voice-note\", \"next\"]"))
        assertTrue(content.contains("First line\nSecond line"))
        assertTrue(content.contains("Follow-up"))
    }

    @Test
    fun yamlMarkdownExportWritesFrontmatterDocumentThroughSaf() {
        val exporter = AndroidConfiguredTranscriptExporter(context)
        val settings = settings(
            format = CaptureExportFileFormat.YAML,
            yamlUsesMarkdownExtension = true,
        )

        val result = exporter.export(state(), settings) as ConfiguredTranscriptExportResult.Exported

        assertEquals("planning-2024-01-01.md", result.displayName)
        val content = readTextDocument(Uri.parse(result.documentUri))
        assertTrue(content.startsWith("---\nid: \"11111111-1111-4111-8111-111111111111\""))
        assertTrue(content.contains("text: |-\n  First line\n  Second line"))
        assertTrue(content.endsWith("title: \"Planning Notes\"\n---"))
    }

    @Test
    fun markdownTemplateExportReadsSelectedSafDocumentAndEnrichesIt() {
        val templateUri = createDocument(
            displayName = "meeting-template.md",
            mimeType = "text/markdown",
            content = "---\ncreated: <% tp.date.now(\"YYYY-MM-DD\") %>\ntags: [\"template\"]\n---\n\n# Meeting",
        )
        val exporter = AndroidConfiguredTranscriptExporter(context)
        val settings = settings(
            format = CaptureExportFileFormat.MARKDOWN,
            markdownTemplateEnabled = true,
            markdownTemplateUri = templateUri.toString(),
        )

        val result = exporter.export(state(), settings) as ConfiguredTranscriptExportResult.Exported

        assertEquals("planning-2024-01-01.md", result.displayName)
        val content = readTextDocument(Uri.parse(result.documentUri))
        assertTrue(content.startsWith("---\ncreated: "))
        assertTrue(content.contains("tags: [\"template\", \"work\", \"voice-note\"]"))
        assertTrue(content.contains("category: Meetings"))
        assertTrue(content.contains("title: Planning Notes"))
        assertTrue(content.contains("# Meeting\n\nFirst line\nSecond line"))
    }

    @Test
    fun newFileExportCopiesAudioBesideTranscriptAndEmbedsAtTop() {
        val audioBytes = byteArrayOf(82, 73, 70, 70, 1, 2, 3, 4)
        val audioSource = createDocument("retained-source.wav", "audio/wav", audioBytes)
        val exporter = AndroidConfiguredTranscriptExporter(context)
        val settings = settings(
            format = CaptureExportFileFormat.MARKDOWN,
            embedAudioInMarkdown = true,
            audioEmbedPlacement = CaptureAudioEmbedPlacement.BEFORE_TEXT,
        )

        val result = exporter.export(
            state(),
            settings,
            ConfiguredTranscriptAudioSource(
                contentUri = audioSource.toString(),
                displayName = "Recording-11111111.wav",
                saveMode = CaptureAudioSaveMode.ALONGSIDE_NOTE,
                attachmentsFolder = "Attachments",
            ),
        ) as ConfiguredTranscriptExportResult.Exported

        assertEquals("planning-2024-01-01.md", result.displayName)
        assertTrue(readDocument(documentUri("planning-2024-01-01.wav")).contentEquals(audioBytes))
        val content = readTextDocument(Uri.parse(result.documentUri))
        assertTrue(content.startsWith("---\naudio: \"planning-2024-01-01.wav\"\n---\n\n![[planning-2024-01-01.wav]]"))
        assertTrue(content.indexOf("![[planning-2024-01-01.wav]]") < content.indexOf("## Transcript"))
    }

    @Test
    fun attachmentsAudioExportCopiesIntoSubfolderAndEmbedsAtBottom() {
        val audioBytes = byteArrayOf(82, 73, 70, 70, 9, 8, 7, 6)
        val audioSource = createDocument("retained-source.wav", "audio/wav", audioBytes)
        val exporter = AndroidConfiguredTranscriptExporter(context)
        val settings = settings(
            format = CaptureExportFileFormat.MARKDOWN,
            embedAudioInMarkdown = true,
            audioEmbedPlacement = CaptureAudioEmbedPlacement.AFTER_TEXT,
        )

        val result = exporter.export(
            state(),
            settings,
            ConfiguredTranscriptAudioSource(
                contentUri = audioSource.toString(),
                displayName = "Recording-11111111.wav",
                saveMode = CaptureAudioSaveMode.ATTACHMENTS_FOLDER,
                attachmentsFolder = "Media/Recordings",
            ),
        ) as ConfiguredTranscriptExportResult.Exported

        val relativePath = "Media/Recordings/planning-2024-01-01.wav"
        assertTrue(readDocument(documentUri(relativePath)).contentEquals(audioBytes))
        val content = readTextDocument(Uri.parse(result.documentUri))
        assertTrue(content.startsWith("---\naudio: \"$relativePath\"\n---"))
        assertTrue(content.endsWith("![[$relativePath]]"))
        assertTrue(content.indexOf("## Transcript") < content.indexOf("![[$relativePath]]"))
    }

    private fun settings(
        format: CaptureExportFileFormat,
        mode: CaptureExportFileMode = CaptureExportFileMode.NEW_FILE,
        appendFileName: String = "daily",
        mdObsidianEnabled: Boolean = false,
        markdownTemplateEnabled: Boolean = false,
        markdownTemplateUri: String? = null,
        yamlUsesMarkdownExtension: Boolean = false,
        embedAudioInMarkdown: Boolean = false,
        audioEmbedPlacement: CaptureAudioEmbedPlacement = CaptureAudioEmbedPlacement.AFTER_TEXT,
    ) = CapturePresetExportSettings(
        usesCustomExportSettings = true,
        exportEnabled = true,
        format = format,
        mode = mode,
        destinationTreeUri = treeUri.toString(),
        destinationName = "Test Documents",
        newFileNameTemplate = "planning-{date}",
        appendFileName = appendFileName,
        markdownTemplateEnabled = markdownTemplateEnabled,
        markdownTemplateUri = markdownTemplateUri,
        mdObsidianEnabled = mdObsidianEnabled,
        yamlUsesMarkdownExtension = yamlUsesMarkdownExtension,
        embedAudioInMarkdown = embedAudioInMarkdown,
        audioEmbedPlacement = audioEmbedPlacement,
    )

    private fun state() = RecordingTranscriptionState(
        sessionID = "11111111-1111-4111-8111-111111111111",
        phase = RecordingTranscriptionPhase.COMPLETED,
        modelID = "vosk-small-en-us",
        modelName = "English Small",
        languageTag = "en-US",
        durationMillis = 1_250,
        recordedAtEpochMillis = 1_704_164_645_678,
        completedAtEpochMillis = 1_704_164_700_000,
        transcript = "First line\nSecond line",
        title = "Planning Notes",
        tags = listOf("work", "voice-note"),
        category = "Meetings",
    )

    private fun deleteProviderDocuments() {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, TestDocumentsProvider.ROOT_ID)
        val ids = context.contentResolver.query(
            children,
            arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
            null,
            null,
            null,
        )?.use { cursor ->
            buildList {
                while (cursor.moveToNext()) add(cursor.getString(0))
            }
        }.orEmpty()
        ids.forEach { id ->
            DocumentsContract.deleteDocument(
                context.contentResolver,
                DocumentsContract.buildDocumentUriUsingTree(treeUri, id),
            )
        }
    }

    private fun createDocument(displayName: String, mimeType: String, content: String): Uri =
        createDocument(displayName, mimeType, content.toByteArray())

    private fun createDocument(displayName: String, mimeType: String, content: ByteArray): Uri {
        val parent = DocumentsContract.buildDocumentUriUsingTree(treeUri, TestDocumentsProvider.ROOT_ID)
        val uri = requireNotNull(DocumentsContract.createDocument(context.contentResolver, parent, mimeType, displayName))
        context.contentResolver.openOutputStream(uri, "wt")!!.use { it.write(content) }
        return uri
    }

    private fun documentUri(documentID: String): Uri =
        DocumentsContract.buildDocumentUriUsingTree(treeUri, documentID)

    private fun readDocument(uri: Uri): ByteArray = context.contentResolver.openInputStream(uri)!!.use { it.readBytes() }

    private fun readTextDocument(uri: Uri): String =
        context.contentResolver.openInputStream(uri)!!.bufferedReader().use { it.readText() }
}
