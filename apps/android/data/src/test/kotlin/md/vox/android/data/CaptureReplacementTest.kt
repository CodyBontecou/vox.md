package md.vox.android.data

import kotlinx.serialization.json.*
import md.vox.android.capturedomain.*
import org.junit.Assert.*
import org.junit.Test
import java.nio.file.Files
import java.io.File

class CaptureReplacementTest {
    private val sourceID = "11111111-1111-4111-8111-111111111111"
    private val replacementID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private val vaultID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    private val assetID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    private val fixture get() = javaClass.classLoader!!.getResourceAsStream("contracts/v1/fixtures/capture-preparation-input/valid-android-m3-text-link.json")!!.use { it.readBytes() }
    private val ops get() = DurableCaptureStorePhase5Test.JvmOps()
    private val preset get() = CapturePreset(vaultID, "Explicit destination", "description", revision = 2,
        logicalFolder = "Chosen", noteNameTemplate = "note-{id}.md", metadataFields = emptyList())
    private class Harness(val base: File, val store: DurableCapturePackageStore, val coordinator: CaptureDurabilityCoordinator, val intents: CaptureRecoveryIntentStore)
    private fun harness(base: File = Files.createTempDirectory("replacement").toFile(), fileOps: DurableFileOps = ops): Harness {
        val store = DurableCapturePackageStore(base, DurableCaptureStorePhase5Test.MemoryIndex(), fileOps)
        return Harness(base, store, CaptureDurabilityCoordinator(store, DurableCaptureStorePhase5Test.MemoryLeases()), CaptureRecoveryIntentStore(base, fileOps))
    }
    private fun enqueue(h: Harness) {
        assertTrue(h.store.enqueue(fixture, 10, listOf(DurableAssetInput(assetID, "photo.jpg", "image/jpeg", byteArrayOf(1, 2, 3)))) is EnqueueResult.SavedLocally)
    }
    private fun intent(h: Harness): CaptureRecoveryIntent {
        val bytes = h.store.loadRequestBytes(sourceID)!!
        return CaptureRecoveryIntent(replacementID, sourceID, CapturePackageCodec.sha256(bytes), 0, CaptureState.QUEUED, 30,
            "route:$vaultID:2:$vaultID", recoveryRequest(bytes, replacementID, vaultID, preset))
    }
    private fun engine(h: Harness, auxiliary: Boolean = true, checkpoint: (String) -> Unit = {}) =
        CaptureReplacement(h.store, h.coordinator, h.intents, { 40 }, { auxiliary }, checkpoint = checkpoint)

    @Test fun explicitReplacementKeepsOriginalContentAssetsAndUsesExactlyOneIdentity() {
        val h = harness(); enqueue(h); val i = intent(h)
        repeat(3) { assertEquals(ReplacementOutcome.Ready(replacementID), engine(h).admit(i) { true }) }
        assertEquals(CaptureState.DISCARDED, h.store.loadJournal(sourceID)!!.state)
        assertEquals(CaptureState.QUEUED, h.store.loadJournal(replacementID)!!.state)
        assertArrayEquals(fixture, h.store.loadRequestBytes(sourceID))
        val original = CapturePackageCodec.parseCanonical(fixture)
        val replacement = CapturePackageCodec.parseCanonical(h.store.loadRequestBytes(replacementID)!!)
        for (key in listOf("payloads", "createdAtEpochMilliseconds", "captureSource", "invocation", "pins", "locale", "timezone")) assertEquals(key, original[key], replacement[key])
        assertArrayEquals(byteArrayOf(1, 2, 3), h.store.loadPackagedAssets(sourceID)!!.single().bytes)
        assertArrayEquals(byteArrayOf(1, 2, 3), h.store.loadPackagedAssets(replacementID)!!.single().bytes)
        assertEquals(1, h.intents.sourceIDs().size)
        assertFalse(h.store.pruneCompletedPackage(sourceID))
        assertArrayEquals(byteArrayOf(1, 2, 3), h.store.loadPackagedAssets(sourceID)!!.single().bytes)
    }

