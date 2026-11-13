package md.vox.android

import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import md.vox.android.capturedomain.*
import md.vox.android.ui.VoxTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class RouteEditorEdgeCaseTest {
    @get:Rule val compose = createComposeRule()

    @Test fun unsavedIdentityAndNestedDeliveryEditsSurviveRestoration() {
        val restoration = StateRestorationTester(compose)
        var saved: CapturePreset? = null
        restoration.setContent {
            VoxTheme { CapturePresetEditorScreen(null, emptyList(), false, {}, { saved = it }, null) }
        }
        compose.onNode(hasText("Name") and hasSetTextAction()).performTextInput("QA 🧪 עברית")
        compose.onNodeWithText("Pinned", substring = true).performClick()
        compose.onNodeWithTag("route_step_4").performScrollTo().performClick()
        compose.onNodeWithText("Folder").performTextReplacement("Odd/日本語")
        compose.onNodeWithText("Note filename template").performTextReplacement("edge-{id}.MD")
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("Odd/日本語").assertExists()
        compose.onNodeWithText("edge-{id}.MD").assertExists()
        compose.onNodeWithContentDescription("Back").performClick()
        compose.onNodeWithTag("capture_preset_editor_done").assertIsEnabled().performClick()
        compose.runOnIdle {
            assertEquals("QA 🧪 עברית", saved?.name)
            assertEquals("Odd/日本語", saved?.logicalFolder)
            assertEquals("edge-{id}.MD", saved?.noteNameTemplate)
            assertTrue(requireNotNull(saved).isPinned)
        }
    }

    @Test fun traversalAndFilenameSeparatorsDisableDoneUntilCorrected() {
        compose.setContent {
            VoxTheme { CapturePresetEditorScreen(
                CapturePresetEditorDraft.from(null).copy(name = "QA").toPreset(1, emptyList()),
                emptyList(), false, {}, {}, null, initialPage = RouteEditorPage.DELIVER,
            ) }
        }
        compose.onNodeWithText("Folder").performTextReplacement("../escape")
        compose.onNodeWithContentDescription("Back").performClick()
        compose.onNodeWithTag("capture_preset_editor_done").assertIsNotEnabled()
        compose.onNodeWithTag("route_step_4").performScrollTo().performClick()
        compose.onNodeWithText("Folder").performTextReplacement("Valid")
        compose.onNodeWithText("Note filename template").performTextReplacement("nested/note.md")
        compose.onNodeWithContentDescription("Back").performClick()
        compose.onNodeWithTag("capture_preset_editor_done").assertIsNotEnabled()
        compose.onNodeWithTag("route_step_4").performScrollTo().performClick()
        compose.onNodeWithText("Note filename template").performTextReplacement("note.md")
        compose.onNodeWithContentDescription("Back").performClick()
        compose.onNodeWithTag("capture_preset_editor_done").assertIsEnabled()
    }

    @Test fun rawInvalidDraftAndNestedSettingsSurviveSavedStateWithoutNormalization() {
        val original = CapturePresetEditorDraft.from(null).copy(
            name = "QA 🧪", emoji = "🧪", isEnabled = false, isPinned = true,
            noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE, rollingPeriod = CaptureRollingPeriod.YEARLY,
            logicalFolder = "../incomplete", noteNameTemplate = "unfinished", existingNotePath = "Journal/Test.md",
            placement = CapturePlacementKind.BENEATH_HEADING, headingTitle = "Heading", headingLevel = 6,
            missingHeadingBehavior = CaptureMissingHeadingBehavior.CREATE, headingPosition = CaptureHeadingPosition.BOTTOM,
            entryPrefix = "\n- {time} ", entrySuffix = "\n---", entryTemplateID = "linked", attachmentsFolder = "Media",
            retryProtectionEnabled = true, metadataScope = CaptureMetadataScope.ENTRY, metadataText = "incomplete metadata=\nraw",
            processingEnabled = true, processingMode = CaptureProcessingMode.CUSTOM, processingScope = CaptureProcessingScope.TEXT_ONLY,
            customInstruction = "Keep 🧪", capturePrompt = "Context", generateImageAltText = true, speakerDiarizationEnabled = true,
            locationEnabled = true, locationPrecision = CaptureLocationPrecision.CITY,
            locationUnavailableBehavior = CaptureLocationUnavailableBehavior.CANCEL, locationMetadataEnabled = true,
            locationOutputMode = CaptureLocationOutputMode.ADVANCED_YAML,
            locationStructuredFields = listOf(CaptureLocationStructuredField(CaptureLocationField.entries.last(), "custom_key")),
            locationCollectionKey = "places", locationAdvancedTemplate = "custom: {latitude}",
            locationLabelLookupClass = CaptureLocationLabelLookupClass.SYSTEM_MAY_USE_NETWORK, locationLabelConsentVersion = 7,
            audioSaveMode = CaptureAudioSaveMode.ATTACHMENTS_FOLDER, embedAudio = true,
            audioEmbedPlacement = CaptureAudioEmbedPlacement.BEFORE_TEXT, watchOutputMode = CaptureWatchOutputMode.RECORDING_ONLY,
            audioFilenameTemplate = "custom-{id}", destination = CaptureDestination("vault", "日本語", "content://vault"),
            transcriptPropertyName = "words", includeTranscriptInBody = false,
            urlDelivery = CaptureURLDeliverySettings(true, "credential-reference", "https://example.com", 9),
            exportSettings = CapturePresetExportSettings(
                true, true, CaptureExportFileFormat.YAML, CaptureExportFileMode.APPEND,
                "content://export", "Exports", "new-{id}", "append", true,
                "content://template", "Template", true, true, setOf(CaptureExportYAMLProperty.TEXT), true,
                CaptureAudioEmbedPlacement.BEFORE_TEXT,
            ),
        )
        lateinit var restored: CapturePresetEditorDraft
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            val draft by rememberSaveable(stateSaver = CapturePresetEditorDraftSaver) { mutableStateOf(original) }
            SideEffect { restored = draft }
        }
        restoration.emulateSavedInstanceStateRestore()
        compose.runOnIdle { assertEquals(original, restored) }
    }
}
