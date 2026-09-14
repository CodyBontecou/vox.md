package md.vox.android.data;

import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;

/** Payload-free inbox completion marker. Keep this schema to request ID and timestamp only. */
@Entity(tableName = "capture_completion")
public final class CaptureCompletionEntity {
    @PrimaryKey @NonNull public String requestID;
    public long completedAtEpochMillis;

    public CaptureCompletionEntity(@NonNull String requestID, long completedAtEpochMillis) {
        this.requestID = requestID;
        this.completedAtEpochMillis = completedAtEpochMillis;
    }
}
