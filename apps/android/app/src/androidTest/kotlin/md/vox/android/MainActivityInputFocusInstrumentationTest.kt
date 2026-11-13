package md.vox.android

import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** Match the live route and real IME path, rather than relying only on an isolated screen. */
class MainActivityInputFocusInstrumentationTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun libraryFingerFocusAndTypingWorkFromTheRealApp() = checkInput(stylus = false)
    @Test fun libraryStylusFocusAndTypingWorkFromTheRealApp() = checkInput(stylus = true)

    private fun checkInput(stylus: Boolean) {
        val done = hasText("Done") and hasClickAction()
        if (compose.onAllNodes(done).fetchSemanticsNodes().isNotEmpty()) compose.onNode(done).performClick()
        // Phones reach Library through Capture's Activity button, then Activity's "All captures" pill.
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("capture-activity").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("capture-activity").performClick()
        compose.waitUntil(5_000) { compose.onAllNodesWithTag("activity-library").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag("activity-library").performClick()
        val search = compose.onNode(hasSetTextAction() and hasText("Search words, routes, files"))
        assertEquals("", search.fetchSemanticsNode().config[SemanticsProperties.EditableText].text)
        try {
            // MainActivity uses edge-to-edge content, so its Compose and decor roots share an origin.
            injectSearchPointer(search, compose.activity.window.decorView, stylus)
            search.assertIsFocused()
            InstrumentationRegistry.getInstrumentation().sendStringSync("qa")
            search.assertTextContains("qa")
        } finally {
            runCatching { search.performTextClearance() }
        }
    }
}
