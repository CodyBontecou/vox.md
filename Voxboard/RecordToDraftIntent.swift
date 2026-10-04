import AppIntents
import VoxboardShared

/// A separate foreground quick action: start now, review before Send.
/// Keep the legacy immediate-record and background-toggle intent identities intact.
@available(iOS 17.0, *)
struct RecordToDraftIntent: AppIntent {
    static let title: LocalizedStringResource = "Record to Draft"
    static let description = IntentDescription("Opens Vox.md and starts recording with a Capture Preset. Adds the transcript to your existing draft for review, without sending it. Optionally attaches the audio.")
    static var openAppWhenRun: Bool = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Preset", description: "The Capture Preset whose voice-processing settings to use.")
    var vox: VoxEntity?

    @Parameter(title: "Attach Audio", description: "Keep the recording as an attachment in the draft.", default: false)
    var attachAudio: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Record with \(\.$vox) to Draft") {
            \.$attachAudio
        }
    }

    init() {}

    init(vox: VoxEntity?, attachAudio: Bool = false) {
        self.vox = vox
        self.attachAudio = attachAudio
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard AppConstants.lockScreenQuickRecordEnabled else { return .result() }
        PendingQuickRecordingRequest(
            requestedFlowID: vox?.id,
            draftAttachAudio: attachAudio
        ).persist()
        return .result()
    }
}
