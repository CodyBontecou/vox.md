package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.displayCutoutPadding
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Pause
import androidx.compose.material.icons.outlined.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInWindow
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.platformservices.LiveSpeechState
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalRouteTile
import md.vox.android.ui.SignalRouteTone
import md.vox.android.ui.GeistMonoFontFamily

private const val LIVE_WAVEFORM_BARS = 48

/**
 * Full-screen live recording (the "Live recording" board): preset, a large mono
 * timer, the on-device live transcript, a level waveform, the Recording Result choice
 * and Cancel / Stop / Pause. When a foldable is half-open with a horizontal hinge
 * (tabletop) the timer and waveform take the upper half and the transcript and
 * controls the lower half, meeting at the hinge.
 */
@Composable
internal fun LiveRecordingScreen(
    preset: CapturePreset?,
    status: RecordingStatus,
    liveSpeech: LiveSpeechState?,
    recordingResult: VoiceRecordingResult,
    setRecordingResult: (VoiceRecordingResult) -> Unit,
    pause: () -> Unit,
    resume: () -> Unit,
    stop: () -> Unit,
    cancel: () -> Unit,
    modifier: Modifier = Modifier,
    /** Live Notes: where this recording is written ("Writing to … as you talk" / "Saves to … when you stop"). */
    writeLine: (@Composable () -> Unit)? = null,
) {
    val c = Signal.colors
    val levels = remember { mutableStateListOf<Float>() }
    LaunchedEffect(status.elapsedMillis / 120, status.phase) {
        val next = if (status.phase == RecordingPhase.PAUSED) 0.04f else status.level.coerceIn(0.04f, 1f)
        levels.add(next)
        while (levels.size > LIVE_WAVEFORM_BARS) levels.removeAt(0)
    }
    val fold = rememberVoxFold()
    val density = LocalDensity.current
    var originY by remember { mutableStateOf(0) }
    var heightPx by remember { mutableStateOf(0) }
    val tabletopSplit = fold?.takeIf { it.isTabletop }?.let {
        splitAroundHorizontalFold(
            containerTopPx = originY,
            containerHeightPx = heightPx,
            foldTopPx = it.topPx,
            foldBottomPx = it.bottomPx,
            minPanePx = with(density) { 200.dp.roundToPx() },
        )
    }
    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(c.cardLowest)
            .onGloballyPositioned {
                originY = it.positionInWindow().y.toInt()
                heightPx = it.size.height
            }
            .testTag("live-recording"),
    ) {
        if (tabletopSplit != null) {
            val (topPx, gapPx) = tabletopSplit
            Column(Modifier.fillMaxSize()) {
                Column(
                    Modifier
                        .fillMaxWidth()
                        .height(with(density) { topPx.toDp() })
                        .statusBarsPadding()
                        .padding(horizontal = 32.dp, vertical = 20.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    LiveRecordingHeader(preset)
                    writeLine?.invoke()
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.Center) {
                        LiveRecordingTimer(status, large = true)
                    }
                    LiveWaveform(levels, height = 88.dp, paused = status.phase == RecordingPhase.PAUSED)
                }
                Spacer(Modifier.fillMaxWidth().height(with(density) { gapPx.toDp() }).background(c.border.copy(alpha = 0.4f)))
                Column(
                    Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .background(c.bg)
                        .navigationBarsPadding()
                        .padding(horizontal = 32.dp, vertical = 22.dp),
                    verticalArrangement = Arrangement.spacedBy(18.dp),
                ) {
                    LiveTranscript(liveSpeech, Modifier.weight(1f), fontSize = 20)
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        RecordingResultChoice(recordingResult, setRecordingResult, Modifier.widthIn(max = 320.dp).weight(1f, fill = false))
                        Spacer(Modifier.weight(1f))
                        LiveRecordingControls(status, pause, resume, stop, cancel, stopSize = 80.dp)
                    }
                }
            }
        } else if (maxWidth >= 600.dp && maxHeight < 480.dp) {
            // In a phone's short landscape window, reserve a full column for
            // actions instead of putting them below the timer and waveform.
            Row(
                Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()
                    .displayCutoutPadding().padding(horizontal = 20.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                Column(
                    Modifier.weight(0.4f).fillMaxHeight().verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    LiveRecordingHeader(preset)
                    writeLine?.invoke()
                    Column { LiveRecordingTimer(status, large = false) }
                    LiveWaveform(levels, height = 40.dp, paused = status.phase == RecordingPhase.PAUSED)
                    Text(voxString("Voice and text stay on-device."), style = MaterialTheme.typography.bodySmall, color = c.muted)
                }
                Column(
                    Modifier.weight(0.6f).fillMaxHeight(),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    LiveTranscript(liveSpeech, Modifier.weight(1f).fillMaxWidth(), fontSize = 20)
                    RecordingResultChoice(recordingResult, setRecordingResult, Modifier.fillMaxWidth())
                    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        LiveRecordingControls(status, pause, resume, stop, cancel, stopSize = 80.dp, spread = true)
                    }
                }
            }
        } else {
            Column(
                Modifier
                    .fillMaxSize()
                    .statusBarsPadding()
                    .navigationBarsPadding(),
            ) {
                Box(Modifier.padding(start = 12.dp, end = 16.dp).heightIn(min = 64.dp), contentAlignment = Alignment.CenterStart) {
                    LiveRecordingHeader(preset)
                }
                if (writeLine != null) Box(Modifier.padding(start = 24.dp, end = 24.dp, top = 4.dp)) { writeLine() }
                Column(Modifier.padding(start = 24.dp, end = 24.dp, top = 20.dp)) {
                    LiveRecordingTimer(status, large = false)
                }
                LiveTranscript(
                    liveSpeech,
                    Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .padding(start = 24.dp, end = 24.dp, top = 28.dp),
                    fontSize = 22,
                )
                LiveWaveform(levels, height = 72.dp, paused = status.phase == RecordingPhase.PAUSED, modifier = Modifier.padding(horizontal = 24.dp))
                Text(
                    voxString("Voice and text stay on-device."),
                    style = MaterialTheme.typography.bodySmall,
                    color = c.muted,
                    modifier = Modifier.padding(start = 24.dp, end = 24.dp, bottom = 12.dp),
                )
                Column(
                    Modifier.padding(start = 20.dp, end = 20.dp, top = 4.dp, bottom = 28.dp),
                    verticalArrangement = Arrangement.spacedBy(24.dp),
                ) {
                    RecordingResultChoice(recordingResult, setRecordingResult, Modifier.fillMaxWidth())
                    Box(Modifier.fillMaxWidth().padding(horizontal = 8.dp), contentAlignment = Alignment.Center) {
                        LiveRecordingControls(status, pause, resume, stop, cancel, stopSize = 96.dp, spread = true)
                    }
                }
            }
        }
    }
}

