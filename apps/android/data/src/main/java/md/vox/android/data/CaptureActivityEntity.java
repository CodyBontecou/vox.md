package md.vox.android.data;

import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;

/** Content-free lifetime activity record. No text, filename, or destination is stored. */
@Entity(tableName = "capture_activity")
public final class CaptureActivityEntity {
    @PrimaryKey @NonNull public String requestID;
    public long completedAtEpochMillis;
    @NonNull public String source;
    public int attachmentCount;

    public CaptureActivityEntity(
            @NonNull String requestID,
            long completedAtEpochMillis,
            @NonNull String source,
            int attachmentCount
    ) {
        this.requestID = requestID;
        this.completedAtEpochMillis = completedAtEpochMillis;
        this.source = source;
        this.attachmentCount = attachmentCount;
    }
}
