package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckBox
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.MoreHoriz
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.platformservices.LiveSpeechPhase
import md.vox.android.platformservices.LiveSpeechState
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.ui.GeistFontFamily
import md.vox.android.ui.GeistMonoFontFamily
import md.vox.android.ui.Signal

private const val DOCK_WAVEFORM_BARS = 28
private val DockBackground = Color(0xFF0B0B0B)
private val DockInk = Color(0xFFF4F4F1)
private val DockMuted = Color(0xFF9A9A95)
private val DockRaised = Color(0xFF1C1C1C)

/**
 * Phone recording controls that take over the Capture footer while a recording runs
 * (port of iOS `CaptureLiveRecordingDock`). Quick actions and Attach / Speak / Send
 * transform into this dark dock, and the words stream straight into the editor above
 * at the writer's cursor, so there is no separate transcript surface. Presentation
 * only: the screen owns the recorder.
 */
@Composable
internal fun CaptureLiveRecordingDock(
    status: RecordingStatus,
    liveSpeech: LiveSpeechState?,
    recordingResult: VoiceRecordingResult,
    setRecordingResult: (VoiceRecordingResult) -> Unit,
    discard: () -> Unit,
    stop: () -> Unit,
    pause: () -> Unit,
    resume: () -> Unit,
    markMoment: () -> Unit,
    addTask: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    val paused = status.phase == RecordingPhase.PAUSED
    val duration = formatRecordingElapsed(status.elapsedMillis)
    var confirmsDiscard by rememberSaveable { mutableStateOf(false) }
    var showsActions by remember { mutableStateOf(false) }
    var actionFeedback by remember { mutableStateOf<String?>(null) }
    val view = LocalView.current
    // Keep the screen awake while a recording is visible.
    DisposableEffect(view) {
        view.keepScreenOn = true
        onDispose { view.keepScreenOn = false }
    }
    LaunchedEffect(actionFeedback) {
        val message = actionFeedback ?: return@LaunchedEffect
        view.announceForAccessibility(message)
        delay(1_600)
        if (actionFeedback == message) actionFeedback = null
    }
    val levels = remember { mutableStateListOf<Float>() }
    LaunchedEffect(status.elapsedMillis / 120, status.phase) {
        levels.add(if (paused) 0.04f else status.level.coerceIn(0.04f, 1f))
        while (levels.size > DOCK_WAVEFORM_BARS) levels.removeAt(0)
    }
    val momentMarked = voxFormat("Moment marked at %@", duration)
    val taskAdded = voxString("Task added to draft")
    Box(modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 12.dp, bottom = 8.dp)) {
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(28.dp))
                .background(DockBackground)
                .padding(start = 14.dp, end = 14.dp, top = 14.dp, bottom = 12.dp)
                .testTag("capture-live-recording-dock"),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            if (liveSpeech?.phase == LiveSpeechPhase.UNAVAILABLE || liveSpeech?.phase == LiveSpeechPhase.FAILED) {
                Text(
                    voxString("Live preview is unavailable. The recording remains safe for final on-device transcription."),
                    style = TextStyle(fontFamily = GeistFontFamily, fontSize = 13.sp, lineHeight = 18.sp),
                    color = DockMuted,
                )
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                val timerDescription = if (paused) voxFormat("Paused, %@", duration) else voxFormat("Recording, %@", duration)
                Row(
                    Modifier.padding(start = 4.dp).clearAndSetSemantics { contentDescription = timerDescription },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Box(Modifier.size(9.dp).clip(CircleShape).background(if (paused) DockMuted else c.recording))
                    Text(
                        duration,
                        style = TextStyle(fontFamily = GeistMonoFontFamily, fontWeight = FontWeight.Medium, fontSize = 20.sp),
                        color = DockInk,
                        maxLines = 1,
                    )
                }
                DockRecordingResultSegment(recordingResult, setRecordingResult, Modifier.weight(1f))
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                DockCircleButton(voxString("Discard recording"), onClick = { confirmsDiscard = true }, testTag = "capture-recording-discard") {
                    Icon(Icons.Outlined.Close, contentDescription = null, tint = DockInk, modifier = Modifier.size(20.dp))
                }
                DockWaveform(levels, paused, Modifier.weight(1f))
                Box {
                    DockCircleButton(voxString("More actions"), onClick = { showsActions = true }, testTag = "capture-recording-actions") {
                        Icon(Icons.Outlined.MoreHoriz, contentDescription = null, tint = DockInk, modifier = Modifier.size(20.dp))
                    }
                    DropdownMenu(expanded = showsActions, onDismissRequest = { showsActions = false }) {
                        DropdownMenuItem(
                            text = { Text(voxString("Mark moment")) },
                            leadingIcon = { Icon(Icons.Outlined.Timer, contentDescription = null) },
                            onClick = {
                                showsActions = false
                                markMoment()
                                actionFeedback = momentMarked
                            },
                            modifier = Modifier.testTag("capture-recording-mark-moment"),
                        )
                        DropdownMenuItem(
                            text = { Text(voxString("Add task")) },
                            leadingIcon = { Icon(Icons.Outlined.CheckBox, contentDescription = null) },
                            onClick = {
                                showsActions = false
                                addTask()
                                actionFeedback = taskAdded
                            },
                            modifier = Modifier.testTag("capture-recording-add-task"),
                        )
                    }
                }
                DockCircleButton(
                    voxString(if (paused) "Resume recording" else "Pause recording"),
                    onClick = if (paused) resume else pause,
                    testTag = "capture-recording-pause-toggle",
                    fill = if (paused) c.accent else DockRaised,
                ) {
                    Icon(
                        if (paused) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                        contentDescription = null,
                        tint = if (paused) c.onAccent else DockInk,
                        modifier = Modifier.size(20.dp),
                    )
                }
                val stopLabel = voxString(
                    if (recordingResult == VoiceRecordingResult.ADD_TO_DRAFT) "Stop and add to draft" else "Stop and send",
                )
                Box(
                    Modifier
                        .size(52.dp)
                        .clip(CircleShape)
                        .border(3.dp, DockInk, CircleShape)
                        .clickable(role = Role.Button, onClick = stop)
                        .testTag("capture-recording-stop")
                        .semantics { contentDescription = stopLabel },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.size(20.dp).clip(RoundedCornerShape(6.dp)).background(c.recording))
                }
            }
        }
        actionFeedback?.let { message ->
            Text(
                message,
                style = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.Medium, fontSize = 13.sp),
                color = DockBackground,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .offset(y = (-34).dp)
                    .clip(CircleShape)
                    .background(DockInk)
                    .padding(horizontal = 12.dp, vertical = 6.dp)
                    .clearAndSetSemantics {},
            )
        }
    }
    if (confirmsDiscard) {
        CaptureSignalDialog(
            onDismissRequest = { confirmsDiscard = false },
            title = voxString("Discard this recording?"),
            confirmButton = {
                TextButton(
                    onClick = {
                        confirmsDiscard = false
                        discard()
                    },
                    modifier = Modifier.testTag("capture-recording-discard-confirm"),
                ) { Text(voxString("Discard Recording"), color = c.error) }
            },
            dismissButton = {
                TextButton(onClick = { confirmsDiscard = false }) { Text(voxString("Keep Recording"), color = c.text) }
            },
        ) {
            Text(voxString("The audio and live transcript are deleted. Nothing is sent."), color = c.secondaryText)
        }
    }
}