@Composable
private fun LiveRecordingHeader(preset: CapturePreset?) {
    val c = Signal.colors
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(
            modifier = Modifier
                .heightIn(min = 40.dp)
                .clip(CircleShape)
                .background(c.secondarySoft)
                .padding(start = 4.dp, end = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            SignalRouteTile(
                label = preset?.emoji ?: preset?.name ?: "Default",
                size = 32.dp,
                tone = SignalRouteTone.PRIMARY,
                circular = true,
            )
            Text(
                preset?.name ?: "Default",
                style = MaterialTheme.typography.labelMedium,
                color = c.secondaryText,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Spacer(Modifier.weight(1f))
        Icon(Icons.Outlined.Lock, contentDescription = null, tint = c.muted, modifier = Modifier.size(14.dp))
        Text(voxString("On-device"), style = MaterialTheme.typography.labelSmall, color = c.muted)
    }
}

@Composable
private fun LiveRecordingTimer(status: RecordingStatus, large: Boolean) {
    val c = Signal.colors
    val paused = status.phase == RecordingPhase.PAUSED
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(if (large) 14.dp else 12.dp)) {
        Box(
            Modifier
                .size(if (large) 14.dp else 12.dp)
                .clip(CircleShape)
                .background(if (paused) c.faint else c.recording),
        )
        Text(
            formatRecordingElapsed(status.elapsedMillis),
            style = TextStyle(
                fontFamily = GeistMonoFontFamily,
                fontWeight = FontWeight.Medium,
                fontSize = if (large) 64.sp else 48.sp,
                lineHeight = if (large) 72.sp else 56.sp,
                letterSpacing = (-0.02).em,
            ),
            color = c.text,
            modifier = Modifier.semantics { contentDescription = formatRecordingElapsed(status.elapsedMillis) },
        )
    }
    Text(
        recordingTitleUiText(status.phase).localized(),
        style = MaterialTheme.typography.bodyMedium,
        color = c.muted,
        modifier = Modifier
            .padding(top = 6.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
    )
}

@Composable
private fun LiveTranscript(liveSpeech: LiveSpeechState?, modifier: Modifier, fontSize: Int) {
    val c = Signal.colors
    val committed = liveSpeech?.committedText.orEmpty().trim()
    val partial = liveSpeech?.partialText.orEmpty().trim()
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState(), reverseScrolling = true)
            .semantics { liveRegion = LiveRegionMode.Polite },
        verticalArrangement = Arrangement.Bottom,
    ) {
        if (committed.isNotEmpty() || partial.isNotEmpty()) {
            Text(
                buildAnnotatedString {
                    append(committed)
                    if (partial.isNotEmpty()) {
                        if (committed.isNotEmpty()) append(' ')
                        withStyle(SpanStyle(color = c.faint)) { append(partial) }
                    }
                },
                style = TextStyle(fontSize = fontSize.sp, lineHeight = (fontSize + 8).sp, fontWeight = FontWeight.Medium),
                color = c.text,
            )
        }
    }
}

