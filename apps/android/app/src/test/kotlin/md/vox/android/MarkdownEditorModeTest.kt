package md.vox.android

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.VisualTransformation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownEditorModeTest {
    private val colors = MarkdownEditorColors(Color.Gray, Color.LightGray, Color.Blue, Color.Cyan)

    private val note = "---\ntags: [daily]\n---\n# Thursday\n- [ ] Pick up **dry** cleaning\n- [x] Renew books\nSee [[Apartment]] #home"

    @Test
    fun formattedKeepsEveryCharacterAndOffset() {
        val transformed = MarkdownFormattedTransformation(colors).filter(AnnotatedString(note))
        assertEquals(note, transformed.text.text)
        for (offset in 0..note.length) {
            assertEquals(offset, transformed.offsetMapping.originalToTransformed(offset))
            assertEquals(offset, transformed.offsetMapping.transformedToOriginal(offset))
        }
    }

    @Test
    fun formattedStylesHeadingsMarkersLinksAndFrontmatter() {
        val styled = styleMarkdown(AnnotatedString(note), colors)
        val headingStart = note.indexOf("# Thursday")
        assertTrue(styled.spanStyles.any { it.start == headingStart && it.item.fontWeight == FontWeight.SemiBold })
        val bold = note.indexOf("**dry**")
        assertTrue(styled.spanStyles.any { it.start == bold && it.item.fontWeight == FontWeight.Bold })
        val link = note.indexOf("[[Apartment]]")
        assertTrue(styled.spanStyles.any { it.start == link && it.item.color == Color.Blue })
        assertTrue("frontmatter is muted", styled.spanStyles.any { it.start == note.indexOf("tags") && it.item.color == Color.LightGray })
    }

    @Test
    fun rawAddsNoMarkdownStyling() {
        val transformed = MarkdownRawTransformation(VisualTransformation.None).filter(AnnotatedString(note))
        assertEquals(note, transformed.text.text)
        assertTrue(transformed.text.spanStyles.isEmpty())
    }

    @Test
    fun formattedStillShowsTheJustAddedLabelFromTheInnerTransformation() {
        val entry = "- [x] Renew books"
        val start = note.indexOf(entry)
        val inner = LiveNoteHighlightTransformation(
            md.vox.android.capturedomain.LiveNoteRange(start, start + entry.length),
            Color.Yellow,
            label = "JUST ADDED",
        )
        val transformed = MarkdownFormattedTransformation(colors, inner).filter(AnnotatedString(note))
        assertTrue(transformed.text.text.contains("JUST ADDED\n$entry"))
        assertEquals(note.length + "JUST ADDED\n".length, transformed.text.text.length)
    }
}
