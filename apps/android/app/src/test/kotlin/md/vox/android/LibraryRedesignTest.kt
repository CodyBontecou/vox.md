package md.vox.android

import md.vox.android.capturedomain.CaptureHistoryDetail
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureTextProcessingOutcome
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class LibraryRedesignTest {
    private val pending = CaptureHistoryDetail(
        requestID = "22222222-2222-4222-8222-222222222222",
        createdAtEpochMillis = 1_000,
        state = CaptureState.RETRYABLE_FAILURE,
        capturedText = "Follow up with Sam",
        capturedURL = null,
        presetID = "33333333-3333-4333-8333-333333333333",
        logicalPath = "Inbox/Follow up.md",
        preparedMarkdown = "## 10:42\n\nFollow up with Sam\n",
        processingMode = CaptureProcessingMode.CLEAN,
        processingOutcome = CaptureTextProcessingOutcome.MODEL_UNAVAILABLE,
    )

    @Test fun routeLogRecordsCaptureProcessingShapeAndFailedDelivery() {
        val steps = captureRouteLogEntries(pending)
        assertEquals(
            listOf("Captured", "Processing skipped", "Shaped with the route template", "Delivery failed"),
            steps.map { it.title.source },
        )
        assertEquals(CaptureRouteLogOutcome.SKIPPED, steps[1].outcome)
        assertEquals(CaptureRouteLogOutcome.FAILED, steps.last().outcome)
        assertEquals(1_000L, steps.first().atEpochMillis)
    }

    @Test fun routeLogShowsDeliveredPathAndOmitsUnrequestedProcessing() {
        val steps = captureRouteLogEntries(
            pending.copy(state = CaptureState.COMPLETED, processingMode = CaptureProcessingMode.NONE, preparedMarkdown = null),
        )
        assertEquals(listOf("Captured", "Delivered"), steps.map { it.title.source })
        assertEquals(listOf<Any>("Inbox/Follow up.md"), steps.last().detail?.arguments)
    }

    @Test fun routeLogKeepsInFlightDeliveryPending() {
        val step = captureRouteLogEntries(pending.copy(state = CaptureState.COMMITTING)).last()
        assertEquals(CaptureRouteLogOutcome.PENDING, step.outcome)
        assertEquals("Capture in progress", step.title.source)
    }

    @Test fun exportAllJoinsPendingCapturesAndCompletedTranscriptsOnly() {
        val transcript = RecordingTranscriptionState(
            sessionID = "00000001-1111-4111-8111-000000000001",
            phase = RecordingTranscriptionPhase.COMPLETED,
            recordedAtEpochMillis = 2_000,
            transcript = "Spoken words",
        )
        val unfinished = transcript.copy(sessionID = "00000002-1111-4111-8111-000000000002", phase = RecordingTranscriptionPhase.PROCESSING)
        val markdown = libraryMarkdownExport(listOf(pending), listOf(transcript, unfinished))!!
        assertTrue(markdown.startsWith("## 10:42\n\nFollow up with Sam"))
        assertTrue(markdown.contains("\n\n---\n\n## Transcript - "))
        assertTrue(markdown.contains("Spoken words"))
        assertEquals(1, Regex("---").findAll(markdown).count())
    }

    @Test fun exportAllIsUnavailableWithoutText() {
        assertNull(libraryMarkdownExport(emptyList(), emptyList()))
    }

    @Test fun dayGroupingStartsAtLocalMidnight() {
        val noon = Calendar.getInstance().apply {
            set(2026, Calendar.NOVEMBER, 6, 12, 30, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        val midnight = Calendar.getInstance().apply {
            set(2026, Calendar.NOVEMBER, 6, 0, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        assertEquals(midnight, libraryStartOfDay(noon))
        assertEquals(midnight, libraryStartOfDay(midnight))
    }
}
