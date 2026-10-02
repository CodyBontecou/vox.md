import AppIntents
import SwiftUI
import VoxboardShared
import WidgetKit

/// A separate kind preserves all existing foreground Record assignments.
/// Use a button (run again to stop), not a SetValueIntent toggle: the app's
/// recorder, rather than a potentially stale extension snapshot, owns state.
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
                    state.isEnabled
                        ? String(localized: "Start or stop recording without switching apps")
                        : String(localized: "Disabled in Vox.md Settings")
                )
            }
            .disabled(!state.isEnabled)
        }
        .displayName("Vox.md Toggle Recording")
        .description("Start or stop recording in the background with a Capture Preset. Opens Vox.md if recording needs setup.")
        .promptsForUserConfiguration()
    }

    struct State {
        let isEnabled: Bool
        let vox: VoxEntity

        var action: ToggleVoxboardRecordingIntent {
            ToggleVoxboardRecordingIntent(vox: vox)
        }
    }

    struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: SelectVoxboardRecordVoxIntent) -> State {
            State(isEnabled: true, vox: VoxEntity.resolved(configuration.vox))
        }

        func currentValue(configuration: SelectVoxboardRecordVoxIntent) async throws -> State {
            State(
                isEnabled: AppConstants.lockScreenQuickRecordEnabled,
                vox: VoxEntity.resolved(configuration.vox)
            )
        }
    }
}
