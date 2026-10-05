import AppIntents
import Foundation
import VoxboardShared

/// Compatibility identity for saved Toggle Recording shortcuts. Keep the preset
/// parameter and background start/stop defaults; new shortcuts use Record Audio.
@available(iOS 26.0, *)
struct ToggleVoxboardRecordingIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Toggle Recording"
    static let description = IntentDescription("Starts or stops a Vox.md recording without leaving the current app. Run it again to stop.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false
    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }

    @Parameter(title: "Preset", description: "The Capture Preset to use when this intent starts a recording.")
    var vox: VoxEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Toggle recording with \(\.$vox)")
    }

    init() {}

    init(vox: VoxEntity?) {
        self.vox = vox
    }

    @MainActor
    func perform() async throws -> some IntentResult & OpensIntent {
        try await RecordingIntentExecution.perform(vox: vox, action: .toggle, openApp: false)
    }
}
