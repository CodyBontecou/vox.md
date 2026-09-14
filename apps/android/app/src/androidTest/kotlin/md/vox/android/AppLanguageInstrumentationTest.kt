package md.vox.android

import androidx.appcompat.app.AppCompatDelegate
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasClickAction
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
            compose.waitUntil(timeoutMillis = 10_000) {
                compose.onAllNodes(hasText("خطوط محددة Markdown"))
                    .fetchSemanticsNodes()
                    .isNotEmpty()
            }
            compose.onNodeWithText("خطوط محددة Markdown").performScrollTo().assertIsDisplayed()
            compose.onNode(hasText("اختيار كوكب أو ملف") and hasClickAction())
                .performScrollTo()
                .assertIsDisplayed()
        } finally {
            AppCompatDelegate.setApplicationLocales(previous)
        }
    }
}
