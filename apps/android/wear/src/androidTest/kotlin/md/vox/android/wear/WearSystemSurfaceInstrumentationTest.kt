package md.vox.android.wear

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WearSystemSurfaceInstrumentationTest {
    private val context: Context = ApplicationProvider.getApplicationContext()

    @Test
    fun tileContainsQuickActionStatusAndAppLaunchTarget() {
        val idleState = WearSurfaceState(recording = false, queued = 3)
        val idle = captureTileEvidence(context, idleState)
        assertNotNull(captureTile(context, idleState))
        assertTrue(idle.brand == "Vox.md")
        assertTrue(idle.action == "Record")
        assertTrue(idle.detail.contains("3 recordings saved on Watch"))
        assertTrue(idle.clickID == "open-capture")
        assertTrue(idle.launchPackage == context.packageName)
        assertTrue(idle.launchClass == WearMainActivity::class.java.name)

        val recordingState = WearSurfaceState(recording = true, queued = 0)
        val recording = captureTileEvidence(context, recordingState)
        assertNotNull(captureTile(context, recordingState))
        assertTrue(recording.action == "Recording")
        assertTrue(recording.detail == "Show detailed recording controls")
    }

    @Test
    fun complicationExposesStatusAndTapActionForIdleQueuedAndRecordingStates() {
        val idle = complicationData(context, preview = false, WearSurfaceState(false, 0))
        val queued = complicationData(context, preview = false, WearSurfaceState(false, 7))
        val recording = complicationData(context, preview = false, WearSurfaceState(true, 0))

        assertTrue(idle is ShortTextComplicationData)
        assertTrue(queued is ShortTextComplicationData)
        assertTrue(recording is ShortTextComplicationData)
        assertTrue(idle.toString().contains("VOX"))
        assertTrue(queued.toString().contains("7"))
        assertTrue(recording.toString().contains("REC"))
        assertTrue((idle as ShortTextComplicationData).tapAction != null)
        assertTrue((queued as ShortTextComplicationData).tapAction != null)
        assertTrue((recording as ShortTextComplicationData).tapAction != null)
    }
}
