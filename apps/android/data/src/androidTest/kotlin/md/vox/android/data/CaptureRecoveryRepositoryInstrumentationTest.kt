package md.vox.android.data

import android.content.Context
import android.content.ContextWrapper
import android.database.DatabaseErrorHandler
import android.database.sqlite.SQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import java.io.File
import java.util.UUID
import kotlinx.coroutines.runBlocking
import md.vox.android.capturedomain.*
import md.vox.android.corebridge.unwiredCoreBridge
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** Repository/Room integration. No model inference or provider writes are required. */
@RunWith(AndroidJUnit4::class)
class CaptureRecoveryRepositoryInstrumentationTest {
    private val sourceID = "11111111-1111-4111-8111-111111111111"
    private val replacementID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    private val vaultID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"

    // Each repository gets its own database, DataStore and package root.
    private fun context(): Context {
        val base = ApplicationProvider.getApplicationContext<Context>()
        val root = File(base.cacheDir, "recovery-${UUID.randomUUID()}").apply { mkdirs() }
        return object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getNoBackupFilesDir(): File = File(root, "no-backup").apply { mkdirs() }
            override fun getFilesDir(): File = File(root, "files").apply { mkdirs() }
            override fun getDatabasePath(name: String): File = File(root, name)
            override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?): SQLiteDatabase =
                base.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory)
            override fun openOrCreateDatabase(name: String, mode: Int, factory: SQLiteDatabase.CursorFactory?, errorHandler: DatabaseErrorHandler?): SQLiteDatabase =
                base.openOrCreateDatabase(getDatabasePath(name).absolutePath, mode, factory, errorHandler)
            override fun deleteDatabase(name: String): Boolean = base.deleteDatabase(getDatabasePath(name).absolutePath)
        }
    }

    private fun retireSource(context: Context, database: CaptureDatabase) {
        val store = DurableCapturePackageStore(context.noBackupFilesDir, RoomCaptureIndex(database))
        val coordinator = CaptureDurabilityCoordinator(store, RoomCaptureCoordination(database))
        val bytes = InstrumentationRegistry.getInstrumentation().context.assets
            .open("capture-preparation-input/valid-android-m3-text-link.json").use { it.readBytes() }
        assertTrue(store.enqueue(bytes, 10) is EnqueueResult.SavedLocally)
        val preset = CapturePreset(vaultID, "Recovery", "description", revision = 1,
            logicalFolder = "Inbox", noteNameTemplate = "capture-{id}.md", metadataFields = emptyList())
        val intent = CaptureRecoveryIntent(replacementID, sourceID, CapturePackageCodec.sha256(bytes), 0,
            CaptureState.QUEUED, 30, "route:$vaultID:1:$vaultID", recoveryRequest(bytes, replacementID, vaultID, preset))
        val engine = CaptureReplacement(store, coordinator, CaptureRecoveryIntentStore(context.noBackupFilesDir), { 40 }, { true },
            checkpoint = { if (it == "sourceRetired") error("interrupted before enqueue") })
        assertTrue(engine.admit(intent) { true } is ReplacementOutcome.Waiting)
        assertEquals(CaptureState.DISCARDED, store.loadJournal(sourceID)!!.state)
        assertNull(store.loadJournal(replacementID))
    }

    @Test fun deletingCompletedHistoryCannotResurrectDeliveredReplacement() = runBlocking {
        val context = context()
        val database = CaptureDatabase.create(context)
        retireSource(context, database)
        // The persisted tail of a verified, compacted replacement. Presentation history
        // is separately deletable; the permanent terminal/quota proof is not.
        val quota = RoomQuotaLedger(database)
        quota.initializeInstallation(vaultID, 40)
        assertTrue(quota.reserve(replacementID, sourceID, 40, chargeFreeQuota = false) is QuotaReservationResult.Reserved)
        assertEquals(TerminalQuotaResult.COMMITTED, quota.commitVerifiedTerminal(VerifiedTerminalDraft(
            replacementID, 50, vaultID, sourceID, 1, 1, 1, 5,
            "0.1.0-alpha.1", "swift-legacy-m0", "apple-parity-v1", 1)))
        assertTrue(RoomCaptureCompletionLedger(database).record(replacementID, 50))
        database.close()
        val repository = AndroidCaptureRepository(context, unwiredCoreBridge(), clock = { 100 })
        assertEquals(1, repository.deleteCompletedHistory(setOf(replacementID)))
        repeat(2) {
            assertFalse(repository.reconcile().any { it.requestID == replacementID })
            assertEquals(CaptureSubmitResult.Delivered(replacementID), repository.retry(sourceID))
            assertFalse(File(context.noBackupFilesDir, "vox-captures/$replacementID").exists())
        }
    }

    @Test fun backgroundDrainReplaysRetiredSourceWithoutForegroundRefresh() = runBlocking {
        val context = context()
        val database = CaptureDatabase.create(context)
        retireSource(context, database)
        database.close()
        // Ended access cannot revoke a previously admitted intent. No destination grant
        // is present, so the ordinary driver must stop at permission recovery.
        val repository = AndroidCaptureRepository(context, unwiredCoreBridge(), clock = { 100 }, isAccessEnded = { true })
        val summary = repository.drainPending(16)
        assertEquals(1, summary.inspected)
        assertEquals(1, summary.needsPermission)
        assertTrue(File(context.noBackupFilesDir, "vox-captures/$replacementID/request.json").isFile)
    }

    @Test fun backgroundDrainRetriesBusyIntentEvenWithNoPendingPackage() = runBlocking {
        val context = context()
        val database = CaptureDatabase.create(context)
        retireSource(context, database)
        val store = DurableCapturePackageStore(context.noBackupFilesDir, RoomCaptureIndex(database))
        val coordinator = CaptureDurabilityCoordinator(store, RoomCaptureCoordination(database))
        assertTrue(coordinator.acquire(sourceID, vaultID, 50, 60_000) is LeasePlan.Grant)
        database.close()
        val repository = AndroidCaptureRepository(context, unwiredCoreBridge(), clock = { 100 })
        val summary = repository.drainPending(16)
        assertEquals(0, summary.inspected)
        assertEquals(1, summary.retryable)
        assertFalse(File(context.noBackupFilesDir, "vox-captures/$replacementID").exists())
    }
}
