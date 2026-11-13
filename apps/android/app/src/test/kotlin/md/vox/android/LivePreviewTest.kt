package md.vox.android

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LivePreviewTest {
    private val note = """
        ---
        title: "Radiator follow-up"
        tags: [home, 'repairs']
        aliases:
          - Radiator
          - "Heating"
        created: 2026-11-13
        ---
        # Radiator
        ![[Recording-1a2b.wav]]
        Some text with ![[inline.png]] in it
        ![photo](attachments/My%20Photo.jpg)
        ```
        ![[not-an-embed.png]]
        ```
        ![[clip.MOV|300]]
        ![[notes.pdf]]
        ![remote](https://example.com/a.png)
    """.trimIndent()

    @Test fun frontmatterBecomesPropertiesWithChipsAndUnquotedValues() {
        val block = requireNotNull(LivePreview.frontmatter(note))
        assertEquals(0, block.start)
        assertEquals(note.indexOf("---\n# Radiator") + 3, block.end)
        assertEquals(
            listOf(
                FrontmatterProperty("title", listOf("Radiator follow-up"), isList = false),
                FrontmatterProperty("tags", listOf("home", "repairs"), isList = true),
                FrontmatterProperty("aliases", listOf("Radiator", "Heating"), isList = true),
                FrontmatterProperty("created", listOf("2026-11-13"), isList = false),
            ),
            block.properties,
        )
    }

    @Test fun frontmatterMustOpenTheFileAndBeClosed() {
        assertNull(LivePreview.frontmatter("# Title\n---\na: b\n---\n"))
        assertNull(LivePreview.frontmatter("---\na: b\nno closing line"))
        assertEquals(emptyList<FrontmatterProperty>(), LivePreview.frontmatter("---\n---\nbody")!!.properties)
    }

    @Test fun embedsAreWholeLinesClassifiedByExtensionOutsideCodeFences() {
        val embeds = LivePreview.blocks(note).filterIsInstance<EmbedBlock>()
        assertEquals(listOf("Recording-1a2b.wav", "attachments/My Photo.jpg", "clip.MOV"), embeds.map { it.target })
        assertEquals(listOf(EmbedKind.AUDIO, EmbedKind.IMAGE, EmbedKind.VIDEO), embeds.map { it.kind })
        val wav = embeds.first()
        assertEquals("![[Recording-1a2b.wav]]", note.substring(wav.start, wav.end))
        assertEquals("My Photo.jpg", embeds[1].fileName)
    }

    @Test fun classificationCoversTheSupportedFormats() {
        for (name in listOf("a.wav", "a.m4a", "a.mp3", "a.aac", "a.ogg", "a.flac", "a.caf")) assertEquals(name, EmbedKind.AUDIO, LivePreview.kindOf(name))
        for (name in listOf("a.png", "a.JPG", "a.jpeg", "a.gif", "a.heic", "a.webp")) assertEquals(name, EmbedKind.IMAGE, LivePreview.kindOf(name))
        for (name in listOf("a.mp4", "a.mov", "a.m4v", "a.webm")) assertEquals(name, EmbedKind.VIDEO, LivePreview.kindOf(name))
        assertNull(LivePreview.kindOf("a.pdf"))
        assertNull(LivePreview.kindOf("wav"))
    }

    @Test fun aBlockShowsItsSourceWhileTheCaretOrSelectionTouchesIt() {
        val block = EmbedBlock(10, 20, "a.wav", EmbedKind.AUDIO)
        assertFalse(LivePreview.isRevealed(block, 5, 5))
        assertTrue(LivePreview.isRevealed(block, 10, 10))
        assertTrue(LivePreview.isRevealed(block, 20, 20))
        assertFalse(LivePreview.isRevealed(block, 21, 21))
        assertTrue(LivePreview.isRevealed(block, 2, 12))
        assertTrue(LivePreview.isRevealed(block, 25, 15))
    }

    @Test fun resolverTriesAttachmentsThenTheNotesFolderThenTheRoot() {
        assertEquals(
            listOf("attachments/a.wav", "Inbox/Daily/a.wav", "a.wav"),
            LivePreview.candidates("Inbox/Daily/Note.md", "a.wav"),
        )
        assertEquals(
            listOf("Attachments/a.wav", "attachments/a.wav", "a.wav"),
            LivePreview.candidates("Note.md", "a.wav", listOf("Attachments", "attachments")),
        )
        assertEquals(emptyList<String>(), LivePreview.candidates("Note.md", "../secret.wav"))
    }
}
