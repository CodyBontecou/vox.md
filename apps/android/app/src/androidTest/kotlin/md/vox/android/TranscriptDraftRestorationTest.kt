package md.vox.android

import androidx.compose.ui.test.*
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.runtime.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.VoxTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import androidx.test.filters.LargeTest

class TranscriptDraftRestorationTest {
    @get:Rule val compose = createComposeRule()
    private val transcript = RecordingTranscriptionState(
        sessionID = "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa",
        phase = RecordingTranscriptionPhase.COMPLETED,
        transcript = "Original raw", cleanedTranscript = "Original clean", title = "Original title",
    )

    @Test fun unsavedTranscriptAndMetadataSurviveRecreationAndSaveExactlyOnce() {
        var saves = 0
        var saved: List<Any>? = null
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            VoxTheme {
                TranscriptDetailScreen(
                    state = transcript, navigateBack = {},
                    save = { _, raw, clean, title, tags, category ->
                        saves++; saved = listOf(raw, clean, title, tags, category); true
                    }, delete = {}, addToDraft = { _, _ -> },
                )
            }
        }
        compose.onNodeWithContentDescription("Edit transcript").performClick()
        field("Title").performTextReplacement("QA 🧪 title")
        field("Tags, comma separated").performTextReplacement("日本語, test")
        field("Category").performTextReplacement("QA category")
        field("Cleaned text").performTextReplacement("QA clean\nשלום")
        field("Raw transcript").performTextReplacement("QA raw\nمرحبا")
        restoration.emulateSavedInstanceStateRestore()
        field("Title").assertTextContains("QA 🧪 title")
        field("Raw transcript").assertTextContains("QA raw\nمرحبا")
        compose.runOnIdle { assertEquals(0, saves) }
        compose.onNodeWithText("Save", useUnmergedTree = true).performScrollTo().performClick()
        compose.runOnIdle {
            assertEquals(1, saves)
            assertEquals(listOf("QA raw\nمرحبا", "QA clean\nשלום", "QA 🧪 title", listOf("日本語", "test"), "QA category"), saved)
        }
    }

    @Test fun lateTranscriptionPopulatesTheEditorWithoutReplacingUnsavedMetadata() {
        var source by mutableStateOf(transcript.copy(transcript = null, cleanedTranscript = null))
        compose.setContent {
            VoxTheme { TranscriptDetailScreen(
                state = source, navigateBack = {}, save = { _, _, _, _, _, _ -> true },
                delete = {}, addToDraft = { _, _ -> }, initialEditing = true,
            ) }
        }
        field("Title").performTextReplacement("Unsaved title")
        compose.runOnIdle { source = transcript.copy(title = "Updated source title") }
        field("Title").assertTextContains("Unsaved title")
        field("Raw transcript").assertTextContains("Original raw")
        field("Cleaned text").assertTextContains("Original clean")
    }

    @Test fun cancelAfterRecreationDiscardsEditsWithoutSaving() {
        var saves = 0
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            VoxTheme { TranscriptDetailScreen(
                state = transcript, navigateBack = {}, save = { _, _, _, _, _, _ -> saves++; true },
                delete = {}, addToDraft = { _, _ -> }, initialEditing = true,
            ) }
        }
        field("Raw transcript").performTextReplacement("Temporary edit")
        restoration.emulateSavedInstanceStateRestore()
        compose.onNodeWithText("Cancel").performScrollTo().performClick()
        compose.onNodeWithContentDescription("Edit transcript").performClick()
        field("Raw transcript").assertTextContains("Original raw")
        compose.runOnIdle { assertEquals(0, saves) }
    }

    @Test fun transientSourceReloadDoesNotOverwriteAnIntentionallyClearedField() {
        var source: RecordingTranscriptionState? by mutableStateOf(transcript)
        compose.setContent {
            VoxTheme { TranscriptDetailScreen(
                state = source, navigateBack = {}, save = { _, _, _, _, _, _ -> true },
                delete = {}, addToDraft = { _, _ -> }, initialEditing = true,
            ) }
        }
        field("Raw transcript").performTextClearance()
        compose.runOnIdle { source = null }
        compose.runOnIdle { source = transcript.copy(title = "Updated title") }
        assertEquals("", field("Raw transcript").fetchSemanticsNode().config[SemanticsProperties.EditableText].text)
        field("Title").assertTextContains("Updated title")
    }

    @Test fun switchingTranscriptsDoesNotReuseAnotherSessionsUnsavedDraft() {
        var source by mutableStateOf(transcript)
        compose.setContent {
            VoxTheme { TranscriptDetailScreen(
                state = source, navigateBack = {}, save = { _, _, _, _, _, _ -> true },
                delete = {}, addToDraft = { _, _ -> },
            ) }
        }
        compose.onNodeWithContentDescription("Edit transcript").performClick()
        field("Title").performTextReplacement("Other session must not see this")
        compose.runOnIdle { source = transcript.copy(sessionID = "bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb", title = "Other transcript") }
        compose.onNodeWithContentDescription("Edit transcript").performClick()
        field("Title").assertTextContains("Other transcript")
    }

    @LargeTest
    @Test fun largeUnicodeTranscriptDraftSurvivesRecreationWithoutSaving() {
        val large = "QA🙂 עברית\n".repeat(6_000)
        var saves = 0
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            VoxTheme { TranscriptDetailScreen(
                state = transcript, navigateBack = {}, save = { _, _, _, _, _, _ -> saves++; true },
                delete = {}, addToDraft = { _, _ -> }, initialEditing = true,
            ) }
        }
        field("Cleaned text").performTextReplacement(large)
        field("Raw transcript").performTextReplacement(large)
        restoration.emulateSavedInstanceStateRestore()
        for (label in listOf("Cleaned text", "Raw transcript")) {
            val actual = field(label).fetchSemanticsNode().config[SemanticsProperties.EditableText].text
            assertEquals(large.length, actual.length)
            assertEquals(digest(large), digest(actual))
        }
        compose.runOnIdle { assertEquals(0, saves) }
        compose.onNodeWithText("Cancel").performScrollTo().performClick()
    }

    private fun digest(value: String) = java.security.MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it) }

    private fun field(label: String) = compose.onNode(hasSetTextAction() and hasText(label)).performScrollTo()
}
