package md.vox.android.data

import android.content.Context
import androidx.room.Room
import androidx.room.testing.MigrationTestHelper
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import md.vox.android.capturedomain.*
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/** Compiles and executes generated Room/DAO/migration code only when a target campaign runs. */
@RunWith(AndroidJUnit4::class)
class CaptureDatabaseInstrumentationTest {
    @get:Rule val migration = MigrationTestHelper(InstrumentationRegistry.getInstrumentation(), CaptureDatabase::class.java)
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test fun generatedRoomProjectionLeaseAndQuotaAreContentFreeAndIdempotent() {
        val database = Room.inMemoryDatabaseBuilder(context, CaptureDatabase::class.java).build()
        try {
            val index = RoomCaptureIndex(database)
            val request = REQUEST
            val projection = CaptureIndexProjection(request, 1, 1, 0, CaptureState.QUEUED, 10, 10, 0)
            assertEquals(IndexWriteResult.INSERTED, index.insertOrRepair(projection))
            assertEquals(IndexWriteResult.IDENTICAL, index.insertOrRepair(projection))
            assertEquals(projection, index.read(request))
            val coordinator = coordinator(database, "basic")
            assertTrue(coordinator.acquire(request, TOKEN, 100, 10_000) is LeasePlan.Grant)
            assertEquals(LeasePlan.Busy(9_000), coordinator.acquire(request, SECOND_TOKEN, 9_000, 1_000))
            assertEquals(LeasePlan.ClockRollback, coordinator.renew(request, TOKEN, 1_000, 1_000))
            assertTrue(coordinator.release(request, TOKEN))

            val quota = RoomQuotaLedger(database)
            val installation = quota.initializeInstallation(INSTALLATION, 100)
            repeat(10) { n ->
                val id = request(n + 1); val token = token(n + 1)
                val reservation = quota.reserve(id, token, 100L + n)
                assertTrue(reservation is QuotaReservationResult.Reserved)
                assertEquals(QuotaReservationResult.Existing(token), quota.reserve(id, "20000000-0000-4000-8000-${(n + 1).toString().padStart(12, '0')}", 200L + n))
            }
            assertEquals(QuotaReservationResult.LimitReached, quota.reserve(request, THIRD_TOKEN, 300))
            val paidRequest = "77777777-7777-4777-8777-777777777777"
            val paidToken = "88888888-8888-4888-8888-888888888888"
            assertEquals(
                QuotaReservationResult.Reserved(paidToken),
                quota.reserve(paidRequest, paidToken, 301, chargeFreeQuota = false),
            )
            assertEquals(0, database.captureCoordinationDao().readReservation(paidRequest).quotaUnits)
            assertEquals(installation, quota.initializeInstallation("66666666-6666-4666-8666-666666666666", 300))
        } finally { database.close() }
    }

    @Test fun activityLedgerIsContentFreeIdempotentAndKeepsSevenDayBreakdown() {
        val database = Room.inMemoryDatabaseBuilder(context, CaptureDatabase::class.java).build()
        try {
            val ledger = RoomActivityStatsLedger(database)
            val now = 1_787_875_200_000L
            assertTrue(ledger.recordCapture(REQUEST, now, "share", 2))
            assertTrue(ledger.recordCapture(REQUEST, now + 1, "app", 99))
            assertTrue(ledger.recordRecording(SECOND_TOKEN, now, 65_000))
            assertTrue(ledger.recordRecording(SECOND_TOKEN, now + 1, 10))

            val stats = ledger.snapshot(now, java.time.ZoneOffset.UTC)
            assertEquals(1, stats.captureCount)
            assertEquals(1, stats.recordingCount)
            assertEquals(2, stats.attachmentCount)
            assertEquals(65_000, stats.recordedDurationMillis)
            assertEquals(mapOf("share" to 1), stats.captureSources)
            assertEquals(7, stats.lastSevenDays.size)
            assertEquals(1, stats.lastSevenDays.last().captureCount)
            assertEquals(1, stats.lastSevenDays.last().recordingCount)
        } finally { database.close() }
    }

