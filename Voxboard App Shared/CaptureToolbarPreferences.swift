import Observation
import SwiftUI
import VoxboardShared

enum CapturePreferenceKeys {
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

/// The quick actions users can place in the capture bar.
enum CaptureToolbarAction: String, CaseIterable, Identifiable {
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

    var id: String { rawValue }

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
        }
    }

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
        }
    }

    var textIcon: String? {
        switch self {
        case .internalLink: "[["
        case .textCase: "Abc"
        default: nil
        }
    }
}

@MainActor
@Observable
final class CaptureToolbarPreferences {
    private struct StoredConfiguration: Codable {
        var order: [String]
        var hidden: [String]
    }

    static let storageKey = "capture.toolbar.configuration.v1"

    private let defaults: UserDefaults
    private(set) var orderedActions: [CaptureToolbarAction]
    private(set) var hiddenActions: Set<CaptureToolbarAction>
    private(set) var confirmsVoiceNotesBeforeAdding: Bool
    private(set) var presetQuickAccessRailSide: CapturePresetQuickAccessRailSide
    private(set) var timestampFormat: CaptureTimestampFormat

    // Avoid an actor-isolated synthesized destructor; this type owns no
    // main-actor resources that require isolated teardown.
    nonisolated deinit {}

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let stored = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode(StoredConfiguration.self, from: $0) }

        orderedActions = Self.migratedActionOrder(from: stored?.order)
        hiddenActions = Set(stored?.hidden.compactMap(CaptureToolbarAction.init(rawValue:)) ?? [])
        confirmsVoiceNotesBeforeAdding = defaults.bool(forKey: CapturePreferenceKeys.confirmVoiceNoteBeforeAdding)
        presetQuickAccessRailSide = CapturePresetQuickAccessRailSide(
            persistedRawValue: defaults.string(forKey: CapturePreferenceKeys.presetQuickAccessRailSide)
        )
        timestampFormat = defaults.string(forKey: CapturePreferenceKeys.timestampFormat)
            .flatMap(CaptureTimestampFormat.init(rawValue:))
            ?? .default
        persist()
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
    }

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
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.storageKey)
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
                Text("Quick Actions")
            } footer: {
                Text("Drag actions into the order you want. Turn off actions you do not want on the capture bar.")
            }

            Section {
                Picker("Side", selection: presetRailSideBinding) {
                    Text("Left").tag(CapturePresetQuickAccessRailSide.left)
                    Text("Right").tag(CapturePresetQuickAccessRailSide.right)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("capture_preset_rail_side")
            } header: {
                Text("Pinned Preset Rail")
            } footer: {
                Text("Choose the physical screen edge for pinned preset alternatives. The selected preset and Send stay in their usual positions.")
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
                    "Confirm Preset Sends",
                    isOn: presetSendConfirmationBinding
                )
                .tint(Geist.Palette.gray1000)
                .accessibilityIdentifier("capture_preset_send_confirmation")
            } header: {
                Text("Presets")
            } footer: {
                Text("Off by default. Turn this on to confirm before a Capture is sent with a preset. The sent-note toast also offers Undo for a few seconds after every composer send.")
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
    }

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
