import Observation
import SwiftUI
import VoxboardShared

enum CapturePreferenceKeys {
    /// Completed only after a delivered note; independent of purchase access.
    static let firstNoteSaved = "capture.firstNote.saved.v1"
    static let confirmVoiceNoteBeforeAdding = "capture.voice.confirmBeforeAdding.v1"
    static let confirmPresetSend = "capture.voice.confirmPresetSend.v1"
    /// Persisted default recording result mode ("Add to Draft" vs
    /// "Send Immediately"). Stored as the `CaptureRecordingMode` raw value;
    /// absent means `.draft` (the fresh-install and 2.8 migration default).
    static let defaultRecordingResultMode = "capture.voice.defaultResult.v1"
    /// One-way onboarding completion, independent of toolbar resets or app versions.
    static let micHoldHintDismissed = "capture.voice.micHoldHintDismissed.v1"
    /// Whether pinned Capture Presets are expanded beside the composer. An
    /// absent value is intentionally collapsed for a compact first launch.
    static let presetQuickAccessRailExpanded = "capture.presets.quickAccess.railExpanded.v1"
    /// Physical screen edge for the floating pinned-preset alternatives rail.
    static let presetQuickAccessRailSide = "capture.presets.quickAccess.railSide.v1"
    /// Explicit hour cycle for the Capture Bar's Insert Timestamp action.
    static let timestampFormat = "capture.toolbar.timestampFormat.v1"
}

/// A thumb-reach preference, intentionally expressed as physical screen edges.
/// Mapping to SwiftUI's logical alignments accounts for layout direction while
/// leaving the rail's child content in the user's natural semantic direction.
enum CapturePresetQuickAccessRailSide: String, CaseIterable, Hashable, Identifiable {
    case left
    case right

    static let `default`: Self = .left

    var id: String { rawValue }

    init(persistedRawValue: String?) {
        self = Self(rawValue: persistedRawValue ?? "") ?? .default
    }

    func overlayAlignment(for layoutDirection: LayoutDirection) -> Alignment {
        switch (self, layoutDirection) {
        case (.left, .leftToRight), (.right, .rightToLeft):
            return .leading
        case (.left, .rightToLeft), (.right, .leftToRight):
            return .trailing
        @unknown default:
            return self == .left ? .leading : .trailing
        }
    }
}

/// The quick actions users can place in the capture bar. The catalog (raw
/// values, design glyphs, groups) lives in `VoxboardShared.CaptureQuickAction`
/// so the keyboard extension can read the same pins from the App Group.
typealias CaptureToolbarAction = CaptureQuickAction

extension CaptureQuickAction {
    var title: LocalizedStringKey {
        switch self {
        case .addMedia: "Add Media"
        case .addFiles: "Add Files"
        case .scanDocument: "Scan Document"
        case .extractText: "Extract Text"
        case .undo: "Undo"
        case .formatMarkdown: "Format Markdown"
        case .markdownLink: "Markdown Link"
        case .dueDate: "Set Due Date"
        case .checklist: "Checklist"
        case .bulletList: "Bullet List"
        case .paste: "Paste"
        case .internalLink: "Internal Link"
        case .sketch: "Sketch"
        case .currentLocation: "Current Location"
        case .timestamp: "Insert Timestamp"
        case .date: "Insert Date"
        case .textCase: "Change Text Case"
        case .heading: "Heading"
        case .bold: "Bold"
        case .italic: "Italic"
        case .tag: "Tag"
        }
    }

