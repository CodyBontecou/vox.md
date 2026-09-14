package md.vox.android.data;

import android.content.Context;
import androidx.annotation.NonNull;
import androidx.room.Database;
import androidx.room.Room;
import androidx.room.RoomDatabase;
import androidx.room.migration.Migration;
import androidx.sqlite.db.SupportSQLiteDatabase;

@Database(entities = {CaptureProjectionEntity.class, CaptureLeaseEntity.class, LeaseClockEntity.class,
        InstallationIdentityEntity.class, QuotaReservationEntity.class, CaptureTombstoneEntity.class,
        CaptureActivityEntity.class, RecordingActivityEntity.class, CaptureCompletionEntity.class}, version = 5, exportSchema = true)
public abstract class CaptureDatabase extends RoomDatabase {
    public abstract CaptureProjectionDao captureProjectionDao();
    public abstract CaptureCoordinationDao captureCoordinationDao();
    public abstract CaptureActivityDao captureActivityDao();

    public static final Migration MIGRATION_1_2 = new Migration(1, 2) {
        @Override public void migrate(@NonNull SupportSQLiteDatabase db) {
            // Rebuild instead of ALTER ADD COLUMN: SQLite retains the forced
            // DEFAULT clause on ALTER-added NOT NULL columns, which diverges
            // from Room's expected v2 schema (no default) and fails runtime
            // TableInfo validation on migrated devices. A table rebuild makes
            // the migrated schema byte-equivalent to a fresh v2 create.
            db.execSQL("CREATE TABLE IF NOT EXISTS capture_projection_v2 (requestID TEXT NOT NULL, packageVersion INTEGER NOT NULL, journalVersion INTEGER NOT NULL, journalRevision INTEGER NOT NULL, state TEXT NOT NULL, createdAtEpochMillis INTEGER NOT NULL, updatedAtEpochMillis INTEGER NOT NULL, attemptCount INTEGER NOT NULL, PRIMARY KEY(requestID))");
            db.execSQL("INSERT INTO capture_projection_v2 (requestID, packageVersion, journalVersion, journalRevision, state, createdAtEpochMillis, updatedAtEpochMillis, attemptCount) SELECT requestID, packageVersion, journalVersion, journalRevision, state, createdAtEpochMillis, updatedAtEpochMillis, 0 FROM capture_projection");
            db.execSQL("DROP TABLE capture_projection");
            db.execSQL("ALTER TABLE capture_projection_v2 RENAME TO capture_projection");
            db.execSQL("CREATE TABLE IF NOT EXISTS capture_lease (requestID TEXT NOT NULL, token TEXT NOT NULL, expiresAtEpochMillis INTEGER NOT NULL, PRIMARY KEY(requestID))");
            db.execSQL("CREATE TABLE IF NOT EXISTS lease_clock (singletonID INTEGER NOT NULL, maxObservedEpochMillis INTEGER NOT NULL, PRIMARY KEY(singletonID))");
            db.execSQL("CREATE TABLE IF NOT EXISTS installation_identity (singletonID INTEGER NOT NULL, installationID TEXT NOT NULL, createdAtEpochMillis INTEGER NOT NULL, PRIMARY KEY(singletonID))");
            db.execSQL("CREATE TABLE IF NOT EXISTS quota_reservation (requestID TEXT NOT NULL, reservationToken TEXT NOT NULL, installationID TEXT NOT NULL, reservedAtEpochMillis INTEGER NOT NULL, updatedAtEpochMillis INTEGER NOT NULL, PRIMARY KEY(requestID))");
            db.execSQL("CREATE TABLE IF NOT EXISTS capture_tombstone (requestID TEXT NOT NULL, installationID TEXT NOT NULL, state TEXT NOT NULL, completedAtEpochMillis INTEGER NOT NULL, destinationID TEXT NOT NULL, receiptID TEXT NOT NULL, packageVersion INTEGER NOT NULL, journalVersion INTEGER NOT NULL, requestContractVersion INTEGER NOT NULL, finalJournalRevision INTEGER NOT NULL, coreVersion TEXT NOT NULL, rendererVersion TEXT NOT NULL, profileID TEXT NOT NULL, profileVersion INTEGER NOT NULL, quotaUnits INTEGER NOT NULL, PRIMARY KEY(requestID))");
        }
    };

    public static final Migration MIGRATION_2_3 = new Migration(2, 3) {
        @Override public void migrate(@NonNull SupportSQLiteDatabase db) {
            db.execSQL("CREATE TABLE IF NOT EXISTS capture_activity (requestID TEXT NOT NULL, completedAtEpochMillis INTEGER NOT NULL, source TEXT NOT NULL, attachmentCount INTEGER NOT NULL, PRIMARY KEY(requestID))");
            db.execSQL("CREATE TABLE IF NOT EXISTS recording_activity (sessionID TEXT NOT NULL, completedAtEpochMillis INTEGER NOT NULL, durationMillis INTEGER NOT NULL, PRIMARY KEY(sessionID))");
        }
    };

    public static final Migration MIGRATION_3_4 = new Migration(3, 4) {
        @Override public void migrate(@NonNull SupportSQLiteDatabase db) {
            // A paid capture still needs a reservation/tombstone, but consumes zero
            // free quota units. Rebuild to keep the migrated schema identical to a
            // fresh Room schema (ALTER would retain a DEFAULT clause).
            db.execSQL("CREATE TABLE IF NOT EXISTS quota_reservation_v4 (requestID TEXT NOT NULL, reservationToken TEXT NOT NULL, installationID TEXT NOT NULL, reservedAtEpochMillis INTEGER NOT NULL, updatedAtEpochMillis INTEGER NOT NULL, quotaUnits INTEGER NOT NULL, PRIMARY KEY(requestID))");
            db.execSQL("INSERT INTO quota_reservation_v4 (requestID, reservationToken, installationID, reservedAtEpochMillis, updatedAtEpochMillis, quotaUnits) SELECT requestID, reservationToken, installationID, reservedAtEpochMillis, updatedAtEpochMillis, 1 FROM quota_reservation");
            db.execSQL("DROP TABLE quota_reservation");
            db.execSQL("ALTER TABLE quota_reservation_v4 RENAME TO quota_reservation");
        }
    };

    public static final Migration MIGRATION_4_5 = new Migration(4, 5) {
        @Override public void migrate(@NonNull SupportSQLiteDatabase db) {
            db.execSQL("CREATE TABLE IF NOT EXISTS capture_completion (requestID TEXT NOT NULL, completedAtEpochMillis INTEGER NOT NULL, PRIMARY KEY(requestID))");
        }
    };

    public static CaptureDatabase create(Context context) {
        return Room.databaseBuilder(context.getApplicationContext(), CaptureDatabase.class, "capture-index-v1.db")
                .addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5).build();
    }
}
