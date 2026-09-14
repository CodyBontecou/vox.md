package md.vox.android.data

import kotlinx.serialization.json.*
import md.vox.android.capturedomain.*
import java.security.MessageDigest
import java.time.DateTimeException
import java.time.ZoneId

internal const val CONTROL_LIMIT_BYTES = 1_048_576
internal const val AGGREGATE_LIMIT_BYTES = 268_435_456L
internal const val JOURNAL_EVENT_LIMIT = 1024
internal val UUID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
internal val SHA_PATTERN = Regex("^[0-9a-f]{64}$")
private const val CURRENT_CORE = "0.1.0-alpha.1"
private const val CURRENT_RENDERER = "swift-legacy-m0"
private const val CURRENT_PROFILE = "apple-parity-v1"
private const val ZERO_SHA = "0000000000000000000000000000000000000000000000000000000000000000"

class PackageCodecException(val coarseCode: String) : IllegalArgumentException(coarseCode)
data class AssetManifestEntry(
    val sourceID: String,
    val fileName: String,
    val mediaType: String,
    val length: Long,
    val sha256: String,
)
data class AssetManifest(val requestID: String, val assets: List<AssetManifestEntry> = emptyList())
data class AdmittedRequest(
    val requestID: String,
    val createdAtEpochMillis: Long,
    val captureSource: String,
    val originRecordingID: String?,
)
data class JournalBinding(
    val packageVersion: Int,
    val requestContractVersion: Int,
    val assetManifestVersion: Int,
    val requestByteCount: Long,
    val requestSHA256: String,
    val assetManifestByteCount: Long,
    val assetManifestSHA256: String,
)
data class DecodedJournal(val snapshot: JournalSnapshot, val binding: JournalBinding)

/** Strict production codec for governed package bytes. */
object CapturePackageCodec {
    private val json = Json { isLenient = false; ignoreUnknownKeys = false; allowSpecialFloatingPointValues = false }

    fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
    fun canonical(element: JsonElement): ByteArray = (canonicalText(element, 0) + "\n").toByteArray(Charsets.UTF_8)

    fun parseCanonical(bytes: ByteArray): JsonObject {
        if (bytes.isEmpty() || bytes.size > CONTROL_LIMIT_BYTES) fail("controlBounds")
        if (bytes.last() != '\n'.code.toByte()) fail("nonCanonical")
        val element = try { json.parseToJsonElement(bytes.toString(Charsets.UTF_8)) } catch (_: Exception) { fail("malformedJson") }
        if (element !is JsonObject || !canonical(element).contentEquals(bytes)) fail("nonCanonical")
        return element
    }

    fun encodeAssets(value: AssetManifest): ByteArray {
        requireUUID(value.requestID)
        validateAssetEntries(value.assets)
        return canonical(JsonObject(sortedMapOf(
            "assetCount" to JsonPrimitive(value.assets.size),
            "assets" to JsonArray(value.assets.map { asset ->
                JsonObject(sortedMapOf(
                    "fileName" to JsonPrimitive(asset.fileName),
                    "length" to JsonPrimitive(asset.length),
                    "mediaType" to JsonPrimitive(asset.mediaType),
                    "sha256" to JsonPrimitive(asset.sha256),
                    "sourceID" to JsonPrimitive(asset.sourceID),
                ))
            }),
            "requestID" to JsonPrimitive(value.requestID),
            "schemaVersion" to JsonPrimitive(1),
        )))
    }

    fun decodeAssets(bytes: ByteArray): AssetManifest {
        val obj = parseCanonical(bytes); exactKeys(obj, setOf("assetCount", "assets", "requestID", "schemaVersion"))
        if (integer(obj, "schemaVersion") != 1L) fail("assetManifestProfile")
        val encoded = array(obj, "assets")
        if (integer(obj, "assetCount") != encoded.size.toLong()) fail("assetManifestProfile")
        val assets = encoded.map { raw ->
            val asset = raw as? JsonObject ?: fail("assetManifestShape")
            exactKeys(asset, setOf("fileName", "length", "mediaType", "sha256", "sourceID"))
            AssetManifestEntry(
                sourceID = string(asset, "sourceID"),
                fileName = string(asset, "fileName"),
                mediaType = string(asset, "mediaType"),
                length = integer(asset, "length"),
                sha256 = string(asset, "sha256"),
            )
        }
        validateAssetEntries(assets)
        return AssetManifest(string(obj, "requestID").also(::requireUUID), assets)
    }

    private fun validateAssetEntries(assets: List<AssetManifestEntry>) {
        if (assets.size > 32 || assets.map(AssetManifestEntry::sourceID).distinct().size != assets.size ||
            assets.map(AssetManifestEntry::fileName).distinct().size != assets.size
        ) fail("assetManifestProfile")
        var aggregate = 0L
        assets.forEach { asset ->
            requireUUID(asset.sourceID)
            if (!safeAssetFileName(asset.fileName)) fail("assetManifestShape")
            if (asset.mediaType.length !in 1..127 || '\n' in asset.mediaType || '\r' in asset.mediaType) fail("assetManifestShape")
            if (asset.length !in 1..104_857_600L) fail("assetBounds")
            requireSha(asset.sha256)
            aggregate = try { Math.addExact(aggregate, asset.length) } catch (_: ArithmeticException) { fail("assetBounds") }
        }
        if (aggregate > AGGREGATE_LIMIT_BYTES - CONTROL_LIMIT_BYTES) fail("assetBounds")
    }

