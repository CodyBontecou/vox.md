package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.EditNote
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Inbox
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.MicNone
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureState
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalSectionLabel
import md.vox.android.ui.SignalType
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant
import java.util.Calendar

/** The four top-level destinations shown in the navigation bar and rail. */
internal enum class VoxTopLevelDestination(val route: String) {
    CAPTURE(Destination.Capture.route),
    HISTORY(Destination.History.route),
    ACTIVITY(ACTIVITY_ROUTE),
    SETTINGS(Destination.Settings.route),
    ;

    companion object {
        fun forRoute(route: String?): VoxTopLevelDestination? = entries.firstOrNull { it.route == route }
    }
}

internal const val ACTIVITY_ROUTE = "activity"

private val VoxTopLevelDestination.icon: ImageVector
    get() = when (this) {
        VoxTopLevelDestination.CAPTURE -> Icons.Outlined.EditNote
        VoxTopLevelDestination.HISTORY -> Icons.Outlined.History
        VoxTopLevelDestination.ACTIVITY -> Icons.Outlined.Inbox
        VoxTopLevelDestination.SETTINGS -> Icons.Outlined.Tune
    }

@Composable
private fun VoxTopLevelDestination.label(): String = when (this) {
    VoxTopLevelDestination.CAPTURE -> voxString("Capture")
    VoxTopLevelDestination.HISTORY -> voxString("History")
    VoxTopLevelDestination.ACTIVITY -> voxString("Activity")
    VoxTopLevelDestination.SETTINGS -> voxString("Settings")
}

/** States that sit in Activity until someone acts on them. */
internal fun CaptureState.needsAttention(): Boolean = this in setOf(
    CaptureState.RETRYABLE_FAILURE,
    CaptureState.NEEDS_PERMISSION,
    CaptureState.NEEDS_USER_ACTION,
    CaptureState.UNKNOWN_OUTCOME,
    CaptureState.PERMANENT_FAILURE,
)

internal fun CaptureState.isInFlight(): Boolean = this in setOf(
    CaptureState.QUEUED,
    CaptureState.PREPARING,
    CaptureState.MATERIALIZED,
    CaptureState.COMMITTING,
)

internal fun RecordingTranscriptionPhase.isTranscriptInFlight(): Boolean = this in setOf(
    RecordingTranscriptionPhase.QUEUED,
    RecordingTranscriptionPhase.PROCESSING,
    RecordingTranscriptionPhase.FINALIZING,
)

/** Badge count on the Activity destination: captures and transcripts that need the person. */
internal fun activityAttentionCount(
    items: List<CaptureHistoryItem>,
    transcripts: Collection<RecordingTranscriptionState>,
): Int = items.count { it.state.needsAttention() } +
    transcripts.count { it.phase == RecordingTranscriptionPhase.FAILED }

/**
 * Material 3 navigation bar for compact windows: 80dp `surfaceContainer`, a 64x32
 * `secondaryContainer` indicator behind the selected icon and an error badge on Activity.
 */
@Composable
internal fun VoxNavigationBar(
    current: VoxTopLevelDestination?,
    activityBadge: Int,
    onSelect: (VoxTopLevelDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(c.container)
            .navigationBarsPadding()
            .height(80.dp)
            .selectableGroup()
            .testTag("vox-navigation-bar"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        VoxTopLevelDestination.entries.forEach { destination ->
            VoxNavigationItem(
                destination = destination,
                selected = destination == current,
                badge = if (destination == VoxTopLevelDestination.ACTIVITY) activityBadge else 0,
                onClick = { onSelect(destination) },
                indicatorWidth = 64.dp,
                modifier = Modifier.weight(1f).fillMaxHeight(),
            )
        }
    }
}

/**
 * Navigation rail for medium and expanded windows (tablets, unfolded foldables): an
 * 88dp column with the primary voice action as a FAB above the four destinations.
 */
@Composable
internal fun VoxNavigationRail(
    current: VoxTopLevelDestination?,
    activityBadge: Int,
    onSelect: (VoxTopLevelDestination) -> Unit,
    startVoiceCapture: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    val voiceLabel = voxString("Start voice capture")
    Column(
        modifier = modifier
            .width(88.dp)
            .fillMaxHeight()
            .background(c.bg)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(vertical = 24.dp)
            .selectableGroup()
            .testTag("vox-navigation-rail"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(SignalMetrics.ActionRadius))
                .background(c.accent)
                .clickable(role = Role.Button, onClick = startVoiceCapture)
                .semantics { contentDescription = voiceLabel },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Outlined.MicNone, contentDescription = null, tint = c.onAccent, modifier = Modifier.size(24.dp))
        }
        Spacer(Modifier.height(16.dp))
        VoxTopLevelDestination.entries.forEach { destination ->
            VoxNavigationItem(
                destination = destination,
                selected = destination == current,
                badge = if (destination == VoxTopLevelDestination.ACTIVITY) activityBadge else 0,
                onClick = { onSelect(destination) },
                indicatorWidth = 56.dp,
                modifier = Modifier.heightIn(min = 56.dp),
            )
        }
    }
}

