import AppIntents
import SwiftUI
import VoxboardShared
import WidgetKit

/// Additive control registration for review-in-draft recording, not the
/// immediate recording control or the iOS 26 background toggle.
@available(iOS 18.0, *)
struct VoxboardDraftRecordingControl: ControlWidget {
    static let kind = "VoxboardDraftRecordingControl"

    var body: some ControlWidgetConfiguration {
        AppIntentControlConfiguration(kind: Self.kind, provider: Provider()) { state in
            ControlWidgetButton(action: RecordToDraftIntent(vox: state.vox)) {
                Label(
                    state.isEnabled ? state.vox.name : String(localized: "Off"),
                    systemImage: state.isEnabled ? "square.and.pencil" : "mic.slash"
                )
                .controlWidgetActionHint(
                    state.isEnabled
                        ? String(localized: "Record to Draft with \(state.vox.name)")
                        : String(localized: "Disabled in Vox.md Settings")
                )
            }
            .disabled(!state.isEnabled)
        }
        .displayName("Vox.md Record to Draft")
        .description("Start recording with a Capture Preset and review the transcript in your draft before sending.")
        .promptsForUserConfiguration()
    }

    struct State {
        let isEnabled: Bool
        let vox: VoxEntity
    }

    private struct Provider: AppIntentControlValueProvider {
        func previewValue(configuration: SelectVoxboardDraftRecordVoxIntent) -> State {
            State(isEnabled: true, vox: VoxEntity.resolved(configuration.vox))
        }

        func currentValue(configuration: SelectVoxboardDraftRecordVoxIntent) async throws -> State {
            State(
                isEnabled: AppConstants.lockScreenQuickRecordEnabled,
                vox: VoxEntity.resolved(configuration.vox)
            )
        }
    }
}
