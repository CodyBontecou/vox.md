package md.vox.android

import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.LiveNoteRange
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.LiveNoteEvent
import md.vox.android.ui.LiveNoteEventKind
import md.vox.android.ui.liveNotePreviewLine
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveNotesUiTest {
    @Test fun breadcrumbJoinsVaultAndPath() {
        assertEquals("Vox Notes / Inbox / Radiator follow-up.md", liveNoteBreadcrumb("Vox Notes", "Inbox/Radiator follow-up.md"))
        assertEquals("Vox Notes / Daily / 2026-11-13.md · ## Log", liveNoteBreadcrumb("Vox Notes", "Daily/2026-11-13.md", "## Log"))
        assertEquals("Inbox / {title}.md", liveNoteBreadcrumb(null, "Inbox/{title}.md"))
    }

    @Test fun highlightFollowsEditsAroundAndInsideTheEntry() {
        val range = LiveNoteRange(10, 20)
        assertEquals(LiveNoteRange(13, 23), shiftLiveNoteHighlight(range, "a".repeat(30), "a".repeat(33), editStart = 2))
        assertEquals(LiveNoteRange(10, 25), shiftLiveNoteHighlight(range, "a".repeat(30), "a".repeat(35), editStart = 20))
        assertEquals(range, shiftLiveNoteHighlight(range, "a".repeat(30), "a".repeat(31), editStart = 25))
        assertNull(shiftLiveNoteHighlight(range, "a".repeat(30), "a".repeat(20), editStart = 10))
    }

    @Test fun justAddedLabelSitsAboveTheEntryLineWithoutMovingTheCaretIntoIt() {
        val file = "## Log\n- 09:12 Standup\n- 14:05 Idea\n"
        val entry = file.indexOf("Idea")
        val transformation = LiveNoteHighlightTransformation(
            LiveNoteRange(entry, entry + 4),
            androidx.compose.ui.graphics.Color.Blue,
            label = "JUST ADDED · 0:21",
        )
        val result = transformation.filter(androidx.compose.ui.text.AnnotatedString(file))
        val lineStart = file.indexOf("- 14:05")
        assertEquals(file.substring(0, lineStart) + "JUST ADDED · 0:21\n" + file.substring(lineStart), result.text.text)
        val shift = "JUST ADDED · 0:21\n".length
        assertEquals(entry + shift, result.offsetMapping.originalToTransformed(entry))
        assertEquals(lineStart, result.offsetMapping.transformedToOriginal(lineStart + 3))
        assertEquals(entry, result.offsetMapping.transformedToOriginal(entry + shift))
        assertEquals(5, result.offsetMapping.originalToTransformed(5))
    }

    @Test fun spokenTextIsSeparatedFromNeighbouringWords() {
        assertEquals("# Log call the office\n- 09:12", insertSpokenText("# Log\n- 09:12", 5, "call the office"))
        assertEquals("Hello there world", insertSpokenText("Helloworld", 5, "there"))
        assertEquals("start ", insertSpokenText("", 0, "start "))
        assertEquals("End. done", insertSpokenText("End.", 99, "done"))
    }

    @Test fun previewSkipsFrontmatterAndHeadings() {
        assertEquals("Idea: the composer is the file", liveNotePreviewLine("---\ntags: [daily]\n---\n# Thursday\n\n- Idea: the composer is the file\n"))
        assertEquals("Move bookshelf", liveNotePreviewLine("# Radiator\n- [ ] Move bookshelf"))
        assertNull(liveNotePreviewLine("# Only a heading\n"))
    }

    @Test fun timelineMergesCapturesRecordingsAndReloadsNewestFirst() {
        val items = listOf(
            CaptureHistoryItem("11111111-1111-4111-8111-111111111111", 1_000, 5_000, CaptureState.NEEDS_PERMISSION, 1, title = "Packing list", logicalPath = "Inbox/Packing list.md"),
            CaptureHistoryItem("22222222-2222-4222-8222-222222222222", 1_000, 3_000, CaptureState.COMPLETED, 1, title = "Standup moved", logicalPath = "Daily/2026-11-13.md", presetID = "d"),
            CaptureHistoryItem("33333333-3333-4333-8333-333333333333", 1_000, 2_500, CaptureState.RETRYABLE_FAILURE, 2, title = "Groceries"),
        )
        val transcripts = listOf(
            RecordingTranscriptionState("44444444-4444-4444-8444-444444444444", RecordingTranscriptionPhase.COMPLETED, durationMillis = 47_000, completedAtEpochMillis = 4_000),
            RecordingTranscriptionState("55555555-5555-4555-8555-555555555555", RecordingTranscriptionPhase.DISCARDED, completedAtEpochMillis = 4_500),
        )
        val events = listOf(LiveNoteEvent(2_000, LiveNoteEventKind.RELOADED, "Book ideas", "Inbox/Book ideas.md"))
        val timeline = activityTimeline(items, transcripts, events, routeName = { if (it.presetID == "d") "Daily log" else null })
        assertEquals(listOf(TimelineTone.NEEDS_YOU, TimelineTone.AUDIO, TimelineTone.SAVED, TimelineTone.NEEDS_YOU, TimelineTone.ELSEWHERE), timeline.map(TimelineEntry::tone))
        assertTrue(timeline[0].action is TimelineAction.Reconnect)
        assertEquals(TimelineAction.Play("44444444-4444-4444-8444-444444444444", 47_000), timeline[1].action)
        assertEquals(TimelineTitle.Saved("Standup moved", "Daily log"), timeline[2].title)
        assertEquals(TimelineTarget.File("Daily/2026-11-13.md"), timeline[2].target)
        assertTrue(timeline[3].action is TimelineAction.Retry)
        assertEquals(TimelineTarget.File("Inbox/Book ideas.md"), timeline[4].target)
    }

    @Test fun vaultRootLineReadsTheTreeDocumentID() {
        assertEquals("Internal storage / Documents / Vox Notes", vaultRootLine("content://com.android.externalstorage.documents/tree/primary%3ADocuments%2FVox%20Notes"))
    }
}
