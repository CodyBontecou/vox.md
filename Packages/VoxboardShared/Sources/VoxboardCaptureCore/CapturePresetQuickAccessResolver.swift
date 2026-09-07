import Foundation

/// Resolves stable IDs against a current profile snapshot, never a selected or
/// default preset. Resolution does not mutate profiles or saved pin order.
public enum CapturePresetQuickAccessResolver {
    /// Stable-first deduplication. IDs are opaque: do not trim, case-fold, or
    /// otherwise turn an unknown ID into a different, valid preset's ID.
    public static func normalizedIDs(_ orderedIDs: [String]) -> [String] {
        var seen = Set<String>()
        return orderedIDs.filter { seen.insert($0).inserted }
    }

    /// Only existing, enabled profiles are returned, in the requested order.
    /// Disabled IDs remain in storage so re-enabling restores their position.
    /// If an invalid snapshot repeats a profile ID, its first record wins,
    /// including its enabled state; a later duplicate cannot enable it.
    public static func resolve(
        orderedIDs: [String],
        profiles: [CapturePresetProfile]
    ) -> [CapturePresetProfile] {
        var profilesByID: [String: CapturePresetProfile] = [:]
        for profile in profiles where profilesByID[profile.id] == nil {
            profilesByID[profile.id] = profile
        }
        return normalizedIDs(orderedIDs).compactMap { id in
            guard let profile = profilesByID[id], profile.isEnabled else { return nil }
            return profile
        }
    }

    /// Read-only App Group path for lightweight clients such as widgets.
    /// Missing/unreadable preferences or profiles resolve empty, not to a
    /// synthetic default. This never seeds, repairs, or prunes preferences.
    /// The host must validate a tile's exact ID again at invocation time.
    public static func resolve(defaults: UserDefaults?) -> [CapturePresetProfile] {
        resolve(
            orderedIDs: CapturePresetQuickAccessStore.load(defaults: defaults).orderedIDs,
            profiles: CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults) ?? []
        )
    }
}
