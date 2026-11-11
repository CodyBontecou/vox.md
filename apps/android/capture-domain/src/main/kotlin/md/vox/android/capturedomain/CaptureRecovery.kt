package md.vox.android.capturedomain

/** A confirmation is bound to exactly the local request and journal frontier the person reviewed. */
data class CaptureRecoveryContext(
    val requestID: String,
    val requestSHA256: String,
    val revision: Int,
    val sourceDestinationID: String?,
    val canReplace: Boolean,
    val sourceDestinationName: String? = null,
    val missingHeading: CaptureMissingHeading? = null,
    val replacementRequestID: String? = null,
)

data class CaptureMissingHeading(val title: String, val level: Int)

sealed interface CaptureRecoveryTarget {
    /** Explicit built-in Inbox in the currently selected vault; never inferred from an edited route. */
    data class Inbox(val destinationID: String) : CaptureRecoveryTarget
    data class Route(val presetID: String, val revision: Int, val destinationID: String) : CaptureRecoveryTarget
    /** Replace only this capture's frozen heading selector; the saved route remains unchanged. */
    data class Heading(val title: String, val level: Int, val createIfMissing: Boolean) : CaptureRecoveryTarget
}

data class CaptureRecoveryCommand(
    val intentID: String,
    val context: CaptureRecoveryContext,
    val target: CaptureRecoveryTarget,
)

sealed interface CaptureRecoveryResult {
    data class Accepted(val replacementRequestID: String, val delivery: CaptureSubmitResult?) : CaptureRecoveryResult
    /** A durable intent may exist. Retrying the same intent is safe; choosing another target is not. */
    data class Waiting(val replacementRequestID: String?) : CaptureRecoveryResult
    data class Rejected(val reason: CaptureRecoveryRejection) : CaptureRecoveryResult
}

/** Typed native rejection; presentation owns localization of these content-free causes. */
enum class CaptureRecoveryRejection {
    UNAVAILABLE, CONFLICT, ACCESS_ENDED, SOURCE_CHANGED, ROUTE_CHANGED, URL_ROUTE,
    UNVERIFIED_HEADING, DESTINATION_CHANGED, VAULT_PERMISSION, INVALID_CHOICE, UNSAFE,
}
