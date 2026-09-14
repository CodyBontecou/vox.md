package md.vox.android.data

import android.content.Context
import androidx.datastore.preferences.preferencesDataStoreFile
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import md.vox.android.capturedomain.CaptureEntryTemplate
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.corebridge.unwiredCoreBridge
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class EntryTemplateRepositoryInstrumentationTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    fun editsPropagateAndDeletionKeepsPresetSnapshotWhileClearingOneShotOverride() = runBlocking {
        context.deleteDatabase("capture-index-v1.db")
        context.preferencesDataStoreFile("capture-destination.preferences_pb").delete()
        val repository = AndroidCaptureRepository(context, unwiredCoreBridge(), clock = { 123L })
        val template = CaptureEntryTemplate(
            id = "22222222-2222-4222-8222-222222222222",
            name = "Meeting bullet",
            entryPrefix = "- {time} ",
            entrySuffix = " #meeting",
        )
        assertEquals(listOf(template), repository.saveEntryTemplate(template))

        val preset = CapturePreset(
            id = "11111111-1111-4111-8111-111111111111",
            name = "Meetings",
            symbol = "mic",
            revision = 1,
            logicalFolder = "Meetings",
            noteNameTemplate = "{date}.md",
            metadataFields = listOf(CaptureMetadataField("kind", "meeting")),
            entryPrefix = "stale",
            entrySuffix = "stale",
            entryTemplateID = template.id,
        )
        val saved = repository.saveCapturePreset(preset).presets.single { it.id == preset.id }
        assertEquals(template.entryPrefix, saved.entryPrefix)
        assertEquals(template.entrySuffix, saved.entrySuffix)

        val edited = template.copy(entryPrefix = "> ", entrySuffix = "\n---")
        repository.saveEntryTemplate(edited)
        val propagated = repository.capturePresets().presets.single { it.id == preset.id }
        assertEquals("> ", propagated.entryPrefix)
        assertEquals("\n---", propagated.entrySuffix)
        assertTrue(propagated.revision > saved.revision)

        assertEquals(template.id, repository.setDraftEntryTemplateOverride(template.id).entryTemplateIDOverride)
        assertTrue(repository.deleteEntryTemplate(template.id).isEmpty())
        val fallback = repository.capturePresets().presets.single { it.id == preset.id }
        assertNull(fallback.entryTemplateID)
        assertEquals("> ", fallback.entryPrefix)
        assertEquals("\n---", fallback.entrySuffix)
        assertNull(repository.currentDraft().entryTemplateIDOverride)
    }
}
