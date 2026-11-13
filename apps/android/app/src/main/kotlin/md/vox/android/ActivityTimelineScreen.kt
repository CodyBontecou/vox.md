package md.vox.android

import android.media.MediaPlayer
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureState
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.LiveNoteEvent
import md.vox.android.ui.LiveNoteEventKind
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalCircleButton
import md.vox.android.ui.SignalEmptyState
import md.vox.android.ui.SignalPillButton
import md.vox.android.ui.SignalType
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Dot colors on the rail: orange needs you, indigo audio, green saved, grey changed elsewhere. */
internal enum class TimelineTone { NEEDS_YOU, AUDIO, SAVED, ELSEWHERE, WAITING }

internal sealed interface TimelineAction {
    data class Reconnect(val requestID: String?) : TimelineAction
    data class Retry(val requestID: String) : TimelineAction
    data class Play(val sessionID: String, val durationMillis: Long) : TimelineAction
}

internal data class TimelineEntry(
    val key: String,
    val atEpochMillis: Long,
    val tone: TimelineTone,
    val title: TimelineTitle,
    val path: String?,
    val action: TimelineAction? = null,
    /** What tapping the row opens. */
    val target: TimelineTarget? = null,
)

/** Titles are built from parts so they localize at render time. */
internal sealed interface TimelineTitle {
    data object CouldNotReachVault : TimelineTitle
    data class CouldNotSave(val name: String?) : TimelineTitle
    data class Recorded(val name: String?) : TimelineTitle
    data class Transcribing(val name: String?) : TimelineTitle
    data class TranscriptFailed(val name: String?) : TimelineTitle
    data class Saved(val name: String?, val route: String?) : TimelineTitle
    data class Waiting(val name: String?) : TimelineTitle
    data class ChangedElsewhere(val name: String) : TimelineTitle
    data class SavedCopy(val name: String) : TimelineTitle
}

internal sealed interface TimelineTarget {
    data class Capture(val requestID: String) : TimelineTarget
    data class Transcript(val sessionID: String) : TimelineTarget
    data class File(val relativePath: String) : TimelineTarget
}

/**
 * One timeline from captures, recordings and live-note reloads, newest first. Absorbs the
 * old History and Activity lists: failed deliveries carry Retry or Reconnect, recordings an
 * inline player, and every row still opens its detail.
 */
internal fun activityTimeline(
    items: List<CaptureHistoryItem>,
    transcripts: List<RecordingTranscriptionState>,
    events: List<LiveNoteEvent>,
    routeName: (CaptureHistoryItem) -> String? = { null },
    hasAudio: (String) -> Boolean = { true },
): List<TimelineEntry> {
    val captures = items.map { item ->
        val name = item.title ?: item.logicalPath?.substringAfterLast('/')?.removeSuffix(".md")
        when {
            item.state == CaptureState.NEEDS_PERMISSION -> TimelineEntry(
                key = "c:${item.requestID}", atEpochMillis = item.updatedAtEpochMillis, tone = TimelineTone.NEEDS_YOU,
                title = TimelineTitle.CouldNotReachVault, path = item.logicalPath,
                action = TimelineAction.Reconnect(item.requestID), target = TimelineTarget.Capture(item.requestID),
            )
            item.state.needsAttention() -> TimelineEntry(
                key = "c:${item.requestID}", atEpochMillis = item.updatedAtEpochMillis, tone = TimelineTone.NEEDS_YOU,
                title = TimelineTitle.CouldNotSave(name), path = item.logicalPath,
                action = TimelineAction.Retry(item.requestID), target = TimelineTarget.Capture(item.requestID),
            )
            item.state.isInFlight() -> TimelineEntry(
                key = "c:${item.requestID}", atEpochMillis = item.updatedAtEpochMillis, tone = TimelineTone.WAITING,
                title = TimelineTitle.Waiting(name), path = item.logicalPath, target = TimelineTarget.Capture(item.requestID),
            )
            item.state == CaptureState.COMPLETED -> TimelineEntry(
                key = "c:${item.requestID}", atEpochMillis = item.updatedAtEpochMillis, tone = TimelineTone.SAVED,
                title = TimelineTitle.Saved(name, routeName(item)), path = item.logicalPath,
                target = item.logicalPath?.let { TimelineTarget.File(it) } ?: TimelineTarget.Capture(item.requestID).takeIf { item.title != null },
            )
            else -> null
        }
    }.filterNotNull()
    val recordings = transcripts.filter { it.phase != RecordingTranscriptionPhase.DISCARDED }.map { transcript ->
        val at = transcript.completedAtEpochMillis ?: transcript.recordedAtEpochMillis ?: 0L
        val name = transcript.title?.takeIf(String::isNotBlank)
        when (transcript.phase) {
            RecordingTranscriptionPhase.FAILED -> TimelineEntry(
                key = "t:${transcript.sessionID}", atEpochMillis = at, tone = TimelineTone.NEEDS_YOU,
                title = TimelineTitle.TranscriptFailed(name), path = null, target = TimelineTarget.Transcript(transcript.sessionID),
            )
            RecordingTranscriptionPhase.COMPLETED -> TimelineEntry(
                key = "t:${transcript.sessionID}", atEpochMillis = at, tone = TimelineTone.AUDIO,
                title = TimelineTitle.Recorded(name), path = null,
                action = TimelineAction.Play(transcript.sessionID, transcript.durationMillis).takeIf { hasAudio(transcript.sessionID) },
                target = TimelineTarget.Transcript(transcript.sessionID),
            )
            else -> TimelineEntry(
                key = "t:${transcript.sessionID}", atEpochMillis = at, tone = TimelineTone.AUDIO,
                title = TimelineTitle.Transcribing(name), path = null, target = TimelineTarget.Transcript(transcript.sessionID),
            )
        }
    }
    val reloads = events.mapIndexed { index, event ->
        TimelineEntry(
            key = "e:$index:${event.atEpochMillis}", atEpochMillis = event.atEpochMillis,
            tone = if (event.kind == LiveNoteEventKind.RELOADED) TimelineTone.ELSEWHERE else TimelineTone.SAVED,
            title = if (event.kind == LiveNoteEventKind.RELOADED) TimelineTitle.ChangedElsewhere(event.title) else TimelineTitle.SavedCopy(event.title),
            path = event.relativePath, target = TimelineTarget.File(event.relativePath),
        )
    }
    return (captures + recordings + reloads).sortedByDescending(TimelineEntry::atEpochMillis)
}

