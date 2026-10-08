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

    @Parameter(title: "Delivery", default: .immediate)
    var delivery: RecordingDelivery

    @Parameter(title: "Attach Audio", default: false)
    var attachAudio: Bool

    init() {}

    init(vox: VoxEntity?, action: RecordingAction, delivery: RecordingDelivery = .immediate, attachAudio: Bool = false) {
        self.vox = vox
        self.recordingAction = action
        self.delivery = delivery
        self.attachAudio = attachAudio
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard AppConstants.lockScreenQuickRecordEnabled else { return .result() }
        PendingQuickRecordingRequest(
            requestedFlowID: VoxEntity.requestedFlowID(for: vox),
            draftAttachAudio: delivery == .draft ? attachAudio : nil,
            recordingAction: recordingAction
        ).persist()
        return .result()
    }
}
