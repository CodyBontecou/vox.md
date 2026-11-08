package md.vox.android

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.core.app.ActivityOptionsCompat
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import md.vox.android.capturedomain.*
import md.vox.android.platformservices.*
import md.vox.android.ui.VoxTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class DetailExportRestorationTest {
    @get:Rule val compose = createComposeRule()
    private val transcript = RecordingTranscriptionState(
        sessionID = "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa",
        phase = RecordingTranscriptionPhase.COMPLETED,
        transcript = "QA raw 日本語", cleanedTranscript = "QA exported שלום", title = "QA export",
    )
    private val detail = CaptureHistoryDetail(
        requestID = "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa", createdAtEpochMillis = 0,
        state = CaptureState.RETRYABLE_FAILURE, capturedText = "QA source", capturedURL = null,
        presetID = "bbbbbbbb-1111-4111-8111-bbbbbbbbbbbb", logicalPath = "QA/test.md",
        preparedMarkdown = "# QA exported\nمرحبا\n",
    )

    @Test fun transcriptPickerRotationWritesTheFrozenExportEvenWhileSourceReloads() = checkExport(true)
    @Test fun capturePickerRotationWritesTheFrozenExportEvenWhileSourceReloads() = checkExport(false)

    private fun checkExport(isTranscript: Boolean) {
        val registry = TestRegistry()
        val owner = object : ActivityResultRegistryOwner { override val activityResultRegistry = registry }
        val available = mutableStateOf(true)
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            CompositionLocalProvider(LocalActivityResultRegistryOwner provides owner) {
                VoxTheme {
                    if (isTranscript) TranscriptDetailScreen(
                        state = transcript.takeIf { available.value }, navigateBack = {},
                        save = { _, _, _, _, _, _ -> true }, delete = {}, addToDraft = { _, _ -> },
                    ) else HistoryDetailScreen(
                        detail = detail.takeIf { available.value }, isLoading = !available.value,
                        isDeleting = false, navigateBack = {}, delete = {},
                    )
                }
            }
        }
        compose.onNodeWithText("Export").performScrollTo().performClick()
        compose.onNodeWithText("Markdown").performClick()
        compose.waitUntil(5_000) { registry.requestCode != 0 }
        restoration.emulateSavedInstanceStateRestore()
        // Activity results can precede asynchronous repository reload after process recreation.
        compose.runOnIdle { available.value = false }
        val output = File.createTempFile("qa-detail-export-", ".md", InstrumentationRegistry.getInstrumentation().targetContext.cacheDir)
        try {
            compose.runOnIdle { registry.dispatchResult(registry.requestCode, Activity.RESULT_OK, Intent().setData(Uri.fromFile(output))) }
            compose.waitUntil(5_000) { output.length() > 0 }
            val expected = if (isTranscript) TranscriptExporter.render(transcript, TranscriptExportFormat.MARKDOWN)
                else HistoryDetailExporter.render(detail, HistoryExportFormat.MARKDOWN)
            assertEquals(expected, output.readText())
        } finally { output.delete() }
    }

    @Test fun canceledRestoredExportCleansItsSnapshotWithoutSuccessFeedback() = checkCleanup(cancel = true)
    @Test fun providerFailureCleansItsSnapshotAndReportsFailureOnce() = checkCleanup(cancel = false)

    private fun checkCleanup(cancel: Boolean) {
        val registry = TestRegistry()
        val owner = object : ActivityResultRegistryOwner { override val activityResultRegistry = registry }
        val directory = File(InstrumentationRegistry.getInstrumentation().targetContext.noBackupFilesDir, "pending-detail-exports")
        val before = directory.listFiles().orEmpty().map { it.name }.toSet()
        lateinit var export: (String, String, String) -> Unit
        val results = mutableListOf<Pair<String, Boolean>>()
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            CompositionLocalProvider(LocalActivityResultRegistryOwner provides owner) {
                val launch = rememberDetailExport { format, success -> results += format to success }
                SideEffect { export = launch }
            }
        }
        compose.runOnIdle { export("MARKDOWN", "QA frozen snapshot", "qa.md") }
        compose.waitUntil(5_000) { registry.requestCode != 0 }
        assertEquals(1, directory.listFiles().orEmpty().count { it.name !in before })
        restoration.emulateSavedInstanceStateRestore()
        compose.runOnIdle {
            registry.dispatchResult(registry.requestCode, if (cancel) Activity.RESULT_CANCELED else Activity.RESULT_OK,
                if (cancel) null else Intent().setData(Uri.parse("content://qa.invalid/unwritable")))
        }
        compose.waitUntil(5_000) { directory.listFiles().orEmpty().none { it.name !in before } }
        compose.runOnIdle { assertEquals(if (cancel) emptyList() else listOf("MARKDOWN" to false), results) }
    }

    private class TestRegistry : ActivityResultRegistry() {
        var requestCode = 0
        override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I, options: ActivityOptionsCompat?) {
            this.requestCode = requestCode
        }
    }
}
