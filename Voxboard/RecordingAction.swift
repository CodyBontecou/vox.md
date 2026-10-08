import AppIntents
import Foundation
import VoxboardShared

/// Recording state and app presentation are independent choices. Keep the raw
/// values stable: Shortcuts and control configurations persist them.
@available(iOS 17.0, *)
enum RecordingAction: String, AppEnum {
    case start
    case stop
    case toggle

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Recording Action"
    static let caseDisplayRepresentations: [RecordingAction: DisplayRepresentation] = [
        .start: "Start",
        .stop: "Stop",
        .toggle: "Start or Stop"
    ]

    enum Command: Equatable {
        case start
        case stop
        case none
    }

    func command(isRecording: Bool) -> Command {
        switch self {
        case .start: isRecording ? .none : .start
        case .stop: isRecording ? .stop : .none
        case .toggle: isRecording ? .stop : .start
        }
    }
}

/// The existing foreground handoff keeps its preset/flag keys. A missing action
/// must mean Start, so pre-upgrade widgets and saved Record shortcuts retain
/// their start-only behavior. Consume the action once, just like the preset.
enum WidgetRecordingActionSelection {
    static let key = "pendingWidgetRecordAction"

    static func persist(
        _ action: RecordingAction,
        defaults: UserDefaults? = AppConstants.sharedDefaults
    ) {
        defaults?.set(action.rawValue, forKey: key)
    }

    static func consume(defaults: UserDefaults? = AppConstants.sharedDefaults) -> RecordingAction {
        defer { defaults?.removeObject(forKey: key) }
        return defaults?.string(forKey: key).flatMap(RecordingAction.init(rawValue:)) ?? .start
    }
}

/// Shared by the configurable action and the legacy background toggle. The
/// injected effects let tests exercise routing and cleanup without a microphone
/// or an ActivityKit entitlement; production effects still use the same recorder.
@MainActor
enum BackgroundRecordingAction {
    enum Outcome: Equatable {
        case completed
        case openApp(action: RecordingAction)
    }

    struct Effects {
        var isRecording: () -> Bool
        var start: (String?) -> Bool
        var stop: () -> Void
        var stopListening: () -> Void
        var ensureLiveActivity: () -> Bool
        var endShortcutActivity: () -> Void
    }

    static func perform(
        action: RecordingAction,
        flowID: String?,
        effects: Effects?
    ) -> Outcome {
        guard let effects else {
            // Stop is idempotent, even when there is no recorder. Never send it
            // through a start-only foreground fallback.
            return action == .stop ? .completed : .openApp(action: .start)
        }

        switch action.command(isRecording: effects.isRecording()) {
        case .none:
            // Starting an already-active recording must not stop it, change its
            // preset, or discard its audio. Reuse/re-present its status card.
            if effects.isRecording(), !effects.ensureLiveActivity() {
                return .openApp(action: .start)
            }
            return .completed
        case .stop:
            effects.stop()
            // Transcription may keep the listening session alive briefly. If a
            // required card cannot be shown, release that session without ever
            // falling back to starting another recording.
            if !effects.ensureLiveActivity() {
                effects.stopListening()
                effects.endShortcutActivity()
            }
            return .completed
        case .start:
            guard effects.start(flowID) else {
                effects.endShortcutActivity()
                return .openApp(action: .start)
            }
            guard effects.ensureLiveActivity() else {
                // An AudioRecordingIntent must not return a newly activated
                // audio session with no Live Activity. Tear it down before the
                // foreground retry; retry Start, not Toggle.
                effects.stopListening()
                effects.endShortcutActivity()
                return .openApp(action: .start)
            }
            return .completed
        }
    }
}
