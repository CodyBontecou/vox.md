package md.vox.android

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.result.ActivityResultRegistry
import androidx.activity.result.ActivityResultRegistryOwner
import androidx.activity.result.contract.ActivityResultContract
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.LocalActivityResultRegistryOwner
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.runtime.*
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.core.app.ActivityOptionsCompat
import androidx.test.core.app.ApplicationProvider
import java.io.File
import java.io.InputStream
import md.vox.android.platformservices.SpeechModelCatalog
import md.vox.android.platformservices.SpeechModelEngine
import md.vox.android.platformservices.SpeechModelManager
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class PendingPickerRegressionTest {
    @get:Rule val compose = createComposeRule()

    @Test fun pickerResultAfterRecreationKeepsItsOriginalTargetAndIsConsumedOnce() {
        val registry = TestRegistry()
        val owner = object : ActivityResultRegistryOwner { override val activityResultRegistry = registry }
        val results = mutableListOf<Pair<String?, Uri?>>()
        lateinit var launch: (String) -> Unit
        lateinit var request: PendingDocumentRequest
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            CompositionLocalProvider(LocalActivityResultRegistryOwner provides owner) {
                val pending = rememberPendingDocumentRequest()
                val launcher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
                    results += pending.consume() to uri
                }
                SideEffect {
                    request = pending
                    launch = { key -> pending.begin(key); launcher.launch(arrayOf("application/zip")) }
                }
            }
        }
        compose.runOnIdle { launch("vosk-original-model") }
        restoration.emulateSavedInstanceStateRestore()
        val uri = Uri.parse("content://qa/model.zip")
        compose.runOnIdle { registry.dispatchResult(registry.requestCode, Activity.RESULT_OK, Intent().setData(uri)) }
        compose.runOnIdle {
            assertEquals(listOf("vosk-original-model" to uri), results)
            assertNull(request.consume())
        }
    }

    @Test fun cancelAndIndependentPickerSlotsDoNotReuseOldTargets() {
        lateinit var model: PendingDocumentRequest
        lateinit var recording: PendingDocumentRequest
        val restoration = StateRestorationTester(compose)
        restoration.setContent {
            val a = rememberPendingDocumentRequest()
            val b = rememberPendingDocumentRequest()
            SideEffect { model = a; recording = b }
        }
        compose.runOnIdle { model.begin("model-a"); recording.begin("recording-a") }
        restoration.emulateSavedInstanceStateRestore()
        compose.runOnIdle {
            assertEquals("model-a", model.consume()) // canceled result consumes its target too
            model.begin("model-b")
            assertEquals("recording-a", recording.consume())
            assertEquals("model-b", model.consume())
        }
        restoration.emulateSavedInstanceStateRestore()
        compose.runOnIdle { assertNull(model.consume()); assertNull(recording.consume()) }
    }

    @Test fun largeMarkdownSnapshotSurvivesRecreationThroughASmallFileReference() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val directory = File(context.cacheDir, "qa-picker-${java.util.UUID.randomUUID()}")
        val store = PendingTextExportStore(directory)
        val text = "🧪 日本語\n".repeat(100_000)
        lateinit var pending: PendingDocumentRequest
        val restoration = StateRestorationTester(compose)
        try {
            restoration.setContent {
                val request = rememberPendingDocumentRequest()
                SideEffect { pending = request }
            }
            compose.runOnIdle { pending.begin(store.stage(text)) }
            restoration.emulateSavedInstanceStateRestore()
            compose.runOnIdle {
                val key = requireNotNull(pending.consume())
                assertEquals(36, key.length)
                assertTrue(store.consume(key) { input -> assertEquals(text, input.reader(Charsets.UTF_8).readText()); true })
                assertFalse(store.consume(key) { fail("Snapshot must be consumed only once"); true })
            }
        } finally { directory.deleteRecursively() }
    }

    @Test fun canceledAndFailedTextExportsRemoveTheirPrivateSnapshots() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val directory = File(context.cacheDir, "qa-picker-${java.util.UUID.randomUUID()}")
        val store = PendingTextExportStore(directory)
        try {
            val canceled = store.stage("canceled")
            store.discard(canceled)
            assertFalse(store.consume(canceled) { true })
            val failed = store.stage("failed")
            assertTrue(runCatching { store.consume(failed) { throw java.io.IOException("full") } }.isFailure)
            assertFalse(store.consume(failed) { true })
            assertTrue(directory.listFiles().orEmpty().isEmpty())
        } finally { directory.deleteRecursively() }
    }

    @Test fun rejectedModelImportClosesItsDocumentStreamWithoutReading() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val manager = SpeechModelManager.get(context)
        val unsupportedEngine = SpeechModelCatalog.models.first { it.engine != SpeechModelEngine.VOSK }.id
        listOf("qa-unknown-model", unsupportedEngine).forEach { id ->
            var closes = 0
            val input = object : InputStream() {
                override fun read(): Int = error("Rejected imports must not read")
                override fun close() { closes++ }
            }
            manager.installImportedZip(id, input)
            assertEquals(id, 1, closes)
        }
    }

    private class TestRegistry : ActivityResultRegistry() {
        var requestCode = 0
        override fun <I, O> onLaunch(requestCode: Int, contract: ActivityResultContract<I, O>, input: I, options: ActivityOptionsCompat?) {
            this.requestCode = requestCode
        }
    }
}
