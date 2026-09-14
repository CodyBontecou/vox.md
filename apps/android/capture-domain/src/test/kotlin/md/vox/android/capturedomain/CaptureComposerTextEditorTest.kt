package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Test

class CaptureComposerTextEditorTest {
    private val editor = CaptureComposerTextEditor()

    @Test fun boldWrapsAndTogglesSelection() {
        val wrapped = apply(CaptureComposerCommand.ToggleBold, "hello world", 6, 11)
        assertEquals("hello **world**", wrapped.text)
        assertEquals(CaptureTextSelection(8, 13), wrapped.selection)
        assertEquals(
            CaptureTextEditResult("hello world", CaptureTextSelection(6, 11)),
            editor.apply(CaptureComposerCommand.ToggleBold, wrapped.text, wrapped.selection),
        )
        assertEquals(
            CaptureTextEditResult("world", CaptureTextSelection(0, 5)),
            apply(CaptureComposerCommand.ToggleBold, "**world**", 0, 9),
        )
    }

    @Test fun italicWrapsAndTogglesSelectedText() {
        val wrapped = apply(CaptureComposerCommand.ToggleItalic, "hello", 0, 5)
        assertEquals(CaptureTextEditResult("*hello*", CaptureTextSelection(1, 6)), wrapped)
        assertEquals(
            CaptureTextEditResult("hello", CaptureTextSelection(0, 5)),
            editor.apply(CaptureComposerCommand.ToggleItalic, wrapped.text, wrapped.selection),
        )
    }

    @Test fun caretFormattingInsertsPairedMarkers() {
        assertEquals(
            CaptureTextEditResult("a****b", CaptureTextSelection(3, 3)),
            apply(CaptureComposerCommand.ToggleBold, "ab", 1, 1),
        )
        assertEquals(
            CaptureTextEditResult("a**b", CaptureTextSelection(2, 2)),
            apply(CaptureComposerCommand.ToggleItalic, "ab", 1, 1),
        )
    }

    @Test fun headingAndListsReplaceExistingPrefixesAcrossSelectedLines() {
        val heading = apply(CaptureComposerCommand.Heading(3), "one\ntwo\nthree", 1, 7)
        assertEquals("### one\n### two\nthree", heading.text)
        assertEquals(CaptureTextSelection(5, 15), heading.selection)
        assertEquals(
            CaptureTextEditResult("## one\ntwo", CaptureTextSelection(3, 7)),
            apply(CaptureComposerCommand.Heading(2), "one\ntwo", 0, 4),
        )
        val tasks = apply(CaptureComposerCommand.TaskCheckbox, "buy milk\n  + call Sam", 0, 21)
        assertEquals("- [ ] buy milk\n  - [ ] call Sam", tasks.text)
        val bullets = editor.apply(CaptureComposerCommand.Bullet, tasks.text, CaptureTextSelection(0, tasks.text.length))
        assertEquals("- buy milk\n  - call Sam", bullets.text)
    }

    @Test fun headingReplacesExistingHeadingAndInvalidLevelIsSafeNoOp() {
        assertEquals("## One\n## Two", apply(CaptureComposerCommand.Heading(2), "# One\n#### Two", 0, 14).text)
        assertEquals(
            CaptureTextEditResult("Title", CaptureTextSelection(2, 2)),
            apply(CaptureComposerCommand.Heading(7), "Title", 2, 2),
        )
    }

    @Test fun headingAndTaskReplaceValidEmptyMarkdownPrefixes() {
        assertEquals(
            CaptureTextEditResult("## ", CaptureTextSelection(3, 3)),
            apply(CaptureComposerCommand.Heading(2), "#", 0, 0),
        )
        assertEquals(
            CaptureTextEditResult("- [ ] ", CaptureTextSelection(6, 6)),
            apply(CaptureComposerCommand.TaskCheckbox, "- [ ]", 5, 5),
        )
    }

    @Test fun hashtagPrefixesSelectedTextOrInsertsAtCaret() {
        assertEquals(
            CaptureTextEditResult("#project", CaptureTextSelection(1, 8)),
            apply(CaptureComposerCommand.InsertHashtag, "project", 0, 7),
        )
        assertEquals(
            CaptureTextEditResult("idea#", CaptureTextSelection(5, 5)),
            apply(CaptureComposerCommand.InsertHashtag, "idea", 4, 4),
        )
    }

    @Test fun linksUseSelectionAndSelectEditablePlaceholder() {
        val markdown = apply(CaptureComposerCommand.MarkdownLink(), "Read Docs", 5, 9)
        assertEquals("Read [Docs](url)", markdown.text)
        assertEquals(CaptureTextSelection(12, 15), markdown.selection)
        val wiki = apply(CaptureComposerCommand.WikiLink(), "Daily Note", 0, 10)
        assertEquals("[[Daily Note]]", wiki.text)
        assertEquals(CaptureTextSelection(2, 12), wiki.selection)
    }

