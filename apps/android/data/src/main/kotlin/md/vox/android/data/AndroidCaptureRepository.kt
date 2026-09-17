package md.vox.android.data

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CapturePresetEmoji
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CaptureAttachment
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.capturedomain.normalized
import md.vox.android.capturedomain.CaptureDrainSummary
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureHistoryDetail
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CaptureMetadataScope
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CaptureRollingPeriod
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CaptureMissingHeadingBehavior
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureProcessingScope
import md.vox.android.capturedomain.CapturePresetLocationPolicy
import md.vox.android.capturedomain.CaptureLocationPrecision
import md.vox.android.capturedomain.CaptureLocationUnavailableBehavior
import md.vox.android.capturedomain.CaptureLocationOutputMode
import md.vox.android.capturedomain.CaptureLocationOutcome
import md.vox.android.capturedomain.CaptureLocationLabelLookupClass
import md.vox.android.capturedomain.CaptureLocationLabelOutcome
import md.vox.android.capturedomain.CaptureLocationField
import md.vox.android.capturedomain.CaptureLocationStructuredField
import md.vox.android.capturedomain.DEFAULT_CAPTURE_LOCATION_FIELDS
import md.vox.android.capturedomain.CURRENT_LOCATION_LABEL_CONSENT_VERSION
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureExportFileFormat
import md.vox.android.capturedomain.CaptureExportFileMode
import md.vox.android.capturedomain.CaptureExportYAMLProperty
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.capturedomain.CaptureMeteringPolicy
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.resolvingEntryTemplate
import md.vox.android.capturedomain.CaptureRepository
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureSubmitResult
import md.vox.android.capturedomain.ActivityStats
import md.vox.android.capturedomain.CompletedRecordingActivity
import md.vox.android.capturedomain.CommitOutcome
import md.vox.android.capturedomain.EnqueueResult
import md.vox.android.capturedomain.JournalCode
import md.vox.android.capturedomain.JournalEvent
import md.vox.android.capturedomain.JournalMutationCommand
import md.vox.android.capturedomain.JournalMutationResult
import md.vox.android.capturedomain.LeasePlan
import md.vox.android.capturedomain.LocalCaptureTextProcessor
import md.vox.android.capturedomain.VaultDestination
import md.vox.android.corebridge.CoreBridge
import java.net.URI
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Production M3 repository: durable enqueue → Rust materialization → verified SAF commit. */
class AndroidCaptureRepository(
    context: Context,
    private val bridge: CoreBridge,
    private val clock: () -> Long = System::currentTimeMillis,
    private val hasUnlimitedAccess: () -> Boolean = { false },
    private val generateImageAltText: suspend (ByteArray, String) -> String? = { _, _ -> null },
) : CaptureRepository {
    private val appContext = context.applicationContext
    private val database = CaptureDatabase.create(appContext)
    private val index = RoomCaptureIndex(database)
    private val store = DurableCapturePackageStore(appContext.noBackupFilesDir, index)
    private val coordination = CaptureDurabilityCoordinator(store, RoomCaptureCoordination(database))
    private val quota = RoomQuotaLedger(database)
    private val activity = RoomActivityStatsLedger(database)
    private val completions = RoomCaptureCompletionLedger(database)
    private val completionCompactor = CompletedCaptureCompactor(
        store = store,
        quota = quota,
        activity = activity,
        completions = completions,
        buildInfo = bridge::buildInfo,
        rendererVersion = RENDERER_REVISION,
        profileID = PROFILE_ID,
    )
    private val draftAssetDirectory = File(appContext.noBackupFilesDir, "vox-draft-assets")
    private val processingAuditStore = CaptureProcessingAuditStore(File(appContext.noBackupFilesDir, "capture-processing"))
    private val draftAttachmentMutex = Mutex()
    private val preferences: DataStore<Preferences> = PreferenceDataStoreFactory.create(
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
        produceFile = { appContext.preferencesDataStoreFile("capture-destination.preferences_pb") },
    )

    override suspend fun currentDestination(): CaptureDestination? = withContext(Dispatchers.IO) {
        destinationFrom(preferences.data.first())
    }

    override suspend fun saveDestination(treeUri: String, displayName: String): CaptureDestination = withContext(Dispatchers.IO) {
        val parsed = Uri.parse(treeUri)
        require(parsed.scheme == "content" && treeUri.toByteArray().size in 1..2_048) { "invalidDestination" }
        val existing = destinationFrom(preferences.data.first())
        val destination = CaptureDestination(
            id = existing?.id ?: UUID.randomUUID().toString().lowercase(),
            displayName = displayName.trim().ifEmpty { "Markdown folder" }.take(128),
            treeUri = treeUri,
        )
        preferences.edit {
            it[destinationIDKey] = destination.id
            it[destinationNameKey] = destination.displayName
            it[destinationTreeKey] = destination.treeUri
        }
        destination
    }

    override suspend fun currentDraft(): CaptureDraft = withContext(Dispatchers.IO) {
        draftFrom(preferences.data.first())
    }

    override suspend fun saveDraft(text: String, url: String?, captureSource: String): CaptureDraft = withContext(Dispatchers.IO) {
        require(text.length <= MAX_TEXT_CHARACTERS) { "draftTextTooLarge" }
        require(captureSource in CAPTURE_SOURCES) { "invalidCaptureSource" }
        val normalizedURL = url?.trim()?.takeIf(String::isNotEmpty)
        require(normalizedURL == null || (normalizedURL.length <= MAX_URL_CHARACTERS && isHttpURL(normalizedURL))) { "invalidDraftURL" }
        val present = draftFrom(preferences.data.first())
        val draft = CaptureDraft(
            text = text,
            url = normalizedURL,
            updatedAtEpochMillis = clock(),
            captureSource = captureSource,
            attachments = present.attachments,
            originRecordingID = present.originRecordingID,
            frozenPreset = present.frozenPreset,
            entryTemplateIDOverride = present.entryTemplateIDOverride,
        )
        preferences.edit { values ->
            if (draft.text.isEmpty()) values.remove(draftTextKey) else values[draftTextKey] = draft.text
            val draftURL = draft.url
            if (draftURL == null) values.remove(draftURLKey) else values[draftURLKey] = draftURL
            values[draftUpdatedAtKey] = draft.updatedAtEpochMillis
            values[draftSourceKey] = draft.captureSource
        }
        draft
    }

    override suspend fun addDraftAttachment(
        contentUri: String,
        displayName: String?,
        mediaType: String?,
        includeInMarkdown: Boolean,
    ): CaptureDraft = importDraftAttachment(contentUri, displayName, mediaType, includeInMarkdown)

    override suspend fun prepareVoiceDraft(
        text: String,
        url: String?,
        originRecordingID: String,
        audioContentUri: String?,
        audioDisplayName: String?,
        frozenPreset: CapturePreset?,
    ): CaptureDraft = withContext(Dispatchers.IO) {
        require(UUID_PATTERN.matches(originRecordingID)) { "invalidOriginRecordingID" }
        require(text.length <= MAX_TEXT_CHARACTERS) { "draftTextTooLarge" }
        val normalizedURL = url?.trim()?.takeIf(String::isNotEmpty)
        require(normalizedURL == null || (normalizedURL.length <= MAX_URL_CHARACTERS && isHttpURL(normalizedURL))) { "invalidDraftURL" }
        val preset = frozenPreset?.let(::normalizePreset)
            ?: presetCollectionFrom(preferences.data.first()).activePreset
        val current = draftFrom(preferences.data.first())
        val prepared = CaptureDraft(
            text = text,
            url = normalizedURL,
            updatedAtEpochMillis = clock(),
            captureSource = "app",
            attachments = current.attachments,
            originRecordingID = originRecordingID,
            frozenPreset = preset,
        )
        preferences.edit { values ->
            if (prepared.text.isEmpty()) values.remove(draftTextKey) else values[draftTextKey] = prepared.text
            val preparedURL = prepared.url
            if (preparedURL == null) values.remove(draftURLKey) else values[draftURLKey] = preparedURL
            values[draftUpdatedAtKey] = prepared.updatedAtEpochMillis
            values[draftSourceKey] = prepared.captureSource
            values[draftOriginRecordingIDKey] = originRecordingID
            values[draftFrozenPresetKey] = encodePresets(listOf(preset))
        }
        if (!recordingAudioArtifactPolicy(preset).retainsSourceAudio) {
            prepared
        } else {
            requireNotNull(audioContentUri) { "audioPreparationFailed" }
            importDraftAttachment(
                audioContentUri,
                audioDisplayName ?: "Recording.wav",
                "audio/wav",
                includeInMarkdown = preset.embedAudioInMarkdown,
            )
        }
    }

    private suspend fun importDraftAttachment(
        contentUri: String,
        displayName: String?,
        mediaType: String?,
        includeInMarkdown: Boolean,
    ): CaptureDraft = withContext(Dispatchers.IO) {
        draftAttachmentMutex.withLock {
        val uri = Uri.parse(contentUri)
        require(uri.scheme == "content") { "invalidAttachmentUri" }
        val currentPreferences = preferences.data.first()
        val current = draftFrom(currentPreferences)
        require(current.attachments.size < MAX_DRAFT_ATTACHMENTS) { "attachmentLimit" }

        val resolver = appContext.contentResolver
        val providerName = displayName?.takeIf(String::isNotBlank) ?: resolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        }
        val safeDisplayName = uniqueDisplayName(
            sanitizeAttachmentName(providerName.orEmpty().ifBlank { "attachment" }),
            current.attachments.map(CaptureAttachment::displayName).toSet(),
        )
        val id = UUID.randomUUID().toString().lowercase()
        val vaultName = "$id-${safeDisplayName}".take(255)
        val normalizedMediaType = (mediaType ?: resolver.getType(uri) ?: "application/octet-stream")
            .trim().take(127).takeIf { it.isNotEmpty() && '\n' !in it && '\r' !in it }
            ?: "application/octet-stream"

        if (!draftAssetDirectory.exists() && !draftAssetDirectory.mkdir() && !draftAssetDirectory.isDirectory) {
            error("draftAssetDirectory")
        }
        val temporary = File(draftAssetDirectory, ".tmp-$id")
        val target = File(draftAssetDirectory, id)
        var byteCount = 0L
        val digest = MessageDigest.getInstance("SHA-256")
        try {
            resolver.openInputStream(uri)?.use { input ->
                FileOutputStream(temporary).use { output ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count == 0) continue
                        byteCount += count
                        require(byteCount <= MAX_DRAFT_ATTACHMENT_BYTES) { "attachmentTooLarge" }
                        digest.update(buffer, 0, count)
                        output.write(buffer, 0, count)
                    }
                    output.flush()
                    output.fd.sync()
                }
            } ?: error("attachmentUnavailable")
            require(byteCount > 0) { "attachmentEmpty" }
            Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
            val attachment = CaptureAttachment(
                id = id,
                displayName = safeDisplayName,
                vaultFileName = vaultName,
                mediaType = normalizedMediaType,
                byteCount = byteCount,
                sha256 = digest.digest().joinToString("") { "%02x".format(it) },
                includeInMarkdown = includeInMarkdown,
            )
            val updated = current.attachments + attachment
            val updatedAt = clock()
            preferences.edit {
                it[draftAttachmentsKey] = encodeDraftAttachments(updated)
                it[draftUpdatedAtKey] = updatedAt
            }
            current.copy(attachments = updated, updatedAtEpochMillis = updatedAt)
        } catch (error: Throwable) {
            temporary.delete()
            if (target.exists() && current.attachments.none { it.id == id }) target.delete()
            throw error
        }
        }
    }

    override suspend fun removeDraftAttachment(attachmentID: String): CaptureDraft = withContext(Dispatchers.IO) {
        draftAttachmentMutex.withLock {
        require(UUID_PATTERN.matches(attachmentID)) { "invalidAttachmentID" }
        val current = draftFrom(preferences.data.first())
        val attachment = current.attachments.firstOrNull { it.id == attachmentID } ?: return@withLock current
        val target = File(draftAssetDirectory, attachment.id)
        if (target.exists() && !target.delete()) error("attachmentDelete")
        val updated = current.attachments.filterNot { it.id == attachmentID }
        val updatedAt = clock()
        preferences.edit { values ->
            if (updated.isEmpty()) values.remove(draftAttachmentsKey)
            else values[draftAttachmentsKey] = encodeDraftAttachments(updated)
            values[draftUpdatedAtKey] = updatedAt
        }
        current.copy(attachments = updated, updatedAtEpochMillis = updatedAt)
        }
    }

    override suspend fun captureBarConfiguration(): CaptureBarConfiguration = withContext(Dispatchers.IO) {
        captureBarFrom(preferences.data.first())
    }

    override suspend fun saveCaptureBarConfiguration(
        configuration: CaptureBarConfiguration,
    ): CaptureBarConfiguration = withContext(Dispatchers.IO) {
        val normalized = configuration.normalized()
        preferences.edit { it[captureBarKey] = encodeCaptureBarConfiguration(normalized) }
        normalized
    }

    override suspend fun presetQuickAccessRailExpanded(): Boolean = withContext(Dispatchers.IO) {
        preferences.data.first()[presetRailExpandedKey] ?: false
    }

    override suspend fun setPresetQuickAccessRailExpanded(expanded: Boolean): Unit = withContext(Dispatchers.IO) {
        preferences.edit { it[presetRailExpandedKey] = expanded }
    }

    override suspend fun capturePresets(): CapturePresetCollection = withContext(Dispatchers.IO) {
        presetCollectionFrom(preferences.data.first())
    }

    override suspend fun selectCapturePreset(presetID: String): CapturePresetCollection = withContext(Dispatchers.IO) {
        val current = presetCollectionFrom(preferences.data.first())
        require(current.presets.any { it.id == presetID && it.isEnabled }) { "unknownOrDisabledPreset" }
        preferences.edit { it[activePresetIDKey] = presetID }
        current.copy(activePresetID = presetID)
    }

    override suspend fun saveCapturePreset(preset: CapturePreset): CapturePresetCollection = withContext(Dispatchers.IO) {
        val current = presetCollectionFrom(preferences.data.first())
        val existing = current.presets.firstOrNull { it.id == preset.id }
        val normalized = normalizePreset(
            preset.resolvingEntryTemplate(entryTemplatesFrom(preferences.data.first())),
        ).copy(revision = (existing?.revision ?: 0) + 1)
        val updated = if (existing == null) {
            require(current.presets.size < MAX_PRESETS) { "presetLimit" }
            current.presets + normalized
        } else {
            current.presets.map { if (it.id == normalized.id) normalized else it }
        }
        val active = current.activePresetID.takeIf { id -> updated.any { it.id == id && it.isEnabled } }
            ?: updated.firstOrNull { it.isEnabled }?.id
            ?: DEFAULT_PRESET_ID
        preferences.edit {
            it[presetsKey] = encodePresets(updated)
            it[activePresetIDKey] = active
        }
        CapturePresetCollection(active, updated)
    }

    override suspend fun deleteCapturePreset(presetID: String): CapturePresetCollection = withContext(Dispatchers.IO) {
        val current = presetCollectionFrom(preferences.data.first())
        require(presetID != DEFAULT_PRESET_ID) { "defaultPresetRequired" }
        require(current.presets.any { it.id == presetID }) { "unknownPreset" }
        val updated = current.presets.filterNot { it.id == presetID }
        val active = if (current.activePresetID == presetID) DEFAULT_PRESET_ID else current.activePresetID
        preferences.edit {
            it[presetsKey] = encodePresets(updated)
            it[activePresetIDKey] = active
        }
        CapturePresetCollection(active, updated)
    }

    override suspend fun entryTemplates(): List<CaptureEntryTemplate> = withContext(Dispatchers.IO) {
        entryTemplatesFrom(preferences.data.first())
    }

    override suspend fun saveEntryTemplate(template: CaptureEntryTemplate): List<CaptureEntryTemplate> = withContext(Dispatchers.IO) {
        val values = preferences.data.first()
        val current = entryTemplatesFrom(values)
        val normalized = normalizeEntryTemplate(template)
        val existing = current.any { it.id == normalized.id }
        if (!existing) require(current.size < MAX_ENTRY_TEMPLATES) { "entryTemplateLimit" }
        val updated = if (existing) current.map { if (it.id == normalized.id) normalized else it } else current + normalized
        val presets = presetCollectionFrom(values).presets.map { preset ->
            if (preset.entryTemplateID == normalized.id) {
                preset.copy(
                    revision = preset.revision + 1,
                    entryPrefix = normalized.entryPrefix,
                    entrySuffix = normalized.entrySuffix,
                )
            } else preset
        }
        preferences.edit {
            it[entryTemplatesKey] = encodeEntryTemplates(updated)
            it[presetsKey] = encodePresets(presets)
        }
        updated
    }

    override suspend fun deleteEntryTemplate(templateID: String): List<CaptureEntryTemplate> = withContext(Dispatchers.IO) {
        require(PRESET_UUID_PATTERN.matches(templateID)) { "invalidEntryTemplateID" }
        val values = preferences.data.first()
        val current = entryTemplatesFrom(values)
        require(current.any { it.id == templateID }) { "unknownEntryTemplate" }
        val updated = current.filterNot { it.id == templateID }
        // Bound presets keep their last-known inline prefix/suffix snapshot.
        val presets = presetCollectionFrom(values).presets.map { preset ->
            if (preset.entryTemplateID == templateID) {
                preset.copy(revision = preset.revision + 1, entryTemplateID = null)
            } else preset
        }
        preferences.edit {
            if (updated.isEmpty()) it.remove(entryTemplatesKey) else it[entryTemplatesKey] = encodeEntryTemplates(updated)
            it[presetsKey] = encodePresets(presets)
            if (values[draftEntryTemplateIDKey] == templateID) it.remove(draftEntryTemplateIDKey)
        }
        updated
    }

    override suspend fun setDraftEntryTemplateOverride(templateID: String?): CaptureDraft = withContext(Dispatchers.IO) {
        val values = preferences.data.first()
        if (templateID != null) {
            require(PRESET_UUID_PATTERN.matches(templateID)) { "invalidEntryTemplateID" }
            require(entryTemplatesFrom(values).any { it.id == templateID }) { "unknownEntryTemplate" }
        }
        preferences.edit {
            if (templateID == null) it.remove(draftEntryTemplateIDKey) else it[draftEntryTemplateIDKey] = templateID
        }
        draftFrom(values).copy(entryTemplateIDOverride = templateID)
    }

    override suspend fun submit(
        text: String,
        url: String?,
        locationOutcome: CaptureLocationOutcome,
    ): CaptureSubmitResult = withContext(Dispatchers.IO) {
        val currentPreferences = preferences.data.first()
        val draft = draftFrom(currentPreferences).copy(text = text, url = url)
        submitDraftOnWorker(
            draft = draft,
            locationOutcome = locationOutcome,
            requestID = UUID.randomUUID().toString().lowercase(),
            clearPersistedDraft = true,
        )
    }

    override suspend fun submitRecording(
        text: String,
        url: String?,
        originRecordingID: String,
        audioContentUri: String?,
        audioDisplayName: String?,
        frozenPreset: CapturePreset,
        captureSource: String,
        locationOutcome: CaptureLocationOutcome,
    ): CaptureSubmitResult = withContext(Dispatchers.IO) {
        if (!UUID_PATTERN.matches(originRecordingID) || captureSource !in setOf("app", "watch", "wear")) {
            return@withContext CaptureSubmitResult.InvalidInput("The recording identity or source is invalid.")
        }
        if (store.loadJournal(originRecordingID) != null) return@withContext retryOnWorker(originRecordingID)
        val preset = runCatching { normalizePreset(frozenPreset) }.getOrElse {
            return@withContext CaptureSubmitResult.InvalidInput("The frozen recording preset is invalid.")
        }
        val audioPolicy = recordingAudioArtifactPolicy(preset)
        val preparedAssets = if (!audioPolicy.retainsSourceAudio) {
            emptyList()
        } else {
            val contentUri = audioContentUri ?: return@withContext CaptureSubmitResult.SavedForRetry(
                originRecordingID,
                "audioPreparationFailed",
                durablySaved = false,
            )
            runCatching {
                listOf(prepareRecordingAsset(contentUri, audioDisplayName, audioPolicy.includesMarkdownReference))
            }.getOrElse {
                return@withContext CaptureSubmitResult.SavedForRetry(
                    originRecordingID,
                    "audioPreparationFailed",
                    durablySaved = false,
                )
            }
        }
        val draft = CaptureDraft(
            text = text,
            url = url,
            updatedAtEpochMillis = clock(),
            captureSource = captureSource,
            attachments = preparedAssets.map(PreparedRecordingAsset::attachment),
            originRecordingID = originRecordingID,
            frozenPreset = preset,
        )
        submitDraftOnWorker(
            draft = draft,
            locationOutcome = locationOutcome,
            requestID = originRecordingID,
            clearPersistedDraft = false,
            suppliedAssets = preparedAssets.map(PreparedRecordingAsset::durableInput),
        )
    }

    private suspend fun submitDraftOnWorker(
        draft: CaptureDraft,
        locationOutcome: CaptureLocationOutcome,
        requestID: String,
        clearPersistedDraft: Boolean,
        suppliedAssets: List<DurableAssetInput>? = null,
    ): CaptureSubmitResult {
        if (completions.read(requestID) != null) {
            if (clearPersistedDraft) clearDraftOnWorker()
            return CaptureSubmitResult.Delivered(requestID)
        }
        val destination = currentDestinationOnWorker() ?: return CaptureSubmitResult.DestinationRequired
        val normalizedText = draft.text.trimEnd()
        val normalizedURL = draft.url?.trim()?.takeIf(String::isNotEmpty)
        if (normalizedText.length > MAX_TEXT_CHARACTERS) {
            return CaptureSubmitResult.InvalidInput("Capture text must be 65,536 characters or fewer.")
        }
        if (normalizedText.isBlank() && normalizedURL == null && draft.attachments.isEmpty()) {
            return CaptureSubmitResult.InvalidInput("Write something or add a link before sending.")
        }
        if (normalizedURL != null && !isHttpURL(normalizedURL)) {
            return CaptureSubmitResult.InvalidInput("Enter a complete http:// or https:// link.")
        }

        val currentPreferences = preferences.data.first()
        val selectedPreset = (draft.frozenPreset ?: presetCollectionFrom(currentPreferences).activePreset)
            .resolvingEntryTemplate(entryTemplatesFrom(currentPreferences), draft.entryTemplateIDOverride)
        val preset = if (draft.originRecordingID != null) {
            val audioPolicy = recordingAudioArtifactPolicy(selectedPreset)
            selectedPreset.copy(attachmentsFolder = audioPolicy.artifactFolder)
        } else selectedPreset
        val captureSource = draft.captureSource
        val processingResult = LocalCaptureTextProcessor.process(
            originalText = normalizedText,
            preset = preset,
            isVoiceCapture = draft.originRecordingID != null,
        )
        if (processingResult != null && !processingAuditStore.save(
                requestID = requestID,
                createdAtEpochMillis = clock(),
                presetID = preset.id,
                presetRevision = preset.revision,
                originRecordingID = draft.originRecordingID,
                result = processingResult,
            )
        ) {
            return CaptureSubmitResult.SavedForRetry(
                requestID = requestID,
                reason = "processingAuditPersistence",
                durablySaved = false,
            )
        }
        val packagedAssets = suppliedAssets ?: runCatching { durableInputsFor(draft.attachments) }.getOrElse {
            processingAuditStore.delete(requestID)
            return CaptureSubmitResult.InvalidInput("One or more attachments are no longer available. Remove them and add them again.")
        }
        val imageDescriptions = if (preset.generateImageAltText) {
            draft.attachments.zip(packagedAssets).associate { (attachment, asset) ->
                attachment.id to if (attachment.isImage) {
                    runCatching { generateImageAltText(asset.bytes, attachment.mediaType) }.getOrNull()
                } else null
            }
        } else emptyMap()
        val requestText = composeCaptureRequestText(
            body = processingResult?.processedText ?: normalizedText,
            attachments = draft.attachments,
            preset = preset,
            imageDescriptions = imageDescriptions,
        )
        if (requestText.length > MAX_TEXT_CHARACTERS) {
            processingAuditStore.delete(requestID)
            return CaptureSubmitResult.InvalidInput("This capture is too large after adding attachment links. Shorten the text and try again.")
        }
        val requestBytes = requestBytes(
            requestID,
            requestText,
            normalizedURL,
            clock(),
            preset,
            captureSource,
            locationOutcome,
            draft.originRecordingID,
            draft.attachments,
        )
        when (val enqueued = store.enqueue(requestBytes, clock(), packagedAssets)) {
            is EnqueueResult.SavedLocally -> Unit
            is EnqueueResult.CorrelationConflict -> {
                processingAuditStore.delete(requestID)
                return CaptureSubmitResult.SavedForRetry(requestID, "correlationConflict", durablySaved = false)
            }
            is EnqueueResult.DurabilityFailure -> {
                processingAuditStore.delete(requestID)
                return CaptureSubmitResult.SavedForRetry(requestID, enqueued.coarseCode, durablySaved = false)
            }
            is EnqueueResult.ExistingPackageCorrupt -> {
                processingAuditStore.delete(requestID)
                return CaptureSubmitResult.SavedForRetry(requestID, enqueued.coarseCode, durablySaved = false)
            }
            is EnqueueResult.IndexFailure -> return CaptureSubmitResult.SavedForRetry(requestID, enqueued.coarseCode)
        }
        if (clearPersistedDraft) clearDraftOnWorker()

        quota.initializeInstallation(UUID.randomUUID().toString().lowercase(), clock())
        when (val result = quota.reserve(
            requestID,
            UUID.randomUUID().toString().lowercase(),
            clock(),
            chargeFreeQuota = CaptureMeteringPolicy.chargesFreeCaptureAllowance(
                originRecordingID = draft.originRecordingID,
                hasUnlimitedAccess = hasUnlimitedAccess(),
            ),
        )) {
            is QuotaReservationResult.Reserved, is QuotaReservationResult.Existing -> Unit
            QuotaReservationResult.AlreadyCommitted -> return CaptureSubmitResult.Delivered(requestID)
            QuotaReservationResult.LimitReached -> return CaptureSubmitResult.LimitReached(requestID)
            QuotaReservationResult.InvalidInput -> return CaptureSubmitResult.SavedForRetry(requestID, "quotaReservation")
        }
        return drive(requestID, destination)
    }

    override suspend fun retry(requestID: String): CaptureSubmitResult = withContext(Dispatchers.IO) {
        retryOnWorker(requestID)
    }

    override suspend fun reconcile(): List<CaptureHistoryItem> = withContext(Dispatchers.IO) {
        store.reconcile()
        compactCompletedPackages()
        historyOnWorker()
    }

    override suspend fun history(): List<CaptureHistoryItem> = withContext(Dispatchers.IO) { historyOnWorker() }

    override suspend fun historyDetail(requestID: String): CaptureHistoryDetail? = withContext(Dispatchers.IO) {
        historyDetailOnWorker(requestID)
    }

    override suspend fun deleteCompletedHistory(requestIDs: Set<String>): Int = withContext(Dispatchers.IO) {
        requestIDs.asSequence()
            .filter(UUID_PATTERN::matches)
            .distinct()
            .take(1_024)
            .count { requestID ->
                when (completionCompactor.compact(requestID)) {
                    CompletionCompactionResult.Compacted,
                    CompletionCompactionResult.AlreadyCompacted,
                    -> completions.delete(requestID).also { removed ->
                        if (removed) processingAuditStore.delete(requestID)
                    }
                    is CompletionCompactionResult.Deferred -> false
                }
            }
    }

    override suspend fun activityStats(): ActivityStats = withContext(Dispatchers.IO) {
        backfillCaptureActivity()
        activity.snapshot(clock())
    }

    override suspend fun recordCompletedRecordings(recordings: List<CompletedRecordingActivity>): ActivityStats = withContext(Dispatchers.IO) {
        recordings.take(1_024).forEach { recording ->
            activity.recordRecording(recording.sessionID, recording.completedAtEpochMillis, recording.durationMillis)
        }
        activity.snapshot(clock())
    }

    override suspend fun drainPending(maxItems: Int): CaptureDrainSummary = withContext(Dispatchers.IO) {
        require(maxItems in 1..MAX_DRAIN_ITEMS) { "invalidDrainLimit" }
        store.reconcile()
        val pending = historyOnWorker().asSequence()
            .filter { it.state.canResumeAutomatically() }
            .take(maxItems)
            .toList()
        var delivered = 0
        var retryable = 0
        var needsPermission = 0
        var blocked = 0
        pending.forEach { item ->
            when (retryOnWorker(item.requestID)) {
                is CaptureSubmitResult.Delivered -> delivered += 1
                is CaptureSubmitResult.NeedsPermission, CaptureSubmitResult.DestinationRequired -> needsPermission += 1
                is CaptureSubmitResult.SavedForRetry -> retryable += 1
                is CaptureSubmitResult.InvalidInput, is CaptureSubmitResult.LimitReached -> blocked += 1
            }
        }
        CaptureDrainSummary(pending.size, delivered, retryable, needsPermission, blocked)
    }

    private fun CaptureState.canResumeAutomatically(): Boolean = when (this) {
        CaptureState.QUEUED,
        CaptureState.PREPARING,
        CaptureState.MATERIALIZED,
        CaptureState.COMMITTING,
        CaptureState.UNKNOWN_OUTCOME,
        CaptureState.RETRYABLE_FAILURE,
        -> true
        CaptureState.NEEDS_PERMISSION,
        CaptureState.NEEDS_USER_ACTION,
        CaptureState.COMPLETED,
        CaptureState.PERMANENT_FAILURE,
        CaptureState.DISCARDED,
        -> false
    }

    private suspend fun retryOnWorker(requestID: String): CaptureSubmitResult {
        if (completions.read(requestID) != null) return CaptureSubmitResult.Delivered(requestID)
        val destination = currentDestinationOnWorker() ?: return CaptureSubmitResult.DestinationRequired
        val snapshot = store.loadJournal(requestID) ?: return CaptureSubmitResult.InvalidInput("Capture is no longer available.")
        if (snapshot.state == CaptureState.COMPLETED) {
            compactCompletedPackage(requestID)
            return CaptureSubmitResult.Delivered(requestID)
        }
        val admitted = store.loadRequestBytes(requestID)?.let { bytes ->
            runCatching { CapturePackageCodec.decodeHistoricalRequest(bytes) }.getOrNull()
        } ?: return CaptureSubmitResult.SavedForRetry(requestID, "requestUnavailable")
        quota.initializeInstallation(UUID.randomUUID().toString().lowercase(), clock())
        when (val result = quota.reserve(
            requestID,
            UUID.randomUUID().toString().lowercase(),
            clock(),
            chargeFreeQuota = CaptureMeteringPolicy.chargesFreeCaptureAllowance(
                originRecordingID = admitted.originRecordingID,
                hasUnlimitedAccess = hasUnlimitedAccess(),
            ),
        )) {
            is QuotaReservationResult.Reserved, is QuotaReservationResult.Existing -> Unit
            QuotaReservationResult.AlreadyCommitted -> return CaptureSubmitResult.Delivered(requestID)
            QuotaReservationResult.LimitReached -> return CaptureSubmitResult.LimitReached(requestID)
            QuotaReservationResult.InvalidInput -> return CaptureSubmitResult.SavedForRetry(requestID, "quotaReservation")
        }
        return drive(requestID, destination)
    }

    private fun drive(
        requestID: String,
        selectedDestination: CaptureDestination,
    ): CaptureSubmitResult {
        val leaseToken = UUID.randomUUID().toString().lowercase()
        val lease = coordination.acquire(requestID, leaseToken, clock(), LEASE_DURATION_MILLIS)
        if (lease !is LeasePlan.Grant && lease !is LeasePlan.Current) {
            return CaptureSubmitResult.SavedForRetry(requestID, "captureBusy")
        }
        val destination = VaultDestination(selectedDestination.id, selectedDestination.treeUri)
        val gateway = AndroidSafDocumentsGateway(appContext)
        val vaultObservations = SafCandidateOccupancy(gateway, destination)
        val materializer = CoreMaterializationCoordinator(
            bridge = bridge,
            store = store,
            coordinator = coordination,
            occupancy = vaultObservations,
            existingNotes = vaultObservations,
            destination = destination,
            clock = clock,
        )
        val executor = SafVaultCommitExecutor(
            store = store,
            coordinator = coordination,
            gateway = gateway,
            destination = destination,
            buildInfo = bridge::buildInfo,
            clock = clock,
        )

        try {
            repeat(MAX_DRIVE_STEPS) {
                val snapshot = store.loadJournal(requestID)
                    ?: return CaptureSubmitResult.SavedForRetry(requestID, "packageMissing")
                when (snapshot.state) {
                    CaptureState.QUEUED, CaptureState.RETRYABLE_FAILURE -> {
                        val started = append(
                            requestID,
                            leaseToken,
                            snapshot.revision,
                            JournalEvent(
                                revision = snapshot.revision + 1,
                                fromState = snapshot.state,
                                state = CaptureState.PREPARING,
                                code = JournalCode.PREPARATION_STARTED,
                                occurredAtEpochMillis = clock(),
                            ),
                        )
                        if (!started) return CaptureSubmitResult.SavedForRetry(requestID, "preparationStart")
                    }

                    CaptureState.PREPARING -> when (val result = materializer.materialize(requestID, leaseToken, snapshot.revision)) {
                        is CoreMaterializationCoordinator.MaterializationResult.Materialized -> Unit
                        CoreMaterializationCoordinator.MaterializationResult.LeaseLost ->
                            return CaptureSubmitResult.SavedForRetry(requestID, "leaseLost")
                        is CoreMaterializationCoordinator.MaterializationResult.Retryable -> {
                            appendRetryableFailure(requestID, leaseToken, result.coarseCode)
                            return CaptureSubmitResult.SavedForRetry(requestID, result.coarseCode)
                        }
                    }

                    CaptureState.MATERIALIZED, CaptureState.COMMITTING, CaptureState.UNKNOWN_OUTCOME -> when (val result = executor.execute(requestID, leaseToken)) {
                        is ExecutorOutcome.Err -> return CaptureSubmitResult.SavedForRetry(requestID, result.code)
                        ExecutorOutcome.LeaseLost -> return CaptureSubmitResult.SavedForRetry(requestID, "leaseLost")
                        is ExecutorOutcome.Ok -> when (val outcome = result.value) {
                            is CommitOutcome.VerifiedCommitted -> {
                                compactCompletedPackage(requestID)
                                return CaptureSubmitResult.Delivered(requestID)
                            }
                            CommitOutcome.PermissionLost -> return CaptureSubmitResult.NeedsPermission(requestID)
                            CommitOutcome.Ambiguous -> return CaptureSubmitResult.SavedForRetry(requestID, "commitOutcomeUnknown")
                            CommitOutcome.ProvedNotCommitted -> Unit
                            CommitOutcome.StaleOccupancy -> {
                                val rematerialize = append(
                                    requestID,
                                    leaseToken,
                                    snapshot.revision,
                                    JournalEvent(
                                        revision = snapshot.revision + 1,
                                        fromState = CaptureState.MATERIALIZED,
                                        state = CaptureState.PREPARING,
                                        code = JournalCode.PREPARATION_STARTED,
                                        occurredAtEpochMillis = clock(),
                                    ),
                                )
                                if (!rematerialize) return CaptureSubmitResult.SavedForRetry(requestID, "staleOccupancy")
                            }
                        }
                    }

                    CaptureState.NEEDS_PERMISSION -> {
                        if (!gateway.revalidateGrant(destination)) return CaptureSubmitResult.NeedsPermission(requestID)
                        val resumeState = snapshot.resumeState ?: return CaptureSubmitResult.SavedForRetry(requestID, "permissionResume")
                        val restored = coordination.mutate(
                            JournalMutationCommand(
                                requestID = requestID,
                                expectedRevision = snapshot.revision,
                                event = JournalEvent(
                                    revision = snapshot.revision + 1,
                                    fromState = CaptureState.NEEDS_PERMISSION,
                                    state = resumeState,
                                    code = JournalCode.PERMISSION_RESTORED,
                                    occurredAtEpochMillis = clock(),
                                ),
                            ),
                            clock(),
                        )
                        if (restored !is JournalMutationResult.Applied && restored !is JournalMutationResult.AlreadyApplied && restored !is JournalMutationResult.PersistedIndexPending) {
                            return CaptureSubmitResult.SavedForRetry(requestID, "permissionResume")
                        }
                    }

                    CaptureState.COMPLETED -> {
                        compactCompletedPackage(requestID)
                        return CaptureSubmitResult.Delivered(requestID)
                    }
                    CaptureState.NEEDS_USER_ACTION, CaptureState.PERMANENT_FAILURE, CaptureState.DISCARDED ->
                        return CaptureSubmitResult.SavedForRetry(requestID, snapshot.state.name.lowercase())
                }
            }
            return CaptureSubmitResult.SavedForRetry(requestID, "driveStepLimit")
        } finally {
            coordination.release(requestID, leaseToken)
        }
    }

    private fun appendRetryableFailure(requestID: String, leaseToken: String, coarseCode: String) {
        val snapshot = store.loadJournal(requestID) ?: return
        if (snapshot.state != CaptureState.PREPARING) return
        append(
            requestID,
            leaseToken,
            snapshot.revision,
            JournalEvent(
                revision = snapshot.revision + 1,
                fromState = CaptureState.PREPARING,
                state = CaptureState.RETRYABLE_FAILURE,
                code = JournalCode.RETRYABLE_FAILURE,
                occurredAtEpochMillis = clock(),
            ),
        )
    }

    private fun append(
        requestID: String,
        leaseToken: String,
        expectedRevision: Int,
        event: JournalEvent,
    ): Boolean = when (
        coordination.mutate(
            JournalMutationCommand(requestID, expectedRevision, event, leaseToken),
            clock(),
        )
    ) {
        is JournalMutationResult.Applied,
        is JournalMutationResult.AlreadyApplied,
        is JournalMutationResult.PersistedIndexPending,
        -> true
        else -> false
    }

    private fun compactCompletedPackages() {
        index.all().asSequence()
            .filter { it.state == CaptureState.COMPLETED }
            .map { it.requestID }
            .toList()
            .forEach(::compactCompletedPackage)
    }

    private fun compactCompletedPackage(requestID: String) {
        when (completionCompactor.compact(requestID)) {
            CompletionCompactionResult.Compacted,
            CompletionCompactionResult.AlreadyCompacted,
            -> processingAuditStore.delete(requestID)
            is CompletionCompactionResult.Deferred -> Unit
        }
    }

    private fun backfillCaptureActivity() {
        index.all().asSequence()
            .filter { it.state == CaptureState.COMPLETED }
            .forEach { recordCaptureActivity(it.requestID) }
    }

    private fun recordCaptureActivity(requestID: String) {
        val requestBytes = store.loadRequestBytes(requestID) ?: return
        val snapshot = store.loadJournal(requestID) ?: return
        if (snapshot.state != CaptureState.COMPLETED) return
        val admitted = runCatching { CapturePackageCodec.decodeHistoricalRequest(requestBytes) }.getOrNull() ?: return
        activity.recordCapture(
            requestID = requestID,
            completedAtEpochMillis = snapshot.events.last().occurredAtEpochMillis,
            source = admitted.captureSource,
            attachmentCount = store.loadPackagedAssets(requestID)?.size ?: 0,
        )
    }

    private fun historyDetailOnWorker(requestID: String): CaptureHistoryDetail? {
        if (!UUID_PATTERN.matches(requestID)) return null
        val requestBytes = store.loadRequestBytes(requestID) ?: return null
        val snapshot = store.loadJournal(requestID) ?: return null
        return runCatching {
            val request = CapturePackageCodec.parseCanonical(requestBytes)
            val payloads = request.getValue("payloads").jsonArray.map { it.jsonObject }
            val text = payloads.filter { it.getValue("kind").jsonPrimitive.content == "text" }
                .joinToString("\n\n") { it.getValue("text").jsonPrimitive.content }
            val url = payloads.firstOrNull { it.getValue("kind").jsonPrimitive.content == "link" }
                ?.get("url")?.jsonPrimitive?.content
            val presetID = request.getValue("preset").jsonObject.getValue("id").jsonPrimitive.content
            val planHash = snapshot.events.lastOrNull { it.planHash != null }?.planHash
            val prepared = planHash?.let { store.loadPreparedArtifacts(requestID, it) }
            val attachments = store.loadPackagedAssets(requestID).orEmpty().map { asset ->
                CaptureAttachment(
                    id = asset.metadata.sourceID,
                    displayName = asset.metadata.fileName.removePrefix("${asset.metadata.sourceID}-"),
                    vaultFileName = asset.metadata.fileName,
                    mediaType = asset.metadata.mediaType,
                    byteCount = asset.metadata.length,
                    sha256 = asset.metadata.sha256,
                )
            }
            val logicalPath = prepared?.planBytes?.let { bytes ->
                val plan = CapturePackageCodec.parseCanonical(bytes)
                plan.getValue("artifacts").jsonArray
                    .map { it.jsonObject }
                    .firstOrNull { it["kind"]?.jsonPrimitive?.content == "note" }
                    ?.get("logicalPath")?.jsonArray
                    ?.joinToString("/") { it.jsonPrimitive.content }
            }
            val processingAudit = processingAuditStore.load(requestID)
            CaptureHistoryDetail(
                requestID = requestID,
                createdAtEpochMillis = request.getValue("createdAtEpochMilliseconds").jsonPrimitive.content.toLong(),
                state = snapshot.state,
                capturedText = text,
                capturedURL = url,
                presetID = presetID,
                logicalPath = logicalPath,
                preparedMarkdown = prepared?.noteBytes?.toString(StandardCharsets.UTF_8),
                captureSource = request.getValue("captureSource").jsonPrimitive.content,
                attachments = attachments,
                originalCapturedText = processingAudit?.originalText,
                processingMode = processingAudit?.mode,
                processingOutcome = processingAudit?.outcome,
                processingNotice = processingAudit?.notice,
            )
        }.getOrNull()
    }

    private fun historyOnWorker(): List<CaptureHistoryItem> {
        val completionRows = completions.all()
        val completedRequestIDs = completionRows.mapTo(mutableSetOf(), CaptureCompletion::requestID)
        val packageRows = index.all()
            .filterNot { it.requestID in completedRequestIDs }
            .map { projection ->
            val detail = historyDetailOnWorker(projection.requestID)
            val normalizedText = detail?.capturedText.orEmpty().trim()
            val title = normalizedText.lineSequence().firstOrNull(String::isNotBlank)?.take(96)
                ?: detail?.capturedURL?.take(96)
            CaptureHistoryItem(
                requestID = projection.requestID,
                createdAtEpochMillis = projection.createdAtEpochMillis,
                updatedAtEpochMillis = projection.updatedAtEpochMillis,
                state = projection.state,
                attemptCount = projection.attemptCount,
                title = title,
                snippet = normalizedText.replace('\n', ' ').take(240).takeIf(String::isNotBlank),
                logicalPath = detail?.logicalPath,
                captureSource = detail?.captureSource ?: "app",
                attachmentCount = detail?.attachments?.size ?: 0,
            )
        }
        val tombstoneRows = completionRows.map { completion ->
            CaptureHistoryItem(
                requestID = completion.requestID,
                createdAtEpochMillis = completion.completedAtEpochMillis,
                updatedAtEpochMillis = completion.completedAtEpochMillis,
                state = CaptureState.COMPLETED,
                attemptCount = 0,
            )
        }
        return (packageRows + tombstoneRows).sortedByDescending(CaptureHistoryItem::updatedAtEpochMillis)
    }

    private suspend fun currentDestinationOnWorker(): CaptureDestination? = destinationFrom(preferences.data.first())

    private fun draftFrom(values: Preferences): CaptureDraft = CaptureDraft(
        text = values[draftTextKey].orEmpty().take(MAX_TEXT_CHARACTERS),
        url = values[draftURLKey]?.take(MAX_URL_CHARACTERS)?.takeIf(::isHttpURL),
        updatedAtEpochMillis = values[draftUpdatedAtKey]?.coerceAtLeast(0L) ?: 0L,
        captureSource = values[draftSourceKey]?.takeIf(CAPTURE_SOURCES::contains) ?: "app",
        attachments = draftAttachmentsFrom(values),
        originRecordingID = values[draftOriginRecordingIDKey]?.takeIf(UUID_PATTERN::matches),
        frozenPreset = values[draftFrozenPresetKey]?.let(::decodePresets)?.singleOrNull(),
        entryTemplateIDOverride = values[draftEntryTemplateIDKey]
            ?.takeIf(PRESET_UUID_PATTERN::matches)
            ?.takeIf { id -> entryTemplatesFrom(values).any { it.id == id } },
    )

    private suspend fun clearDraftOnWorker() {
        preferences.edit { values ->
            values.remove(draftTextKey)
            values.remove(draftURLKey)
            values.remove(draftSourceKey)
            values.remove(draftOriginRecordingIDKey)
            values.remove(draftFrozenPresetKey)
            values.remove(draftAttachmentsKey)
            values.remove(draftEntryTemplateIDKey)
            values[draftUpdatedAtKey] = clock()
        }
        if (draftAssetDirectory.exists()) draftAssetDirectory.deleteRecursively()
    }

    private fun destinationFrom(values: Preferences): CaptureDestination? {
        val id = values[destinationIDKey] ?: return null
        val name = values[destinationNameKey] ?: return null
        val tree = values[destinationTreeKey] ?: return null
        return runCatching { CaptureDestination(id, name, tree) }.getOrNull()
    }

    private fun presetCollectionFrom(values: Preferences): CapturePresetCollection {
        val decoded = values[presetsKey]?.let(::decodePresets).orEmpty()
        val withDefault = if (decoded.any { it.id == DEFAULT_PRESET_ID }) decoded else listOf(DEFAULT_PRESET) + decoded
        val presets = withDefault.take(MAX_PRESETS)
        val requestedActive = values[activePresetIDKey]
        val active = requestedActive?.takeIf { id -> presets.any { it.id == id && it.isEnabled } }
            ?: presets.firstOrNull { it.isEnabled }?.id
            ?: DEFAULT_PRESET_ID
        return CapturePresetCollection(active, presets)
    }

    private fun captureBarFrom(values: Preferences): CaptureBarConfiguration =
        values[captureBarKey]?.let(::decodeCaptureBarConfiguration) ?: CaptureBarConfiguration()

    private fun entryTemplatesFrom(values: Preferences): List<CaptureEntryTemplate> =
        values[entryTemplatesKey]?.let(::decodeEntryTemplates).orEmpty()

    private fun normalizeEntryTemplate(template: CaptureEntryTemplate): CaptureEntryTemplate {
        require(PRESET_UUID_PATTERN.matches(template.id)) { "invalidEntryTemplateID" }
        val name = template.name.trim()
        require(name.length in 1..80) { "invalidEntryTemplateName" }
        require(template.entryPrefix.length <= 16_384 && template.entrySuffix.length <= 16_384) { "entryFormattingLimit" }
        return template.copy(name = name)
    }

    private fun encodeEntryTemplates(templates: List<CaptureEntryTemplate>): String = CapturePackageCodec.canonical(
        buildJsonObject {
            put("templates", JsonArray(templates.map { template ->
                buildJsonObject {
                    put("entryPrefix", template.entryPrefix)
                    put("entrySuffix", template.entrySuffix)
                    put("id", template.id)
                    put("name", template.name)
                }
            }))
            put("version", 1)
        },
    ).toString(StandardCharsets.UTF_8)

    private fun decodeEntryTemplates(value: String): List<CaptureEntryTemplate> = runCatching {
        val root = Json.parseToJsonElement(value).jsonObject
        require(root.getValue("version").jsonPrimitive.intOrNull == 1)
        root.getValue("templates").jsonArray.take(MAX_ENTRY_TEMPLATES).map { raw ->
            val template = raw.jsonObject
            normalizeEntryTemplate(
                CaptureEntryTemplate(
                    id = template.getValue("id").jsonPrimitive.content,
                    name = template.getValue("name").jsonPrimitive.content,
                    entryPrefix = template.stringOr("entryPrefix", ""),
                    entrySuffix = template.stringOr("entrySuffix", ""),
                ),
            )
        }.distinctBy(CaptureEntryTemplate::id)
    }.getOrDefault(emptyList())

    private fun encodePresets(presets: List<CapturePreset>): String = CapturePackageCodec.canonical(
        buildJsonObject {
            put("presets", JsonArray(presets.map(::encodePreset)))
            put("version", 2)
        },
    ).toString(StandardCharsets.UTF_8)

    private fun encodePreset(preset: CapturePreset): JsonObject = buildJsonObject {
        put("attachmentsFolder", preset.attachmentsFolder)
        put("audioEmbedPlacement", preset.audioEmbedPlacement.name)
        put("audioSaveMode", preset.audioSaveMode.name)
        put("capturePrompt", preset.capturePrompt)
        put("customProcessingInstruction", preset.customProcessingInstruction)
        put("embedAudioInMarkdown", preset.embedAudioInMarkdown)
        put("emoji", preset.emoji?.let(::JsonPrimitive) ?: JsonNull)
        put("entryPrefix", preset.entryPrefix)
        put("entrySuffix", preset.entrySuffix)
        put("entryTemplateID", preset.entryTemplateID?.let(::JsonPrimitive) ?: JsonNull)
        put("existingNotePath", preset.existingNotePath)
        put("exportSettings", buildJsonObject {
            put("appendFileName", preset.exportSettings.appendFileName)
            put("destinationName", preset.exportSettings.destinationName)
            put("destinationTreeUri", preset.exportSettings.destinationTreeUri?.let(::JsonPrimitive) ?: JsonNull)
            put("audioEmbedPlacement", preset.exportSettings.audioEmbedPlacement.name)
            put("embedAudioInMarkdown", preset.exportSettings.embedAudioInMarkdown)
            put("exportEnabled", preset.exportSettings.exportEnabled)
            put("format", preset.exportSettings.format.name)
            put("markdownTemplateEnabled", preset.exportSettings.markdownTemplateEnabled)
            put("markdownTemplateName", preset.exportSettings.markdownTemplateName)
            put("markdownTemplateUri", preset.exportSettings.markdownTemplateUri?.let(::JsonPrimitive) ?: JsonNull)
            put("mdObsidianEnabled", preset.exportSettings.mdObsidianEnabled)
            put("mode", preset.exportSettings.mode.name)
            put("newFileNameTemplate", preset.exportSettings.newFileNameTemplate)
            put("usesCustomExportSettings", preset.exportSettings.usesCustomExportSettings)
            put("yamlProperties", JsonArray(preset.exportSettings.yamlProperties.sortedBy { it.name }.map { JsonPrimitive(it.name) }))
            put("yamlUsesMarkdownExtension", preset.exportSettings.yamlUsesMarkdownExtension)
        })
        put("generateImageAltText", preset.generateImageAltText)
        put("headingLevel", preset.headingLevel)
        put("headingTitle", preset.headingTitle)
        put("id", preset.id)
        put("isEnabled", preset.isEnabled)
        put("isPinned", preset.isPinned)
        put("logicalFolder", preset.logicalFolder)
        put("locationPolicy", buildJsonObject {
            put("advancedTemplate", preset.locationPolicy.advancedTemplate)
            put("collectionKey", preset.locationPolicy.collectionKey)
            put("isEnabled", preset.locationPolicy.isEnabled)
            put("labelConsentVersion", preset.locationPolicy.labelConsentVersion?.let(::JsonPrimitive) ?: JsonNull)
            put("labelLookupClass", preset.locationPolicy.labelLookupClass.name)
            put("metadataOutputEnabled", preset.locationPolicy.metadataOutputEnabled)
            put("outputMode", preset.locationPolicy.outputMode.name)
            put("precision", preset.locationPolicy.precision.name)
            put("structuredFields", JsonArray(preset.locationPolicy.structuredFields.map { selection ->
                buildJsonObject {
                    put("field", selection.field.wireName)
                    put("outputKey", selection.outputKey)
                }
            }))
            put("unavailableBehavior", preset.locationPolicy.unavailableBehavior.name)
        })
        put("metadataFields", JsonArray(preset.metadataFields.map { field ->
            buildJsonObject {
                put("name", field.name)
                put("value", field.value)
            }
        }))
        put("metadataScope", preset.metadataScope.name)
        put("missingHeadingBehavior", preset.missingHeadingBehavior.name)
        put("name", preset.name)
        put("noteTargetKind", preset.noteTargetKind.name)
        put("noteNameTemplate", preset.noteNameTemplate)
        put("placement", preset.placement.name)
        put("processingEnabled", preset.processingEnabled)
        put("processingMode", preset.processingMode.name)
        put("processingScope", preset.processingScope.name)
        put("retryProtectionEnabled", preset.retryProtectionEnabled)
        put("revision", preset.revision)
        put("rollingPeriod", preset.rollingPeriod.name)
        put("speakerDiarizationEnabled", preset.speakerDiarizationEnabled)
        put("symbol", preset.symbol)
        put("watchOutputMode", preset.watchOutputMode.name)
    }

    private fun decodePresets(value: String): List<CapturePreset> = runCatching {
        val root = Json.parseToJsonElement(value).jsonObject
        require(root["version"]?.jsonPrimitive?.intOrNull in 1..2)
        root.getValue("presets").jsonArray.map { raw ->
            val preset = raw.jsonObject
            val location = preset["locationPolicy"]?.jsonObject
            val export = preset["exportSettings"] as? JsonObject
            normalizePreset(
                CapturePreset(
                    id = preset.getValue("id").jsonPrimitive.content,
                    name = preset.getValue("name").jsonPrimitive.content,
                    symbol = preset.getValue("symbol").jsonPrimitive.content,
                    emoji = CapturePresetEmoji.normalized(preset["emoji"]?.jsonPrimitive?.contentOrNull),
                    revision = preset.getValue("revision").jsonPrimitive.intOrNull ?: error("presetRevision"),
                    logicalFolder = preset.getValue("logicalFolder").jsonPrimitive.content,
                    noteNameTemplate = preset.getValue("noteNameTemplate").jsonPrimitive.content,
                    metadataFields = preset.getValue("metadataFields").jsonArray.map { field ->
                        val objectValue = field.jsonObject
                        CaptureMetadataField(
                            objectValue.getValue("name").jsonPrimitive.content,
                            objectValue.getValue("value").jsonPrimitive.content,
                        )
                    },
                    isEnabled = preset.booleanOr("isEnabled", true),
                    isPinned = preset.booleanOr("isPinned", false),
                    noteTargetKind = preset.enumOr("noteTargetKind", CaptureNoteTargetKind.NEW_NOTE),
                    rollingPeriod = preset.enumOr("rollingPeriod", CaptureRollingPeriod.DAILY),
                    existingNotePath = preset.stringOr("existingNotePath", ""),
                    placement = preset.enumOr("placement", CapturePlacementKind.APPEND),
                    headingTitle = preset.stringOr("headingTitle", ""),
                    headingLevel = preset.intOr("headingLevel", 1),
                    missingHeadingBehavior = preset.enumOr("missingHeadingBehavior", CaptureMissingHeadingBehavior.FAIL),
                    entryPrefix = preset.stringOr("entryPrefix", ""),
                    entrySuffix = preset.stringOr("entrySuffix", ""),
                    entryTemplateID = preset.nullableString("entryTemplateID"),
                    attachmentsFolder = preset.stringOr("attachmentsFolder", "Attachments"),
                    retryProtectionEnabled = preset.booleanOr("retryProtectionEnabled", false),
                    metadataScope = preset.enumOr("metadataScope", CaptureMetadataScope.DOCUMENT),
                    speakerDiarizationEnabled = preset.booleanOr("speakerDiarizationEnabled", false),
                    processingEnabled = preset.booleanOr("processingEnabled", false),
                    processingMode = preset.enumOr("processingMode", CaptureProcessingMode.CLEAN),
                    processingScope = preset.enumOr("processingScope", CaptureProcessingScope.BOTH),
                    customProcessingInstruction = preset.stringOr("customProcessingInstruction", ""),
                    capturePrompt = preset.stringOr("capturePrompt", ""),
                    generateImageAltText = preset.booleanOr("generateImageAltText", false),
                    locationPolicy = CapturePresetLocationPolicy(
                        isEnabled = location?.booleanOr("isEnabled", false) ?: false,
                        precision = location?.enumOr("precision", CaptureLocationPrecision.EXACT) ?: CaptureLocationPrecision.EXACT,
                        unavailableBehavior = location?.enumOr("unavailableBehavior", CaptureLocationUnavailableBehavior.ASK)
                            ?: CaptureLocationUnavailableBehavior.ASK,
                        metadataOutputEnabled = location?.booleanOr("metadataOutputEnabled", false) ?: false,
                        outputMode = location?.enumOr("outputMode", CaptureLocationOutputMode.STRUCTURED_FIELDS)
                            ?: CaptureLocationOutputMode.STRUCTURED_FIELDS,
                        structuredFields = location?.get("structuredFields")?.jsonArray?.mapNotNull { raw ->
                            val item = raw as? JsonObject ?: return@mapNotNull null
                            val fieldName = item.stringOr("field", "")
                            val field = CaptureLocationField.entries.firstOrNull { it.wireName == fieldName }
                                ?: return@mapNotNull null
                            CaptureLocationStructuredField(field, item.stringOr("outputKey", field.wireName))
                        } ?: DEFAULT_CAPTURE_LOCATION_FIELDS,
                        collectionKey = location?.stringOr("collectionKey", "locations") ?: "locations",
                        advancedTemplate = location?.stringOr("advancedTemplate", "") ?: "",
                        labelLookupClass = location?.enumOr("labelLookupClass", CaptureLocationLabelLookupClass.NONE)
                            ?: CaptureLocationLabelLookupClass.NONE,
                        labelConsentVersion = location?.get("labelConsentVersion")?.jsonPrimitive?.intOrNull,
                    ),
                    audioSaveMode = preset.enumOr("audioSaveMode", CaptureAudioSaveMode.OFF),
                    embedAudioInMarkdown = preset.booleanOr("embedAudioInMarkdown", false),
                    audioEmbedPlacement = preset.enumOr("audioEmbedPlacement", CaptureAudioEmbedPlacement.AFTER_TEXT),
                    watchOutputMode = preset.enumOr("watchOutputMode", CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE),
                    exportSettings = CapturePresetExportSettings(
                        usesCustomExportSettings = export?.booleanOr("usesCustomExportSettings", false) ?: false,
                        exportEnabled = export?.booleanOr("exportEnabled", true) ?: true,
                        format = export?.enumOr("format", CaptureExportFileFormat.MARKDOWN)
                            ?: CaptureExportFileFormat.MARKDOWN,
                        mode = export?.enumOr("mode", CaptureExportFileMode.NEW_FILE) ?: CaptureExportFileMode.NEW_FILE,
                        destinationTreeUri = export?.nullableString("destinationTreeUri"),
                        destinationName = export?.stringOr("destinationName", "") ?: "",
                        embedAudioInMarkdown = export?.booleanOr("embedAudioInMarkdown", false) ?: false,
                        audioEmbedPlacement = export?.enumOr("audioEmbedPlacement", CaptureAudioEmbedPlacement.AFTER_TEXT)
                            ?: CaptureAudioEmbedPlacement.AFTER_TEXT,
                        newFileNameTemplate = export?.stringOr("newFileNameTemplate", "voxboard-{timestamp}-{id8}")
                            ?: "voxboard-{timestamp}-{id8}",
                        appendFileName = export?.stringOr("appendFileName", "voxboard-transcripts")
                            ?: "voxboard-transcripts",
                        markdownTemplateEnabled = export?.booleanOr("markdownTemplateEnabled", false) ?: false,
                        markdownTemplateUri = export?.nullableString("markdownTemplateUri"),
                        markdownTemplateName = export?.stringOr("markdownTemplateName", "") ?: "",
                        mdObsidianEnabled = export?.booleanOr("mdObsidianEnabled", false) ?: false,
                        yamlUsesMarkdownExtension = export?.booleanOr("yamlUsesMarkdownExtension", false) ?: false,
                        yamlProperties = export?.get("yamlProperties")?.let { value ->
                            (value as? JsonArray)?.mapNotNull { property ->
                                runCatching { CaptureExportYAMLProperty.valueOf(property.jsonPrimitive.content) }.getOrNull()
                            }?.toSet()?.takeIf(Set<CaptureExportYAMLProperty>::isNotEmpty)
                        } ?: CaptureExportYAMLProperty.entries.toSet(),
                    ),
                ),
            )
        }.distinctBy(CapturePreset::id)
    }.getOrDefault(emptyList())

    private fun normalizePreset(preset: CapturePreset): CapturePreset {
        require(PRESET_UUID_PATTERN.matches(preset.id)) { "invalidPresetID" }
        val name = preset.name.trim()
        require(name.length in 1..64) { "invalidPresetName" }
        val symbol = preset.symbol.trim()
        // An empty symbol means "no icon": emoji wins first, then the symbol,
        // then surfaces fall back to the preset's initial.
        require(symbol.codePointCount(0, symbol.length) in 0..32 && symbol.length <= 64) { "invalidPresetSymbol" }
        require(preset.emoji === null || preset.emoji!!.length <= 64) { "invalidPresetEmoji" }
        val segments = preset.logicalFolder.split('/').map(String::trim).filter(String::isNotEmpty)
        require(segments.size in 1..31 && segments.all(::isSafePathSegment)) { "invalidPresetFolder" }
        val noteNameTemplate = preset.noteNameTemplate.trim()
        require(
            noteNameTemplate.length in 1..128 &&
                noteNameTemplate.endsWith(".md", ignoreCase = true) &&
                noteNameTemplate.none { it == '/' || it == '\\' || it == '\u0000' },
        ) { "invalidNoteNameTemplate" }
        require(preset.metadataFields.size <= MAX_METADATA_FIELDS) { "metadataFieldLimit" }
        val fields = preset.metadataFields.map { field ->
            val fieldName = field.name.trim()
            require(fieldName.matches(METADATA_NAME_PATTERN)) { "invalidMetadataName" }
            require(field.value.length <= 512) { "invalidMetadataValue" }
            CaptureMetadataField(fieldName, field.value)
        }
        require(fields.map { it.name.lowercase() }.distinct().size == fields.size) { "duplicateMetadataName" }
        val existingSegments = preset.existingNotePath.split('/').map(String::trim).filter(String::isNotEmpty)
        if (preset.noteTargetKind == CaptureNoteTargetKind.EXISTING_NOTE) {
            require(existingSegments.isNotEmpty() && existingSegments.size <= 32 && existingSegments.all(::isSafePathSegment)) {
                "invalidExistingNotePath"
            }
            require(existingSegments.last().endsWith(".md", ignoreCase = true)) { "invalidExistingNotePath" }
        }
        require(preset.headingLevel in 1..6) { "invalidHeadingLevel" }
        if (preset.placement == CapturePlacementKind.BENEATH_HEADING) {
            require(preset.headingTitle.trim().isNotEmpty() && preset.headingTitle.length <= 256) { "invalidHeadingTitle" }
        }
        require(preset.entryPrefix.length <= 16_384 && preset.entrySuffix.length <= 16_384) { "entryFormattingLimit" }
        require(preset.entryTemplateID?.let(PRESET_UUID_PATTERN::matches) != false) { "invalidEntryTemplateID" }
        val attachmentSegments = preset.attachmentsFolder.split('/').map(String::trim).filter(String::isNotEmpty)
        require(attachmentSegments.size <= 31 && attachmentSegments.all(::isSafePathSegment)) { "invalidAttachmentsFolder" }
        require(preset.customProcessingInstruction.length <= 8_192 && preset.capturePrompt.length <= 512) { "processingConfigurationLimit" }
        require(preset.locationPolicy.collectionKey.matches(METADATA_NAME_PATTERN)) { "invalidLocationCollectionKey" }
        require(preset.locationPolicy.advancedTemplate.length <= 8_192) { "locationTemplateLimit" }
        require(
            preset.locationPolicy.labelLookupClass != CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK ||
                preset.locationPolicy.labelConsentVersion == CURRENT_LOCATION_LABEL_CONSENT_VERSION,
        ) { "locationLabelConsent" }
        require(
            preset.locationPolicy.labelLookupClass == CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK ||
                preset.locationPolicy.labelConsentVersion == null,
        ) { "locationLabelConsent" }
        val structuredLocationFields = preset.locationPolicy.structuredFields.map { selection ->
            selection.copy(outputKey = selection.outputKey.trim())
        }
        require(structuredLocationFields.size <= CaptureLocationField.entries.size) { "locationStructuredFieldLimit" }
        require(structuredLocationFields.map { it.field }.distinct().size == structuredLocationFields.size) {
            "duplicateLocationStructuredField"
        }
        require(structuredLocationFields.map { it.outputKey }.distinct().size == structuredLocationFields.size) {
            "duplicateLocationOutputKey"
        }
        require(structuredLocationFields.all { selection ->
            selection.outputKey.matches(Regex("^[A-Za-z_][A-Za-z0-9_-]{0,63}$")) &&
                if (selection.field == CaptureLocationField.ID) selection.outputKey == "id" else selection.outputKey != "id"
        }) { "invalidLocationOutputKey" }
        val export = preset.exportSettings
        val destinationTreeUri = export.destinationTreeUri?.trim()?.takeIf(String::isNotEmpty)
        val markdownTemplateUri = export.markdownTemplateUri?.trim()?.takeIf(String::isNotEmpty)
        require(destinationTreeUri == null || (destinationTreeUri.length <= 4_096 && Uri.parse(destinationTreeUri).scheme == "content")) {
            "invalidExportDestination"
        }
        require(markdownTemplateUri == null || (markdownTemplateUri.length <= 4_096 && Uri.parse(markdownTemplateUri).scheme == "content")) {
            "invalidExportTemplate"
        }
        require(export.destinationName.length <= 256 && export.markdownTemplateName.length <= 256) { "exportDisplayNameLimit" }
        require(export.newFileNameTemplate.length in 1..256 && export.appendFileName.length in 1..256) { "exportFilenameLimit" }
        require(export.yamlProperties.isNotEmpty()) { "exportYAMLPropertiesEmpty" }
        return preset.copy(
            name = name,
            symbol = symbol,
            emoji = CapturePresetEmoji.normalized(preset.emoji),
            revision = preset.revision.coerceAtLeast(1),
            logicalFolder = segments.joinToString("/"),
            noteNameTemplate = noteNameTemplate,
            metadataFields = fields,
            existingNotePath = existingSegments.joinToString("/"),
            headingTitle = preset.headingTitle.trim(),
            attachmentsFolder = attachmentSegments.joinToString("/"),
            locationPolicy = preset.locationPolicy.copy(structuredFields = structuredLocationFields),
            isEnabled = if (preset.id == DEFAULT_PRESET_ID) true else preset.isEnabled,
            exportSettings = export.copy(
                destinationTreeUri = destinationTreeUri,
                destinationName = export.destinationName.trim(),
                newFileNameTemplate = export.newFileNameTemplate.trim(),
                appendFileName = export.appendFileName.trim(),
                markdownTemplateUri = markdownTemplateUri,
                markdownTemplateName = export.markdownTemplateName.trim(),
            ),
        )
    }

    private fun JsonObject.stringOr(key: String, default: String): String =
        this[key]?.jsonPrimitive?.content ?: default

    private fun JsonObject.booleanOr(key: String, default: Boolean): Boolean =
        this[key]?.jsonPrimitive?.booleanOrNull ?: default

    private fun JsonObject.intOr(key: String, default: Int): Int =
        this[key]?.jsonPrimitive?.intOrNull ?: default

    private fun JsonObject.nullableString(key: String): String? =
        this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.content

    private inline fun <reified T : Enum<T>> JsonObject.enumOr(key: String, default: T): T =
        this[key]?.jsonPrimitive?.content?.let { value -> runCatching { enumValueOf<T>(value) }.getOrNull() } ?: default

    private fun isSafePathSegment(value: String): Boolean =
        value.length in 1..255 && value !in setOf(".", "..") && value.none { it == '/' || it == '\\' || it == '\u0000' }

    private data class PreparedRecordingAsset(
        val attachment: CaptureAttachment,
        val durableInput: DurableAssetInput,
    )

    private fun prepareRecordingAsset(
        contentUri: String,
        displayName: String?,
        includeInMarkdown: Boolean,
    ): PreparedRecordingAsset {
        val uri = Uri.parse(contentUri)
        require(uri.scheme == "content") { "invalidAttachmentUri" }
        val resolver = appContext.contentResolver
        val providerName = displayName?.takeIf(String::isNotBlank) ?: resolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        val safeDisplayName = sanitizeAttachmentName(providerName.orEmpty().ifBlank { "Recording.wav" })
        val id = UUID.randomUUID().toString().lowercase()
        val vaultName = "$id-$safeDisplayName".take(255)
        val bytes = resolver.openInputStream(uri)?.use { input ->
            val output = ByteArrayOutputStream()
            val buffer = ByteArray(64 * 1024)
            var total = 0L
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                if (count == 0) continue
                total += count
                require(total <= MAX_DRAFT_ATTACHMENT_BYTES) { "attachmentTooLarge" }
                output.write(buffer, 0, count)
            }
            output.toByteArray()
        } ?: error("attachmentUnavailable")
        require(bytes.isNotEmpty()) { "attachmentEmpty" }
        val sha256 = CapturePackageCodec.sha256(bytes)
        val attachment = CaptureAttachment(
            id = id,
            displayName = safeDisplayName,
            vaultFileName = vaultName,
            mediaType = "audio/wav",
            byteCount = bytes.size.toLong(),
            sha256 = sha256,
            includeInMarkdown = includeInMarkdown,
        )
        return PreparedRecordingAsset(
            attachment,
            DurableAssetInput(id, vaultName, attachment.mediaType, bytes),
        )
    }

    private fun durableInputsFor(attachments: List<CaptureAttachment>): List<DurableAssetInput> =
        attachments.map { attachment ->
            require(UUID_PATTERN.matches(attachment.id) && CapturePackageCodec.safeAssetFileName(attachment.vaultFileName))
            val source = File(draftAssetDirectory, attachment.id)
            require(source.isFile && !Files.isSymbolicLink(source.toPath()) && source.length() == attachment.byteCount)
            val bytes = source.readBytes()
            require(bytes.size.toLong() == attachment.byteCount && CapturePackageCodec.sha256(bytes) == attachment.sha256)
            DurableAssetInput(attachment.id, attachment.vaultFileName, attachment.mediaType, bytes)
        }

    private fun draftAttachmentsFrom(values: Preferences): List<CaptureAttachment> =
        values[draftAttachmentsKey]?.let(::decodeDraftAttachments).orEmpty().filter { attachment ->
            UUID_PATTERN.matches(attachment.id) && File(draftAssetDirectory, attachment.id).let { it.isFile && it.length() == attachment.byteCount }
        }

    private fun encodeDraftAttachments(attachments: List<CaptureAttachment>): String = CapturePackageCodec.canonical(
        buildJsonObject {
            put("attachments", JsonArray(attachments.map { attachment ->
                buildJsonObject {
                    put("byteCount", attachment.byteCount)
                    put("displayName", attachment.displayName)
                    put("id", attachment.id)
                    put("mediaType", attachment.mediaType)
                    put("sha256", attachment.sha256)
                    put("vaultFileName", attachment.vaultFileName)
                    put("includeInMarkdown", attachment.includeInMarkdown)
                }
            }))
            put("version", 2)
        },
    ).toString(StandardCharsets.UTF_8)

    private fun decodeDraftAttachments(value: String): List<CaptureAttachment> = runCatching {
        val root = Json.parseToJsonElement(value).jsonObject
        require(root["version"]?.jsonPrimitive?.intOrNull in 1..2)
        root.getValue("attachments").jsonArray.take(MAX_DRAFT_ATTACHMENTS).map { raw ->
            val asset = raw.jsonObject
            CaptureAttachment(
                id = asset.getValue("id").jsonPrimitive.content.also { require(UUID_PATTERN.matches(it)) },
                displayName = asset.getValue("displayName").jsonPrimitive.content.also { require(CapturePackageCodec.safeAssetFileName(it)) },
                vaultFileName = asset.getValue("vaultFileName").jsonPrimitive.content.also { require(CapturePackageCodec.safeAssetFileName(it)) },
                mediaType = asset.getValue("mediaType").jsonPrimitive.content.also { require(it.length in 1..127) },
                byteCount = asset.getValue("byteCount").jsonPrimitive.content.toLong().also { require(it in 1..MAX_DRAFT_ATTACHMENT_BYTES) },
                sha256 = asset.getValue("sha256").jsonPrimitive.content.also { require(SHA_PATTERN.matches(it)) },
                includeInMarkdown = asset.booleanOr("includeInMarkdown", true),
            )
        }.distinctBy(CaptureAttachment::id)
    }.getOrDefault(emptyList())

    private fun sanitizeAttachmentName(value: String): String {
        val last = value.replace('\\', '/').substringAfterLast('/').trim()
        val replaced = last.map { character ->
            if (character in "/\\?%*|\"<>:\n\r\t" || character.isISOControl()) '-' else character
        }.joinToString("").trim().trimStart('.')
        return replaced.ifBlank { "attachment" }.take(180).ifBlank { "attachment" }
    }

    private fun uniqueDisplayName(initial: String, occupied: Set<String>): String {
        if (initial !in occupied) return initial
        val dot = initial.lastIndexOf('.').takeIf { it > 0 }
        val stem = dot?.let { initial.substring(0, it) } ?: initial
        val extension = dot?.let { initial.substring(it) }.orEmpty()
        var suffix = 2
        while (true) {
            val candidate = "${stem.take(170)}-$suffix$extension".take(180)
            if (candidate !in occupied) return candidate
            suffix++
        }
    }

    private fun requestBytes(
        requestID: String,
        text: String,
        url: String?,
        createdAt: Long,
        preset: CapturePreset,
        captureSource: String,
        locationOutcome: CaptureLocationOutcome,
        originRecordingID: String?,
        attachments: List<CaptureAttachment>,
    ): ByteArray {
        val payloads = buildList {
            if (text.isNotBlank()) add(buildJsonObject {
                put("id", UUID.randomUUID().toString().lowercase())
                put("kind", "text")
                put("text", text)
            })
            if (url != null) add(buildJsonObject {
                put("id", UUID.randomUUID().toString().lowercase())
                put("kind", "link")
                put("label", runCatching { URI(url).host }.getOrNull().orEmpty())
                put("url", url)
            })
            addAll(captureAssetPayloads(attachments))
        }
        val presetWithoutHash = presetSnapshot(preset, ZERO_SHA)
        val presetHash = CapturePackageCodec.sha256(CapturePackageCodec.canonical(presetWithoutHash))
        return CapturePackageCodec.canonical(buildJsonObject {
            put("calendar", "gregorian")
            put("captureSource", captureSource)
            put("contractVersion", 1)
            put("createdAtEpochMilliseconds", createdAt)
            put("invocation", buildJsonObject {
                put(
                    "locationOutcome",
                    when (locationOutcome) {
                        CaptureLocationOutcome.NotRequested -> "notRequested"
                        is CaptureLocationOutcome.Unavailable -> "unavailable"
                        is CaptureLocationOutcome.Available -> if (
                            locationOutcome.labelObservation.outcome == CaptureLocationLabelOutcome.FROZEN
                        ) "labelFrozen" else "coordinatesFrozen"
                    },
                )
                val labelObservation = when (locationOutcome) {
                    CaptureLocationOutcome.NotRequested -> null
                    is CaptureLocationOutcome.Unavailable -> locationOutcome.labelObservation
                    is CaptureLocationOutcome.Available -> locationOutcome.labelObservation
                }
                if (labelObservation != null) {
                    put("locationLabelObservation", buildJsonObject {
                        put("consentVersion", labelObservation.consentVersion?.let(::JsonPrimitive) ?: JsonNull)
                        put("lookupClass", labelObservation.lookupClass.wireName)
                        put("outcome", labelObservation.outcome.wireName)
                        put("requested", labelObservation.requested)
                    })
                }
                if (locationOutcome is CaptureLocationOutcome.Unavailable) {
                    put("locationAttemptedAtEpochMilliseconds", locationOutcome.attemptedAtEpochMillis)
                    put("locationUnavailableReason", locationOutcome.reason.wireName)
                }
                if (locationOutcome is CaptureLocationOutcome.Available) {
                    put("locationSnapshot", buildJsonObject {
                        val snapshot = locationOutcome.snapshot
                        put("accuracyMillimeters", snapshot.accuracyMillimeters?.let(::JsonPrimitive) ?: JsonNull)
                        put("capturedAtEpochMilliseconds", snapshot.capturedAtEpochMillis)
                        put("latitudeE6", snapshot.latitudeE6)
                        put("longitudeE6", snapshot.longitudeE6)
                        put("precision", snapshot.precision.name.lowercase())
                        put("source", snapshot.source)
                        snapshot.label?.takeUnless { it.isEmpty }?.let { label ->
                            put("label", buildJsonObject {
                                put("place", label.place?.let(::JsonPrimitive) ?: JsonNull)
                                put("city", label.city?.let(::JsonPrimitive) ?: JsonNull)
                                put("region", label.region?.let(::JsonPrimitive) ?: JsonNull)
                                put("country", label.country?.let(::JsonPrimitive) ?: JsonNull)
                            })
                        }
                    })
                }
                put("originRecordingID", originRecordingID?.let(::JsonPrimitive) ?: JsonNull)
                put("sequence", 1)
            })
            put("locale", Locale.getDefault().toLanguageTag().ifBlank { "en-US" })
            put("operation", captureOperationFor(preset))
            put("payloads", JsonArray(payloads))
            put("pins", buildJsonObject {
                put("coreVersion", CORE_VERSION)
                put("modelProfileID", JsonNull)
                put("modelRevision", JsonNull)
                put("profileID", PROFILE_ID)
                put("profileVersion", 1)
                put("rendererRevision", RENDERER_REVISION)
            })
            put("preset", presetSnapshot(preset, presetHash))
            put("requestID", requestID)
            put("timezone", TimeZone.getDefault().id.ifBlank { "UTC" })
        })
    }

    private fun presetSnapshot(preset: CapturePreset, snapshotHash: String): JsonObject = buildJsonObject {
        put("destinationPolicy", buildJsonObject {
            put("capabilityClass", "userVault")
            put("capabilityReference", "synthetic-vault-capability")
            put("expectedCaseSensitivity", "sensitive")
        })
        put("id", preset.id)
        put("locationPolicy", captureLocationPolicyFor(preset.locationPolicy))
        put("metadataPolicy", captureMetadataPolicyFor(preset))
        put("retryMarkerPolicy", captureRetryMarkerPolicyFor(preset))
        put("revision", preset.revision)
        put("routePolicy", captureRoutePolicyFor(preset))
        put("snapshotHash", snapshotHash)
        put("templateFreezePoint", "firstPreparation")
    }

    private fun isHttpURL(value: String): Boolean = runCatching {
        val uri = URI(value)
        (uri.scheme == "http" || uri.scheme == "https") && !uri.host.isNullOrBlank()
    }.getOrDefault(false)

    private companion object {
        val destinationIDKey = stringPreferencesKey("capture.destination.id")
        val destinationNameKey = stringPreferencesKey("capture.destination.name")
        val destinationTreeKey = stringPreferencesKey("capture.destination.tree")
        val draftTextKey = stringPreferencesKey("capture.draft.text")
        val draftURLKey = stringPreferencesKey("capture.draft.url")
        val draftUpdatedAtKey = longPreferencesKey("capture.draft.updated-at")
        val draftSourceKey = stringPreferencesKey("capture.draft.capture-source")
        val draftOriginRecordingIDKey = stringPreferencesKey("capture.draft.origin-recording-id")
        val draftFrozenPresetKey = stringPreferencesKey("capture.draft.frozen-preset.v1")
        val draftEntryTemplateIDKey = stringPreferencesKey("capture.draft.entry-template-id")
        val draftAttachmentsKey = stringPreferencesKey("capture.draft.attachments.v1")
        val captureBarKey = stringPreferencesKey("capture.toolbar.configuration.v1")
        val presetRailExpandedKey = booleanPreferencesKey("capture.preset.quick-access.rail-expanded.v1")
        val activePresetIDKey = stringPreferencesKey("capture.preset.active-id")
        val presetsKey = stringPreferencesKey("capture.presets.v1")
        val entryTemplatesKey = stringPreferencesKey("capture.entry-templates.v1")
        const val CORE_VERSION = "0.1.0-alpha.1"
        const val RENDERER_REVISION = "swift-legacy-m0"
        const val PROFILE_ID = "apple-parity-v1"
        const val DEFAULT_PRESET_ID = "33333333-3333-4333-8333-333333333333"
        const val ZERO_SHA = "0000000000000000000000000000000000000000000000000000000000000000"
        const val MAX_TEXT_CHARACTERS = 65_536
        const val MAX_URL_CHARACTERS = 8_192
        const val MAX_DRAFT_ATTACHMENTS = 32
        const val MAX_DRAFT_ATTACHMENT_BYTES = 100L * 1024 * 1024
        const val MAX_DRIVE_STEPS = 8
        const val MAX_DRAIN_ITEMS = 32
        const val MAX_PRESETS = 24
        const val MAX_ENTRY_TEMPLATES = 32
        const val MAX_METADATA_FIELDS = 16
        const val LEASE_DURATION_MILLIS = 10 * 60 * 1_000L
        val PRESET_UUID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        val METADATA_NAME_PATTERN = Regex("^[A-Za-z0-9_-]{1,64}$")
        val CAPTURE_SOURCES = setOf("app", "share", "keyboard", "widget", "shortcut", "watch", "wear")
        val DEFAULT_PRESET = CapturePreset(
            id = DEFAULT_PRESET_ID,
            name = "Default",
            symbol = "description",
            revision = 1,
            logicalFolder = "Inbox",
            noteNameTemplate = "capture-{id}.md",
            metadataFields = emptyList(),
        )
    }
}

