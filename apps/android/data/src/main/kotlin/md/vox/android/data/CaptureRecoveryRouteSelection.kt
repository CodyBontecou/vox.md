package md.vox.android.data

import md.vox.android.capturedomain.*

internal sealed interface RecoveryRouteSelection {
    data class Ready(val preset: CapturePreset, val destination: CaptureDestination) : RecoveryRouteSelection
    data class Rejected(val reason: CaptureRecoveryRejection) : RecoveryRouteSelection
}

/** Evaluates the exact route revision and vault the confirmation names; never chooses a fallback route. */
internal fun selectRecoveryRoute(
    target: CaptureRecoveryTarget.Route,
    presets: List<CapturePreset>,
    defaultDestination: CaptureDestination?,
): RecoveryRouteSelection {
    val preset = presets.firstOrNull { it.id == target.presetID && it.revision == target.revision && it.isEnabled }
        ?: return RecoveryRouteSelection.Rejected(CaptureRecoveryRejection.ROUTE_CHANGED)
    if (preset.urlDelivery.enabled) return RecoveryRouteSelection.Rejected(CaptureRecoveryRejection.URL_ROUTE)
    val destination = (preset.destination ?: defaultDestination)?.takeIf { it.id == target.destinationID }
        ?: return RecoveryRouteSelection.Rejected(CaptureRecoveryRejection.DESTINATION_CHANGED)
    return RecoveryRouteSelection.Ready(preset, destination)
}
