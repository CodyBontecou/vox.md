package md.vox.android

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import md.vox.android.capturedomain.CaptureAudioSaveMode
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.CaptureHeadingPosition
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.CaptureExportFileFormat
import md.vox.android.capturedomain.CaptureExportFileMode
import md.vox.android.capturedomain.CaptureLocationField
import md.vox.android.capturedomain.CaptureLocationLabelLookupClass
import md.vox.android.capturedomain.CaptureLocationOutputMode
import md.vox.android.capturedomain.CaptureLocationStructuredField
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CaptureNoteTargetKind
import md.vox.android.capturedomain.CapturePlacementKind
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.capturedomain.CapturePresetCollection
import md.vox.android.capturedomain.CapturePresetExportSettings
import md.vox.android.capturedomain.CapturePresetLocationPolicy
import md.vox.android.capturedomain.CaptureProcessingMode
import md.vox.android.capturedomain.CaptureRollingPeriod
import md.vox.android.capturedomain.CaptureWatchOutputMode
import md.vox.android.capturedomain.CURRENT_LOCATION_LABEL_CONSENT_VERSION
import md.vox.android.capturedomain.DEFAULT_CAPTURE_LOCATION_FIELDS
import md.vox.android.capturedomain.PresetWidgetSelection
import md.vox.android.capturedomain.PresetWidgetSource
import md.vox.android.ui.Signal

/**
 * Signal redesign stories for the route area. Story ids use the
 * "routes-" prefix; launch with
 * `adb shell am start -n md.vox.android/.VisualStoryActivity --es story <id> --ez dark <bool>`.
 * Returns false when [story] is not one of these.
 */
