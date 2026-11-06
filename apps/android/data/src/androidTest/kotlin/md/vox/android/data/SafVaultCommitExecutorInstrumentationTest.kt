package md.vox.android.data

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import android.provider.DocumentsContract
import android.view.accessibility.AccessibilityNodeInfo
import md.vox.android.capturedomain.*
import md.vox.android.corebridge.CoreResult
import md.vox.android.corebridge.productionCoreBridge
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * ADR-0023 Phase 5 on-target evidence: the full M3 vertical slice executes against the
 * REAL local DocumentsProvider (com.android.externalstorage) through the production
 * coordinator (real native core via the lazy bridge), production durable store, and the
 * production SAF executor. The system document picker supplies and persists the real
 * tree grant before the vertical slice runs; no provider or grant check is substituted.
 */
@RunWith(AndroidJUnit4::class)
class SafVaultCommitExecutorInstrumentationTest {
    private val requestID = "11111111-1111-4111-8111-111111111111"
    private val leaseToken = "22222222-2222-4222-8222-222222222222"

    private fun requestBytes(): ByteArray = InstrumentationRegistry.getInstrumentation().context.assets
        .open("capture-preparation-input/valid-android-m3-text-link.json").use { it.readBytes() }

    @Test fun enqueueMaterializeCommitAndVerifyThroughRealProvider() = runCampaign(Fault.NONE)
    @Test fun revokedGrantBeforeCommitPreservesPreparedCaptureUntilReauthorized() = runCampaign(Fault.REVOKED_BEFORE)
    @Test fun revokedGrantAfterInterruptedWriteReconcilesWithoutDuplicate() = runCampaign(Fault.REVOKED_AFTER_WRITE)
    @Test fun interruptedAfterWriteRecoversFromReopenedRoomAndPackage() = runCampaign(Fault.AFTER_WRITE)
    @Test fun interruptedAfterCreateNeverBlindlyRewritesEmptyDocument() = runCampaign(Fault.AFTER_CREATE)
    @Test fun partialProviderWriteStaysUnknownAcrossRepeatedRetries() = runCampaign(Fault.PARTIAL_WRITE)
    @Test fun unavailableReadbackRetainsExactPlanAndReconcilesWhenProviderRecovers() = runCampaign(Fault.READBACK_FAILURE)
    @Test fun clearedNonCommitProofCanRematerializeAndCommitAfterReopen() = runCampaign(Fault.CLEARED_RETRY)

    private enum class Fault { NONE, REVOKED_BEFORE, REVOKED_AFTER_WRITE, AFTER_WRITE, AFTER_CREATE, PARTIAL_WRITE, READBACK_FAILURE, CLEARED_RETRY }
    private class InterruptedDelivery : Error("syntheticDeliveryBoundary")

    private fun runCampaign(fault: Fault) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        // SAF child-listing is restricted under Android/data on Android 11+, so the
        // campaign vault lives under the public Download tree where provider listing,
        // folder creation, and read-back are all exercised for real.
        val vaultRoot = File(android.os.Environment.getExternalStoragePublicDirectory(android.os.Environment.DIRECTORY_DOWNLOADS), "vox-e2e-vault")
        File(context.noBackupFilesDir, "vox-captures/$requestID").deleteRecursively()
        context.deleteDatabase("capture-index-v1.db")
        instrumentation.uiAutomation.adoptShellPermissionIdentity()
        try {
            vaultRoot.deleteRecursively()
            check(vaultRoot.mkdirs()) { "vaultRootCreateFailed" }
        } finally {
            instrumentation.uiAutomation.dropShellPermissionIdentity()
        }

        val requestedTreeUri = android.net.Uri.parse("content://com.android.externalstorage.documents/tree/" + android.net.Uri.encode("primary:Download/vox-e2e-vault"))
        val treeUri = grantTreeThroughSystemPicker(instrumentation, requestedTreeUri)
        assertEquals(
            "system picker failed to grant the real tree URI",
            PackageManager.PERMISSION_GRANTED,
            context.checkUriPermission(
                treeUri,
                android.os.Process.myPid(),
                android.os.Process.myUid(),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            ),
        )
        val destination = VaultDestination("33333333-3333-4333-8333-333333333333", treeUri.toString())

