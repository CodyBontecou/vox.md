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

    @Test
    fun routePinsRoundTripAndStayOptionalForOlderPayloads() {
        val configuration = CaptureBarConfiguration()
            .withRoutePins("b-route", listOf(CaptureBarAction.TIMESTAMP, CaptureBarAction.CHECKLIST))
            .withRoutePins("a-route", emptyList())
            .normalized()

        val encoded = encodeCaptureBarConfiguration(configuration)
        val decoded = decodeCaptureBarConfiguration(encoded)

        assertEquals(configuration, decoded)
        assertTrue(encoded.contains("\"routePins\""))
        assertEquals(listOf(CaptureBarAction.TIMESTAMP, CaptureBarAction.CHECKLIST), decoded.pinnedActions("b-route"))
        assertTrue(decoded.pinnedActions("a-route").isEmpty())

        // No pins: the field is omitted, so the payload is unchanged from before per-route pins.
        assertFalse(encodeCaptureBarConfiguration(CaptureBarConfiguration()).contains("routePins"))
        // A payload written before per-route pins decodes with none.
        val older = """{"hidden":[],"order":["addMedia"],"twentyFourHour":false,"version":1}"""
        assertTrue(decodeCaptureBarConfiguration(older).routePins.isEmpty())
        // Unknown actions are dropped and a malformed map is ignored without resetting the row.
        val tolerant = """{"hidden":["paste"],"order":["addMedia"],"routePins":{"r":["timestamp","nope"]},"version":1}"""
        assertEquals(listOf(CaptureBarAction.TIMESTAMP), decodeCaptureBarConfiguration(tolerant).pinnedActions("r"))
        val malformed = """{"hidden":["paste"],"order":["addMedia"],"routePins":"bad","version":1}"""
        val decodedMalformed = decodeCaptureBarConfiguration(malformed)
        assertTrue(decodedMalformed.routePins.isEmpty())
        assertFalse(CaptureBarAction.PASTE in decodedMalformed.visibleActions)
    }
}