@Composable
internal fun RouteStories(story: String): Boolean {
    when (story) {
        // List
        "routes-list" -> RouteListStory(routeStoryCollection, routeStoryTemplates)
        "routes-list-disabled" -> RouteListStory(
            routeStoryCollection.copy(
                presets = routeStoryCollection.presets.mapIndexed { index, preset ->
                    if (index >= 2) preset.copy(isEnabled = false) else preset
                },
            ),
            routeStoryTemplates,
        )
        "routes-list-loading" -> RouteListStory(null, emptyList())
        "routes-list-busy" -> RouteListStory(routeStoryCollection, routeStoryTemplates, isBusy = true)
        "routes-list-single" -> RouteListStory(
            CapturePresetCollection(ROUTE_INBOX_ID, listOf(routeStoryCollection.presets.first())),
            emptyList(),
        )
        "routes-templates-empty" -> RouteListStory(routeStoryCollection, emptyList())
        "routes-templates-populated" -> RouteListStory(
            routeStoryCollection,
            routeStoryTemplates + CaptureEntryTemplate(
                id = "abababab-abab-4bab-8bab-abababababab",
                name = "Long template name that wraps across two lines on narrow phones",
                entryPrefix = "### {time} · {title}\n",
                entrySuffix = "\n— captured with vox.md, tagged #inbox #review #followup",
            ),
        )
        "routes-long-text" -> RouteListStory(
            CapturePresetCollection(
                ROUTE_INBOX_ID,
                routeStoryCollection.presets + routeStoryPreset(
                    id = "cdcdcdcd-cdcd-4dcd-8dcd-cdcdcdcdcdcd",
                    name = "Quarterly planning notes for the extended leadership team offsite",
                    folder = "Work/Planning/Quarterly Reviews/2026",
                    file = "{year}-Q{quarter}-leadership-offsite-{id}.md",
                    isPinned = true,
                ),
            ),
            routeStoryTemplates,
        )

        // Entry template dialog
        "routes-template-new" -> RouteTemplateDialogStory(template = null)
        "routes-template-edit" -> RouteTemplateDialogStory(template = routeStoryTemplates.first())

        // Full editor
        "routes-editor-new" -> RouteEditorStory(preset = null)
        "routes-editor-existing" -> RouteEditorStory(preset = routeStoryCollection.presets[1])
        "routes-editor-busy" -> RouteEditorStory(preset = routeStoryCollection.presets[1], isBusy = true)
        "routes-editor-disabled" -> RouteEditorStory(preset = routeStoryCollection.presets[1].copy(isEnabled = false))
        "routes-editor-invalid" -> RouteEditorStory(
            preset = routeStoryCollection.presets[1].copy(name = "", noteNameTemplate = "meeting"),
        )
        // Route editor board: default route with its own quick actions, a meeting-summary
        // daily note under a heading, and each step's sub-page.
        "routes-editor-default" -> RouteEditorStory(preset = routeStoryMeetingRoute, isDefault = true, captureBar = routeStoryCustomBar)
        "routes-editor-recording-only" -> RouteEditorStory(
            preset = routeStoryCollection.presets[2].copy(watchOutputMode = CaptureWatchOutputMode.RECORDING_ONLY),
        )
        "routes-editor-step-capture" -> RouteEditorStory(preset = routeStoryMeetingRoute, page = RouteEditorPage.CAPTURE)
        "routes-editor-step-process" -> RouteEditorStory(preset = routeStoryMeetingRoute, page = RouteEditorPage.PROCESS)
        "routes-editor-step-shape" -> RouteEditorStory(preset = routeStoryMeetingRoute, page = RouteEditorPage.SHAPE)
        "routes-editor-step-deliver" -> RouteEditorStory(preset = routeStoryMeetingRoute, page = RouteEditorPage.DELIVER)
        "routes-editor-step-invalid" -> RouteEditorStory(
            preset = routeStoryMeetingRoute.copy(headingTitle = "", existingNotePath = ""),
            page = RouteEditorPage.DELIVER,
        )

        // Route quick actions board
        "routes-quick-actions" -> RouteEditorStory(preset = routeStoryMeetingRoute, page = RouteEditorPage.QUICK_ACTIONS)
        "routes-quick-actions-custom" -> RouteEditorStory(
            preset = routeStoryMeetingRoute,
            page = RouteEditorPage.QUICK_ACTIONS,
            captureBar = routeStoryCustomBar,
        )
        "routes-quick-actions-empty" -> RouteEditorStory(
            preset = routeStoryMeetingRoute,
            page = RouteEditorPage.QUICK_ACTIONS,
            captureBar = CaptureBarConfiguration().withRoutePins(ROUTE_MEETINGS_ID, emptyList()),
        )
        "routes-quick-actions-all-pinned" -> RouteEditorStory(
            preset = routeStoryMeetingRoute,
            page = RouteEditorPage.QUICK_ACTIONS,
            captureBar = CaptureBarConfiguration().withRoutePins(ROUTE_MEETINGS_ID, CaptureBarAction.entries),
        )

        // Identity
        "routes-identity-symbol" -> RouteSectionStory { IdentityStory(symbol = "work", emoji = null) }
        "routes-identity-emoji" -> RouteSectionStory { IdentityStory(symbol = "favorite", emoji = "📓") }
        "routes-identity-none" -> RouteSectionStory { IdentityStory(symbol = "", emoji = null) }

        // Destination
        "routes-destination-folder" -> RouteSectionStory {
            DestinationStory(routeStoryPreset(ROUTE_INBOX_ID, "Inbox", "Inbox", "capture-{id}.md"))
        }
        "routes-destination-daily" -> RouteSectionStory {
            DestinationStory(
                routeStoryPreset(ROUTE_JOURNAL_ID, "Journal", "Journal/Daily", "{period}.md")
                    .copy(noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE, placement = CapturePlacementKind.APPEND),
            )
        }
        "routes-destination-weekly-heading" -> RouteSectionStory {
            DestinationStory(
                routeStoryPreset(ROUTE_JOURNAL_ID, "Journal", "Journal/Weekly", "{period}.md").copy(
                    noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE,
                    rollingPeriod = CaptureRollingPeriod.WEEKLY,
                    placement = CapturePlacementKind.BENEATH_HEADING,
                    headingTitle = "Log",
                    headingLevel = 2,
                ),
            )
        }
        "routes-destination-single-file" -> RouteSectionStory {
            DestinationStory(
                routeStoryPreset(ROUTE_TASKS_ID, "Tasks", "", "").copy(
                    noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE,
                    existingNotePath = "Tasks.md",
                    placement = CapturePlacementKind.BENEATH_HEADING,
                    headingTitle = "Today",
                    headingLevel = 2,
                ),
            )
        }
        "routes-destination-prepend" -> RouteSectionStory {
            DestinationStory(
                routeStoryPreset(ROUTE_TASKS_ID, "Tasks", "", "").copy(
                    noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE,
                    existingNotePath = "Tasks.md",
                    placement = CapturePlacementKind.PREPEND,
                ),
            )
        }
        "routes-destination-template-linked" -> RouteSectionStory {
            DestinationStory(
                routeStoryPreset(ROUTE_MEETINGS_ID, "Meetings", "Meetings", "{date}-meeting.md").copy(
                    entryTemplateID = routeStoryTemplates.first().id,
                    entryPrefix = routeStoryTemplates.first().entryPrefix,
                ),
            )
        }

        // Metadata
        "routes-metadata" -> RouteSectionStory { MetadataStory("source=android\ntags=inbox") }
        "routes-metadata-invalid" -> RouteSectionStory { MetadataStory("source=android\nbad key!=value\nsource=dup") }

        // Voice
        "routes-voice" -> RouteSectionStory {
            VoiceStory(CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE, CaptureAudioSaveMode.OFF, false)
        }
        "routes-voice-audio" -> RouteSectionStory {
            VoiceStory(CaptureWatchOutputMode.TRANSCRIBE_AND_CAPTURE, CaptureAudioSaveMode.ATTACHMENTS_FOLDER, true)
        }
        "routes-voice-recording-only" -> RouteSectionStory {
            VoiceStory(CaptureWatchOutputMode.RECORDING_ONLY, CaptureAudioSaveMode.ALONGSIDE_NOTE, false)
        }

        // Transcript export
        "routes-export-off" -> RouteSectionStory {
            ExportStory(CapturePresetExportSettings(usesCustomExportSettings = true, exportEnabled = false), CaptureAudioSaveMode.OFF)
        }
        "routes-export-missing-folder" -> RouteSectionStory {
            ExportStory(
                CapturePresetExportSettings(usesCustomExportSettings = true, exportEnabled = true, markdownTemplateEnabled = true),
                CaptureAudioSaveMode.OFF,
            )
        }
        "routes-export-markdown" -> RouteSectionStory {
            ExportStory(
                CapturePresetExportSettings(
                    usesCustomExportSettings = true,
                    exportEnabled = true,
                    destinationTreeUri = "content://md.vox.android.visual/exports",
                    destinationName = "Transcripts",
                    mdObsidianEnabled = true,
                    embedAudioInMarkdown = true,
                ),
                CaptureAudioSaveMode.ATTACHMENTS_FOLDER,
            )
        }
        "routes-export-yaml" -> RouteSectionStory {
            ExportStory(
                CapturePresetExportSettings(
                    usesCustomExportSettings = true,
                    exportEnabled = true,
                    destinationTreeUri = "content://md.vox.android.visual/exports",
                    destinationName = "Transcripts",
                    format = CaptureExportFileFormat.YAML,
                    mode = CaptureExportFileMode.APPEND,
                ),
                CaptureAudioSaveMode.OFF,
            )
        }

        // Processing
        "routes-processing-off" -> RouteSectionStory { ProcessingStory(enabled = false, mode = CaptureProcessingMode.CLEAN) }
        "routes-processing" -> RouteSectionStory { ProcessingStory(enabled = true, mode = CaptureProcessingMode.TODO_LIST) }
        "routes-processing-custom" -> RouteSectionStory { ProcessingStory(enabled = true, mode = CaptureProcessingMode.CUSTOM) }

        // Location
        "routes-location-off" -> RouteSectionStory { LocationStory(CapturePresetLocationPolicy()) }
        "routes-location-structured" -> RouteSectionStory {
            LocationStory(
                CapturePresetLocationPolicy(
                    isEnabled = true,
                    metadataOutputEnabled = true,
                    structuredFields = DEFAULT_CAPTURE_LOCATION_FIELDS + CaptureLocationStructuredField(CaptureLocationField.CITY),
                    labelLookupClass = CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK,
                    labelConsentVersion = CURRENT_LOCATION_LABEL_CONSENT_VERSION,
                ),
            )
        }
        "routes-location-advanced" -> RouteSectionStory {
            LocationStory(
                CapturePresetLocationPolicy(
                    isEnabled = true,
                    metadataOutputEnabled = true,
                    outputMode = CaptureLocationOutputMode.ADVANCED_YAML,
                    advancedTemplate = "lat: {latitude}\nlon: {longitude}",
                ),
            )
        }
        "routes-location-invalid" -> RouteSectionStory {
            LocationStory(
                CapturePresetLocationPolicy(
                    isEnabled = true,
                    metadataOutputEnabled = true,
                    collectionKey = "1 bad key",
                    structuredFields = DEFAULT_CAPTURE_LOCATION_FIELDS +
                        CaptureLocationStructuredField(CaptureLocationField.PLACE, outputKey = "id"),
                ),
            )
        }

        // Widget configuration
        "routes-widget-follow" -> PresetWidgetConfigurationScreen(routeStoryCollection.presets, PresetWidgetSelection(), {}, {})
        "routes-widget-custom" -> PresetWidgetConfigurationScreen(
            routeStoryCollection.presets,
            PresetWidgetSelection(PresetWidgetSource.CUSTOM, listOf(ROUTE_INBOX_ID, ROUTE_MEETINGS_ID, null, ROUTE_JOURNAL_ID, null, null)),
            {},
            {},
        )

        else -> return false
    }
    return true
}