    @Test fun completionLedgerContainsOnlyStableIDAndTimestampAndIsIdempotent() {
        val database = Room.inMemoryDatabaseBuilder(context, CaptureDatabase::class.java).build()
        try {
            val ledger = RoomCaptureCompletionLedger(database)
            assertTrue(ledger.record(REQUEST, 1_700_000_000_123))
            assertTrue(ledger.record(REQUEST, 1_700_000_000_123))
            assertFalse(ledger.record(REQUEST, 1_700_000_000_124))
            assertEquals(CaptureCompletion(REQUEST, 1_700_000_000_123), ledger.read(REQUEST))
            assertEquals(listOf(CaptureCompletion(REQUEST, 1_700_000_000_123)), ledger.all())
            database.openHelper.writableDatabase.query("PRAGMA table_info(`capture_completion`)").use { cursor ->
                val names = buildList {
                    val nameColumn = cursor.getColumnIndexOrThrow("name")
                    while (cursor.moveToNext()) add(cursor.getString(nameColumn))
                }
                assertEquals(listOf("requestID", "completedAtEpochMillis"), names)
            }
            assertTrue(ledger.delete(REQUEST))
            assertNull(ledger.read(REQUEST))
        } finally { database.close() }
    }

    @Test fun migrationTwoToThreeAddsOnlyContentFreeActivityTables() {
        val name = "capture-migration-v3-${System.nanoTime()}"
        migration.createDatabase(name, 2).close()
        val migrated = migration.runMigrationsAndValidate(name, 3, true, CaptureDatabase.MIGRATION_2_3)
        try {
            for (table in listOf("capture_activity", "recording_activity")) {
                migrated.query("PRAGMA table_info(`$table`)").use { cursor -> assertTrue(cursor.count > 0) }
            }
        } finally { migrated.close(); context.deleteDatabase(name) }
    }

    @Test fun migrationThreeToFourPreservesReservationsAsFreeQuotaUnits() {
        val name = "capture-migration-v4-${System.nanoTime()}"
        migration.createDatabase(name, 3).apply {
            execSQL("INSERT INTO quota_reservation VALUES ('$REQUEST','$TOKEN','$INSTALLATION',1,2)")
            close()
        }
        val migrated = migration.runMigrationsAndValidate(name, 4, true, CaptureDatabase.MIGRATION_3_4)
        try {
            migrated.query("SELECT quotaUnits FROM quota_reservation WHERE requestID='$REQUEST'").use { cursor ->
                assertTrue(cursor.moveToFirst())
                assertEquals(1, cursor.getInt(0))
            }
        } finally { migrated.close(); context.deleteDatabase(name) }
    }

    @Test fun migrationFourToFiveAddsOnlyThePayloadFreeCompletionTable() {
        val name = "capture-migration-v5-${System.nanoTime()}"
        migration.createDatabase(name, 4).close()
        val migrated = migration.runMigrationsAndValidate(name, 5, true, CaptureDatabase.MIGRATION_4_5)
        try {
            migrated.query("PRAGMA table_info(`capture_completion`)").use { cursor ->
                val nameColumn = cursor.getColumnIndexOrThrow("name")
                val columns = buildList { while (cursor.moveToNext()) add(cursor.getString(nameColumn)) }
                assertEquals(listOf("requestID", "completedAtEpochMillis"), columns)
            }
        } finally { migrated.close(); context.deleteDatabase(name) }
    }

