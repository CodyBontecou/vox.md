package md.vox.android

import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CaptureRouteOverride
import md.vox.android.capturedomain.CaptureState
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureSignalStatesTest {
    @Test
    fun allQuickActionsPanelListsEveryActionExactlyOnce() {
        val listed = CaptureQuickActionGroup.entries.flatMap { it.actions }
        assertEquals(CaptureBarAction.entries.toSet(), listed.toSet())
        assertEquals(listed.size, listed.toSet().size)
        assertEquals(listOf("MARKDOWN", "INSERT", "EDIT", "ATTACH"), CaptureQuickActionGroup.entries.map { it.title.source })
    }

    @Test
    fun microphoneDenialIsPermanentOnlyWhenTheSystemStopsAsking() {
        // First refusal: the system will explain next time.
        assertFalse(microphoneDeniedPermanently(granted = false, rationaleBefore = false, rationaleAfter = true, wasBlocked = false))
        // Second refusal ("Don't ask again").
        assertTrue(microphoneDeniedPermanently(granted = false, rationaleBefore = true, rationaleAfter = false, wasBlocked = false))
        // A dismissed first dialog reads the same as never asked.
        assertFalse(microphoneDeniedPermanently(granted = false, rationaleBefore = false, rationaleAfter = false, wasBlocked = false))
        // Already blocked: the request returns immediately without a dialog.
        assertTrue(microphoneDeniedPermanently(granted = false, rationaleBefore = false, rationaleAfter = false, wasBlocked = true))
        assertFalse(microphoneDeniedPermanently(granted = true, rationaleBefore = true, rationaleAfter = false, wasBlocked = true))
    }

    @Test
    fun vaultIsUnreachableWhenAccessIsGoneOrACaptureWaitsOnPermission() {
        val waiting = listOf(item(CaptureState.NEEDS_PERMISSION), item(CaptureState.QUEUED), item(CaptureState.COMPLETED))
        assertTrue(captureVaultIsUnreachable(waiting, hasVaultAccess = true))
        assertTrue(captureVaultIsUnreachable(emptyList(), hasVaultAccess = false))
        assertFalse(captureVaultIsUnreachable(listOf(item(CaptureState.QUEUED)), hasVaultAccess = true))
        assertEquals(2, captureWaitingCount(waiting + item(CaptureState.DISCARDED) + item(CaptureState.PERMANENT_FAILURE)))
    }

    @Test
    fun destinationLineNamesTheRouteNoteAndHeading() {
        val preset = CapturePreset(
            "12345678-1234-4234-8234-123456789abc",
            "Meeting Notes",
            "",
            revision = 1,
            logicalFolder = "Meetings",
            noteNameTemplate = "{date}.md",
            metadataFields = emptyList(),
            headingTitle = "Notes",
            headingLevel = 2,
        )
        assertEquals("→ Meeting Notes · Meetings/{date}.md › ## Notes", captureDestinationLine(preset, null))
        assertEquals(
            "→ Meeting Notes · Journal/Today.md",
            captureDestinationLine(preset, CaptureRouteOverride("Journal/Today.md", CapturePlacementKind.PREPEND)),
        )
        val existing = preset.copy(noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE, existingNotePath = "Tasks.md", headingTitle = "")
        assertEquals("→ Meeting Notes · Tasks.md", captureDestinationLine(existing, null))
        assertEquals(null, captureDestinationLine(null, null))
    }

    @Test
    fun routeProgressReportsOnlyTheStepsAndroidRuns() {
        val status = RecordingStatus(sessionID = SESSION, phase = RecordingPhase.COMPLETED, elapsedMillis = 119_000)
        assertTrue(captureRouteSteps(status, null).isEmpty())

        val processing = captureRouteSteps(status, transcription(RecordingTranscriptionPhase.PROCESSING, progress = 0.42f))
        assertEquals(listOf(CaptureRouteStepState.DONE, CaptureRouteStepState.ACTIVE), processing.map { it.state })
        assertEquals(voxUiText("Captured · %@ audio", "1:59"), processing.first().title)

        val done = captureRouteSteps(status, transcription(RecordingTranscriptionPhase.COMPLETED, added = true))
        assertEquals(List(3) { CaptureRouteStepState.DONE }, done.map { it.state })
        assertEquals(voxUiText("Transcribed · %@, on device", "Whisper Small"), done[1].title)

        val failed = captureRouteSteps(status, transcription(RecordingTranscriptionPhase.FAILED))
        assertEquals(CaptureRouteStepState.PAUSED, failed.last().state)
    }

    private fun item(state: CaptureState) = CaptureHistoryItem(
        requestID = state.name,
        createdAtEpochMillis = 0,
        updatedAtEpochMillis = 0,
        state = state,
        attemptCount = 1,
    )

    private fun transcription(phase: RecordingTranscriptionPhase, progress: Float = 0f, added: Boolean = false) =
        RecordingTranscriptionState(
            sessionID = SESSION,
            phase = phase,
            progress = progress,
            modelName = "Whisper Small",
            durationMillis = 119_000,
            addedToDraft = added,
        )

    private companion object {
        const val SESSION = "11111111-1111-4111-8111-111111111111"
    }
}