@Composable
private fun TimelineTitle.text(): String = when (this) {
    TimelineTitle.CouldNotReachVault -> voxString("Couldn't reach your folder")
    is TimelineTitle.CouldNotSave -> name?.let { voxFormat("Couldn't save %@", it) } ?: voxString("A capture couldn't be saved")
    is TimelineTitle.Recorded -> name?.let { voxFormat("Recorded %@", it) } ?: voxString("Recording")
    is TimelineTitle.Transcribing -> name?.let { voxFormat("Transcribing %@", it) } ?: voxString("Transcribing a recording")
    is TimelineTitle.TranscriptFailed -> name?.let { voxFormat("Couldn't transcribe %@", it) } ?: voxString("A recording couldn't be transcribed")
    is TimelineTitle.Saved -> when {
        name != null && route != null -> voxFormat("%1\$@ added to %2\$@", name, route)
        name != null -> voxFormat("Saved %@", name)
        route != null -> voxFormat("Saved to %@", route)
        else -> voxString("Capture saved")
    }
    is TimelineTitle.Waiting -> name?.let { voxFormat("Saving %@", it) } ?: voxString("Saving a capture")
    is TimelineTitle.ChangedElsewhere -> voxFormat("%@ changed in another app", name)
    is TimelineTitle.SavedCopy -> voxFormat("Saved a copy: %@", name)
}

@Composable
private fun TimelineTone.color(): Color {
    val c = Signal.colors
    return when (this) {
        TimelineTone.NEEDS_YOU -> c.warning
        TimelineTone.AUDIO -> c.accent
        TimelineTone.SAVED -> c.success
        TimelineTone.ELSEWHERE, TimelineTone.WAITING -> c.faint
    }
}

/**
 * Activity tab: one vertical timeline grouped by day. Time on the left, a colored dot on a
 * rail, the title, the mono file path, and inline content where it helps: a Reconnect or
 * Retry card for items that need the person, a player row for recordings.
 */
