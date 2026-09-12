import Foundation

/// Identity only: widget entries never retain a workflow, route or selection preference.
public struct CapturePresetWidgetIdentity: Identifiable, Equatable, Hashable, Sendable {
    public let id: String
    /// Visible title. Empty means the preset is intentionally icon-only.
    public let name: String
    public let accessibilityName: String
    public let symbolName: String
    public let emoji: String?
    public let isEnabled: Bool

    public init(profile: CapturePresetProfile) {
        id = profile.id
        name = profile.visibleName ?? ""
        accessibilityName = profile.accessibilityName
        symbolName = profile.symbolName
        emoji = profile.emoji
        isEnabled = profile.isEnabled
    }
}

public enum CapturePresetWidgetSelection: Equatable, Sendable {
    case followCaptureBar
    /// Explicit positions. Interior empty slots and repeated targets are intentional.
    case custom(slots: [String?])
}

public enum CapturePresetWidgetAvailability: Equatable, Sendable {
    case available, disabled, missing, unconfigured, storageUnavailable
}

public struct CapturePresetWidgetTile: Identifiable, Equatable, Sendable {
    /// Follow uses the preset ID; custom uses its fixed slot, even when empty/stale.
    public let id: String
    public let presetID: String?
    public let identity: CapturePresetWidgetIdentity?
    public let availability: CapturePresetWidgetAvailability

    /// Even a stale/unavailable tile retains its exact expected ID. The existing
    /// app launch handler revalidates availability and asks before rerouting a draft.
    public var captureURL: URL? {
        guard let presetID, !presetID.isEmpty, presetID.count <= 160,
              presetID == presetID.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        // The existing parser trims edge whitespace. Refuse a non-roundtrippable
        // identifier instead of letting it alias a different preset at launch.
        var components = URLComponents()
        components.scheme = "voxboard"
        components.host = "capture"
        components.queryItems = [
            URLQueryItem(name: "preset", value: presetID),
            URLQueryItem(name: "source", value: "widget"),
        ]
        return components.url
    }
}

public enum CapturePresetWidgetEmptyState: Equatable, Sendable {
    case needsCaptureBarSetup, emptyCaptureBar, unavailableCaptureBar
}

public struct CapturePresetWidgetSnapshot: Equatable, Sendable {
    public let selection: CapturePresetWidgetSelection
    public let tiles: [CapturePresetWidgetTile]
    public let emptyState: CapturePresetWidgetEmptyState?

    public init(
        selection: CapturePresetWidgetSelection,
        pins: CapturePresetQuickAccessState,
        profiles: [CapturePresetProfile]?
    ) {
        self.selection = selection
        let identities = CapturePresetWidgetCatalog.identities(profiles: profiles ?? [])
        switch selection {
        case .followCaptureBar:
            // Follow is the bar's enabled-only ordered resolution, not a seed operation.
            let resolved = CapturePresetQuickAccessResolver.resolve(
                orderedIDs: pins.orderedIDs, profiles: profiles ?? []
            )
            tiles = resolved.map { profile in
                CapturePresetWidgetTile(
                    id: "preset:\(profile.id)", presetID: profile.id,
                    identity: CapturePresetWidgetIdentity(profile: profile), availability: .available
                )
            }
            if !tiles.isEmpty {
                emptyState = nil
            } else if profiles == nil || pins == .unavailable || pins == .malformed {
                emptyState = .unavailableCaptureBar
            } else if pins == .absent {
                emptyState = .needsCaptureBarSetup
            } else {
                emptyState = .emptyCaptureBar
            }
        case .custom(let slots):
            // Omit unused trailing slots only. Never compact interior holes or
            // duplicates, which would silently move another preset into a position.
            let count = max(1, (slots.lastIndex(where: { $0 != nil }).map { $0 + 1 }) ?? 0)
            tiles = (0..<count).map { index in
                let presetID = index < slots.count ? slots[index] : nil
                let identity = identities.first { $0.id == presetID }
                let availability: CapturePresetWidgetAvailability
                if presetID == nil { availability = .unconfigured }
                else if profiles == nil { availability = .storageUnavailable }
                else if let identity { availability = identity.isEnabled ? .available : .disabled }
                else { availability = .missing }
                return CapturePresetWidgetTile(
                    id: "slot:\(index)", presetID: presetID, identity: identity, availability: availability
                )
            }
            emptyState = nil
        }
    }

    /// Read-only App Group snapshot. In particular, absent pins never seed here.
    public static func load(selection: CapturePresetWidgetSelection, defaults: UserDefaults?) -> Self {
        Self(
            selection: selection,
            pins: CapturePresetQuickAccessStore.load(defaults: defaults),
            profiles: CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults)
        )
    }
}

public enum CapturePresetWidgetCatalog {
    /// First record wins, including availability, matching quick-access resolution.
    public static func identities(profiles: [CapturePresetProfile]) -> [CapturePresetWidgetIdentity] {
        var seen = Set<String>()
        return profiles.filter { seen.insert($0.id).inserted }.map(CapturePresetWidgetIdentity.init)
    }

    /// Missing results deliberately keep their requested ID and a nil identity.
    /// AppEntity queries can preserve a stale configuration rather than replacing it.
    public static func requested(
        identifiers: [String], identities: [CapturePresetWidgetIdentity]
    ) -> [(id: String, identity: CapturePresetWidgetIdentity?)] {
        CapturePresetQuickAccessResolver.normalizedIDs(identifiers).map { id in
            (id, identities.first { $0.id == id })
        }
    }
}
