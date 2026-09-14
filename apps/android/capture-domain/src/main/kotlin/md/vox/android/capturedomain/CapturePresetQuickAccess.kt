package md.vox.android.capturedomain

/**
 * Resolves the pinned quick-access rail shown beside the capture editor.
 *
 * Membership comes from each preset's own [CapturePreset.isPinned] flag, so the
 * editor toggle, the Presets settings list, and this rail can never disagree.
 * Disabled pins are hidden, never lost: re-enabling a preset restores its rail
 * eligibility with no migration. The rail intentionally excludes the active
 * preset because the selector row beneath the editor already represents it.
 */
object CapturePresetQuickAccess {
    /** Enabled pinned presets excluding the one the selector already shows, in settings list order. */
    fun alternatePresets(collection: CapturePresetCollection): List<CapturePreset> =
        collection.presets
            .filter { it.isPinned && it.isEnabled && it.id != collection.activePreset.id }
            .sortedBy { it.name.trim().lowercase() }

    /**
     * Guard for a rail tap. Presentation-only snapshots can go stale while a
     * selection round-trips through the repository, so the resolved collection
     * is revalidated here before [selectCapturePreset] is invoked.
     */
    fun canActivatePreset(collection: CapturePresetCollection, presetID: String, routeLocked: Boolean): Boolean =
        !routeLocked &&
            presetID != collection.activePreset.id &&
            collection.presets.any { it.id == presetID && it.isEnabled }
}
