import Foundation

/// System surfaces a route (Capture Preset) can be pinned to from the Routes
/// list's long-press menu. Capture Bar pins remain owned by
/// `CapturePresetQuickAccessStore`; these are independent per-surface lists.
public enum CapturePresetPinSurface: String, Codable, CaseIterable, Sendable, Identifiable {
    case widgets
    case controlCenter
    case keyboard
    case watch

    public var id: String { rawValue }
}

/// App Group record of which routes are pinned to widgets, Control Center,
/// the keyboard and Apple Watch, plus the route the Action button / Control
/// Center control launches.
///
/// Readers (widget, keyboard, watch bridge, controls) should use
/// `effectivePinnedIDs(for:allIDs:defaults:)`: a surface the user has never
/// configured keeps the pre-pinning behavior of offering every route.
public enum CapturePresetSurfacePinStore {
    /// JSON object `{ "<surface>": ["<preset id>", …] }` in the App Group defaults.
    public static let defaultsKey = "vox.capturePresetSurfacePins.v1"
    /// Preset ID launched by the Action button and the Control Center control.
    public static let actionButtonRouteKey = "vox.actionButtonRouteID.v1"

    public static func load(defaults: UserDefaults?) -> [CapturePresetPinSurface: [String]] {
        guard let data = defaults?.data(forKey: defaultsKey),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        var result: [CapturePresetPinSurface: [String]] = [:]
        for (key, ids) in raw {
            guard let surface = CapturePresetPinSurface(rawValue: key) else { continue }
            var seen = Set<String>()
            result[surface] = ids.filter { seen.insert($0).inserted }
        }
        return result
    }

    /// True once the user has pinned or unpinned anything for `surface`.
    public static func isConfigured(_ surface: CapturePresetPinSurface, defaults: UserDefaults?) -> Bool {
        load(defaults: defaults)[surface] != nil
    }

    /// Explicitly pinned IDs, in pin order. Empty for an unconfigured surface.
    public static func pinnedIDs(for surface: CapturePresetPinSurface, defaults: UserDefaults?) -> [String] {
        load(defaults: defaults)[surface] ?? []
    }

    /// IDs a surface should offer: its pins (filtered to `allIDs`) once
    /// configured, otherwise every route in `allIDs`.
    public static func effectivePinnedIDs(
        for surface: CapturePresetPinSurface,
        allIDs: [String],
        defaults: UserDefaults?
    ) -> [String] {
        guard let pinned = load(defaults: defaults)[surface] else { return allIDs }
        let available = Set(allIDs)
        return pinned.filter { available.contains($0) }
    }

    public static func isPinned(id: String, to surface: CapturePresetPinSurface, defaults: UserDefaults?) -> Bool {
        pinnedIDs(for: surface, defaults: defaults).contains(id)
    }

    public static func surfaces(for id: String, defaults: UserDefaults?) -> [CapturePresetPinSurface] {
        let all = load(defaults: defaults)
        return CapturePresetPinSurface.allCases.filter { all[$0]?.contains(id) == true }
    }

    public static func setPinned(
        _ pinned: Bool,
        id: String,
        to surface: CapturePresetPinSurface,
        defaults: UserDefaults?
    ) {
        var all = load(defaults: defaults)
        var ids = all[surface] ?? []
        ids.removeAll { $0 == id }
        if pinned { ids.append(id) }
        all[surface] = ids
        save(all, defaults: defaults)
    }

    /// Drops a deleted route from every surface and the Action button.
    public static func remove(id: String, defaults: UserDefaults?) {
        var all = load(defaults: defaults)
        for surface in all.keys { all[surface]?.removeAll { $0 == id } }
        save(all, defaults: defaults)
        if actionButtonRouteID(defaults: defaults) == id {
            defaults?.removeObject(forKey: actionButtonRouteKey)
        }
    }

    /// Written by the keyboard extension each time it appears.
    public static let keyboardFullAccessKey = "vox.keyboard.hasFullAccess.v1"

    public static func recordKeyboardFullAccess(_ hasFullAccess: Bool, defaults: UserDefaults?) {
        defaults?.set(hasFullAccess, forKey: keyboardFullAccessKey)
    }

    /// Nil until the keyboard has been opened with the App Group reachable.
    public static func keyboardHasFullAccess(defaults: UserDefaults?) -> Bool? {
        defaults?.object(forKey: keyboardFullAccessKey) as? Bool
    }

    public static func actionButtonRouteID(defaults: UserDefaults?) -> String? {
        let value = defaults?.string(forKey: actionButtonRouteKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    public static func setActionButtonRouteID(_ id: String?, defaults: UserDefaults?) {
        if let id, !id.isEmpty {
            defaults?.set(id, forKey: actionButtonRouteKey)
        } else {
            defaults?.removeObject(forKey: actionButtonRouteKey)
        }
    }

    private static func save(_ all: [CapturePresetPinSurface: [String]], defaults: UserDefaults?) {
        let raw = Dictionary(uniqueKeysWithValues: all.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        defaults?.set(data, forKey: defaultsKey)
    }
}
