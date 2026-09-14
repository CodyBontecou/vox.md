package md.vox.android.capturedomain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class WearProtocolTest {
    private val id = "123e4567-e89b-42d3-a456-426614174000"

    @Test
    fun roundTripsManifestChunkAndStatusPaths() {
        val manifest = WearProtocol.manifestPath(id)
        val chunk = WearProtocol.chunkPath(id, 17)
        val status = WearProtocol.statusPath(id)

        assertEquals(id, WearProtocol.recordingIDFromWatchPath(manifest))
        assertEquals(id, WearProtocol.recordingIDFromWatchPath(chunk))
        assertEquals(17, WearProtocol.chunkIndexFromWatchPath(chunk))
        assertEquals(id, WearProtocol.recordingIDFromPhoneStatusPath(status))
        assertTrue(chunk.endsWith("/chunks/000017"))
    }

    @Test
    fun rejectsLookalikeTraversalAndMalformedPaths() {
        listOf(
            id,
            "/wrong/$id/manifest",
            "${WearProtocol.WATCH_RECORDING_PREFIX}$id/other",
            "${WearProtocol.WATCH_RECORDING_PREFIX}$id/chunks/17",
            "${WearProtocol.WATCH_RECORDING_PREFIX}$id/chunks/000001/extra",
            "${WearProtocol.WATCH_RECORDING_PREFIX}../$id/manifest",
        ).forEach { assertNull(it, WearProtocol.recordingIDFromWatchPath(it)) }

        assertNull(WearProtocol.chunkIndexFromWatchPath(WearProtocol.manifestPath(id)))
        assertNull(WearProtocol.recordingIDFromPhoneStatusPath("$id/status"))
        assertNull(WearProtocol.recordingIDFromPhoneStatusPath("${WearProtocol.PHONE_STATUS_PREFIX}$id/status/extra"))
    }

    @Test
    fun enforcesCanonicalIdentifiersAndChecksums() {
        assertTrue(WearProtocol.recordingIDPattern.matches(id))
        assertTrue(WearProtocol.checksumPattern.matches("a".repeat(64)))
        assertTrue(!WearProtocol.recordingIDPattern.matches(id.uppercase()))
        assertTrue(!WearProtocol.checksumPattern.matches("g".repeat(64)))
    }

    @Test
    fun representsEveryRemoteRecordingLifecycleStateExactly() {
        assertEquals(
            listOf("receiving", "ingested", "queued", "transcribing", "delivering", "delivered", "failed", "transportFailed", "discarded"),
            WearRemoteRecordingPhase.entries.map(WearRemoteRecordingPhase::wireValue),
        )
        WearRemoteRecordingPhase.entries.forEach { phase ->
            assertEquals(phase, WearRemoteRecordingPhase.fromWireValue(phase.wireValue))
        }
        assertNull(WearRemoteRecordingPhase.fromWireValue("unknown"))
        assertEquals(setOf("delivered", "discarded"), WearRemoteRecordingPhase.entries.filter { it.terminal }.mapTo(mutableSetOf(), WearRemoteRecordingPhase::wireValue))
    }

    @Test
    fun remoteStatusRevisionsAdvanceAcrossFailureAndRetry() {
        assertEquals(1, WearProtocol.nextRemoteRevision(current = 0, minimum = 1))
        assertEquals(2, WearProtocol.nextRemoteRevision(current = 1, minimum = 1))
        assertEquals(8, WearProtocol.nextRemoteRevision(current = 2, minimum = 8))
        assertEquals(Int.MAX_VALUE, WearProtocol.nextRemoteRevision(Int.MAX_VALUE, Int.MAX_VALUE))
    }
}
