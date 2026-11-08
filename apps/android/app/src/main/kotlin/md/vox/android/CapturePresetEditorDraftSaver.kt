package md.vox.android

import android.os.Bundle
import androidx.compose.runtime.saveable.Saver
import md.vox.android.capturedomain.*

/** Preserve raw edits, including incomplete fields, without committing a route. */
internal val CapturePresetEditorDraftSaver = Saver<CapturePresetEditorDraft, Bundle>(
    save = { it.savedDraft() },
    restore = { it.restoreCapturePresetEditorDraft() },
)

private fun CapturePresetEditorDraft.savedDraft(): Bundle = Bundle().apply {
    putString("id", id)
    putString("name", name)
    putString("symbol", symbol)
    putString("emoji", emoji)
    putBoolean("isEnabled", isEnabled)
    putBoolean("isPinned", isPinned)
    putString("noteTargetKind", noteTargetKind.name)
    putString("rollingPeriod", rollingPeriod.name)
    putString("logicalFolder", logicalFolder)
    putString("noteNameTemplate", noteNameTemplate)
    putString("existingNotePath", existingNotePath)
    putString("placement", placement.name)
    putString("headingTitle", headingTitle)
    putInt("headingLevel", headingLevel)
    putString("missingHeadingBehavior", missingHeadingBehavior.name)
    putString("entryPrefix", entryPrefix)
    putString("entrySuffix", entrySuffix)
    putString("entryTemplateID", entryTemplateID)
    putString("attachmentsFolder", attachmentsFolder)
    putBoolean("retryProtectionEnabled", retryProtectionEnabled)
    putString("metadataScope", metadataScope.name)
    putString("metadataText", metadataText)
    putBoolean("speakerDiarizationEnabled", speakerDiarizationEnabled)
    putBoolean("processingEnabled", processingEnabled)
    putString("processingMode", processingMode.name)
    putString("processingScope", processingScope.name)
    putString("customInstruction", customInstruction)
    putString("capturePrompt", capturePrompt)
    putBoolean("generateImageAltText", generateImageAltText)
    putBoolean("locationEnabled", locationEnabled)
    putString("locationPrecision", locationPrecision.name)
    putString("locationUnavailableBehavior", locationUnavailableBehavior.name)
    putBoolean("locationMetadataEnabled", locationMetadataEnabled)
    putString("locationOutputMode", locationOutputMode.name)
    putParcelableArrayList("locationStructuredFields", ArrayList(locationStructuredFields.map { it.savedCaptureLocationStructuredField() }))
    putString("locationCollectionKey", locationCollectionKey)
    putString("locationAdvancedTemplate", locationAdvancedTemplate)
    putString("locationLabelLookupClass", locationLabelLookupClass.name)
    locationLabelConsentVersion?.let { putInt("locationLabelConsentVersion", it) }
    putString("audioSaveMode", audioSaveMode.name)
    putBoolean("embedAudio", embedAudio)
    putString("audioEmbedPlacement", audioEmbedPlacement.name)
    putString("watchOutputMode", watchOutputMode.name)
    putBundle("exportSettings", exportSettings.savedCapturePresetExportSettings())
    putBundle("destination", destination?.savedCaptureDestination())
    putString("transcriptPropertyName", transcriptPropertyName)
    putBoolean("includeTranscriptInBody", includeTranscriptInBody)
    putBundle("urlDelivery", urlDelivery.savedCaptureURLDeliverySettings())
    putString("headingPosition", headingPosition.name)
    putString("audioFilenameTemplate", audioFilenameTemplate)
}

