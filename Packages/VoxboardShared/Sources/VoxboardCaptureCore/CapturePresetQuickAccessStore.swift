import Foundation

/// Absence is eligible for one-time seeding; a stored empty array is not.
/// Malformed values fail closed and are preserved until a deliberate write.
public enum CapturePresetQuickAccessState: Equatable, Sendable {
    case unavailable
    case absent
    case malformed
    case stored([String])

    /// Unavailable, absent, and malformed states expose no launchable IDs.
    public var orderedIDs: [String] {
        guard case .stored(let ids) = self else { return [] }
        return ids
    }
}

/// Independent App Group ordered IDs, not workflow copies or selection state.
/// Lightweight clients should use `load` / the resolver only; the foreground
/// host owns seeding and deliberate writes. Writers are serialized in-process;
/// UserDefaults does not provide cross-process compare-and-swap or disk-flush
/// guarantees. Hosts must reload after external edits rather than reuse stale
/// in-memory order for a read-modify-write operation.
public enum CapturePresetQuickAccessStore {
    /// A property-list string array. Do not register a default for this key:
    /// doing so would hide the difference between absent and explicitly empty.
    public static let storageKey = "capture.presets.quickAccess.orderedIDs.v1"
    public static let initialSeedLimit = 5

    private static let writeLock = NSLock()

    /// Pure read: normalizes duplicate IDs in memory, but never writes back.
    /// Wrong outer types or even one non-string element make the whole value
    /// malformed. Do not salvage a partial list or treat corruption as absence.
    public static func load(defaults: UserDefaults?) -> CapturePresetQuickAccessState {
        guard let defaults else { return .unavailable }
        guard let value = defaults.object(forKey: storageKey) else { return .absent }
        guard let ids = value as? [String] else { return .malformed }
        return .stored(CapturePresetQuickAccessResolver.normalizedIDs(ids))
    }

    /// Reads the full persisted profile set without migrations or defaults.
    /// Unlike `CapturePresetProfileStore.loadProfiles`, nil distinguishes a
    /// missing/unreadable store from a successfully decoded, authoritative [].
    /// Never substitute `enabledProfiles` here: disabled IDs must survive edits.
    public static func loadAuthoritativeProfiles(
        defaults: UserDefaults?
    ) -> [CapturePresetProfile]? {
        guard let data = defaults?.data(forKey: CapturePresetProfileStore.profilesKey) else {
            return nil
        }
        return try? JSONDecoder().decode([CapturePresetProfile].self, from: data)
    }

    /// Seeds once from the first five unique enabled profiles in authoritative
    /// order. Supply the FULL current set, including disabled profiles and
    /// excluding deleted/retired profiles. nil means unavailable, not empty.
    ///
    /// Missing/unreadable profiles or defaults defer initialization. An actual
    /// authoritative empty/all-disabled set persists [], which is never later
    /// reseeded, even when profiles are added or enabled. Existing stored or
    /// malformed preferences are untouched. Reads alone never invoke this.
    @discardableResult
    public static func seedIfNeeded(
        authoritativeProfiles: [CapturePresetProfile]?,
        defaults: UserDefaults?
    ) -> CapturePresetQuickAccessState {
        writeLock.lock()
        defer { writeLock.unlock() }

        let state = load(defaults: defaults)
        guard state == .absent, let defaults, let authoritativeProfiles else { return state }
        let enabled = CapturePresetQuickAccessResolver.resolve(
            orderedIDs: authoritativeProfiles.map(\.id),
            profiles: authoritativeProfiles
        )
        defaults.set(Array(enabled.prefix(initialSeedLimit).map(\.id)), forKey: storageKey)
        return load(defaults: defaults)
    }

    /// Deliberate replacement, with no five-item cap. Stable-first duplicates
    /// are removed and IDs absent from the FULL authoritative set are pruned.
    /// Disabled existing IDs are retained. Pass nil if the full set could not
    /// be read; never pass an enabled-only subset or synthetic fallback set.
    ///
    /// Explicit [] persists as []; an explicit write may repair malformed
    /// storage. With unavailable defaults/profiles nothing is written. The
    /// result confirms local readback only, not cross-process propagation.
    @discardableResult
    public static func save(
        orderedIDs: [String],
        authoritativeProfiles: [CapturePresetProfile]?,
        defaults: UserDefaults?
    ) -> Bool {
        writeLock.lock()
        defer { writeLock.unlock() }

        guard let defaults, let authoritativeProfiles else { return false }
        let existingIDs = Set(authoritativeProfiles.map(\.id))
        let ids = CapturePresetQuickAccessResolver.normalizedIDs(orderedIDs)
            .filter { existingIDs.contains($0) }
        defaults.set(ids, forKey: storageKey)
        return load(defaults: defaults) == .stored(ids)
    }
}
