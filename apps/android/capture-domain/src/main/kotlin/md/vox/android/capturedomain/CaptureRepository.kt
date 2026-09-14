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

enum class CaptureMetadataScope { DOCUMENT, ENTRY }

enum class CaptureNoteTargetKind { NEW_NOTE, ROLLING_NOTE, EXISTING_NOTE }

enum class CaptureRollingPeriod { DAILY, WEEKLY, MONTHLY, QUARTERLY, YEARLY }

enum class CapturePlacementKind { APPEND, PREPEND, BENEATH_HEADING }

enum class CaptureMissingHeadingBehavior { FAIL, CREATE }

enum class CaptureProcessingMode { NONE, CLEAN, TODO_LIST, MEETING_NOTES, CUSTOM }

enum class CaptureProcessingScope { BOTH, VOICE_ONLY, TEXT_ONLY }

enum class CaptureLocationPrecision { EXACT, CITY }

enum class CaptureLocationUnavailableBehavior { ASK, SEND_WITHOUT_LOCATION, CANCEL }

enum class CaptureLocationUnavailableReason(val wireName: String) {
    PERMISSION_DENIED("permissionDenied"),
    RESTRICTED("restricted"),
    NOT_DETERMINED("notDetermined"),
    REDUCED_ACCURACY("reducedAccuracy"),
    TIMEOUT("timeout"),
    CANCELLED("cancelled"),
    UNAVAILABLE("unavailable"),
}

enum class CaptureLocationField(val wireName: String, val displayName: String) {
    COORDINATES("coordinates", "Coordinates"),
    LATITUDE("latitude", "Latitude"),
    LONGITUDE("longitude", "Longitude"),
    PLACE("place", "Place"),
    CITY("city", "City"),
    REGION("region", "Region"),
    COUNTRY("country", "Country"),
    APPLE_MAPS_URL("appleMapsURL", "Apple Maps URL"),
    GOOGLE_MAPS_URL("googleMapsURL", "Google Maps URL"),
    OPEN_STREET_MAP_URL("openStreetMapURL", "OpenStreetMap URL"),
    GEO_URI("geoURI", "geo URI"),
    ACCURACY("accuracy", "Accuracy"),
    TIMESTAMP("timestamp", "Timestamp"),
    SOURCE("source", "Source"),
    ID("id", "Capture ID"),
}

data class CaptureLocationStructuredField(
    val field: CaptureLocationField,
    val outputKey: String = field.wireName,
)

enum class CaptureLocationOutputMode { STRUCTURED_FIELDS, ADVANCED_YAML }

enum class CaptureLocationLabelLookupClass(val wireName: String) {
    NONE("none"),
    OFFLINE("offline"),
    SYSTEM_MAY_USE_NETWORK("systemMayUseNetwork"),
}

enum class CaptureLocationLabelOutcome(val wireName: String) {
    NOT_REQUESTED("notRequested"),
    UNAVAILABLE("unavailable"),
    FROZEN("frozen"),
}

const val CURRENT_LOCATION_LABEL_CONSENT_VERSION = 1

data class CaptureLocationLabel(
    val place: String? = null,
    val city: String? = null,
    val region: String? = null,
    val country: String? = null,
) {
    val isEmpty: Boolean get() = listOf(place, city, region, country).all { it.isNullOrBlank() }
}

data class CaptureLocationLabelObservation(
    val requested: Boolean,
    val lookupClass: CaptureLocationLabelLookupClass,
    val consentVersion: Int?,
    val outcome: CaptureLocationLabelOutcome,
) {
    companion object {
        val NOT_REQUESTED = CaptureLocationLabelObservation(
            requested = false,
            lookupClass = CaptureLocationLabelLookupClass.NONE,
            consentVersion = null,
            outcome = CaptureLocationLabelOutcome.NOT_REQUESTED,
        )
    }
}