private const val ROUTE_INBOX_ID = "a1a1a1a1-a1a1-4a1a-8a1a-a1a1a1a1a1a1"
private const val ROUTE_MEETINGS_ID = "b2b2b2b2-b2b2-4b2b-8b2b-b2b2b2b2b2b2"
private const val ROUTE_JOURNAL_ID = "c3c3c3c3-c3c3-4c3c-8c3c-c3c3c3c3c3c3"
private const val ROUTE_TASKS_ID = "d4d4d4d4-d4d4-4d4d-8d4d-d4d4d4d4d4d4"
private const val ROUTE_TRAVEL_ID = "e5e5e5e5-e5e5-4e5e-8e5e-e5e5e5e5e5e5"

private fun routeStoryPreset(
    id: String,
    name: String,
    folder: String,
    file: String,
    symbol: String = "description",
    isPinned: Boolean = false,
) = CapturePreset(
    id = id,
    name = name,
    symbol = symbol,
    revision = 1,
    logicalFolder = folder,
    noteNameTemplate = file,
    metadataFields = emptyList(),
    isPinned = isPinned,
)

/** Inbox (indigo) and Meetings (ink) are pinned first; the rest are neutral; Travel is disabled. */
private val routeStoryCollection = CapturePresetCollection(
    activePresetID = ROUTE_INBOX_ID,
    presets = listOf(
        routeStoryPreset(ROUTE_INBOX_ID, "Inbox", "Inbox", "{title}.md", symbol = "mic", isPinned = true),
        routeStoryPreset(ROUTE_MEETINGS_ID, "Meetings", "Meetings", "{date}-meeting.md", symbol = "work", isPinned = true).copy(
            metadataFields = listOf(CaptureMetadataField("type", "meeting")),
            entryTemplateID = "44444444-4444-4444-8444-444444444444",
            entryPrefix = "- {time} ",
        ),
        routeStoryPreset(ROUTE_JOURNAL_ID, "Journal", "Journal", "{period}.md", symbol = "favorite").copy(
            emoji = "📓",
            noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE,
        ),
        routeStoryPreset(ROUTE_TASKS_ID, "Tasks", "", "", symbol = "checklist").copy(
            noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE,
            existingNotePath = "Tasks.md",
            placement = CapturePlacementKind.BENEATH_HEADING,
            headingTitle = "Today",
        ),
        routeStoryPreset(ROUTE_TRAVEL_ID, "Travel", "Travel", "{date}-travel.md", symbol = "lightbulb").copy(isEnabled = false),
    ),
)

