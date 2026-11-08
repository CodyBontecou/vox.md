package md.vox.android.capturedomain

import org.junit.Assert.*
import org.junit.Test

class CapturePresetPathsTest {
    @Test fun rejectsUnsafeAndOverdeepFoldersButAllowsEmptyAttachmentsFolder() {
        listOf("../escape", "a/./b", "a/../b", "a\\b", "a\u0000b", "x".repeat(256), List(32) { "a" }.joinToString("/")).forEach {
            assertNull(it, CapturePresetPaths.folder(it))
        }
        assertNull(CapturePresetPaths.folder(" / "))
        assertEquals("", CapturePresetPaths.folder(" / ", allowEmpty = true))
        assertEquals("日本語/עברית", CapturePresetPaths.folder(" / 日本語 // עברית / "))
    }

    @Test fun filenamesAreBoundedSingleMarkdownNames() {
        listOf("../note.md", "a/b.md", "a\\b.md", "a\u0000.md", "note.txt", "a".repeat(126) + ".md").forEach {
            assertNull(it, CapturePresetPaths.filename(it))
        }
        assertEquals("{date}-🧪.MD", CapturePresetPaths.filename(" {date}-🧪.MD "))
        assertNotNull(CapturePresetPaths.filename("a".repeat(125) + ".md"))
    }

    @Test fun existingNotesRejectTraversalAndAcceptNestedMarkdownPaths() {
        listOf("../note.md", "a/./note.md", "a\\note.md", "a\u0000.md", "note.txt", List(33) { "a.md" }.joinToString("/")).forEach {
            assertNull(it, CapturePresetPaths.existingNote(it))
        }
        assertEquals("Journal/🧪.md", CapturePresetPaths.existingNote(" /Journal//🧪.md/ "))
    }
}
