package md.vox.android.capturedomain

/** Native vault and invocation facts stay outside the shared renderer's JSON. */
data class CaptureRouteOverride(
    val relativeNotePath: String? = null,
    val placement: CapturePlacementKind? = null,
) {
    fun validated(): CaptureRouteOverride {
        relativeNotePath?.let { path ->
            require(path.length in 1..512 && path.endsWith(".md", ignoreCase = true)) { "invalidNotePath" }
            require(path.split('/').all { it.isNotBlank() && it !in setOf(".", "..") && it.none { c -> c == '\\' || c.isISOControl() } }) { "invalidNotePath" }
        }
        require(placement == null || placement in setOf(CapturePlacementKind.APPEND, CapturePlacementKind.PREPEND)) { "invalidPlacementOverride" }
        return this
    }

    fun applyTo(preset: CapturePreset): CapturePreset {
        validated()
        return preset.copy(
            noteTargetKind = if (relativeNotePath != null) CaptureNoteTargetKind.EXISTING_NOTE else preset.noteTargetKind,
            existingNotePath = relativeNotePath ?: preset.existingNotePath,
            placement = placement ?: preset.placement,
        )
    }
}

/** Credentials and full endpoints live in the Android Keystore-backed store, never snapshots. */
data class CaptureURLDeliverySettings(
    val enabled: Boolean = false,
    val credentialID: String? = null,
    val origin: String = "",
    val maxAttempts: Int = 5,
)

fun normalizedTranscriptProperty(name: String): String? = name.trim().takeIf {
    it.length in 1..128 && it.all { c -> c.isLetterOrDigit() || c == '_' || c == '-' }
}