private val routeStoryTemplates = listOf(
    CaptureEntryTemplate(id = "44444444-4444-4444-8444-444444444444", name = "Meeting bullet", entryPrefix = "- {time} "),
    CaptureEntryTemplate(
        id = "45454545-4545-4545-8545-454545454545",
        name = "Timestamped heading",
        entryPrefix = "### {time}\n",
        entrySuffix = "\n",
    ),
)

/** Meeting Notes from the Route editor board: meeting summary into a daily note under "## Notes". */
private val routeStoryMeetingRoute = routeStoryCollection.presets[1].copy(
    name = "Meeting Notes",
    logicalFolder = "Meetings",
    noteNameTemplate = "{date}.md",
    noteTargetKind = CaptureNoteTargetKind.ROLLING_NOTE,
    placement = CapturePlacementKind.BENEATH_HEADING,
    headingTitle = "Notes",
    headingLevel = 2,
    headingPosition = CaptureHeadingPosition.BOTTOM,
    entryTemplateID = null,
    entryPrefix = "### {time} · {title}\n",
    processingEnabled = true,
    processingMode = CaptureProcessingMode.MEETING_NOTES,
    speakerDiarizationEnabled = true,
    audioSaveMode = CaptureAudioSaveMode.ATTACHMENTS_FOLDER,
    embedAudioInMarkdown = true,
)