    @Test fun restartReplaysEveryIntentRetirementAndEnqueueCrashWindow() {
        for (point in listOf("intentPersisted", "sourceRetired", "replacementEnqueued")) {
            val h = harness(); enqueue(h)
            assertTrue(engine(h, checkpoint = { if (it == point) error("crash") }).admit(intent(h)) { true } is ReplacementOutcome.Waiting)
            if (point == "sourceRetired") {
                assertEquals(CaptureState.DISCARDED, h.store.loadJournal(sourceID)!!.state)
                assertNull(h.store.loadJournal(replacementID))
            }
            val reopened = harness(h.base)
            repeat(2) { assertEquals(point, ReplacementOutcome.Ready(replacementID), engine(reopened).replay(sourceID)) }
            assertEquals(CaptureState.DISCARDED, reopened.store.loadJournal(sourceID)!!.state)
            assertArrayEquals(byteArrayOf(1, 2, 3), reopened.store.loadPackagedAssets(replacementID)!!.single().bytes)
        }
    }

    @Test fun intentPromotionUncertaintyResyncsBeforeSourceRetirement() {
        for (point in listOf("beforeRecoveryIntentPromote", "afterRecoveryIntentPromote", "afterRecoveryIntentSync")) {
            val base = Files.createTempDirectory("recovery-intent-crash").toFile()
            val h = harness(base, object : DurableFileOps by ops {
                override fun checkpoint(name: String) { if (name == point) error("crash") }
            }); enqueue(h); val i = intent(h)
            assertTrue(engine(h).admit(i) { true } is ReplacementOutcome.Waiting)
            assertEquals(CaptureState.QUEUED, h.store.loadJournal(sourceID)!!.state)
            val reopened = harness(base)
            val recovered = if (reopened.intents.exists(sourceID)) engine(reopened).replay(sourceID) else engine(reopened).admit(i) { true }
            assertEquals(point, ReplacementOutcome.Ready(replacementID), recovered)
        }
    }

    @Test fun sameIntentAdmitCannotRetireSourceUntilPromotedIntentDirectoryResyncs() {
        val base = Files.createTempDirectory("recovery-resync").toFile()
        val first = harness(base, object : DurableFileOps by ops {
            override fun checkpoint(name: String) { if (name == "afterRecoveryIntentPromote") error("crash") }
        }); enqueue(first); val i = intent(first)
        assertTrue(engine(first).admit(i) { true } is ReplacementOutcome.Waiting)
        val second = harness(base, object : DurableFileOps by ops {
            override fun syncDirectory(directory: File) {
                if (directory.name == "vox-capture-recoveries") error("fsync failed")
                ops.syncDirectory(directory)
            }
        })
        assertTrue(engine(second).admit(i) { true } is ReplacementOutcome.Waiting)
        assertEquals(CaptureState.QUEUED, second.store.loadJournal(sourceID)!!.state)
        assertNull(second.store.loadJournal(replacementID))
        assertEquals(ReplacementOutcome.Ready(replacementID), engine(harness(base)).admit(i) { true })
    }

    @Test fun corruptAssetsBlockRetirementAndSurviveForExplicitRecovery() {
        val h = harness(); enqueue(h); val i = intent(h)
        File(h.base, "vox-captures/$sourceID/asset-data/$assetID").writeBytes(byteArrayOf(9, 9, 9))
        assertFalse(engine(h).admit(i) { true } is ReplacementOutcome.Ready)
        assertFalse(h.intents.exists(sourceID)); assertFalse(h.store.hasPackageEntry(replacementID))
        assertTrue(File(h.base, "vox-captures/$sourceID/request.json").exists())
    }

