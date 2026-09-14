package md.vox.android

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.FileInputStream
import md.vox.android.capturedomain.CaptureMetadataField
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingStatusRegistry
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.SpeechModelManager
import md.vox.android.platformservices.VoiceAutoStopSettings
import md.vox.android.platformservices.VoiceAutoStopSettingsStore
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class VoiceLifecycleInstrumentationTest {
    @Test
    fun foregroundRecordingPausesResumesStopsAndPreservesAudioAfterTranscriptionFailure() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        grant(context, Manifest.permission.RECORD_AUDIO)
        grant(context, Manifest.permission.POST_NOTIFICATIONS)

        val autoStopStore = VoiceAutoStopSettingsStore.get(context)
        val previousAutoStop = autoStopStore.state.value
        autoStopStore.update(VoiceAutoStopSettings(enabled = false))
        val modelPreferences = context.getSharedPreferences("vox-local-speech-v1", Context.MODE_PRIVATE)
        val previousModelID = modelPreferences.getString("selected-model-id", null)
        val audio = AudioCaptureClient(context)
        val transcription = RecordingTranscriptionClient.get(context)
        var sessionID: String? = null
        try {
            audio.dismissResult()
            assertFalse("another recording was already active", RecordingStatusRegistry.status.value.isActive)
            audio.start(testPreset())
            val recording = awaitPhase(RecordingPhase.RECORDING)
            val id = requireNotNull(recording.sessionID)
            sessionID = id
            assertEquals(
                setOf("Pause", "Stop", "Cancel"),
                awaitRecordingNotification(context, "Pause").actions.orEmpty().map { it.title.toString() }.toSet(),
            )
            SystemClock.sleep(500)

            audio.pause()
            val paused = awaitPhase(RecordingPhase.PAUSED, id)
            assertTrue(paused.elapsedMillis > 0)
            assertTrue(paused.chunkCount > 0)
            val pausedNotification = awaitRecordingNotification(context, "Resume")
            assertTrue(pausedNotification.flags and Notification.FLAG_ONGOING_EVENT != 0)
            assertEquals(
                setOf("Resume", "Stop", "Cancel"),
                pausedNotification.actions.orEmpty().map { it.title.toString() }.toSet(),
            )

            audio.resume()
            awaitPhase(RecordingPhase.RECORDING, id)
            SystemClock.sleep(350)
            audio.stop()
            val completed = awaitPhase(RecordingPhase.COMPLETED, id)
            assertFalse(completed.isActive)
            assertTrue(completed.chunkCount >= paused.chunkCount)

            val beforeFailure = ByteArrayOutputStream()
            assertTrue(audio.exportWav(id, beforeFailure))
            assertTrue(beforeFailure.size() > 44)

            // Model selection is removed, not the installed model. This forces the
            // production local manager's explicit no-model failure branch without
            // deleting device state or invoking any recognizer/network fallback.
            modelPreferences.edit().remove("selected-model-id").commit()
            SpeechModelManager.get(context).refresh()
            transcription.process(id)
            val failed = transcription.states.value.getValue(id)
            assertEquals(RecordingTranscriptionPhase.FAILED, failed.phase)
            assertEquals("modelNotInstalled", failed.failureCode)

            val afterFailure = ByteArrayOutputStream()
            assertTrue(audio.exportWav(id, afterFailure))
            assertTrue(afterFailure.toByteArray().contentEquals(beforeFailure.toByteArray()))

            audio.dismissResult()
            assertEquals(RecordingPhase.IDLE, RecordingStatusRegistry.status.value.phase)
        } finally {
            sessionID?.let {
                transcription.clear(it)
                audio.dismissResult()
                audio.deleteRecording(it)
            }
            if (previousModelID == null) modelPreferences.edit().remove("selected-model-id").commit()
            else modelPreferences.edit().putString("selected-model-id", previousModelID).commit()
            SpeechModelManager.get(context).refresh()
            autoStopStore.update(previousAutoStop)
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

    private fun grant(context: Context, permission: String) {
        InstrumentationRegistry.getInstrumentation().uiAutomation
            .executeShellCommand("pm grant ${context.packageName} $permission").use { descriptor ->
                FileInputStream(descriptor.fileDescriptor).use { it.readBytes() }
            }
    }

    private fun awaitRecordingNotification(
        context: Context,
        firstAction: String,
        timeoutMillis: Long = 5_000,
    ): Notification {
        val manager = context.getSystemService(NotificationManager::class.java)
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            manager.activeNotifications.firstOrNull { it.id == 201 }?.notification?.let { notification ->
                if (notification.actions?.firstOrNull()?.title?.toString() == firstAction) return notification
            }
            SystemClock.sleep(50)
        }
        error("recording notification did not expose $firstAction")
    }

    private fun testPreset() = CapturePreset(
        id = "33333333-3333-4333-8333-333333333333",
        name = "Voice test",
        symbol = "mic",
        revision = 1,
        logicalFolder = "Inbox",
        noteNameTemplate = "voice-{id}",
        metadataFields = listOf(CaptureMetadataField("source", "voice-test")),
    )
}
