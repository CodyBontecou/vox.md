package md.vox.android

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.ListenableWorker
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import md.vox.android.capturedomain.CaptureDrainSummary
import md.vox.android.capturedomain.CaptureRepository

class CaptureDrainWorker(
    appContext: Context,
    parameters: WorkerParameters,
    private val repository: CaptureRepository,
) : CoroutineWorker(appContext, parameters) {
    override suspend fun doWork(): Result = runCatching {
        repository.drainPending(MAX_ITEMS_PER_RUN)
    }.fold(
        onSuccess = { summary -> if (shouldRetryCaptureDrain(summary)) Result.retry() else Result.success() },
        onFailure = { Result.retry() },
    )

    companion object {
        private const val UNIQUE_NAME = "capture-durable-drain-v1"
        private const val MAX_ITEMS_PER_RUN = 16

        fun schedule(context: Context) {
            val request = OneTimeWorkRequestBuilder<CaptureDrainWorker>()
                .setConstraints(Constraints.Builder().setRequiresStorageNotLow(true).build())
                .setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(UNIQUE_NAME, ExistingWorkPolicy.KEEP, request)
        }
    }
}

internal fun shouldRetryCaptureDrain(summary: CaptureDrainSummary): Boolean = summary.retryable > 0

class VoxWorkerFactory(
    private val repository: () -> CaptureRepository,
) : WorkerFactory() {
    override fun createWorker(
        appContext: Context,
        workerClassName: String,
        workerParameters: WorkerParameters,
    ): ListenableWorker? = when (workerClassName) {
        CaptureDrainWorker::class.java.name -> CaptureDrainWorker(appContext, workerParameters, repository())
        else -> null
    }
}
