package md.vox.android

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.test.core.app.ApplicationProvider
import java.util.Locale
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class LocalizationParityInstrumentationTest {
    @get:Rule val compose = createComposeRule()
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test fun everySupportedLocaleResolvesAndroidComposerCopy() {
        val tags = listOf("ar", "bn", "de", "es", "fr", "hi", "id", "it", "ja", "ko", "nl", "pl", "pt-BR", "ru", "ta", "th", "tr", "uk", "ur", "vi", "zh-Hans", "zh-Hant")
        for (tag in tags) {
            val source = "Audio Filename Template"
            assertNotEquals(tag, source, RuntimeLocalization.translate(context, Locale.forLanguageTag(tag), source))
        }
        assertEquals(RuntimeLocalization.translate(context, Locale.forLanguageTag("pt-BR"), "Draft preview"),
            RuntimeLocalization.translate(context, Locale.forLanguageTag("pt-PT"), "Draft preview"))
        assertEquals(RuntimeLocalization.translate(context, Locale.forLanguageTag("zh-Hant"), "Draft preview"),
            RuntimeLocalization.translate(context, Locale.TAIWAN, "Draft preview"))
    }

    @Test fun arabicSelectsAllSixCardinalFormsAndLocalizedDigits() {
        val locale = Locale.forLanguageTag("ar-EG")
        val expected = mapOf(0 to "٠ مرفقات", 1 to "١ مرفق", 2 to "مرفقان (٢)", 3 to "٣ مرفقات", 11 to "١١ مرفقًا", 100 to "١٠٠ مرفق")
        for ((count, text) in expected) assertEquals(text, RuntimeLocalization.format(context, locale, "%lld attachments", count))
    }

    @Test fun slavicCountsUseOneFewAndManyInsteadOfEnglishSuffixes() {
        for ((tag, forms) in mapOf("ru" to listOf("1 вложение", "2 вложения", "5 вложений", "21 вложение"),
            "pl" to listOf("1 załącznik", "2 załączniki", "5 załączników", "21 załączników"))) {
            for ((index, count) in listOf(1, 2, 5, 21).withIndex())
                assertEquals(forms[index], RuntimeLocalization.format(context, Locale.forLanguageTag(tag), "%lld attachments", count))
        }
        assertEquals("1 attachment", RuntimeLocalization.format(context, Locale.ENGLISH, "%lld attachments", 1))
    }

    @Test fun rtlFormattingIsolatesLatinPathsWithoutChangingTheirStoredValue() {
        val url = "https://example.com/notes?id=42"
        val formatted = RuntimeLocalization.format(context, Locale.forLanguageTag("ar-EG"), "%@ · %lld attachments", url, 3)
        assertTrue(formatted.contains(url))
        assertTrue(formatted.contains('\u202a') || formatted.contains('\u2066'))
        assertEquals("https://example.com/notes?id=42", url)
        assertTrue(formatted.contains("٣"))
    }

    @Test fun rtlBackControlStaysReachableAtTwoHundredPercentText() {
        var clicked = false
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl,
                LocalDensity provides Density(density.density, 2f)) {
                MaterialTheme { Column { VoxTopBar(voxUiText("Settings")) { clicked = true } } }
            }
        }
        val back = compose.onNodeWithContentDescription("Back")
        val bounds = back.fetchSemanticsNode().boundsInRoot
        val root = compose.onRoot().fetchSemanticsNode().boundsInRoot
        assertTrue(bounds.center.x > root.center.x)
        back.assertIsDisplayed().performClick()
        compose.runOnIdle { assertTrue(clicked) }
    }
}