        var database = CaptureDatabase.create(context)
        var store = DurableCapturePackageStore(context.noBackupFilesDir, RoomCaptureIndex(database), AndroidDurableFileOps())
        val coordination = RoomCaptureCoordination(database)
        var coordinator = CaptureDurabilityCoordinator(store, coordination)
        var quota = RoomQuotaLedger(database)
        quota.initializeInstallation("44444444-4444-4444-8444-444444444444", 1_700_000_000_000)
        assertEquals(
            QuotaReservationResult.Reserved("55555555-5555-4555-8555-555555555555"),
            quota.reserve(requestID, "55555555-5555-4555-8555-555555555555", 1_700_000_000_000),
        )

        // 1. Durable local enqueue (Phase 2 production path).
        assertEquals(EnqueueResult.SavedLocally(requestID), store.enqueue(requestBytes(), 1_700_000_000_000))

        // 2. Lease + PREPARING append (Phase 3 production path).
        val granted = coordinator.acquire(requestID, leaseToken, 1_700_000_000_001, 600_000)
        assertTrue("lease grant failed: $granted", granted is LeasePlan.Grant)
        val queued = store.loadJournal(requestID)!!
        val preparingAppend = coordinator.mutate(
            JournalMutationCommand(requestID, queued.revision, JournalEvent(queued.revision + 1, CaptureState.QUEUED, CaptureState.PREPARING, JournalCode.PREPARATION_STARTED, 1_700_000_000_002), leaseToken),
            1_700_000_000_002,
        )
        assertTrue("preparing append failed: $preparingAppend", preparingAppend is JournalMutationResult.Applied)

        // 3. Materialization through the REAL native core (Phase 4 bridge + Phase 5 coordinator).
        val bridge = productionCoreBridge()
        val gateway = AndroidSafDocumentsGateway(context)
        val occupancy = SafCandidateOccupancy(gateway, destination)
        var time = 1_700_000_000_003L
        val materializer = CoreMaterializationCoordinator(bridge, store, coordinator, occupancy, occupancy, destination) { time++ }
        val materialized = materializer.materialize(requestID, leaseToken, store.loadJournal(requestID)!!.revision)
        assertTrue(
            "materialization failed: $materialized; bridge=${bridge.availability}",
            materialized is CoreMaterializationCoordinator.MaterializationResult.Materialized,
        )
        val planHash = (materialized as CoreMaterializationCoordinator.MaterializationResult.Materialized).planHash
        assertEquals(CaptureState.MATERIALIZED, store.loadJournal(requestID)!!.state)

        // Prepared note bytes exist and are non-empty markdown verified by the core.
        val artifacts = store.loadPreparedArtifacts(requestID, planHash)!!
        assertTrue(artifacts.noteBytes.size in 1..1_048_576)
        val noteText = artifacts.noteBytes.toString(Charsets.UTF_8)
        assertTrue(noteText.endsWith("\n"))
        assertTrue(noteText.contains("Synthetic capture text."))
        assertTrue(noteText.contains("[Synthetic link](https://example.invalid/synthetic)"))
        assertEquals(listOf("Inbox"), logicalFolderOf(artifacts.planBytes))
        assertEquals("capture-$requestID.md", candidateNameOf(artifacts.planBytes))

