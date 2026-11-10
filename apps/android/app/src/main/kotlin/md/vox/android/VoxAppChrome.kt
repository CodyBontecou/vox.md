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
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import md.vox.android.capturedomain.CaptureHistoryDetail
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.ui.SignalCard
import md.vox.android.ui.SignalDivider
import md.vox.android.ui.signalStatusColors
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
import md.vox.android.ui.SignalPillButton
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalSectionLabel
import md.vox.android.ui.SignalType
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalButtonVariant

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
    VoxTopLevelDestination.HISTORY -> voxString("Library")
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
 * Navigation rail for medium and expanded windows (tablets, unfolded foldables), the
 * Android counterpart of the iPad sidebar; phones navigate from the Capture header. An
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

/** Activity filter: everything, only what needs the person, or only what is on the way. */
internal enum class ActivityFilter { ALL, NEEDS_YOU, IN_FLIGHT }

/**
 * Activity: what is on the way to the vault right now. Captures that need the person
 * come first with their repair or retry action, then captures and private transcripts
 * still in flight, then what was delivered today. Activity keeps routes and status
 * only; capture text is not part of it.
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
    /** Route (capture preset) name for a capture, from its frozen preset ID. */
    captureRouteName: (CaptureHistoryItem) -> String? = { null },
    /** Loads a capture's local package so the delivery sheet can preview and copy it. */
    loadCaptureDetail: suspend (String) -> CaptureHistoryDetail? = { null },
    /** Opens the route editor for a capture's frozen preset ID. */
    editRoute: ((String) -> Unit)? = null,
    discard: ((String) -> Unit)? = null,
    recoveryPresets: List<md.vox.android.capturedomain.CapturePreset> = emptyList(),
    recoveryDestination: md.vox.android.capturedomain.CaptureDestination? = null,
    loadRecoveryContext: suspend (String) -> md.vox.android.capturedomain.CaptureRecoveryContext? = { null },
    replaceCapture: ((md.vox.android.capturedomain.CaptureRecoveryCommand) -> Unit)? = null,
    initialFilter: ActivityFilter = ActivityFilter.ALL,
    initialProblemRequestID: String? = null,
    /** Phones: back to Capture. Null when a navigation rail carries the destinations. */
    navigateBack: (() -> Unit)? = null,
    /** Phones: the Library pill in the header, as on iOS. */
    openLibrary: (() -> Unit)? = null,
) {
    val c = Signal.colors
    var filter by rememberSaveable { mutableStateOf(initialFilter) }
    var problemRequestID by rememberSaveable { mutableStateOf(initialProblemRequestID) }
    val attention = items.filter { it.state.needsAttention() }.sortedByDescending(CaptureHistoryItem::updatedAtEpochMillis)
    val inFlight = items.filter { it.state.isInFlight() }.sortedByDescending(CaptureHistoryItem::updatedAtEpochMillis)
    val failedTranscripts = transcripts.filter { it.phase == RecordingTranscriptionPhase.FAILED }
    val processing = transcripts.filter { it.phase.isTranscriptInFlight() }
    val startOfToday = libraryStartOfDay(nowEpochMillis)
    val deliveredToday = items
        .filter { it.state == CaptureState.COMPLETED && it.updatedAtEpochMillis >= startOfToday }
        .sortedByDescending(CaptureHistoryItem::updatedAtEpochMillis)
    val needsYouCount = attention.size + failedTranscripts.size
    val showsNeedsYou = filter != ActivityFilter.IN_FLIGHT
    val showsInFlight = filter != ActivityFilter.NEEDS_YOU
    val showsDelivered = filter == ActivityFilter.ALL
    val isEmpty = (!showsNeedsYou || needsYouCount == 0) &&
        (!showsInFlight || (inFlight.isEmpty() && processing.isEmpty())) &&
        (!showsDelivered || deliveredToday.isEmpty())
    Column(Modifier.fillMaxSize().background(c.bg)) {
        VoxTopBar(
            title = voxUiText("Activity"),
            navigateBack = navigateBack,
            actions = {
                if (openLibrary != null) {
                    SignalPillButton(
                        text = voxString("Library"),
                        onClick = openLibrary,
                        modifier = Modifier.testTag("activity-library"),
                    )
                }
                SignalCircleButton(
                    icon = Icons.Outlined.Refresh,
                    contentDescription = voxString("Refresh"),
                    onClick = refresh,
                    enabled = !isBusy,
                )
            },
        )
        LibrarySegmentedTabs(
            options = listOf(
                voxString("All") to ActivityFilter.ALL,
                (if (needsYouCount > 0) voxFormat("%@ · %@", voxString("Needs you"), needsYouCount.toString()) else voxString("Needs you")) to ActivityFilter.NEEDS_YOU,
                voxString("In flight") to ActivityFilter.IN_FLIGHT,
            ),
            selected = filter,
            onSelect = { filter = it },
            modifier = Modifier
                .padding(horizontal = SignalMetrics.PageGutter)
                .padding(bottom = 12.dp)
                .testTag("activity-filter"),
        )
        if (isEmpty) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                when (filter) {
                    ActivityFilter.ALL -> SignalEmptyState(
                        icon = Icons.Outlined.CheckCircle,
                        title = voxString("All caught up"),
                        message = voxString("Nothing waiting. Captures from the keyboard and Wear OS show up here while they’re on the way to your vault."),
                        iconTint = c.successText,
                        action = {
                            SignalButton(
                                voxString("New capture"),
                                onClick = openCapture,
                                size = SignalButtonSize.MEDIUM,
                                fillWidth = false,
                            )
                        },
                    )
                    ActivityFilter.NEEDS_YOU -> SignalEmptyState(
                        icon = Icons.Outlined.CheckCircle,
                        title = voxString("All caught up"),
                        message = voxString("Nothing needs you right now."),
                        iconTint = c.successText,
                    )
                    ActivityFilter.IN_FLIGHT -> SignalEmptyState(
                        icon = Icons.Outlined.CheckCircle,
                        title = voxString("All caught up"),
                        message = voxString("Nothing is in flight right now."),
                        iconTint = c.successText,
                    )
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxWidth().weight(1f).testTag("activity-list"),
                contentPadding = PaddingValues(start = SignalMetrics.PageGutter, end = SignalMetrics.PageGutter, top = 4.dp, bottom = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                if (showsNeedsYou) {
                    items(attention, key = { "attention:${it.requestID}" }) { item ->
                        ActivityProblemCard(
                            item = item,
                            routeName = captureRouteName(item),
                            isBusy = isBusy,
                            retry = { retry(item.requestID) },
                            repairAccess = { repairAccess(item.requestID) },
                            openProblem = { problemRequestID = item.requestID },
                        )
                    }
                    items(failedTranscripts, key = { "failed:${it.sessionID}" }) { transcript ->
                        TranscriptHistoryCard(transcript = transcript, openDetail = { openTranscript(transcript.sessionID) })
                    }
                }
                if (showsInFlight) {
                    items(inFlight, key = { "flight:${it.requestID}" }) { item ->
                        ActivityInFlightRow(
                            title = captureRouteName(item) ?: voxString("Capture"),
                            detail = historyTitleUiText(item.state).localized(),
                            timeEpochMillis = item.updatedAtEpochMillis,
                            progress = null,
                            onClick = { openDetail(item.requestID) },
                        )
                    }
                    items(processing, key = { "transcript:${it.sessionID}" }) { transcript ->
                        ActivityInFlightRow(
                            title = libraryTranscriptPhaseTitle(transcript),
                            detail = formatTranscriptDuration(transcript.durationMillis),
                            timeEpochMillis = transcript.recordedAtEpochMillis ?: transcript.completedAtEpochMillis,
                            progress = transcript.progress
                                .takeIf { transcript.phase == RecordingTranscriptionPhase.PROCESSING && it > 0f }
                                ?.coerceIn(0f, 1f),
                            onClick = { openTranscript(transcript.sessionID) },
                        )
                    }
                }
                if (showsDelivered && deliveredToday.isNotEmpty()) {
                    item(key = "delivered-label") {
                        SignalSectionLabel(voxString("Delivered today"), Modifier.padding(start = 4.dp, top = 12.dp), color = c.muted)
                    }
                    item(key = "delivered") { DeliveredTodayGroup(deliveredToday, captureRouteName, openDetail) }
                }
            }
        }
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.Top,
        ) {
            Icon(Icons.Outlined.Lock, contentDescription = null, tint = c.muted, modifier = Modifier.size(14.dp).padding(top = 2.dp))
            Text(
                voxString("Activity keeps routes and status only — never your words, links or locations."),
                style = MaterialTheme.typography.bodySmall,
                color = c.muted,
            )
        }
    }
    val problem = problemRequestID?.let { id -> attention.firstOrNull { it.requestID == id } }
    if (problem != null) {
        val presetID = problem.presetID
        DeliveryProblemSheet(
            item = problem,
            routeName = captureRouteName(problem),
            loadDetail = loadCaptureDetail,
            isBusy = isBusy,
            retry = { retry(problem.requestID) },
            repairAccess = { repairAccess(problem.requestID) },
            openDetail = { openDetail(problem.requestID) },
            editRoute = if (editRoute != null && presetID != null) ({ editRoute(presetID) }) else null,
            discard = discard?.let { action -> { action(problem.requestID) } },
            recoveryPresets = recoveryPresets, recoveryDestination = recoveryDestination,
            loadRecoveryContext = loadRecoveryContext, replaceCapture = replaceCapture,
            onDismiss = { problemRequestID = null },
        )
    }
}