private val routeStoryCustomBar = CaptureBarConfiguration().withRoutePins(
    ROUTE_MEETINGS_ID,
    listOf(
        CaptureBarAction.TIMESTAMP,
        CaptureBarAction.CHECKLIST,
        CaptureBarAction.INTERNAL_LINK,
        CaptureBarAction.FORMAT_MARKDOWN,
        CaptureBarAction.BULLET_LIST,
        CaptureBarAction.ADD_MEDIA,
    ),
)

@Composable
private fun RouteListStory(collection: CapturePresetCollection?, templates: List<CaptureEntryTemplate>, isBusy: Boolean = false) {
    CapturePresetsScreen(
        collection = collection,
        entryTemplates = templates,
        isBusy = isBusy,
        navigateBack = {},
        selectPreset = {},
        editPreset = {},
        createPreset = {},
        saveEntryTemplate = {},
        deleteEntryTemplate = {},
        defaultDestinationName = "Vox Notes",
        togglePinned = {},
    )
}

@Composable
private fun RouteTemplateDialogStory(template: CaptureEntryTemplate?) {
    RouteListStory(routeStoryCollection, routeStoryTemplates)
    EntryTemplateEditorDialog(
        template = template,
        isBusy = false,
        dismiss = {},
        save = {},
        delete = template?.let { { } },
    )
}

@Composable
private fun RouteEditorStory(
    preset: CapturePreset?,
    isBusy: Boolean = false,
    isDefault: Boolean = false,
    page: RouteEditorPage? = null,
    captureBar: CaptureBarConfiguration = CaptureBarConfiguration(),
) {
    // Quick actions apply immediately, so the story keeps them in local state.
    var bar by remember { mutableStateOf(captureBar) }
    CapturePresetEditorScreen(
        preset = preset,
        entryTemplates = routeStoryTemplates,
        isBusy = isBusy,
        navigateBack = {},
        save = {},
        delete = preset?.let { { } },
        isDefault = isDefault,
        defaultDestinationName = "Vox Notes",
        captureBar = bar,
        setRouteQuickActions = { routeID, actions -> bar = bar.withRoutePins(routeID, actions) },
        initialPage = page,
    )
}

/** One editor section on the page ground, scrollable, for focused screenshots. */
@Composable
private fun RouteSectionStory(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Signal.colors.bg)
            .systemBarsPadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
        content = content,
    )
}

