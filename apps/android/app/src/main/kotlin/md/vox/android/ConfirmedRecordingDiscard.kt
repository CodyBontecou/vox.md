package md.vox.android

import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus

/**
 * The composer's Discard (confirmed in "Discard this recording?", which promises "The audio
 * and live transcript are deleted") cancels the recording and then deletes its audio, as
 * iOS `cancelSegment()` does. Cancel alone only marks the session DISCARDED and keeps its
 * chunks recoverable, which is right for Recovery and the notification's Cancel but broke
 * that promise.
 *
 * Only the audio chunks are removed; the session's manifest stays (shown in Recovery as a
 * cancelled recording without audio). Deleting the whole session would move the "latest
 * recording" pointer to an older session, and the composer could then pick up that older
 * session's transcript.
 */
internal object ConfirmedRecordingDiscard {
    const val TIMEOUT_MILLIS = 10_000L

    /**
     * Cancels [sessionID], waits until the recorder has marked it DISCARDED (the final chunk
     * is flushed before that is published), then deletes its audio. Returns whether the
     * audio was deleted.
     */
    suspend fun discard(
        sessionID: String?,
        cancel: () -> Unit,
        status: Flow<RecordingStatus>,
        deleteAudio: (String) -> Boolean,
        timeoutMillis: Long = TIMEOUT_MILLIS,
    ): Boolean {
        cancel()
        val id = sessionID ?: return false
        withTimeoutOrNull(timeoutMillis) {
            status.first { it.sessionID == id && it.phase == RecordingPhase.DISCARDED }
        } ?: return false
        return deleteAudio(id)
    }
}
