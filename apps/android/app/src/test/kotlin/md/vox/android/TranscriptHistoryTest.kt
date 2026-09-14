package md.vox.android

import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TranscriptHistoryTest {
    private val state = RecordingTranscriptionState(
        sessionID = "11111111-1111-4111-8111-111111111111",
        phase = RecordingTranscriptionPhase.COMPLETED,
        modelID = "vosk-small-es",
        modelName = "Español Small",
        languageTag = "es-ES",
        durationMillis = 62_000,
        recordedAtEpochMillis = 1_700_000_000_000,
        completedAtEpochMillis = 1_700_000_000_000,
        transcript = "palabras crudas del micrófono",
        cleanedTranscript = "Revisión del proyecto mañana",
        title = "Revisión semanal",
        tags = listOf("proyecto", "mañana"),
        category = "Trabajo",
    )

    @Test fun searchIsMultiTokenAndDiacriticInsensitive() {
        assertTrue(TranscriptSearch.matches(state, "revision manana"))
        assertTrue(TranscriptSearch.matches(state, "crudas microfono"))
        assertTrue(TranscriptSearch.matches(state, "small es-es"))
        assertTrue(TranscriptSearch.matches(state, "semanal trabajo"))
        assertFalse(TranscriptSearch.matches(state, "revision viernes"))
    }

    @Test fun structuredExportsEscapeContentAndStayTerminated() {
        val quoted = state.copy(transcript = "raw", cleanedTranscript = "A \"quote\"\nand slash \\")
        assertTrue(TranscriptExporter.render(quoted, TranscriptExportFormat.JSON).contains("\\\"quote\\\"\\nand slash \\\\"))
        assertFalse(TranscriptExporter.render(quoted, TranscriptExportFormat.YAML).endsWith('\n'))
        assertTrue(TranscriptExporter.render(quoted, TranscriptExportFormat.MARKDOWN).startsWith("## Transcript - "))
        assertFalse(TranscriptExporter.render(quoted, TranscriptExportFormat.MARKDOWN).contains("Duration"))
        assertTrue(TranscriptExporter.render(quoted, TranscriptExportFormat.JSON).contains("\"tags\" : [\"proyecto\", \"mañana\"]"))
    }

    @Test fun yamlIncludesEveryGovernedTranscriptPropertyInStableIosOrder() {
        val yaml = TranscriptExporter.render(state, TranscriptExportFormat.YAML)
        assertEquals(
            """id: "11111111-1111-4111-8111-111111111111"
text: |-
  Revisión del proyecto mañana
date: "2023-11-14T22:13:20.000Z"
duration_seconds: 62.000
model_used: "Español Small"
language: "es-ES"
tags: ["proyecto", "mañana"]
category: "Trabajo"
title: "Revisión semanal"""",
            yaml,
        )
    }

    @Test fun exportDateUsesRecordingStartInsteadOfCompletionTime() {
        val started = state.copy(
            recordedAtEpochMillis = 1_700_000_000_000,
            completedAtEpochMillis = 1_700_086_400_000,
        )

        assertTrue(TranscriptExporter.render(started, TranscriptExportFormat.YAML).contains("2023-11-14T22:13:20.000Z"))
        assertTrue(TranscriptExporter.render(started, TranscriptExportFormat.MARKDOWN).contains("2023-11-14"))
    }

    @Test fun allFourTranscriptExportFormatsRemainAvailable() {
        assertEquals(
            listOf("Markdown" to "md", "Plain Text" to "txt", "JSON" to "json", "YAML" to "yaml"),
            TranscriptExportFormat.entries.map { it.label to it.extension },
        )
        assertEquals(
            "Revisión del proyecto mañana\n\nTags: proyecto, mañana",
            TranscriptExporter.render(state, TranscriptExportFormat.TEXT),
        )
    }
}