    @Test fun markdownLinkAtCaretSelectsLabelPlaceholderAndEscapesSelectedLabel() {
        assertEquals(
            CaptureTextEditResult("[link text](https://example.com)", CaptureTextSelection(1, 10)),
            apply(CaptureComposerCommand.MarkdownLink("https://example.com"), "", 0, 0),
        )
        assertEquals(
            CaptureTextEditResult("[A \\[label\\]](url)", CaptureTextSelection(14, 17)),
            apply(CaptureComposerCommand.MarkdownLink(), "A [label]", 0, 9),
        )
        assertEquals(
            CaptureTextEditResult("[[Note]]", CaptureTextSelection(2, 6)),
            apply(CaptureComposerCommand.WikiLink(), "", 0, 0),
        )
    }

    @Test fun replaceNormalizesNewlines() {
        assertEquals(
            CaptureTextEditResult("new\nline value", CaptureTextSelection(8, 8)),
            apply(CaptureComposerCommand.ReplaceSelection("new\r\nline"), "old value", 0, 3),
        )
    }

    @Test fun caseAndSlugCommandsMatchAppleExamples() {
        assertEquals("mixed case", transform(CaptureComposerCommand.Lowercase, "MIXED Case"))
        assertEquals("MIXED CASE", transform(CaptureComposerCommand.Uppercase, "Mixed case"))
        assertEquals("Hello world. Next line! Yes", transform(CaptureComposerCommand.SentenceCase, "hELLO world. nEXT line! yes"))
        assertEquals("Hello-World And O'brien", transform(CaptureComposerCommand.CapitalizeWords, "hELLO-world and O'BRIEN"))
        assertEquals("creme-brulee-notes", transform(CaptureComposerCommand.Slugify, "  Crème brûlée & Notes  "))
    }

    @Test fun caretOnlyCaseTransformDoesNothing() {
        assertEquals(
            CaptureTextEditResult("hello", CaptureTextSelection(2, 2)),
            apply(CaptureComposerCommand.Uppercase, "hello", 2, 2),
        )
    }

    @Test fun crlfSelectionIsTranslatedBeforeLineEdit() {
        val result = apply(CaptureComposerCommand.Heading(2), "one\r\ntwo\rthree", 5, 8)
        assertEquals("one\n## two\nthree", result.text)
        assertEquals(CaptureTextSelection(7, 10), result.selection)
    }

    @Test fun invalidSelectionsClampWithoutSplittingSurrogates() {
        assertEquals(
            CaptureTextEditResult("x", CaptureTextSelection(1, 1)),
            apply(CaptureComposerCommand.ReplaceSelection("x"), "hello", -20, 999),
        )
        val emoji = "A👩🏽‍💻B"
        val start = emoji.indexOf("👩")
        val end = emoji.lastIndexOf('B')
        val wrapped = apply(CaptureComposerCommand.ToggleBold, emoji, start + 1, end - 1)
        assertEquals("A**👩🏽‍💻**B", wrapped.text)
        assertEquals(CaptureTextSelection(3, 10), wrapped.selection)
        assertEquals(
            CaptureTextEditResult("AXB", CaptureTextSelection(2, 2)),
            apply(CaptureComposerCommand.ReplaceSelection("X"), emoji, start + 1, start + 2),
        )
        assertEquals(
            CaptureTextEditResult("hi#", CaptureTextSelection(3, 3)),
            apply(CaptureComposerCommand.InsertHashtag, "hi", 99, 139),
        )
    }

    @Test fun currentLocationMatchesTheIosCoordinateOnlyGoogleMapsInsertion() {
        assertEquals(
            "[A \\[quiet\\] \\\\\\\\ place](https://www.google.com/maps?q=21.306900,-157.858300)",
            CaptureInsertionFormatter.googleMapsLink(
                latitude = 21.3069,
                longitude = -157.8583,
                label = "A [quiet] \\\\ place",
            ),
        )
        assertEquals(
            "[First Second Third](https://www.google.com/maps?q=0.000000,0.000000)",
            CaptureInsertionFormatter.googleMapsLink(0.0, -0.0, "First\u0000Second\nThird"),
        )
    }

    @Test fun currentLocationRejectsNonFiniteAndOutOfRangeCoordinates() {
        listOf(
            Double.NaN to 0.0,
            0.0 to Double.POSITIVE_INFINITY,
            90.0001 to 0.0,
            0.0 to -180.0001,
        ).forEach { (latitude, longitude) ->
            org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
                CaptureInsertionFormatter.googleMapsLink(latitude, longitude)
            }
        }
    }

    private fun apply(command: CaptureComposerCommand, text: String, start: Int, end: Int) =
        editor.apply(command, text, CaptureTextSelection(start, end))

    private fun transform(command: CaptureComposerCommand, text: String): String =
        apply(command, text, 0, text.length).text
}
