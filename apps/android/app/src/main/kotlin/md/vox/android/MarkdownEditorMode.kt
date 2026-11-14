package md.vox.android

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TransformedText
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import md.vox.android.ui.GeistMonoFontFamily
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalType

/**
 * Raw/formatted Markdown in the composer. Formatted styles the Markdown in place (the
 * characters, and so the file, never change); raw shows the source in mono. Shared by the
 * path-row toggle and the editor, and remembered across launches.
 */
internal object MarkdownEditorMode {
    private const val PREFERENCES = "vox_editor"
    private const val RAW_KEY = "shows_raw_markdown"
    private var loaded = false
    private var raw by mutableStateOf(false)

    @Composable
    fun showsRaw(): Boolean {
        val context = LocalContext.current
        if (!loaded) {
            raw = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean(RAW_KEY, false)
            loaded = true
        }
        return raw
    }

    fun set(context: Context, value: Boolean) {
        raw = value
        loaded = true
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().putBoolean(RAW_KEY, value).apply()
    }
}

/** "</>" switches to raw Markdown; "Aa" switches back to formatted. */
@Composable
internal fun MarkdownModeToggle(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val raw = MarkdownEditorMode.showsRaw()
    val c = Signal.colors
    val description = if (raw) voxString("Show formatted Markdown") else voxString("Show raw Markdown")
    val state = if (raw) voxString("Raw") else voxString("Formatted")
    // Mode glyphs, not words: the toggle is announced through its description.
    val glyph = if (raw) "Aa" else "</>"
    Text(
        glyph,
        style = SignalType.monoCaption,
        fontWeight = FontWeight.Medium,
        color = if (raw) c.accentText else c.muted,
        textAlign = TextAlign.Center,
        modifier = modifier
            .heightIn(min = 48.dp)
            .padding(vertical = 12.dp)
            .clip(CircleShape)
            .background(if (raw) c.accentSoft else c.well)
            .clickable(role = Role.Switch) { MarkdownEditorMode.set(context, !raw) }
            .widthIn(min = 36.dp)
            .padding(horizontal = 8.dp, vertical = 2.dp)
            .semantics {
                contentDescription = description
                stateDescription = state
            }
            .testTag("markdown-mode-toggle"),
    )
}

/** Styles Markdown spans in place (identity offsets), then hands off to [inner]. */
internal class MarkdownFormattedTransformation(
    private val colors: MarkdownEditorColors,
    private val inner: VisualTransformation = VisualTransformation.None,
    /** Live preview: blocks drawn as panels/players, whose source is hidden but keeps its space. */
    private val hidden: List<HiddenPreviewBlock> = emptyList(),
) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText =
        inner.filter(hidePreviewBlocks(styleMarkdown(text, colors), hidden))

    override fun equals(other: Any?): Boolean =
        other is MarkdownFormattedTransformation && other.colors == colors && other.inner == inner && other.hidden == hidden

    override fun hashCode(): Int = 31 * (31 * colors.hashCode() + inner.hashCode()) + hidden.hashCode()
}

/** Raw mode: no styling of its own, just the inner transformation (the "Just added" highlight). */
internal class MarkdownRawTransformation(private val inner: VisualTransformation = VisualTransformation.None) : VisualTransformation {
    override fun filter(text: AnnotatedString): TransformedText = inner.filter(text)
    override fun equals(other: Any?): Boolean = other is MarkdownRawTransformation && other.inner == inner
    override fun hashCode(): Int = inner.hashCode() + 7
}

internal data class MarkdownEditorColors(val muted: Color, val faint: Color, val accent: Color, val linkBackground: Color)

@Composable
internal fun markdownEditorColors(): MarkdownEditorColors {
    val c = Signal.colors
    return MarkdownEditorColors(muted = c.muted, faint = c.faint, accent = c.accentText, linkBackground = c.accentSoft)
}

private val headingSizes = listOf(26, 22, 19, 18, 18, 18)