/**
 * A capture that needs the person: a warning dot, what went wrong, and the action that
 * fixes it. Content-free: the route and time stand in for the capture's words.
 */
@Composable
internal fun ActivityProblemCard(
    item: CaptureHistoryItem,
    routeName: String?,
    isBusy: Boolean,
    retry: () -> Unit,
    repairAccess: () -> Unit,
    openProblem: () -> Unit,
) {
    val c = Signal.colors
    val isVaultProblem = item.state == CaptureState.NEEDS_PERMISSION
    val status = signalStatusColors(libraryCaptureStatus(item.state))
    SignalCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(14.dp),
        radius = 18.dp,
        borderColor = status.fill,
        onClick = openProblem,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.padding(top = 6.dp).size(10.dp).clip(CircleShape).background(status.dot))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    if (isVaultProblem) voxString("Can’t reach your vault") else historyTitleUiText(item.state).localized(),
                    style = SignalType.rowTitle,
                    color = c.text,
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                )
                val time = java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(item.updatedAtEpochMillis))
                Text(
                    listOfNotNull(
                        routeName,
                        time,
                        if (isVaultProblem) voxString("Keeps this capture waiting on this device until vault access is back.") else null,
                    ).joinToString(" · "),
                    style = MaterialTheme.typography.bodyMedium,
                    color = c.muted,
                )
            }
        }
        if (item.state != CaptureState.DISCARDED) {
            Spacer(Modifier.height(12.dp))
            Row(Modifier.padding(start = 22.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (isVaultProblem) {
                    SignalButton(
                        voxString("Fix access"),
                        onClick = repairAccess,
                        size = SignalButtonSize.MEDIUM,
                        enabled = !isBusy,
                        fillWidth = false,
                    )
                }
                SignalButton(
                    voxString("Retry"),
                    onClick = retry,
                    variant = SignalButtonVariant.SECONDARY,
                    size = SignalButtonSize.MEDIUM,
                    enabled = !isBusy,
                    fillWidth = false,
                )
            }
        }
    }
}

