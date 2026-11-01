package md.vox.android

import java.util.Locale
import md.vox.android.capturedomain.CaptureLocationUnavailableReason
import md.vox.android.capturedomain.CaptureState
import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimeLocalizationTest {
    @Test fun `Chinese region locales resolve to the available script catalog`() {
        assertEquals(listOf("zh-TW", "zh-Hant", "zh"),localizationCandidates(Locale.forLanguageTag("zh-TW")))
        assertEquals(listOf("zh-CN", "zh-Hans", "zh"),localizationCandidates(Locale.forLanguageTag("zh-CN")))
        assertEquals(listOf("zh-Hant-HK", "zh-Hant", "zh"),localizationCandidates(Locale.forLanguageTag("zh-Hant-HK")))
    }

    @Test fun `regional Portuguese uses the available Brazilian catalog`() {
        assertEquals(listOf("pt-PT", "pt", "pt-BR"), localizationCandidates(Locale.forLanguageTag("pt-PT")))
    }

    @Test
    fun `Apple placeholders become Java formatter placeholders`() {
        assertEquals("%1\$d recordings · %2\$s", appleFormatToJava("%1\$lld recordings · %2\$@"))
        assertEquals("%1\$.1f / %2\$d · %%", appleFormatToJava("%1\$.1f / %2\$lld · %%"))
    }

    @Test
    fun `finite ui mappings cover capture states sources and location failures`() {
        assertEquals(CaptureState.entries.size, CaptureState.entries.map(::captureStateUiText).map(VoxUiText::source).distinct().size)
        assertEquals("Watch", captureSourceUiText("wear").source)
        assertEquals("Watch", captureSourceUiText("watch").source)
        assertEquals("App", captureSourceUiText("unknown-source").source)
        CaptureLocationUnavailableReason.entries.forEach { reason ->
            assertEquals(locationUnavailableMessage(reason), locationUnavailableUiText(reason).source)
        }
    }

    @Test
    fun `localized formatter respects indexed argument order`() {
        assertEquals(
            "Capture: 12",
            formatLocalized("%2\$@: %1\$lld", Locale.ENGLISH, 12L, "Capture"),
        )
    }

    @Test
    fun `invalid localized format falls back to the English source format`() {
        assertEquals(
            "12 captures",
            formatLocalized("%2\$@ captures", "%1\$lld captures", Locale.GERMAN, 12L),
        )
    }
}
