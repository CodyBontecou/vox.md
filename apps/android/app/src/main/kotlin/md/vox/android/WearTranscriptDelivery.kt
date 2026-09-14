package md.vox.android

import android.content.Context
import android.os.SystemClock
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import kotlinx.coroutines.delay
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureRepository
import md.vox.android.capturedomain.CaptureSubmitResult
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.capturedomain.WearRemoteRecordingPhase
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState

internal sealed interface WearTranscriptDeliveryResult {
    data class Delivered(val requestID: String, val transcript: String) : WearTranscriptDeliveryResult
    data class Retryable(val code: String) : WearTranscriptDeliveryResult
    data class Failed(val code: String) : WearTranscriptDeliveryResult
}

/**
 * Background-safe owner of the Wear `Transcribe & Capture` route. The frozen preset,
 * recording UUID, and imported audio are reused throughout so retries cannot change
 * either the destination policy or the idempotency key.
 */
internal class WearTranscriptDelivery(
    context: Context,
    private val repository: CaptureRepository,
    private val audioClient: AudioCaptureClient = AudioCaptureClient(context),
    private val transcriptionClient: RecordingTranscriptionClient = RecordingTranscriptionClient.get(context),
) {
    private val appContext = context.applicationContext

    suspend fun deliver(recordingID: String, frontier: Int): WearTranscriptDeliveryResult {
        val recording = audioClient.recordings().firstOrNull { it.sessionID == recordingID }
            ?: return WearTranscriptDeliveryResult.Failed("recordingMissing")
        if (!audioClient.isImportedFromWear(recordingID)) {
            return WearTranscriptDeliveryResult.Failed("notWearRecording")
        }
        if (frontier <= 0 || frontier != recording.chunkCount) {
            return WearTranscriptDeliveryResult.Failed("incompleteFrontier")
        }
        val preset = audioClient.frozenPreset(recordingID)
            ?: return WearTranscriptDeliveryResult.Failed("presetMissing")
        if (preset.watchOutputMode != CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE) {
            return WearTranscriptDeliveryResult.Failed("outputMode")
        }

        val transcription = completedTranscription(recordingID)
            ?: return when (val state = transcriptionClient.states.value[recordingID]) {
                null -> WearTranscriptDeliveryResult.Retryable("transcriptionUnavailable")
                else -> if (state.failureCode == "modelNotInstalled") {
                    WearTranscriptDeliveryResult.Retryable("modelNotInstalled")
                } else {
                    WearTranscriptDeliveryResult.Failed(state.failureCode ?: "transcriptionFailed")
                }
            }
        val needsAudio = preset.audioSaveMode != CaptureAudioSaveMode.OFF
        val audioUri = if (needsAudio) exportRecordingForCapture(appContext, audioClient, recordingID) else null
        if (needsAudio && audioUri == null) return WearTranscriptDeliveryResult.Retryable("audioPreparationFailed")
        val result = repository.submitRecording(
            text = transcription.preferredTranscript.orEmpty(),
            url = null,
            originRecordingID = recordingID,
            audioContentUri = audioUri,
            audioDisplayName = "Recording-${recordingID.take(8)}.wav",
            frozenPreset = preset,
            captureSource = "wear",
        )
        return when (result) {
            is CaptureSubmitResult.Delivered -> WearTranscriptDeliveryResult.Delivered(
                result.requestID,
                transcription.preferredTranscript.orEmpty(),
            )
            is CaptureSubmitResult.SavedForRetry -> WearTranscriptDeliveryResult.Retryable(result.reason)
            is CaptureSubmitResult.NeedsPermission -> WearTranscriptDeliveryResult.Retryable("folderAccess")
            is CaptureSubmitResult.DestinationRequired -> WearTranscriptDeliveryResult.Retryable("destinationRequired")
            is CaptureSubmitResult.LimitReached -> WearTranscriptDeliveryResult.Failed("quotaReached")
            is CaptureSubmitResult.InvalidInput -> WearTranscriptDeliveryResult.Failed("invalidCapture")
        }
    }

    private suspend fun completedTranscription(recordingID: String): RecordingTranscriptionState? {
        transcriptionClient.states.value[recordingID]?.takeIf { it.phase == RecordingTranscriptionPhase.COMPLETED }
            ?.let { return it }
        transcriptionClient.process(recordingID)
        val deadline = SystemClock.uptimeMillis() + TRANSCRIPTION_TIMEOUT_MILLIS
        while (SystemClock.uptimeMillis() < deadline) {
            val state = transcriptionClient.states.value[recordingID]
            when (state?.phase) {
                RecordingTranscriptionPhase.COMPLETED -> return state
                RecordingTranscriptionPhase.FAILED,
                RecordingTranscriptionPhase.DISCARDED,
                -> return null
                else -> delay(100)
            }
        }
        return null
    }

    private companion object {
        const val TRANSCRIPTION_TIMEOUT_MILLIS = 5L * 60L * 1_000L
    }
}

class WearTranscriptDeliveryWorker(
    appContext: Context,
    params: WorkerParameters,
    private val repository: CaptureRepository,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val recordingID = inputData.getString(KEY_RECORDING_ID) ?: return Result.failure()
        val frontier = inputData.getInt(KEY_FRONTIER, 0)
        PhoneWearBridge.postStatus(
            applicationContext,
            recordingID,
            WearRemoteRecordingPhase.TRANSCRIBING,
            minimumRevision = 0,
            frontier = frontier,
        )
        return when (val result = WearTranscriptDelivery(applicationContext, repository).deliver(recordingID, frontier)) {
            is WearTranscriptDeliveryResult.Delivered -> {
                if (PhoneWearBridge.postStatus(
                        applicationContext,
                        recordingID,
                        WearRemoteRecordingPhase.DELIVERED,
                        minimumRevision = 0,
                        frontier = frontier,
                    )
                ) Result.success() else Result.retry()
            }
            is WearTranscriptDeliveryResult.Retryable -> {
                CaptureDrainWorker.schedule(applicationContext)
                PhoneWearBridge.postStatus(
                    applicationContext,
                    recordingID,
                    WearRemoteRecordingPhase.FAILED,
                    minimumRevision = 0,
                    frontier = frontier,
                    message = result.code,
                )
                Result.retry()
            }
            is WearTranscriptDeliveryResult.Failed -> {
                PhoneWearBridge.postStatus(
                    applicationContext,
                    recordingID,
                    WearRemoteRecordingPhase.FAILED,
                    minimumRevision = 0,
                    frontier = frontier,
                    message = result.code,
                )
                Result.failure(Data.Builder().putString(KEY_FAILURE, result.code).build())
            }
        }
    }

    companion object {
        private const val KEY_RECORDING_ID = "recordingID"
        private const val KEY_FRONTIER = "frontier"
        private const val KEY_FAILURE = "failure"

        fun enqueue(context: Context, recordingID: String, frontier: Int) {
            val request = OneTimeWorkRequestBuilder<WearTranscriptDeliveryWorker>()
                .setInputData(
                    Data.Builder()
                        .putString(KEY_RECORDING_ID, recordingID)
                        .putInt(KEY_FRONTIER, frontier.coerceAtLeast(0))
                        .build(),
                )
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "wear-transcript-delivery-$recordingID",
                ExistingWorkPolicy.KEEP,
                request,
            )
        }
    }
}