/**
 * Produces the immutable control-plane descriptor for every app-owned attachment.
 * Bytes remain in the separately fsynced package asset store; the shared core only
 * receives bounded identity, type, size, and digest facts.
 */
internal fun captureAssetPayloads(attachments: List<CaptureAttachment>): List<JsonObject> =
    attachments.map { attachment ->
        buildJsonObject {
            put("id", attachment.id)
            put("kind", "asset")
            put("sourceID", attachment.id)
            put("mediaType", attachment.mediaType)
            put("length", attachment.byteCount)
            put("sha256", attachment.sha256)
            put("safeExtension", safeAssetExtension(attachment.displayName))
            put("originalNamePolicy", "safeStem")
        }
    }

private fun safeAssetExtension(displayName: String): String {
    val extension = displayName.substringAfterLast('.', "").lowercase(Locale.ROOT)
    return extension.takeIf { it.length <= 16 && it.all { character -> character in 'a'..'z' || character in '0'..'9' } }
        .orEmpty()
}

internal fun encodeCaptureBarConfiguration(configuration: CaptureBarConfiguration): String = CapturePackageCodec.canonical(
    buildJsonObject {
        put("hidden", JsonArray(configuration.hiddenActions.map(CaptureBarAction::persistedName).sorted().map(::JsonPrimitive)))
        put("order", JsonArray(configuration.orderedActions.map { JsonPrimitive(it.persistedName) }))
        put("confirmVoiceNoteBeforeAdding", configuration.confirmsVoiceNotesBeforeAdding)
        put("voiceRecordingResult", configuration.voiceRecordingResult.persistedName)
        put("twentyFourHour", configuration.usesTwentyFourHourTimestamps)
        put("version", 1)
    },
).toString(StandardCharsets.UTF_8)