    /// Short label used under glyphs (design: "Task", "Link note" …).
    var shortTitle: LocalizedStringKey {
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

    var accessibilityLabel: String {
        switch self {
        case .addMedia: String(localized: "Add media")
        case .addFiles: String(localized: "Add files")
        case .scanDocument: String(localized: "Scan document")
        case .extractText: String(localized: "Extract text from journal images")
        case .undo: String(localized: "Undo")
        case .formatMarkdown: String(localized: "Format Markdown")
        case .markdownLink: String(localized: "Markdown link")
        case .dueDate: String(localized: "Set due date")
        case .checklist: String(localized: "Checklist")
        case .bulletList: String(localized: "Bullet list")
        case .paste: String(localized: "Paste")
        case .internalLink: String(localized: "Internal link")
        case .sketch: String(localized: "Sketch")
        case .currentLocation: String(localized: "Insert current location")
        case .timestamp: String(localized: "Insert timestamp")
        case .date: String(localized: "Insert date")
        case .textCase: String(localized: "Change text case")
        case .heading: String(localized: "Heading")
        case .bold: String(localized: "Bold")
        case .italic: String(localized: "Italic")
        case .tag: String(localized: "Tag")
        }
    }

    /// SF Symbol, used only where the design has no text glyph (media and
    /// legacy list rows).
    var systemImage: String? {
        switch self {
        case .addMedia: "photo"
        case .addFiles: "paperclip"
        case .scanDocument: "doc.viewfinder"
        case .extractText: "text.viewfinder"
        case .undo: "arrow.uturn.backward"
        case .formatMarkdown: "textformat"
        case .markdownLink: "link"
        case .dueDate: "alarm"
        case .checklist: "checkmark.square"
        case .bulletList: "list.bullet"
        case .paste: "clipboard"
        case .internalLink: nil
        case .sketch: "pencil.tip"
        case .currentLocation: "location"
        case .timestamp: "clock"
        case .date: "calendar"
        case .textCase: nil
        case .heading, .bold, .italic, .tag: nil
        }
    }

    /// Mono text glyph for chips. `nil` for media actions, which keep SF
    /// Symbols (the design has no text glyph for them).
    var textIcon: String? {
        isMedia ? nil : glyph
    }
}

extension CaptureQuickActionGroup {
    var title: LocalizedStringKey {
        switch self {
        case .markdown: "MARKDOWN"
        case .insert: "INSERT"
        case .edit: "EDIT"
        case .media: "ATTACH"
        }
    }
}

/// Capture Bar preferences.
///
/// Two layers of quick-action pins:
/// - **Default row** (`orderedActions` minus `hiddenActions`, i.e.
///   `visibleActions`): the original global Capture Bar configuration. It is
///   the fallback for every route without its own pins.
/// - **Per-route pins** (`pinnedActions(forRoute:)`): an ordered list per
///   `CapturePreset.id`, stored in App Group defaults via
///   `CaptureQuickActionPins` so the keyboard, iPad and Mac read the same row.
///
/// Use `CaptureToolbarPreferences.shared` from views that are not handed an
/// instance (e.g. `RouteQuickActionsView`).
@MainActor
@Observable
final class CaptureToolbarPreferences {
    private struct StoredConfiguration: Codable {
        var order: [String]
        var hidden: [String]
    }

    static let storageKey = "capture.toolbar.configuration.v1"

    /// App-wide instance (standard defaults + App Group pins).
    static let shared = CaptureToolbarPreferences()

    private let defaults: UserDefaults
    private let pinDefaults: UserDefaults?
    private(set) var orderedActions: [CaptureToolbarAction]
    private(set) var hiddenActions: Set<CaptureToolbarAction>
    private(set) var confirmsVoiceNotesBeforeAdding: Bool
    private(set) var presetQuickAccessRailSide: CapturePresetQuickAccessRailSide
    private(set) var timestampFormat: CaptureTimestampFormat
    /// Ordered pins for routes the user customized. Routes absent here use
    /// `visibleActions`.
    private(set) var routePins: [String: [CaptureToolbarAction]]
    /// "Same actions on Mac, iPad and keyboard". Default `true`.
    private(set) var syncsQuickActionsAcrossSurfaces: Bool

    // Avoid an actor-isolated synthesized destructor; this type owns no
    // main-actor resources that require isolated teardown.
    nonisolated deinit {}

