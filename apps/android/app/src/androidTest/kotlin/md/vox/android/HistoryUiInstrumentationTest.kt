package md.vox.android

import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertHasNoClickAction
import androidx.compose.ui.test.hasSetTextAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextReplacement
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.capturedomain.CaptureHistoryItem
import md.vox.android.capturedomain.CaptureState
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HistoryUiInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun completedCaptureHistoryRendersOnlyItsPayloadFreeMarkerAndCannotOpenContent() {
        var openedID: String? = null
        compose.setContent {
            VoxTheme {
                Surface {
                    HistoryScreen(
                        items = listOf(
                            CaptureHistoryItem(
                                requestID = TARGET_ID,
                                createdAtEpochMillis = 1_700_000_000_000,
                                updatedAtEpochMillis = 1_700_000_000_000,
                                state = CaptureState.COMPLETED,
                                attemptCount = 0,
                            ),
                        ),
                        transcripts = emptyList(),
                        isBusy = false,
                        navigateBack = {},
                        refresh = {},
                        retry = {},
                        repairAccess = {},
                        openDetail = { openedID = it },
                        openTranscript = {},
                        clearCompleted = {},
                    )
                }
            }
        }

        compose.onNodeWithText("Capture sent").assertIsDisplayed().assertHasNoClickAction()
        compose.onNodeWithText("App").assertDoesNotExist()
        compose.onNodeWithText("private captured body", substring = true).assertDoesNotExist()
        compose.runOnIdle { assertNull(openedID) }
    }

    @Test
    fun historySearchMatchesRawCleanedTitleTagsAndCategoryThenOpensOnlyTheMatch() {
        val target = transcript(
            id = TARGET_ID,
            raw = "raw microphone phrase",
            cleaned = "Cleaned shipping summary",
            title = "Résumé réunion",
            tags = listOf("client", "launch"),
            category = "Planning",
        )
        val decoy = transcript(
            id = DECOY_ID,
            raw = "unrelated words",
            cleaned = null,
            title = "Decoy transcript",
            tags = listOf("personal"),
            category = "Notes",
        )
        var openedID: String? = null
        compose.setContent {
            VoxTheme {
                Surface {
                    HistoryScreen(
                        items = emptyList(),
                        transcripts = listOf(target, decoy),
                        isBusy = false,
                        navigateBack = {},
                        refresh = {},
                        retry = {},
                        repairAccess = {},
                        openDetail = {},
                        openTranscript = { openedID = it },
                        clearCompleted = {},
                    )
                }
            }
        }

        val search = compose.onNode(hasSetTextAction() and hasText("Search History", substring = true))
        listOf("microphone", "shipping", "resume", "client launch", "planning").forEach { query ->
            search.performTextReplacement(query)
            compose.onNodeWithText("Résumé réunion").assertIsDisplayed()
            compose.onNodeWithText("Decoy transcript").assertDoesNotExist()
        }
        compose.onNodeWithText("Résumé réunion").performClick()
        compose.runOnIdle { assertEquals(TARGET_ID, openedID) }
    }

    @Test
    fun filteredTranscriptDeletionTargetsItsStableID() {
        val target = transcript(TARGET_ID, "needle raw", "Needle cleaned", "Delete target")
        val decoy = transcript(DECOY_ID, "other raw", null, "Keep target")
        var selectedID by mutableStateOf<String?>(null)
        var deletedID: String? = null
        compose.setContent {
            VoxTheme {
                Surface {
                    val selected = selectedID
                    if (selected == null) {
                        HistoryScreen(
                            items = emptyList(),
                            transcripts = listOf(target, decoy),
                            isBusy = false,
                            navigateBack = {},
                            refresh = {},
                            retry = {},
                            repairAccess = {},
                            openDetail = {},
                            openTranscript = { selectedID = it },
                            clearCompleted = {},
                        )
                    } else {
                        TranscriptDetailScreen(
                            state = listOf(target, decoy).first { it.sessionID == selected },
                            navigateBack = { selectedID = null },
                            save = { _, _, _, _, _, _ -> true },
                            delete = { deletedID = it },
                            addToDraft = { _, _ -> },
                        )
                    }
                }
            }
        }

        compose.onNode(hasSetTextAction() and hasText("Search History", substring = true))
            .performTextReplacement("needle")
        compose.onNodeWithText("Keep target").assertDoesNotExist()
        compose.onNodeWithText("Delete target").performClick()
        compose.onNodeWithText("Delete Transcript").performScrollTo().performClick()
        compose.onNodeWithText("Delete").performClick()
        compose.runOnIdle { assertEquals(TARGET_ID, deletedID) }
    }

    @Test
    fun transcriptEditorSavesRawCleanedAndOrganizationFields() {
        val state = transcript(TARGET_ID, "old raw", "Old cleaned", "Old title", listOf("old"), "Old category")
        var saved: SavedTranscript? = null
        compose.setContent {
            VoxTheme {
                Surface {
                    TranscriptDetailScreen(
                        state = state,
                        navigateBack = {},
                        save = { id, raw, cleaned, title, tags, category ->
                            saved = SavedTranscript(id, raw, cleaned, title, tags, category)
                            true
                        },
                        delete = {},
                        addToDraft = { _, _ -> },
                    )
                }
            }
        }

        compose.onNodeWithContentDescription("Edit transcript").performClick()
        replaceField("Title", "Edited title")
        replaceField("Tags, comma separated", "reviewed, launch")
        replaceField("Category", "Meeting")
        replaceField("Cleaned text", "Corrected clean text.")
        replaceField("Raw transcript", "corrected raw words")
        compose.onNodeWithText("Save").performScrollTo().performClick()

        compose.runOnIdle {
            assertEquals(
                SavedTranscript(
                    TARGET_ID,
                    "corrected raw words",
                    "Corrected clean text.",
                    "Edited title",
                    listOf("reviewed", "launch"),
                    "Meeting",
                ),
                saved,
            )
        }
    }

    @Test
    fun previousTranscriptCanBeSharedOrExportedFromItsDetail() {
        val state = transcript(TARGET_ID, "raw body", "Clean body", "Share target")
        var sharedText: String? = null
        var exported: Pair<String, TranscriptExportFormat>? = null
        compose.setContent {
            VoxTheme {
                Surface {
                    TranscriptDetailScreen(
                        state = state,
                        shareTranscript = { sharedText = it },
                        exportTranscript = { item, format -> exported = item.sessionID to format },
                        navigateBack = {},
                        save = { _, _, _, _, _, _ -> true },
                        delete = {},
                        addToDraft = { _, _ -> },
                    )
                }
            }
        }

        compose.runOnIdle { assertNull(sharedText) }
        compose.onNodeWithText("Share").performClick()
        compose.runOnIdle { assertEquals("Clean body", sharedText) }
        compose.onNodeWithText("Export").performClick()
        compose.onNodeWithText("Markdown").performClick()
        compose.runOnIdle { assertEquals(TARGET_ID to TranscriptExportFormat.MARKDOWN, exported) }
    }

    private fun replaceField(label: String, value: String) {
        compose.onNode(hasSetTextAction() and hasText(label, substring = true))
            .performScrollTo()
            .performTextReplacement(value)
    }

    private fun transcript(
        id: String,
        raw: String,
        cleaned: String?,
        title: String,
        tags: List<String> = emptyList(),
        category: String? = null,
    ) = RecordingTranscriptionState(
        sessionID = id,
        phase = RecordingTranscriptionPhase.COMPLETED,
        modelID = "local-model",
        modelName = "Local Model",
        languageTag = "en-US",
        durationMillis = 12_000,
        completedAtEpochMillis = 1_700_000_000_000,
        transcript = raw,
        cleanedTranscript = cleaned,
        title = title,
        tags = tags,
        category = category,
    )

    private data class SavedTranscript(
        val id: String,
        val raw: String,
        val cleaned: String,
        val title: String,
        val tags: List<String>,
        val category: String,
    )

    private companion object {
        const val TARGET_ID = "11111111-1111-4111-8111-111111111111"
        const val DECOY_ID = "22222222-2222-4222-8222-222222222222"
    }
}