@Suppress("DEPRECATION")
private fun Bundle.restoreCapturePresetEditorDraft(): CapturePresetEditorDraft = CapturePresetEditorDraft(
    id = requireNotNull(getString("id")),
    name = requireNotNull(getString("name")),
    symbol = requireNotNull(getString("symbol")),
    emoji = getString("emoji"),
    isEnabled = getBoolean("isEnabled"),
    isPinned = getBoolean("isPinned"),
    noteTargetKind = CaptureNoteTargetKind.valueOf(requireNotNull(getString("noteTargetKind"))),
    rollingPeriod = CaptureRollingPeriod.valueOf(requireNotNull(getString("rollingPeriod"))),
    logicalFolder = requireNotNull(getString("logicalFolder")),
    noteNameTemplate = requireNotNull(getString("noteNameTemplate")),
    existingNotePath = requireNotNull(getString("existingNotePath")),
    placement = CapturePlacementKind.valueOf(requireNotNull(getString("placement"))),
    headingTitle = requireNotNull(getString("headingTitle")),
    headingLevel = getInt("headingLevel"),
    missingHeadingBehavior = CaptureMissingHeadingBehavior.valueOf(requireNotNull(getString("missingHeadingBehavior"))),
    entryPrefix = requireNotNull(getString("entryPrefix")),
    entrySuffix = requireNotNull(getString("entrySuffix")),
    entryTemplateID = getString("entryTemplateID"),
    attachmentsFolder = requireNotNull(getString("attachmentsFolder")),
    retryProtectionEnabled = getBoolean("retryProtectionEnabled"),
    metadataScope = CaptureMetadataScope.valueOf(requireNotNull(getString("metadataScope"))),
    metadataText = requireNotNull(getString("metadataText")),
    speakerDiarizationEnabled = getBoolean("speakerDiarizationEnabled"),
    processingEnabled = getBoolean("processingEnabled"),
    processingMode = CaptureProcessingMode.valueOf(requireNotNull(getString("processingMode"))),
    processingScope = CaptureProcessingScope.valueOf(requireNotNull(getString("processingScope"))),
    customInstruction = requireNotNull(getString("customInstruction")),
    capturePrompt = requireNotNull(getString("capturePrompt")),
    generateImageAltText = getBoolean("generateImageAltText"),
    locationEnabled = getBoolean("locationEnabled"),
    locationPrecision = CaptureLocationPrecision.valueOf(requireNotNull(getString("locationPrecision"))),
    locationUnavailableBehavior = CaptureLocationUnavailableBehavior.valueOf(requireNotNull(getString("locationUnavailableBehavior"))),
    locationMetadataEnabled = getBoolean("locationMetadataEnabled"),
    locationOutputMode = CaptureLocationOutputMode.valueOf(requireNotNull(getString("locationOutputMode"))),
    locationStructuredFields = getParcelableArrayList<Bundle>("locationStructuredFields").orEmpty().map { it.restoreCaptureLocationStructuredField() },
    locationCollectionKey = requireNotNull(getString("locationCollectionKey")),
    locationAdvancedTemplate = requireNotNull(getString("locationAdvancedTemplate")),
    locationLabelLookupClass = CaptureLocationLabelLookupClass.valueOf(requireNotNull(getString("locationLabelLookupClass"))),
    locationLabelConsentVersion = if (containsKey("locationLabelConsentVersion")) getInt("locationLabelConsentVersion") else null,
    audioSaveMode = CaptureAudioSaveMode.valueOf(requireNotNull(getString("audioSaveMode"))),
    embedAudio = getBoolean("embedAudio"),
    audioEmbedPlacement = CaptureAudioEmbedPlacement.valueOf(requireNotNull(getString("audioEmbedPlacement"))),
    watchOutputMode = CaptureWatchOutputMode.valueOf(requireNotNull(getString("watchOutputMode"))),
    exportSettings = requireNotNull(getBundle("exportSettings")).restoreCapturePresetExportSettings(),
    destination = getBundle("destination")?.restoreCaptureDestination(),
    transcriptPropertyName = requireNotNull(getString("transcriptPropertyName")),
    includeTranscriptInBody = getBoolean("includeTranscriptInBody"),
    urlDelivery = requireNotNull(getBundle("urlDelivery")).restoreCaptureURLDeliverySettings(),
    headingPosition = CaptureHeadingPosition.valueOf(requireNotNull(getString("headingPosition"))),
    audioFilenameTemplate = requireNotNull(getString("audioFilenameTemplate")),
)

private fun CaptureDestination.savedCaptureDestination(): Bundle = Bundle().apply {
    putString("id", id)
    putString("displayName", displayName)
    putString("treeUri", treeUri)
}

