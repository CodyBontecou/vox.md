package md.vox.android

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.MicOff
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LifecycleResumeEffect
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureState
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.Signal
import md.vox.android.ui.SignalButton
import md.vox.android.ui.SignalButtonSize
import md.vox.android.ui.SignalMetrics
import md.vox.android.ui.SignalType

// Capture states board (iOS Voxboard/Capture/CaptureStateViews.swift):
// A · vault unreachable banner, B · microphone-off card, C · route progress.

// region A · Vault unreachable

/** Captures still on their way to the vault (anything not finished or given up). */
internal fun captureWaitingCount(history: List<CaptureHistoryItem>): Int = history.count {
    it.state !in setOf(CaptureState.COMPLETED, CaptureState.DISCARDED, CaptureState.PERMANENT_FAILURE)
}

/**
 * The vault folder can no longer be written: the persisted SAF grant is gone, or
 * the durable queue already reports a capture blocked on folder permission.
 */
internal fun captureVaultIsUnreachable(history: List<CaptureHistoryItem>, hasVaultAccess: Boolean): Boolean =
    !hasVaultAccess || history.any { it.state == CaptureState.NEEDS_PERMISSION }

internal fun hasPersistedTreeAccess(context: Context, destination: CaptureDestination?): Boolean {
    val treeUri = destination?.treeUri ?: return true
    return context.contentResolver.persistedUriPermissions.any {
        it.uri.toString() == treeUri && it.isWritePermission
    }
}

/** Whether the destination's folder grant is still held; re-read on every resume. */
@Composable
internal fun rememberVaultAccess(destination: CaptureDestination?): Boolean {
    val context = LocalContext.current
    var hasAccess by remember(destination?.treeUri) { mutableStateOf(hasPersistedTreeAccess(context, destination)) }
    LifecycleResumeEffect(destination?.treeUri) {
        hasAccess = hasPersistedTreeAccess(context, destination)
        onPauseOrDispose {}
    }
    return hasAccess
}

@Composable
internal fun CaptureVaultUnreachableBanner(regrantAccess: () -> Unit, modifier: Modifier = Modifier) {
    val c = Signal.colors
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.card)
            .border(1.dp, c.warning.copy(alpha = 0.45f), shape)
            .padding(horizontal = 14.dp, vertical = 12.dp)
            .semantics(mergeDescendants = false) { liveRegion = LiveRegionMode.Polite }
            .testTag("capture-vault-unreachable"),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Box(
            Modifier
                .padding(top = 6.dp)
                .size(10.dp)
                .clip(CircleShape)
                .background(c.warning),
        )
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(
                voxString("Vault folder access expired"),
                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold),
                color = c.text,
            )
            Text(
                voxString("Keep capturing. Everything is held on this device and delivers as soon as access is back."),
                style = SignalType.caption,
                color = c.muted,
            )
            SignalButton(
                voxString("Re-grant access"),
                onClick = regrantAccess,
                size = SignalButtonSize.MEDIUM,
                modifier = Modifier.testTag("capture-vault-regrant"),
            )
        }
    }
}

/** Footer line replacing the Speak hint while captures wait for the vault. */
@Composable
internal fun captureWaitingLine(count: Int): String = if (count == 1) {
    voxString("1 capture waiting · nothing is lost")
} else {
    // iOS says "%lld captures waiting · nothing is lost"; that quantity has no Android
    // plural pattern yet, so compose the existing "%lld captures" plural instead.
    voxFormat("%@ · %@", voxFormat("%lld captures", count.toLong()), voxString("waiting · nothing is lost"))
}

// endregion

// region B · Microphone off

/**
 * Remembers that the microphone permission was permanently denied (the system no
 * longer shows its dialog), so Capture can offer "Open Settings" instead of a
 * request that silently fails. Cleared as soon as the permission is granted.
 */
internal object MicrophonePermissionMemory {
    private const val PREFERENCES = "vox.microphone.permission"
    private const val PERMANENTLY_DENIED = "permanentlyDenied"

    /** Bumped on every change so composables re-read the preference. */
    internal var revision by mutableIntStateOf(0)
        private set