@Composable
internal fun ActivityTimelineScreen(
    items: List<CaptureHistoryItem>,
    transcripts: List<RecordingTranscriptionState>,
    events: List<LiveNoteEvent>,
    vaultName: String?,
    isBusy: Boolean,
    retry: (String) -> Unit,
    reconnect: (String?) -> Unit,
    openCapture: (String) -> Unit,
    openTranscript: (String) -> Unit,
    openFile: (String) -> Unit,
    loadAudio: suspend (String) -> String?,
    openLibrary: () -> Unit,
    captureRouteName: (CaptureHistoryItem) -> String? = { null },
    hasAudio: (String) -> Boolean = { true },
    nowEpochMillis: Long = System.currentTimeMillis(),
) {
    val c = Signal.colors
    val timeline = remember(items, transcripts, events) { activityTimeline(items, transcripts, events, captureRouteName, hasAudio) }
    Column(Modifier.fillMaxSize().background(c.bg)) {
        Row(
            Modifier.fillMaxWidth().statusBarsPadding().padding(start = 16.dp, end = 8.dp, top = 16.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(voxString("Activity"), style = MaterialTheme.typography.headlineMedium.copy(fontSize = 30.sp, fontWeight = FontWeight.SemiBold), color = c.text, modifier = Modifier.weight(1f))
            SignalPillButton(text = voxString("All captures"), onClick = openLibrary, modifier = Modifier.testTag("activity-library"))
        }
        Row(Modifier.padding(start = 16.dp, top = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            LegendItem(TimelineTone.NEEDS_YOU, voxString("Needs you"))
            LegendItem(TimelineTone.AUDIO, voxString("Audio"))
            LegendItem(TimelineTone.SAVED, voxString("Saved"))
        }
        if (timeline.isEmpty()) {
            Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                SignalEmptyState(
                    icon = Icons.Outlined.CheckCircle,
                    title = voxString("Nothing yet"),
                    message = voxString("Saves, recordings and anything that needs you show up here."),
                    iconTint = c.successText,
                )
            }
            return@Column
        }
        val days = timeline.groupBy { libraryStartOfDay(it.atEpochMillis) }
        LazyColumn(
            modifier = Modifier.fillMaxWidth().weight(1f).testTag("activity-timeline"),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 24.dp),
        ) {
            days.forEach { (day, entries) ->
                item(key = "day:$day") {
                    Text(
                        libraryDayLabel(day, nowEpochMillis).uppercase(Locale.getDefault()),
                        style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold, letterSpacing = 0.8.sp),
                        color = c.muted,
                        modifier = Modifier.padding(start = 64.dp, top = 8.dp, bottom = 6.dp),
                    )
                }
                items(entries, key = TimelineEntry::key) { entry ->
                    TimelineRow(
                        entry = entry,
                        vaultName = vaultName,
                        isBusy = isBusy,
                        retry = retry,
                        reconnect = reconnect,
                        loadAudio = loadAudio,
                        open = {
                            when (val target = entry.target) {
                                is TimelineTarget.Capture -> openCapture(target.requestID)
                                is TimelineTarget.Transcript -> openTranscript(target.sessionID)
                                is TimelineTarget.File -> openFile(target.relativePath)
                                null -> Unit
                            }
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun LegendItem(tone: TimelineTone, label: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(tone.color()))
        Text(label, style = SignalType.caption.copy(fontSize = 11.5.sp), color = Signal.colors.muted)
    }
}

@Composable
private fun TimelineRow(
    entry: TimelineEntry,
    vaultName: String?,
    isBusy: Boolean,
    retry: (String) -> Unit,
    reconnect: (String?) -> Unit,
    loadAudio: suspend (String) -> String?,
    open: () -> Unit,
) {
    val c = Signal.colors
    Row(
        Modifier
            .fillMaxWidth()
            .height(androidx.compose.foundation.layout.IntrinsicSize.Min)
            .clickable(enabled = entry.target != null, role = Role.Button, onClick = open)
            .testTag("timeline-${entry.key}"),
    ) {
        Text(
            SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(entry.atEpochMillis)),
            style = SignalType.monoCaption.copy(fontSize = 12.sp),
            color = c.muted,
            textAlign = TextAlign.End,
            modifier = Modifier.width(44.dp).padding(top = 2.dp),
        )
        Spacer(Modifier.width(8.dp))
        Box(Modifier.width(20.dp).fillMaxHeight(), contentAlignment = Alignment.TopCenter) {
            Box(Modifier.width(2.dp).fillMaxHeight().background(c.border))
            Box(
                Modifier
                    .padding(top = 4.dp)
                    .size(16.dp)
                    .clip(CircleShape)
                    .background(c.bg)
                    .padding(2.dp)
                    .clip(CircleShape)
                    .background(entry.tone.color()),
            )
        }
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f).padding(bottom = 16.dp)) {
            Text(entry.title.text(), style = MaterialTheme.typography.titleSmall.copy(fontSize = 15.sp, fontWeight = FontWeight.SemiBold), color = c.text)
            entry.path?.let {
                Text(it, style = SignalType.monoCaption.copy(fontSize = 12.sp), color = c.muted, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 2.dp))
            }
            when (val action = entry.action) {
                is TimelineAction.Reconnect -> NeedsYouCard(
                    message = voxFormat("Folder access to %@ ended. Nothing is lost; it's kept on this phone.", vaultName ?: voxString("your vault")),
                    button = voxString("Reconnect folder"),
                    enabled = !isBusy,
                    onClick = { reconnect(action.requestID) },
                )
                is TimelineAction.Retry -> NeedsYouCard(
                    message = voxString("It's saved on this phone. Try writing it to the folder again."),
                    button = voxString("Retry"),
                    enabled = !isBusy,
                    onClick = { retry(action.requestID) },
                )
                is TimelineAction.Play -> TimelinePlayer(action.sessionID, action.durationMillis, loadAudio)
                null -> Unit
            }
        }
    }
}

