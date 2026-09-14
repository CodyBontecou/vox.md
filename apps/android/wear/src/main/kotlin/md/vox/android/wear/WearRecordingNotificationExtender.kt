package md.vox.android.wear

import android.app.Notification
import android.content.Context
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.wear.ongoing.OngoingActivity
import androidx.wear.ongoing.Status
import md.vox.android.platformservices.RecordingNotificationExtender
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus

/** Adds the Wear OS watch-face and Recents affordance to the shared recorder notification. */
class WearRecordingNotificationExtender : RecordingNotificationExtender {
    override fun extend(
        context: Context,
        notificationID: Int,
        status: RecordingStatus,
        builder: NotificationCompat.Builder,
    ) {
        val elapsedStart = SystemClock.elapsedRealtime() - status.elapsedMillis.coerceAtLeast(0)
        val ongoingStatus = Status.Builder()
            .addTemplate("#state# · #time#")
            .addPart(
                "state",
                Status.TextPart(
                    context.getString(
                        if (status.phase == RecordingPhase.PAUSED) R.string.wear_paused else R.string.wear_recording,
                    ),
                ),
            )
            .addPart(
                "time",
                if (status.phase == RecordingPhase.PAUSED) {
                    Status.StopwatchPart(elapsedStart, SystemClock.elapsedRealtime())
                } else {
                    Status.StopwatchPart(elapsedStart)
                },
            )
            .build()
        builder.setCategory(Notification.CATEGORY_STOPWATCH)
        OngoingActivity.Builder(context, notificationID, builder)
            .setOngoingActivityId(ONGOING_ACTIVITY_ID)
            .setStaticIcon(R.drawable.ic_vox_mic)
            .setTitle(context.getString(R.string.wear_brand))
            .setContentDescription(context.getString(R.string.wear_is_recording))
            .setStatus(ongoingStatus)
            .build()
            .apply(context)
    }

    private companion object {
        const val ONGOING_ACTIVITY_ID = 201
    }
}