sealed interface CaptureLocationOutcome {
    data object NotRequested : CaptureLocationOutcome
    data class Unavailable(
        val reason: CaptureLocationUnavailableReason,
        val attemptedAtEpochMillis: Long,
        val labelObservation: CaptureLocationLabelObservation = CaptureLocationLabelObservation.NOT_REQUESTED,
    ) : CaptureLocationOutcome
    data class Available(
        val snapshot: CaptureLocationSnapshot,
        val labelObservation: CaptureLocationLabelObservation = CaptureLocationLabelObservation.NOT_REQUESTED,
    ) : CaptureLocationOutcome
}

/** Request-scoped, privacy-adjusted location frozen before durable enqueue. */
data class CaptureLocationSnapshot(
    val latitudeE6: Long,
    val longitudeE6: Long,
    val accuracyMillimeters: Long?,
    val capturedAtEpochMillis: Long,
    val precision: CaptureLocationPrecision,
    val source: String,
    val label: CaptureLocationLabel? = null,
)

enum class CaptureAudioSaveMode { OFF, ALONGSIDE_NOTE, ATTACHMENTS_FOLDER }

enum class CaptureAudioEmbedPlacement { BEFORE_TEXT, AFTER_TEXT }

enum class CaptureWatchOutputMode { TRANSCRIBE_AND_CAPTURE, RECORDING_ONLY }

enum class CaptureExportFileFormat { TEXT, MARKDOWN, JSON, YAML }

enum class CaptureExportFileMode { NEW_FILE, APPEND }

enum class CaptureExportYAMLProperty { ID, TEXT, DATE, DURATION, MODEL_USED, LANGUAGE }

data class CapturePresetExportSettings(
    /** False for presets migrated from builds that only supported manual document export. */
    val usesCustomExportSettings: Boolean = false,
    val exportEnabled: Boolean = true,
    val format: CaptureExportFileFormat = CaptureExportFileFormat.MARKDOWN,
    val mode: CaptureExportFileMode = CaptureExportFileMode.NEW_FILE,
    val destinationTreeUri: String? = null,
    val destinationName: String = "",
    val newFileNameTemplate: String = "voxboard-{timestamp}-{id8}",
    val appendFileName: String = "voxboard-transcripts",
    val markdownTemplateEnabled: Boolean = false,
    val markdownTemplateUri: String? = null,
    val markdownTemplateName: String = "",
    val mdObsidianEnabled: Boolean = false,
    val yamlUsesMarkdownExtension: Boolean = false,
    val yamlProperties: Set<CaptureExportYAMLProperty> = CaptureExportYAMLProperty.entries.toSet(),
    val embedAudioInMarkdown: Boolean = false,
    val audioEmbedPlacement: CaptureAudioEmbedPlacement = CaptureAudioEmbedPlacement.AFTER_TEXT,
)

object CaptureMeteringPolicy {
    /** Voice/recording captures consume transcription allowance, never the text Capture allowance. */
    fun chargesFreeCaptureAllowance(originRecordingID: String?, hasUnlimitedAccess: Boolean): Boolean =
        originRecordingID == null && !hasUnlimitedAccess
}

data class CapturePresetLocationPolicy(
    val isEnabled: Boolean = false,
    val precision: CaptureLocationPrecision = CaptureLocationPrecision.EXACT,
    val unavailableBehavior: CaptureLocationUnavailableBehavior = CaptureLocationUnavailableBehavior.ASK,
    val metadataOutputEnabled: Boolean = false,
    val outputMode: CaptureLocationOutputMode = CaptureLocationOutputMode.STRUCTURED_FIELDS,
    val structuredFields: List<CaptureLocationStructuredField> = DEFAULT_CAPTURE_LOCATION_FIELDS,
    val collectionKey: String = "locations",
    val advancedTemplate: String = "",
    val labelLookupClass: CaptureLocationLabelLookupClass = CaptureLocationLabelLookupClass.NONE,
    val labelConsentVersion: Int? = null,
) {
    val requiresLabels: Boolean
        get() {
            if (!isEnabled || !metadataOutputEnabled) return false
            val labelFields = setOf(
                CaptureLocationField.PLACE,
                CaptureLocationField.CITY,
                CaptureLocationField.REGION,
                CaptureLocationField.COUNTRY,
            )
            return when (outputMode) {
                CaptureLocationOutputMode.STRUCTURED_FIELDS -> structuredFields.any { it.field in labelFields }
                CaptureLocationOutputMode.ADVANCED_YAML -> listOf("place", "city", "region", "country").any { field ->
                    Regex("\\{\\{\\s*$field\\s*}}", RegexOption.IGNORE_CASE).containsMatchIn(advancedTemplate)
                }
            }
        }

    val hasValidSystemLabelConsent: Boolean
        get() = labelLookupClass == CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK &&
            labelConsentVersion == CURRENT_LOCATION_LABEL_CONSENT_VERSION
}

