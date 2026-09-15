package md.vox.android

import java.util.TimeZone
import java.util.UUID
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureExportFileFormat
import md.vox.android.capturedomain.CaptureExportFileMode
import md.vox.android.capturedomain.CaptureExportYAMLProperty
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ConfiguredTranscriptExporterTest {
    companion object {
        // The planner formats fixed instants near UTC midnight in the JVM default
        // zone; pin it so expectations hold on UTC CI runners and dev machines alike.
        init {
            TimeZone.setDefault(TimeZone.getTimeZone("America/New_York"))
        }
    }

    private val state = RecordingTranscriptionState(
        sessionID = "11111111-1111-4111-8111-111111111111",
        phase = RecordingTranscriptionPhase.COMPLETED,
        modelID = "vosk-small-en-us",
        modelName = "English Small",
        languageTag = "en-US",
        durationMillis = 1_250,
        recordedAtEpochMillis = 1_704_164_645_678,
        completedAtEpochMillis = 1_704_164_645_678,
        transcript = "First line\nSecond line",
        title = "Planning Notes",
        tags = listOf("work", "voice-note"),
        category = "Meetings",
    )

    @Test
    fun `configured export failures expose stable translatable ui text`() {
        assertEquals(
            listOf(
                "Choose an export folder in this Capture Preset.",
                "The transcript was not exported because its retained audio could not be prepared.",
                "The configured transcript export failed.",
            ),
            ConfiguredTranscriptExportFailure.entries.map { it.uiText().source },
        )
        assertTrue(ConfiguredTranscriptExportFailure.entries.all { it.uiText().arguments.isEmpty() })
    }

    @Test
    fun `new file template resolves stable transcript values and strips configured extension`() {
        val plan = ConfiguredTranscriptExportPlanner.plan(
            state,
            CapturePresetExportSettings(
                usesCustomExportSettings = true,
                format = CaptureExportFileFormat.TEXT,
                newFileNameTemplate = "{date}-{id8}-{language}.txt",
            ),
        )

        assertEquals("2024-01-01-11111111-en-US", plan.baseName)
        assertEquals("txt", plan.extension)
        assertEquals("2024-01-01-11111111-en-US.txt", plan.displayName)
    }

    @Test
    fun `yaml markdown mode renders only selected governed properties inside frontmatter`() {
        val plan = ConfiguredTranscriptExportPlanner.plan(
            state,
            CapturePresetExportSettings(
                usesCustomExportSettings = true,
                format = CaptureExportFileFormat.YAML,
                yamlUsesMarkdownExtension = true,
                yamlProperties = setOf(CaptureExportYAMLProperty.ID, CaptureExportYAMLProperty.TEXT),
            ),
        )

        assertEquals("md", plan.extension)
        assertTrue(plan.content.startsWith("---\nid: \"11111111-1111-4111-8111-111111111111\"\ntext: |-"))
        assertTrue(plan.content.endsWith("\n---"))
        assertFalse(plan.content.contains("duration_seconds:"))
        assertFalse(plan.content.contains("model_used:"))
    }

    @Test
    fun `filename cleanup matches ios space and extension rules`() {
        val plan = ConfiguredTranscriptExportPlanner.plan(
            state,
            CapturePresetExportSettings(
                usesCustomExportSettings = true,
                format = CaptureExportFileFormat.MARKDOWN,
                newFileNameTemplate = "  Planning Notes.backup  ",
            ),
        )

        assertEquals("Planning-Notes", plan.baseName)
        assertEquals("Planning-Notes.md", plan.displayName)
    }

    @Test
    fun `json append creates an array and ignores the same transcript identity on retry`() {
        val settings = CapturePresetExportSettings(
            usesCustomExportSettings = true,
            format = CaptureExportFileFormat.JSON,
            mode = CaptureExportFileMode.APPEND,
        )
        val plan = ConfiguredTranscriptExportPlanner.plan(state, settings)

        val first = ConfiguredTranscriptExportPlanner.mergeForAppend("", plan, settings, state.sessionID)
        val retried = ConfiguredTranscriptExportPlanner.mergeForAppend(first, plan, settings, state.sessionID)

        assertTrue(first.startsWith("[\n"))
        assertTrue(first.endsWith("]\n"))
        assertEquals(first, retried)
    }

    @Test
    fun `ordinary markdown append inserts a divider while obsidian append preserves document flow`() {
        val ordinary = CapturePresetExportSettings(
            usesCustomExportSettings = true,
            format = CaptureExportFileFormat.MARKDOWN,
            mode = CaptureExportFileMode.APPEND,
        )
        val ordinaryPlan = ConfiguredTranscriptExportPlanner.plan(state, ordinary)
        assertTrue(
            ConfiguredTranscriptExportPlanner.mergeForAppend("Existing", ordinaryPlan, ordinary, state.sessionID)
                .startsWith("Existing\n\n---\n\n"),
        )

        val obsidian = ordinary.copy(mdObsidianEnabled = true)
        val obsidianPlan = ConfiguredTranscriptExportPlanner.plan(state, obsidian)
        val merged = ConfiguredTranscriptExportPlanner.mergeForAppend("Existing", obsidianPlan, obsidian, state.sessionID)
        assertTrue(merged.startsWith("---\ncategory: \"Meetings\""))
        assertTrue(merged.contains("\n---\n\nExisting\n\n## Transcript - "))
        assertEquals(1, Regex("(?m)^category:").findAll(merged).count())
    }

    @Test
    fun `yaml markdown append becomes one obsidian document with a markdown transcript entry`() {
        val settings = CapturePresetExportSettings(
            usesCustomExportSettings = true,
            format = CaptureExportFileFormat.YAML,
            mode = CaptureExportFileMode.APPEND,
            yamlUsesMarkdownExtension = true,
        )

        val plan = ConfiguredTranscriptExportPlanner.plan(state, settings)
        val merged = ConfiguredTranscriptExportPlanner.mergeForAppend(
            "---\ntitle: \"Existing title\"\n---\n\nExisting body",
            plan,
            settings,
            state.sessionID,
        )

        assertTrue(merged.startsWith("---\ntitle: \"Existing title\"\ncategory: \"Meetings\""))
        assertTrue(merged.contains("Existing body\n\n## Transcript - "))
        assertFalse(merged.contains("duration_seconds:"))
        assertEquals(1, Regex("(?m)^title:").findAll(merged).count())
    }

    @Test
    fun `markdown template resolves supported expressions fills enrichment and appends transcript`() {
        val settings = CapturePresetExportSettings(
            usesCustomExportSettings = true,
            format = CaptureExportFileFormat.MARKDOWN,
            markdownTemplateEnabled = true,
            markdownTemplateUri = "content://test/template",
        )
        val plan = ConfiguredTranscriptExportPlanner.plan(
            state = state,
            settings = settings,
            markdownTemplate = "---\ntitle:\ntags: []\ncreated: <% tp.date.now(\"YYYY-MM-DD\") %>\nid: <% crypto.randomUUID() %>\n---\n\n# Voice",
            nowEpochMillis = 1_704_164_645_678,
            randomUUID = { UUID.fromString("22222222-2222-4222-8222-222222222222") },
        )

        assertEquals("md", plan.extension)
        assertTrue(plan.content.contains("title: Planning Notes"))
        assertTrue(plan.content.contains("category: Meetings"))
        assertTrue(plan.content.contains("tags: [\"work\", \"voice-note\"]"))
        assertTrue(plan.content.contains("created: 2024-01-01"))
        assertTrue(plan.content.contains("id: 22222222-2222-4222-8222-222222222222"))
        assertTrue(plan.content.endsWith("First line\nSecond line\n"))
    }

    @Test
    fun `markdown audio reference is frontmatter plus top or bottom obsidian embed`() {
        val base = CapturePresetExportSettings(
            usesCustomExportSettings = true,
            format = CaptureExportFileFormat.MARKDOWN,
            embedAudioInMarkdown = true,
        )

        val top = ConfiguredTranscriptExportPlanner.plan(
            state,
            base.copy(audioEmbedPlacement = CaptureAudioEmbedPlacement.BEFORE_TEXT),
            audioRelativePath = "Media/planning.wav",
        ).content
        val bottom = ConfiguredTranscriptExportPlanner.plan(
            state,
            base.copy(audioEmbedPlacement = CaptureAudioEmbedPlacement.AFTER_TEXT),
            audioRelativePath = "Media/planning.wav",
        ).content

        assertTrue(top.startsWith("---\naudio: \"Media/planning.wav\"\n---\n\n![[Media/planning.wav]]"))
        assertTrue(top.indexOf("![[Media/planning.wav]]") < top.indexOf("## Transcript"))
        assertTrue(bottom.startsWith("---\naudio: \"Media/planning.wav\"\n---"))
        assertTrue(bottom.endsWith("![[Media/planning.wav]]"))
    }

    @Test
    fun `text and yaml include audio reference while json remains schema stable`() {
        val base = CapturePresetExportSettings(usesCustomExportSettings = true)

        val text = ConfiguredTranscriptExportPlanner.plan(
            state,
            base.copy(format = CaptureExportFileFormat.TEXT),
            audioRelativePath = "planning.wav",
        ).content
        val yaml = ConfiguredTranscriptExportPlanner.plan(
            state,
            base.copy(format = CaptureExportFileFormat.YAML),
            audioRelativePath = "planning.wav",
        ).content
        val json = ConfiguredTranscriptExportPlanner.plan(
            state,
            base.copy(format = CaptureExportFileFormat.JSON),
            audioRelativePath = "planning.wav",
        ).content

        assertTrue(text.endsWith("Audio: planning.wav"))
        assertTrue(yaml.endsWith("audio: \"planning.wav\""))
        assertFalse(json.contains("planning.wav"))
    }
}