    @Test fun unmeteredRecordingReservationCommitsZeroCaptureUnitsAndRemainsIdempotent() {
        val database = Room.inMemoryDatabaseBuilder(context, CaptureDatabase::class.java).build()
        try {
            val quota = RoomQuotaLedger(database)
            quota.initializeInstallation(INSTALLATION, 1)
            assertEquals(
                QuotaReservationResult.Reserved(TOKEN),
                quota.reserve(REQUEST, TOKEN, 2, chargeFreeQuota = false),
            )
            val draft = tombstoneDraft()
            assertEquals(TerminalQuotaResult.COMMITTED, quota.commitTerminal(TOKEN, draft))
            assertEquals(TerminalQuotaResult.IDENTICAL, quota.commitTerminal(TOKEN, draft))
            assertEquals(0, database.captureCoordinationDao().committedUnits())
            assertEquals(0, database.captureCoordinationDao().readTombstone(REQUEST).quotaUnits)
        } finally { database.close() }
    }

    @Test fun failedWriteReservationAndRetryConsumeOnlyAfterVerifiedTerminalCommit() {
        val database = Room.inMemoryDatabaseBuilder(context, CaptureDatabase::class.java).build()
        try {
            val quota = RoomQuotaLedger(database)
            quota.initializeInstallation(INSTALLATION, 1)
            assertEquals(QuotaReservationResult.Reserved(TOKEN), quota.reserve(REQUEST, TOKEN, 2))
            assertEquals(0, database.captureCoordinationDao().committedUnits())
            assertEquals(QuotaReservationResult.Existing(TOKEN), quota.reserve(REQUEST, SECOND_TOKEN, 3))
            assertEquals(0, database.captureCoordinationDao().committedUnits())

            assertEquals(TerminalQuotaResult.COMMITTED, quota.commitTerminal(TOKEN, tombstoneDraft()))
            assertEquals(1, database.captureCoordinationDao().committedUnits())
            assertEquals(QuotaReservationResult.AlreadyCommitted, quota.reserve(REQUEST, SECOND_TOKEN, 4))
            assertEquals(1, database.captureCoordinationDao().committedUnits())
        } finally { database.close() }
    }

    @Test fun greatestLeaseClockSurvivesCloseAndReopen() {
        val name = "capture-clock-${System.nanoTime()}.db"; val root = testRoot("clock")
        fun open() = Room.databaseBuilder(context, CaptureDatabase::class.java, name).addMigrations(CaptureDatabase.MIGRATION_1_2).build()
        try {
            val first = open()
            try {
                RoomCaptureIndex(first).insertOrRepair(CaptureIndexProjection(REQUEST, 1, 1, 0, CaptureState.QUEUED, 1, 1, 0))
                val coordinator = CaptureDurabilityCoordinator(DurableCapturePackageStore(root, RoomCaptureIndex(first)), RoomCaptureCoordination(first))
                assertTrue(coordinator.acquire(REQUEST, TOKEN, 0, 10_000) is LeasePlan.Grant)
                assertEquals(LeasePlan.Busy(9_000), coordinator.acquire(REQUEST, SECOND_TOKEN, 9_000, 1_000))
                assertEquals(LeasePlan.Lost(9_001), coordinator.renew(REQUEST, SECOND_TOKEN, 9_001, 1_000))
            } finally { first.close() }
            val reopened = open()
            try {
                val coordinator = CaptureDurabilityCoordinator(DurableCapturePackageStore(root, RoomCaptureIndex(reopened)), RoomCaptureCoordination(reopened))
                assertEquals(LeasePlan.ClockRollback, coordinator.renew(REQUEST, TOKEN, 1_000, 1_000))
            } finally { reopened.close() }
        } finally { context.deleteDatabase(name); root.deleteRecursively() }
    }

