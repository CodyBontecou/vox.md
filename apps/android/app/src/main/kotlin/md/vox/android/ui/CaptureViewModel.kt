package md.vox.android.ui

import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureHistoryDetail
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.CaptureRepository
import md.vox.android.capturedomain.CaptureSubmitResult
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.capturedomain.CompletedRecordingActivity
import md.vox.android.capturedomain.CaptureLocationOutcome
import md.vox.android.VoxUiText

internal data class CaptureUiState(
    val isLoading: Boolean = true,
    val isSending: Boolean = false,
    val isSavingConfiguration: Boolean = false,
    val destination: CaptureDestination? = null,
    val draft: CaptureDraft = CaptureDraft("", null, 0L),
    val captureBar: CaptureBarConfiguration = CaptureBarConfiguration(),
    val presetCollection: CapturePresetCollection? = null,
    val isPresetRailExpanded: Boolean = false,
    val entryTemplates: List<CaptureEntryTemplate> = emptyList(),
    val history: List<CaptureHistoryItem> = emptyList(),
    val notice: VoxUiText? = null,
    val acceptedRequestID: String? = null,
    val pendingExternalDraftID: String? = null,
    val historyDetail: CaptureHistoryDetail? = null,
    val isLoadingHistoryDetail: Boolean = false,
    val activityStats: ActivityStats = ActivityStats.Empty,
    val isDeletingHistory: Boolean = false,
)

