package md.vox.android.platformservices

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import md.vox.android.capturedomain.CaptureAudioEmbedPlacement
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureExportFileFormat
import md.vox.android.capturedomain.CaptureExportFileMode
import md.vox.android.capturedomain.CaptureExportYAMLProperty
import md.vox.android.capturedomain.CaptureLocationOutputMode
import md.vox.android.capturedomain.CaptureLocationLabelLookupClass
import md.vox.android.capturedomain.CaptureLocationField
import md.vox.android.capturedomain.CaptureLocationPrecision
import md.vox.android.capturedomain.CaptureLocationStructuredField
import md.vox.android.capturedomain.CaptureLocationUnavailableBehavior
import md.vox.android.capturedomain.DEFAULT_CAPTURE_LOCATION_FIELDS
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CaptureMetadataScope
import md.vox.android.capturedomain.CaptureMissingHeadingBehavior
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.capturedomain.CapturePresetLocationPolicy
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureProcessingScope
import md.vox.android.capturedomain.CaptureRollingPeriod
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.capturedomain.CURRENT_LOCATION_LABEL_CONSENT_VERSION

/** Versioned full preset snapshot frozen before a phone or Wear recording starts. */
object RecordingPresetSnapshotCodec {
    fun encode(preset: CapturePreset): String = buildJsonObject {
        put("version", VERSION)
        put("attachmentsFolder", preset.attachmentsFolder)
        put("audioEmbedPlacement", preset.audioEmbedPlacement.name)
        put("audioSaveMode", preset.audioSaveMode.name)
        put("capturePrompt", preset.capturePrompt)
        put("customProcessingInstruction", preset.customProcessingInstruction)
        put("embedAudioInMarkdown", preset.embedAudioInMarkdown)
        put("entryPrefix", preset.entryPrefix)
        put("entrySuffix", preset.entrySuffix)
        preset.entryTemplateID?.let { put("entryTemplateID", it) }
        put("existingNotePath", preset.existingNotePath)
        put("exportSettings", buildJsonObject {
            put("appendFileName", preset.exportSettings.appendFileName)
            put("destinationName", preset.exportSettings.destinationName)
            preset.exportSettings.destinationTreeUri?.let { put("destinationTreeUri", it) }
            put("audioEmbedPlacement", preset.exportSettings.audioEmbedPlacement.name)
            put("embedAudioInMarkdown", preset.exportSettings.embedAudioInMarkdown)
            put("exportEnabled", preset.exportSettings.exportEnabled)
            put("format", preset.exportSettings.format.name)
            put("markdownTemplateEnabled", preset.exportSettings.markdownTemplateEnabled)
            put("markdownTemplateName", preset.exportSettings.markdownTemplateName)
            preset.exportSettings.markdownTemplateUri?.let { put("markdownTemplateUri", it) }
            put("mdObsidianEnabled", preset.exportSettings.mdObsidianEnabled)
            put("mode", preset.exportSettings.mode.name)
            put("newFileNameTemplate", preset.exportSettings.newFileNameTemplate)
            put("usesCustomExportSettings", preset.exportSettings.usesCustomExportSettings)
            put("yamlProperties", buildJsonArray {
                preset.exportSettings.yamlProperties.sortedBy { it.name }.forEach { add(JsonPrimitive(it.name)) }
            })
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
            put("structuredFields", buildJsonArray {
                preset.locationPolicy.structuredFields.forEach { selection ->
                    add(buildJsonObject {
                        put("field", selection.field.wireName)
                        put("outputKey", selection.outputKey)
                    })
                }
            })
            put("unavailableBehavior", preset.locationPolicy.unavailableBehavior.name)
        })
        put("metadataFields", buildJsonArray {
            preset.metadataFields.forEach { field ->
                add(buildJsonObject {
                    put("name", field.name)
                    put("value", field.value)
                })
            }
        })
        put("metadataScope", preset.metadataScope.name)
        put("missingHeadingBehavior", preset.missingHeadingBehavior.name)
        put("name", preset.name)
        put("noteNameTemplate", preset.noteNameTemplate)
        put("noteTargetKind", preset.noteTargetKind.name)
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
    }.toString()