@Suppress("DEPRECATION")
private fun Bundle.restoreCaptureDestination(): CaptureDestination = CaptureDestination(
    id = requireNotNull(getString("id")),
    displayName = requireNotNull(getString("displayName")),
    treeUri = requireNotNull(getString("treeUri")),
)

private fun CaptureLocationStructuredField.savedCaptureLocationStructuredField(): Bundle = Bundle().apply {
    putString("field", field.name)
    putString("outputKey", outputKey)
}

@Suppress("DEPRECATION")
private fun Bundle.restoreCaptureLocationStructuredField(): CaptureLocationStructuredField = CaptureLocationStructuredField(
    field = CaptureLocationField.valueOf(requireNotNull(getString("field"))),
    outputKey = requireNotNull(getString("outputKey")),
)

private fun CapturePresetExportSettings.savedCapturePresetExportSettings(): Bundle = Bundle().apply {
    putBoolean("usesCustomExportSettings", usesCustomExportSettings)
    putBoolean("exportEnabled", exportEnabled)
    putString("format", format.name)
    putString("mode", mode.name)
    putString("destinationTreeUri", destinationTreeUri)
    putString("destinationName", destinationName)
    putString("newFileNameTemplate", newFileNameTemplate)
    putString("appendFileName", appendFileName)
    putBoolean("markdownTemplateEnabled", markdownTemplateEnabled)
    putString("markdownTemplateUri", markdownTemplateUri)
    putString("markdownTemplateName", markdownTemplateName)
    putBoolean("mdObsidianEnabled", mdObsidianEnabled)
    putBoolean("yamlUsesMarkdownExtension", yamlUsesMarkdownExtension)
    putStringArrayList("yamlProperties", ArrayList(yamlProperties.map { it.name }))
    putBoolean("embedAudioInMarkdown", embedAudioInMarkdown)
    putString("audioEmbedPlacement", audioEmbedPlacement.name)
}

@Suppress("DEPRECATION")
private fun Bundle.restoreCapturePresetExportSettings(): CapturePresetExportSettings = CapturePresetExportSettings(
    usesCustomExportSettings = getBoolean("usesCustomExportSettings"),
    exportEnabled = getBoolean("exportEnabled"),
    format = CaptureExportFileFormat.valueOf(requireNotNull(getString("format"))),
    mode = CaptureExportFileMode.valueOf(requireNotNull(getString("mode"))),
    destinationTreeUri = getString("destinationTreeUri"),
    destinationName = requireNotNull(getString("destinationName")),
    newFileNameTemplate = requireNotNull(getString("newFileNameTemplate")),
    appendFileName = requireNotNull(getString("appendFileName")),
    markdownTemplateEnabled = getBoolean("markdownTemplateEnabled"),
    markdownTemplateUri = getString("markdownTemplateUri"),
    markdownTemplateName = requireNotNull(getString("markdownTemplateName")),
    mdObsidianEnabled = getBoolean("mdObsidianEnabled"),
    yamlUsesMarkdownExtension = getBoolean("yamlUsesMarkdownExtension"),
    yamlProperties = getStringArrayList("yamlProperties").orEmpty().map(CaptureExportYAMLProperty::valueOf).toSet(),
    embedAudioInMarkdown = getBoolean("embedAudioInMarkdown"),
    audioEmbedPlacement = CaptureAudioEmbedPlacement.valueOf(requireNotNull(getString("audioEmbedPlacement"))),
)

private fun CaptureURLDeliverySettings.savedCaptureURLDeliverySettings(): Bundle = Bundle().apply {
    putBoolean("enabled", enabled)
    putString("credentialID", credentialID)
    putString("origin", origin)
    putInt("maxAttempts", maxAttempts)
}

@Suppress("DEPRECATION")
private fun Bundle.restoreCaptureURLDeliverySettings(): CaptureURLDeliverySettings = CaptureURLDeliverySettings(
    enabled = getBoolean("enabled"),
    credentialID = getString("credentialID"),
    origin = requireNotNull(getString("origin")),
    maxAttempts = getInt("maxAttempts"),
)