val DEFAULT_CAPTURE_LOCATION_FIELDS = listOf(
    CaptureLocationStructuredField(CaptureLocationField.COORDINATES),
    CaptureLocationStructuredField(CaptureLocationField.PLACE),
    CaptureLocationStructuredField(CaptureLocationField.APPLE_MAPS_URL),
    CaptureLocationStructuredField(CaptureLocationField.TIMESTAMP),
    CaptureLocationStructuredField(CaptureLocationField.SOURCE),
    CaptureLocationStructuredField(CaptureLocationField.ID),
)

data class CapturePreset(
    val id: String,
    val name: String,
    val symbol: String,
    /** Validated single-emoji identity that replaces the symbol icon wherever rendered. */
    val emoji: String? = null,
    val revision: Int,
    val logicalFolder: String,
    val noteNameTemplate: String,
    val metadataFields: List<CaptureMetadataField>,
    val isEnabled: Boolean = true,
    val isPinned: Boolean = false,
    val noteTargetKind: CaptureNoteTargetKind = CaptureNoteTargetKind.NEW_NOTE,
    val rollingPeriod: CaptureRollingPeriod = CaptureRollingPeriod.DAILY,
    val existingNotePath: String = "",
    val placement: CapturePlacementKind = CapturePlacementKind.APPEND,
    val headingTitle: String = "",
    val headingLevel: Int = 1,
    val missingHeadingBehavior: CaptureMissingHeadingBehavior = CaptureMissingHeadingBehavior.FAIL,
    val entryPrefix: String = "",
    val entrySuffix: String = "",
    /** Reusable entry template bound to this preset. Prefix/suffix remain its safe last-known snapshot. */
    val entryTemplateID: String? = null,
    val attachmentsFolder: String = "Attachments",
    val retryProtectionEnabled: Boolean = false,
    val metadataScope: CaptureMetadataScope = CaptureMetadataScope.DOCUMENT,
    val speakerDiarizationEnabled: Boolean = false,
    val processingEnabled: Boolean = false,
    val processingMode: CaptureProcessingMode = CaptureProcessingMode.CLEAN,
    val processingScope: CaptureProcessingScope = CaptureProcessingScope.BOTH,
    val customProcessingInstruction: String = "",
    val capturePrompt: String = "",
    val generateImageAltText: Boolean = false,
    val locationPolicy: CapturePresetLocationPolicy = CapturePresetLocationPolicy(),
    val audioSaveMode: CaptureAudioSaveMode = CaptureAudioSaveMode.OFF,
    val embedAudioInMarkdown: Boolean = false,
    val audioEmbedPlacement: CaptureAudioEmbedPlacement = CaptureAudioEmbedPlacement.AFTER_TEXT,
    val watchOutputMode: CaptureWatchOutputMode = CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE,
    val exportSettings: CapturePresetExportSettings = CapturePresetExportSettings(),
)

data class CaptureEntryTemplate(
    val id: String,
    val name: String,
    val entryPrefix: String = "",
    val entrySuffix: String = "",
)

/**
 * Resolves the live reusable template at the capture boundary. A one-shot override wins over
 * the preset binding; missing templates deliberately fall back to the preset's inline snapshot.
 */
