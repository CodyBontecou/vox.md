package md.vox.android.platformservices

import md.vox.android.capturedomain.*
import org.junit.Assert.*
import org.junit.Test

class RecordingProcessingReuseTest {
    private val preset = CapturePreset(id="abababab-abab-4bab-8bab-abababababab",name="Test",symbol="sparkles",revision=1,
        logicalFolder="Inbox",noteNameTemplate="capture-{id}",metadataFields=emptyList(),processingEnabled=true,
        processingMode=CaptureProcessingMode.CUSTOM,customProcessingInstruction="Translate into Spanish")
    private val state = RecordingTranscriptionState(sessionID="abababab-abab-4bab-8bab-abababababab",phase=RecordingTranscriptionPhase.COMPLETED,
        transcript="Hello",cleanedTranscript="Hola")
    @Test fun completedPreferredTextKeepsItsRawAuditSourceAndIsNotTransformedTwice() {
        val result=requireNotNull(reusableRecordingProcessing(state,preset,"Hola",preset))
        assertEquals("Hello",result.originalText);assertEquals("Hola",result.processedText)
    }
    @Test fun editedTextChangedPolicyOrIncompleteProcessingCannotReuseAnOldResult() {
        assertNull(reusableRecordingProcessing(state,preset,"Edited text",preset))
        assertNull(reusableRecordingProcessing(state,preset,"Hola",preset.copy(customProcessingInstruction="Translate into French")))
        assertNull(reusableRecordingProcessing(state,preset,"Hola",preset.copy(capturePrompt="different context")))
        assertNull(reusableRecordingProcessing(state.copy(phase=RecordingTranscriptionPhase.FAILED),preset,"Hola",preset))
        assertNull(reusableRecordingProcessing(state.copy(cleanedTranscript=null),preset,"Hello",preset))
    }
}
