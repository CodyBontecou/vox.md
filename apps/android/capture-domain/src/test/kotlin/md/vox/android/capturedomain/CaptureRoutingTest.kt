package md.vox.android.capturedomain

import org.junit.Assert.*
import org.junit.Test

class CaptureRoutingTest {
    private val preset = CapturePreset("11111111-1111-4111-8111-111111111111", "Inbox", "mic", revision = 1,
        logicalFolder = "Inbox", noteNameTemplate = "capture-{id}.md", metadataFields = emptyList())

    @Test fun invocationOverridesDoNotMutatePresetOrVault() {
        val vault = CaptureDestination("22222222-2222-4222-8222-222222222222", "Work", "content://vault/work")
        val source = preset.copy(destination = vault)
        val routed = CaptureRouteOverride("Journal/Today.md", CapturePlacementKind.PREPEND).applyTo(source)
        assertEquals(CaptureNoteTargetKind.EXISTING_NOTE, routed.noteTargetKind)
        assertEquals("Journal/Today.md", routed.existingNotePath)
        assertEquals(CapturePlacementKind.PREPEND, routed.placement)
        assertEquals(vault, routed.destination)
        assertEquals(CaptureNoteTargetKind.NEW_NOTE, source.noteTargetKind)
        assertEquals(CapturePlacementKind.APPEND, source.placement)
    }

    @Test fun unsafePathsCannotEscapeVault() {
        for (path in listOf("../private.md", "/Inbox.md", "Notes//x.md", "Notes/./x.md", "Notes\\x.md", "note.txt", "a\u0000.md")) {
            assertTrue(path, runCatching { CaptureRouteOverride(path).validated() }.isFailure)
        }
        assertEquals("日記/今日.md", CaptureRouteOverride("日記/今日.md").validated().relativeNotePath)
    }

    @Test fun propertyKeysAcceptUnicodeButRejectYamlSyntax() {
        assertEquals("記録", normalizedTranscriptProperty(" 記録 "))
        for (key in listOf("", "note: injected", "a\nb", "[note]", "a.b")) assertNull(normalizedTranscriptProperty(key))
    }
}
