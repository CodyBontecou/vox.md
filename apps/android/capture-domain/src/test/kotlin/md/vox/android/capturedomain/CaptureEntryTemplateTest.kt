package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Test

class CaptureEntryTemplateTest {
    private val preset = CapturePreset(
        id = "11111111-1111-4111-8111-111111111111",
        name = "Journal",
        symbol = "description",
        revision = 4,
        logicalFolder = "Inbox",
        noteNameTemplate = "capture-{id}.md",
        metadataFields = emptyList(),
        entryPrefix = "safe-prefix",
        entrySuffix = "safe-suffix",
        entryTemplateID = "22222222-2222-4222-8222-222222222222",
    )

    private val bound = CaptureEntryTemplate(
        id = "22222222-2222-4222-8222-222222222222",
        name = "Bound",
        entryPrefix = "bound-prefix",
        entrySuffix = "bound-suffix",
    )

    private val oneShot = CaptureEntryTemplate(
        id = "33333333-3333-4333-8333-333333333333",
        name = "One shot",
        entryPrefix = "override-prefix",
        entrySuffix = "override-suffix",
    )

    @Test
    fun reusableAndOneShotTemplatesResolveAtTheImmutableCaptureBoundary() {
        val liveBinding = preset.resolvingEntryTemplate(listOf(bound, oneShot))
        assertEquals("bound-prefix", liveBinding.entryPrefix)
        assertEquals("bound-suffix", liveBinding.entrySuffix)

        val overridden = preset.resolvingEntryTemplate(listOf(bound, oneShot), oneShot.id)
        assertEquals("override-prefix", overridden.entryPrefix)
        assertEquals("override-suffix", overridden.entrySuffix)
        assertEquals(bound.id, overridden.entryTemplateID)
    }

    @Test
    fun missingOrDeletedTemplateFallsBackToTheLastSafeInlineSnapshot() {
        val resolved = preset.resolvingEntryTemplate(emptyList())
        assertEquals("safe-prefix", resolved.entryPrefix)
        assertEquals("safe-suffix", resolved.entrySuffix)
    }
}
