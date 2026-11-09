package md.vox.android

import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.core.os.LocaleListCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AppLanguageInstrumentationTest {
    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    @Test
    fun appScopedLanguageSelectionRecreatesTheRealActivityWithReviewedArabicCopy() {
        val previous = AppCompatDelegate.getApplicationLocales()
        try {
            AppCompatDelegate.setApplicationLocales(LocaleListCompat.forLanguageTags("ar"))
            // A configured install opens Capture; preserve its data instead of assuming first run.
            compose.waitUntil(timeoutMillis = 10_000) {
                compose.onAllNodes(hasText("يُنسخ صوتيًا على هذا الجهاز"))
                    .fetchSemanticsNodes().isNotEmpty() ||
                    compose.onAllNodes(hasContentDescription("تسجيل النص"))
                        .fetchSemanticsNodes().isNotEmpty()
            }
            if (compose.onAllNodes(hasText("يُنسخ صوتيًا على هذا الجهاز")).fetchSemanticsNodes().isNotEmpty()) {
                compose.onNodeWithText("يُنسخ صوتيًا على هذا الجهاز").performScrollTo().assertIsDisplayed()
                compose.onNode(hasText("ابدأ") and hasClickAction()).performScrollTo().assertIsDisplayed()
            } else {
                compose.onNodeWithTag("capture-editor").assertIsDisplayed()
                    .assertContentDescriptionEquals("تسجيل النص")
            }
        } finally {
            AppCompatDelegate.setApplicationLocales(previous)
        }
    }
}
