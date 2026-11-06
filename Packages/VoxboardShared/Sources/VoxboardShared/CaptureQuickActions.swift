import Foundation

// MARK: - Catalog

/// Every quick action that can sit in a Capture quick-action row (iPhone
/// toolbar above the keyboard, iPad, Mac workspace and the Vox keyboard).
///
/// Raw values are persisted (App Group defaults and the legacy Capture Bar
/// configuration) — never rename a case's raw value. Append new cases at the
/// end so fresh-install ordering stays stable.
///
/// The iOS/macOS apps use this type as `CaptureToolbarAction` (a typealias in
/// "Voxboard App Shared/CaptureToolbarPreferences.swift"), which adds
/// localized titles and SF Symbols. Extensions without the app sources (the
/// keyboard) can use `glyph`, `defaultLabel` and `group` directly.
public enum CaptureQuickAction: String, CaseIterable, Identifiable, Codable, Sendable {
    case addMedia
    case addFiles
    case scanDocument
    case extractText
    case undo
    case formatMarkdown
    case markdownLink
    case dueDate
    case checklist
    case bulletList
    case paste
    case internalLink
    case sketch
    case currentLocation
    case timestamp
    case date
    case textCase
    // Signal redesign: separate Markdown chips.
    case heading
    case bold
    case italic
    case tag

    public var id: String { rawValue }

    /// Monospaced text glyph from the Signal design ("- [ ]", "[[ ]]", "#" …).
    /// `timestamp`/`date` return sample values; live surfaces may render the
    /// current time/date instead.
    public var glyph: String {
        switch self {
        case .checklist: "- [ ]"
        case .bulletList: "•"
        case .heading: "H"
        case .bold: "B"
        case .italic: "I"
        case .markdownLink: "[ ]( )"
        case .internalLink: "[[ ]]"
        case .tag: "#"
        case .formatMarkdown: "¶"
        case .timestamp: "10:42"
        case .date: "11-01"
        case .dueDate: "due"
        case .currentLocation: "◎"
        case .textCase: "Aa"
        case .paste: "⌘V"
        case .undo: "↺"
        case .addMedia: "+"
        case .addFiles: "File"
        case .scanDocument: "Scan"
        case .extractText: "OCR"
        case .sketch: "Draw"
        }
    }

    /// Short English label from the design ("Task", "Link note" …). The apps
    /// show localized titles instead; use this where no localization exists.
    public var defaultLabel: String {
        switch self {
        case .checklist: "Task"
        case .bulletList: "Bullet"
        case .heading: "Heading"
        case .bold: "Bold"
        case .italic: "Italic"
        case .markdownLink: "Web link"
        case .internalLink: "Link note"
        case .tag: "Tag"
        case .formatMarkdown: "Format"
        case .timestamp: "Time"
        case .date: "Date"
        case .dueDate: "Due date"
        case .currentLocation: "Location"
        case .textCase: "Text case"
        case .paste: "Paste"
        case .undo: "Undo"
        case .addMedia: "Media"
        case .addFiles: "Files"
        case .scanDocument: "Scan"
        case .extractText: "Extract text"
        case .sketch: "Sketch"
        }
    }

    public var group: CaptureQuickActionGroup {
        switch self {
        case .checklist, .bulletList, .heading, .bold, .italic, .markdownLink, .internalLink, .tag, .formatMarkdown:
            .markdown
        case .timestamp, .date, .dueDate, .currentLocation:
            .insert
        case .textCase, .paste, .undo:
            .edit
        case .addMedia, .addFiles, .scanDocument, .extractText, .sketch:
            .media
        }
    }

    /// Media/attachment actions are kept separate from the text quick actions
    /// (the design puts them behind the composer's Attach control).
    public var isMedia: Bool { group == .media }

    /// Actions introduced after the original Capture Bar. Existing saved bars
    /// get them hidden (they were already reachable via Format Markdown).
    public static let introducedInSignalRedesign: Set<CaptureQuickAction> = [.heading, .bold, .italic, .tag]

    /// The Mac Capture workspace's own row (Signal MacWorkspace design), used
    /// when the person has neither customized the default row nor pinned
    /// actions for the route. Other surfaces keep `CaptureQuickActionPins.builtInDefault`.
    public static let macWorkspaceDefault: [CaptureQuickAction] = [
        .timestamp, .checklist, .internalLink, .heading, .bulletList,
        .tag, .bold, .italic, .currentLocation, .textCase,
    ]
}

/// Sections of the "•••" all-actions panel, in display order.
public enum CaptureQuickActionGroup: String, CaseIterable, Identifiable, Sendable {
    case markdown
    case insert
    case edit
    case media

    public var id: String { rawValue }

    /// Uppercase mono section label ("MARKDOWN", "INSERT", "EDIT", "ATTACH").
    public var defaultLabel: String {
        switch self {
        case .markdown: "MARKDOWN"
        case .insert: "INSERT"
        case .edit: "EDIT"
        case .media: "ATTACH"
        }
    }

    /// Actions in this group, in design order.
    public var actions: [CaptureQuickAction] {
        switch self {
        case .markdown: [.checklist, .bulletList, .heading, .bold, .italic, .markdownLink, .internalLink, .tag, .formatMarkdown]
        case .insert: [.timestamp, .date, .dueDate, .currentLocation]
        case .edit: [.textCase, .paste, .undo]
        case .media: [.addMedia, .addFiles, .scanDocument, .extractText, .sketch]
        }
    }
}

// MARK: - Per-route pins (App Group)

