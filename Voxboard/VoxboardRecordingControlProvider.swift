import AppIntents
import Foundation
import VoxboardShared
import WidgetKit

/// Both stable control kinds share one configurable action. Defaults belong to
/// the kind, not to the optional new fields in saved configurations.
@available(iOS 18.0, *)
struct VoxboardRecordingControlProvider: AppIntentControlValueProvider {
    var defaultAction: RecordingAction = .start
    var defaultOpenApp: Bool = true

    struct State {
        let isEnabled: Bool
        let vox: VoxEntity
        let recordingAction: RecordingAction
        let openApp: Bool

        var action: VoxboardRecordingControlIntent {
            VoxboardRecordingControlIntent(vox: vox, action: recordingAction, openApp: openApp)
        }

        var actionHint: String {
            let opensApp: Bool
            if #available(iOS 26.0, *) { opensApp = openApp }
            else { opensApp = true }
            return switch (recordingAction, opensApp) {
            case (.start, true): String(localized: "Start recording and open Vox.md")
            case (.stop, true): String(localized: "Stop recording and open Vox.md")
            case (.toggle, true): String(localized: "Start or stop recording and open Vox.md")
            case (.start, false): String(localized: "Start recording without switching apps")
            case (.stop, false): String(localized: "Stop recording without switching apps")
            case (.toggle, false): String(localized: "Start or stop recording without switching apps")
            }
        }
    }

    func previewValue(configuration: SelectVoxboardRecordVoxIntent) -> State {
        state(configuration: configuration, isEnabled: true)
    }

    func currentValue(configuration: SelectVoxboardRecordVoxIntent) async throws -> State {
        state(configuration: configuration, isEnabled: AppConstants.lockScreenQuickRecordEnabled)
    }

    private func state(configuration: SelectVoxboardRecordVoxIntent, isEnabled: Bool) -> State {
        State(
            isEnabled: isEnabled,
            vox: VoxEntity.resolved(configuration.vox),
            recordingAction: configuration.recordingAction ?? defaultAction,
            openApp: configuration.openApp ?? defaultOpenApp
        )
    }
}
