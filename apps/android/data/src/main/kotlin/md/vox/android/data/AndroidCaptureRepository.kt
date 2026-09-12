package md.vox.android.data

import android.content.Context
import android.net.Uri
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import md.vox.android.capturedomain.CaptureDestination
import md.vox.android.capturedomain.CaptureDraft
import md.vox.android.capturedomain.CaptureDrainSummary
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CaptureRepository
import md.vox.android.capturedomain.CaptureState
import md.vox.android.capturedomain.CaptureSubmitResult
import md.vox.android.capturedomain.CommitOutcome
import md.vox.android.capturedomain.EnqueueResult
import md.vox.android.capturedomain.JournalCode
import md.vox.android.capturedomain.JournalEvent
import md.vox.android.capturedomain.JournalMutationCommand
import md.vox.android.capturedomain.JournalMutationResult
import md.vox.android.capturedomain.LeasePlan
import md.vox.android.capturedomain.VaultDestination
import md.vox.android.corebridge.CoreBridge
import md.vox.android.corebridge.CoreResult
import java.net.URI
import java.nio.charset.StandardCharsets
import java.util.Locale
import java.util.TimeZone
import java.util.UUID

/** Production M3 repository: durable enqueue → Rust materialization → verified SAF commit. */
class AndroidCaptureRepository(
    context: Context,
    private val bridge: CoreBridge,
    private val clock: () -> Long = System::currentTimeMillis,
) : CaptureRepository {
    private val appContext = context.applicationContext
    private val database = CaptureDatabase.create(appContext)
    private val index = RoomCaptureIndex(database)
    private val store = DurableCapturePackageStore(appContext.noBackupFilesDir, index)
    private val coordination = CaptureDurabilityCoordinator(store, RoomCaptureCoordination(database))
    private val quota = RoomQuotaLedger(database)
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

    override suspend fun saveDraft(text: String, url: String?): CaptureDraft = withContext(Dispatchers.IO) {
        require(text.length <= MAX_TEXT_CHARACTERS) { "draftTextTooLarge" }
        val normalizedURL = url?.trim()?.takeIf(String::isNotEmpty)
        require(normalizedURL == null || (normalizedURL.length <= MAX_URL_CHARACTERS && isHttpURL(normalizedURL))) { "invalidDraftURL" }
        val draft = CaptureDraft(text, normalizedURL, clock())
        preferences.edit { values ->
            if (draft.text.isEmpty()) values.remove(draftTextKey) else values[draftTextKey] = draft.text
            if (draft.url == null) values.remove(draftURLKey) else values[draftURLKey] = draft.url
            values[draftUpdatedAtKey] = draft.updatedAtEpochMillis
        }
        draft
    }

    override suspend fun capturePresets(): CapturePresetCollection = withContext(Dispatchers.IO) {
        presetCollectionFrom(preferences.data.first())
    }

    override suspend fun selectCapturePreset(presetID: String): CapturePresetCollection = withContext(Dispatchers.IO) {
        val current = presetCollectionFrom(preferences.data.first())
        require(current.presets.any { it.id == presetID }) { "unknownPreset" }
        preferences.edit { it[activePresetIDKey] = presetID }
        current.copy(activePresetID = presetID)
    }

    override suspend fun saveCapturePreset(preset: CapturePreset): CapturePresetCollection = withContext(Dispatchers.IO) {
        val current = presetCollectionFrom(preferences.data.first())
        val existing = current.presets.firstOrNull { it.id == preset.id }
        val normalized = normalizePreset(preset).copy(revision = (existing?.revision ?: 0) + 1)
        val updated = if (existing == null) {
            require(current.presets.size < MAX_PRESETS) { "presetLimit" }
            current.presets + normalized
        } else {
            current.presets.map { if (it.id == normalized.id) normalized else it }
        }
        preferences.edit { it[presetsKey] = encodePresets(updated) }
        current.copy(presets = updated)
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

    override suspend fun submit(text: String, url: String?): CaptureSubmitResult = withContext(Dispatchers.IO) {
        val destination = currentDestinationOnWorker() ?: return@withContext CaptureSubmitResult.DestinationRequired
        val normalizedText = text.trimEnd()
        val normalizedURL = url?.trim()?.takeIf(String::isNotEmpty)
        if (normalizedText.length > MAX_TEXT_CHARACTERS) {
            return@withContext CaptureSubmitResult.InvalidInput("Capture text must be 65,536 characters or fewer.")
        }
        if (normalizedText.isBlank() && normalizedURL == null) {
            return@withContext CaptureSubmitResult.InvalidInput("Write something or add a link before sending.")
        }
        if (normalizedURL != null && !isHttpURL(normalizedURL)) {
            return@withContext CaptureSubmitResult.InvalidInput("Enter a complete http:// or https:// link.")
        }

        val requestID = UUID.randomUUID().toString().lowercase()
        val preset = presetCollectionFrom(preferences.data.first()).activePreset
        val requestBytes = requestBytes(requestID, normalizedText, normalizedURL, clock(), preset)
        when (val enqueued = store.enqueue(requestBytes, clock())) {
            is EnqueueResult.SavedLocally -> Unit
            is EnqueueResult.CorrelationConflict -> return@withContext CaptureSubmitResult.SavedForRetry(requestID, "correlationConflict", durablySaved = false)
            is EnqueueResult.DurabilityFailure -> return@withContext CaptureSubmitResult.SavedForRetry(requestID, enqueued.coarseCode, durablySaved = false)
            is EnqueueResult.ExistingPackageCorrupt -> return@withContext CaptureSubmitResult.SavedForRetry(requestID, enqueued.coarseCode, durablySaved = false)
            is EnqueueResult.IndexFailure -> return@withContext CaptureSubmitResult.SavedForRetry(requestID, enqueued.coarseCode)
        }
        clearDraftOnWorker()

        val installationID = quota.initializeInstallation(UUID.randomUUID().toString().lowercase(), clock())
        val reservation = when (val result = quota.reserve(requestID, UUID.randomUUID().toString().lowercase(), clock())) {
            is QuotaReservationResult.Reserved -> result.token
            is QuotaReservationResult.Existing -> result.token
            QuotaReservationResult.AlreadyCommitted -> return@withContext CaptureSubmitResult.Delivered(requestID)
            QuotaReservationResult.LimitReached -> return@withContext CaptureSubmitResult.LimitReached(requestID)
            QuotaReservationResult.InvalidInput -> return@withContext CaptureSubmitResult.SavedForRetry(requestID, "quotaReservation")
        }
        drive(requestID, destination, installationID, reservation)
    }

    override suspend fun retry(requestID: String): CaptureSubmitResult = withContext(Dispatchers.IO) {
        retryOnWorker(requestID)
    }

    override suspend fun reconcile(): List<CaptureHistoryItem> = withContext(Dispatchers.IO) {
        store.reconcile()
        historyOnWorker()
    }

    override suspend fun history(): List<CaptureHistoryItem> = withContext(Dispatchers.IO) { historyOnWorker() }

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
        val destination = currentDestinationOnWorker() ?: return CaptureSubmitResult.DestinationRequired
        val snapshot = store.loadJournal(requestID) ?: return CaptureSubmitResult.InvalidInput("Capture is no longer available.")
        if (snapshot.state == CaptureState.COMPLETED) return CaptureSubmitResult.Delivered(requestID)
        val installationID = quota.initializeInstallation(UUID.randomUUID().toString().lowercase(), clock())
        val reservation = when (val result = quota.reserve(requestID, UUID.randomUUID().toString().lowercase(), clock())) {
            is QuotaReservationResult.Reserved -> result.token
            is QuotaReservationResult.Existing -> result.token
            QuotaReservationResult.AlreadyCommitted -> return CaptureSubmitResult.Delivered(requestID)
            QuotaReservationResult.LimitReached -> return CaptureSubmitResult.LimitReached(requestID)
            QuotaReservationResult.InvalidInput -> return CaptureSubmitResult.SavedForRetry(requestID, "quotaReservation")
        }
        return drive(requestID, destination, installationID, reservation)
    }

    private fun drive(
        requestID: String,
        selectedDestination: CaptureDestination,
        installationID: String,
        reservationToken: String,
    ): CaptureSubmitResult {
        val leaseToken = UUID.randomUUID().toString().lowercase()
        val lease = coordination.acquire(requestID, leaseToken, clock(), LEASE_DURATION_MILLIS)
        if (lease !is LeasePlan.Grant && lease !is LeasePlan.Current) {
            return CaptureSubmitResult.SavedForRetry(requestID, "captureBusy")
        }
        val destination = VaultDestination(selectedDestination.id, selectedDestination.treeUri)
        val gateway = AndroidSafDocumentsGateway(appContext)
        val materializer = CoreMaterializationCoordinator(
            bridge = bridge,
            store = store,
            coordinator = coordination,
            occupancy = SafCandidateOccupancy(gateway, destination),
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
                                finalizeQuota(requestID, selectedDestination.id, installationID, reservationToken, outcome.receiptID)
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

                    CaptureState.COMPLETED -> return CaptureSubmitResult.Delivered(requestID)
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

    private fun finalizeQuota(
        requestID: String,
        destinationID: String,
        installationID: String,
        reservationToken: String,
        receiptID: String,
    ) {
        val snapshot = store.loadJournal(requestID) ?: return
        val info = (bridge.buildInfo() as? CoreResult.Success)?.value ?: return
        quota.commitTerminal(
            reservationToken,
            TombstoneDraft(
                requestID = requestID,
                installationID = installationID,
                completedAtEpochMillis = clock(),
                destinationID = destinationID,
                receiptID = receiptID,
                packageVersion = 1,
                journalVersion = 1,
                requestContractVersion = 1,
                finalJournalRevision = snapshot.revision,
                coreVersion = info.coreVersion,
                rendererVersion = RENDERER_REVISION,
                profileID = PROFILE_ID,
                profileVersion = 1,
            ),
        )
    }

    private fun historyOnWorker(): List<CaptureHistoryItem> = index.all()
        .map {
            CaptureHistoryItem(
                requestID = it.requestID,
                createdAtEpochMillis = it.createdAtEpochMillis,
                updatedAtEpochMillis = it.updatedAtEpochMillis,
                state = it.state,
                attemptCount = it.attemptCount,
            )
        }
        .sortedByDescending(CaptureHistoryItem::updatedAtEpochMillis)

    private suspend fun currentDestinationOnWorker(): CaptureDestination? = destinationFrom(preferences.data.first())

    private fun draftFrom(values: Preferences): CaptureDraft = CaptureDraft(
        text = values[draftTextKey].orEmpty().take(MAX_TEXT_CHARACTERS),
        url = values[draftURLKey]?.take(MAX_URL_CHARACTERS)?.takeIf(::isHttpURL),
        updatedAtEpochMillis = values[draftUpdatedAtKey]?.coerceAtLeast(0L) ?: 0L,
    )

    private suspend fun clearDraftOnWorker() {
        preferences.edit { values ->
            values.remove(draftTextKey)
            values.remove(draftURLKey)
            values[draftUpdatedAtKey] = clock()
        }
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
        val active = requestedActive?.takeIf { id -> presets.any { it.id == id } } ?: DEFAULT_PRESET_ID
        return CapturePresetCollection(active, presets)
    }

    private fun encodePresets(presets: List<CapturePreset>): String = CapturePackageCodec.canonical(
        buildJsonObject {
            put("presets", JsonArray(presets.map(::encodePreset)))
            put("version", 1)
        },
    ).toString(StandardCharsets.UTF_8)

    private fun encodePreset(preset: CapturePreset): JsonObject = buildJsonObject {
        put("id", preset.id)
        put("logicalFolder", preset.logicalFolder)
        put("metadataFields", JsonArray(preset.metadataFields.map { field ->
            buildJsonObject {
                put("name", field.name)
                put("value", field.value)
            }
        }))
        put("name", preset.name)
        put("noteNameTemplate", preset.noteNameTemplate)
        put("revision", preset.revision)
        put("symbol", preset.symbol)
    }

    private fun decodePresets(value: String): List<CapturePreset> = runCatching {
        val root = Json.parseToJsonElement(value).jsonObject
        require(root["version"]?.jsonPrimitive?.intOrNull == 1)
        root.getValue("presets").jsonArray.map { raw ->
            val preset = raw.jsonObject
            normalizePreset(
                CapturePreset(
                    id = preset.getValue("id").jsonPrimitive.content,
                    name = preset.getValue("name").jsonPrimitive.content,
                    symbol = preset.getValue("symbol").jsonPrimitive.content,
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
                ),
            )
        }.distinctBy(CapturePreset::id)
    }.getOrDefault(emptyList())

    private fun normalizePreset(preset: CapturePreset): CapturePreset {
        require(PRESET_UUID_PATTERN.matches(preset.id)) { "invalidPresetID" }
        val name = preset.name.trim()
        require(name.length in 1..64) { "invalidPresetName" }
        val symbol = preset.symbol.trim()
        require(symbol.codePointCount(0, symbol.length) in 1..32 && symbol.length <= 64) { "invalidPresetSymbol" }
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
        return preset.copy(
            name = name,
            symbol = symbol,
            revision = preset.revision.coerceAtLeast(1),
            logicalFolder = segments.joinToString("/"),
            noteNameTemplate = noteNameTemplate,
            metadataFields = fields,
        )
    }

    private fun isSafePathSegment(value: String): Boolean =
        value.length in 1..255 && value !in setOf(".", "..") && value.none { it == '/' || it == '\\' || it == '\u0000' }

    private fun requestBytes(
        requestID: String,
        text: String,
        url: String?,
        createdAt: Long,
        preset: CapturePreset,
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
        }
        val presetWithoutHash = presetSnapshot(preset, ZERO_SHA)
        val presetHash = CapturePackageCodec.sha256(CapturePackageCodec.canonical(presetWithoutHash))
        return CapturePackageCodec.canonical(buildJsonObject {
            put("calendar", "gregorian")
            put("captureSource", "app")
            put("contractVersion", 1)
            put("createdAtEpochMilliseconds", createdAt)
            put("invocation", buildJsonObject {
                put("locationOutcome", "notRequested")
                put("originRecordingID", JsonNull)
                put("sequence", 1)
            })
            put("locale", Locale.getDefault().toLanguageTag().ifBlank { "en-US" })
            put("operation", "newNote")
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
        put("metadataPolicy", buildJsonObject {
            put("finalNewline", true)
            put("frontmatterMode", if (preset.metadataFields.isEmpty()) "none" else "merge")
            put("lineEnding", "lf")
            put("orderedFields", JsonArray(preset.metadataFields.map { field ->
                buildJsonObject {
                    put("name", field.name)
                    put("value", field.value)
                }
            }))
            put("templatePolicy", "none")
        })
        put("retryMarkerPolicy", "none")
        put("revision", preset.revision)
        put("routePolicy", buildJsonObject {
            put("attachmentFolder", JsonArray(emptyList()))
            put("collisionPolicy", "deterministicSuffix")
            put("extensionPolicy", "markdownDotMd")
            put("logicalFolder", JsonArray(preset.logicalFolder.split('/').map(::JsonPrimitive)))
            put("noteNameTemplate", preset.noteNameTemplate)
        })
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
        val activePresetIDKey = stringPreferencesKey("capture.preset.active-id")
        val presetsKey = stringPreferencesKey("capture.presets.v1")
        const val CORE_VERSION = "0.1.0-alpha.1"
        const val RENDERER_REVISION = "swift-legacy-m0"
        const val PROFILE_ID = "apple-parity-v1"
        const val DEFAULT_PRESET_ID = "33333333-3333-4333-8333-333333333333"
        const val ZERO_SHA = "0000000000000000000000000000000000000000000000000000000000000000"
        const val MAX_TEXT_CHARACTERS = 65_536
        const val MAX_URL_CHARACTERS = 8_192
        const val MAX_DRIVE_STEPS = 8
        const val MAX_DRAIN_ITEMS = 32
        const val MAX_PRESETS = 24
        const val MAX_METADATA_FIELDS = 16
        const val LEASE_DURATION_MILLIS = 10 * 60 * 1_000L
        val PRESET_UUID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        val METADATA_NAME_PATTERN = Regex("^[A-Za-z0-9_-]{1,64}$")
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