    @Test fun sourceJournalFailureNeverEnqueuesUntilRetirementIsDurable() {
        for (point in listOf("beforeJournalReplace", "afterJournalReplace", "beforePackageDirectorySync")) {
            val base = Files.createTempDirectory("replacement-retirement").toFile()
            val h = harness(base, object : DurableFileOps by ops {
                override fun checkpoint(name: String) { if (name == point) error("crash") }
            }); enqueue(h)
            assertTrue(engine(h).admit(intent(h)) { true } is ReplacementOutcome.Waiting)
            assertNull(h.store.loadJournal(replacementID))
            assertEquals(point, ReplacementOutcome.Ready(replacementID), engine(harness(base)).replay(sourceID))
        }
    }

    @Test fun staleUnauthorizedBusyAndURLBoundRequestsDoNotRetireOrEnqueue() {
        val h = harness(); enqueue(h); val i = intent(h)
        assertTrue(engine(h).admit(i.copy(sourceRevision = 1)) { true } is ReplacementOutcome.Rejected)
        assertTrue(engine(h).admit(i.copy(sourceSHA256 = "0".repeat(64))) { true } is ReplacementOutcome.Rejected)
        assertTrue(engine(h).admit(i) { false } is ReplacementOutcome.Rejected)
        assertTrue(engine(h, auxiliary = false).admit(i) { true } is ReplacementOutcome.Rejected)
        val token = vaultID
        assertTrue(h.coordinator.acquire(sourceID, token, 35, 60_000) is LeasePlan.Grant)
        assertTrue(engine(h).admit(i) { true } is ReplacementOutcome.Waiting)
        assertFalse(h.intents.exists(sourceID)); assertNull(h.store.loadJournal(replacementID))
        assertEquals(CaptureState.QUEUED, h.store.loadJournal(sourceID)!!.state)
    }

    @Test fun duplicateIntentWithAnotherIdentityOrChoiceIsAConflict() {
        val h = harness(); enqueue(h); val i = intent(h)
        assertEquals(ReplacementOutcome.Ready(replacementID), engine(h).admit(i) { true })
        assertTrue(engine(h).admit(i.copy(choice = "another-route")) { true } is ReplacementOutcome.Rejected)
        assertTrue(engine(h).admit(i.copy(intentID = vaultID)) { true } is ReplacementOutcome.Rejected)
        assertEquals(1, h.intents.sourceIDs().size)
        assertNull(h.store.loadJournal(vaultID))
    }

    @Test fun anotherSourceCannotReuseAnIntentIdentityOrRetireACompletedReplacementAgain() {
        val h = harness(); enqueue(h); val i = intent(h)
        assertEquals(ReplacementOutcome.Ready(replacementID), engine(h).admit(i) { true })
        val another = recoveryRequest(fixture, vaultID, vaultID, preset)
        assertTrue(h.store.enqueue(another, 41) is EnqueueResult.SavedLocally)
        val duplicate = i.copy(sourceID = vaultID, sourceSHA256 = CapturePackageCodec.sha256(another),
            replacementBytes = recoveryRequest(another, replacementID, vaultID, preset))
        assertTrue(engine(h).admit(duplicate) { true } is ReplacementOutcome.Rejected)
        assertEquals(CaptureState.QUEUED, h.store.loadJournal(vaultID)!!.state)
        val completedEngine = CaptureReplacement(h.store, h.coordinator, h.intents, { 42 }, { true }, completed = { it == replacementID })
        assertEquals(ReplacementOutcome.Ready(replacementID), completedEngine.replay(sourceID))
    }

