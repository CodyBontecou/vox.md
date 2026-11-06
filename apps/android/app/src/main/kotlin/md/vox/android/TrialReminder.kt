package md.vox.android

import android.Manifest
import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import java.util.Locale
import java.util.concurrent.TimeUnit

/**
 * Local "your trial ends in two days" reminder promised on the paywall's trial timeline.
 * Scheduled only after a free-trial purchase succeeds; contains no purchase or capture data.
 * When notification permission is missing or denied, the work simply posts nothing.
 */
internal object TrialReminderScheduler {
    private const val UNIQUE_NAME = "trial-ending-reminder-v1"

    fun schedule(context: Context, triggerAtEpochMillis: Long, nowEpochMillis: Long = System.currentTimeMillis()) {
        val delay = (triggerAtEpochMillis - nowEpochMillis).coerceAtLeast(0L)
        val request = OneTimeWorkRequestBuilder<TrialReminderWorker>()
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .build()
        runCatching {
            WorkManager.getInstance(context).enqueueUniqueWork(UNIQUE_NAME, ExistingWorkPolicy.REPLACE, request)
        }
    }

    fun cancel(context: Context) {
        runCatching { WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_NAME) }
    }
}

class TrialReminderWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    @SuppressLint("MissingPermission") // Checked by canPostNotifications.
    override suspend fun doWork(): Result {
        val context = applicationContext
        if (!canPostNotifications(context)) return Result.success()
        // Skip the reminder when the last verified Play answer no longer shows a subscription.
        val evidence = PlayEntitlementCache(
            context = context,
            productID = PlayBillingManager.LIFETIME_PRODUCT_ID,
            recognizedProductIDs = PlayBillingManager.ALL_PRODUCT_IDS,
        ).read()
        if (evidence != null && (!evidence.isOwned || evidence.productID !in PlayBillingManager.SUBSCRIPTION_PRODUCT_IDS)) {
            return Result.success()
        }
        val locale = context.resources.configuration.locales[0] ?: Locale.getDefault()
        // voxUiText keeps each source visible to the localization pipeline.
        fun text(source: VoxUiText) = RuntimeLocalization.translate(context, locale, source.source)
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                text(voxUiText("Trial reminders")),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = text(voxUiText("A reminder two days before a Vox.md free trial ends.")) },
        )
        val manageIntent = Intent(
            Intent.ACTION_VIEW,
            Uri.parse(
                VoxPlayCatalog.manageSubscriptionsUrl(
                    context.packageName,
                    evidence?.productID?.takeIf { it in PlayBillingManager.SUBSCRIPTION_PRODUCT_IDS },
                ),
            ),
        )
        val pendingIntent = PendingIntent.getActivity(
            context,
            0,
            manageIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(text(voxUiText("Your Vox.md trial ends in 2 days")))
            .setContentText(text(voxUiText("Keep Unlimited, or cancel anytime in Google Play › Payments & subscriptions.")))
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .bigText(text(voxUiText("Keep Unlimited, or cancel anytime in Google Play › Payments & subscriptions."))),
            )
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification) }
        return Result.success()
    }

    private fun canPostNotifications(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    private companion object {
        const val CHANNEL_ID = "vox-trial-reminder-v1"
        const val NOTIFICATION_ID = 4_107
    }
}