fun CapturePreset.resolvingEntryTemplate(
    templates: List<CaptureEntryTemplate>,
    oneShotOverrideID: String? = null,
): CapturePreset {
    val requestedID = oneShotOverrideID ?: entryTemplateID ?: return this
    val template = templates.firstOrNull { it.id == requestedID } ?: return this
    return copy(entryPrefix = template.entryPrefix, entrySuffix = template.entrySuffix)
}

data class CapturePresetCollection(
    val activePresetID: String,
    val presets: List<CapturePreset>,
) {
    val activePreset: CapturePreset
        get() = presets.firstOrNull { it.id == activePresetID && it.isEnabled }
            ?: presets.firstOrNull(CapturePreset::isEnabled)
            ?: presets.first()
}

data class CaptureDraft(
    val text: String,
    val url: String?,
    val updatedAtEpochMillis: Long,
    val captureSource: String = "app",
    val attachments: List<CaptureAttachment> = emptyList(),
    val originRecordingID: String? = null,
    val frozenPreset: CapturePreset? = null,
    val entryTemplateIDOverride: String? = null,
)

/** App-owned, hash-verified copy of a provider attachment in the current durable draft. */
data class CaptureAttachment(
    val id: String,
    val displayName: String,
    val vaultFileName: String,
    val mediaType: String,
    val byteCount: Long,
    val sha256: String,
    val includeInMarkdown: Boolean = true,
) {
    val isImage: Boolean get() = mediaType.startsWith("image/")
}

enum class CaptureBarAction(val persistedName: String, val displayName: String) {
    ADD_MEDIA("addMedia", "Add Media"),
    ADD_FILES("addFiles", "Add Files"),
    SCAN_DOCUMENT("scanDocument", "Scan Document"),
    EXTRACT_TEXT("extractText", "Extract Text"),
    UNDO("undo", "Undo"),
    FORMAT_MARKDOWN("formatMarkdown", "Format Markdown"),
    MARKDOWN_LINK("markdownLink", "Markdown Link"),
    DUE_DATE("dueDate", "Set Due Date"),
    CHECKLIST("checklist", "Checklist"),
    BULLET_LIST("bulletList", "Bullet List"),
    PASTE("paste", "Paste"),
    INTERNAL_LINK("internalLink", "Internal Link"),
    SKETCH("sketch", "Sketch"),
    CURRENT_LOCATION("currentLocation", "Current Location"),
    TIMESTAMP("timestamp", "Insert Timestamp"),
    DATE("date", "Insert Date"),
    TEXT_CASE("textCase", "Change Text Case"),
}

data class CaptureBarConfiguration(
    val orderedActions: List<CaptureBarAction> = CaptureBarAction.entries,
    val hiddenActions: Set<CaptureBarAction> = emptySet(),
    val usesTwentyFourHourTimestamps: Boolean = false,
    val confirmsVoiceNotesBeforeAdding: Boolean = false,
) {
    val visibleActions: List<CaptureBarAction>
        get() = orderedActions.filterNot(hiddenActions::contains)
}

fun CaptureBarConfiguration.normalized(): CaptureBarConfiguration {
    val order = buildList {
        orderedActions.distinct().forEach(::add)
        CaptureBarAction.entries.filterNot { it in this }.forEach(::add)
    }
    return copy(
        orderedActions = order,
        hiddenActions = hiddenActions.intersect(CaptureBarAction.entries.toSet()),
    )
}

data class CaptureHistoryItem(
    val requestID: String,
    val createdAtEpochMillis: Long,
    val updatedAtEpochMillis: Long,
    val state: CaptureState,
    val attemptCount: Int,
    val title: String? = null,
    val snippet: String? = null,
    val logicalPath: String? = null,
    val captureSource: String = "app",
    val attachmentCount: Int = 0,
)

data class CaptureHistoryDetail(
    val requestID: String,
    val createdAtEpochMillis: Long,
    val state: CaptureState,
    val capturedText: String,
    val capturedURL: String?,
    val presetID: String,
    val logicalPath: String?,
    val preparedMarkdown: String?,
    val captureSource: String = "app",
    val attachments: List<CaptureAttachment> = emptyList(),
    val originalCapturedText: String? = null,
    val processingMode: CaptureProcessingMode? = null,
    val processingOutcome: CaptureTextProcessingOutcome? = null,
    val processingNotice: String? = null,
)

