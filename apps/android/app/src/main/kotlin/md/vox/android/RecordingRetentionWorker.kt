package md.vox.android

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingJobPolicy
import md.vox.android.platformservices.RecordingJobPolicyStore
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.recordingRetentionDeadlineEpochMillis
import md.vox.android.platformservices.shouldDeleteRecordingAudio
import java.util.concurrent.TimeUnit

/** Enforces content-safe recording retention even when the UI is not running. */
class RecordingRetentionWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    override suspend fun doWork(): Result = runCatching {
        val audio = AudioCaptureClient(applicationContext)
        val policies = RecordingJobPolicyStore.get(applicationContext)
        val transcriptionStates = RecordingTranscriptionClient.get(applicationContext).states.value
        val target = inputData.getString(INPUT_SESSION_ID)
        audio.recordings().asSequence()
            .filter { target == null || it.sessionID == target }
            .forEach { recording ->
                val sessionID = recording.sessionID ?: return@forEach
                val transcription = transcriptionStates[sessionID]
                if (shouldDeleteRecordingAudio(
                        policy = policies.policy(sessionID),
                        transcriptionCompleted = transcription?.phase == RecordingTranscriptionPhase.COMPLETED,
                        completedAtEpochMillis = transcription?.completedAtEpochMillis,
                        nowEpochMillis = System.currentTimeMillis(),
                    )
                ) {
                    audio.deleteRetainedAudio(sessionID)
                }
            }
    }.fold(onSuccess = { Result.success() }, onFailure = { Result.retry() })

    companion object {
        private const val INPUT_SESSION_ID = "sessionID"
        private const val PERIODIC_NAME = "recording-retention-sweep-v1"
        private const val SESSION_PREFIX = "recording-retention-v1-"

        fun scheduleSweep(context: Context) {
            val request = PeriodicWorkRequestBuilder<RecordingRetentionWorker>(12, TimeUnit.HOURS).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork(
                PERIODIC_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                request,
            )
        }

        fun schedule(
            context: Context,
            sessionID: String,
            policy: RecordingJobPolicy,
            transcriptionCompletedAtEpochMillis: Long?,
            nowEpochMillis: Long = System.currentTimeMillis(),
        ) {
            val workManager = WorkManager.getInstance(context)
            val uniqueName = SESSION_PREFIX + sessionID
            val deadline = recordingRetentionDeadlineEpochMillis(policy, transcriptionCompletedAtEpochMillis)
            if (deadline == null) {
                workManager.cancelUniqueWork(uniqueName)
                return
            }
            val delay = (deadline - nowEpochMillis).coerceAtLeast(0)
            val request = OneTimeWorkRequestBuilder<RecordingRetentionWorker>()
                .setInputData(Data.Builder().putString(INPUT_SESSION_ID, sessionID).build())
                .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                .build()
            workManager.enqueueUniqueWork(uniqueName, ExistingWorkPolicy.REPLACE, request)
        }
    }
}