    /// - Parameters:
    ///   - defaults: storage for the global Capture Bar settings.
    ///   - pinDefaults: storage for per-route pins. When omitted, `.standard`
    ///     uses the App Group (`AppConstants.sharedDefaults`); any other
    ///     `defaults` (tests) keeps the pins in that same suite.
    init(defaults: UserDefaults = .standard, pinDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        let resolvedPinDefaults = pinDefaults
            ?? (defaults === UserDefaults.standard ? (AppConstants.sharedDefaults ?? defaults) : defaults)
        self.pinDefaults = resolvedPinDefaults

        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(StoredConfiguration.self, from: $0) }

        orderedActions = Self.migratedActionOrder(from: stored?.order)
        var hidden = Set(stored?.hidden.compactMap(CaptureToolbarAction.init(rawValue:)) ?? [])
        if let storedOrder = stored?.order {
            // Saved bars predate the split Markdown chips; keep those bars as
            // they were (the chips stay reachable under •••).
            for action in CaptureToolbarAction.introducedInSignalRedesign
            where !storedOrder.contains(action.rawValue) {
                hidden.insert(action)
            }
        }
        hiddenActions = hidden
        confirmsVoiceNotesBeforeAdding = defaults.bool(forKey: CapturePreferenceKeys.confirmVoiceNoteBeforeAdding)
        presetQuickAccessRailSide = CapturePresetQuickAccessRailSide(
            persistedRawValue: defaults.string(forKey: CapturePreferenceKeys.presetQuickAccessRailSide)
        )
        timestampFormat = defaults.string(forKey: CapturePreferenceKeys.timestampFormat)
            .flatMap(CaptureTimestampFormat.init(rawValue:))
            ?? .default
        let sharedPins = CaptureQuickActionPins.load(from: resolvedPinDefaults)
        routePins = sharedPins.routePins
        syncsQuickActionsAcrossSurfaces = sharedPins.syncsAcrossSurfaces
        persist()
        mirrorTimestampFormat()
    }

