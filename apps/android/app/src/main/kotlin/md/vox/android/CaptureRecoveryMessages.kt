package md.vox.android

import md.vox.android.capturedomain.CaptureRecoveryRejection

internal fun recoveryRejectionNotice(reason: CaptureRecoveryRejection): VoxUiText = when (reason) {
    CaptureRecoveryRejection.UNAVAILABLE -> voxUiText("Recovery is unavailable. Refresh and try again.")
    CaptureRecoveryRejection.CONFLICT -> voxUiText("This capture already has another recovery decision. Refresh Library.")
    CaptureRecoveryRejection.ACCESS_ENDED -> voxUiText("New captures and edits need Vox.md.")
    CaptureRecoveryRejection.SOURCE_CHANGED -> voxUiText("This capture changed. Refresh and review it again.")
    CaptureRecoveryRejection.ROUTE_CHANGED -> voxUiText("This route changed or is unavailable. Choose it again.")
    CaptureRecoveryRejection.URL_ROUTE -> voxUiText("Choose a route without URL delivery for this recovery.")
    CaptureRecoveryRejection.UNVERIFIED_HEADING -> voxUiText("A missing heading has not been verified for this capture.")
    CaptureRecoveryRejection.DESTINATION_CHANGED -> voxUiText("The vault changed or is unavailable. Review the destination again.")
    CaptureRecoveryRejection.VAULT_PERMISSION -> voxUiText("Choose the vault folder again before sending this capture.")
    CaptureRecoveryRejection.INVALID_CHOICE -> voxUiText("The recovery choice is invalid. Review it and try again.")
    CaptureRecoveryRejection.UNSAFE -> voxUiText("This capture changed or cannot be replaced safely. Refresh and review it again.")
}