    internal fun safeAssetFileName(value: String): Boolean =
        value.codePointCount(0, value.length) in 1..255 &&
            value !in setOf(".", "..") &&
            !value.startsWith('.') &&
            value.none { it == '/' || it == '\\' || it == '\u0000' || it == '\n' || it == '\r' }

    fun encodeJournal(snapshot: JournalSnapshot, requestBytes: ByteArray, assetBytes: ByteArray): ByteArray {
        requireUUID(snapshot.requestID)
        if (snapshot.events.isEmpty() || snapshot.events.size > JOURNAL_EVENT_LIMIT) fail("eventBounds")
        var replay: JournalSnapshot? = null
        snapshot.events.forEach { event -> replay = when (val result = CaptureJournalReducer.reduce(snapshot.requestID, replay, event)) {
            is JournalReduction.Accepted -> result.snapshot
            is JournalReduction.Rejected -> fail("journal.${result.reason}")
        } }
        if (replay != snapshot) fail("snapshotFrontierMismatch")
        return canonical(JsonObject(sortedMapOf(
            "assetManifestByteCount" to JsonPrimitive(assetBytes.size), "assetManifestSHA256" to JsonPrimitive(sha256(assetBytes)), "assetManifestVersion" to JsonPrimitive(1),
            "events" to JsonArray(snapshot.events.map(::eventJson)), "journalVersion" to JsonPrimitive(2), "packageVersion" to JsonPrimitive(1),
            "requestByteCount" to JsonPrimitive(requestBytes.size), "requestID" to JsonPrimitive(snapshot.requestID), "requestSHA256" to JsonPrimitive(sha256(requestBytes)), "requestContractVersion" to JsonPrimitive(1),
        )))
    }

    fun decodeJournal(bytes: ByteArray): DecodedJournal {
        val obj = parseCanonical(bytes)
        exactKeys(obj, setOf("assetManifestByteCount", "assetManifestSHA256", "assetManifestVersion", "events", "journalVersion", "packageVersion", "requestByteCount", "requestID", "requestSHA256", "requestContractVersion"))
        if (integer(obj, "journalVersion") != 2L) fail("journalVersion")
        val binding = JournalBinding(integer(obj, "packageVersion").toInt(), integer(obj, "requestContractVersion").toInt(), integer(obj, "assetManifestVersion").toInt(), integer(obj, "requestByteCount"), string(obj, "requestSHA256"), integer(obj, "assetManifestByteCount"), string(obj, "assetManifestSHA256"))
        if (binding.packageVersion != 1 || binding.requestContractVersion != 1 || binding.assetManifestVersion != 1) fail("bindingVersion")
        if (binding.requestByteCount !in 1..CONTROL_LIMIT_BYTES.toLong() || binding.assetManifestByteCount !in 1..CONTROL_LIMIT_BYTES.toLong()) fail("bindingBounds")
        requireSha(binding.requestSHA256); requireSha(binding.assetManifestSHA256)
        val requestID = string(obj, "requestID").also(::requireUUID)
        val encodedEvents = array(obj, "events")
        if (encodedEvents.isEmpty() || encodedEvents.size > JOURNAL_EVENT_LIMIT) fail("eventBounds")
        var snapshot: JournalSnapshot? = null
        encodedEvents.forEach { encoded ->
            val event = decodeEvent(encoded as? JsonObject ?: fail("eventShape"))
            snapshot = when (val reduced = CaptureJournalReducer.reduce(requestID, snapshot, event)) {
                is JournalReduction.Accepted -> reduced.snapshot
                is JournalReduction.Rejected -> fail("journal.${reduced.reason}")
            }
        }
        return DecodedJournal(snapshot!!, binding)
    }

    /** Full v1 validation followed by the narrower current M3 admission profile. */
    fun admitRequest(bytes: ByteArray): AdmittedRequest = decodeRequest(bytes, gateCurrentCore = true)

    /** Historical package decoding validates v1 bytes without comparing an old pin to today's core build. */
    fun decodeHistoricalRequest(bytes: ByteArray): AdmittedRequest = decodeRequest(bytes, gateCurrentCore = false)

