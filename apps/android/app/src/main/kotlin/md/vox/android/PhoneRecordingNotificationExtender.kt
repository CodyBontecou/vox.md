package md.vox.android

import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingNotificationExtender
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import java.util.Locale

/**
 * Phone styling for the ongoing recording notification (System surfaces board): the
 * Vox.md mic glyph tinted with the recording color, the frozen preset as the title,
 * its note path as the text, a running chronometer and a localized state line.
 * Named through the `md.vox.android.RECORDING_NOTIFICATION_EXTENDER` manifest entry.
 */
class PhoneRecordingNotificationExtender : RecordingNotificationExtender {
    override fun extend(
        context: Context,
        notificationID: Int,
        status: RecordingStatus,
        builder: NotificationCompat.Builder,
    ) {
        val locale = context.resources.configuration.locales[0] ?: Locale.ENGLISH
        fun localize(text: VoxUiText) = RuntimeLocalization.translate(context, locale, text.source)
        val paused = status.phase == RecordingPhase.PAUSED
        val preset = status.sessionID?.let { runCatching { AudioCaptureClient(context).frozenPreset(it) }.getOrNull() }
        builder
            .setSmallIcon(R.drawable.keyboard_ic_mic)
            .setColor(ContextCompat.getColor(context, R.color.signal_recording))
            .setSubText(localize(if (paused) voxUiText("Recording paused") else voxUiText("Recording")))
            .setContentTitle(preset?.name ?: localize(recordingTitleUiText(status.phase)))
            .setShowWhen(!paused)
            .setUsesChronometer(!paused)
            .setWhen(System.currentTimeMillis() - status.elapsedMillis.coerceAtLeast(0))
        preset?.let {
            builder.setContentText("→ ${it.logicalFolder}/${it.noteNameTemplate}")
        }
    }
}