@Composable
private fun IdentityStory(symbol: String, emoji: String?) {
    var draft by remember {
        mutableStateOf(CapturePresetEditorDraft.from(routeStoryCollection.presets[2].copy(symbol = symbol, emoji = emoji)))
    }
    CapturePresetIdentityEditor(
        name = draft.name,
        symbol = draft.symbol,
        emoji = draft.emoji,
        isEnabled = draft.isEnabled,
        isPinned = draft.isPinned,
        setName = { draft = draft.copy(name = it) },
        setSymbol = { draft = draft.copy(symbol = it, emoji = null) },
        setEmoji = { draft = draft.copy(emoji = it) },
        setEnabled = { draft = draft.copy(isEnabled = it) },
        setPinned = { draft = draft.copy(isPinned = it) },
    )
}

@Composable
private fun DestinationStory(preset: CapturePreset) {
    var draft by remember { mutableStateOf(CapturePresetEditorDraft.from(preset)) }
    CapturePresetDestinationEditor(
        noteTargetKind = draft.noteTargetKind,
        rollingPeriod = draft.rollingPeriod,
        logicalFolder = draft.logicalFolder,
        noteNameTemplate = draft.noteNameTemplate,
        existingNotePath = draft.existingNotePath,
        placement = draft.placement,
        headingTitle = draft.headingTitle,
        headingLevel = draft.headingLevel,
        missingHeadingBehavior = draft.missingHeadingBehavior,
        entryPrefix = draft.entryPrefix,
        entrySuffix = draft.entrySuffix,
        entryTemplateID = draft.entryTemplateID,
        entryTemplates = routeStoryTemplates,
        attachmentsFolder = draft.attachmentsFolder,
        retryProtectionEnabled = draft.retryProtectionEnabled,
        setNoteTargetKind = { draft = draft.copy(noteTargetKind = it) },
        setRollingPeriod = { draft = draft.copy(rollingPeriod = it) },
        setLogicalFolder = { draft = draft.copy(logicalFolder = it) },
        setNoteNameTemplate = { draft = draft.copy(noteNameTemplate = it) },
        setExistingNotePath = { draft = draft.copy(existingNotePath = it) },
        setPlacement = { draft = draft.copy(placement = it) },
        setHeadingTitle = { draft = draft.copy(headingTitle = it) },
        setHeadingLevel = { draft = draft.copy(headingLevel = it) },
        setMissingHeadingBehavior = { draft = draft.copy(missingHeadingBehavior = it) },
        setEntryPrefix = { draft = draft.copy(entryPrefix = it) },
        setEntrySuffix = { draft = draft.copy(entrySuffix = it) },
        setEntryTemplateID = { id -> draft = draft.copy(entryTemplateID = id) },
        setAttachmentsFolder = { draft = draft.copy(attachmentsFolder = it) },
        setRetryProtectionEnabled = { draft = draft.copy(retryProtectionEnabled = it) },
    )
}

@Composable
private fun MetadataStory(text: String) {
    var draft by remember { mutableStateOf(CapturePresetEditorDraft.from(null).copy(metadataText = text)) }
    CapturePresetMetadataEditor(
        metadataScope = draft.metadataScope,
        metadataText = draft.metadataText,
        metadataIsValid = parseMetadataFields(draft.metadataText) != null,
        setMetadataScope = { draft = draft.copy(metadataScope = it) },
        setMetadataText = { draft = draft.copy(metadataText = it) },
    )
}

@Composable
private fun VoiceStory(watch: CaptureWatchOutputMode, audio: CaptureAudioSaveMode, embed: Boolean) {
    var draft by remember {
        mutableStateOf(CapturePresetEditorDraft.from(null).copy(watchOutputMode = watch, audioSaveMode = audio, embedAudio = embed))
    }
    CapturePresetVoiceEditor(
        speakerDiarizationEnabled = draft.speakerDiarizationEnabled,
        watchOutputMode = draft.watchOutputMode,
        audioSaveMode = draft.audioSaveMode,
        embedAudio = draft.embedAudio,
        audioEmbedPlacement = draft.audioEmbedPlacement,
        setSpeakerDiarizationEnabled = { draft = draft.copy(speakerDiarizationEnabled = it) },
        setWatchOutputMode = { draft = draft.copy(watchOutputMode = it) },
        setAudioSaveMode = { draft = draft.copy(audioSaveMode = it) },
        setEmbedAudio = { draft = draft.copy(embedAudio = it) },
        setAudioEmbedPlacement = { draft = draft.copy(audioEmbedPlacement = it) },
    )
}

