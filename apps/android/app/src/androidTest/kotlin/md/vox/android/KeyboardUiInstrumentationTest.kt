package md.vox.android

import android.Manifest
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import md.vox.android.platformservices.AudioCaptureClient
import md.vox.android.platformservices.RecordingTranscriptionClient
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class KeyboardUiInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun voxImeTypesAndExposesLocalVoiceCaptureState() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val automation = instrumentation.uiAutomation
        val previousIme = shell("settings get secure default_input_method").trim()
        shell("pm grant ${context.packageName} ${Manifest.permission.RECORD_AUDIO}")
        shell("ime enable ${context.packageName}/.VoxInputMethodService")
        assertTrue(shell("ime set ${context.packageName}/.VoxInputMethodService").contains("selected", ignoreCase = true))
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }

        var fieldText by mutableStateOf("")
        try {
            compose.setContent {
                VoxTheme {
                    Surface(Modifier.padding(24.dp)) {
                        BasicTextField(
                            value = fieldText,
                            onValueChange = { fieldText = it },
                            modifier = Modifier.fillMaxWidth().height(80.dp).testTag("keyboard-test-field"),
                        )
                    }
                }
            }
            compose.onNodeWithTag("keyboard-test-field").performClick()

            clickNode(description = "v")
            clickNode(description = "o")
            clickNode(description = "x")
            compose.runOnIdle { assertEquals("vox", fieldText) }

            val voice = awaitNode(description = "Start voice typing")
            assertTrue(voice.performAction(AccessibilityNodeInfo.ACTION_CLICK))
            val status = awaitNode(description = "Voice status") { node ->
                node.text?.toString()?.let { it.isNotBlank() && it != "On-device voice" } == true
            }
            assertNotEquals("On-device voice", status.text?.toString())
        } finally {
            if (previousIme.isNotBlank() && previousIme != "null") shell("ime set $previousIme")
        }
    }

    @Test
    fun keyboardIpcFailurePreservesDurableAudioAndRecoverableText() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val directory = File(context.noBackupFilesDir, "recordings/$RECOVERY_SESSION_ID")
        val audioCapture = AudioCaptureClient(context)
        val transcription = RecordingTranscriptionClient.get(context)
        try {
            assertTrue(directory.mkdirs())
            File(directory, "session.properties").writeText(
                """version=1
sessionID=$RECOVERY_SESSION_ID
phase=COMPLETED
createdAtEpochMillis=1700000000000
elapsedMillis=1000
chunkCount=1
failureCode=
sampleRate=16000
channelCount=1
encoding=pcm16le
""",
            )
            File(directory, "chunk-000000.pcm").writeBytes(byteArrayOf(1, 0, 2, 0, 3, 0, 4, 0))
            val before = ByteArrayOutputStream()
            assertTrue(audioCapture.exportWav(RECOVERY_SESSION_ID, before))

            assertTrue(
                !KeyboardVoiceCommitPolicy.commitOrPreserve(
                    context = context,
                    audioCapture = audioCapture,
                    transcription = transcription,
                    sessionID = RECOVERY_SESSION_ID,
                    text = "Recovered keyboard phrase",
                    commit = { false },
                ),
            )

            assertEquals("Recovered keyboard phrase", PendingVoiceTextStore.read(context))
            val after = ByteArrayOutputStream()
            assertTrue(audioCapture.exportWav(RECOVERY_SESSION_ID, after))
            assertTrue(before.toByteArray().contentEquals(after.toByteArray()))
            assertTrue(File(directory, "chunk-000000.pcm").isFile)
        } finally {
            PendingVoiceTextStore.clear(context)
            transcription.clear(RECOVERY_SESSION_ID)
            audioCapture.deleteRecording(RECOVERY_SESSION_ID)
        }
    }

    private fun clickNode(description: String) {
        val node = awaitNode(description)
        assertTrue("$description key was not clickable", node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
    }

    private fun awaitNode(
        description: String,
        timeoutMillis: Long = 10_000,
        extra: (AccessibilityNodeInfo) -> Boolean = { true },
    ): AccessibilityNodeInfo {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            automation.windows.asSequence()
                .mapNotNull { it.root }
                .mapNotNull { root -> findNode(root, description, extra) }
                .firstOrNull()
                ?.let { return it }
            SystemClock.sleep(50)
        }
        error("timed out waiting for accessibility node: $description")
    }

    private fun findNode(
        node: AccessibilityNodeInfo,
        description: String,
        extra: (AccessibilityNodeInfo) -> Boolean,
    ): AccessibilityNodeInfo? {
        if (node.contentDescription?.toString() == description && extra(node)) return node
        for (index in 0 until node.childCount) {
            findNode(node.getChild(index) ?: continue, description, extra)?.let { return it }
        }
        return null
    }

    private fun shell(command: String): String {
        return InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { descriptor ->
            FileInputStream(descriptor.fileDescriptor).use { it.readBytes().toString(Charsets.UTF_8) }
        }
    }

    private companion object {
        const val RECOVERY_SESSION_ID = "88888888-8888-4888-8888-888888888888"
    }
}
