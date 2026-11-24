import AVFoundation
import VoxboardShared

/// The `.playAndRecord` session the iPhone recorder runs with. `standard` is
/// the configuration every recording used before High/Lossless input options:
/// Keyboard Listening, dictation and Speech recordings keep it.
///
/// A High or Lossless one-shot recording can add:
/// - `.bluetoothHighQualityRecording` (iOS 26): full-bandwidth recording from
///   AirPods that support it. `.allowBluetooth` (HFP) stays set as the system's
///   fallback for every other headset.
/// - the `.measurement` mode ("Natural sound"): less system input processing.
/// - built-in microphone (Stereo and Spatial Audio): `.allowBluetoothA2DP`
///   instead of `.allowBluetooth`, so AirPods and other Bluetooth headsets
///   stay connected for playback but never become the input. The hands-free
///   profile is what makes a headset the microphone.
///
/// Applying never fails a recording: if the system rejects the requested
/// configuration, the standard one is applied instead.
struct RecordingAudioSessionConfiguration: Equatable {
    var mode: AVAudioSession.Mode
    var options: AVAudioSession.CategoryOptions
    /// High-quality Bluetooth recording adds input latency and a call ringtone
    /// would interrupt it, so Apple recommends muting system alerts while it
    /// records (`setPrefersNoInterruptionsFromSystemAlerts`).
    var prefersNoSystemAlertInterruptions: Bool

    static let standard = RecordingAudioSessionConfiguration(
        mode: .default,
        options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers],
        prefersNoSystemAlertInterruptions: false
    )

    init(
        mode: AVAudioSession.Mode,
        options: AVAudioSession.CategoryOptions,
        prefersNoSystemAlertInterruptions: Bool
    ) {
        self.mode = mode
        self.options = options
        self.prefersNoSystemAlertInterruptions = prefersNoSystemAlertInterruptions
    }

    init(_ input: KeptAudioInputOptions) {
        var configuration = Self.standard
        if input.naturalInput {
            configuration.mode = .measurement
        }
        if input.builtInMicrophone {
            configuration.options.remove(.allowBluetooth)
            configuration.options.insert(.allowBluetoothA2DP)
        }
        if input.highQualityBluetooth, !input.builtInMicrophone, #available(iOS 26.0, *) {
            configuration.options.insert(.bluetoothHighQualityRecording)
            configuration.prefersNoSystemAlertInterruptions = true
        }
        self = configuration
    }

    var isStandard: Bool { self == Self.standard }

    /// True when Bluetooth headsets are output only (Stereo, Spatial Audio).
    var prefersBuiltInMicrophone: Bool {
        options.contains(.allowBluetoothA2DP) && !options.contains(.allowBluetooth)
    }

    /// Applies this configuration, or `standard` if the system refuses it.
    /// Returns the configuration that is now active. Throws only if the
    /// standard configuration fails too (as `setCategory` always could).
    @discardableResult
    func apply(to session: AVAudioSession, log: (String) -> Void) throws -> RecordingAudioSessionConfiguration {
        do {
            try set(on: session)
            return self
        } catch where !isStandard {
            log("[RecordingAudioSession] ⚠️ \(describe()) refused (\(error.localizedDescription)); using standard input")
            try Self.standard.set(on: session)
            return Self.standard
        }
    }

    private func set(on session: AVAudioSession) throws {
        try session.setCategory(.playAndRecord, mode: mode, options: options)
        try? session.setPrefersNoInterruptionsFromSystemAlerts(prefersNoSystemAlertInterruptions)
    }

    func describe() -> String {
        var parts = ["mode=\(mode.rawValue)"]
        if prefersBuiltInMicrophone {
            parts.append("builtInMic")
        }
        if #available(iOS 26.0, *), options.contains(.bluetoothHighQualityRecording) {
            parts.append("bluetoothHighQuality")
        }
        return parts.joined(separator: " ")
    }

    /// Whether the current Bluetooth input really records at full bandwidth.
    /// Nil when the input isn't a Bluetooth microphone or before iOS 26.
    static func highQualityBluetoothActive(on session: AVAudioSession) -> Bool? {
        guard #available(iOS 26.0, *),
              let input = session.currentRoute.inputs.first,
              let bluetooth = input.bluetoothMicrophoneExtension else { return nil }
        return bluetooth.highQualityRecording.isEnabled
    }
}
