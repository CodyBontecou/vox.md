package md.vox.android

import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.Surface
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.test.ext.junit.runners.AndroidJUnit4
import md.vox.android.capturedomain.CapturePreset
import md.vox.android.platformservices.RecordingJobPolicy
import md.vox.android.platformservices.RecordingPhase
import md.vox.android.platformservices.RecordingRetentionKind
import md.vox.android.platformservices.RecordingStatus
import md.vox.android.platformservices.RecordingTranscriptionPhase
import md.vox.android.platformservices.RecordingTranscriptionState
import md.vox.android.ui.VoxTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RecordingQueueUiInstrumentationTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun retainedRecordingDispatchesProcessDeleteAudioShareReassignmentAndRetentionOverride() {
        val preset = preset("Journal")
        var processed = 0
        var deleted = 0
        var exported = 0
        var audioShared = 0
        var reassigned: CapturePreset? = null
        var updatedPolicy: RecordingJobPolicy? = null
        renderCard(
            recording = recording(RecordingPhase.INTERRUPTED),
            transcription = null,
            reassignPresets = listOf(preset),
            process = { processed += 1 },
            export = { exported += 1 },
            shareAudio = { audioShared += 1 },
            delete = { deleted += 1 },
            reassign = { reassigned = it },
            updatePolicy = { updatedPolicy = it },
        )

        clickVisible("Process Now")
        clickVisible("Export Audio")
        clickVisible("Share Audio")
        clickVisible("Delete")
        clickVisible("Choose Preset")
        compose.onNodeWithText("Journal").performClick()
        clickVisible("Save Audio", substring = true)
        compose.onNodeWithText("30 Days").performClick()

        compose.runOnIdle {
            assertEquals(1, processed)
            assertEquals(1, exported)
            assertEquals(1, audioShared)
            assertEquals(1, deleted)
            assertEquals(preset, reassigned)
            assertEquals(RecordingRetentionKind.TIMED, updatedPolicy?.retention)
            assertEquals(30L * 24 * 60 * 60 * 1_000, updatedPolicy?.retentionMillis)
        }
    }

    @Test
    fun failedAndCompletedJobsDispatchRetryCopyShareAndAddToDraft() {
        var transcription by mutableStateOf(
            RecordingTranscriptionState(
                sessionID = SESSION_ID,
                phase = RecordingTranscriptionPhase.FAILED,
                failureCode = "processInterrupted",
            ),
        )
        var processed = 0
        var copied: String? = null
        var shared: String? = null
        var added: String? = null
        compose.setContent {
            VoxTheme {
                Surface {
                    LazyColumn {
                        item {
                            RecordingQueueCard(
                                recording = recording(RecordingPhase.COMPLETED),
                                transcription = transcription,
                                policy = RecordingJobPolicy(),
                                canProcess = true,
                                canControl = false,
                                isExporting = false,
                                resume = {},
                                finish = {},
                                cancel = {},
                                export = {},
                                shareAudio = {},
                                delete = {},
                                process = { processed += 1 },
                                cancelProcessing = {},
                                addToDraft = { added = it },
                                copyTranscript = { copied = it },
                                shareTranscript = { shared = it },
                                reassignPresets = emptyList(),
                                reassign = {},
                                updatePolicy = {},
                            )
                        }
                    }
                }
            }
        }

        clickVisible("Retry")
        compose.runOnIdle {
            transcription = transcription.copy(
                phase = RecordingTranscriptionPhase.COMPLETED,
                transcript = "raw transcript",
                cleanedTranscript = "Clean transcript",
                failureCode = null,
            )
        }
        clickVisible("Add to Draft")
        compose.onNodeWithContentDescription("Copy Last Transcript").performScrollTo().performClick()
        clickVisible("Share")

        compose.runOnIdle {
            assertEquals(1, processed)
            assertEquals("Clean transcript", added)
            assertEquals("Clean transcript", copied)
            assertEquals("Clean transcript", shared)
        }
    }

    @Test
    fun retryAllActionIsExplicitAndDispatchesOnce() {
        var retries = 0
        compose.setContent {
            VoxTheme {
                Surface { RecordingRetryAllAction(visible = true) { retries += 1 } }
            }
        }
        compose.onNodeWithText("Retry All").performClick()
        compose.runOnIdle { assertEquals(1, retries) }
    }

    @Test
    fun missingLocalModelKeepsManualAudioExportAvailable() {
        var exported = 0
        renderCard(
            recording = recording(RecordingPhase.COMPLETED),
            transcription = RecordingTranscriptionState(
                sessionID = SESSION_ID,
                phase = RecordingTranscriptionPhase.FAILED,
                failureCode = "modelNotInstalled",
            ),
            reassignPresets = emptyList(),
            canProcess = false,
            process = {},
            export = { exported += 1 },
            shareAudio = {},
            delete = {},
            reassign = {},
            updatePolicy = {},
        )

        compose.onNodeWithText("Install and select a local model, then retry.").performScrollTo().assertExists()
        clickVisible("Export Audio")
        compose.runOnIdle { assertEquals(1, exported) }
    }

    private fun renderCard(
        recording: RecordingStatus,
        transcription: RecordingTranscriptionState?,
        reassignPresets: List<CapturePreset>,
        canProcess: Boolean = true,
        process: () -> Unit,
        export: () -> Unit,
        shareAudio: () -> Unit,
        delete: () -> Unit,
        reassign: (CapturePreset) -> Unit,
        updatePolicy: (RecordingJobPolicy) -> Unit,
    ) {
        compose.setContent {
            VoxTheme {
                Surface {
                    LazyColumn {
                        item {
                            RecordingQueueCard(
                                recording = recording,
                                transcription = transcription,
                                policy = RecordingJobPolicy(),
                                canProcess = canProcess,
                                canControl = false,
                                isExporting = false,
                                resume = {},
                                finish = {},
                                cancel = {},
                                export = export,
                                shareAudio = shareAudio,
                                delete = delete,
                                process = process,
                                cancelProcessing = {},
                                addToDraft = {},
                                copyTranscript = {},
                                shareTranscript = {},
                                reassignPresets = reassignPresets,
                                reassign = reassign,
                                updatePolicy = updatePolicy,
                            )
                        }
                    }
                }
            }
        }
    }

    private fun clickVisible(text: String, substring: Boolean = false) {
        compose.onNodeWithText(text, substring = substring).performScrollTo().performClick()
    }

    private fun recording(phase: RecordingPhase) = RecordingStatus(
        sessionID = SESSION_ID,
        phase = phase,
        createdAtEpochMillis = 1_700_000_000_000,
        elapsedMillis = 12_000,
        chunkCount = 2,
    )

    private fun preset(name: String) = CapturePreset(
        id = "22222222-2222-4222-8222-222222222222",
        name = name,
        symbol = "book",
        revision = 1,
        logicalFolder = "Journal",
        noteNameTemplate = "{date}",
        metadataFields = emptyList(),
    )

    private companion object {
        const val SESSION_ID = "11111111-1111-4111-8111-111111111111"
    }
}
