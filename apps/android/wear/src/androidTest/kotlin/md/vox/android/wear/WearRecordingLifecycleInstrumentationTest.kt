package md.vox.android.wear

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.wear.ongoing.SerializationHelper
import java.io.FileInputStream
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingStatusRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class WearRecordingLifecycleInstrumentationTest {
    @Test
    fun realWatchRecorderPausesResumesStopsAndPublishesAnOngoingActivity() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        grant(context, Manifest.permission.RECORD_AUDIO)
        grant(context, Manifest.permission.POST_NOTIFICATIONS)
        val client = AudioCaptureClient(context)
        var sessionID: String? = null
        try {
            client.dismissResult()
            assertFalse(RecordingStatusRegistry.status.value.isActive)
            client.start(testPreset())
            val recording = awaitPhase(RecordingPhase.RECORDING)
            sessionID = requireNotNull(recording.sessionID)
            val activeNotification = awaitRecordingNotification(context, "Pause")
            assertTrue(activeNotification.flags and Notification.FLAG_ONGOING_EVENT != 0)
            assertTrue(SerializationHelper.hasOngoingActivity(activeNotification))
            assertEquals(setOf("Pause", "Stop", "Cancel"), activeNotification.actions.orEmpty().map { it.title.toString() }.toSet())
            SystemClock.sleep(400)

            client.pause()
            val paused = awaitPhase(RecordingPhase.PAUSED, sessionID)
            assertTrue(paused.chunkCount > 0)
            val pausedNotification = awaitRecordingNotification(context, "Resume")
            assertTrue(SerializationHelper.hasOngoingActivity(pausedNotification))
            assertEquals(setOf("Resume", "Stop", "Cancel"), pausedNotification.actions.orEmpty().map { it.title.toString() }.toSet())

            client.resume()
            awaitPhase(RecordingPhase.RECORDING, sessionID)
            SystemClock.sleep(250)
            client.stop()
            val completed = awaitPhase(RecordingPhase.COMPLETED, sessionID)
            assertTrue(completed.chunkCount >= paused.chunkCount)
            assertFalse(completed.isActive)
        } finally {
            sessionID?.let {
                client.dismissResult()
                client.deleteRecording(it)
            }
        }
    }

    private fun awaitPhase(
        phase: RecordingPhase,
        sessionID: String? = null,
        timeoutMillis: Long = 10_000,
    ): RecordingStatus {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            val status = RecordingStatusRegistry.status.value
            if (status.phase == phase && (sessionID == null || status.sessionID == sessionID)) return status
            if (status.phase == RecordingPhase.FAILED) error("recording failed: ${status.failureCode}")
            SystemClock.sleep(50)
        }
        error("timed out waiting for $phase; last=${RecordingStatusRegistry.status.value}")
    }

    private fun awaitRecordingNotification(context: Context, firstAction: String): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        val deadline = SystemClock.uptimeMillis() + 5_000
        while (SystemClock.uptimeMillis() < deadline) {
            manager.activeNotifications.firstOrNull { it.id == 201 }?.notification?.let { notification ->
                if (notification.actions?.firstOrNull()?.title?.toString() == firstAction) return notification
            }
            SystemClock.sleep(50)
        }
        error("recording notification did not expose $firstAction")
    }

    private fun grant(context: Context, permission: String) {
        InstrumentationRegistry.getInstrumentation().uiAutomation
            .executeShellCommand("pm grant ${context.packageName} $permission").use { descriptor ->
                FileInputStream(descriptor.fileDescriptor).use { it.readBytes() }
            }
    }

    private fun testPreset() = CapturePreset(
        id = "55555555-5555-4555-8555-555555555555",
        name = "Watch recording",
        symbol = "mic",
        revision = 1,
        logicalFolder = "Daily",
        noteNameTemplate = "watch-{uuid}.md",
        metadataFields = emptyList(),
    )
}