/** "When I stop": Add to draft or Send on stop, the dock's two-segment capsule. */
@Composable
private fun DockRecordingResultSegment(
    selected: VoiceRecordingResult,
    onSelect: (VoiceRecordingResult) -> Unit,
    modifier: Modifier = Modifier,
) {
    val label = voxString("When I stop")
    Row(
        modifier = modifier
            .height(36.dp)
            .clip(CircleShape)
            .background(DockRaised)
            .padding(3.dp)
            .selectableGroup()
            .semantics { contentDescription = label },
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        listOf(
            VoiceRecordingResult.ADD_TO_DRAFT to voxString("Add to draft"),
            VoiceRecordingResult.SEND_IMMEDIATELY to voxString("Send on stop"),
        ).forEach { (option, text) ->
            val on = option == selected
            Box(
                Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .clip(CircleShape)
                    .background(if (on) DockInk else Color.Transparent)
                    .selectable(selected = on, role = Role.RadioButton) { onSelect(option) }
                    .padding(horizontal = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text,
                    style = TextStyle(fontFamily = GeistFontFamily, fontWeight = FontWeight.SemiBold, fontSize = 13.sp),
                    color = if (on) DockBackground else DockMuted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun DockWaveform(levels: List<Float>, paused: Boolean, modifier: Modifier = Modifier) {
    val c = Signal.colors
    val height = 32.dp
    Row(
        modifier = modifier.height(height).clearAndSetSemantics {},
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val padded = List((DOCK_WAVEFORM_BARS - levels.size).coerceAtLeast(0)) { 0.04f } + levels
        padded.forEachIndexed { index, level ->
            val recent = index >= DOCK_WAVEFORM_BARS - 5
            Box(
                Modifier
                    .weight(1f)
                    .height((4f + (height.value - 6f) * level).dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(if (recent && !paused) c.recording else DockMuted.copy(alpha = 0.45f)),
            )
        }
    }
}

@Composable
private fun DockCircleButton(
    description: String,
    onClick: () -> Unit,
    testTag: String,
    fill: Color = DockRaised,
    diameter: Dp = 44.dp,
    content: @Composable () -> Unit,
) {
    Box(
        modifier = Modifier
            .size(diameter)
            .clip(CircleShape)
            .background(fill)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag(testTag)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) { content() }
}
