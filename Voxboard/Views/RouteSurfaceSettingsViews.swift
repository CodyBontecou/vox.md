import SwiftUI
import VoxboardShared
import WidgetKit

extension CapturePresetPinSurface {
    var displayName: String {
        switch self {
        case .widgets: String(localized: "Widgets")
        case .controlCenter: String(localized: "Control Center")
        case .keyboard: String(localized: "Keyboard")
        case .watch: String(localized: "Apple Watch")
        }
    }

    /// Lower-case form used in running copy ("pinned to Watch and keyboard").
    var inlineName: String {
        switch self {
        case .widgets: String(localized: "widgets")
        case .controlCenter: String(localized: "Control Center")
        case .keyboard: String(localized: "keyboard")
        case .watch: String(localized: "Watch")
        }
    }

    var systemImage: String {
        switch self {
        case .widgets: "square.grid.2x2"
        case .controlCenter: "switch.2"
        case .keyboard: "keyboard"
        case .watch: "applewatch"
        }
    }

    /// Notifies the surfaces that read these pins.
    func reloadConsumers() {
        switch self {
        case .widgets: WidgetCenter.shared.reloadAllTimelines()
        case .controlCenter:
            if #available(iOS 18.0, *) { ControlCenter.shared.reloadAllControls() }
        case .watch: WatchRecordingController.shared.publishState()
        case .keyboard: break
        }
    }
}

enum RouteSurfacePins {
    static var defaults: UserDefaults? { AppConstants.sharedDefaults }

    static func toggle(_ surface: CapturePresetPinSurface, id: String) {
        let pinned = CapturePresetSurfacePinStore.isPinned(id: id, to: surface, defaults: defaults)
        set(!pinned, surface: surface, id: id)
    }

    static func set(_ pinned: Bool, surface: CapturePresetPinSurface, id: String) {
        // The first explicit choice for Watch replaces "every route" with an
        // explicit list; seed it with the enabled routes so unpinning one does
        // not silently hide all others.
        if surface == .watch, !CapturePresetSurfacePinStore.isConfigured(.watch, defaults: defaults) {
            for flow in CapturePresetStore.loadFlows().filter(\.isEnabled) where flow.id != id {
                CapturePresetSurfacePinStore.setPinned(true, id: flow.id, to: .watch, defaults: defaults)
            }
        }
        CapturePresetSurfacePinStore.setPinned(pinned, id: id, to: surface, defaults: defaults)
        surface.reloadConsumers()
    }

    /// Effective membership shown in the UI (Watch shows every route until configured).
    static func isPinned(_ surface: CapturePresetPinSurface, id: String) -> Bool {
        if surface == .watch, !CapturePresetSurfacePinStore.isConfigured(.watch, defaults: defaults) {
            return true
        }
        return CapturePresetSurfacePinStore.isPinned(id: id, to: surface, defaults: defaults)
    }

    static func pinnedFlows(_ surface: CapturePresetPinSurface) -> [CapturePreset] {
        let enabled = CapturePresetStore.loadFlows().filter(\.isEnabled)
        let ids = surface == .watch
            ? CapturePresetSurfacePinStore.effectivePinnedIDs(for: .watch, allIDs: enabled.map(\.id), defaults: defaults)
            : CapturePresetSurfacePinStore.pinnedIDs(for: surface, defaults: defaults)
        return ids.compactMap { id in enabled.first { $0.id == id } }
    }
}

/// Toggle list of routes for one surface (Keyboard, Apple Watch, widgets…).
struct RouteSurfacePinsView: View {
    let surface: CapturePresetPinSurface
    @State private var flows: [CapturePreset] = []
    @State private var revision = 0