    @Test fun internalTerminalTransactionRollsBackAfterTombstoneInsertAndIsIdempotent() {
        val database = Room.inMemoryDatabaseBuilder(context, CaptureDatabase::class.java).build()
        try {
            val quota = RoomQuotaLedger(database)
            quota.initializeInstallation(INSTALLATION, 1)
            assertTrue(quota.reserve(REQUEST, TOKEN, 2) is QuotaReservationResult.Reserved)
            val draft = tombstoneDraft()
            database.openHelper.writableDatabase.execSQL("CREATE TRIGGER fail_terminal_delete BEFORE DELETE ON quota_reservation BEGIN SELECT RAISE(ABORT, 'injected'); END")
            assertThrows(Throwable::class.java) { quota.commitTerminal(TOKEN, draft) }
            assertNotNull(database.captureCoordinationDao().readReservation(REQUEST))
            assertNull(database.captureCoordinationDao().readTombstone(REQUEST))
            database.openHelper.writableDatabase.execSQL("DROP TRIGGER fail_terminal_delete")
            assertEquals(TerminalQuotaResult.COMMITTED, quota.commitTerminal(TOKEN, draft))
            assertEquals(TerminalQuotaResult.IDENTICAL, quota.commitTerminal(TOKEN, draft))
            assertEquals(1, database.captureCoordinationDao().committedUnits())
            assertNull(database.captureCoordinationDao().readReservation(REQUEST))
        } finally { database.close() }
    }

    @Test fun concurrentDifferentAndSameRequestReservationsAreBoundedAndIdempotent() {
        val database = Room.inMemoryDatabaseBuilder(context, CaptureDatabase::class.java).build()
        try {
            val quota = RoomQuotaLedger(database); quota.initializeInstallation(INSTALLATION, 1)
            val different = runConcurrent(12) { n -> quota.reserve(request(n + 1), token(n + 1), 10L + n) }
            assertEquals(10, different.count { it is QuotaReservationResult.Reserved })
            assertEquals(2, different.count { it is QuotaReservationResult.LimitReached })
            assertEquals(10, database.captureCoordinationDao().allReservations().size)
            database.captureCoordinationDao().allReservations().forEach { assertTrue(quota.release(it.requestID, it.reservationToken)) }
            val same = runConcurrent(12) { n -> quota.reserve(REQUEST, token(n + 1), 100L + n) }
            assertEquals(1, same.count { it is QuotaReservationResult.Reserved })
            assertEquals(11, same.count { it is QuotaReservationResult.Existing })
            assertEquals(1, database.captureCoordinationDao().allReservations().size)
        } finally { database.close() }
    }

    @Test fun concurrentLeaseAcquisitionIsExclusiveAndFenced() {
        val database = Room.inMemoryDatabaseBuilder(context, CaptureDatabase::class.java).build()
        val root = testRoot("lease-race")
        try {
            val index = RoomCaptureIndex(database); index.insertOrRepair(CaptureIndexProjection(REQUEST, 1, 1, 0, CaptureState.QUEUED, 1, 1, 0))
            val coordinator = CaptureDurabilityCoordinator(DurableCapturePackageStore(root, index), RoomCaptureCoordination(database))
            val results = runConcurrent(2) { n -> coordinator.acquire(REQUEST, if (n == 0) TOKEN else SECOND_TOKEN, 100, 10_000) }
            assertEquals(1, results.count { it is LeasePlan.Grant }); assertEquals(1, results.count { it is LeasePlan.Busy })
            val winner = (results.single { it is LeasePlan.Grant } as LeasePlan.Grant).lease.token
            val loser = if (winner == TOKEN) SECOND_TOKEN else TOKEN
            assertTrue(coordinator.isCurrent(REQUEST, winner, 101) is LeasePlan.Current)
            assertTrue(coordinator.isCurrent(REQUEST, loser, 102) is LeasePlan.Lost)
            assertFalse(coordinator.release(REQUEST, loser)); assertTrue(coordinator.release(REQUEST, winner))
        } finally { database.close(); root.deleteRecursively() }
    }