@Composable
private fun ExportStory(settings: CapturePresetExportSettings, audio: CaptureAudioSaveMode) {
    var current by remember { mutableStateOf(settings) }
    CapturePresetTranscriptExportEditor(
        settings = current,
        audioSaveMode = audio,
        attachmentsFolder = "Attachments",
        onSettingsChanged = { current = it },
    )
}

@Composable
private fun ProcessingStory(enabled: Boolean, mode: CaptureProcessingMode) {
    var draft by remember {
        mutableStateOf(
            CapturePresetEditorDraft.from(null).copy(
                processingEnabled = enabled,
                processingMode = mode,
                customInstruction = if (mode == CaptureProcessingMode.CUSTOM) "Rewrite as a short status update." else "",
            ),
        )
    }
    CapturePresetProcessingEditor(
        processingEnabled = draft.processingEnabled,
        processingScope = draft.processingScope,
        processingMode = draft.processingMode,
        customInstruction = draft.customInstruction,
        generateImageAltText = draft.generateImageAltText,
        setProcessingEnabled = { draft = draft.copy(processingEnabled = it) },
        setProcessingScope = { draft = draft.copy(processingScope = it) },
        setProcessingMode = { draft = draft.copy(processingMode = it) },
        setCustomInstruction = { draft = draft.copy(customInstruction = it) },
        setGenerateImageAltText = { draft = draft.copy(generateImageAltText = it) },
    )
}

@Composable
private fun LocationStory(policy: CapturePresetLocationPolicy) {
    var draft by remember {
        mutableStateOf(
            CapturePresetEditorDraft.from(
                routeStoryPreset(ROUTE_INBOX_ID, "Inbox", "Inbox", "{title}.md").copy(locationPolicy = policy),
            ),
        )
    }
    CapturePresetLocationEditor(
        locationEnabled = draft.locationEnabled,
        locationPrecision = draft.locationPrecision,
        locationUnavailableBehavior = draft.locationUnavailableBehavior,
        locationMetadataEnabled = draft.locationMetadataEnabled,
        locationOutputMode = draft.locationOutputMode,
        locationStructuredFields = draft.locationStructuredFields,
        locationCollectionKey = draft.locationCollectionKey,
        locationAdvancedTemplate = draft.locationAdvancedTemplate,
        locationLabelLookupClass = draft.locationLabelLookupClass,
        locationLabelConsentVersion = draft.locationLabelConsentVersion,
        setLocationEnabled = { draft = draft.copy(locationEnabled = it) },
        setLocationPrecision = { draft = draft.copy(locationPrecision = it) },
        setLocationUnavailableBehavior = { draft = draft.copy(locationUnavailableBehavior = it) },
        setLocationMetadataEnabled = { draft = draft.copy(locationMetadataEnabled = it) },
        setLocationOutputMode = { draft = draft.copy(locationOutputMode = it) },
        setLocationStructuredFields = { draft = draft.copy(locationStructuredFields = it) },
        setLocationCollectionKey = { draft = draft.copy(locationCollectionKey = it) },
        setLocationAdvancedTemplate = { draft = draft.copy(locationAdvancedTemplate = it) },
        setLocationLabelConsent = { consented ->
            draft = draft.copy(
                locationLabelLookupClass = if (consented) {
                    CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK
                } else {
                    CaptureLocationLabelLookupClass.NONE
                },
                locationLabelConsentVersion = if (consented) CURRENT_LOCATION_LABEL_CONSENT_VERSION else null,
            )
        },
    )
}
