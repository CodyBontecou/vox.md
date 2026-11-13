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
import md.vox.android.capturedomain.CaptureRecoveryCommand
import md.vox.android.capturedomain.CaptureRecoveryResult
import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.withLock
import md.vox.android.capturedomain.CaptureDestination as LiveNoteVault
import md.vox.android.capturedomain.LiveNoteBinding
import md.vox.android.capturedomain.LiveNoteConflict
import md.vox.android.capturedomain.LiveNoteCopyResult
import md.vox.android.capturedomain.LiveNoteFileStore
import md.vox.android.capturedomain.LiveNoteLocation
import md.vox.android.capturedomain.LiveNotePendingWrite
import md.vox.android.capturedomain.LiveNotePlan
import md.vox.android.capturedomain.LiveNoteRange
import md.vox.android.capturedomain.LiveNoteReadResult
import md.vox.android.capturedomain.LiveNoteRelease
import md.vox.android.capturedomain.LiveNoteSession
import md.vox.android.capturedomain.LiveNoteSync
import md.vox.android.capturedomain.LiveNoteSyncOutcome
import md.vox.android.capturedomain.LiveNoteWriteResult
import md.vox.android.capturedomain.VaultBrowser
import md.vox.android.capturedomain.VaultListing
import md.vox.android.capturedomain.CaptureRouteOverride
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CaptureWebLink
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.capturedomain.CaptureHistoryDetail
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.CaptureRepository
import md.vox.android.capturedomain.CaptureTextProcessingOutcome
import md.vox.android.capturedomain.CaptureSubmitResult
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.capturedomain.CompletedRecordingActivity
import md.vox.android.capturedomain.CaptureLocationOutcome
import md.vox.android.VoxUiText
import md.vox.android.mergeExternalDraft
import md.vox.android.recoveryRejectionNotice

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
    val pendingWidgetPresetID: String? = null,
    val historyDetail: CaptureHistoryDetail? = null,
    val isLoadingHistoryDetail: Boolean = false,
    val activityStats: ActivityStats = ActivityStats.Empty,
    val isDeletingHistory: Boolean = false,
    /** Live Notes: the composer's binding to its vault file and the save status. */
    val liveNote: LiveNoteSession = LiveNoteSession(),
    /** Bumped whenever the view model replaces the editor text (bind, reload, New note, open). */
    val liveNoteEditor: LiveNoteEditorUpdate? = null,
    /** "<title> is in <preset>" after New note, with Reopen. */
    val liveNoteReleased: LiveNoteRelease? = null,
    /** True when the bound file was opened from the Files tab (back instead of the preset switcher). */
    val liveNoteOpenedFromFiles: Boolean = false,
    /** Recent "changed in another app" reloads, for the Activity timeline (this process only). */
    val liveNoteEvents: List<LiveNoteEvent> = emptyList(),
)

internal data class LiveNoteEditorUpdate(
    val revision: Long,
    val text: String,
    /** The entry to highlight (append presets) and to put the caret after. */
    val entryRange: LiveNoteRange? = null,
    /** Where to put the caret; null keeps it (clamped). Opened files start at the end. */
    val caret: Int? = null,
)

internal enum class LiveNoteEventKind { RELOADED, SAVED_COPY }

internal data class LiveNoteEvent(
    val atEpochMillis: Long,
    val kind: LiveNoteEventKind,
    val title: String,
    val relativePath: String,
)