@Composable
private fun LiveWaveform(levels: List<Float>, height: Dp, paused: Boolean, modifier: Modifier = Modifier) {
    val c = Signal.colors
    Row(
        modifier = modifier.fillMaxWidth().height(height),
        horizontalArrangement = Arrangement.spacedBy(3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val padded = List((LIVE_WAVEFORM_BARS - levels.size).coerceAtLeast(0)) { 0.04f } + levels
        padded.forEachIndexed { index, level ->
            val recent = index >= LIVE_WAVEFORM_BARS - 7
            Box(
                Modifier
                    .weight(1f)
                    .height((8f + (height.value - 12f) * level).dp)
                    .clip(RoundedCornerShape(2.dp))
                    .background(if (recent && !paused) c.recording else c.border),
            )
        }
    }
}

/** "Recording Result": Add to Draft or Send Immediately, as a two-segment button. */
@Composable
private fun RecordingResultChoice(
    selected: VoiceRecordingResult,
    onSelect: (VoiceRecordingResult) -> Unit,
    modifier: Modifier = Modifier,
) {
    val c = Signal.colors
    val label = voxString("Recording Result")
    Row(
        modifier = modifier
            .height(40.dp)
            .clip(CircleShape)
            .border(1.dp, c.borderHi, CircleShape)
            .selectableGroup()
            .semantics { contentDescription = label },
    ) {
        listOf(
            VoiceRecordingResult.ADD_TO_DRAFT to voxString("Add to Draft"),
            VoiceRecordingResult.SEND_IMMEDIATELY to voxString("Send Immediately"),
        ).forEachIndexed { index, (option, text) ->
            val on = option == selected
            if (index > 0) Box(Modifier.width(1.dp).fillMaxHeight().background(c.borderHi))
            Row(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .background(if (on) c.secondarySoft else androidx.compose.ui.graphics.Color.Transparent)
                    .selectable(selected = on, role = Role.RadioButton) { onSelect(option) }
                    .padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (on) Icon(Icons.Outlined.Check, contentDescription = null, tint = c.secondaryText, modifier = Modifier.size(18.dp))
                Text(
                    text,
                    style = MaterialTheme.typography.labelMedium,
                    color = if (on) c.secondaryText else c.text,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
    }
}

@Composable
private fun LiveRecordingControls(
    status: RecordingStatus,
    pause: () -> Unit,
    resume: () -> Unit,
    stop: () -> Unit,
    cancel: () -> Unit,
    stopSize: Dp,
    spread: Boolean = false,
) {
    val c = Signal.colors
    val paused = status.phase == RecordingPhase.PAUSED
    val cancelLabel = voxString("Cancel voice recording")
    val stopLabel = voxString("Stop Recording")
    val pauseLabel = voxString(if (paused) "Resume recording" else "Pause recording")
    Row(
        modifier = if (spread) Modifier.fillMaxWidth() else Modifier,
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = if (spread) Arrangement.SpaceBetween else Arrangement.spacedBy(16.dp),
    ) {
        LiveSquareButton(cancelLabel, onClick = cancel, testTag = "live-recording-cancel") {
            Icon(Icons.Outlined.Close, contentDescription = null, tint = c.text, modifier = Modifier.size(24.dp))
        }
        Box(
            modifier = Modifier
                .size(stopSize)
                .clip(RoundedCornerShape(stopSize * 0.29f))
                .background(c.recording)
                .clickable(role = Role.Button, onClick = stop)
                .testTag("live-recording-stop")
                .semantics { contentDescription = stopLabel },
            contentAlignment = Alignment.Center,
        ) {
            Box(Modifier.size(stopSize / 3).clip(RoundedCornerShape(8.dp)).background(c.onRecording))
        }
        LiveSquareButton(pauseLabel, onClick = if (paused) resume else pause, testTag = "live-recording-pause", filled = paused) {
            Icon(
                if (paused) Icons.Outlined.PlayArrow else Icons.Outlined.Pause,
                contentDescription = null,
                tint = if (paused) c.onAccent else c.text,
                modifier = Modifier.size(24.dp),
            )
        }
    }
}

@Composable
private fun LiveSquareButton(
    description: String,
    onClick: () -> Unit,
    testTag: String,
    filled: Boolean = false,
    content: @Composable () -> Unit,
) {
    val c = Signal.colors
    Box(
        modifier = Modifier
            .size(56.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(if (filled) c.accent else c.well)
            .clickable(role = Role.Button, onClick = onClick)
            .testTag(testTag)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) { content() }
}