        // Provider calls use the real external-storage provider. Faults are injected only
        // at executor boundaries; neither grant validation nor readback is substituted.
        var activeToken = leaseToken
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        val provider = object : SafDocumentsGateway by gateway {
            var creates = 0
            var writes = 0
            var readbackUnavailable = fault == Fault.READBACK_FAILURE
            override fun createDocument(marker: DurableMarkerToken, parent: SafFolderHandle, displayName: String, mediaType: String): SafResult<SafDocumentHandle> {
                creates++
                val result = gateway.createDocument(marker,parent,displayName,mediaType)
                if (fault == Fault.AFTER_CREATE && result is SafResult.Success) throw InterruptedDelivery()
                return result
            }
            override fun writeDocument(handle: SafDocumentHandle, bytes: ByteArray, expectedLength: Long): SafResult<Unit> {
                writes++
                if (fault == Fault.PARTIAL_WRITE) {
                    val partial = bytes.copyOf(bytes.size / 2)
                    assertTrue(gateway.writeDocument(handle,partial,partial.size.toLong()) is SafResult.Success)
                    return SafResult.error(GatewayError.ProviderFailure.name)
                }
                val result = gateway.writeDocument(handle,bytes,expectedLength)
                if (result is SafResult.Success && fault in setOf(Fault.AFTER_WRITE,Fault.REVOKED_AFTER_WRITE)) {
                    if (fault == Fault.REVOKED_AFTER_WRITE) context.contentResolver.releasePersistableUriPermission(treeUri,flags)
                    throw InterruptedDelivery()
                }
                return result
            }
            override fun readBackDocument(handle: SafDocumentHandle): SafResult<Pair<Long,String>> =
                if (readbackUnavailable) SafResult.error(GatewayError.ProviderFailure.name) else gateway.readBackDocument(handle)
        }
        fun attempt() = SafVaultCommitExecutor(store,coordinator,provider,destination,bridge::buildInfo,{ time++ }).execute(requestID,activeToken)
        fun preserved(expected: CaptureState) {
            assertEquals(expected,store.loadJournal(requestID)!!.state)
            assertArrayEquals(requestBytes(),store.loadRequestBytes(requestID))
            val retained = store.loadPreparedArtifacts(requestID,planHash)!!
            assertArrayEquals(artifacts.noteBytes,retained.noteBytes)
            assertArrayEquals(artifacts.planBytes,retained.planBytes)
            assertEquals(0,database.captureCoordinationDao().committedUnits())
            assertEquals(1,database.captureCoordinationDao().allReservations().size)
            assertTrue(database.captureCoordinationDao().allTombstones().isEmpty())
        }
        fun resumePermission() {
            val snapshot = store.loadJournal(requestID)!!
            val restored = coordinator.mutate(JournalMutationCommand(requestID,snapshot.revision,
                JournalEvent(snapshot.revision+1,CaptureState.NEEDS_PERMISSION,snapshot.resumeState!!,
                    JournalCode.PERMISSION_RESTORED,time++)),time++)
            assertTrue("permission resume: $restored",restored is JournalMutationResult.Applied)
        }
        if (fault == Fault.CLEARED_RETRY) {
            var snapshot = store.loadJournal(requestID)!!
            assertTrue(coordinator.mutate(JournalMutationCommand(requestID,snapshot.revision,
                JournalEvent(snapshot.revision+1,CaptureState.MATERIALIZED,CaptureState.COMMITTING,JournalCode.COMMIT_STARTED,time++,planHash=planHash),activeToken),time++) is JournalMutationResult.Applied)
            store.persistCommitMarker(requestID,CommitMarker.validated(CommitMarker.MarkerState.ACTIVE,destination.destinationID,planHash,candidateNameOf(artifacts.planBytes),time++))
            // The fixture has not issued any provider create. Record that causal proof
            // through the same durable transition used by reconciliation.
            snapshot = store.loadJournal(requestID)!!
            assertTrue(coordinator.mutate(JournalMutationCommand(requestID,snapshot.revision,
                JournalEvent(snapshot.revision+1,CaptureState.COMMITTING,CaptureState.RETRYABLE_FAILURE,JournalCode.PROVED_NOT_COMMITTED,time++),activeToken,clearCommitMarker=true),time++) is JournalMutationResult.Applied)
            preserved(CaptureState.RETRYABLE_FAILURE)
            assertEquals(CommitMarker.MarkerState.CLEARED,store.readCommitMarker(requestID)!!.state)
            assertEquals(0,provider.creates)
        } else if (fault == Fault.REVOKED_BEFORE) {
            context.contentResolver.releasePersistableUriPermission(treeUri,flags)
            assertFalse(gateway.revalidateGrant(destination))
            assertEquals(CommitOutcome.PermissionLost,(attempt() as ExecutorOutcome.Ok).value)
            preserved(CaptureState.NEEDS_PERMISSION)
            assertEquals(CaptureState.MATERIALIZED,store.loadJournal(requestID)!!.resumeState)
            assertNull(store.readCommitMarker(requestID))
            assertEquals(0,provider.creates)
        } else if (fault != Fault.NONE) {
            if (fault in setOf(Fault.AFTER_WRITE,Fault.AFTER_CREATE,Fault.REVOKED_AFTER_WRITE)) {
                try { attempt(); fail("Expected interruption at provider boundary") } catch (_: InterruptedDelivery) { }
                preserved(CaptureState.COMMITTING)
            } else {
                assertEquals(CommitOutcome.Ambiguous,(attempt() as ExecutorOutcome.Ok).value)
                preserved(CaptureState.UNKNOWN_OUTCOME)
            }
            assertEquals(CommitMarker.MarkerState.ACTIVE,store.readCommitMarker(requestID)!!.state)
            assertEquals(1,provider.creates)
        }
        if (fault != Fault.NONE) {
            // A fresh Room connection/store/coordinator must recover solely from persisted
            // bytes and the expired lease. No in-memory executor state is carried over.
            database.close()
            database = CaptureDatabase.create(context)
            store = DurableCapturePackageStore(context.noBackupFilesDir,RoomCaptureIndex(database),AndroidDurableFileOps())
            coordinator = CaptureDurabilityCoordinator(store,RoomCaptureCoordination(database))
            quota = RoomQuotaLedger(database)
            store.reconcile()
            time += 600_001
            activeToken = "77777777-7777-4777-8777-777777777777"
            assertTrue(coordinator.acquire(requestID,activeToken,time++,600_000) is LeasePlan.Grant)
            assertEquals(QuotaReservationResult.Existing("55555555-5555-4555-8555-555555555555"),
                quota.reserve(requestID,"88888888-8888-4888-8888-888888888888",time++))
            if (fault == Fault.CLEARED_RETRY) {
                val snapshot = store.loadJournal(requestID)!!
                assertTrue(coordinator.mutate(JournalMutationCommand(requestID,snapshot.revision,
                    JournalEvent(snapshot.revision+1,CaptureState.RETRYABLE_FAILURE,CaptureState.PREPARING,JournalCode.PREPARATION_STARTED,time++),activeToken),time++) is JournalMutationResult.Applied)
                val recovered = CoreMaterializationCoordinator(bridge,store,coordinator,occupancy,occupancy,destination) { time++ }
                    .materialize(requestID,activeToken,store.loadJournal(requestID)!!.revision)
                assertTrue("rematerialization: $recovered",recovered is CoreMaterializationCoordinator.MaterializationResult.Materialized)
                assertEquals(planHash,(recovered as CoreMaterializationCoordinator.MaterializationResult.Materialized).planHash)
                preserved(CaptureState.MATERIALIZED)
            }
            if (fault in setOf(Fault.REVOKED_BEFORE,Fault.REVOKED_AFTER_WRITE)) {
                if (fault == Fault.REVOKED_AFTER_WRITE) {
                    assertEquals(CommitOutcome.PermissionLost,(attempt() as ExecutorOutcome.Ok).value)
                    preserved(CaptureState.NEEDS_PERMISSION)
                    assertEquals(CaptureState.COMMITTING,store.loadJournal(requestID)!!.resumeState)
                }
                // No provider mutation is attempted while waiting for explicit repair.
                val creates = provider.creates; val writes = provider.writes
                repeat(3) { assertTrue(attempt() is ExecutorOutcome.Err); preserved(CaptureState.NEEDS_PERMISSION) }
                assertEquals(creates,provider.creates); assertEquals(writes,provider.writes)
                assertEquals(treeUri,grantTreeThroughSystemPicker(instrumentation,requestedTreeUri))
                assertTrue(gateway.revalidateGrant(destination))
                resumePermission()
            }
            if (fault in setOf(Fault.AFTER_CREATE,Fault.PARTIAL_WRITE,Fault.READBACK_FAILURE)) {
                val creates = provider.creates; val writes = provider.writes
                repeat(3) {
                    assertEquals(CommitOutcome.Ambiguous,(attempt() as ExecutorOutcome.Ok).value)
                    preserved(CaptureState.UNKNOWN_OUTCOME)
                }
                assertEquals(creates,provider.creates); assertEquals(writes,provider.writes)
                val folder = gateway.resolveFolder(destination,logicalFolderOf(artifacts.planBytes),false)!!
                val target = gateway.findChildByDisplayName(folder,candidateNameOf(artifacts.planBytes)).single()
                if (fault != Fault.READBACK_FAILURE) {
                    val actual = (gateway.readDocument(target,1_048_576) as SafResult.Success).value
                    assertArrayEquals(if (fault == Fault.AFTER_CREATE) byteArrayOf() else artifacts.noteBytes.copyOf(artifacts.noteBytes.size/2),actual)
                    // Simulate the provider completing its delayed write. Recovery itself
                    // never overwrites or deletes the ambiguous document.
                    assertTrue(gateway.writeDocument(target,artifacts.noteBytes,artifacts.noteBytes.size.toLong()) is SafResult.Success)
                }
                provider.readbackUnavailable = false
            }
        }
        val outcome = attempt()
        assertTrue("commit failed: $outcome", outcome is ExecutorOutcome.Ok && outcome.value is CommitOutcome.VerifiedCommitted)
        assertEquals(1,provider.creates)
        assertEquals(if (fault == Fault.AFTER_CREATE) 0 else 1,provider.writes)
        val committedFolder = gateway.resolveFolder(destination,logicalFolderOf(artifacts.planBytes),false)!!
        assertEquals(listOf(candidateNameOf(artifacts.planBytes)),gateway.listChildDisplayNames(committedFolder))