    fun isGranted(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED

    fun isBlocked(context: Context): Boolean {
        if (isGranted(context)) return false
        return context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean(PERMANENTLY_DENIED, false)
    }

    /** Whether the system would explain the request again (only after one denial). */
    fun shouldShowRationale(activity: Activity?): Boolean =
        activity != null && ActivityCompat.shouldShowRequestPermissionRationale(activity, Manifest.permission.RECORD_AUDIO)

    /**
     * Records the outcome of a microphone request. A denial is permanent when the
     * system stops offering the rationale after a request that had it, or when an
     * already-blocked request is denied again without a dialog. A first dialog that
     * was merely dismissed keeps both rationale readings false and is not treated
     * as permanent.
     */
    fun recordResult(context: Context, granted: Boolean, rationaleBefore: Boolean, rationaleAfter: Boolean) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val blocked = microphoneDeniedPermanently(
            granted = granted,
            rationaleBefore = rationaleBefore,
            rationaleAfter = rationaleAfter,
            wasBlocked = preferences.getBoolean(PERMANENTLY_DENIED, false),
        )
        preferences.edit().apply {
            if (blocked) putBoolean(PERMANENTLY_DENIED, true) else remove(PERMANENTLY_DENIED)
        }.apply()
        revision++
    }

    fun clear(context: Context) {
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        if (!preferences.contains(PERMANENTLY_DENIED)) return
        preferences.edit().remove(PERMANENTLY_DENIED).apply()
        revision++
    }
}

internal fun microphoneDeniedPermanently(
    granted: Boolean,
    rationaleBefore: Boolean,
    rationaleAfter: Boolean,
    wasBlocked: Boolean,
): Boolean = !granted && !rationaleAfter && (rationaleBefore || wasBlocked)

/** True while the microphone is permanently denied; re-read on every resume. */
@Composable
internal fun rememberMicrophoneBlocked(): Boolean {
    val context = LocalContext.current
    val revision = MicrophonePermissionMemory.revision
    var blocked by remember(revision) { mutableStateOf(MicrophonePermissionMemory.isBlocked(context)) }
    LifecycleResumeEffect(revision) {
        if (MicrophonePermissionMemory.isGranted(context)) MicrophonePermissionMemory.clear(context)
        blocked = MicrophonePermissionMemory.isBlocked(context)
        onPauseOrDispose {}
    }
    return blocked
}

internal fun openAppDetailsSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null))
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    runCatching { context.startActivity(intent) }
}

@Composable
internal fun CaptureMicrophoneOffCard(openSettings: () -> Unit, modifier: Modifier = Modifier) {
    val c = Signal.colors
    val shape = RoundedCornerShape(18.dp)
    Column(
        modifier = modifier
            .fillMaxWidth()
            .clip(shape)
            .background(c.card)
            .border(1.dp, c.border, shape)
            .padding(16.dp)
            .testTag("capture-microphone-off"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Icon(Icons.Outlined.MicOff, contentDescription = null, tint = c.text, modifier = Modifier.size(20.dp))
            Text(
                voxString("Microphone is off for Vox.md"),
                style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.SemiBold, fontSize = 16.sp),
                color = c.text,
                modifier = Modifier.semantics { heading() },
            )
        }
        Text(
            voxString("Audio is transcribed on this device and saved beside your note. It never leaves your devices."),
            style = SignalType.caption,
            color = c.muted,
        )
        SignalButton(
            voxString("Open Settings"),
            onClick = openSettings,
            size = SignalButtonSize.MEDIUM,
            fillWidth = true,
            modifier = Modifier.heightIn(min = 48.dp).testTag("capture-microphone-open-settings"),
        )
    }
}

// endregion

// region C · Route progress

internal enum class CaptureRouteStepState { DONE, ACTIVE, PAUSED, SKIPPED }

internal data class CaptureRouteStep(val state: CaptureRouteStepState, val title: VoxUiText, val detail: VoxUiText? = null)

/**
 * The steps Android can report truthfully for one voice capture: the durable
 * recording, then local transcription (queued, running with its real percentage,
 * finished, failed or cancelled), then whether the transcript reached the draft.
 * Android has no separate on-device summary step, so none is invented here.
 */
