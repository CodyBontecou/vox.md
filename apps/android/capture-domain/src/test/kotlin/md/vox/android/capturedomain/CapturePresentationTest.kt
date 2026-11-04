package md.vox.android.capturedomain

import java.time.ZoneId
import org.junit.Assert.*
import org.junit.Test

class CapturePresentationTest {
    private val utc = ZoneId.of("UTC")
    private val id = "12345678-1234-4234-8234-123456789abc"
    private fun render(template: String, preset: String = "Meetings") = CaptureAudioFilename.render(template,id,1700000000000,preset,"original.wav",zone=utc)
    @Test fun audioTokensUseActualExtensionAndFrozenContext() {
        assertEquals("Meetings-2023-11-14-221320-23-12345678-original.wav", render("{preset}-{timestamp}-{YR}-{id8}-{original}.mp3"))
        assertNull(render("  "))
    }
    @Test fun tokenReplacementDoesNotInterpretPresetNamesAsTemplates() {
        assertEquals("{date}.wav",render("{preset}","{date}"))
    }
    @Test fun pathAndYamlLikeInputCannotCreateDirectories() {
        val value=render("../../secret\\name:\nfile.mp3")!!
        assertFalse(value.startsWith('.')); assertFalse('/' in value); assertFalse('\\' in value); assertFalse('\n' in value)
        assertTrue(value.endsWith(".wav"))
    }
    @Test fun unicodeFilenameIsBoundedWithoutBrokenSurrogates() {
        val value=render("語😀".repeat(100))!!.removeSuffix(".wav")
        assertTrue(value.toByteArray(Charsets.UTF_8).size <= 180)
        assertFalse(value.last().isHighSurrogate())
        assertEquals(value, value.toByteArray(Charsets.UTF_8).toString(Charsets.UTF_8))
    }
    @Test fun timestampFormatsHaveExplicitHourCycleAndTimezone() {
        assertEquals("10:13 PM 2023-11-14",CaptureTimestampFormat.TWELVE_HOUR.render(1700000000000,utc))
        assertEquals("22:13 2023-11-14",CaptureTimestampFormat.TWENTY_FOUR_HOUR.render(1700000000000,utc))
        assertEquals(CaptureTimestampFormat.TWELVE_HOUR,CaptureTimestampFormat.fromWireName("future"))
        assertEquals(CaptureTimestampFormat.TWENTY_FOUR_HOUR,CaptureBarConfiguration(usesTwentyFourHourTimestamps=true).timestampFormat)
    }
    private fun preset(id: String, enabled: Boolean = true, pinned: Boolean = true) = CapturePreset(id,id,"",revision=1,
        logicalFolder="Inbox",noteNameTemplate="capture-{id}.md",metadataFields=emptyList(),isEnabled=enabled,isPinned=pinned)
    @Test fun customWidgetSlotsKeepEmptiesDuplicatesAndStaleTargets() {
        val selection=PresetWidgetSelection(PresetWidgetSource.CUSTOM,listOf(null,"a","a","gone","off",null))
        val tiles=PresetWidgetResolver.resolve(selection,listOf(preset("a"),preset("off",enabled=false)),false)
        assertEquals(listOf(PresetWidgetAvailability.EMPTY,PresetWidgetAvailability.AVAILABLE,PresetWidgetAvailability.AVAILABLE,
            PresetWidgetAvailability.MISSING,PresetWidgetAvailability.DISABLED,PresetWidgetAvailability.EMPTY),tiles.map { it.availability })
        assertNull(PresetWidgetResolver.resolve(selection,listOf(preset("a")),true).single().presetID)
    }
    @Test fun followWidgetIncludesActivePinsAndSkipsDisabledUnpinnedPresets() {
        val tiles=PresetWidgetResolver.resolve(PresetWidgetSelection(),listOf(preset("z"),preset("a"),preset("off",false),preset("unpinned",pinned=false)),false)
        assertEquals(listOf("a","z"),tiles.map { it.presetID })
    }
}