    private fun decodeRequest(bytes: ByteArray, gateCurrentCore: Boolean): AdmittedRequest {
        val obj = parseCanonical(bytes)
        exactKeys(obj, setOf("calendar", "captureSource", "contractVersion", "createdAtEpochMilliseconds", "invocation", "locale", "operation", "payloads", "pins", "preset", "requestID", "timezone"))
        if (integer(obj, "contractVersion") != 1L) fail("requestContractVersion")
        val requestID = string(obj, "requestID").also(::requireUUID)
        val source = boundedString(obj, "captureSource", 1, 16)
        val calendar = boundedString(obj, "calendar", 1, 32)
        val operation = boundedString(obj, "operation", 1, 32)
        if (operation !in setOf("newNote", "rollingNote", "existingNoteAppend", "existingNotePrepend", "existingNoteHeading")) fail("operation")
        val created = integer(obj, "createdAtEpochMilliseconds")
        if (created !in 0..4_102_444_800_000L) fail("requestBounds")
        val timezone = boundedString(obj, "timezone", 1, 64)
        try { ZoneId.of(timezone) } catch (_: DateTimeException) { fail("timezone") }
        boundedString(obj, "locale", 2, 35)

        val invocation = objectValue(obj, "invocation"); allowedKeys(
            invocation,
            required = setOf("locationOutcome", "originRecordingID", "sequence"),
            optional = setOf("locationAttemptedAtEpochMilliseconds", "locationLabelObservation", "locationSnapshot", "locationUnavailableReason"),
        )
        val location = boundedString(invocation, "locationOutcome", 1, 32)
        val origin = invocation["originRecordingID"]
        val originRecordingID = if (origin !is JsonNull) string(invocation, "originRecordingID").also(::requireUUID) else null
        val sequence = integer(invocation, "sequence"); if (sequence < 0) fail("invocationBounds")
        if (location !in setOf("notRequested", "unavailable", "coordinatesFrozen", "labelFrozen")) fail("invocationEnum")
        val attemptedAt = invocation["locationAttemptedAtEpochMilliseconds"]
            ?.takeUnless { it is JsonNull }
            ?.let { (it as? JsonPrimitive)?.longOrNull ?: fail("locationAttemptedAt") }
        if (attemptedAt != null && attemptedAt !in 0..4_102_444_800_000L) fail("locationAttemptedAt")
        val unavailableReason = invocation["locationUnavailableReason"]?.takeUnless { it is JsonNull }?.let {
            boundedString(invocation, "locationUnavailableReason", 1, 32).also { reason ->
                if (reason !in LOCATION_UNAVAILABLE_REASONS) fail("locationUnavailableReason")
            }
        }
        val labelObservation = invocation["locationLabelObservation"]?.takeUnless { it is JsonNull }?.let { raw ->
            val observation = raw as? JsonObject ?: fail("locationLabelObservation")
            exactKeys(observation, setOf("consentVersion", "lookupClass", "outcome", "requested"))
            val requested = boolean(observation, "requested")
            val lookupClass = boundedString(observation, "lookupClass", 1, 32)
            val labelOutcome = boundedString(observation, "outcome", 1, 32)
            if (lookupClass !in setOf("none", "offline", "systemMayUseNetwork") ||
                labelOutcome !in setOf("notRequested", "unavailable", "frozen")) fail("locationLabelObservationEnum")
            val consentVersion = observation["consentVersion"]
                ?.takeUnless { it is JsonNull }
                ?.let { (it as? JsonPrimitive)?.longOrNull ?: fail("locationLabelConsent") }
            if (consentVersion != null && consentVersion !in 1..Int.MAX_VALUE.toLong()) fail("locationLabelConsent")
            if (!requested && (lookupClass != "none" || consentVersion != null || labelOutcome != "notRequested")) {
                fail("locationLabelObservationCoherence")
            }
            if (requested && (lookupClass == "none" || labelOutcome == "notRequested")) fail("locationLabelObservationCoherence")
            if ((lookupClass == "systemMayUseNetwork") != (consentVersion != null)) fail("locationLabelConsent")
            observation
        }
        var frozenLabel: JsonObject? = null
        val locationSnapshot = invocation["locationSnapshot"]?.takeUnless { it is JsonNull }?.let { raw ->
            val snapshot = raw as? JsonObject ?: fail("locationSnapshot")
            allowedKeys(
                snapshot,
                required = setOf("accuracyMillimeters", "capturedAtEpochMilliseconds", "latitudeE6", "longitudeE6", "precision", "source"),
                optional = setOf("label"),
            )
            val latitude = integer(snapshot, "latitudeE6")
            val longitude = integer(snapshot, "longitudeE6")
            val capturedAt = integer(snapshot, "capturedAtEpochMilliseconds")
            if (latitude !in -90_000_000L..90_000_000L || longitude !in -180_000_000L..180_000_000L || capturedAt !in 0..4_102_444_800_000L) fail("locationSnapshotBounds")
            val accuracy = snapshot["accuracyMillimeters"]
            if (accuracy !is JsonNull && ((accuracy as? JsonPrimitive)?.longOrNull ?: -1L) !in 0..100_000_000L) fail("locationAccuracy")
            val precision = string(snapshot, "precision")
            if (precision !in setOf("exact", "city") || string(snapshot, "source") !in CURRENT_CAPTURE_SOURCES) fail("locationSnapshotEnum")
            if (precision == "city" && (latitude % 10_000L != 0L || longitude % 10_000L != 0L)) fail("locationCityPrecision")
            frozenLabel = snapshot["label"]?.takeUnless { it is JsonNull }?.let { labelRaw ->
                val label = labelRaw as? JsonObject ?: fail("locationLabel")
                exactKeys(label, setOf("city", "country", "place", "region"))
                val present = listOf("place", "city", "region", "country").count { key ->
                    val value = label[key] ?: fail("locationLabel")
                    if (value is JsonNull) false else {
                        val text = boundedString(label, key, 1, 512)
                        if (text != text.trim()) fail("locationLabel")
                        true
                    }
                }
                if (present == 0 || (precision == "city" && label["place"] !is JsonNull)) fail("locationLabelCoherence")
                label
            }
            snapshot
        }
        if ((location in setOf("coordinatesFrozen", "labelFrozen")) != (locationSnapshot != null)) fail("locationSnapshotCoherence")
        if ((location == "unavailable") != (attemptedAt != null)) fail("locationAttemptedAtCoherence")
        if (unavailableReason != null && location != "unavailable") fail("locationUnavailableReasonCoherence")
        if ((location == "labelFrozen") != (frozenLabel != null)) fail("locationLabelCoherence")
        labelObservation?.let { observation ->
            val outcome = string(observation, "outcome")
            if ((outcome == "frozen") != (frozenLabel != null) || (outcome == "frozen") != (location == "labelFrozen")) {
                fail("locationLabelObservationCoherence")
            }
            if (outcome != "frozen" && frozenLabel != null) fail("locationLabelObservationCoherence")
        }

        val payloads = array(obj, "payloads"); if (payloads.size !in 1..128) fail("payloadBounds")
        val ids = mutableSetOf<String>()
        payloads.forEach { raw ->
            val payload = raw as? JsonObject ?: fail("payloadShape")
            when (string(payload, "kind")) {
                "text" -> { exactKeys(payload, setOf("id", "kind", "text")); boundedString(payload, "text", 0, 65_536) }
                "link" -> { exactKeys(payload, setOf("id", "kind", "label", "url")); boundedString(payload, "label", 0, 4_096); val url = boundedString(payload, "url", 1, 8_192); if (!url.startsWith("http://") && !url.startsWith("https://")) fail("linkUrl") }
                "asset" -> { // Validate the complete tagged shape before the M3 profile rejects it.
                    exactKeys(payload, setOf("id", "kind", "length", "mediaType", "originalNamePolicy", "safeExtension", "sha256", "sourceID"))
                    requireUUID(string(payload, "sourceID")); boundedString(payload, "mediaType", 1, 127)
                    if (integer(payload, "length") !in 0..1_073_741_824L) fail("assetBounds")
                    requireSha(string(payload, "sha256")); val ext = boundedString(payload, "safeExtension", 0, 16)
                    if (!Regex("^[a-z0-9]*$").matches(ext) || string(payload, "originalNamePolicy") !in setOf("discard", "safeStem")) fail("assetShape")
                }
                else -> fail("payloadKind")
            }
            if (!ids.add(string(payload, "id").also(::requireUUID))) fail("duplicatePayload")
        }

        val pins = objectValue(obj, "pins"); exactKeys(pins, setOf("coreVersion", "modelProfileID", "modelRevision", "profileID", "profileVersion", "rendererRevision"))
        val core = boundedString(pins, "coreVersion", 1, 64); val renderer = boundedString(pins, "rendererRevision", 1, 64); val profile = boundedString(pins, "profileID", 1, 64)
        val profileVersion = integer(pins, "profileVersion"); if (profileVersion !in 1..Int.MAX_VALUE.toLong()) fail("pinBounds")
        for (key in listOf("modelProfileID", "modelRevision")) if (pins[key] !is JsonNull) boundedString(pins, key, 1, 64)

        val preset = objectValue(obj, "preset"); allowedKeys(
            preset,
            required = setOf("destinationPolicy", "id", "metadataPolicy", "retryMarkerPolicy", "revision", "routePolicy", "snapshotHash", "templateFreezePoint"),
            optional = setOf("locationPolicy"),
        )
        string(preset, "id").also(::requireUUID); if (integer(preset, "revision") < 0) fail("presetBounds")
        val snapshotHash = string(preset, "snapshotHash").also(::requireSha)
        val zeroed = JsonObject(preset.toMutableMap().also { it["snapshotHash"] = JsonPrimitive(ZERO_SHA) })
        if (sha256(canonical(zeroed)) != snapshotHash) fail("presetSnapshotHash")
        if (string(preset, "templateFreezePoint") != "firstPreparation" || string(preset, "retryMarkerPolicy") !in setOf("none", "voxCaptureCommentV1")) fail("presetEnum")
        val locationPolicy = (preset["locationPolicy"] as? JsonObject)?.also { policy ->
            allowedKeys(
                policy,
                required = setOf("advancedTemplate", "collectionKey", "isEnabled", "metadataOutputEnabled", "outputMode", "precision"),
                optional = setOf("labelConsentVersion", "labelLookupClass", "structuredFields"),
            )
            boolean(policy, "isEnabled")
            boolean(policy, "metadataOutputEnabled")
            if (string(policy, "precision") !in setOf("exact", "city") || string(policy, "outputMode") !in setOf("structured", "advancedTemplate")) fail("locationPolicyEnum")
            val collection = boundedString(policy, "collectionKey", 1, 128)
            if (!Regex("^[A-Za-z_][A-Za-z0-9_-]*$").matches(collection)) fail("locationCollectionKey")
            val advanced = boundedString(policy, "advancedTemplate", 0, 8_192)
            val lookupClass = policy["labelLookupClass"]?.let { boundedString(policy, "labelLookupClass", 1, 32) } ?: "none"
            if (lookupClass !in setOf("none", "offline", "systemMayUseNetwork")) fail("locationLabelLookupClass")
            val consentVersion = policy["labelConsentVersion"]
                ?.takeUnless { it is JsonNull }
                ?.let { (it as? JsonPrimitive)?.longOrNull ?: fail("locationLabelConsent") }
            if ((lookupClass == "systemMayUseNetwork") != (consentVersion != null) ||
                (consentVersion != null && consentVersion !in 1..Int.MAX_VALUE.toLong())) fail("locationLabelConsent")
            if (string(policy, "outputMode") == "advancedTemplate" && boolean(policy, "metadataOutputEnabled") && advanced.isBlank()) fail("locationTemplate")
            policy["structuredFields"]?.let {
                val fields = array(policy, "structuredFields")
                if (fields.size > 15) fail("locationStructuredFields")
                val fieldNames = mutableSetOf<String>()
                val outputKeys = mutableSetOf<String>()
                fields.forEach { raw ->
                    val selection = raw as? JsonObject ?: fail("locationStructuredField")
                    exactKeys(selection, setOf("field", "outputKey"))
                    val field = boundedString(selection, "field", 1, 32)
                    val outputKey = boundedString(selection, "outputKey", 1, 64)
                    if (field !in LOCATION_FIELDS || !Regex("^[A-Za-z_][A-Za-z0-9_-]*$").matches(outputKey)) {
                        fail("locationStructuredField")
                    }
                    if (!fieldNames.add(field) || !outputKeys.add(outputKey)) fail("locationStructuredFieldDuplicate")
                    if ((field == "id") != (outputKey == "id")) fail("locationStructuredFieldID")
                }
            }
        }

        val route = objectValue(preset, "routePolicy"); allowedKeys(
            route,
            required = setOf("attachmentFolder", "collisionPolicy", "extensionPolicy", "logicalFolder", "noteNameTemplate"),
            optional = setOf(
                "entryPrefix",
                "entrySuffix",
                "rollingPeriod",
                "placement",
                "headingTitle",
                "headingLevel",
                "missingHeadingBehavior",
            ),
        )
        boundedString(route, "noteNameTemplate", 1, 1024); validateSegments(array(route, "logicalFolder"), allow32 = false); validateSegments(array(route, "attachmentFolder"), allow32 = true)
        if (route["entryPrefix"] != null) boundedString(route, "entryPrefix", 0, 16_384)
        if (route["entrySuffix"] != null) boundedString(route, "entrySuffix", 0, 16_384)
        if (string(route, "extensionPolicy") != "markdownDotMd" || string(route, "collisionPolicy") !in setOf("fail", "reuseIfHashMatches", "deterministicSuffix")) fail("routeEnum")
        val rollingPeriod = (route["rollingPeriod"] as? JsonPrimitive)?.content
        if (rollingPeriod != null && rollingPeriod !in setOf("daily", "weekly", "monthly", "quarterly", "yearly")) fail("rollingPeriod")
        val placement = (route["placement"] as? JsonPrimitive)?.content
        if (placement != null && placement !in setOf("append", "prepend", "beneathHeading")) fail("placement")
        val headingTitle = (route["headingTitle"] as? JsonPrimitive)?.content
        val headingLevel = (route["headingLevel"] as? JsonPrimitive)?.content?.toLongOrNull()
        val missingHeadingBehavior = (route["missingHeadingBehavior"] as? JsonPrimitive)?.content
        if (headingTitle != null && headingTitle.length !in 1..256) fail("headingTitle")
        if (headingLevel != null && headingLevel !in 1L..6L) fail("headingLevel")
        if (missingHeadingBehavior != null && missingHeadingBehavior !in setOf("fail", "create")) fail("missingHeadingBehavior")

        val metadata = objectValue(preset, "metadataPolicy"); allowedKeys(
            metadata,
            required = setOf("finalNewline", "frontmatterMode", "lineEnding", "orderedFields", "templatePolicy"),
            optional = setOf("scope"),
        )
        boolean(metadata, "finalNewline")
        if (string(metadata, "frontmatterMode") !in setOf("none", "merge", "replace") || string(metadata, "templatePolicy") !in setOf("none", "frozenObservation") || string(metadata, "lineEnding") !in setOf("lf", "preserveExisting")) fail("metadataEnum")
        val metadataScope = (metadata["scope"] as? JsonPrimitive)?.content ?: "document"
        if (metadataScope !in setOf("document", "entry")) fail("metadataScope")
        val fields = array(metadata, "orderedFields"); if (fields.size > 128) fail("metadataBounds")
        val names = mutableSetOf<String>(); fields.forEach { raw -> val field = raw as? JsonObject ?: fail("fieldType"); exactKeys(field, setOf("name", "value")); val name = boundedString(field, "name", 1, 128); boundedString(field, "value", 0, 8192); if ('\n' in name || '\r' in name || !names.add(name)) fail("metadataField") }

        val destination = objectValue(preset, "destinationPolicy"); exactKeys(destination, setOf("capabilityClass", "capabilityReference", "expectedCaseSensitivity"))
        boundedString(destination, "capabilityReference", 1, 128)
        if (string(destination, "capabilityClass") !in setOf("userVault", "recordingExport") || string(destination, "expectedCaseSensitivity") !in setOf("unknown", "sensitive", "insensitive")) fail("destinationEnum")

        // Current enqueue profile. Case sensitivity must have been observed by native storage discovery.
        // Asset bytes remain native-owned package members; their immutable descriptors
        // and recording correlation are admitted by the shared request boundary.
        if (source !in CURRENT_CAPTURE_SOURCES || calendar != "gregorian" || payloads.size !in 1..128 || payloads.any { string(it as JsonObject, "kind") !in setOf("text", "link", "asset") }) fail("requestProfile")
        if (origin !is JsonNull) requireUUID((origin as? JsonPrimitive)?.content ?: fail("invocationProfile"))
        if (locationSnapshot != null) {
            val policy = locationPolicy ?: fail("locationPolicy")
            if (!boolean(policy, "isEnabled") || string(policy, "precision") != string(locationSnapshot, "precision") || string(locationSnapshot, "source") != source) fail("locationProfile")
        }
        if (labelObservation != null) {
            val policy = locationPolicy ?: fail("locationPolicy")
            val requested = boolean(labelObservation, "requested")
            val policyLookup = policy["labelLookupClass"]?.let { string(policy, "labelLookupClass") } ?: "none"
            if (requested && string(labelObservation, "lookupClass") != policyLookup) fail("locationLabelProfile")
            if (string(labelObservation, "lookupClass") == "systemMayUseNetwork" &&
                integer(labelObservation, "consentVersion") != 1L) fail("locationLabelProfile")
        }
        if (locationPolicy != null && string(locationPolicy, "outputMode") == "advancedTemplate" && metadataScope == "entry") fail("locationProfile")
        if (pins["modelProfileID"] !is JsonNull || pins["modelRevision"] !is JsonNull || renderer != CURRENT_RENDERER || profile != CURRENT_PROFILE || profileVersion != 1L || (gateCurrentCore && core != CURRENT_CORE)) fail("pinProfile")
        if (integer(preset, "revision") !in 1..Int.MAX_VALUE.toLong()) fail("presetProfile")
        val noteNameTemplate = string(route, "noteNameTemplate")
        val logicalFolder = array(route, "logicalFolder")
        if (
            (operation == "newNote" && string(route, "collisionPolicy") != "deterministicSuffix") ||
            (operation != "newNote" && string(route, "collisionPolicy") !in setOf("fail", "reuseIfHashMatches")) ||
            noteNameTemplate.length !in 1..128 ||
            !noteNameTemplate.endsWith(".md", ignoreCase = true) ||
            noteNameTemplate.any { it == '/' || it == '\\' || it == '\u0000' }
        ) fail("routeProfile")
        if (operation != "existingNoteAppend" && operation != "existingNotePrepend" && operation != "existingNoteHeading" && logicalFolder.isEmpty()) fail("routeProfile")
        if ((operation == "rollingNote") != (rollingPeriod != null)) fail("rollingProfile")
        val expectedPlacement = when (operation) {
            "existingNoteAppend" -> "append"
            "existingNotePrepend" -> "prepend"
            "existingNoteHeading" -> "beneathHeading"
            "rollingNote" -> placement ?: "append"
            else -> null
        }
        if (operation == "newNote" && placement != null) fail("placementProfile")
        if (operation != "newNote" && (placement ?: "append") != expectedPlacement) fail("placementProfile")
        if (expectedPlacement == "beneathHeading") {
            if (headingTitle.isNullOrBlank() || headingLevel !in 1L..6L || missingHeadingBehavior !in setOf("fail", "create")) fail("headingProfile")
        } else if (headingTitle != null || headingLevel != null || missingHeadingBehavior != null) {
            fail("headingProfile")
        }
        val frontmatterMode = string(metadata, "frontmatterMode")
        if (
            frontmatterMode !in setOf("none", "merge") ||
            (metadataScope == "document" && (frontmatterMode == "none") != fields.isEmpty()) ||
            (metadataScope == "entry" && frontmatterMode != "none") ||
            string(metadata, "templatePolicy") != "none" ||
            string(metadata, "lineEnding") != "lf" ||
            !boolean(metadata, "finalNewline")
        ) fail("metadataProfile")
        if (string(destination, "capabilityClass") != "userVault" || string(destination, "expectedCaseSensitivity") != "sensitive") fail("destinationProfile")
        return AdmittedRequest(requestID, created, source, originRecordingID)
    }