internal fun decodeCaptureBarConfiguration(value: String): CaptureBarConfiguration = runCatching {
    val root = Json.parseToJsonElement(value).jsonObject
    require(root["version"]?.jsonPrimitive?.intOrNull == 1)
    val byName = CaptureBarAction.entries.associateBy(CaptureBarAction::persistedName)
    CaptureBarConfiguration(
        orderedActions = root.getValue("order").jsonArray.mapNotNull { byName[it.jsonPrimitive.content] },
        hiddenActions = root.getValue("hidden").jsonArray.mapNotNull { byName[it.jsonPrimitive.content] }.toSet(),
        usesTwentyFourHourTimestamps = root["twentyFourHour"]?.jsonPrimitive?.booleanOrNull ?: false,
        confirmsVoiceNotesBeforeAdding = root["confirmVoiceNoteBeforeAdding"]?.jsonPrimitive?.booleanOrNull ?: false,
        voiceRecordingResult = VoiceRecordingResult.fromPersistedName(
            root["voiceRecordingResult"]?.jsonPrimitive?.contentOrNull,
        ),
    ).normalized()
}.getOrDefault(CaptureBarConfiguration())

internal fun captureOperationFor(preset: CapturePreset): String = when (preset.noteTargetKind) {
    CaptureNoteTargetKind.NEW_NOTE -> "newNote"
    CaptureNoteTargetKind.ROLLING_NOTE -> "rollingNote"
    CaptureNoteTargetKind.EXISTING_NOTE -> when (preset.placement) {
        CapturePlacementKind.APPEND -> "existingNoteAppend"
        CapturePlacementKind.PREPEND -> "existingNotePrepend"
        CapturePlacementKind.BENEATH_HEADING -> "existingNoteHeading"
    }
}

