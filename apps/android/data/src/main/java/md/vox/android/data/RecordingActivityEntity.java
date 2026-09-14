package md.vox.android.data;

import androidx.annotation.NonNull;
import androidx.room.Entity;
import androidx.room.PrimaryKey;

/** Content-free lifetime recording activity. Audio paths and transcript text are excluded. */
@Entity(tableName = "recording_activity")
public final class RecordingActivityEntity {
    @PrimaryKey @NonNull public String sessionID;
    public long completedAtEpochMillis;
    public long durationMillis;

    public RecordingActivityEntity(@NonNull String sessionID, long completedAtEpochMillis, long durationMillis) {
        this.sessionID = sessionID;
        this.completedAtEpochMillis = completedAtEpochMillis;
        this.durationMillis = durationMillis;
    }
}
