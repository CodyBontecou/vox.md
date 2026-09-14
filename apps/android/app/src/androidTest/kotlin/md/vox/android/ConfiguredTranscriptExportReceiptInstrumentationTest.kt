package md.vox.android

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ConfiguredTranscriptExportReceiptInstrumentationTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun successfulConfiguredExportReceiptSurvivesStoreRecreationWithoutTranscriptContent() {
        val sessionID = "77777777-7777-4777-8777-777777777777"
        val directory = File(context.noBackupFilesDir, "recordings/$sessionID")
        check(directory.mkdirs() || directory.isDirectory)
        try {
            val store = ConfiguredTranscriptExportReceiptStore(context)
            assertFalse(store.wasExported(sessionID))
            assertTrue(store.markExported(sessionID))
            assertTrue(ConfiguredTranscriptExportReceiptStore(context).wasExported(sessionID))
            val receipt = File(directory, "configured-export.receipt").readText()
            assertFalse(receipt.contains("transcript", ignoreCase = true))
            assertFalse(receipt.contains("content://"))
        } finally {
            directory.deleteRecursively()
        }
    }
}
