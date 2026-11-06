package md.vox.android

import md.vox.android.capturedomain.CaptureNoteTargetKind
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class StarterRouteTest {
    @Test
    fun `setup offers four routes with Journal off by default`() {
        assertEquals(listOf("Inbox", "Meeting Notes", "Tasks", "Journal"), StarterRoute.entries.map { it.nameSource })
        assertEquals(setOf(StarterRoute.INBOX, StarterRoute.MEETING_NOTES, StarterRoute.TASKS), StarterRoute.defaultSelection)
        assertEquals(StarterRoute.entries.toSet(), StarterRoute.installOrder.toSet())
        assertEquals(StarterRoute.MEETING_NOTES, StarterRoute.installOrder.first())
    }

    @Test
    fun `starter presets match their path labels and stay creatable without an existing note`() {
        StarterRoute.entries.forEach { route ->
            val preset = route.preset(route.nameSource, route.promptSource)
            assertNotEquals(CaptureNoteTargetKind.EXISTING_NOTE, preset.noteTargetKind)
            assertTrue(preset.noteNameTemplate.endsWith(".md"))
            assertTrue(route.pathLabel.startsWith("${preset.logicalFolder}/${preset.noteNameTemplate}"))
            if ("›" in route.pathLabel) {
                assertTrue(route.pathLabel.endsWith("## ${preset.headingTitle}"))
            }
        }
        val first = StarterRoute.INBOX.preset("Inbox", "")
        val second = StarterRoute.INBOX.preset("Inbox", "")
        assertNotEquals(first.id, second.id)
    }
}