    /// Re-reads pins whenever another process (keyboard, share extension)
    /// saves them. Call once for the app-wide instance; the observer lives
    /// for the process.
    static func observeSharedPinChanges() {
        guard !isObservingSharedPinChanges else { return }
        isObservingSharedPinChanges = true
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    CaptureToolbarPreferences.shared.reloadSharedPins()
                }
            },
            CaptureQuickActionPins.darwinDidChangeNotificationName as CFString,
            nil,
            .deliverImmediately
        )
    }

    private static var isObservingSharedPinChanges = false

    /// Mirrors the Insert Timestamp hour cycle to the App Group so the
    /// keyboard's Time quick action follows the app setting.
    private func mirrorTimestampFormat() {
        guard let pinDefaults, pinDefaults !== defaults else { return }
        pinDefaults.set(timestampFormat.rawValue, forKey: CaptureQuickActionPins.sharedTimestampFormatKey)
    }

    nonisolated static func migratedActionOrder(from storedRawValues: [String]?) -> [CaptureToolbarAction] {
        var seen = Set<CaptureToolbarAction>()
        var order: [CaptureToolbarAction] = []
        for rawValue in storedRawValues ?? [] {
            guard let action = CaptureToolbarAction(rawValue: rawValue),
                  seen.insert(action).inserted else { continue }
            order.append(action)
        }

        for action in CaptureToolbarAction.allCases {
            guard seen.insert(action).inserted else { continue }
            // Keep newly introduced OCR discoverable for existing custom bars
            // instead of silently appending it beyond the initial viewport.
            if action == .extractText,
               let scanIndex = order.firstIndex(of: .scanDocument) {
                order.insert(action, at: scanIndex + 1)
            } else {
                order.append(action)
            }
        }
        return order
    }

    /// The global default row (fallback for routes without their own pins).
    var visibleActions: [CaptureToolbarAction] {
        orderedActions.filter { !hiddenActions.contains($0) }
    }

    func isVisible(_ action: CaptureToolbarAction) -> Bool {
        !hiddenActions.contains(action)
    }

    func setVisible(_ isVisible: Bool, for action: CaptureToolbarAction) {
        if isVisible {
            hiddenActions.remove(action)
        } else {
            hiddenActions.insert(action)
        }
        persist()
    }

    func moveActions(from source: IndexSet, to destination: Int) {
        orderedActions.move(fromOffsets: source, toOffset: destination)
        persist()
    }

    // MARK: Per-route pins

    /// Ordered pinned row for a route (`CapturePreset.id`); `nil` or an
    /// uncustomized route returns the global default row.
    func pinnedActions(forRoute routeID: String?) -> [CaptureToolbarAction] {
        if let routeID, let pins = routePins[routeID] { return pins }
        return visibleActions
    }

    /// Like `pinnedActions(forRoute:)`, but a surface with its own design row
    /// (the Mac workspace) shows `surfaceDefault` when the person has neither
    /// pinned actions for the route nor customized the default row, or when
    /// "Same actions on Mac, iPad and keyboard" is off.
    func pinnedActions(
        forRoute routeID: String?,
        surfaceDefault: [CaptureToolbarAction]
    ) -> [CaptureToolbarAction] {
        guard syncsQuickActionsAcrossSurfaces else { return surfaceDefault }
        if let routeID, let pins = routePins[routeID] { return pins }
        return hasCustomizedDefaultRow ? visibleActions : surfaceDefault
    }

    /// `false` while the default row is still the built-in one: every action
    /// in catalog order with nothing hidden, or a pre-redesign bar whose only
    /// hidden actions are the chips added by the Signal redesign.
    var hasCustomizedDefaultRow: Bool {
        guard orderedActions == CaptureToolbarAction.allCases else { return true }
        return !(hiddenActions.isEmpty || hiddenActions == CaptureToolbarAction.introducedInSignalRedesign)
    }

    /// Every action not pinned on the route, in catalog group order.
    func unpinnedActions(forRoute routeID: String?) -> [CaptureToolbarAction] {
        let pinned = Set(pinnedActions(forRoute: routeID))
        return CaptureQuickActionGroup.allCases
            .flatMap(\.actions)
            .filter { !pinned.contains($0) }
    }

    func hasCustomPins(forRoute routeID: String) -> Bool {
        routePins[routeID] != nil
    }

    func isPinned(_ action: CaptureToolbarAction, forRoute routeID: String?) -> Bool {
        pinnedActions(forRoute: routeID).contains(action)
    }

    /// Replaces a route's pins (creates the override if needed).
    func setPinnedActions(_ actions: [CaptureToolbarAction], forRoute routeID: String) {
        var seen = Set<CaptureToolbarAction>()
        routePins[routeID] = actions.filter { seen.insert($0).inserted }
        persistPins()
    }

    /// Appends `action` to the route's row (copying the default row first).
    func pin(_ action: CaptureToolbarAction, forRoute routeID: String) {
        var pins = pinnedActions(forRoute: routeID)
        guard !pins.contains(action) else { return }
        pins.append(action)
        setPinnedActions(pins, forRoute: routeID)
    }

    func unpin(_ action: CaptureToolbarAction, forRoute routeID: String) {
        setPinnedActions(pinnedActions(forRoute: routeID).filter { $0 != action }, forRoute: routeID)
    }

    func movePinnedActions(from source: IndexSet, to destination: Int, forRoute routeID: String) {
        var pins = pinnedActions(forRoute: routeID)
        pins.move(fromOffsets: source, toOffset: destination)
        setPinnedActions(pins, forRoute: routeID)
    }

    /// Drops the route's override so it follows the global default row again.
    func resetPins(forRoute routeID: String) {
        routePins[routeID] = nil
        persistPins()
    }

    func setSyncsQuickActionsAcrossSurfaces(_ syncs: Bool) {
        syncsQuickActionsAcrossSurfaces = syncs
        persistPins()
    }

    /// Re-reads App Group pins (e.g. after another process changed them).
    func reloadSharedPins() {
        let sharedPins = CaptureQuickActionPins.load(from: pinDefaults)
        if routePins != sharedPins.routePins { routePins = sharedPins.routePins }
        if syncsQuickActionsAcrossSurfaces != sharedPins.syncsAcrossSurfaces {
            syncsQuickActionsAcrossSurfaces = sharedPins.syncsAcrossSurfaces
        }
    }

    func setConfirmsVoiceNotesBeforeAdding(_ shouldConfirm: Bool) {
        confirmsVoiceNotesBeforeAdding = shouldConfirm
        defaults.set(shouldConfirm, forKey: CapturePreferenceKeys.confirmVoiceNoteBeforeAdding)
    }

    func setPresetQuickAccessRailSide(_ side: CapturePresetQuickAccessRailSide) {
        presetQuickAccessRailSide = side
        defaults.set(side.rawValue, forKey: CapturePreferenceKeys.presetQuickAccessRailSide)
    }

    func setTimestampFormat(_ format: CaptureTimestampFormat) {
        timestampFormat = format
        defaults.set(format.rawValue, forKey: CapturePreferenceKeys.timestampFormat)
        mirrorTimestampFormat()
    }

    /// Resets the global default row. Per-route pins are left alone; use
    /// `resetPins(forRoute:)` for those.
    func reset() {
        orderedActions = CaptureToolbarAction.allCases
        hiddenActions = []
        persist()
    }

    private func persist() {
        let configuration = StoredConfiguration(
            order: orderedActions.map(\.rawValue),
            hidden: hiddenActions.map(\.rawValue).sorted()
        )
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: Self.storageKey)
        }
        persistPins()
    }

    /// Mirrors the default row and writes route pins to the App Group.
    private func persistPins() {
        CaptureQuickActionPins(
            defaultPins: visibleActions,
            routePins: routePins,
            syncsAcrossSurfaces: syncsQuickActionsAcrossSurfaces
        ).save(to: pinDefaults)
    }
}

