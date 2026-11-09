package md.vox.android

import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.ViewModelStore
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.ui.CaptureViewModel
import md.vox.android.ui.VoxTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LinkAndRecordingRegressionTest {
    @get:Rule val compose = createComposeRule()

    @Test fun linkDialogRejectsHostlessLinksAndNormalizesPastedSchemeAndWhitespace() {
        var saved: String? = null
        compose.setContent { VoxTheme { LinkDialog("", {}, { saved = it }) } }
        compose.onNodeWithText("Web address").performTextInput("https://")
        compose.onNodeWithText("Add").assertIsNotEnabled()
        compose.onNodeWithText("Web address").performTextReplacement("  HTTPS://Example.com/Case?q=%25  ")
        compose.onNodeWithText("Add").assertIsEnabled().performClick()
        compose.runOnIdle { assertEquals("https://Example.com/Case?q=%25", saved) }
    }

    @Test fun invalidLinkCannotPreventLaterTextFromReachingDurableStorage() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val repository = (context.applicationContext as VoxApplication).compositionRoot.captureRepository
        val original = repository.currentDraft()
        val store = ViewModelStore()
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        try {
            val admitted = repository.saveDraft("baseline", "HTTPS://example.com/Case", "app")
            assertEquals("https://example.com/Case", admitted.url)
            try {
                repository.saveDraft("must not replace baseline", "https://", "app")
                fail("Repository must still reject malformed links")
            } catch (_: IllegalArgumentException) { }
            var model: CaptureViewModel? = null
            instrumentation.runOnMainSync {
                model = ViewModelProvider(store, CaptureViewModel.factory(repository))[CaptureViewModel::class.java]
            }
            val editor = requireNotNull(model)
            withTimeout(10_000) { editor.state.first { !it.isLoading } }
            instrumentation.runOnMainSync { editor.updateDraft("baseline with later edit", "https://") }
            withTimeout(10_000) {
                while (repository.currentDraft().text != "baseline with later edit") delay(20)
            }
            val reloaded = repository.currentDraft()
            assertEquals("baseline with later edit", reloaded.text)
            assertEquals("https://example.com/Case", reloaded.url)
        } finally {
            instrumentation.runOnMainSync { store.clear() }
            repository.saveDraft(original.text, original.url, original.captureSource)
        }
    }

    @Test fun shortLandscapeRecordingKeepsAllControlsInsideItsBoundsAndDispatchesActions() {
        val phase = mutableStateOf(RecordingPhase.RECORDING)
        var pauses = 0
        var resumes = 0
        var stops = 0
        var cancels = 0
        compose.setContent {
            VoxTheme {
                Box(Modifier.requiredSize(900.dp, 360.dp)) {
                    LiveRecordingScreen(
                        preset = null,
                        status = RecordingStatus(phase = phase.value, elapsedMillis = 11_000),
                        liveSpeech = null,
                        recordingResult = VoiceRecordingResult.ADD_TO_DRAFT,
                        setRecordingResult = {},
                        pause = { pauses++; phase.value = RecordingPhase.PAUSED },
                        resume = { resumes++; phase.value = RecordingPhase.RECORDING },
                        stop = { stops++ },
                        cancel = { cancels++ },
                    )
                }
            }
        }
        val screen = compose.onNodeWithTag("live-recording").getUnclippedBoundsInRoot()
        listOf("live-recording-cancel", "live-recording-stop", "live-recording-pause").forEach { tag ->
            val bounds = compose.onNodeWithTag(tag).getUnclippedBoundsInRoot()
            assertTrue("$tag must fit vertically inside the screen", bounds.top >= screen.top && bounds.bottom <= screen.bottom)
        }
        compose.onNodeWithContentDescription("Pause recording").performClick()
        compose.onNodeWithContentDescription("Resume recording").performClick()
        compose.onNodeWithContentDescription("Stop Recording").performClick()
        compose.onNodeWithContentDescription("Cancel voice recording").performClick()
        compose.runOnIdle {
            assertEquals(1, pauses)
            assertEquals(1, resumes)
            assertEquals(1, stops)
            assertEquals(1, cancels)
        }
    }
}