        // 5. Terminal state: COMPLETED journal with the deterministic receipt on disk.
        val snapshot = store.loadJournal(requestID)!!
        assertEquals(CaptureState.COMPLETED, snapshot.state)
        val receiptID = snapshot.events.last().receiptID!!
        val receipt = store.loadReceipt(requestID, receiptID)!!
        assertEquals(planHash, receipt.planHash)
        assertEquals(artifacts.descriptor.noteLengthBytes, receipt.verifiedLengthBytes)
        assertEquals(artifacts.descriptor.noteSHA256, receipt.verifiedSHA256)
        assertEquals(CommitMarker.MarkerState.ACTIVE, store.readCommitMarker(requestID)!!.state)

        // 6. Read the committed note back through the provider and compare exact bytes.
        val noteDescriptor = gateway.findChildByDisplayName(
            gateway.resolveFolder(destination, logicalFolderOf(artifacts.planBytes), createMissing = false)!!,
            candidateNameOf(artifacts.planBytes),
        ).single()
        val readBack = (gateway.readBackDocument(noteDescriptor) as SafResult.Success).value
        assertEquals(artifacts.noteBytes.size.toLong(), readBack.first)
        assertEquals(artifacts.descriptor.noteSHA256, readBack.second)

        // 7. Production completion compaction leaves only independent content-free
        // accounting/activity proof and the ID/timestamp inbox marker. The request,
        // source text, assets, prepared Markdown, marker, and receipt are all removed.
        val completions = RoomCaptureCompletionLedger(database)
        val compactor = CompletedCaptureCompactor(
            store = store,
            quota = quota,
            activity = RoomActivityStatsLedger(database),
            completions = completions,
            buildInfo = bridge::buildInfo,
            rendererVersion = "swift-legacy-m0",
            profileID = "apple-parity-v1",
        )
        assertEquals(CompletionCompactionResult.Compacted, compactor.compact(requestID))
        assertEquals(CompletionCompactionResult.AlreadyCompacted, compactor.compact(requestID))
        assertNull(store.loadRequestBytes(requestID))
        assertNull(store.loadJournal(requestID))
        assertNull(RoomCaptureIndex(database).read(requestID))
        assertEquals(1, database.captureActivityDao().all().size)
        assertEquals(1, database.captureCoordinationDao().allTombstones().size)
        assertEquals(1, database.captureCoordinationDao().committedUnits())
        assertTrue(database.captureCoordinationDao().allReservations().isEmpty())
        val completion = completions.read(requestID)
        assertNotNull(completion)
        assertEquals(snapshot.events.last().occurredAtEpochMillis, completion!!.completedAtEpochMillis)
        database.openHelper.writableDatabase.query("PRAGMA table_info(`capture_completion`)").use { cursor ->
            val nameColumn = cursor.getColumnIndexOrThrow("name")
            val columns = buildList { while (cursor.moveToNext()) add(cursor.getString(nameColumn)) }
            assertEquals(listOf("requestID", "completedAtEpochMillis"), columns)
        }
        assertEquals(
            QuotaReservationResult.AlreadyCommitted,
            quota.reserve(requestID, "66666666-6666-4666-8666-666666666666", time++),
        )