#if os(iOS)
struct CaptureToolbarSettingsView: View {
    @Bindable var preferences: CaptureToolbarPreferences
    @State private var editMode: EditMode = .active

    var body: some View {
        List {
            Section {
                ForEach(preferences.orderedActions) { action in
                    HStack(spacing: Geist.Spacing.three) {
                        actionIcon(action)
                            .frame(width: 24)
                        Text(action.title)

                        Spacer()
                        Toggle("", isOn: visibilityBinding(for: action))
                            .labelsHidden()
                            .tint(Geist.Palette.gray1000)
                    }
                }
                .onMove(perform: preferences.moveActions)
            } header: {
                Text("Default Quick Actions")
            } footer: {
                Text("Drag actions into the order you want. Turn off actions you do not want on the capture bar. Routes without their own quick actions use this row.")
            }

            Section {
                ForEach(routes) { route in
                    // Buttons stay tappable while the list is in edit mode
                    // (NavigationLink rows do not).
                    Button {
                        editingRouteID = route.id
                    } label: {
                        HStack(spacing: Geist.Spacing.three) {
                            CapturePresetIconView(symbolName: route.symbolName, emoji: route.emoji)
                                .frame(width: 24)
                            Text(verbatim: route.displayName)
                            Spacer()
                            Text(preferences.hasCustomPins(forRoute: route.id) ? "Custom" : "Default")
                                .font(Geist.mono(.caption))
                                .foregroundStyle(Geist.muted)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Geist.faint)
                        }
                        .foregroundStyle(Geist.text)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("capture_route_quick_actions_\(route.id)")
                }
            } header: {
                Text("Quick Actions per Route")
            } footer: {
                Text("Pin a different row for each route. It shows above the keyboard while that route is selected.")
            }

            Section {
                Picker("Side", selection: presetRailSideBinding) {
                    Text("Left").tag(CapturePresetQuickAccessRailSide.left)
                    Text("Right").tag(CapturePresetQuickAccessRailSide.right)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("capture_preset_rail_side")
            } header: {
                Text("Pinned Route Rail")
            } footer: {
                Text("Choose the physical screen edge for pinned route alternatives. The selected route and Send stay in their usual positions.")
            }

            Section {
                Picker("Timestamp Format", selection: timestampFormatRawValueBinding) {
                    ForEach(CaptureTimestampFormat.allCases) { format in
                        Text(verbatim: format.rawValue).tag(format.rawValue)
                    }
                }
                .accessibilityIdentifier("capture_timestamp_format")
            } header: {
                Text("Insert Timestamp")
            } footer: {
                Text("The Capture Bar uses this explicit hour cycle instead of inferring it from the device setting.")
            }

            Section {
                Toggle(
                    "Review Before Adding",
                    isOn: voiceConfirmationBinding
                )
                .tint(Geist.Palette.gray1000)
                .accessibilityIdentifier("capture_voice_review_before_adding")
            } header: {
                Text("Voice Notes")
            } footer: {
                Text("Off by default. After you tap Done, Vox.md adds the recording and, when available, its on-device transcript to the current draft automatically. Turn this on to play, retry, copy, or review them before adding.")
            }

            Section {
                Toggle(
                    "Confirm Route Sends",
                    isOn: presetSendConfirmationBinding
                )
                .tint(Geist.Palette.gray1000)
                .accessibilityIdentifier("capture_preset_send_confirmation")
            } header: {
                Text("Routes")
            } footer: {
                Text("Off by default. Turn this on to confirm before a Capture is sent with a route. The sent-note toast also offers Undo for a few seconds after every composer send.")
            }

            Section {
                Button("Reset Quick Actions", role: .destructive) {
                    preferences.reset()
                }
            }
        }
        .navigationTitle("Capture Bar")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, $editMode)
        .navigationDestination(item: $editingRouteID) { routeID in
            RouteQuickActionsView(presetID: routeID, preferences: preferences)
        }
        .onAppear {
            routes = CapturePresetStore.loadFlows(persistMigrations: false).filter(\.isEnabled)
        }
    }