    fun decode(value: String): CapturePreset? = runCatching {
        require(value.toByteArray().size in 1..MAX_BYTES)
        val root = Json.parseToJsonElement(value) as? JsonObject ?: error("snapshotRoot")
        require(root.int("version") == VERSION)
        val location = root.objectValue("locationPolicy")
        val metadata = root.array("metadataFields")
        val export = root["exportSettings"] as? JsonObject
        require(metadata.size <= 16)
        CapturePreset(
            id = root.string("id").also { require(UUID_PATTERN.matches(it)) },
            name = root.string("name").also { require(it.length in 1..64) },
            symbol = root.string("symbol").also { require(it.length <= 64) },
            revision = root.int("revision").also { require(it > 0) },
            logicalFolder = root.string("logicalFolder").also { require(it.length <= 1_024) },
            noteNameTemplate = root.string("noteNameTemplate").also { require(it.length in 1..512) },
            metadataFields = metadata.map { element ->
                (element as? JsonObject ?: error("metadataField")).let { field ->
                    CaptureMetadataField(
                        field.string("name").also { require(METADATA_NAME.matches(it)) },
                        field.string("value").also { require(it.length <= 512) },
                    )
                }
            },
            isEnabled = root.boolean("isEnabled"),
            isPinned = root.boolean("isPinned"),
            noteTargetKind = enumValue(root, "noteTargetKind"),
            rollingPeriod = enumValue(root, "rollingPeriod"),
            existingNotePath = root.string("existingNotePath").also { require(it.length <= 1_024) },
            placement = enumValue(root, "placement"),
            headingTitle = root.string("headingTitle").also { require(it.length <= 256) },
            headingLevel = root.int("headingLevel").also { require(it in 1..6) },
            missingHeadingBehavior = enumValue(root, "missingHeadingBehavior"),
            entryPrefix = root.string("entryPrefix").also { require(it.length <= 16_384) },
            entrySuffix = root.string("entrySuffix").also { require(it.length <= 16_384) },
            entryTemplateID = root.optionalString("entryTemplateID")?.also { require(UUID_PATTERN.matches(it)) },
            attachmentsFolder = root.string("attachmentsFolder").also { require(it.length <= 1_024) },
            retryProtectionEnabled = root.boolean("retryProtectionEnabled"),
            metadataScope = enumValue(root, "metadataScope"),
            speakerDiarizationEnabled = root.boolean("speakerDiarizationEnabled"),
            processingEnabled = root.boolean("processingEnabled"),
            processingMode = enumValue(root, "processingMode"),
            processingScope = enumValue(root, "processingScope"),
            customProcessingInstruction = root.string("customProcessingInstruction").also { require(it.length <= 4_096) },
            capturePrompt = root.string("capturePrompt").also { require(it.length <= 4_096) },
            generateImageAltText = root.boolean("generateImageAltText"),
            locationPolicy = CapturePresetLocationPolicy(
                isEnabled = location.boolean("isEnabled"),
                precision = enumValue(location, "precision"),
                unavailableBehavior = enumValue(location, "unavailableBehavior"),
                metadataOutputEnabled = location.boolean("metadataOutputEnabled"),
                outputMode = enumValue(location, "outputMode"),
                structuredFields = (location["structuredFields"] as? JsonArray)?.map { raw ->
                    val item = raw as? JsonObject ?: error("locationStructuredField")
                    val field = CaptureLocationField.entries.firstOrNull { it.wireName == item.string("field") }
                        ?: error("locationStructuredField")
                    CaptureLocationStructuredField(
                        field = field,
                        outputKey = item.string("outputKey").also { require(METADATA_NAME.matches(it)) },
                    )
                }?.also { fields ->
                    require(fields.size <= CaptureLocationField.entries.size)
                    require(fields.map { it.field }.distinct().size == fields.size)
                    require(fields.map { it.outputKey }.distinct().size == fields.size)
                    require(fields.all { selection ->
                        if (selection.field == CaptureLocationField.ID) selection.outputKey == "id" else selection.outputKey != "id"
                    })
                } ?: DEFAULT_CAPTURE_LOCATION_FIELDS,
                collectionKey = location.string("collectionKey").also { require(METADATA_NAME.matches(it)) },
                advancedTemplate = location.string("advancedTemplate").also { require(it.length <= 4_096) },
                labelLookupClass = enumValueOr(location, "labelLookupClass", CaptureLocationLabelLookupClass.NONE),
                labelConsentVersion = location.optionalInt("labelConsentVersion"),
            ).also { policy ->
                require(
                    policy.labelLookupClass != CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK ||
                        policy.labelConsentVersion == CURRENT_LOCATION_LABEL_CONSENT_VERSION,
                )
                require(
                    policy.labelLookupClass == CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK ||
                        policy.labelConsentVersion == null,
                )
            },
            audioSaveMode = enumValue(root, "audioSaveMode"),
            embedAudioInMarkdown = root.boolean("embedAudioInMarkdown"),
            audioEmbedPlacement = enumValue(root, "audioEmbedPlacement"),
            watchOutputMode = enumValue(root, "watchOutputMode"),
            exportSettings = export?.let { value ->
                CapturePresetExportSettings(
                    usesCustomExportSettings = value.booleanOr("usesCustomExportSettings", false),
                    exportEnabled = value.booleanOr("exportEnabled", true),
                    format = enumValueOr(value, "format", CaptureExportFileFormat.MARKDOWN),
                    mode = enumValueOr(value, "mode", CaptureExportFileMode.NEW_FILE),
                    destinationTreeUri = value.optionalString("destinationTreeUri")?.also { require(it.length <= 4_096) },
                    destinationName = value.stringOr("destinationName", "").also { require(it.length <= 256) },
                    embedAudioInMarkdown = value.booleanOr("embedAudioInMarkdown", false),
                    audioEmbedPlacement = enumValueOr(value, "audioEmbedPlacement", CaptureAudioEmbedPlacement.AFTER_TEXT),
                    newFileNameTemplate = value.stringOr("newFileNameTemplate", "voxboard-{timestamp}-{id8}")
                        .also { require(it.length in 1..256) },
                    appendFileName = value.stringOr("appendFileName", "voxboard-transcripts")
                        .also { require(it.length in 1..256) },
                    markdownTemplateEnabled = value.booleanOr("markdownTemplateEnabled", false),
                    markdownTemplateUri = value.optionalString("markdownTemplateUri")?.also { require(it.length <= 4_096) },
                    markdownTemplateName = value.stringOr("markdownTemplateName", "").also { require(it.length <= 256) },
                    mdObsidianEnabled = value.booleanOr("mdObsidianEnabled", false),
                    yamlUsesMarkdownExtension = value.booleanOr("yamlUsesMarkdownExtension", false),
                    yamlProperties = (value["yamlProperties"] as? JsonArray)?.mapNotNull { property ->
                        runCatching { CaptureExportYAMLProperty.valueOf(property.jsonPrimitive.content) }.getOrNull()
                    }?.toSet()?.takeIf(Set<CaptureExportYAMLProperty>::isNotEmpty)
                        ?: CaptureExportYAMLProperty.entries.toSet(),
                )
            } ?: CapturePresetExportSettings(),
        )
    }.getOrNull()

