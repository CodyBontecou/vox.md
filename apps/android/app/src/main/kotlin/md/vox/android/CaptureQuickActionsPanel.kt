package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalType

/**
 * Sections of the "•••" all-actions panel (CaptureRestActions / CaptureKeyboard
 * boards), mirroring iOS `CaptureQuickActionGroup`: MARKDOWN, INSERT, EDIT, ATTACH.
 */
internal enum class CaptureQuickActionGroup(val title: VoxUiText, val actions: List<CaptureBarAction>) {
    MARKDOWN(
        voxUiText("MARKDOWN"),
        listOf(
            CaptureBarAction.CHECKLIST,
            CaptureBarAction.BULLET_LIST,
            CaptureBarAction.MARKDOWN_LINK,
            CaptureBarAction.INTERNAL_LINK,
            CaptureBarAction.FORMAT_MARKDOWN,
        ),
    ),
    INSERT(
        voxUiText("INSERT"),
        listOf(
            CaptureBarAction.TIMESTAMP,
            CaptureBarAction.DATE,
            CaptureBarAction.DUE_DATE,
            CaptureBarAction.CURRENT_LOCATION,
        ),
    ),
    EDIT(voxUiText("EDIT"), listOf(CaptureBarAction.TEXT_CASE, CaptureBarAction.PASTE, CaptureBarAction.UNDO)),
    ATTACH(
        voxUiText("ATTACH"),
        listOf(
            CaptureBarAction.ADD_MEDIA,
            CaptureBarAction.ADD_FILES,
            CaptureBarAction.SCAN_DOCUMENT,
            CaptureBarAction.EXTRACT_TEXT,
            CaptureBarAction.SKETCH,
        ),
    ),
}

/** Short tile label from the design (iOS `CaptureToolbarAction.shortTitle`). */
internal val CaptureBarAction.shortTitle: VoxUiText
    get() = when (this) {
        CaptureBarAction.ADD_MEDIA -> voxUiText("Media")
        CaptureBarAction.ADD_FILES -> voxUiText("Files")
        CaptureBarAction.SCAN_DOCUMENT -> voxUiText("Scan")
        CaptureBarAction.EXTRACT_TEXT -> voxUiText("Extract text")
        CaptureBarAction.UNDO -> voxUiText("Undo")
        CaptureBarAction.FORMAT_MARKDOWN -> voxUiText("Format")
        CaptureBarAction.MARKDOWN_LINK -> voxUiText("Web link")
        CaptureBarAction.DUE_DATE -> voxUiText("Due date")
        CaptureBarAction.CHECKLIST -> voxUiText("Task")
        CaptureBarAction.BULLET_LIST -> voxUiText("Bullet")
        CaptureBarAction.PASTE -> voxUiText("Paste")
        CaptureBarAction.INTERNAL_LINK -> voxUiText("Link note")
        CaptureBarAction.SKETCH -> voxUiText("Sketch")
        CaptureBarAction.CURRENT_LOCATION -> voxUiText("Location")
        CaptureBarAction.TIMESTAMP -> voxUiText("Time")
        CaptureBarAction.DATE -> voxUiText("Date")
        CaptureBarAction.TEXT_CASE -> voxUiText("Text case")
    }

/** Actions whose chip opens a menu; the panel must stay open to anchor it. */
private val menuActions = setOf(CaptureBarAction.FORMAT_MARKDOWN, CaptureBarAction.TEXT_CASE)

/**
 * When provided, [CaptureBarChip] renders as a labelled panel tile instead of a
 * compact chip, and runs [afterAction] (closing the panel) after its action.
 */
internal data class CaptureBarTileStyle(val label: String, val afterAction: (() -> Unit)?)

internal val LocalCaptureBarTile = staticCompositionLocalOf<CaptureBarTileStyle?> { null }

/** Tile form of a Capture Bar action inside the all-actions panel. */
@Composable
internal fun CaptureBarTile(
    style: CaptureBarTileStyle,
    onClick: () -> Unit,
    enabled: Boolean,
    description: String,
    content: @Composable () -> Unit,
) {
    val c = Signal.colors
    val shape = RoundedCornerShape(12.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 52.dp)
            .clip(shape)
            .background(c.card)
            .border(1.dp, c.border, shape)
            .clickable(enabled = enabled, role = Role.Button) {
                onClick()
                style.afterAction?.invoke()
            }
            .semantics { contentDescription = description }
            .padding(horizontal = 4.dp, vertical = 6.dp)
            .alpha(if (enabled) 1f else 0.5f),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterVertically),
    ) {
        Box(Modifier.heightIn(min = 20.dp), contentAlignment = Alignment.Center) { content() }
        Text(
            style.label,
            style = SignalType.caption.copy(fontSize = 11.sp, lineHeight = 14.sp),
            color = c.muted,
            textAlign = TextAlign.Center,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** The "•••" toggle at the trailing end of the quick-actions row. */
@Composable
internal fun CaptureAllQuickActionsButton(expanded: Boolean, onClick: () -> Unit, enabled: Boolean = true) {
    val c = Signal.colors
    val label = voxString("All quick actions")
    val state = voxString(if (expanded) "Expanded" else "Collapsed")
    val shape = RoundedCornerShape(10.dp)
    Box(
        modifier = Modifier
            .size(width = 48.dp, height = 48.dp)
            .padding(vertical = 4.dp)
            .clip(shape)
            .background(if (expanded) c.inverse else c.bg)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = label
                stateDescription = state
            }
            .testTag("capture-quick-actions-more"),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            Icons.Outlined.MoreHoriz,
            contentDescription = null,
            tint = if (expanded) c.onInverse else c.text,
            modifier = Modifier.size(20.dp),
        )
    }
}

/** Grouped panel of every quick action, opened from "•••". */
@Composable
internal fun CaptureAllQuickActionsPanel(
    close: () -> Unit,
    modifier: Modifier = Modifier,
    item: @Composable (CaptureBarAction) -> Unit,
) {
    val c = Signal.colors
    val columns = if (LocalDensity.current.fontScale >= 1.5f) 2 else 4
    Column(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(max = 300.dp)
            .background(c.well)
            .verticalScroll(rememberScrollState())
            .padding(12.dp)
            .testTag("capture-all-quick-actions"),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        CaptureQuickActionGroup.entries.forEach { group ->
            CaptureMonoSectionLabel(group.title.localized(), Modifier.padding(top = 2.dp))
            group.actions.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { action ->
                        Box(Modifier.weight(1f).widthIn(min = 0.dp)) {
                            CompositionLocalProvider(
                                LocalCaptureBarTile provides CaptureBarTileStyle(
                                    label = action.shortTitle.localized(),
                                    afterAction = if (action in menuActions) null else close,
                                ),
                            ) {
                                item(action)
                            }
                        }
                    }
                    repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
                }
            }
        }
    }
}
