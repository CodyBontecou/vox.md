package md.vox.android.data

import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CapturePreset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RecordingAudioArtifactPolicyTest {
    @Test fun offDoesNotCopySourceAudioIntoDestinationArtifacts() {
        val policy = recordingAudioArtifactPolicy(preset(CaptureAudioSaveMode.OFF))

        assertFalse(policy.retainsSourceAudio)
        assertFalse(policy.includesMarkdownReference)
    }

    @Test fun alongsideCopiesSourceAudioBesideTheTranscriptNote() {
        val policy = recordingAudioArtifactPolicy(preset(CaptureAudioSaveMode.ALONGSIDE_NOTE))

        assertTrue(policy.retainsSourceAudio)
        assertEquals("Inbox", policy.artifactFolder)
    }

    @Test fun attachmentsModeCopiesSourceAudioIntoConfiguredFolder() {
        val policy = recordingAudioArtifactPolicy(preset(CaptureAudioSaveMode.ATTACHMENTS_FOLDER))

        assertTrue(policy.retainsSourceAudio)
        assertEquals("Media/Recordings", policy.artifactFolder)
    }

    @Test fun alongsideUsesExistingNotesParentFolder() {
        val preset = preset(CaptureAudioSaveMode.ALONGSIDE_NOTE).copy(
            noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE,
            existingNotePath = "Journal/Meetings/standup.md",
        )

        assertEquals("Journal/Meetings", recordingAudioArtifactPolicy(preset).artifactFolder)
    }

    @Test fun retainedAudioReferencePolicyPreservesVisibilityAndPlacement() {
        val preset = preset(CaptureAudioSaveMode.ATTACHMENTS_FOLDER).copy(
            embedAudioInMarkdown = true,
            audioEmbedPlacement = CaptureAudioEmbedPlacement.BEFORE_TEXT,
        )

        val policy = recordingAudioArtifactPolicy(preset)

        assertTrue(policy.includesMarkdownReference)
        assertEquals(CaptureAudioEmbedPlacement.BEFORE_TEXT, policy.referencePlacement)
    }

    private fun preset(mode: CaptureAudioSaveMode) = CapturePreset(
        id = "33333333-3333-4333-8333-333333333333",
        name = "Default",
        symbol = "description",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "capture-{id}.md",
        metadataFields = emptyList<CaptureMetadataField>(),
        attachmentsFolder = "Media/Recordings",
        audioSaveMode = mode,
        embedAudioInMarkdown = true,
    )
}
