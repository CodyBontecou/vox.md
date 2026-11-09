package md.vox.android.data

import kotlinx.serialization.json.*
import md.vox.android.capturedomain.*
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files

class CaptureHeadingFailureStoreTest {
    private val id = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private val vault = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private val fixture get() = javaClass.classLoader!!.getResourceAsStream("contracts/v1/fixtures/capture-preparation-input/valid-android-m3-text-link.json")!!.use { it.readBytes() }
    private fun request() = recoveryRequest(fixture, id, vault, CapturePreset(vault, "Heading", "description", revision = 2,
        logicalFolder = "", noteNameTemplate = "ignored.md", metadataFields = emptyList(), noteTargetKind = CaptureNoteTargetKind.EXISTING_NOTE,
        existingNotePath = "Notes.md", placement = CapturePlacementKind.BENEATH_HEADING, headingTitle = "Real selector", headingLevel = 2))
    private fun snapshot(state: CaptureState = CaptureState.NEEDS_USER_ACTION, revision: Int = 2): JournalSnapshot = JournalSnapshot(id, revision, state, null,
        listOf(JournalEvent(revision, CaptureState.PREPARING, state, JournalCode.USER_ACTION_REQUIRED, 40)))

    @Test fun coarseFailureNeverManufacturesAHeadingRepair() {
        val store = CaptureHeadingFailureStore(Files.createTempDirectory("heading-coarse").toFile(), DurableCaptureStorePhase5Test.JvmOps())
        assertNull(store.load(id, request(), snapshot()))
        assertThrows(IllegalArgumentException::class.java) { store.save(id, fixture, 1) }
    }
    @Test fun authoritativeDiagnosticIsBoundToRequestSelectorAndExactFailureRevision() {
        val store = CaptureHeadingFailureStore(Files.createTempDirectory("heading-bound").toFile(), DurableCaptureStorePhase5Test.JvmOps())
        val bytes = request(); store.save(id, bytes, 1)
        assertEquals(CaptureMissingHeading("Real selector", 2), store.load(id, bytes, snapshot()))
        assertNull(store.load(id, bytes, snapshot(revision = 3)))
        assertNull(store.load(id, bytes, snapshot(CaptureState.RETRYABLE_FAILURE)))
        assertNull(store.load(id, fixture, snapshot()))
        val changed = recoveryRequest(bytes, vault, vault, heading = CaptureRecoveryTarget.Heading("Other", 2, false))
        assertNull(store.load(id, changed, snapshot()))
    }
    @Test fun repairReplacesOnlyFrozenSelectorWithoutTouchingPayloadOrOtherRouteSettings() {
        val source = request()
        val changed = recoveryRequest(source, vault, vault, heading = CaptureRecoveryTarget.Heading("Chosen", 3, false))
        val original = CapturePackageCodec.parseCanonical(source); val repaired = CapturePackageCodec.parseCanonical(changed)
        assertEquals(original["payloads"], repaired["payloads"])
        assertEquals(original["invocation"], repaired["invocation"])
        val route = repaired.getValue("preset").jsonObject.getValue("routePolicy").jsonObject
        assertEquals("Chosen", route.text("headingTitle")); assertEquals(3, route.getValue("headingLevel").jsonPrimitive.int)
        assertEquals("fail", route.text("missingHeadingBehavior"))
        val created = recoveryRequest(source, vault, vault, heading = CaptureRecoveryTarget.Heading("Real selector", 2, true))
        assertEquals("create", CapturePackageCodec.parseCanonical(created).getValue("preset").jsonObject.getValue("routePolicy").jsonObject.text("missingHeadingBehavior"))
        assertThrows(IllegalArgumentException::class.java) { recoveryRequest(source, vault, vault, heading = CaptureRecoveryTarget.Heading("", 7, true)) }
    }
}