data class CaptureDrainSummary(
    val inspected: Int,
    val delivered: Int,
    val retryable: Int,
    val needsPermission: Int,
    val blocked: Int,
)

data class ActivityDay(
    val epochDay: Long,
    val captureCount: Int,
    val recordingCount: Int,
)

data class ActivityStats(
    val recordingCount: Int,
    val captureCount: Int,
    val recordedDurationMillis: Long,
    val attachmentCount: Int,
    val lastSevenDays: List<ActivityDay>,
    val captureSources: Map<String, Int>,
) {
    companion object {
        val Empty = ActivityStats(0, 0, 0, 0, emptyList(), emptyMap())
    }
}

data class CompletedRecordingActivity(
    val sessionID: String,
    val completedAtEpochMillis: Long,
    val durationMillis: Long,
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
    suspend fun saveDraft(text: String, url: String?, captureSource: String = "app"): CaptureDraft
    suspend fun addDraftAttachment(
        contentUri: String,
        displayName: String?,
        mediaType: String?,
        includeInMarkdown: Boolean = true,
    ): CaptureDraft
    suspend fun prepareVoiceDraft(
        text: String,
        url: String?,
        originRecordingID: String,
        audioContentUri: String?,
        audioDisplayName: String?,
        frozenPreset: CapturePreset?,
    ): CaptureDraft
    suspend fun removeDraftAttachment(attachmentID: String): CaptureDraft
    suspend fun captureBarConfiguration(): CaptureBarConfiguration
    suspend fun saveCaptureBarConfiguration(configuration: CaptureBarConfiguration): CaptureBarConfiguration
    /** Collapsed by default; independent of preset edits so resetting presets never discards it. */
    suspend fun presetQuickAccessRailExpanded(): Boolean
    suspend fun setPresetQuickAccessRailExpanded(expanded: Boolean)
    suspend fun capturePresets(): CapturePresetCollection
    suspend fun selectCapturePreset(presetID: String): CapturePresetCollection
    suspend fun saveCapturePreset(preset: CapturePreset): CapturePresetCollection
    suspend fun deleteCapturePreset(presetID: String): CapturePresetCollection
    suspend fun entryTemplates(): List<CaptureEntryTemplate>
    suspend fun saveEntryTemplate(template: CaptureEntryTemplate): List<CaptureEntryTemplate>
    suspend fun deleteEntryTemplate(templateID: String): List<CaptureEntryTemplate>
    suspend fun setDraftEntryTemplateOverride(templateID: String?): CaptureDraft
    suspend fun submit(
        text: String,
        url: String?,
        locationOutcome: CaptureLocationOutcome = CaptureLocationOutcome.NotRequested,
    ): CaptureSubmitResult
    /**
     * Submits a frozen recording without mutating or clearing the user's interactive draft.
     * The recording ID is also the idempotent Capture request ID for crash-safe replay.
     */
    suspend fun submitRecording(
        text: String,
        url: String?,
        originRecordingID: String,
        audioContentUri: String?,
        audioDisplayName: String?,
        frozenPreset: CapturePreset,
        captureSource: String,
        locationOutcome: CaptureLocationOutcome = CaptureLocationOutcome.NotRequested,
    ): CaptureSubmitResult
    suspend fun retry(requestID: String): CaptureSubmitResult
    suspend fun reconcile(): List<CaptureHistoryItem>
    suspend fun history(): List<CaptureHistoryItem>
    suspend fun historyDetail(requestID: String): CaptureHistoryDetail?
    suspend fun deleteCompletedHistory(requestIDs: Set<String>): Int
    suspend fun activityStats(): ActivityStats
    suspend fun recordCompletedRecordings(recordings: List<CompletedRecordingActivity>): ActivityStats
    suspend fun drainPending(maxItems: Int): CaptureDrainSummary
}