internal fun captureRetryMarkerPolicyFor(preset: CapturePreset): String =
    if (preset.retryProtectionEnabled) "voxCaptureCommentV1" else "none"

internal fun captureMetadataPolicyFor(preset: CapturePreset): JsonObject = buildJsonObject {
    put("finalNewline", true)
    put(
        "frontmatterMode",
        if (preset.metadataScope == CaptureMetadataScope.ENTRY || preset.metadataFields.isEmpty()) "none" else "merge",
    )
    put("lineEnding", "lf")
    put("orderedFields", JsonArray(preset.metadataFields.map { field ->
        buildJsonObject {
            put("name", field.name)
            put("value", field.value)
        }
    }))
    put("scope", if (preset.metadataScope == CaptureMetadataScope.ENTRY) "entry" else "document")
    put("templatePolicy", "none")
}

internal fun captureLocationPolicyFor(policy: md.vox.android.capturedomain.CapturePresetLocationPolicy): JsonObject =
    buildJsonObject {
        put("advancedTemplate", policy.advancedTemplate)
        put("collectionKey", policy.collectionKey)
        put("isEnabled", policy.isEnabled)
        policy.labelConsentVersion?.let { put("labelConsentVersion", it) }
        put("labelLookupClass", policy.labelLookupClass.wireName)
        put("metadataOutputEnabled", policy.metadataOutputEnabled)
        put("outputMode", when (policy.outputMode) {
            CaptureLocationOutputMode.STRUCTURED_FIELDS -> "structured"
            CaptureLocationOutputMode.ADVANCED_YAML -> "advancedTemplate"
        })
        put("precision", policy.precision.name.lowercase())
        put("structuredFields", JsonArray(policy.structuredFields.map { selection ->
            buildJsonObject {
                put("field", selection.field.wireName)
                put("outputKey", selection.outputKey)
            }
        }))
    }