internal fun captureRouteSteps(
    status: RecordingStatus,
    transcription: RecordingTranscriptionState?,
): List<CaptureRouteStep> {
    if (transcription == null) return emptyList()
    val durationMillis = transcription.durationMillis.takeIf { it > 0 } ?: status.elapsedMillis
    val steps = mutableListOf(
        CaptureRouteStep(
            CaptureRouteStepState.DONE,
            voxUiText("Captured · %@ audio", formatRecordingElapsed(durationMillis)),
        ),
    )
    steps += when (transcription.phase) {
        RecordingTranscriptionPhase.QUEUED -> CaptureRouteStep(
            CaptureRouteStepState.ACTIVE,
            voxUiText("Preparing transcript"),
            voxUiText("Waiting for the local model…"),
        )
        RecordingTranscriptionPhase.PROCESSING -> CaptureRouteStep(
            CaptureRouteStepState.ACTIVE,
            voxUiText("Transcribing voice capture, %@ complete", voxUiText("%lld%%", (transcription.progress * 100).toLong())),
            voxUiText("Processing audio on this device"),
        )
        RecordingTranscriptionPhase.FINALIZING -> CaptureRouteStep(
            CaptureRouteStepState.ACTIVE,
            voxUiText("Finalizing transcript"),
        )
        RecordingTranscriptionPhase.COMPLETED -> CaptureRouteStep(
            CaptureRouteStepState.DONE,
            transcription.modelName?.takeIf(String::isNotBlank)
                ?.let { voxUiText("Transcribed · %@, on device", it) }
                ?: voxUiText("Transcript ready"),
        )
        RecordingTranscriptionPhase.FAILED -> CaptureRouteStep(
            CaptureRouteStepState.PAUSED,
            voxUiText("Transcription needs attention"),
            voxUiText("The original recording is still safe on this device"),
        )
        RecordingTranscriptionPhase.DISCARDED -> CaptureRouteStep(
            CaptureRouteStepState.SKIPPED,
            voxUiText("Transcription cancelled"),
            voxUiText("The original recording remains available"),
        )
    }
    if (transcription.phase == RecordingTranscriptionPhase.COMPLETED) {
        steps += if (transcription.addedToDraft) {
            CaptureRouteStep(CaptureRouteStepState.DONE, voxUiText("Transcript added to Capture"))
        } else {
            CaptureRouteStep(
                CaptureRouteStepState.ACTIVE,
                voxUiText("Review the transcript or send it with the selected preset"),
            )
        }
    }
    return steps
}

/** "ROUTE PROGRESS" list from the Capture states board (C), inside the recording card. */
@Composable
internal fun CaptureRouteProgressSteps(steps: List<CaptureRouteStep>, modifier: Modifier = Modifier) {
    if (steps.isEmpty()) return
    val c = Signal.colors
    Column(
        modifier = modifier.fillMaxWidth().testTag("capture-route-progress"),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(
            voxString("ROUTE PROGRESS"),
            style = SignalType.monoCaption.copy(fontSize = 11.sp, letterSpacing = 0.6.sp),
            color = c.muted,
            modifier = Modifier.semantics { heading() },
        )
        steps.forEach { step ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top) {
                Box(Modifier.padding(top = 2.dp).size(18.dp), contentAlignment = Alignment.Center) {
                    when (step.state) {
                        CaptureRouteStepState.DONE -> Icon(
                            Icons.Outlined.CheckCircle,
                            contentDescription = null,
                            tint = c.success,
                            modifier = Modifier.size(18.dp),
                        )
                        CaptureRouteStepState.ACTIVE -> CircularProgressIndicator(
                            modifier = Modifier.size(15.dp),
                            strokeWidth = 2.dp,
                            color = c.tint,
                            trackColor = c.well,
                        )
                        CaptureRouteStepState.PAUSED -> {
                            val dash = c.warningText
                            Box(
                                Modifier.size(18.dp).drawBehind {
                                    drawCircle(
                                        color = dash,
                                        radius = size.minDimension / 2 - 1.dp.toPx(),
                                        center = Offset(size.width / 2, size.height / 2),
                                        style = Stroke(
                                            width = 2.dp.toPx(),
                                            pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 2.dp.toPx())),
                                        ),
                                    )
                                },
                            )
                        }
                        CaptureRouteStepState.SKIPPED -> Icon(
                            Icons.Outlined.RemoveCircleOutline,
                            contentDescription = null,
                            tint = c.muted,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(
                        step.title.localized(),
                        style = SignalType.caption.copy(fontSize = 15.sp),
                        color = if (step.state == CaptureRouteStepState.SKIPPED) c.muted else c.text,
                    )
                    step.detail?.let { detail ->
                        Text(detail.localized(), style = SignalType.caption.copy(fontSize = 13.sp), color = c.muted)
                    }
                }
            }
        }
    }
}

// endregion

/** Mono uppercase section label used by the Attach sheet and quick-actions panel. */
@Composable
internal fun CaptureMonoSectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = SignalType.monoCaption.copy(fontSize = 11.sp, letterSpacing = 0.6.sp),
        color = Signal.colors.muted,
        modifier = modifier.padding(horizontal = 4.dp).semantics { heading() },
    )
}

internal val CaptureTileShape = RoundedCornerShape(14.dp)
internal val CaptureReadTileShape = RoundedCornerShape(SignalMetrics.GroupRadius)

