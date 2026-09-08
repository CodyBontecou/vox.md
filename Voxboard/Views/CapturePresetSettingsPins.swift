import Observation
import SwiftUI
import VoxboardShared

/// Settings-only edit seam. Membership and move offsets always refer to stored
/// IDs, including disabled/missing pins, never to the enabled launch row.
@MainActor
@Observable
final class CapturePresetSettingsPins {
    let preferences: CapturePresetQuickAccessPreferences
    private let defaults: UserDefaults?
    private(set) var profiles: [CapturePresetProfile]?
    private(set) var errorMessage: String?

    nonisolated deinit {}

    init(defaults: UserDefaults? = AppConstants.sharedDefaults) {
        self.defaults = defaults
        let profiles = CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults)
        self.profiles = profiles
        self.preferences = CapturePresetQuickAccessPreferences(defaults: defaults, authoritativeProfiles: profiles)
    }

    var orderedIDs: [String] { preferences.orderedIDs }

    func profile(id: String) -> CapturePresetProfile? {
        profiles?.first { $0.id == id }
    }

    func reload() {
        profiles = CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults)
        preferences.reload(authoritativeProfiles: profiles)
        errorMessage = nil
    }

    @discardableResult
    func setPinned(_ pinned: Bool, id: String) -> Bool {
        // Read-modify-write from fresh storage, not a stale settings snapshot.
        reload()
        if pinned, profile(id: id) == nil {
            errorMessage = String(localized: "This preset is unavailable. Reload before pinning it to the Capture Bar.")
            return false
        }
        var ids = orderedIDs.filter { $0 != id }
        if pinned {
            // Re-pinning an already pinned preset must not move it to the end.
            ids = preferences.isPinned(id: id) ? orderedIDs : orderedIDs + [id]
        }
        return write(ids)
    }

    @discardableResult
    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) -> Bool {
        let displayedIDs = orderedIDs
        reload()
        guard displayedIDs == orderedIDs,
              !offsets.isEmpty,
              offsets.allSatisfy({ displayedIDs.indices.contains($0) }),
              (0...displayedIDs.count).contains(destination) else {
            errorMessage = String(localized: "The Capture Bar order changed. Review the reloaded order and try again.")
            return false
        }
        var ids = displayedIDs
        ids.move(fromOffsets: offsets, toOffset: destination)
        return write(ids)
    }

    /// Only the successful persisted deletion can authorize pruning. loadFlows
    /// may synthesize defaults; that fallback is never passed as authoritative.
    @discardableResult
    func pruneAfterPersistedDeletion(id: String) -> Bool {
        reload()
        guard let profiles, !profiles.contains(where: { $0.id == id }) else {
            errorMessage = String(localized: "The preset deletion could not be confirmed. Its Capture Bar pin was kept.")
            return false
        }
        return write(orderedIDs)
    }

    var storageMessage: String? {
        if profiles == nil || preferences.state == .unavailable {
            return String(localized: "Capture Bar storage is unavailable. Reload after your presets are available.")
        }
        if preferences.state == .malformed {
            return String(localized: "The saved Capture Bar order could not be read. Pin a preset to replace it.")
        }
        return nil
    }

    private func write(_ ids: [String]) -> Bool {
        // FULL strict-read profiles include disabled records. The wrapper owns
        // refusal/readback and any central successful-save refresh hooks.
        let saved = preferences.setOrderedIDs(ids, authoritativeProfiles: profiles)
        errorMessage = saved ? nil : String(localized: "The Capture Bar change could not be confirmed. Reload and try again.")
        return saved
    }
}