    @State private var editingRouteID: String?
    @State private var routes: [CapturePreset] = CapturePresetStore.loadFlows(persistMigrations: false)
        .filter(\.isEnabled)

    private func visibilityBinding(for action: CaptureToolbarAction) -> Binding<Bool> {
        Binding(
            get: { preferences.isVisible(action) },
            set: { preferences.setVisible($0, for: action) }
        )
    }

    private var voiceConfirmationBinding: Binding<Bool> {
        Binding(
            get: { preferences.confirmsVoiceNotesBeforeAdding },
            set: { preferences.setConfirmsVoiceNotesBeforeAdding($0) }
        )
    }

    private var presetRailSideBinding: Binding<CapturePresetQuickAccessRailSide> {
        Binding(
            get: { preferences.presetQuickAccessRailSide },
            set: { preferences.setPresetQuickAccessRailSide($0) }
        )
    }

    private var timestampFormatRawValueBinding: Binding<String> {
        Binding(
            get: { preferences.timestampFormat.rawValue },
            set: {
                preferences.setTimestampFormat(
                    CaptureTimestampFormat(rawValue: $0) ?? .default
                )
            }
        )
    }

    @AppStorage(CapturePreferenceKeys.confirmPresetSend)
    private var confirmsPresetSend = false

    private var presetSendConfirmationBinding: Binding<Bool> {
        Binding(
            get: { confirmsPresetSend },
            set: { confirmsPresetSend = $0 }
        )
    }

    @ViewBuilder
    private func actionIcon(_ action: CaptureToolbarAction) -> some View {
        if let systemImage = action.systemImage {
            Image(systemName: systemImage)
                .foregroundStyle(Geist.text)
        } else {
            Text(action.textIcon ?? "")
                .font(Geist.mono(.footnote, medium: true))
                .foregroundStyle(Geist.text)
        }
    }
}
#endif