    fun verifyBinding(decoded: DecodedJournal, requestBytes: ByteArray, assetBytes: ByteArray) {
        val b = decoded.binding
        if (b.requestByteCount != requestBytes.size.toLong() || b.assetManifestByteCount != assetBytes.size.toLong() || b.requestSHA256 != sha256(requestBytes) || b.assetManifestSHA256 != sha256(assetBytes)) fail("journalBindingMismatch")
    }

    private fun validateSegments(value: JsonArray, allow32: Boolean) {
        val maximum = if (allow32) 32 else 31; if (value.size > maximum) fail("pathBounds")
        value.forEach { raw -> val segment = (raw as? JsonPrimitive)?.takeIf { it.isString }?.content ?: fail("fieldType"); if (codePoints(segment) !in 1..255 || segment in setOf(".", "..") || segment.any { it == '/' || it == '\\' || it == '\u0000' }) fail("unsafePath") }
    }
    private fun eventJson(event: JournalEvent) = JsonObject(sortedMapOf("code" to JsonPrimitive(event.code.wire()), "fromState" to (event.fromState?.let { JsonPrimitive(it.wire()) } ?: JsonNull), "occurredAtEpochMillis" to JsonPrimitive(event.occurredAtEpochMillis), "planHash" to (event.planHash?.let { JsonPrimitive(it) } ?: JsonNull), "receiptID" to (event.receiptID?.let { JsonPrimitive(it) } ?: JsonNull), "resumeState" to (event.resumeState?.let { JsonPrimitive(it.wire()) } ?: JsonNull), "revision" to JsonPrimitive(event.revision), "state" to JsonPrimitive(event.state.wire())))
    private fun decodeEvent(obj: JsonObject): JournalEvent {
        exactKeys(obj, setOf("code", "fromState", "occurredAtEpochMillis", "planHash", "receiptID", "resumeState", "revision", "state"))
        fun optionalState(key: String): CaptureState? = if (obj[key] is JsonNull) null else state(string(obj, key))
        fun optionalUUID(key: String): String? = if (obj[key] is JsonNull) null else string(obj, key).also(::requireUUID)
        fun optionalSha(key: String): String? = if (obj[key] is JsonNull) null else string(obj, key).also(::requireSha)
        val revision = integer(obj, "revision")
        if (revision !in Int.MIN_VALUE.toLong()..Int.MAX_VALUE.toLong()) fail("revisionBounds")
        return JournalEvent(revision.toInt(), optionalState("fromState"), state(string(obj, "state")), code(string(obj, "code")), integer(obj, "occurredAtEpochMillis"), optionalState("resumeState"), optionalUUID("receiptID"), optionalSha("planHash"))
    }
    private fun exactKeys(obj: JsonObject, expected: Set<String>) { if (obj.keys != expected) fail("unknownOrMissingField") }
    private fun allowedKeys(obj: JsonObject, required: Set<String>, optional: Set<String>) {
        if (!obj.keys.containsAll(required) || obj.keys.any { it !in required && it !in optional }) fail("unknownOrMissingField")
    }
    private fun string(obj: JsonObject, key: String) = (obj[key] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: fail("fieldType")
    private fun boundedString(obj: JsonObject, key: String, min: Int, max: Int): String = string(obj, key).also { if (codePoints(it) !in min..max) fail("stringBounds") }
    private fun codePoints(value: String) = value.codePointCount(0, value.length)
    private fun integer(obj: JsonObject, key: String) = (obj[key] as? JsonPrimitive)?.takeIf { !it.isString }?.longOrNull ?: fail("fieldType")
    private fun boolean(obj: JsonObject, key: String) = (obj[key] as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull ?: fail("fieldType")
    private fun array(obj: JsonObject, key: String) = obj[key] as? JsonArray ?: fail("fieldType")
    private fun objectValue(obj: JsonObject, key: String) = obj[key] as? JsonObject ?: fail("fieldType")
    private fun requireUUID(value: String) { if (!UUID_PATTERN.matches(value)) fail("uuid") }
    private fun requireSha(value: String) { if (!SHA_PATTERN.matches(value)) fail("sha256") }

    /** Canonical commit-attempt marker bytes (ADR-0023 §4). */
    fun encodeMarker(marker: CommitMarker): ByteArray = canonical(JsonObject(sortedMapOf(
            "candidateDisplayName" to JsonPrimitive(marker.candidateDisplayName),
            "destinationID" to JsonPrimitive(marker.destinationID),
            "markerState" to JsonPrimitive(marker.state.name.lowercase()),
            "planHash" to JsonPrimitive(marker.planHash),
            "recordedAtEpochMillis" to JsonPrimitive(marker.recordedAtEpochMillis),
            "schemaVersion" to JsonPrimitive(1),
        )))

    fun decodeMarker(bytes: ByteArray): CommitMarker {
        val obj = parseCanonical(bytes)
        exactKeys(obj, setOf("candidateDisplayName", "destinationID", "markerState", "planHash", "recordedAtEpochMillis", "schemaVersion"))
        if (integer(obj, "schemaVersion") != 1L) fail("markerSchemaVersion")
        if (integer(obj, "recordedAtEpochMillis") < 0) fail("markerTimestamp")
        val markerState = when (string(obj, "markerState")) {
            "active" -> CommitMarker.MarkerState.ACTIVE
            "cleared" -> CommitMarker.MarkerState.CLEARED
            else -> return fail("markerState")
        }
        return try {
            CommitMarker.validated(markerState, string(obj, "destinationID"), string(obj, "planHash"), string(obj, "candidateDisplayName"), integer(obj, "recordedAtEpochMillis"))
        } catch (_: IllegalArgumentException) { fail("markerBounds") }
    }

    /** Canonical verified-commit receipt bytes (ADR-0023 §5). */
    fun encodeReceipt(receipt: DeliveryReceipt): ByteArray = canonical(JsonObject(sortedMapOf(
        "artifactID" to JsonPrimitive(receipt.artifactID),
        "committedAtEpochMillis" to JsonPrimitive(receipt.committedAtEpochMillis),
        "destinationID" to JsonPrimitive(receipt.destinationID),
        "operationID" to JsonPrimitive(receipt.operationID),
        "planHash" to JsonPrimitive(receipt.planHash),
        "receiptID" to JsonPrimitive(receipt.receiptID),
        "requestID" to JsonPrimitive(receipt.requestID),
        "schemaVersion" to JsonPrimitive(1),
        "verifiedLengthBytes" to JsonPrimitive(receipt.verifiedLengthBytes),
        "verifiedSHA256" to JsonPrimitive(receipt.verifiedSHA256),
    )))

    fun decodeReceipt(bytes: ByteArray): DeliveryReceipt {
        val obj = parseCanonical(bytes)
        exactKeys(obj, setOf("artifactID", "committedAtEpochMillis", "destinationID", "operationID", "planHash", "receiptID", "requestID", "schemaVersion", "verifiedLengthBytes", "verifiedSHA256"))
        if (integer(obj, "schemaVersion") != 1L) fail("receiptSchemaVersion")
        return try {
            DeliveryReceipt.validated(
                string(obj, "receiptID"), string(obj, "requestID"), string(obj, "operationID"), string(obj, "artifactID"),
                string(obj, "planHash"), string(obj, "destinationID"),
                integer(obj, "verifiedLengthBytes"), string(obj, "verifiedSHA256"), integer(obj, "committedAtEpochMillis"),
            )
        } catch (_: IllegalArgumentException) { fail("receiptBounds") }
    }
    private fun state(value: String) = CaptureState.entries.firstOrNull { it.wire() == value } ?: fail("state")
    private fun code(value: String) = JournalCode.entries.firstOrNull { it.wire() == value } ?: fail("code")
    private fun fail(code: String): Nothing = throw PackageCodecException(code)
    private val CURRENT_CAPTURE_SOURCES = setOf("app", "share", "keyboard", "widget", "shortcut", "watch", "wear")
    private val LOCATION_UNAVAILABLE_REASONS = setOf(
        "permissionDenied", "restricted", "notDetermined", "reducedAccuracy", "timeout", "cancelled", "unavailable",
    )
    private val LOCATION_FIELDS = setOf(
        "coordinates", "latitude", "longitude", "place", "city", "region", "country", "appleMapsURL",
        "googleMapsURL", "openStreetMapURL", "geoURI", "accuracy", "timestamp", "source", "id",
    )
    private fun canonicalText(value: JsonElement, depth: Int): String = when (value) { is JsonObject -> if (value.isEmpty()) "{}" else value.entries.sortedBy { it.key }.joinToString(",\n", "{\n", "\n${"  ".repeat(depth)}}") { (key, item) -> "${"  ".repeat(depth + 1)}${quote(key)}: ${canonicalText(item, depth + 1)}" }; is JsonArray -> if (value.isEmpty()) "[]" else value.joinToString(",\n", "[\n", "\n${"  ".repeat(depth)}]") { "${"  ".repeat(depth + 1)}${canonicalText(it, depth + 1)}" }; is JsonNull -> "null"; is JsonPrimitive -> if (value.isString) quote(value.content) else value.content }
    private fun quote(value: String): String = buildString { append('"'); value.forEach { c -> when (c) { '"' -> append("\\\""); '\\' -> append("\\\\"); '\b' -> append("\\b"); '\u000C' -> append("\\f"); '\n' -> append("\\n"); '\r' -> append("\\r"); '\t' -> append("\\t"); else -> if (c.code < 0x20) append("\\u%04x".format(c.code)) else append(c) } }; append('"') }
}

internal fun CaptureState.wire() = name.lowercase().replace(Regex("_([a-z])")) { it.groupValues[1].uppercase() }
internal fun JournalCode.wire() = name.lowercase().replace(Regex("_([a-z])")) { it.groupValues[1].uppercase() }
