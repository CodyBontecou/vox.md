import Foundation

/// An input-level check cannot decide whether speech was present. In
/// particular, all-zero buffers can come from a muted or stalled input route
/// even when permission is granted and AVAudioEngine reports that it is running.
enum RecordingInputValidation {
    enum Failure: Equatable {
        case muted
        case unavailable
        case tooQuiet

        var message: String {
            switch self {
            case .muted:
                return String(localized: "The microphone is muted. Unmute it, then try recording again.")
            case .unavailable:
                return String(localized: "The microphone isn't receiving audio. Check your input device or restart your iPhone, then try again.")
            case .tooQuiet:
                return String(localized: "The recording was too quiet. Move closer to the microphone, then try again.")
            }
        }
    }

    static func failure(maxAmplitude: Float, isInputMuted: Bool) -> Failure? {
        guard maxAmplitude.isFinite, maxAmplitude >= 0 else { return .unavailable }
        // Keep usable audio captured before an input was muted at the end.
        guard maxAmplitude < 0.005 else { return nil }
        if isInputMuted { return .muted }
        return maxAmplitude == 0 ? .unavailable : .tooQuiet
    }
}
