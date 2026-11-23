package md.vox.android

import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.android.play.core.review.testing.FakeReviewManager
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Play's review flow through Google's FakeReviewManager: it completes without showing a card
 * or submitting a rating, so this proves only the wiring, never what Play shows.
 */
@RunWith(AndroidJUnit4::class)
class PlayReviewFlowInstrumentationTest {
    @Test
    fun enabledFlowPreparesAndLaunchesThroughPlay() {
        withActivity { activity ->
            // Off the main thread: Play's tasks complete on it.
            runBlocking {
                val launch = PlayReviewFlow(activity, FakeReviewManager(activity), enabled = true).prepare()
                assertNotNull(launch)
                launch!!.launch()
            }
        }
    }

    @Test
    fun aBuildNotInstalledByPlayNeverAsks() {
        withActivity { activity ->
            runBlocking {
                assertNull(PlayReviewFlow(activity, FakeReviewManager(activity), enabled = false).prepare())
            }
        }
    }

    private fun withActivity(block: (MainActivity) -> Unit) {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            var activity: MainActivity? = null
            scenario.onActivity { activity = it }
            block(requireNotNull(activity))
        }
    }
}