@Composable
private fun VoxNavigationItem(
    destination: VoxTopLevelDestination,
    selected: Boolean,
    badge: Int,
    onClick: () -> Unit,
    indicatorWidth: androidx.compose.ui.unit.Dp,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    Column(
        modifier = modifier
            .selectable(selected = selected, role = Role.Tab, onClick = onClick)
            .testTag("nav-${destination.route}"),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp, Alignment.CenterVertically),
    ) {
        Box(contentAlignment = Alignment.Center) {
            Box(
                Modifier
                    .width(indicatorWidth)
                    .height(32.dp)
                    .clip(CircleShape)
                    .background(if (selected) c.secondarySoft else androidx.compose.ui.graphics.Color.Transparent),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    destination.icon,
                    contentDescription = null,
                    tint = if (selected) c.secondaryText else c.muted,
                    modifier = Modifier.size(24.dp),
                )
            }
            if (badge > 0) {
                val badgeText = badge.coerceAtMost(99).toString()
                Text(
                    badgeText,
                    style = MaterialTheme.typography.labelSmall.copy(fontSize = 11.sp, fontWeight = FontWeight.SemiBold),
                    color = c.onError,
                    maxLines = 1,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(start = 28.dp)
                        .heightIn(min = 16.dp)
                        .clip(CircleShape)
                        .background(c.error)
                        .padding(horizontal = 4.dp),
                )
            }
        }
        Text(
            destination.label(),
            style = MaterialTheme.typography.labelSmall.copy(
                fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
            ),
            color = if (selected) c.text else c.muted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * Activity: what is on the way to the vault right now. Captures that need the person
 * come first with their repair or retry action, then captures and private transcripts
 * still in flight, then what was delivered today. Activity shows status only; capture
 * text is not part of it.
 */
@Composable
internal fun ActivityScreen(
    items: List<CaptureHistoryItem>,
    transcripts: List<RecordingTranscriptionState>,
    isBusy: Boolean,
    refresh: () -> Unit,
    retry: (String) -> Unit,
    repairAccess: (String?) -> Unit,
    openDetail: (String) -> Unit,
    openTranscript: (String) -> Unit,
    openCapture: () -> Unit,
    nowEpochMillis: Long = System.currentTimeMillis(),
) {
    val c = Signal.colors
    val attention = items.filter { it.state.needsAttention() }.sortedByDescending(CaptureHistoryItem::updatedAtEpochMillis)
    val inFlight = items.filter { it.state.isInFlight() }.sortedByDescending(CaptureHistoryItem::updatedAtEpochMillis)
    val transcriptRows = transcripts
        .filter { it.phase.isTranscriptInFlight() || it.phase == RecordingTranscriptionPhase.FAILED }
    val startOfToday = Calendar.getInstance().apply {
        timeInMillis = nowEpochMillis
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis
    val deliveredToday = items
        .filter { it.state == CaptureState.COMPLETED && it.updatedAtEpochMillis >= startOfToday }
        .sortedByDescending(CaptureHistoryItem::updatedAtEpochMillis)
    val isEmpty = attention.isEmpty() && inFlight.isEmpty() && transcriptRows.isEmpty() && deliveredToday.isEmpty()
    Column(Modifier.fillMaxSize().background(c.bg)) {
        VoxTopBar(
            title = voxUiText("Activity"),
            navigateBack = null,
            actions = {
                SignalCircleButton(
                    icon = Icons.Outlined.Refresh,
                    contentDescription = voxString("Refresh"),
                    onClick = refresh,
                    enabled = !isBusy,
                )
            },
        )
        if (isEmpty) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                SignalEmptyState(
                    icon = Icons.Outlined.CheckCircle,
                    title = voxString("No activity yet"),
                    message = voxString("Record or send a Capture to create your first history item."),
                    iconTint = c.successText,
                    action = {
                        SignalButton(
                            voxString("Capture"),
                            onClick = openCapture,
                            size = SignalButtonSize.MEDIUM,
                            fillWidth = false,
                        )
                    },
                )
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().weight(1f).testTag("activity-list"),
                contentPadding = PaddingValues(start = SignalMetrics.PageGutter, end = SignalMetrics.PageGutter, top = 4.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (attention.isNotEmpty() || transcriptRows.any { it.phase == RecordingTranscriptionPhase.FAILED }) {
                    item(key = "attention-label") { SignalSectionLabel(voxString("Needs attention"), Modifier.padding(start = 4.dp, top = 4.dp)) }
                }
                items(attention, key = { "attention:${it.requestID}" }) { item ->
                    HistoryCard(
                        item = item,
                        isBusy = isBusy,
                        retry = { retry(item.requestID) },
                        repairAccess = { repairAccess(item.requestID) },
                        openDetail = { openDetail(item.requestID) },
                    )
                }
                items(transcriptRows.filter { it.phase == RecordingTranscriptionPhase.FAILED }, key = { "failed:${it.sessionID}" }) { transcript ->
                    TranscriptHistoryCard(transcript = transcript, openDetail = { openTranscript(transcript.sessionID) })
                }
                val processing = transcriptRows.filter { it.phase.isTranscriptInFlight() }
                if (inFlight.isNotEmpty() || processing.isNotEmpty()) {
                    item(key = "processing-label") { SignalSectionLabel(voxString("Processing"), Modifier.padding(start = 4.dp, top = 12.dp)) }
                }
                items(inFlight, key = { "flight:${it.requestID}" }) { item ->
                    HistoryCard(
                        item = item,
                        isBusy = isBusy,
                        retry = { retry(item.requestID) },
                        repairAccess = { repairAccess(item.requestID) },
                        openDetail = { openDetail(item.requestID) },
                    )
                }
                items(processing, key = { "transcript:${it.sessionID}" }) { transcript ->
                    TranscriptHistoryCard(transcript = transcript, openDetail = { openTranscript(transcript.sessionID) })
                }
                if (deliveredToday.isNotEmpty()) {
                    item(key = "delivered-label") { SignalSectionLabel(voxString("Delivered"), Modifier.padding(start = 4.dp, top = 12.dp)) }
                    item(key = "delivered") { DeliveredTodayGroup(deliveredToday, openDetail) }
                }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Outlined.Lock, contentDescription = null, tint = c.muted, modifier = Modifier.size(14.dp))
            Text(voxString("Everything stays on this device."), style = MaterialTheme.typography.bodySmall, color = c.muted)
        }
    }
}

/** Segmented rows (16dp outer, 4dp inner corners) of today's deliveries. */
@Composable
private fun DeliveredTodayGroup(items: List<CaptureHistoryItem>, openDetail: (String) -> Unit) {
    val c = Signal.colors
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        items.forEachIndexed { index, item ->
            val shape = segmentedShape(index, items.size)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 64.dp)
                    .clip(shape)
                    .background(c.card)
                    .clickable { openDetail(item.requestID) }
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = c.success, modifier = Modifier.size(20.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        item.title?.takeIf(String::isNotBlank) ?: historyTitleUiText(item.state).localized(),
                        style = SignalType.rowTitle.copy(fontSize = 15.sp),
                        color = c.text,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    item.logicalPath?.let {
                        Text(it, style = SignalType.monoCaption, color = c.muted, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
                Text(
                    java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(item.updatedAtEpochMillis)),
                    style = SignalType.monoCaption,
                    color = c.muted,
                )
            }
        }
    }
}

/** 16dp outer and 4dp inner corners for row [index] of a [count]-row segmented list. */
internal fun segmentedShape(index: Int, count: Int): RoundedCornerShape {
    val outer = SignalMetrics.GroupRadius
    val inner = SignalMetrics.SegmentRadius
    return when {
        count <= 1 -> RoundedCornerShape(outer)
        index == 0 -> RoundedCornerShape(topStart = outer, topEnd = outer, bottomStart = inner, bottomEnd = inner)
        index == count - 1 -> RoundedCornerShape(topStart = inner, topEnd = inner, bottomStart = outer, bottomEnd = outer)
        else -> RoundedCornerShape(inner)
    }
}
