import AppIntents
import Foundation
import VoxboardShared

/// Internal foreground handoff for Record Audio. A separate, non-recording
/// intent keeps immediate-foreground execution available without requiring a
/// background Live Activity or making another action visible in Shortcuts.
@available(iOS 17.0, *)
struct OpenVoxboardRecordingActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Recording in Vox.md"
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Preset")
    var vox: VoxEntity?

    @Parameter(title: "Action", default: .start)
    var recordingAction: RecordingAction

    init() {}

    init(vox: VoxEntity?, action: RecordingAction) {
        self.vox = vox
        self.recordingAction = action
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard AppConstants.lockScreenQuickRecordEnabled else { return .result() }
        if let flowID = VoxEntity.requestedFlowID(for: vox) {
            AppConstants.sharedDefaults?.set(flowID, forKey: AppConstants.pendingWidgetRecordFlowIdKey)
        } else {
            AppConstants.sharedDefaults?.removeObject(forKey: AppConstants.pendingWidgetRecordFlowIdKey)
        }
        WidgetRecordingActionSelection.persist(recordingAction)
        AppConstants.sharedDefaults?.set(true, forKey: AppConstants.pendingWidgetRecordKey)
        return .result()
    }
}