/// Per-route quick-action pins shared through the App Group so the iPhone
/// app, iPad, Mac app and the keyboard extension agree.
///
/// Storage (in `AppConstants.sharedDefaults`):
/// - `routePinsKey`: JSON `[routeID: [actionRawValue]]` — ordered pins for
///   routes that were customized. A route without an entry uses the default.
/// - `defaultPinsKey`: JSON `[actionRawValue]` — the global default row (the
///   visible actions of the original Capture Bar settings, mirrored here).
/// - `syncAcrossSurfacesKey`: Bool, default `true` — "Same actions on Mac,
///   iPad and keyboard". When `false`, other surfaces should keep their own
///   built-in rows and ignore these pins.
///
/// Route IDs are `CapturePreset.id` (String). Unknown raw values are dropped.
public struct CaptureQuickActionPins: Equatable, Sendable {
    public static let routePinsKey = "capture.quickActions.routePins.v1"
    public static let defaultPinsKey = "capture.quickActions.defaultPins.v1"
    public static let syncAcrossSurfacesKey = "capture.quickActions.syncAcrossSurfaces.v1"

    /// Posted (on the default center, in-process) after `save(to:)`.
    public static let didChangeNotification = Notification.Name("CaptureQuickActionPinsDidChange")
    /// Darwin (cross-process) notification posted after `save(to:)` so the
    /// app, keyboard and other extensions can re-read pins live.
    public static let darwinDidChangeNotificationName = "bontecou.Voxboard.quickActionPinsDidChange"
    /// App Group mirror of the app's Insert Timestamp hour cycle
    /// (`CaptureTimestampFormat` raw value) for the keyboard extension.
    public static let sharedTimestampFormatKey = "capture.toolbar.timestampFormat.v1"

    /// The app's Insert Timestamp hour cycle as mirrored to the App Group,
    /// or nil when the app never wrote one.
    public static func sharedTimestampFormat(
        from defaults: UserDefaults? = AppConstants.sharedDefaults
    ) -> CaptureTimestampFormat? {
        defaults?.string(forKey: sharedTimestampFormatKey).flatMap(CaptureTimestampFormat.init(rawValue:))
    }

    /// Posts the cross-process pins-changed notification.
    public static func postDarwinDidChange() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(darwinDidChangeNotificationName as CFString),
            nil, nil, true
        )
    }

    /// Fallback row when nothing was ever saved.
    public static let builtInDefault: [CaptureQuickAction] = CaptureQuickAction.allCases

    public var defaultPins: [CaptureQuickAction]
    public var routePins: [String: [CaptureQuickAction]]
    public var syncsAcrossSurfaces: Bool

    public init(
        defaultPins: [CaptureQuickAction] = CaptureQuickActionPins.builtInDefault,
        routePins: [String: [CaptureQuickAction]] = [:],
        syncsAcrossSurfaces: Bool = true
    ) {
        self.defaultPins = defaultPins
        self.routePins = routePins
        self.syncsAcrossSurfaces = syncsAcrossSurfaces
    }

    /// Ordered pins for a route, falling back to `defaultPins`.
    public func pins(forRoute routeID: String?) -> [CaptureQuickAction] {
        if let routeID, let pins = routePins[routeID] { return pins }
        return defaultPins
    }

    /// What Mac / iPad / keyboard should show for a route: the route's pins
    /// when syncing is on, otherwise `nil` (use the surface's own row).
    public func pinsForOtherSurface(route routeID: String?) -> [CaptureQuickAction]? {
        syncsAcrossSurfaces ? pins(forRoute: routeID) : nil
    }

    public func hasCustomPins(forRoute routeID: String) -> Bool {
        routePins[routeID] != nil
    }

    /// Reads the shared pins. Pass `nil` (no App Group) to get defaults.
    public static func load(from defaults: UserDefaults? = AppConstants.sharedDefaults) -> CaptureQuickActionPins {
        guard let defaults else { return CaptureQuickActionPins() }
        let decoder = JSONDecoder()
        var result = CaptureQuickActionPins()
        if let data = defaults.data(forKey: defaultPinsKey),
           let raw = try? decoder.decode([String].self, from: data) {
            result.defaultPins = sanitized(raw)
        }
        if let data = defaults.data(forKey: routePinsKey),
           let raw = try? decoder.decode([String: [String]].self, from: data) {
            result.routePins = raw.mapValues(sanitized)
        }
        if defaults.object(forKey: syncAcrossSurfacesKey) != nil {
            result.syncsAcrossSurfaces = defaults.bool(forKey: syncAcrossSurfacesKey)
        }
        return result
    }

    public func save(to defaults: UserDefaults? = AppConstants.sharedDefaults) {
        guard let defaults else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(defaultPins.map(\.rawValue)) {
            defaults.set(data, forKey: Self.defaultPinsKey)
        }
        if let data = try? encoder.encode(routePins.mapValues { $0.map(\.rawValue) }) {
            defaults.set(data, forKey: Self.routePinsKey)
        }
        defaults.set(syncsAcrossSurfaces, forKey: Self.syncAcrossSurfacesKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        Self.postDarwinDidChange()
    }

    /// Drops unknown and duplicate raw values, preserving order.
    public static func sanitized(_ rawValues: [String]) -> [CaptureQuickAction] {
        var seen = Set<CaptureQuickAction>()
        return rawValues.compactMap { raw in
            guard let action = CaptureQuickAction(rawValue: raw), seen.insert(action).inserted else { return nil }
            return action
        }
    }
}