internal class CaptureViewModel private constructor(
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
                    mutableState.update { state -> state.copy(isLoading = false, notice = voxNotice("That folder could not be used. Choose another folder.")) }
                }
        }
    }

    fun submit(
        text: String,
        url: String?,
        locationOutcome: CaptureLocationOutcome = CaptureLocationOutcome.NotRequested,
    ) {
        if (mutableState.value.isSending) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSending = true, notice = null, acceptedRequestID = null) }
            draftSaveJob?.join()
            val result = runCatching { repository.submit(text, url, locationOutcome) }
                .getOrElse { CaptureSubmitResult.SavedForRetry("unknown", "unexpectedFailure", durablySaved = false) }
            apply(result, acceptNewCapture = true)
        }
    }

    fun updateDraft(text: String, url: String?) {
        val next = CaptureDraft(
            text = text.take(65_536),
            url = url,
            updatedAtEpochMillis = System.currentTimeMillis(),
            captureSource = mutableState.value.draft.captureSource,
            attachments = mutableState.value.draft.attachments,
            originRecordingID = mutableState.value.draft.originRecordingID,
            frozenPreset = mutableState.value.draft.frozenPreset,
            entryTemplateIDOverride = mutableState.value.draft.entryTemplateIDOverride,
        )
        mutableState.update { it.copy(draft = next) }
        draftSaveJob?.cancel()
        draftSaveJob = viewModelScope.launch {
            try {
                repository.saveDraft(next.text, next.url, next.captureSource)
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Throwable) {
                mutableState.update { state -> state.copy(notice = voxNotice("The current draft could not be saved locally.")) }
            }
        }
    }

    fun submitRecording(
        text: String,
        url: String?,
        originRecordingID: String,
        audioContentUri: String?,
        audioDisplayName: String?,
        frozenPreset: CapturePreset?,
        locationOutcome: CaptureLocationOutcome = CaptureLocationOutcome.NotRequested,
    ) {
        if (mutableState.value.isSending) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSending = true, notice = null, acceptedRequestID = null) }
            draftSaveJob?.join()
            val prepared = runCatching {
                repository.prepareVoiceDraft(text, url, originRecordingID, audioContentUri, audioDisplayName, frozenPreset)
            }.getOrElse {
                mutableState.update { state ->
                    state.copy(
                        isSending = false,
                        notice = voxNotice("The voice note could not be prepared. Its transcript and original recording are still safe."),
                    )
                }
                return@launch
            }
            mutableState.update { it.copy(draft = prepared) }
            val result = runCatching { repository.submit(text, url, locationOutcome) }
                .getOrElse { CaptureSubmitResult.SavedForRetry("unknown", "unexpectedFailure", durablySaved = false) }
            apply(result, acceptNewCapture = true)
        }
    }

    fun addDraftAttachment(
        contentUri: String,
        displayName: String? = null,
        mediaType: String? = null,
        includeInMarkdown: Boolean = true,
    ) {
        viewModelScope.launch {
            val draft = runCatching { repository.addDraftAttachment(contentUri, displayName, mediaType, includeInMarkdown) }
                .getOrElse { error ->
                    val notice = voxNotice(when (error.message) {
                        "attachmentTooLarge" -> "Attachments must be 100 MB or smaller."
                        "attachmentLimit" -> "A capture can contain up to 32 attachments."
                        else -> "That attachment could not be copied into the local draft."
                    })
                    mutableState.update { it.copy(notice = notice) }
                    return@launch
                }
            mutableState.update { it.copy(draft = draft, notice = null) }
        }
    }

    fun removeDraftAttachment(attachmentID: String) {
        viewModelScope.launch {
            val draft = runCatching { repository.removeDraftAttachment(attachmentID) }.getOrElse {
                mutableState.update { state -> state.copy(notice = voxNotice("That attachment could not be removed.")) }
                return@launch
            }
            mutableState.update { it.copy(draft = draft) }
        }
    }

    fun acceptExternalCapture(
        text: String,
        url: String?,
        presetID: String?,
        correlationID: String,
        sourceLabel: String,
        captureSource: String,
        attachmentUris: List<String>,
    ) {
        draftSaveJob?.cancel()
        draftSaveJob = viewModelScope.launch {
            runCatching { repository.setDraftEntryTemplateOverride(null) }
            var draft = runCatching { repository.saveDraft(text, url, captureSource) }.getOrElse {
                mutableState.update { state ->
                    state.copy(notice = voxNotice("%@ could not be saved locally.", sourceLabel))
                }
                return@launch
            }
            var failedAttachments = 0
            attachmentUris.forEach { uri ->
                draft = runCatching { repository.addDraftAttachment(uri, null, null) }
                    .getOrElse { failedAttachments += 1; draft }
            }
            val presets = if (presetID != null) {
                runCatching { repository.selectCapturePreset(presetID) }.getOrNull()
            } else {
                null
            }
            val notice = if (failedAttachments == 1) {
                voxNotice("%@ is ready, but 1 shared file could not be copied.", sourceLabel)
            } else if (failedAttachments > 1) {
                voxNotice(
                    "%1\$@ is ready, but %2\$lld shared files could not be copied.",
                    sourceLabel,
                    failedAttachments.toLong(),
                )
            } else {
                voxNotice("%@ is ready to review.", sourceLabel)
            }
            mutableState.update { state ->
                state.copy(
                    draft = draft,
                    presetCollection = presets ?: state.presetCollection,
                    notice = notice,
                    pendingExternalDraftID = correlationID,
                )
            }
        }
    }

    fun consumeExternalDraft() {
        mutableState.update { it.copy(pendingExternalDraftID = null) }
    }

    fun togglePresetRail() {
        val expanded = !mutableState.value.isPresetRailExpanded
        mutableState.update { it.copy(isPresetRailExpanded = expanded) }
        viewModelScope.launch {
            runCatching { repository.setPresetQuickAccessRailExpanded(expanded) }
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
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = voxNotice("That capture preset could not be selected.")) }
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
                        it.copy(isSavingConfiguration = false, presetCollection = collection, notice = voxNotice("Capture preset saved"))
                    }
                    onSaved()
                }
                .onFailure {
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = voxNotice("Check the preset name, folder, filename, and metadata fields.")) }
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
                        it.copy(isSavingConfiguration = false, presetCollection = collection, notice = voxNotice("Capture preset deleted"))
                    }
                    onDeleted()
                }
                .onFailure {
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = voxNotice("The Default preset cannot be deleted.")) }
                }
        }
    }

    fun setEntryTemplateOverride(templateID: String?) {
        val previous = mutableState.value.draft.entryTemplateIDOverride
        mutableState.update { state ->
            state.copy(draft = state.draft.copy(entryTemplateIDOverride = templateID), notice = null)
        }
        viewModelScope.launch {
            runCatching { repository.setDraftEntryTemplateOverride(templateID) }
                .onFailure {
                    mutableState.update { state ->
                        state.copy(
                            draft = if (state.draft.entryTemplateIDOverride == templateID) {
                                state.draft.copy(entryTemplateIDOverride = previous)
                            } else state.draft,
                            notice = voxNotice("That entry template is no longer available."),
                        )
                    }
                }
        }
    }

    fun saveEntryTemplate(template: CaptureEntryTemplate, onSaved: () -> Unit = {}) {
        if (mutableState.value.isSavingConfiguration) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSavingConfiguration = true, notice = null) }
            runCatching { repository.saveEntryTemplate(template) }
                .onSuccess { templates ->
                    val presets = runCatching { repository.capturePresets() }.getOrNull() ?: mutableState.value.presetCollection
                    mutableState.update {
                        it.copy(
                            isSavingConfiguration = false,
                            entryTemplates = templates,
                            presetCollection = presets,
                            notice = voxNotice("Entry template saved"),
                        )
                    }
                    onSaved()
                }
                .onFailure {
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = voxNotice("Check the template name and entry formatting.")) }
                }
        }
    }

    fun deleteEntryTemplate(templateID: String, onDeleted: () -> Unit = {}) {
        if (mutableState.value.isSavingConfiguration) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSavingConfiguration = true, notice = null) }
            runCatching { repository.deleteEntryTemplate(templateID) }
                .onSuccess { templates ->
                    val presets = runCatching { repository.capturePresets() }.getOrNull() ?: mutableState.value.presetCollection
                    val draft = runCatching { repository.currentDraft() }.getOrDefault(mutableState.value.draft)
                    mutableState.update {
                        it.copy(
                            isSavingConfiguration = false,
                            entryTemplates = templates,
                            presetCollection = presets,
                            draft = draft,
                            notice = voxNotice("Entry template deleted; linked presets kept their last formatting."),
                        )
                    }
                    onDeleted()
                }
                .onFailure {
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = voxNotice("That entry template could not be deleted.")) }
                }
        }
    }

    fun setCaptureBarActionVisible(action: CaptureBarAction, visible: Boolean) {
        val current = mutableState.value.captureBar
        val hidden = current.hiddenActions.toMutableSet().apply {
            if (visible) remove(action) else add(action)
        }
        saveCaptureBar(current.copy(hiddenActions = hidden))
    }

    fun moveCaptureBarAction(action: CaptureBarAction, direction: Int) {
        val current = mutableState.value.captureBar
        val from = current.orderedActions.indexOf(action)
        val to = (from + direction).coerceIn(0, current.orderedActions.lastIndex)
        if (from < 0 || from == to) return
        val order = current.orderedActions.toMutableList().apply {
            removeAt(from)
            add(to, action)
        }
        saveCaptureBar(current.copy(orderedActions = order))
    }

    fun setTwentyFourHourTimestamps(enabled: Boolean) {
        saveCaptureBar(mutableState.value.captureBar.copy(usesTwentyFourHourTimestamps = enabled))
    }

    fun setConfirmsVoiceNotesBeforeAdding(enabled: Boolean) {
        saveCaptureBar(mutableState.value.captureBar.copy(confirmsVoiceNotesBeforeAdding = enabled))
    }

    fun resetCaptureBar() {
        saveCaptureBar(CaptureBarConfiguration(), successNotice = voxNotice("Capture Bar reset"))
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

    fun loadHistoryDetail(requestID: String) {
        viewModelScope.launch {
            mutableState.update { it.copy(historyDetail = null, isLoadingHistoryDetail = true) }
            val detail = runCatching { repository.historyDetail(requestID) }.getOrNull()
            mutableState.update {
                it.copy(
                    historyDetail = detail,
                    isLoadingHistoryDetail = false,
                    notice = if (detail == null) voxNotice("That capture is no longer available.") else it.notice,
                )
            }
        }
    }

    fun clearHistoryDetail() {
        mutableState.update { it.copy(historyDetail = null, isLoadingHistoryDetail = false) }
    }

    fun deleteCompletedHistory(requestIDs: Set<String>, onComplete: () -> Unit = {}) {
        if (requestIDs.isEmpty() || mutableState.value.isDeletingHistory) return
        viewModelScope.launch {
            mutableState.update { it.copy(isDeletingHistory = true, notice = null) }
            val removed = runCatching { repository.deleteCompletedHistory(requestIDs) }.getOrDefault(0)
            val history = runCatching { repository.history() }.getOrDefault(mutableState.value.history)
            val stats = runCatching { repository.activityStats() }.getOrDefault(mutableState.value.activityStats)
            mutableState.update {
                it.copy(
                    isDeletingHistory = false,
                    history = history,
                    historyDetail = if (it.historyDetail?.requestID?.let(requestIDs::contains) == true) null else it.historyDetail,
                    activityStats = stats,
                    notice = if (removed == 0) {
                        voxNotice("No completed captures were removed.")
                    } else if (removed == 1) {
                        voxNotice("1 capture removed from History.")
                    } else {
                        voxNotice("%lld captures removed from History.", removed.toLong())
                    },
                )
            }
            if (removed > 0) onComplete()
        }
    }

    fun reconcileCompletedRecordings(recordings: List<CompletedRecordingActivity>) {
        viewModelScope.launch {
            val stats = runCatching { repository.recordCompletedRecordings(recordings) }.getOrNull() ?: return@launch
            mutableState.update { it.copy(activityStats = stats) }
        }
    }

    fun refresh(reconcile: Boolean = false) {
        viewModelScope.launch {
            val destination = runCatching { repository.currentDestination() }.getOrNull()
            val draft = runCatching { repository.currentDraft() }.getOrDefault(CaptureDraft("", null, 0L))
            val captureBar = runCatching { repository.captureBarConfiguration() }.getOrDefault(CaptureBarConfiguration())
            val presets = runCatching { repository.capturePresets() }.getOrNull()
            val presetRailExpanded = runCatching { repository.presetQuickAccessRailExpanded() }.getOrDefault(false)
            val entryTemplates = runCatching { repository.entryTemplates() }.getOrDefault(emptyList())
            val history = runCatching { if (reconcile) repository.reconcile() else repository.history() }.getOrDefault(emptyList())
            val activityStats = runCatching { repository.activityStats() }.getOrDefault(mutableState.value.activityStats)
            mutableState.update {
                it.copy(
                    isLoading = false,
                    destination = destination,
                    draft = draft,
                    captureBar = captureBar,
                    presetCollection = presets,
                    isPresetRailExpanded = presetRailExpanded,
                    entryTemplates = entryTemplates,
                    history = history,
                    activityStats = activityStats,
                )
            }
        }
    }

    fun clearNotice() {
        mutableState.update { it.copy(notice = null) }
    }

    fun presentNotice(message: VoxUiText) {
        mutableState.update { it.copy(notice = message.copy(source = message.source.take(240))) }
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
                    notice = voxNotice("Capture sent"),
                    acceptedRequestID = acceptedRequestID,
                )
                CaptureSubmitResult.DestinationRequired -> state.copy(
                    isSending = false,
                    history = history,
                    destination = null,
                    notice = voxNotice("Choose a Markdown folder before sending."),
                )
                is CaptureSubmitResult.InvalidInput -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = invalidInputNotice(result.reason),
                )
                is CaptureSubmitResult.LimitReached -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = voxNotice("The free Capture limit has been reached. Your capture is saved locally."),
                    acceptedRequestID = acceptedRequestID,
                )
                is CaptureSubmitResult.NeedsPermission -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = voxNotice("Folder access changed. Your capture is saved locally; choose the folder again to continue."),
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
        if (result is CaptureSubmitResult.Delivered) {
            viewModelScope.launch {
                val stats = runCatching { repository.activityStats() }.getOrNull() ?: return@launch
                mutableState.update { it.copy(activityStats = stats) }
            }
        }
    }

    private fun invalidInputNotice(reason: String): VoxUiText = when (reason) {
        "The recording identity or source is invalid." ->
            voxNotice("The recording identity or source is invalid.")
        "The frozen recording preset is invalid." ->
            voxNotice("The frozen recording preset is invalid.")
        "Capture text must be 65,536 characters or fewer." ->
            voxNotice("Capture text must be 65,536 characters or fewer.")
        "Write something or add a link before sending." ->
            voxNotice("Write something or add a link before sending.")
        "Enter a complete http:// or https:// link." ->
            voxNotice("Enter a complete http:// or https:// link.")
        "One or more attachments are no longer available. Remove them and add them again." ->
            voxNotice("One or more attachments are no longer available. Remove them and add them again.")
        "This capture is too large after adding attachment links. Shorten the text and try again." ->
            voxNotice("This capture is too large after adding attachment links. Shorten the text and try again.")
        "Capture is no longer available." ->
            voxNotice("Capture is no longer available.")
        else -> voxNotice("Capture input is invalid.")
    }

    private fun humanReason(reason: String): VoxUiText = when (reason) {
        "captureBusy", "leaseLost" -> voxNotice("Capture is busy. It is saved locally and can be retried.")
        "commitOutcomeUnknown" -> voxNotice("The folder provider did not confirm the result. Vox.md will not write again until it can reconcile safely.")
        "bridgeUnavailable", "nativeUnavailable" -> voxNotice("The local Markdown engine is unavailable. Your capture is saved for retry.")
        "occupancyObservation", "occupancyObservationFailed" -> voxNotice("The destination could not be checked. Your capture is saved for retry.")
        "quotaFinalizationPending" -> voxNotice("The capture was delivered; local usage reconciliation is still pending.")
        else -> voxNotice("Capture is saved locally and can be retried.")
    }

    private fun saveCaptureBar(configuration: CaptureBarConfiguration, successNotice: VoxUiText? = null) {
        if (mutableState.value.isSavingConfiguration) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSavingConfiguration = true, notice = null) }
            runCatching { repository.saveCaptureBarConfiguration(configuration) }
                .onSuccess { saved ->
                    mutableState.update {
                        it.copy(
                            isSavingConfiguration = false,
                            captureBar = saved,
                            notice = successNotice,
                        )
                    }
                }
                .onFailure {
                    mutableState.update {
                        it.copy(isSavingConfiguration = false, notice = voxNotice("The Capture Bar configuration could not be saved."))
                    }
                }
        }
    }

    companion object {
        fun factory(repository: CaptureRepository): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = CaptureViewModel(repository) as T
        }
    }
}

private fun voxNotice(source: String, vararg arguments: Any): VoxUiText =
    VoxUiText(source, arguments.toList())
