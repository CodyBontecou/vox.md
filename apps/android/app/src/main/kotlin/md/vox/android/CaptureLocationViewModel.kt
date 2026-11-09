package md.vox.android

import androidx.compose.runtime.mutableStateOf
import androidx.lifecycle.ViewModel

/** Permission requests and decisions survive rotation without saving full captures in a Bundle. */
internal class CaptureLocationViewModel : ViewModel() {
    val pendingSubmission = mutableStateOf<PendingLocationSubmission?>(null)
    val decision = mutableStateOf<PendingLocationDecision?>(null)
}