    private fun JsonObject.value(key: String): JsonPrimitive =
        this[key] as? JsonPrimitive ?: error("missing:$key")

    private fun JsonObject.string(key: String): String = value(key).content
    private fun JsonObject.stringOr(key: String, default: String): String = optionalString(key) ?: default
    private fun JsonObject.optionalString(key: String): String? = (this[key] as? JsonPrimitive)?.content
    private fun JsonObject.int(key: String): Int = value(key).int
    private fun JsonObject.optionalInt(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull
    private fun JsonObject.boolean(key: String): Boolean = value(key).boolean
    private fun JsonObject.booleanOr(key: String, default: Boolean): Boolean =
        (this[key] as? JsonPrimitive)?.booleanOrNull ?: default
    private fun JsonObject.objectValue(key: String): JsonObject = this[key] as? JsonObject ?: error("missing:$key")
    private fun JsonObject.array(key: String): JsonArray = this[key] as? JsonArray ?: error("missing:$key")

    private inline fun <reified T : Enum<T>> enumValue(root: JsonObject, key: String): T =
        enumValueOf(root.string(key))

    private inline fun <reified T : Enum<T>> enumValueOr(root: JsonObject, key: String, default: T): T =
        root.optionalString(key)?.let { runCatching { enumValueOf<T>(it) }.getOrNull() } ?: default

    private const val VERSION = 1
    private const val MAX_BYTES = 65_536
    private val UUID_PATTERN = Regex("^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
    private val METADATA_NAME = Regex("^[A-Za-z0-9_-]{1,64}$")
}
