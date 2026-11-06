package md.vox.android.ui

import md.vox.android.VoxUiText
import md.vox.android.capturedomain.CaptureTextProcessingOutcome
import org.junit.Assert.*
import org.junit.Test

class LocalInstructionDeliveryNoticeTest {
    @Test fun successfulDeliveryDoesNotHideProcessingFailureOrMissingModel() {
        for (outcome in listOf(CaptureTextProcessingOutcome.MODEL_FAILURE,CaptureTextProcessingOutcome.MODEL_UNAVAILABLE)) {
            val notice=deliveredCaptureNotice(outcome)
            assertEquals("%@ · %@",notice.source)
            assertEquals("Capture sent",(notice.arguments[0] as VoxUiText).source)
            assertTrue((notice.arguments[1] as VoxUiText).source.contains("the original text was kept"))
        }
        assertEquals("Capture sent",deliveredCaptureNotice(CaptureTextProcessingOutcome.APPLIED).source)
    }
}