/** Something on the way to the vault: a primary dot, its route and step, and progress. */
@Composable
private fun ActivityInFlightRow(
    title: String,
    detail: String,
    timeEpochMillis: Long?,
    progress: Float?,
    onClick: () -> Unit,
) {
    val c = Signal.colors
    SignalCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(14.dp),
        radius = 18.dp,
        borderColor = c.border,
        onClick = onClick,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.Top) {
            Box(Modifier.padding(top = 6.dp).size(10.dp).clip(CircleShape).background(c.tint))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.Top) {
                    Text(
                        title,
                        style = SignalType.rowTitle,
                        color = c.text,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f),
                    )
                    timeEpochMillis?.let {
                        Text(
                            java.text.DateFormat.getTimeInstance(java.text.DateFormat.SHORT).format(java.util.Date(it)),
                            style = SignalType.monoCaption,
                            color = c.muted,
                            modifier = Modifier.padding(start = 8.dp, top = 2.dp),
                        )
                    }
                }
                Text(detail, style = MaterialTheme.typography.bodyMedium, color = c.muted)
                val barModifier = Modifier.fillMaxWidth().height(4.dp).clip(CircleShape)
                if (progress != null) {
                    LinearProgressIndicator(
                        progress = { progress },
                        modifier = barModifier,
                        color = c.tint,
                        trackColor = c.well,
                        drawStopIndicator = {},
                        gapSize = 0.dp,
                    )
                } else {
                    LinearProgressIndicator(modifier = barModifier, color = c.tint, trackColor = c.well, gapSize = 0.dp)
                }
            }
        }
    }
}

/** One card of divided rows for today's deliveries: route, where it went, and when. */
@Composable
private fun DeliveredTodayGroup(
    items: List<CaptureHistoryItem>,
    routeName: (CaptureHistoryItem) -> String?,
    openDetail: (String) -> Unit,
) {
    val c = Signal.colors
    SignalCard(
        modifier = Modifier.fillMaxWidth(),
        padding = PaddingValues(horizontal = 14.dp),
        radius = 18.dp,
        borderColor = c.border,
    ) {
        items.forEachIndexed { index, item ->
            if (index > 0) SignalDivider()
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 56.dp)
                    .clickable { openDetail(item.requestID) }
                    .padding(vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(Icons.Outlined.Check, contentDescription = null, tint = c.successText, modifier = Modifier.size(18.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        routeName(item) ?: historyTitleUiText(item.state).localized(),
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

/** Display name of the route (capture preset) with [presetID], if it still exists. */
internal fun libraryRouteName(collection: CapturePresetCollection?, presetID: String?): String? =
    presetID?.let { id -> collection?.presets?.firstOrNull { it.id == id }?.name?.takeIf(String::isNotBlank) }

/** True when a finished recording still has its local audio chunks. Reads storage. */
internal fun AudioCaptureClient.hasRetainedAudio(sessionID: String): Boolean =
    recordings().any { it.sessionID == sessionID && it.chunkCount > 0 && !it.isActive }

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
