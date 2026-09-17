package md.vox.android.data

import md.vox.android.capturedomain.CaptureBarAction
import md.vox.android.capturedomain.CaptureBarConfiguration
import md.vox.android.capturedomain.VoiceRecordingResult
import md.vox.android.capturedomain.normalized
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CaptureBarPersistenceTest {
    @Test
    fun customOrderHiddenActionsAndTimestampPreferenceRoundTripExactly() {
        val configuration = CaptureBarConfiguration(
            orderedActions = listOf(
                CaptureBarAction.DATE,
                CaptureBarAction.ADD_MEDIA,
                CaptureBarAction.UNDO,
            ),
            hiddenActions = setOf(CaptureBarAction.UNDO, CaptureBarAction.ADD_MEDIA),
            usesTwentyFourHourTimestamps = true,
            confirmsVoiceNotesBeforeAdding = true,
            voiceRecordingResult = VoiceRecordingResult.SEND_IMMEDIATELY,
        ).normalized()

        val encoded = encodeCaptureBarConfiguration(configuration)
        val decoded = decodeCaptureBarConfiguration(encoded)

        assertEquals(configuration, decoded)
        assertTrue(encoded.contains("\"hidden\": ["))
        assertTrue(encoded.contains("\"order\": ["))
        assertTrue(encoded.contains("\"twentyFourHour\": true"))
        assertTrue(encoded.contains("\"confirmVoiceNoteBeforeAdding\": true"))
        assertTrue(encoded.contains("\"voiceRecordingResult\": \"sendImmediately\""))
        assertTrue(decoded.confirmsVoiceNotesBeforeAdding)
        assertEquals(VoiceRecordingResult.SEND_IMMEDIATELY, decoded.voiceRecordingResult)
        assertFalse(CaptureBarAction.ADD_MEDIA in decoded.visibleActions)
    }

    @Test
    fun olderOrderMigratesEveryNewActionOnceAndMalformedStateFailsClosed() {
        val older = """{"hidden":["paste"],"order":["addMedia","currentLocation"],"twentyFourHour":false,"version":1}"""
        val migrated = decodeCaptureBarConfiguration(older)

        assertEquals(CaptureBarAction.ADD_MEDIA, migrated.orderedActions[0])
        assertEquals(CaptureBarAction.CURRENT_LOCATION, migrated.orderedActions[1])
        assertEquals(CaptureBarAction.entries.size, migrated.orderedActions.size)
        assertEquals(CaptureBarAction.entries.size, migrated.orderedActions.distinct().size)
        assertFalse(CaptureBarAction.PASTE in migrated.visibleActions)
        assertFalse(migrated.confirmsVoiceNotesBeforeAdding)
        assertEquals(VoiceRecordingResult.ADD_TO_DRAFT, migrated.voiceRecordingResult)
        assertEquals(VoiceRecordingResult.ADD_TO_DRAFT, VoiceRecordingResult.fromPersistedName(null))
        assertEquals(VoiceRecordingResult.ADD_TO_DRAFT, VoiceRecordingResult.fromPersistedName("unknown"))
        assertEquals(VoiceRecordingResult.SEND_IMMEDIATELY, VoiceRecordingResult.fromPersistedName("sendImmediately"))
        assertEquals(CaptureBarConfiguration(), decodeCaptureBarConfiguration("{\"version\":999}"))
    }
}