internal fun captureRoutePolicyFor(preset: CapturePreset): JsonObject = buildJsonObject {
    val existingSegments = preset.existingNotePath.split('/').map(String::trim).filter(String::isNotEmpty)
    val routeFolder = if (preset.noteTargetKind == CaptureNoteTargetKind.EXISTING_NOTE) {
        existingSegments.dropLast(1)
    } else {
        preset.logicalFolder.split('/').map(String::trim).filter(String::isNotEmpty)
    }
    val routeName = if (preset.noteTargetKind == CaptureNoteTargetKind.EXISTING_NOTE) {
        existingSegments.last()
    } else {
        preset.noteNameTemplate
    }
    put(
        "attachmentFolder",
        JsonArray(preset.attachmentsFolder.split('/').map(String::trim).filter(String::isNotEmpty).map(::JsonPrimitive)),
    )
    put(
        "collisionPolicy",
        when (preset.noteTargetKind) {
            CaptureNoteTargetKind.NEW_NOTE -> "deterministicSuffix"
            CaptureNoteTargetKind.ROLLING_NOTE -> "reuseIfHashMatches"
            CaptureNoteTargetKind.EXISTING_NOTE -> "fail"
        },
    )
    put("entryPrefix", preset.entryPrefix)
    put("entrySuffix", preset.entrySuffix)
    put("extensionPolicy", "markdownDotMd")
    if (preset.noteTargetKind != CaptureNoteTargetKind.NEW_NOTE) {
        put(
            "placement",
            when (preset.placement) {
                CapturePlacementKind.APPEND -> "append"
                CapturePlacementKind.PREPEND -> "prepend"
                CapturePlacementKind.BENEATH_HEADING -> "beneathHeading"
            },
        )
    }
    if (preset.noteTargetKind == CaptureNoteTargetKind.ROLLING_NOTE) {
        put("rollingPeriod", preset.rollingPeriod.name.lowercase())
    }
    if (preset.placement == CapturePlacementKind.BENEATH_HEADING && preset.noteTargetKind != CaptureNoteTargetKind.NEW_NOTE) {
        put("headingTitle", preset.headingTitle)
        put("headingLevel", preset.headingLevel)
        put("missingHeadingBehavior", preset.missingHeadingBehavior.name.lowercase())
    }
    put("logicalFolder", JsonArray(routeFolder.map(::JsonPrimitive)))
    put("noteNameTemplate", routeName)
}

