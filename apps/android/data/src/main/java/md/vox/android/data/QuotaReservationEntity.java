package md.vox.android.data;
import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;
@Entity(tableName = "quota_reservation")
public final class QuotaReservationEntity {
 @PrimaryKey @NonNull public String requestID; @NonNull public String reservationToken; @NonNull public String installationID; public long reservedAtEpochMillis; public long updatedAtEpochMillis; public int quotaUnits;
 public QuotaReservationEntity(@NonNull String requestID, @NonNull String reservationToken, @NonNull String installationID, long reservedAtEpochMillis, long updatedAtEpochMillis, int quotaUnits) { this.requestID=requestID; this.reservationToken=reservationToken; this.installationID=installationID; this.reservedAtEpochMillis=reservedAtEpochMillis; this.updatedAtEpochMillis=updatedAtEpochMillis; this.quotaUnits=quotaUnits; }
}
