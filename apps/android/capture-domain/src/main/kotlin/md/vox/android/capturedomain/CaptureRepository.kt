package md.vox.android.capturedomain

/** User-selected Android document-tree capability. The URI remains native-only. */
data class CaptureDestination(
    val id: String,
    val displayName: String,
    val treeUri: String,
)

data class CaptureMetadataField(
    val name: String,
    val value: String,
)

data class CapturePreset(
    val id: String,
    val name: String,
    val symbol: String,
    val revision: Int,
    val logicalFolder: String,
    val noteNameTemplate: String,
    val metadataFields: List<CaptureMetadataField>,
)

data class CapturePresetCollection(
    val activePresetID: String,
    val presets: List<CapturePreset>,
) {
    val activePreset: CapturePreset
        get() = presets.firstOrNull { it.id == activePresetID } ?: presets.first()
}

data class CaptureDraft(
    val text: String,
    val url: String?,
    val updatedAtEpochMillis: Long,
)

data class CaptureHistoryItem(
    val requestID: String,
    val createdAtEpochMillis: Long,
    val updatedAtEpochMillis: Long,
    val state: CaptureState,
    val attemptCount: Int,
)

data class CaptureDrainSummary(
    val inspected: Int,
    val delivered: Int,
    val retryable: Int,
    val needsPermission: Int,
    val blocked: Int,
)

sealed interface CaptureSubmitResult {
    data class Delivered(val requestID: String) : CaptureSubmitResult
    data class SavedForRetry(
        val requestID: String,
        val reason: String,
        val durablySaved: Boolean = true,
    ) : CaptureSubmitResult
    data class NeedsPermission(val requestID: String?) : CaptureSubmitResult
    data object DestinationRequired : CaptureSubmitResult
    data class LimitReached(val requestID: String) : CaptureSubmitResult
    data class InvalidInput(val reason: String) : CaptureSubmitResult
}

/**
 * UI-facing M3 capture boundary. Implementations perform blocking storage/provider work
 * off the main thread and expose only content-free outcomes and history projections.
 */
interface CaptureRepository {
    suspend fun currentDestination(): CaptureDestination?
    suspend fun saveDestination(treeUri: String, displayName: String): CaptureDestination
    suspend fun currentDraft(): CaptureDraft
    suspend fun saveDraft(text: String, url: String?): CaptureDraft
    suspend fun capturePresets(): CapturePresetCollection
    suspend fun selectCapturePreset(presetID: String): CapturePresetCollection
    suspend fun saveCapturePreset(preset: CapturePreset): CapturePresetCollection
    suspend fun deleteCapturePreset(presetID: String): CapturePresetCollection
    suspend fun submit(text: String, url: String?): CaptureSubmitResult
    suspend fun retry(requestID: String): CaptureSubmitResult
    suspend fun reconcile(): List<CaptureHistoryItem>
    suspend fun history(): List<CaptureHistoryItem>
    suspend fun drainPending(maxItems: Int): CaptureDrainSummary
}
