import SwiftUI
import VoxboardShared

struct CaptureHTTPEndpointSettingsRoute: Hashable, Identifiable {
    let presetID: String
    var id: String { presetID }
}

/// A direct entry to the same HTTP controls used in the full preset editor.
/// The route freezes preset identity; edits merge into its latest saved record.
@Observable
final class CaptureHTTPEndpointSettingsModel {
    private(set) var preset: CapturePreset?
    let presetID: String
    private let defaults: UserDefaults?
    private let widgetRefresh: CapturePresetWidgetRefresh

    init(
        presetID: String,
        defaults: UserDefaults? = AppConstants.sharedDefaults,
        widgetRefresh: CapturePresetWidgetRefresh = .live
    ) {
        self.presetID = presetID
        self.defaults = defaults
        self.widgetRefresh = widgetRefresh
        let saved = CapturePresetStore.flow(id: presetID, defaults: defaults)
        preset = saved?.deliveryTarget == .http ? saved : nil
    }

    var settings: CapturePresetURLDeliverySettings {
        get { preset?.exportSettings.urlDelivery ?? CapturePresetURLDeliverySettings() }
        set {
            var flows = CapturePresetStore.loadFlows(defaults: defaults)
            guard let index = flows.firstIndex(where: { $0.id == presetID }),
                  flows[index].deliveryTarget == .http else {
                preset = nil
                return
            }
            flows[index].exportSettings.urlDelivery = newValue
            flows[index].exportSettings.usesCustomExportSettings = true
            CapturePresetStore.saveFlows(flows, defaults: defaults, widgetRefresh: widgetRefresh)
            preset = CapturePresetStore.flow(id: presetID, defaults: defaults)
        }
    }
}

struct CaptureHTTPEndpointSettingsView: View {
    @State private var model: CaptureHTTPEndpointSettingsModel

    init(presetID: String) {
        _model = State(initialValue: CaptureHTTPEndpointSettingsModel(presetID: presetID))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            if let preset = model.preset {
                Section {
                    Text(preset.accessibilityName)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("capture_http_endpoint_preset")
                }
                URLDeliverySettingsSection(settings: $model.settings, focusEndpointOnAppear: true)
            } else {
                ContentUnavailableView("HTTP Preset Unavailable", systemImage: "network.slash",
                                       description: Text("Return to Capture and choose an HTTP preset."))
            }
        }
        .navigationTitle("HTTP Endpoint")
        .accessibilityIdentifier("capture_http_endpoint_editor")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .formStyle(.grouped)
        #endif
    }
}