    var body: some View {
        Form {
            Section {
                ForEach(flows) { flow in
                    Toggle(isOn: Binding(
                        get: { _ = revision; return RouteSurfacePins.isPinned(surface, id: flow.id) },
                        set: { RouteSurfacePins.set($0, surface: surface, id: flow.id); revision &+= 1 }
                    )) {
                        HStack(spacing: 12) {
                            CapturePresetSettingsRouteTile(preset: flow, size: 32)
                            Text(flow.displayName).font(Geist.label(.body))
                        }
                    }
                    .tint(Geist.accent)
                    .accessibilityIdentifier("surface_pin_\(surface.rawValue)_\(flow.id)")
                }
            } header: {
                Text("Routes").textCase(.uppercase).font(Geist.mono(size: 11, relativeTo: .caption))
            } footer: {
                Text(footer)
            }
            .listRowBackground(Geist.card)
        }
        .scrollContentBackground(.hidden)
        .background(Geist.bg.ignoresSafeArea())
        .tint(Geist.accent)
        .navigationTitle(surface.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { flows = CapturePresetStore.loadFlows().filter(\.isEnabled) }
    }

    private var footer: LocalizedStringKey {
        switch surface {
        case .keyboard: "Pinned routes appear in the Vox.md keyboard. Allow Full Access in Settings › General › Keyboard to dictate."
        case .watch: "Only pinned routes appear on Apple Watch. Until you change this, every route is available."
        case .widgets: "Pinned routes are suggested first when you configure a Vox.md widget."
        case .controlCenter: "Pinned routes are suggested first when you configure a Vox.md control."
        }
    }
}

/// Action button / Control Center → Route mapping plus Control Center pins.
struct ShortcutsControlCenterSettingsView: View {
    @State private var flows: [CapturePreset] = []
    @State private var actionRouteID: String = ""

    var body: some View {
        Form {
            Section {
                Picker("Action Button", selection: $actionRouteID) {
                    Text("Default Route").tag("")
                    ForEach(flows) { flow in
                        Text(flow.displayName).tag(flow.id)
                    }
                }
                .accessibilityIdentifier("settings_action_button_route")
            } header: {
                Text("Action Button & Controls").textCase(.uppercase).font(Geist.mono(size: 11, relativeTo: .caption))
            } footer: {
                Text("Used by the Vox.md Record control and shortcuts that don’t choose a route. Assign the Vox.md Record control to the Action button in iPhone Settings › Action Button.")
            }
            .listRowBackground(Geist.card)

            Section {
                NavigationLink {
                    RouteSurfacePinsView(surface: .controlCenter)
                } label: {
                    LabeledContent("Control Center", value: summary(.controlCenter))
                }
                NavigationLink {
                    RouteSurfacePinsView(surface: .widgets)
                } label: {
                    LabeledContent("Widgets", value: summary(.widgets))
                }
            } header: {
                Text("Pinned Routes").textCase(.uppercase).font(Geist.mono(size: 11, relativeTo: .caption))
            }
            .listRowBackground(Geist.card)
        }
        .scrollContentBackground(.hidden)
        .background(Geist.bg.ignoresSafeArea())
        .tint(Geist.accent)
        .navigationTitle("Shortcuts & Control Center")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            flows = CapturePresetStore.loadFlows().filter(\.isEnabled)
            actionRouteID = CapturePresetSurfacePinStore.actionButtonRouteID(defaults: RouteSurfacePins.defaults) ?? ""
        }
        .onChange(of: actionRouteID) { _, id in
            CapturePresetSurfacePinStore.setActionButtonRouteID(id.isEmpty ? nil : id, defaults: RouteSurfacePins.defaults)
            CapturePresetPinSurface.controlCenter.reloadConsumers()
        }
    }

    private func summary(_ surface: CapturePresetPinSurface) -> String {
        let names = RouteSurfacePins.pinnedFlows(surface).map(\.displayName)
        return names.isEmpty ? String(localized: "None") : names.joined(separator: ", ")
    }
}

/// Picker for the transcription language, also reachable from Models.
struct TranscriptionLanguageSettingsView: View {
    @Environment(ModelManager.self) private var modelManager

    var body: some View {
        Form {
            Section {
                if modelManager.selectedModel?.engine.isParakeet == true {
                    Text("Parakeet detects language automatically. Manual language hints are unavailable for this engine.")
                        .foregroundStyle(Geist.muted)
                } else {
                    ForEach(modelManager.availableLanguages, id: \.code) { language in
                        Button {
                            modelManager.selectedLanguage = language.code
                        } label: {
                            HStack {
                                Text(language.name).foregroundStyle(Geist.text)
                                Spacer()
                                if modelManager.selectedLanguage == language.code {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Geist.accentText)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(modelManager.selectedLanguage == language.code ? .isSelected : [])
                    }
                }
            } footer: {
                if modelManager.isAutomaticSelection {
                    Text("System Language follows your device language. Choose a language explicitly when the recording uses another language.")
                }
            }
            .listRowBackground(Geist.card)
        }
        .scrollContentBackground(.hidden)
        .background(Geist.bg.ignoresSafeArea())
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}
