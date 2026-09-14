package md.vox.android.data;

import androidx.room.Dao;
import androidx.room.Insert;
import androidx.room.OnConflictStrategy;
import androidx.room.Query;
import java.util.List;

@Dao
public interface CaptureActivityDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    long insert(CaptureActivityEntity activity);

    @Query("SELECT * FROM capture_activity ORDER BY completedAtEpochMillis")
    List<CaptureActivityEntity> all();

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    long insertRecording(RecordingActivityEntity activity);

    @Query("SELECT * FROM recording_activity ORDER BY completedAtEpochMillis")
    List<RecordingActivityEntity> allRecordings();

    @Insert(onConflict = OnConflictStrategy.IGNORE)
    long insertCompletion(CaptureCompletionEntity completion);

    @Query("SELECT * FROM capture_completion WHERE requestID = :requestID")
    CaptureCompletionEntity readCompletion(String requestID);

    @Query("SELECT * FROM capture_completion ORDER BY completedAtEpochMillis DESC, requestID")
    List<CaptureCompletionEntity> allCompletions();

    @Query("DELETE FROM capture_completion WHERE requestID = :requestID")
    int deleteCompletion(String requestID);
}