    @Test fun migrationOneToTwoPreservesProjectionAndMatchesFreshV2Schema() {
        val migratedName = "capture-migration-${System.nanoTime()}"; val freshName = "capture-fresh-${System.nanoTime()}.db"
        migration.createDatabase(migratedName, 1).apply {
            execSQL("INSERT INTO capture_projection VALUES ('$REQUEST',1,1,0,'QUEUED',10,10)")
            close()
        }
        val migrated = migration.runMigrationsAndValidate(migratedName, 2, true, CaptureDatabase.MIGRATION_1_2)
        val fresh = Room.databaseBuilder(context, CaptureDatabase::class.java, freshName).build()
        try {
            migrated.query("SELECT attemptCount FROM capture_projection").use { cursor -> assertTrue(cursor.moveToFirst()); assertEquals(0, cursor.getInt(0)) }
            migrated.query("SELECT COUNT(*) FROM installation_identity").use { cursor -> assertTrue(cursor.moveToFirst()); assertEquals(0, cursor.getInt(0)) }
            assertEquals(schemaShape(fresh.openHelper.writableDatabase), schemaShape(migrated))
        } finally { migrated.close(); fresh.close(); context.deleteDatabase(migratedName); context.deleteDatabase(freshName) }
    }

    private fun coordinator(database: CaptureDatabase, name: String): CaptureDurabilityCoordinator {
        val index = RoomCaptureIndex(database)
        return CaptureDurabilityCoordinator(DurableCapturePackageStore(testRoot(name), index), RoomCaptureCoordination(database))
    }

    private fun testRoot(name: String) = File(context.cacheDir, "capture-instrumentation-$name-${System.nanoTime()}").apply { check(mkdirs()) }

    private fun tombstoneDraft() = TombstoneDraft(REQUEST, INSTALLATION, 3, "33333333-3333-4333-8333-333333333333", THIRD_TOKEN, 1, 1, 1, 4, "0.1.0-alpha.1", "swift-legacy-m0", "apple-parity-v1", 1)

    private fun schemaShape(database: SupportSQLiteDatabase): Map<String, List<String>> {
        val tables = listOf("capture_projection", "capture_lease", "lease_clock", "installation_identity", "capture_tombstone")
        return tables.associateWith { table ->
            database.query("PRAGMA table_info(`$table`)").use { cursor ->
                buildList { while (cursor.moveToNext()) add((0 until cursor.columnCount).joinToString("|") { cursor.getString(it) ?: "NULL" }) }
            }
        }
    }

    private fun <T> runConcurrent(count: Int, action: (Int) -> T): List<T> {
        val start = CountDownLatch(1); val done = CountDownLatch(count)
        val results = java.util.Collections.synchronizedList(mutableListOf<T>()); val errors = java.util.Collections.synchronizedList(mutableListOf<Throwable>())
        val threads = (0 until count).map { n -> Thread { try { start.await(10, TimeUnit.SECONDS); results += action(n) } catch (error: Throwable) { errors += error } finally { done.countDown() } } }
        threads.forEach(Thread::start); start.countDown()
        assertTrue("concurrent operations timed out", done.await(20, TimeUnit.SECONDS))
        threads.forEach { it.join(1_000); assertFalse("worker remained alive", it.isAlive) }
        if (errors.isNotEmpty()) throw AssertionError("concurrent operation failed", errors.first())
        assertEquals(count, results.size)
        return results
    }

    private fun request(n: Int) = "00000000-0000-4000-8000-${n.toString().padStart(12, '0')}"
    private fun token(n: Int) = "10000000-0000-4000-8000-${n.toString().padStart(12, '0')}"

    private companion object {
        const val REQUEST = "11111111-1111-4111-8111-111111111111"
        const val TOKEN = "22222222-2222-4222-8222-222222222222"
        const val SECOND_TOKEN = "33333333-3333-4333-8333-333333333333"
        const val INSTALLATION = "44444444-4444-4444-8444-444444444444"
        const val THIRD_TOKEN = "55555555-5555-4555-8555-555555555555"
    }
}