@Composable
private fun NeedsYouCard(message: String, button: String, enabled: Boolean, onClick: () -> Unit) {
    val c = Signal.colors
    Column(
        Modifier
            .padding(top = 8.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(c.card)
            .border(1.dp, c.warning.copy(alpha = 0.35f), RoundedCornerShape(12.dp))
            .padding(horizontal = 12.dp, vertical = 10.dp),
    ) {
        Text(message, style = SignalType.caption, color = c.text)
        Box(
            Modifier
                .padding(top = 8.dp)
                .heightIn(min = 34.dp)
                .clip(RoundedCornerShape(10.dp))
                .background(c.text)
                .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
                .padding(horizontal = 12.dp)
                .testTag("timeline-action"),
            contentAlignment = Alignment.Center,
        ) {
            Text(button, style = MaterialTheme.typography.labelMedium.copy(fontSize = 12.5.sp, fontWeight = FontWeight.SemiBold), color = c.bg)
        }
    }
}

/** Compact inline player: play/pause, a static waveform and the duration. */
@Composable
private fun TimelinePlayer(sessionID: String, durationMillis: Long, loadAudio: suspend (String) -> String?) {
    val c = Signal.colors
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var player by remember(sessionID) { mutableStateOf<MediaPlayer?>(null) }
    var playing by remember(sessionID) { mutableStateOf(false) }
    var unavailable by remember(sessionID) { mutableStateOf(false) }
    DisposableEffect(sessionID) { onDispose { player?.release(); player = null } }
    val label = voxString(if (playing) "Pause recording" else "Play recording")
    Row(
        Modifier
            .padding(top = 8.dp)
            .fillMaxWidth()
            .clip(RoundedCornerShape(12.dp))
            .background(c.card)
            .border(1.dp, c.divider, RoundedCornerShape(12.dp))
            .padding(horizontal = 10.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier
                .size(28.dp)
                .clip(CircleShape)
                .background(c.accentSoft)
                .clickable(enabled = !unavailable, role = Role.Button) {
                    val current = player
                    when {
                        current != null && playing -> { current.pause(); playing = false }
                        current != null -> { current.start(); playing = true }
                        else -> scope.launch {
                            val prepared = withContext(Dispatchers.IO) {
                                val uri = runCatching { loadAudio(sessionID) }.getOrNull() ?: return@withContext null
                                runCatching { MediaPlayer().apply { setDataSource(context, Uri.parse(uri)); prepare() } }.getOrNull()
                            }
                            if (prepared == null) unavailable = true else {
                                prepared.setOnCompletionListener { playing = false; it.seekTo(0) }
                                prepared.start()
                                player = prepared
                                playing = true
                            }
                        }
                    }
                }
                .semantics { contentDescription = label },
            contentAlignment = Alignment.Center,
        ) {
            Icon(if (playing) Icons.Outlined.Pause else Icons.Outlined.PlayArrow, contentDescription = null, tint = c.accentText, modifier = Modifier.size(16.dp))
        }
        Row(Modifier.weight(1f).height(20.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            WAVE.forEach { height -> Box(Modifier.width(2.dp).height(height.dp).clip(RoundedCornerShape(1.dp)).background(c.tint.copy(alpha = 0.55f))) }
        }
        Text(
            if (unavailable) voxString("Unavailable") else formatTranscriptDuration(durationMillis),
            style = SignalType.monoCaption,
            color = c.muted,
        )
    }
}

private val WAVE = listOf(6, 12, 16, 9, 14, 18, 7, 12, 15, 6, 11, 17, 9, 13, 6, 12, 18, 8, 11, 6, 14, 9, 16, 7, 12, 5, 10, 15)