internal class CaptureViewModel private constructor(
    private val repository: CaptureRepository,
    private val liveNotes: LiveNoteFileStore,
    private val vault: VaultBrowser?,
    private val media: md.vox.android.capturedomain.VaultMediaResolver? = null,
) : ViewModel() {
    private val mutableState = MutableStateFlow(CaptureUiState())
    val state: StateFlow<CaptureUiState> = mutableState.asStateFlow()
    private var draftSaveJob: Job? = null
    private var routeSaveJob: Job? = null
    private var liveSaveJob: Job? = null
    private var livePersistJob: Job? = null
    private var liveWriteJob: Job? = null
    // Unique across process restarts: the screen applies an update only once per revision.
    private val liveSaveMutex = kotlinx.coroutines.sync.Mutex()
    private var livePendingSince: Long? = null
    private var editorRevision = System.currentTimeMillis() * 1_000

    init {
        refresh(reconcile = true)
        viewModelScope.launch { restoreLiveNote() }
    }

    fun saveDestination(treeUri: String, displayName: String, retryRequestID: String? = null) {
        viewModelScope.launch {
            mutableState.update { it.copy(isLoading = true, notice = null) }
            runCatching { repository.saveDestination(treeUri, displayName) }
                .onSuccess { destination ->
                    mutableState.update { it.copy(isLoading = false, destination = destination) }
                    if (retryRequestID != null) retry(retryRequestID) else refresh()
                    // Folder access is back: write what was kept on the phone.
                    val pending = mutableState.value.liveNote.pending
                    if (pending != null && pending.requestID != retryRequestID) retry(pending.requestID) else refreshLiveNote()
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
            routeSaveJob?.join()
            val result = runCatching { repository.submit(text, url, locationOutcome) }
                .getOrElse { CaptureSubmitResult.SavedForRetry("unknown", "unexpectedFailure", durablySaved = false) }
            apply(result, acceptNewCapture = true)
        }
    }

    fun updateDraft(text: String, url: String?) {
        if (mutableState.value.liveNote.isStarted || mutableState.value.liveNote.isWriting) {
            updateLiveText(text)
            return
        }
        val normalizedURL = CaptureWebLink.normalize(url)
        val invalidLink = !url.isNullOrBlank() && normalizedURL == null
        val next = CaptureDraft(
            text = text.take(65_536),
            // An invalid attachment must never prevent otherwise valid text edits
            // from reaching durable storage. Keep the last admitted link instead.
            url = if (invalidLink) CaptureWebLink.normalize(mutableState.value.draft.url) else normalizedURL,
            updatedAtEpochMillis = System.currentTimeMillis(),
            captureSource = mutableState.value.draft.captureSource,
            attachments = mutableState.value.draft.attachments,
            originRecordingID = mutableState.value.draft.originRecordingID,
            originRecordingCreatedAtEpochMillis = mutableState.value.draft.originRecordingCreatedAtEpochMillis,
            frozenPreset = mutableState.value.draft.frozenPreset,
            entryTemplateIDOverride = mutableState.value.draft.entryTemplateIDOverride,
            routeOverride = mutableState.value.draft.routeOverride,
        )
        mutableState.update {
            it.copy(draft = next, notice = if (invalidLink) voxNotice("Enter a complete http:// or https:// link.") else it.notice)
        }
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
            routeSaveJob?.join()
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
            if (mutableState.value.liveNote.isBound) attachToBoundNote()
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
            // Shared text starts its own note; the bound file must never be overwritten by it.
            if (mutableState.value.liveNote.isStarted) releaseLiveNote(showToast = true)
            if (captureSource == "widget" && presetID != null && text.isBlank() && url == null && attachmentUris.isEmpty()) {
                val loaded = runCatching { repository.capturePresets() to repository.currentDraft() }.getOrElse {
                    mutableState.update { it.copy(notice = voxNotice("That capture preset could not be selected."), pendingExternalDraftID = correlationID) }
                    return@launch
                }
                val (presets, draft) = loaded
                val target = presets.presets.firstOrNull { it.id == presetID && it.isEnabled }
                if (target == null) {
                    mutableState.update { it.copy(notice = voxNotice("The requested Capture Preset no longer exists or is disabled."), pendingExternalDraftID = correlationID) }
                } else if ((draft.text.isNotBlank() || draft.url != null || draft.attachments.isNotEmpty()) &&
                    (draft.frozenPreset?.id ?: presets.activePresetID) != target.id) {
                    mutableState.update { it.copy(draft = draft, presetCollection = presets, pendingWidgetPresetID = target.id, pendingExternalDraftID = correlationID) }
                } else {
                    runCatching { repository.selectCapturePresetForDraft(target.id) to repository.currentDraft() }
                        .onSuccess { (selected, current) -> mutableState.update { it.copy(draft = current, presetCollection = selected, pendingExternalDraftID = correlationID) } }
                        .onFailure { mutableState.update { it.copy(notice = voxNotice("That capture preset could not be selected."), pendingExternalDraftID = correlationID) } }
                }
                return@launch
            }
            runCatching { repository.setDraftEntryTemplateOverride(null) }
            var draft = runCatching {
                val present = repository.currentDraft()
                val merged = mergeExternalDraft(present.text, present.url, text, url)
                repository.saveDraft(merged.text, merged.url, captureSource)
            }.getOrElse {
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
            val notice = if (failedAttachments > 0) {
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

    fun dismissWidgetPreset() { mutableState.update { it.copy(pendingWidgetPresetID = null) } }
    fun confirmWidgetPreset() {
        val id = mutableState.value.pendingWidgetPresetID ?: return
        viewModelScope.launch {
            draftSaveJob?.join(); routeSaveJob?.join()
            runCatching { repository.selectCapturePresetForDraft(id) }
                .onSuccess { presets ->
                    val draft = repository.currentDraft()
                    mutableState.update { it.copy(presetCollection = presets, draft = draft, pendingWidgetPresetID = null) }
                }.onFailure { mutableState.update { it.copy(pendingWidgetPresetID = null, notice = voxNotice("That capture preset could not be selected.")) } }
        }
    }

    fun selectPreset(presetID: String) {
        if (mutableState.value.isSavingConfiguration) return
        viewModelScope.launch {
            // The bound file's path is fixed; another preset means another note.
            if (mutableState.value.liveNote.isStarted && mutableState.value.presetCollection?.activePresetID != presetID) {
                releaseLiveNote(showToast = true)
            }
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

    /**
     * First-run "Start with these routes": saves each chosen starter preset through the normal
     * preset store, skipping any whose name already exists, then makes [activePresetID] (else the
     * first new route) the active route. Mirrors iOS StarterRouteInstaller.
     */
    fun installStarterPresets(presets: List<CapturePreset>, activePresetID: String?, onInstalled: () -> Unit) {
        if (mutableState.value.isSavingConfiguration) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSavingConfiguration = true, notice = null) }
            runCatching {
                val existingNames = repository.capturePresets().presets.map { it.name.trim().lowercase() }.toSet()
                val created = presets.filter { it.name.trim().lowercase() !in existingNames }
                var collection: CapturePresetCollection? = null
                created.forEach { collection = repository.saveCapturePreset(it) }
                val active = created.firstOrNull { it.id == activePresetID }?.id ?: created.firstOrNull()?.id
                if (active != null) collection = repository.selectCapturePreset(active)
                collection ?: repository.capturePresets()
            }
                .onSuccess { collection ->
                    mutableState.update { it.copy(isSavingConfiguration = false, presetCollection = collection) }
                    onInstalled()
                }
                .onFailure { error ->
                    if (error is CancellationException) throw error
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = voxNotice("The capture route could not be saved.")) }
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
                    // Drop the deleted route's own quick actions so they cannot resurface.
                    if (mutableState.value.captureBar.hasCustomPins(presetID)) setRouteQuickActions(presetID, null)
                }
                .onFailure {
                    mutableState.update { it.copy(isSavingConfiguration = false, notice = voxNotice("The Default preset cannot be deleted.")) }
                }
        }
    }

    fun setRouteOverride(route: CaptureRouteOverride?) {
        if (mutableState.value.isSending) return
        // Serialize with draft saves; submission joins this job before freezing the request.
        val previous = routeSaveJob
        routeSaveJob = viewModelScope.launch {
            previous?.join()
            runCatching { repository.setDraftRouteOverride(route) }
                .onSuccess { draft -> mutableState.update { it.copy(draft = it.draft.copy(routeOverride = draft.routeOverride), notice = null) } }
                .onFailure { mutableState.update { it.copy(notice = voxNotice("The capture route could not be saved.")) } }
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

    fun setVoiceRecordingResult(result: VoiceRecordingResult) {
        saveCaptureBar(mutableState.value.captureBar.copy(voiceRecordingResult = result))
    }

    /** Resets the global row. Per-route quick actions are kept; reset those from each route. */
    fun resetCaptureBar() {
        saveCaptureBar(
            CaptureBarConfiguration(routePins = mutableState.value.captureBar.routePins),
            successNotice = voxNotice("Capture Bar reset"),
        )
    }

    /** Sets a route's own quick actions; `null` makes the route follow the global Capture Bar again. */
    fun setRouteQuickActions(routeID: String, actions: List<CaptureBarAction>?) {
        saveCaptureBar(mutableState.value.captureBar.withRoutePins(routeID, actions))
    }

    suspend fun recoveryContext(requestID: String) = runCatching { repository.recoveryContext(requestID) }.getOrNull()

    fun replaceCapture(command: CaptureRecoveryCommand) {
        if (mutableState.value.isSending) return
        mutableState.update { it.copy(isSending = true, notice = null) }
        viewModelScope.launch {
            val result = runCatching { repository.replaceCapture(command) }.getOrElse { CaptureRecoveryResult.Waiting(command.intentID) }
            val notice = when (result) {
                is CaptureRecoveryResult.Accepted -> if (result.delivery is CaptureSubmitResult.Delivered) voxNotice("Capture delivered")
                    else voxNotice("Recovery is saved. Delivery is waiting on this device.")
                is CaptureRecoveryResult.Waiting -> voxNotice("Recovery is waiting. Retry delivery to continue the same decision.")
                is CaptureRecoveryResult.Rejected -> recoveryRejectionNotice(result.reason)
            }
            mutableState.update { it.copy(isSending = false, notice = notice) }
            refresh(reconcile = true)
        }
    }

    fun discard(requestID: String) {
        if (mutableState.value.isSending) return
        mutableState.update { it.copy(isSending = true, notice = null) }
        viewModelScope.launch {
            val discarded = runCatching { repository.discard(requestID) }.getOrDefault(false)
            mutableState.update { it.copy(isSending = false, notice = voxNotice(
                if (discarded) "Capture discarded" else "This delivery cannot be discarded safely yet. Retry to check its outcome.",
            )) }
            refresh(reconcile = true)
        }
    }

    fun retry(requestID: String) {
        if (mutableState.value.isSending) return
        viewModelScope.launch {
            mutableState.update { it.copy(isSending = true, notice = null, acceptedRequestID = null) }
            val result = runCatching { repository.retry(requestID) }
                .getOrElse { CaptureSubmitResult.SavedForRetry(requestID, "unexpectedFailure") }
            apply(result, acceptNewCapture = false)
            if (mutableState.value.liveNote.pending?.requestID == requestID) completeFirstWrite(result)
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

    /** Reads one capture's local package without touching the screen's selected detail. */
    suspend fun historyDetailSnapshot(requestID: String): CaptureHistoryDetail? =
        runCatching { repository.historyDetail(requestID) }.getOrNull()

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


    // ---- Live Notes: generate = save ----

    /**
     * First write of a new composer note: the text goes through the durable capture pipeline
     * (path planning, entry rendering, verified SAF commit) exactly once, and the composer then
     * binds to the file it produced. Called by the screen after ~600 ms idle, on background, or
     * when the location preflight finishes.
     */
    fun startLiveNote(text: String, url: String?, locationOutcome: CaptureLocationOutcome = CaptureLocationOutcome.NotRequested) {
        val current = mutableState.value
        if (current.liveNote.isStarted || current.isSending || liveWriteJob?.isActive == true) return
        if (text.isBlank() && url == null && current.draft.attachments.isEmpty()) return
        val preset = current.draft.frozenPreset ?: current.presetCollection?.activePreset
        val route = current.draft.routeOverride
        liveWriteJob = viewModelScope.launch {
            mutableState.update { it.copy(liveNote = it.liveNote.copy(localText = text, isWriting = true)) }
            draftSaveJob?.join()
            routeSaveJob?.join()
            val result = runCatching { repository.submit(text, url, locationOutcome) }
                .getOrElse { CaptureSubmitResult.SavedForRetry("unknown", "unexpectedFailure", durablySaved = false) }
            val requestID = when (result) {
                is CaptureSubmitResult.Delivered -> result.requestID
                is CaptureSubmitResult.LimitReached -> result.requestID
                is CaptureSubmitResult.NeedsPermission -> result.requestID
                is CaptureSubmitResult.SavedForRetry -> result.requestID.takeIf { result.durablySaved }
                CaptureSubmitResult.DestinationRequired, is CaptureSubmitResult.InvalidInput -> null
            }
            if (requestID == null) {
                // Not admitted: nothing was queued, the words stay in the local draft.
                val typed = mutableState.value.liveNote.localText
                mutableState.update { it.copy(liveNote = LiveNoteSession(parked = it.liveNote.parked)) }
                updateDraft(typed, url)
                apply(result, acceptNewCapture = false)
                return@launch
            }
            val pending = LiveNotePendingWrite(
                requestID = requestID,
                submittedText = text,
                presetID = preset?.id,
                presetName = preset?.name,
                isAppendTarget = LiveNotePlan.isAppendTarget(preset, route),
                prefersLastOccurrence = LiveNotePlan.prefersLastOccurrence(preset, route),
                plannedPath = LiveNotePlan.plannedPath(preset, route),
            )
            mutableState.update { state ->
                state.copy(
                    liveNote = state.liveNote.copy(pending = pending, isWriting = false),
                    draft = CaptureDraft("", null, System.currentTimeMillis()),
                )
            }
            persistLiveNote()
            val history = runCatching { repository.history() }.getOrDefault(mutableState.value.history)
            mutableState.update { it.copy(history = history) }
            if (result is CaptureSubmitResult.LimitReached) {
                mutableState.update { it.copy(notice = voxNotice("The free Capture limit has been reached. Your capture is saved locally.")) }
            }
            completeFirstWrite(result)
        }
    }

    private suspend fun completeFirstWrite(result: CaptureSubmitResult) {
        val pending = mutableState.value.liveNote.pending ?: return
        when (result) {
            is CaptureSubmitResult.Delivered -> {
                val location = result.noteLocation
                    ?: runCatching { repository.committedNoteLocation(pending.requestID) }.getOrNull()
                if (location == null) {
                    // Delivered, but the file it wrote is unknown: keep the words, end the session.
                    releaseLiveNote(showToast = true, awaitWrite = false)
                    return
                }
                bindPending(pending, location)
                runCatching { repository.activityStats() }.getOrNull()?.let { stats -> mutableState.update { it.copy(activityStats = stats) } }
            }
            is CaptureSubmitResult.NeedsPermission, CaptureSubmitResult.DestinationRequired ->
                mutableState.update { it.copy(liveNote = it.liveNote.copy(isUnreachable = true)) }
            is CaptureSubmitResult.SavedForRetry -> mutableState.update {
                it.copy(liveNote = it.liveNote.copy(isUnreachable = result.reason !in setOf("captureBusy", "leaseLost")))
            }
            is CaptureSubmitResult.LimitReached, is CaptureSubmitResult.InvalidInput -> Unit
        }
    }

    private suspend fun bindPending(pending: LiveNotePendingWrite, location: LiveNoteLocation) {
        when (val read = liveNotes.read(location)) {
            is LiveNoteReadResult.Found -> {
                val localText = mutableState.value.liveNote.localText
                val bound = LiveNoteSync.bindFirstWrite(pending, read.file, localText)
                mutableState.update { state ->
                    state.copy(
                        liveNote = state.liveNote.copy(
                            binding = bound.binding,
                            pending = null,
                            localText = bound.editorText,
                            isUnreachable = false,
                            highlight = bound.entryRange.takeIf { pending.isAppendTarget },
                        ),
                        liveNoteEditor = nextEditor(bound.editorText, bound.entryRange),
                    )
                }
                persistLiveNote()
                if (bound.needsSave) saveLiveNoteNow()
            }
            // Written, but not readable right now: stay pending and bind on the next refresh.
            is LiveNoteReadResult.Unreachable -> mutableState.update { it.copy(liveNote = it.liveNote.copy(isUnreachable = true)) }
            LiveNoteReadResult.Missing -> mutableState.update { it.copy(liveNote = it.liveNote.copy(isUnreachable = true)) }
        }
    }

    /** Editor changes while a note is live: keep them locally at once, write the file after idle. */
    fun updateLiveText(text: String) {
        mutableState.update { it.copy(liveNote = it.liveNote.copy(localText = text)) }
        livePersistJob?.cancel()
        livePersistJob = viewModelScope.launch {
            delay(LIVE_PERSIST_DEBOUNCE_MILLIS)
            persistLiveNote()
        }
        scheduleLiveSave()
    }

    private fun scheduleLiveSave() {
        val session = mutableState.value.liveNote
        if (session.binding == null || session.conflict != null) return
        val now = System.currentTimeMillis()
        val pendingSince = livePendingSince ?: now.also { livePendingSince = it }
        // Idle debounce, but never wait longer than the max delay: dictation rarely pauses.
        val wait = minOf(LIVE_SAVE_DEBOUNCE_MILLIS, (LIVE_SAVE_MAX_WAIT_MILLIS - (now - pendingSince)).coerceAtLeast(0L))
        liveSaveJob?.cancel()
        liveSaveJob = viewModelScope.launch {
            delay(wait)
            // The write itself is never cancelled by later keystrokes: a cancelled in-flight
            // write could land without its new version being recorded and conflict with itself.
            viewModelScope.launch { saveLiveNoteNow() }
        }
    }

    /** Background: write now instead of waiting for the idle debounce. */
    fun flushLiveNote() {
        livePersistJob?.cancel()
        liveSaveJob?.cancel()
        viewModelScope.launch {
            persistLiveNote()
            saveLiveNoteNow()
        }
    }

    private suspend fun saveLiveNoteNow() = liveSaveMutex.withLock {
        livePendingSince = null
        val session = mutableState.value.liveNote
        val binding = session.binding ?: return@withLock
        if (session.conflict != null || !session.hasUnsavedEdits) return@withLock
        mutableState.update { it.copy(liveNote = it.liveNote.copy(isWriting = true)) }
        val outcome = runCatching { LiveNoteSync.save(liveNotes, binding, session.localText) }
            .getOrElse { LiveNoteSyncOutcome.Unreachable }
        applySync(outcome, savedText = session.localText)
    }

    /** Resume: SAF has no change notifications, so look at the file again. */
    fun refreshLiveNote() {
        viewModelScope.launch {
            drainParkedLiveNotes()
            val session = mutableState.value.liveNote
            val pending = session.pending
            if (pending != null) {
                val location = runCatching { repository.committedNoteLocation(pending.requestID) }.getOrNull()
                if (location != null) bindPending(pending, location)
                return@launch
            }
            if (session.binding == null) return@launch
            liveSaveMutex.withLock {
                // Re-read under the lock: a save may have just recorded a newer version.
                val current = mutableState.value.liveNote
                val binding = current.binding ?: return@withLock
                if (current.conflict != null) return@withLock
                mutableState.update { it.copy(liveNote = it.liveNote.copy(isWriting = current.hasUnsavedEdits)) }
                val outcome = runCatching { LiveNoteSync.refresh(liveNotes, binding, current.localText) }
                    .getOrElse { LiveNoteSyncOutcome.Unreachable }
                applySync(outcome, savedText = current.localText)
            }
        }
    }

    private suspend fun applySync(outcome: LiveNoteSyncOutcome, savedText: String) {
        mutableState.update { state ->
            val session = state.liveNote.copy(isWriting = false)
            when (outcome) {
                LiveNoteSyncOutcome.Unchanged -> state.copy(liveNote = session.copy(isUnreachable = false))
                is LiveNoteSyncOutcome.Saved -> state.copy(liveNote = session.copy(binding = outcome.binding, isUnreachable = false, conflict = null))
                is LiveNoteSyncOutcome.Reloaded -> {
                    val binding = outcome.binding
                    // Only replace the editor if nobody typed while the read was in flight.
                    if (session.localText != savedText) state.copy(liveNote = session.copy(binding = binding, isUnreachable = false))
                    else state.copy(
                        liveNote = session.copy(binding = binding, localText = outcome.text, isUnreachable = false, conflict = null, highlight = null),
                        liveNoteEditor = nextEditor(outcome.text, null),
                        liveNoteEvents = (listOf(LiveNoteEvent(System.currentTimeMillis(), LiveNoteEventKind.RELOADED, binding.location.title, binding.location.relativePath)) + state.liveNoteEvents).take(20),
                    )
                }
                is LiveNoteSyncOutcome.Conflicted -> state.copy(liveNote = session.copy(conflict = outcome.conflict, isUnreachable = false))
                LiveNoteSyncOutcome.Unreachable -> state.copy(liveNote = session.copy(isUnreachable = true))
            }
        }
        persistLiveNote()
        // Typing continued while the write was in flight: write again after idle.
        if (outcome is LiveNoteSyncOutcome.Saved && mutableState.value.liveNote.hasUnsavedEdits) scheduleLiveSave()
    }

    fun resolveLiveNoteConflict(choice: LiveNoteConflictChoice) {
        val session = mutableState.value.liveNote
        val binding = session.binding ?: return
        val conflict = session.conflict ?: return
        viewModelScope.launch {
            mutableState.update { it.copy(liveNote = it.liveNote.copy(isWriting = true)) }
            val outcome = liveSaveMutex.withLock { runCatching {
                when (choice) {
                    LiveNoteConflictChoice.USE_THEIRS -> LiveNoteSync.useTheirs(binding, conflict)
                    LiveNoteConflictChoice.KEEP_MINE -> LiveNoteSync.keepMine(liveNotes, binding, conflict)
                    LiveNoteConflictChoice.SAVE_COPY -> LiveNoteSync.saveCopy(liveNotes, binding, conflict)
                }
            }.getOrElse { LiveNoteSyncOutcome.Unreachable } }
            mutableState.update { state ->
                val cleared = state.liveNote.copy(isWriting = false, conflict = null)
                when (outcome) {
                    is LiveNoteSyncOutcome.Reloaded -> state.copy(
                        liveNote = cleared.copy(binding = outcome.binding, localText = outcome.text, highlight = null),
                        liveNoteEditor = nextEditor(outcome.text, null),
                    )
                    is LiveNoteSyncOutcome.Saved -> state.copy(
                        liveNote = cleared.copy(binding = outcome.binding, localText = conflict.mine, isUnreachable = false),
                        liveNoteEvents = if (choice == LiveNoteConflictChoice.SAVE_COPY) {
                            (listOf(LiveNoteEvent(System.currentTimeMillis(), LiveNoteEventKind.SAVED_COPY, outcome.binding.location.title, outcome.binding.location.relativePath)) + state.liveNoteEvents).take(20)
                        } else state.liveNoteEvents,
                        notice = if (choice == LiveNoteConflictChoice.SAVE_COPY) voxNotice("Saved a copy as %@", outcome.binding.location.fileName) else state.notice,
                    )
                    is LiveNoteSyncOutcome.Conflicted -> state.copy(liveNote = cleared.copy(conflict = outcome.conflict))
                    LiveNoteSyncOutcome.Unreachable -> state.copy(liveNote = cleared.copy(conflict = conflict, isUnreachable = true))
                    LiveNoteSyncOutcome.Unchanged -> state.copy(liveNote = cleared)
                }
            }
            persistLiveNote()
        }
    }

    /** New note: write what is pending, release the binding and open a blank composer. */
    fun newLiveNote() {
        val state = mutableState.value
        if (!state.liveNote.isStarted && !state.liveNote.isWriting &&
            (state.draft.text.isNotBlank() || state.draft.url != null || state.draft.attachments.isNotEmpty())) {
            // Nothing written yet (idle debounce not reached): write it, then release.
            startLiveNote(state.draft.text, state.draft.url)
        }
        viewModelScope.launch { releaseLiveNote(showToast = true) }
    }

    /** Files tab back affordance: release the opened file without a toast. */
    fun closeOpenedFile() {
        viewModelScope.launch { releaseLiveNote(showToast = false) }
    }

    private suspend fun releaseLiveNote(showToast: Boolean, awaitWrite: Boolean = true) {
        if (awaitWrite) liveWriteJob?.join()
        livePersistJob?.cancel()
        liveSaveJob?.cancel()
        if (mutableState.value.liveNote.conflict == null) saveLiveNoteNow()
        val release = mutableState.value.liveNote.released()
        runCatching { repository.saveDraft("", null) }
        mutableState.update { state ->
            state.copy(
                liveNote = release.next,
                draft = CaptureDraft("", null, System.currentTimeMillis()),
                liveNoteEditor = nextEditor("", null),
                liveNoteReleased = release.takeIf { showToast && (it.binding != null || it.relativePath != null) },
                liveNoteOpenedFromFiles = false,
            )
        }
        persistLiveNote()
        if (release.next.parked.isNotEmpty()) drainParkedLiveNotes()
    }

    /** Finishes released notes whose last edits were kept on the phone. */
    private suspend fun drainParkedLiveNotes() {
        val parked = mutableState.value.liveNote.parked
        if (parked.isEmpty()) return
        val finished = parked.filter { item ->
            runCatching { finishParked(item) }.getOrDefault(false)
        }.toSet()
        if (finished.isEmpty()) return
        mutableState.update { it.copy(liveNote = it.liveNote.copy(parked = it.liveNote.parked.filterNot(finished::contains))) }
        persistLiveNote()
    }

    private suspend fun finishParked(item: md.vox.android.capturedomain.LiveNoteParked): Boolean {
        val (binding, text) = item.binding?.let { it to item.localText } ?: run {
            val pending = item.pending ?: return true
            val location = repository.committedNoteLocation(pending.requestID) ?: return false
            val file = (liveNotes.read(location) as? LiveNoteReadResult.Found)?.file ?: return false
            val bound = LiveNoteSync.bindFirstWrite(pending, file, item.localText)
            if (!bound.needsSave) return true
            bound.binding to bound.editorText
        }
        return when (val outcome = LiveNoteSync.save(liveNotes, binding, text)) {
            LiveNoteSyncOutcome.Unchanged, is LiveNoteSyncOutcome.Saved, is LiveNoteSyncOutcome.Reloaded -> true
            // Nobody is looking at this note any more: keep both versions rather than choose.
            is LiveNoteSyncOutcome.Conflicted -> LiveNoteSync.saveCopy(liveNotes, binding, outcome.conflict) is LiveNoteSyncOutcome.Saved
            LiveNoteSyncOutcome.Unreachable -> false
        }
    }

    fun dismissLiveNoteToast() {
        mutableState.update { it.copy(liveNoteReleased = null) }
    }

    /** Reopen from the toast: bind the released file again. */
    fun reopenReleasedNote() {
        val binding = mutableState.value.liveNoteReleased?.binding ?: return
        mutableState.update { it.copy(liveNoteReleased = null) }
        openFile(binding.location, binding.presetID, binding.presetName, fromFiles = false)
    }

    /** Opens a vault file in the composer (Files tab, Reopen). The current note is saved first. */
    fun openFile(location: LiveNoteLocation, presetID: String? = null, presetName: String? = null, fromFiles: Boolean = true) {
        viewModelScope.launch {
            val current = mutableState.value.liveNote
            if (current.binding?.location == location) {
                mutableState.update { it.copy(liveNoteOpenedFromFiles = fromFiles || it.liveNoteOpenedFromFiles) }
                refreshLiveNote()
                return@launch
            }
            if (current.isStarted || current.localText.isNotBlank()) releaseLiveNote(showToast = false)
            when (val read = liveNotes.read(location)) {
                is LiveNoteReadResult.Found -> {
                    val binding = LiveNoteBinding(
                        location = location,
                        presetID = presetID,
                        presetName = presetName ?: location.folderSegments.lastOrNull(),
                        requestID = null,
                        isAppendTarget = false,
                        version = read.file.version,
                        savedText = read.file.text,
                    )
                    mutableState.update { state ->
                        state.copy(
                            liveNote = LiveNoteSession(binding = binding, localText = read.file.text, parked = state.liveNote.parked),
                            liveNoteEditor = nextEditor(read.file.text, null, caret = read.file.text.length),
                            liveNoteOpenedFromFiles = fromFiles,
                        )
                    }
                    persistLiveNote()
                }
                LiveNoteReadResult.Missing -> mutableState.update { it.copy(notice = voxNotice("That file is no longer in the folder.")) }
                is LiveNoteReadResult.Unreachable -> mutableState.update { it.copy(notice = voxNotice("The file could not be opened. Reconnect the folder and try again.")) }
            }
        }
    }

    suspend fun listVault(destination: LiveNoteVault, relativeFolder: String, countChildren: Boolean = true): VaultListing =
        vault?.let { browser -> runCatching { browser.list(destination, relativeFolder, countChildren) }.getOrElse { VaultListing.Unreachable("listFailed") } }
            ?: VaultListing.Unreachable("unavailable")

    /**
     * Live preview: a content URI for an embed in the bound note, looked up in the preset's
     * attachments folder, "attachments", the note's folder, the vault root, then by name.
     */
    suspend fun resolveEmbed(target: String): String? {
        val binding = mutableState.value.liveNote.binding ?: return null
        val resolver = media ?: return null
        val presetFolder = mutableState.value.presetCollection?.presets?.firstOrNull { it.id == binding.presetID }?.attachmentsFolder
        val folders = listOfNotNull(presetFolder, "attachments", "Attachments").distinct()
        val candidates = md.vox.android.LivePreview.candidates(binding.location.relativePath, target, folders)
        if (candidates.isEmpty()) return null
        return runCatching {
            resolver.resolveMedia(binding.location.destinationID, binding.location.treeUri, candidates, target.substringAfterLast('/'))
        }.getOrNull()
    }

    /** First non-heading, non-frontmatter line of a file, for folder previews. */
    suspend fun previewFile(location: LiveNoteLocation): String? =
        (runCatching { liveNotes.read(location) }.getOrNull() as? LiveNoteReadResult.Found)?.file?.text?.let(::liveNotePreviewLine)

    /** Attachments added to a bound note go through the pipeline into the same file. */
    private suspend fun attachToBoundNote() {
        val binding = mutableState.value.liveNote.binding ?: return
        val route = runCatching { md.vox.android.capturedomain.CaptureRouteOverride(binding.location.relativePath, md.vox.android.capturedomain.CapturePlacementKind.APPEND).validated() }.getOrNull() ?: return
        saveLiveNoteNow()
        if (mutableState.value.liveNote.hasUnsavedEdits) return
        runCatching { repository.setDraftRouteOverride(route) }.getOrElse { return }
        val result = runCatching { repository.submit("", null) }
            .getOrElse { CaptureSubmitResult.SavedForRetry("unknown", "unexpectedFailure", durablySaved = false) }
        val draft = runCatching { repository.currentDraft() }.getOrDefault(mutableState.value.draft)
        mutableState.update { it.copy(draft = draft) }
        if (result !is CaptureSubmitResult.Delivered) apply(result, acceptNewCapture = false)
        refreshLiveNote()
    }

    private suspend fun restoreLiveNote() {
        val restored = runCatching { repository.liveNoteSession() }.getOrNull() ?: return
        if (!restored.isStarted) {
            if (restored.parked.isNotEmpty()) {
                mutableState.update { it.copy(liveNote = it.liveNote.copy(parked = restored.parked)) }
                drainParkedLiveNotes()
            }
            return
        }
        mutableState.update { state ->
            state.copy(liveNote = restored, liveNoteEditor = nextEditor(restored.localText, restored.highlight, caret = restored.localText.length))
        }
        refreshLiveNote()
    }

    private suspend fun persistLiveNote() {
        val session = mutableState.value.liveNote
        runCatching { repository.saveLiveNoteSession(session) }
    }

    private fun nextEditor(text: String, range: LiveNoteRange?, caret: Int? = null): LiveNoteEditorUpdate {
        editorRevision += 1
        return LiveNoteEditorUpdate(editorRevision, text, range, caret)
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
            val liveSession = state.liveNote.isStarted
            when (result) {
                is CaptureSubmitResult.Delivered -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = deliveredCaptureNotice(result.processingOutcome),
                    acceptedRequestID = acceptedRequestID.takeUnless { liveSession },
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
                    acceptedRequestID = acceptedRequestID.takeUnless { liveSession },
                )
                is CaptureSubmitResult.NeedsPermission -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = voxNotice("Folder access changed. Your capture is saved locally; choose the folder again to continue."),
                    acceptedRequestID = acceptedRequestID.takeUnless { liveSession },
                )
                is CaptureSubmitResult.SavedForRetry -> state.copy(
                    isSending = false,
                    draft = draft,
                    history = history,
                    notice = humanReason(result.reason),
                    acceptedRequestID = acceptedRequestID.takeUnless { liveSession },
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
        const val LIVE_SAVE_DEBOUNCE_MILLIS = 600L
        /** While dictating there may be no idle gap; write at least this often. */
        const val LIVE_SAVE_MAX_WAIT_MILLIS = 2_000L
        const val LIVE_PERSIST_DEBOUNCE_MILLIS = 250L

        fun factory(
            repository: CaptureRepository,
            liveNotes: LiveNoteFileStore = UnavailableLiveNoteStore,
            vault: VaultBrowser? = null,
            media: md.vox.android.capturedomain.VaultMediaResolver? = null,
        ): ViewModelProvider.Factory = object : ViewModelProvider.Factory {
            @Suppress("UNCHECKED_CAST")
            override fun <T : ViewModel> create(modelClass: Class<T>): T = CaptureViewModel(repository, liveNotes, vault, media) as T
        }
    }
}

private fun voxNotice(source: String, vararg arguments: Any): VoxUiText =
    VoxUiText(source, arguments.toList())

internal fun deliveredCaptureNotice(outcome: CaptureTextProcessingOutcome?): md.vox.android.VoxUiText {
    val detail = when (outcome) {
        CaptureTextProcessingOutcome.MODEL_UNAVAILABLE -> voxNotice("Local model unavailable; the original text was kept.")
        CaptureTextProcessingOutcome.MODEL_FAILURE -> voxNotice("Local processing failed; the original text was kept.")
        CaptureTextProcessingOutcome.UNSUPPORTED_CUSTOM_INSTRUCTION -> voxNotice("Unsupported custom instruction")
        CaptureTextProcessingOutcome.SKIPPED_TOO_LARGE -> voxNotice("Skipped because the capture is too large")
        else -> null
    }
    return if (detail == null) voxNotice("Capture sent") else voxNotice("%@ · %@", voxNotice("Capture sent"), detail)
}

internal enum class LiveNoteConflictChoice { USE_THEIRS, KEEP_MINE, SAVE_COPY }

/** Skips YAML frontmatter, headings and blank lines; returns the first line of prose. */
internal fun liveNotePreviewLine(text: String): String? {
    var lines = text.lineSequence()
    if (text.startsWith("---")) {
        val all = text.lines()
        val end = all.drop(1).indexOfFirst { it.trim() == "---" }
        if (end >= 0) lines = all.drop(end + 2).asSequence()
    }
    return lines.map(String::trim)
        .firstOrNull { it.isNotEmpty() && !it.startsWith("#") }
        ?.removePrefix("- [ ] ")?.removePrefix("- [x] ")?.removePrefix("- ")
        ?.take(160)
}

/** Live Notes without a vault file store (previews and tests): every file is unreachable. */
internal object UnavailableLiveNoteStore : LiveNoteFileStore {
    override suspend fun read(location: LiveNoteLocation): LiveNoteReadResult = LiveNoteReadResult.Unreachable("unavailable")
    override suspend fun replace(location: LiveNoteLocation, text: String, expected: md.vox.android.capturedomain.LiveNoteVersion?): LiveNoteWriteResult =
        LiveNoteWriteResult.Unreachable("unavailable")
    override suspend fun createCopy(location: LiveNoteLocation, text: String): LiveNoteCopyResult = LiveNoteCopyResult.Unreachable("unavailable")
}
