import AppIntents
import SwiftUI
import VoxboardShared
import WidgetKit

/// Keep this kind registered so installed background control assignments keep
/// working. New assignments should use the configurable Vox.md Record control.
/// WidgetKit has no public modifier for hiding a registered legacy control kind.
@available(iOS 26.0, *)
struct VoxboardToggleRecordingControl: ControlWidget {
    static let kind = "VoxboardToggleRecordingControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: Provider()) { state in
            ControlWidgetButton(action: state.action) {
                Label(
                    state.isEnabled ? state.vox.name : String(localized: "Off"),
                    systemImage: state.isEnabled ? state.vox.symbolName : "mic.slash"
                )
                .controlWidgetActionHint(
                    state.isEnabled ? state.actionHint : String(localized: "Disabled in Vox.md Settings")
                )
            }
            .disabled(!state.isEnabled)
        }
        .displayName("Vox.md Record (Legacy Background)")
        .description("Preserves existing background start/stop assignments. For new controls, use Vox.md Record and configure Action and Open App.")
        .promptsForUserConfiguration()
    }

    struct Provider: AppIntentControlValueProvider {
        private let provider = VoxboardRecordingControlProvider(defaultAction: .toggle, defaultOpenApp: false)

        func previewValue(configuration: SelectVoxboardRecordVoxIntent) -> VoxboardRecordingControlProvider.State {
            provider.previewValue(configuration: configuration)
        }

        func currentValue(configuration: SelectVoxboardRecordVoxIntent) async throws -> VoxboardRecordingControlProvider.State {
            try await provider.currentValue(configuration: configuration)
        }
    }
}