    @Test fun routeRevisionDisableDeletionURLAndVaultChangesRejectTheReviewedChoice() {
        val target = CaptureRecoveryTarget.Route(preset.id, preset.revision, vaultID)
        val vault = CaptureDestination(vaultID, "Reviewed vault", "content://test/vault")
        assertTrue(selectRecoveryRoute(target, listOf(preset), vault) is RecoveryRouteSelection.Ready)
        assertEquals(RecoveryRouteSelection.Rejected(CaptureRecoveryRejection.ROUTE_CHANGED), selectRecoveryRoute(target, emptyList(), vault))
        assertEquals(RecoveryRouteSelection.Rejected(CaptureRecoveryRejection.ROUTE_CHANGED), selectRecoveryRoute(target, listOf(preset.copy(revision = 3)), vault))
        assertEquals(RecoveryRouteSelection.Rejected(CaptureRecoveryRejection.ROUTE_CHANGED), selectRecoveryRoute(target, listOf(preset.copy(isEnabled = false)), vault))
        assertEquals(RecoveryRouteSelection.Rejected(CaptureRecoveryRejection.DESTINATION_CHANGED), selectRecoveryRoute(target, listOf(preset), vault.copy(id = assetID)))
        assertEquals(RecoveryRouteSelection.Rejected(CaptureRecoveryRejection.URL_ROUTE), selectRecoveryRoute(target, listOf(preset.copy(urlDelivery = CaptureURLDeliverySettings(enabled = true))), vault))
    }

    @Test fun persistedAmbiguousCommitAndPermissionLossNeverAdmitAReplacement() {
        for (permissionLost in listOf(false, true)) {
            val h = harness(); enqueue(h)
            val token = vaultID
            assertTrue(h.coordinator.acquire(sourceID, token, 20, 600_000) is LeasePlan.Grant)
            fun append(state: CaptureState, code: JournalCode, hash: String? = null, resume: CaptureState? = null) {
                val previous = h.store.loadJournal(sourceID)!!
                assertTrue(h.coordinator.mutate(JournalMutationCommand(sourceID, previous.revision,
                    JournalEvent(previous.revision + 1, previous.state, state, code, 25, resumeState = resume, planHash = hash), token), 25) is JournalMutationResult.Applied)
            }
            append(CaptureState.PREPARING, JournalCode.PREPARATION_STARTED)
            val note = "prepared".toByteArray()
            val helpers = DurableCaptureStorePhase5Test()
            val plan = helpers.minimalPlan(note.size.toLong(), CapturePackageCodec.sha256(note))
            val hash = PreparedPlanVerifier.verifiedPlanHash(plan)!!
            helpers.stageAndPromote(h.store, note, plan, hash)
            append(CaptureState.MATERIALIZED, JournalCode.MATERIALIZED, hash)
            append(CaptureState.COMMITTING, JournalCode.COMMIT_STARTED, hash)
            h.store.persistCommitMarker(sourceID, CommitMarker.validated(CommitMarker.MarkerState.ACTIVE, vaultID, hash, "capture.md", 25))
            append(CaptureState.UNKNOWN_OUTCOME, JournalCode.COMMIT_AMBIGUOUS)
            if (permissionLost) append(CaptureState.NEEDS_PERMISSION, JournalCode.PERMISSION_LOST, resume = CaptureState.COMMITTING)
            val source = h.store.loadJournal(sourceID)!!
            h.coordinator.release(sourceID, token)
            val i = intent(h).copy(sourceRevision = source.revision, sourceState = source.state)
            assertTrue(engine(h).admit(i) { true } is ReplacementOutcome.Rejected)
            assertFalse(h.intents.exists(sourceID)); assertNull(h.store.loadJournal(replacementID))
            assertEquals(source.state, h.store.loadJournal(sourceID)!!.state)
            assertArrayEquals(note, h.store.loadPreparedArtifacts(sourceID, hash)!!.noteBytes)
        }
    }

    @Test fun ambiguousCommitAndPermissionResumeCannotBeReplaced() {
        val h = harness(); enqueue(h)
        val snapshot = h.store.loadJournal(sourceID)!!
        val active = CommitMarker.validated(CommitMarker.MarkerState.ACTIVE, vaultID, "a".repeat(64), "note.md", 30)
        assertFalse(canDiscardCapture(snapshot, active))
        for (state in listOf(CaptureState.COMMITTING, CaptureState.UNKNOWN_OUTCOME, CaptureState.COMPLETED)) assertFalse(canDiscardCapture(snapshot.copy(state = state), null))
        assertFalse(canDiscardCapture(snapshot.copy(state = CaptureState.NEEDS_PERMISSION, resumeState = CaptureState.COMMITTING), null))
    }
}
