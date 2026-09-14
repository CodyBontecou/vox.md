package md.vox.android

import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.LocalCaptureTextProcessor
import md.vox.android.platformservices.DeterministicTranscriptEnrichment
import md.vox.android.platformservices.LocalSpeakerDiarizer
import md.vox.android.platformservices.SpeakerObservation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LocalIntelligenceInstrumentationTest {
    @Test
    fun localProcessingProducesChecklistMeetingTitleTagsAndCategoryOutcomes() {
        val checklist = requireNotNull(
            LocalCaptureTextProcessor.process(
                originalText = "Prepare agenda\nSend launch notes",
                preset = preset(CaptureProcessingMode.TODO_LIST),
                isVoiceCapture = true,
            ),
        )
        assertEquals("- [ ] Prepare agenda\n- [ ] Send launch notes", checklist.processedText)

        val meeting = requireNotNull(
            LocalCaptureTextProcessor.process(
                originalText = "Meeting discussed launch. Maya will send launch notes.",
                preset = preset(CaptureProcessingMode.MEETING_NOTES),
                isVoiceCapture = true,
            ),
        )
        assertTrue(meeting.processedText.startsWith("## Notes"))
        assertTrue(meeting.processedText.contains("## Action Items"))
        assertTrue(meeting.processedText.contains("- [ ] Maya will send launch notes."))

        val metadata = DeterministicTranscriptEnrichment.enrich(
            "Launch meeting agenda. Launch discussion and launch notes were discussed.",
        )
        assertEquals("Launch meeting agenda.", metadata.title)
        assertEquals("Meetings", metadata.category)
        assertEquals("launch", metadata.tags.first())
        assertTrue(metadata.tags.contains("agenda"))
        assertTrue(metadata.tags.contains("discussion"))
    }

    @Test
    fun localSpeakerDiarizationLabelsGroundedTurnsAndPreservesFallback() {
        val firstVoice = DoubleArray(16).also { it[0] = 1.0 }
        val secondVoice = DoubleArray(16).also { it[1] = 1.0 }
        val labeled = LocalSpeakerDiarizer.diarize(
            observations = listOf(
                SpeakerObservation("Opening update", firstVoice, 180, 0),
                SpeakerObservation("Second perspective", secondVoice, 180, 0),
            ),
            fallbackTranscript = "Opening update Second perspective",
        )
        assertEquals(2, labeled.speakerCount)
        assertEquals("Speaker 1: Opening update\n\nSpeaker 2: Second perspective", labeled.transcript)

        val original = "Every original word remains"
        val fallback = LocalSpeakerDiarizer.diarize(
            observations = listOf(SpeakerObservation(original, null, 0, 0)),
            fallbackTranscript = original,
        )
        assertEquals(0, fallback.speakerCount)
        assertEquals(original, fallback.transcript)
        assertTrue(fallback.skipReason.orEmpty().contains("preserved"))
    }

    private fun preset(mode: CaptureProcessingMode) = CapturePreset(
        id = "99999999-9999-4999-8999-999999999999",
        name = "Local intelligence test",
        symbol = "sparkles",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "capture-{id}",
        metadataFields = listOf(CaptureMetadataField("source", "device-test")),
        processingEnabled = true,
        processingMode = mode,
    )
}
