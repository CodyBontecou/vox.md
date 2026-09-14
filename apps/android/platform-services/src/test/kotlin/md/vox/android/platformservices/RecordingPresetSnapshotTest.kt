package md.vox.android.platformservices

import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureExportFileFormat
import md.vox.android.capturedomain.CaptureExportFileMode
import md.vox.android.capturedomain.CaptureExportYAMLProperty
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CaptureLocationField
import md.vox.android.capturedomain.CaptureLocationStructuredField
import md.vox.android.capturedomain.CaptureLocationUnavailableBehavior
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.capturedomain.CapturePresetLocationPolicy
import md.vox.android.capturedomain.CaptureLocationLabelLookupClass
import md.vox.android.capturedomain.CURRENT_LOCATION_LABEL_CONSENT_VERSION
import md.vox.android.capturedomain.CaptureProcessingMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class RecordingPresetSnapshotTest {
    @Test fun fullPresetRoundTripsAtRecordingFreezePoint() {
        val preset = CapturePreset(
            id = "11111111-1111-4111-8111-111111111111",
            name = "Meetings",
            symbol = "mic",
            revision = 7,
            logicalFolder = "Meetings",
            noteNameTemplate = "{date}-{id}.md",
            metadataFields = listOf(CaptureMetadataField("kind", "meeting")),
            entryTemplateID = "22222222-2222-4222-8222-222222222222",
            processingEnabled = true,
            processingMode = CaptureProcessingMode.MEETING_NOTES,
            locationPolicy = CapturePresetLocationPolicy(
                isEnabled = true,
                labelLookupClass = CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK,
                labelConsentVersion = CURRENT_LOCATION_LABEL_CONSENT_VERSION,
                structuredFields = listOf(
                    CaptureLocationStructuredField(CaptureLocationField.LONGITUDE, "lng"),
                    CaptureLocationStructuredField(CaptureLocationField.COORDINATES, "point"),
                ),
            ),
            audioSaveMode = CaptureAudioSaveMode.ATTACHMENTS_FOLDER,
            embedAudioInMarkdown = true,
            exportSettings = CapturePresetExportSettings(
                usesCustomExportSettings = true,
                exportEnabled = true,
                format = CaptureExportFileFormat.YAML,
                mode = CaptureExportFileMode.APPEND,
                destinationTreeUri = "content://provider/tree/export",
                destinationName = "Exports",
                markdownTemplateEnabled = true,
                markdownTemplateUri = "content://provider/document/template",
                markdownTemplateName = "voice.md",
                yamlUsesMarkdownExtension = true,
                yamlProperties = setOf(CaptureExportYAMLProperty.ID, CaptureExportYAMLProperty.TEXT),
                embedAudioInMarkdown = true,
                audioEmbedPlacement = CaptureAudioEmbedPlacement.BEFORE_TEXT,
            ),
        )
        assertEquals(preset, RecordingPresetSnapshotCodec.decode(RecordingPresetSnapshotCodec.encode(preset)))
    }

    @Test fun malformedOrOversizedSnapshotsFailClosed() {
        assertNull(RecordingPresetSnapshotCodec.decode("{}"))
        assertNull(RecordingPresetSnapshotCodec.decode("x".repeat(65_537)))
    }

    @Test fun everyUnavailableBehaviorSurvivesTheRecordingFreezePoint() {
        CaptureLocationUnavailableBehavior.entries.forEach { behavior ->
            val preset = CapturePreset(
                id = "11111111-1111-4111-8111-111111111111",
                name = "Location behavior",
                symbol = "description",
                revision = 3,
                logicalFolder = "Inbox",
                noteNameTemplate = "capture-{id}.md",
                metadataFields = emptyList(),
                locationPolicy = CapturePresetLocationPolicy(isEnabled = true, unavailableBehavior = behavior),
            )
            assertEquals(
                behavior,
                RecordingPresetSnapshotCodec.decode(RecordingPresetSnapshotCodec.encode(preset))?.locationPolicy?.unavailableBehavior,
            )
        }
    }

    @Test fun markdownNoteTemplateSelectionIsFrozenAtRecordingStart() {
        val original = CapturePreset(
            id = "11111111-1111-4111-8111-111111111111",
            name = "Template freeze",
            symbol = "description",
            revision = 4,
            logicalFolder = "Inbox",
            noteNameTemplate = "capture-{id}.md",
            metadataFields = emptyList(),
            exportSettings = CapturePresetExportSettings(
                usesCustomExportSettings = true,
                markdownTemplateEnabled = true,
                markdownTemplateUri = "content://provider/document/template-v1",
                markdownTemplateName = "meeting-v1.md",
            ),
        )
        val frozenBytes = RecordingPresetSnapshotCodec.encode(original)

        val editedPreset = original.copy(
            revision = 5,
            exportSettings = original.exportSettings.copy(
                markdownTemplateUri = "content://provider/document/template-v2",
                markdownTemplateName = "meeting-v2.md",
            ),
        )
        val decoded = requireNotNull(RecordingPresetSnapshotCodec.decode(frozenBytes))

        assertEquals("content://provider/document/template-v1", decoded.exportSettings.markdownTemplateUri)
        assertEquals("meeting-v1.md", decoded.exportSettings.markdownTemplateName)
        assertEquals(4, decoded.revision)
        assertEquals("content://provider/document/template-v2", editedPreset.exportSettings.markdownTemplateUri)
    }

    @Test fun audioReferencePlacementSurvivesRecordingFreezePoint() {
        CaptureAudioEmbedPlacement.entries.forEach { placement ->
            val preset = CapturePreset(
                id = "11111111-1111-4111-8111-111111111111",
                name = "Meetings",
                symbol = "mic",
                revision = 7,
                logicalFolder = "Meetings",
                noteNameTemplate = "{date}-{id}.md",
                metadataFields = emptyList(),
                audioEmbedPlacement = placement,
            )

            val restored = RecordingPresetSnapshotCodec.decode(RecordingPresetSnapshotCodec.encode(preset))

            assertEquals(placement, restored?.audioEmbedPlacement)
        }
    }
}
