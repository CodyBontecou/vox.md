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

    @Test
    fun enqueueMaterializeCommitAndVerifyThroughRealProvider() {
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

        val database = CaptureDatabase.create(context)
        val store = DurableCapturePackageStore(context.noBackupFilesDir, RoomCaptureIndex(database), AndroidDurableFileOps())
        val coordination = RoomCaptureCoordination(database)
        val coordinator = CaptureDurabilityCoordinator(store, coordination)
        val quota = RoomQuotaLedger(database)
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

        // 4. Commit through the real local DocumentsProvider (Phase 5 executor).
        val executor = SafVaultCommitExecutor(
            store, coordinator, gateway, destination,
            buildInfo = { bridge.buildInfo() },
            clock = { time++ },
        )
        val outcome = executor.execute(requestID, leaseToken)
        assertTrue("commit failed: $outcome", outcome is ExecutorOutcome.Ok && outcome.value is CommitOutcome.VerifiedCommitted)

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
