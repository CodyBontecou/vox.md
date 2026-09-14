package md.vox.android

import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class WearRecordingOnlyDeliveryTest {
    private val recordingID = "11111111-1111-4111-8111-111111111111"

    @Test
    fun filenameTemplateExpandsStableDateAndIdentifierTokens() {
        assertEquals(
            "watch-2024-01-02-2024-142725-11111111-$recordingID",
            recordingOnlyBaseName(
                template = "watch-{date}-{YR}-{time}-{id8}-{uuid}.wav",
                sessionID = recordingID,
                recordedAtEpochMillis = 1_704_205_645_000,
                zoneID = ZoneOffset.UTC,
            ),
        )
    }

    @Test
    fun filenameTemplateRemovesExtensionsUnknownTokensAndUnsafeSeparators() {
        assertEquals(
            "Voice-2024-01-02-11111111",
            recordingOnlyBaseName(
                template = " Voice / {date}: {id8} {unknown}.WAV ",
                sessionID = recordingID,
                recordedAtEpochMillis = 1_704_205_645_000,
                zoneID = ZoneOffset.UTC,
            ),
        )
    }

    @Test
    fun filenameTemplateRejectsNonUuidRecordingIdentifier() {
        assertThrows(IllegalArgumentException::class.java) {
            recordingOnlyBaseName("watch-{id8}", "../recording", 0, ZoneOffset.UTC)
        }
    }
}