        database.close()
        context.contentResolver.releasePersistableUriPermission(
            treeUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
        )
        instrumentation.uiAutomation.adoptShellPermissionIdentity()
        try {
            assertTrue("vault cleanup failed", vaultRoot.deleteRecursively())
        } finally {
            instrumentation.uiAutomation.dropShellPermissionIdentity()
        }
    }

    private fun logicalFolderOf(planBytes: ByteArray): List<String> {
        val plan = CapturePackageCodec.parseCanonical(planBytes)
        val note = (plan["artifacts"] as kotlinx.serialization.json.JsonArray)
            .single { (it as kotlinx.serialization.json.JsonObject)["kind"].toString().contains("note") } as kotlinx.serialization.json.JsonObject
        return (note["logicalPath"] as kotlinx.serialization.json.JsonArray).map { (it as kotlinx.serialization.json.JsonPrimitive).content }.dropLast(1)
    }

    private fun candidateNameOf(planBytes: ByteArray): String {
        val plan = CapturePackageCodec.parseCanonical(planBytes)
        val note = (plan["artifacts"] as kotlinx.serialization.json.JsonArray)
            .single { (it as kotlinx.serialization.json.JsonObject)["kind"].toString().contains("note") } as kotlinx.serialization.json.JsonObject
        return (note["logicalPath"] as kotlinx.serialization.json.JsonArray).map { (it as kotlinx.serialization.json.JsonPrimitive).content }.last()
    }

    private fun grantTreeThroughSystemPicker(
        instrumentation: android.app.Instrumentation,
        requestedTreeUri: android.net.Uri,
    ): android.net.Uri {
        SafTreeGrantActivity.reset()
        val initialDocumentUri = DocumentsContract.buildDocumentUriUsingTree(
            requestedTreeUri,
            DocumentsContract.getTreeDocumentId(requestedTreeUri),
        )
        instrumentation.startActivitySync(
            SafTreeGrantActivity.launchIntent(instrumentation.targetContext, initialDocumentUri),
        )
        assertTrue(
            "DocumentsUI did not expose the tree-selection action",
            clickEventually(
                instrumentation.uiAutomation,
                listOf(
                    "com.google.android.documentsui:id/action_menu_select",
                    "com.android.documentsui:id/action_menu_select",
                ),
                listOf("Use this folder"),
            ),
        )
        assertTrue(
            "DocumentsUI did not expose the grant confirmation",
            clickEventually(
                instrumentation.uiAutomation,
                listOf("android:id/button1"),
                listOf("Allow"),
            ),
        )
        return SafTreeGrantActivity.awaitResult(10).getOrThrow()
    }

    private fun clickEventually(
        uiAutomation: android.app.UiAutomation,
        viewIDs: List<String>,
        textCandidates: List<String>,
        timeoutMillis: Long = 10_000,
    ): Boolean {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            val root = uiAutomation.rootInActiveWindow
            val candidates = buildList {
                viewIDs.forEach { addAll(root?.findAccessibilityNodeInfosByViewId(it).orEmpty()) }
                textCandidates.forEach { addAll(root?.findAccessibilityNodeInfosByText(it).orEmpty()) }
            }
            if (candidates.any(::clickNodeOrClickableParent)) return true
            SystemClock.sleep(100)
        }
        return false
    }

    private fun clickNodeOrClickableParent(node: AccessibilityNodeInfo): Boolean {
        var candidate: AccessibilityNodeInfo? = node
        repeat(4) {
            val current = candidate ?: return false
            if (current.isVisibleToUser && current.isEnabled &&
                current.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            ) return true
            candidate = current.parent
        }
        return false
    }
}