internal fun renderAttachmentMarkdown(
    attachment: CaptureAttachment,
    preset: CapturePreset,
    imageAltText: String?,
): String {
    if (!attachment.includeInMarkdown) return ""
    val folder = preset.attachmentsFolder.trim('/').takeIf(String::isNotEmpty)
    val path = listOfNotNull(folder, attachment.vaultFileName).joinToString("/").replace("]", "\\]")
    val alias = (imageAltText?.takeIf { attachment.isImage && it.isNotBlank() } ?: attachment.displayName)
        .replace("|", "\\|").replace("]", "\\]").replace('\n', ' ').take(240)
    return if (attachment.mediaType.startsWith("image/") || attachment.mediaType.startsWith("audio/") ||
        attachment.mediaType.startsWith("video/")
    ) "![[$path|$alias]]" else "[[$path|$alias]]"
}

internal data class RecordingAudioArtifactPolicy(
    val retainsSourceAudio: Boolean,
    val artifactFolder: String,
    val includesMarkdownReference: Boolean,
    val referencePlacement: CaptureAudioEmbedPlacement,
)

internal fun recordingAudioArtifactPolicy(preset: CapturePreset): RecordingAudioArtifactPolicy =
    RecordingAudioArtifactPolicy(
        retainsSourceAudio = preset.audioSaveMode != CaptureAudioSaveMode.OFF,
        artifactFolder = if (preset.audioSaveMode == CaptureAudioSaveMode.ALONGSIDE_NOTE) {
            when (preset.noteTargetKind) {
                CaptureNoteTargetKind.EXISTING_NOTE -> preset.existingNotePath
                    .split('/')
                    .map(String::trim)
                    .filter(String::isNotEmpty)
                    .dropLast(1)
                    .joinToString("/")
                CaptureNoteTargetKind.NEW_NOTE,
                CaptureNoteTargetKind.ROLLING_NOTE,
                -> preset.logicalFolder.trim('/')
            }
        } else preset.attachmentsFolder,
        includesMarkdownReference = preset.audioSaveMode != CaptureAudioSaveMode.OFF && preset.embedAudioInMarkdown,
        referencePlacement = preset.audioEmbedPlacement,
    )

internal fun composeCaptureRequestText(
    body: String,
    attachments: List<CaptureAttachment>,
    preset: CapturePreset,
    imageDescriptions: Map<String, String?> = emptyMap(),
): String {
    val (audio, other) = attachments.partition { it.mediaType.startsWith("audio/") }
    fun markdown(values: List<CaptureAttachment>): String = values
        .map { renderAttachmentMarkdown(it, preset, imageDescriptions[it.id]) }
        .filter(String::isNotBlank)
        .joinToString("\n")

    val audioMarkdown = markdown(audio)
    val otherMarkdown = markdown(other)
    val sections = when (preset.audioEmbedPlacement) {
        CaptureAudioEmbedPlacement.BEFORE_TEXT -> listOf(audioMarkdown, body, otherMarkdown)
        CaptureAudioEmbedPlacement.AFTER_TEXT -> listOf(body, otherMarkdown, audioMarkdown)
    }
    return sections.filter(String::isNotBlank).joinToString("\n\n")
}