/** Pure: the same characters with Markdown styles applied. Unit tested. */
internal fun styleMarkdown(text: AnnotatedString, colors: MarkdownEditorColors): AnnotatedString {
    val source = text.text
    if (source.isEmpty() || source.length > 60_000) return text
    return buildAnnotatedString {
        append(text)
        var offset = 0
        var inFence = false
        var inFrontmatter = false
        source.split('\n').forEachIndexed { index, line ->
            val start = offset
            val end = start + line.length
            offset = end + 1
            val trimmed = line.trimStart()
            if (index == 0 && line.trim() == "---") {
                inFrontmatter = true
                addStyle(SpanStyle(color = colors.faint, fontFamily = GeistMonoFontFamily), start, end)
                return@forEachIndexed
            }
            if (inFrontmatter) {
                addStyle(SpanStyle(color = colors.faint, fontFamily = GeistMonoFontFamily, fontSize = 14.sp), start, end)
                if (line.trim() == "---") inFrontmatter = false
                return@forEachIndexed
            }
            if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) {
                inFence = !inFence
                addStyle(SpanStyle(color = colors.faint, fontFamily = GeistMonoFontFamily), start, end)
                return@forEachIndexed
            }
            if (inFence) {
                addStyle(SpanStyle(fontFamily = GeistMonoFontFamily, fontSize = 15.sp), start, end)
                return@forEachIndexed
            }
            val heading = Regex("^(#{1,6}) ").find(line)
            if (heading != null) {
                val level = heading.groupValues[1].length
                addStyle(SpanStyle(fontWeight = FontWeight.SemiBold, fontSize = headingSizes[level - 1].sp), start, end)
                addStyle(SpanStyle(color = colors.faint, fontWeight = FontWeight.Medium), start, start + level)
            }
            Regex("^\\s*(- \\[[ xX]] |[-*] |\\d+\\. |> )").find(line)?.let { marker ->
                addStyle(SpanStyle(color = colors.muted), start + marker.range.first, start + marker.range.last + 1)
                if (marker.value.trim().equals("- [x]", ignoreCase = true)) {
                    addStyle(SpanStyle(color = colors.muted), start + marker.range.last + 1, end)
                }
                if (marker.value.trimStart().startsWith(">")) {
                    addStyle(SpanStyle(fontStyle = FontStyle.Italic, color = colors.muted), start, end)
                }
            }
            Regex("\\*\\*(.+?)\\*\\*").findAll(line).forEach {
                addStyle(SpanStyle(fontWeight = FontWeight.Bold), start + it.range.first, start + it.range.last + 1)
                addStyle(SpanStyle(color = colors.faint), start + it.range.first, start + it.range.first + 2)
                addStyle(SpanStyle(color = colors.faint), start + it.range.last - 1, start + it.range.last + 1)
            }
            Regex("(?<![*\\w])\\*([^*\\s][^*]*)\\*(?!\\*)|(?<!\\w)_([^_\\s][^_]*)_(?!\\w)").findAll(line).forEach {
                addStyle(SpanStyle(fontStyle = FontStyle.Italic), start + it.range.first, start + it.range.last + 1)
            }
            Regex("`([^`]+)`").findAll(line).forEach {
                addStyle(SpanStyle(fontFamily = GeistMonoFontFamily, fontSize = 15.sp), start + it.range.first, start + it.range.last + 1)
            }
            Regex("\\[\\[([^\\]]+)]]").findAll(line).forEach {
                addStyle(SpanStyle(color = colors.accent, background = colors.linkBackground), start + it.range.first, start + it.range.last + 1)
            }
            Regex("(?<!\\[)\\[([^\\]]+)]\\(([^)]+)\\)").findAll(line).forEach {
                addStyle(SpanStyle(color = colors.accent), start + it.range.first, start + it.range.last + 1)
            }
            Regex("(?<![\\w#])#[A-Za-z][\\w/-]*").findAll(line).forEach {
                if (heading == null || it.range.first > heading.range.last) {
                    addStyle(SpanStyle(color = colors.accent), start + it.range.first, start + it.range.last + 1)
                }
            }
        }
    }
}
