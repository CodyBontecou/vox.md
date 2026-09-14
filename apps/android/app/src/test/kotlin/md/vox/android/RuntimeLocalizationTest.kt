package md.vox.android

import java.util.Locale
import md.vox.android.capturedomain.CaptureLocationUnavailableReason
import md.vox.android.capturedomain.CaptureState
import org.junit.Assert.assertEquals
import org.junit.Test

class RuntimeLocalizationTest {
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
