package md.vox.android.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureRepository
import md.vox.android.capturedomain.CaptureSubmitResult

data class CaptureUiState(
    val isLoading: Boolean = true,
    val isSending: Boolean = false,
    val isSavingConfiguration: Boolean = false,
    val destination: CaptureDestination? = null,
    val draft: CaptureDraft = CaptureDraft("", null, 0L),
    val presetCollection: CapturePresetCollection? = null,
    val history: List<CaptureHistoryItem> = emptyList(),
    val notice: String? = null,
    val acceptedRequestID: String? = null,
)

class CaptureViewModel private constructor(
    private val repository: CaptureRepository,
) : ViewModel() {
    private val mutableState = MutableStateFlow(CaptureUiState())
    val state: StateFlow<CaptureUiState> = mutableState.asStateFlow()
    private var draftSaveJob: Job? = null

    init {
        refresh(reconcile = true)
    }

    fun saveDestination(treeUri: String, displayName: String, retryRequestID: String? = null) {
        viewModelScope.launch {
            mutableState.update { it.copy(isLoading = true, notice = null) }
            runCatching { repository.saveDestination(treeUri, displayName) }
                .onSuccess { destination ->
                    mutableState.update { it.copy(isLoading = false, destination = destination) }
                    if (retryRequestID != null) retry(retryRequestID) else refresh()
                }
                .onFailure {
                    mutableState.update { state -> state.copy(isLoading = false, notice = "That folder could not be used. Choose another folder.") }
                }
        }
    }

    fun submit(text: String, url: String?) {
        if (mutableState.value.isSending) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSending = true, notice = null, acceptedRequestID = null) }
            draftSaveJob?.join()
            val result = runCatching { repository.submit(text, url) }
                .getOrElse { CaptureSubmitResult.SavedForRetry("unknown", "unexpectedFailure", durablySaved = false) }
            apply(result, acceptNewCapture = true)
        }
    }

    fun updateDraft(text: String, url: String?) {
        val next = CaptureDraft(text.take(65_536), url, System.currentTimeMillis())
        mutableState.update { it.copy(draft = next) }
        draftSaveJob?.cancel()
        draftSaveJob = viewModelScope.launch {
            runCatching { repository.saveDraft(next.text, next.url) }
                .onFailure {
                    mutableState.update { state -> state.copy(notice = "The current draft could not be saved locally.") }
                }
        }
    }

    fun selectPreset(presetID: String) {
        if (mutableState.value.isSavingConfiguration) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSavingConfiguration = true, notice = null) }
            runCatching { repository.selectCapturePreset(presetID) }
                .onSuccess { collection ->
                    mutableState.update { it.copy(isSavingConfiguration = false, presetCollection = collection) }
                }
                .onFailure {
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = "That capture preset could not be selected.") }
                }
        }
    }

    fun savePreset(preset: CapturePreset, onSaved: () -> Unit = {}) {
        if (mutableState.value.isSavingConfiguration) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSavingConfiguration = true, notice = null) }
            runCatching { repository.saveCapturePreset(preset) }
                .onSuccess { collection ->
                    mutableState.update {
                        it.copy(isSavingConfiguration = false, presetCollection = collection, notice = "Capture preset saved")
                    }
                    onSaved()
                }
                .onFailure {
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = "Check the preset name, folder, filename, and metadata fields.") }
                }
        }
    }

    fun deletePreset(presetID: String, onDeleted: () -> Unit = {}) {
        if (mutableState.value.isSavingConfiguration) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSavingConfiguration = true, notice = null) }
            runCatching { repository.deleteCapturePreset(presetID) }
                .onSuccess { collection ->
                    mutableState.update {
                        it.copy(isSavingConfiguration = false, presetCollection = collection, notice = "Capture preset deleted")
                    }
                    onDeleted()
                }
                .onFailure {
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = "The Default preset cannot be deleted.") }
                }
        }
    }

    fun retry(requestID: String) {
        if (mutableState.value.isSending) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSending = true, notice = null, acceptedRequestID = null) }
            val result = runCatching { repository.retry(requestID) }
                .getOrElse { CaptureSubmitResult.SavedForRetry(requestID, "unexpectedFailure") }
            apply(result, acceptNewCapture = false)
        }
    }

    fun refresh(reconcile: Boolean = false) {
        viewModelScope.launch {
            val destination = runCatching { repository.currentDestination() }.getOrNull()
            val draft = runCatching { repository.currentDraft() }.getOrDefault(CaptureDraft("", null, 0L))
            val presets = runCatching { repository.capturePresets() }.getOrNull()
            val history = runCatching { if (reconcile) repository.reconcile() else repository.history() }.getOrDefault(emptyList())
            mutableState.update { it.copy(isLoading = false, destination = destination, draft = draft, presetCollection = presets, history = history) }
        }
    }

    fun clearNotice() {
        mutableState.update { it.copy(notice = null) }
    }

    fun consumeAcceptedCapture() {
        mutableState.update { it.copy(acceptedRequestID = null) }
    }

    private suspend fun apply(result: CaptureSubmitResult, acceptNewCapture: Boolean) {
        val history = runCatching { repository.history() }.getOrDefault(mutableState.value.history)
        mutableState.update { state ->
            val acceptedRequestID = if (!acceptNewCapture) null else when (result) {
                is CaptureSubmitResult.Delivered -> result.requestID
                is CaptureSubmitResult.LimitReached -> result.requestID
                is CaptureSubmitResult.NeedsPermission -> result.requestID
                is CaptureSubmitResult.SavedForRetry -> result.requestID.takeIf { result.durablySaved }
                CaptureSubmitResult.DestinationRequired, is CaptureSubmitResult.InvalidInput -> null
            }
            val draft = if (acceptedRequestID == null) state.draft else CaptureDraft("", null, System.currentTimeMillis())
            when (result) {
                is CaptureSubmitResult.Delivered -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = "Capture sent",
                    acceptedRequestID = acceptedRequestID,
                )
                CaptureSubmitResult.DestinationRequired -> state.copy(
                    isSending = false,
                    history = history,
                    destination = null,
                    notice = "Choose a Markdown folder before sending.",
                )
                is CaptureSubmitResult.InvalidInput -> state.copy(isSending = false, draft = draft, history = history, notice = result.reason)
                is CaptureSubmitResult.LimitReached -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = "The free Capture limit has been reached. Your capture is saved locally.",
                    acceptedRequestID = acceptedRequestID,
                )
                is CaptureSubmitResult.NeedsPermission -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = "Folder access changed. Your capture is saved locally; choose the folder again to continue.",
                    acceptedRequestID = acceptedRequestID,
                )
                is CaptureSubmitResult.SavedForRetry -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = humanReason(result.reason),
                    acceptedRequestID = acceptedRequestID,
                )
            }
        }
    }

    private fun humanReason(reason: String): String = when (reason) {
        "captureBusy", "leaseLost" -> "Capture is busy. It is saved locally and can be retried."
        "commitOutcomeUnknown" -> "The folder provider did not confirm the result. Vox.md will not write again until it can reconcile safely."
        "bridgeUnavailable", "nativeUnavailable" -> "The local Markdown engine is unavailable. Your capture is saved for retry."
        "occupancyObservation", "occupancyObservationFailed" -> "The destination could not be checked. Your capture is saved for retry."
        "quotaFinalizationPending" -> "The capture was delivered; local usage reconciliation is still pending."
        else -> "Capture is saved locally and can be retried."
    }

    companion object {
        fun factory(repository: CaptureRepository): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = CaptureViewModel(repository) as T
        }
    }
}
