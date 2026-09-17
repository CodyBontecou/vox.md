package md.vox.android

import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.hasScrollToIndexAction
import androidx.compose.ui.test.performScrollToIndex
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.capturedomain.CaptureComposerCommand
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CaptureBarUiInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun captureBarMenusAndActionsDispatchEveryEditorCommand() {
        var action by mutableStateOf(CaptureBarAction.FORMAT_MARKDOWN)
        val commands = mutableListOf<CaptureComposerCommand>()
        var pasted = 0
        var undone = 0
        val launchedActions = mutableListOf<CaptureBarAction>()
        var dueDate: String? = null
        var dueDateDialog by mutableStateOf(false)
        compose.setContent {
            VoxTheme {
                Surface {
                    CaptureBarActionItem(
                        action = action,
                        usesTwentyFourHourTimestamps = true,
                        canUndo = true,
                        addLink = {},
                        addMedia = { launchedActions += CaptureBarAction.ADD_MEDIA },
                        addFiles = { launchedActions += CaptureBarAction.ADD_FILES },
                        scanDocument = { launchedActions += CaptureBarAction.SCAN_DOCUMENT },
                        extractText = { launchedActions += CaptureBarAction.EXTRACT_TEXT },
                        addSketch = { launchedActions += CaptureBarAction.SKETCH },
                        addCurrentLocation = { launchedActions += CaptureBarAction.CURRENT_LOCATION },
                        undo = { undone += 1 },
                        editorCommand = commands::add,
                        paste = { pasted += 1 },
                        showDueDate = { dueDateDialog = true },
                    )
                    if (dueDateDialog) {
                        DueDateDialog(
                            onDismiss = { dueDateDialog = false },
                            onInsert = {
                                dueDate = it
                                dueDateDialog = false
                            },
                        )
                    }
                }
            }
        }

        val formatCases = listOf(
            "Bold" to CaptureComposerCommand.ToggleBold,
            "Italic" to CaptureComposerCommand.ToggleItalic,
            "Hashtag" to CaptureComposerCommand.InsertHashtag,
            "Heading 1" to CaptureComposerCommand.Heading(1),
            "Heading 6" to CaptureComposerCommand.Heading(6),
        )
        formatCases.forEach { (label, expected) ->
            compose.onNodeWithContentDescription("Format Markdown").performClick()
            compose.onNodeWithText(label).performClick()
            compose.runOnIdle { assertEquals(expected, commands.last()) }
        }

        directAction(compose, { action = CaptureBarAction.MARKDOWN_LINK }, "Markdown link")
        compose.runOnIdle { assertEquals(CaptureComposerCommand.MarkdownLink(), commands.last()) }
        directAction(compose, { action = CaptureBarAction.CHECKLIST }, "Checklist")
        compose.runOnIdle { assertEquals(CaptureComposerCommand.TaskCheckbox, commands.last()) }
        directAction(compose, { action = CaptureBarAction.BULLET_LIST }, "Bullet list")
        compose.runOnIdle { assertEquals(CaptureComposerCommand.Bullet, commands.last()) }
        directAction(compose, { action = CaptureBarAction.INTERNAL_LINK }, "Internal link")
        compose.runOnIdle { assertEquals(CaptureComposerCommand.WikiLink(), commands.last()) }

        compose.runOnIdle { action = CaptureBarAction.TEXT_CASE }
        listOf(
            "Lowercase" to CaptureComposerCommand.Lowercase,
            "Uppercase" to CaptureComposerCommand.Uppercase,
            "Sentence case" to CaptureComposerCommand.SentenceCase,
            "Capitalize case" to CaptureComposerCommand.CapitalizeWords,
            "Slugify case" to CaptureComposerCommand.Slugify,
        ).forEach { (label, expected) ->
            compose.onNodeWithContentDescription("Change text case").performClick()
            compose.onNodeWithText(label).performClick()
            compose.runOnIdle { assertEquals(expected, commands.last()) }
        }

        directAction(compose, { action = CaptureBarAction.DATE }, "Insert date")
        compose.runOnIdle {
            val value = (commands.last() as CaptureComposerCommand.ReplaceSelection).replacement
            assertTrue(Regex("^\\d{4}-\\d{2}-\\d{2}$").matches(value))
        }
        directAction(compose, { action = CaptureBarAction.TIMESTAMP }, "Insert timestamp")
        compose.runOnIdle {
            val value = (commands.last() as CaptureComposerCommand.ReplaceSelection).replacement
            assertTrue(Regex("^\\d{2}:\\d{2} \\d{4}-\\d{2}-\\d{2}$").matches(value))
        }
        directAction(compose, { action = CaptureBarAction.PASTE }, "Paste")
        directAction(compose, { action = CaptureBarAction.UNDO }, "Undo")
        directAction(compose, { action = CaptureBarAction.ADD_MEDIA }, "Add media")
        directAction(compose, { action = CaptureBarAction.ADD_FILES }, "Add files")
        directAction(compose, { action = CaptureBarAction.SCAN_DOCUMENT }, "Scan document")
        directAction(compose, { action = CaptureBarAction.EXTRACT_TEXT }, "Extract text from journal images")
        directAction(compose, { action = CaptureBarAction.SKETCH }, "Sketch")
        directAction(compose, { action = CaptureBarAction.CURRENT_LOCATION }, "Insert current location")
        directAction(compose, { action = CaptureBarAction.DUE_DATE }, "Set due date")
        compose.onNodeWithText("Today", substring = true).performClick()
        compose.runOnIdle {
            assertEquals(1, pasted)
            assertEquals(1, undone)
            assertEquals(
                listOf(
                    CaptureBarAction.ADD_MEDIA,
                    CaptureBarAction.ADD_FILES,
                    CaptureBarAction.SCAN_DOCUMENT,
                    CaptureBarAction.EXTRACT_TEXT,
                    CaptureBarAction.SKETCH,
                    CaptureBarAction.CURRENT_LOCATION,
                ),
                launchedActions,
            )
            assertTrue(Regex("^\\(@\\d{4}-\\d{2}-\\d{2}\\)$").matches(requireNotNull(dueDate)))
        }
    }

    @Test
    fun captureBarSettingsDispatchVisibilityAndOrderChanges() {
        var visibility: Pair<CaptureBarAction, Boolean>? = null
        var movement: Pair<CaptureBarAction, Int>? = null
        var voiceConfirmation: Boolean? = null
        val configuration = CaptureBarConfiguration(
            orderedActions = listOf(CaptureBarAction.ADD_MEDIA, CaptureBarAction.ADD_FILES) +
                CaptureBarAction.entries.filterNot { it == CaptureBarAction.ADD_MEDIA || it == CaptureBarAction.ADD_FILES },
        )
        compose.setContent {
            VoxTheme {
                Surface {
                    CaptureBarSettingsScreen(
                        configuration = configuration,
                        isBusy = false,
                        navigateBack = {},
                        setVisible = { action, visible -> visibility = action to visible },
                        move = { action, direction -> movement = action to direction },
                        setTwentyFourHour = {},
                        setVoiceConfirmation = { voiceConfirmation = it },
                        reset = {},
                    )
                }
            }
        }

        compose.onNodeWithContentDescription("Show: Add Media").performClick()
        compose.onNodeWithContentDescription("Move Down: Add Media").performClick()
        compose.onNode(hasScrollToIndexAction()).performScrollToIndex(configuration.orderedActions.size + 1)
        compose.onNodeWithContentDescription("Review Before Adding").performClick()
        compose.runOnIdle {
            assertEquals(CaptureBarAction.ADD_MEDIA to false, visibility)
            assertEquals(CaptureBarAction.ADD_MEDIA to 1, movement)
            assertEquals(true, voiceConfirmation)
        }
    }

    @Test
    fun voiceConfirmationKeepsManualReviewOrAutomaticallyAddsTheFinishedTranscript() {
        var confirmsBeforeAdding by mutableStateOf(true)
        var transcription by mutableStateOf(
            RecordingTranscriptionState(
                sessionID = "11111111-1111-4111-8111-111111111111",
                phase = RecordingTranscriptionPhase.COMPLETED,
                transcript = "raw voice words",
                cleanedTranscript = "Reviewed voice note.",
            ),
        )
        val added = mutableListOf<String>()
        compose.setContent {
            VoxTheme {
                Surface {
                    RecordingTranscriptCompletionEffect(
                        transcription = transcription,
                        confirmsVoiceNotesBeforeAdding = confirmsBeforeAdding,
                        addToDraft = added::add,
                    )
                    RecordingDetails(
                        status = RecordingStatus(
                            sessionID = transcription.sessionID,
                            phase = RecordingPhase.COMPLETED,
                            elapsedMillis = 12_000,
                            chunkCount = 1,
                        ),
                        transcription = transcription,
                        liveSpeech = null,
                        start = {},
                        pause = {},
                        resume = {},
                        stop = {},
                        cancel = {},
                        dismiss = {},
                        close = {},
                        process = {},
                        cancelProcessing = {},
                        addToDraft = added::add,
                        sendWithPreset = {},
                    )
                }
            }
        }

        compose.runOnIdle { assertTrue(added.isEmpty()) }
        compose.onNodeWithText("Add to Draft").performClick()
        compose.runOnIdle { assertEquals(listOf("Reviewed voice note."), added) }

        compose.runOnIdle {
            transcription = transcription.copy(
                sessionID = "22222222-2222-4222-8222-222222222222",
                transcript = "automatic raw",
                cleanedTranscript = "Automatic voice note.",
            )
            confirmsBeforeAdding = false
        }
        compose.waitForIdle()
        compose.runOnIdle {
            assertEquals(listOf("Reviewed voice note.", "Automatic voice note."), added)
        }
    }

    @Test
    fun sendImmediatelyResultSubmitsTheFinishedTranscriptWithoutDrafting() {
        var transcription by mutableStateOf(
            RecordingTranscriptionState(
                sessionID = "33333333-3333-4333-8333-333333333333",
                phase = RecordingTranscriptionPhase.COMPLETED,
                transcript = "raw send words",
                cleanedTranscript = "Send immediately voice note.",
            ),
        )
        val drafted = mutableListOf<String>()
        val sent = mutableListOf<String>()
        var markedAdded = 0
        compose.setContent {
            VoxTheme {
                Surface {
                    RecordingTranscriptCompletionEffect(
                        transcription = transcription,
                        confirmsVoiceNotesBeforeAdding = false,
                        addToDraft = drafted::add,
                        voiceRecordingResult = VoiceRecordingResult.SEND_IMMEDIATELY,
                        sendWithPreset = sent::add,
                        markRecordingAdded = { markedAdded += 1 },
                    )
                }
            }
        }

        compose.runOnIdle {
            assertEquals(listOf("Send immediately voice note."), sent)
            assertTrue(drafted.isEmpty())
            assertEquals(1, markedAdded)
        }

        // A new recording sends exactly once; the consumed transcript never
        // falls back into the composer.
        compose.runOnIdle {
            transcription = transcription.copy(
                sessionID = "44444444-4444-4444-8444-444444444444",
                cleanedTranscript = "Second voice note.",
            )
        }
        compose.waitForIdle()
        compose.runOnIdle {
            assertEquals(listOf("Send immediately voice note.", "Second voice note."), sent)
            assertTrue(drafted.isEmpty())
            assertEquals(2, markedAdded)
        }
    }

    private fun directAction(
        compose: androidx.compose.ui.test.junit4.ComposeContentTestRule,
        select: () -> Unit,
        contentDescription: String,
    ) {
        compose.runOnIdle(select)
        compose.onNodeWithContentDescription(contentDescription).performClick()
    }
}
