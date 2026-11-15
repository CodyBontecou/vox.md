package md.vox.android

import md.vox.android.platformservices.RecordingPhase

/**
 * The empty editor's line while a recording runs, before any words land: it sits where
 * the live transcript will start, and the words replace it. `null` once the draft has
 * text, or when no recording is running (stopped, discarded or failed).
 */
internal fun composerRecordingStatusUiText(draftText: String, phase: RecordingPhase): VoxUiText? {
    if (draftText.isNotEmpty()) return null
    return when (phase) {
        RecordingPhase.RECORDING -> voxUiText("Listening for speech…")
        RecordingPhase.PAUSED -> voxUiText("Paused")
        else -> null
    }
}
