import AppIntents
import SwiftUI
import VoxboardShared
import WidgetKit

// MARK: - Control Widget (iOS 18+ lock screen bottom slots / Control Center)

@available(iOS 18.0, *)
struct VoxboardRecordControl: ControlWidget {
    static let kind = "VoxboardRecordControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: VoxboardRecordingControlProvider()) { state in
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
        .displayName("Vox.md Record")
        .description("Record with a Capture Preset. Configure Start, Stop, or Start or Stop and whether to open Vox.md. Background recording requires iOS 26+.")
        .promptsForUserConfiguration()
    }
}
