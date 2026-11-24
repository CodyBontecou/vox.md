import Foundation
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Quality of the audio Vox.md keeps after a recording.
///
/// Transcription always runs on a 16 kHz mono copy, whatever is chosen here.
/// `speech` keeps today's 16 kHz file; `high` and `lossless` keep a 48 kHz
/// recording for people who use the audio itself as the record of a call or
/// meeting. The setting applies to new recordings only.
public enum RecordingQuality: String, CaseIterable, Codable, Sendable, Identifiable {
    /// 16 kHz mono AAC. Matches what the transcription engines need.
    case speech
    /// 48 kHz mono AAC at about 64 kbps.
    case high
    /// 48 kHz mono Apple Lossless (ALAC).
    case lossless

    public static let `default`: RecordingQuality = .speech

    /// Shared-defaults key on iPhone and the Watch-local defaults key.
    public static let defaultsKey = "recordingQuality"

    /// Watch payload key used to sync the iPhone setting to Apple Watch.
    public static let watchPayloadKey = "recordingQuality"

    public var id: String { rawValue }

    /// Sample rate of the kept recording.
    public var sampleRate: Double {
        switch self {
        case .speech: return 16_000
        case .high, .lossless: return 48_000
        }
    }

    /// True when the kept audio is recorded separately from the 16 kHz
    /// transcription stream.
    public var recordsSeparateKeptAudio: Bool { self != .speech }

    /// Kept recordings are always `.m4a` (AAC and ALAC share the container), so
    /// file links and Recording Only exports keep the same extension.
    public var fileExtension: String { "m4a" }

    /// Target AAC bit rate, when the format uses one. Stereo doubles it so
    /// each channel keeps the mono rate.
    public func encoderBitRate(channelCount: Int = 1) -> Int? {
        switch self {
        case .high: return 64_000 * max(1, channelCount)
        case .speech, .lossless: return nil
        }
    }

    /// Target AAC bit rate of a mono recording, when the format uses one.
    public var encoderBitRate: Int? { encoderBitRate(channelCount: 1) }

    /// True when the Stereo setting can apply to this quality. Speech stays
    /// 16 kHz mono: it is the transcription format.
    public var supportsStereo: Bool { recordsSeparateKeptAudio }

    /// Bit depth of the lossless encoding.
    public static let losslessBitDepth = 16

    /// Rough size of one minute of kept audio, used for the storage hint.
    /// Speech and High are AAC bit rates; Lossless assumes ALAC compresses
    /// 16-bit 48 kHz mono PCM (5.76 MB/min) to roughly half. Stereo doubles
    /// High and Lossless; Speech is always mono.
    public func approximateBytesPerMinute(channelCount: Int) -> Int {
        let channels = supportsStereo ? max(1, channelCount) : 1
        switch self {
        case .speech: return 240_000
        case .high: return 480_000 * channels
        case .lossless: return 2_900_000 * channels
        }
    }

    /// Rough size of one minute of mono kept audio.
    public var approximateBytesPerMinute: Int { approximateBytesPerMinute(channelCount: 1) }

    /// Megabytes per minute for the storage hint ("0.5", "3"), formatted for
    /// `locale`. The app passes the locale of its UI language so the number
    /// matches the localized "≈ … MB/min" around it.
    public func approximateMegabytesPerMinuteText(
        channelCount: Int = 1,
        locale: Locale = .current
    ) -> String {
        let megabytes = Double(approximateBytesPerMinute(channelCount: channelCount)) / 1_000_000
        // Decide on the rounded value so 0.96 reads "1", not "1.0".
        let digits = (megabytes * 10).rounded() / 10 >= 1 ? 0 : 1
        return megabytes.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }

    public static func load(from defaults: UserDefaults?) -> RecordingQuality {
        guard let raw = defaults?.string(forKey: defaultsKey),
              let quality = RecordingQuality(rawValue: raw) else { return .default }
        return quality
    }

    public static func save(_ quality: RecordingQuality, to defaults: UserDefaults?) {
        defaults?.set(quality.rawValue, forKey: defaultsKey)
    }

    #if canImport(AVFoundation)
    /// Core Audio format of the kept recording.
    public var formatID: AudioFormatID {
        switch self {
        case .speech, .high: return kAudioFormatMPEG4AAC
        case .lossless: return kAudioFormatAppleLossless
        }
    }

    /// Settings for `AVAudioRecorder` / `AVAudioFile(forWriting:)`.
    ///
    /// `speech` is exactly the 16 kHz AAC configuration the Watch has always
    /// used, so choosing it keeps file format and size unchanged.
    public var recorderSettings: [String: Any] { recorderSettings(channelCount: 1) }

    /// Settings for a kept recording with `channelCount` channels (1 or 2).
    /// Speech ignores the count and stays mono.
    public func recorderSettings(channelCount: Int) -> [String: Any] {
        let channels = supportsStereo ? min(max(1, channelCount), 2) : 1
        var settings: [String: Any] = [
            AVFormatIDKey: Int(formatID),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
        ]
        switch self {
        case .speech:
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        case .high:
            settings[AVEncoderBitRateKey] = encoderBitRate(channelCount: channels) ?? 64_000
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        case .lossless:
            settings[AVEncoderBitDepthHintKey] = Self.losslessBitDepth
        }
        return settings
    }
    #endif
}

/// iPhone setting that records High and Lossless in stereo from the built-in
/// microphones. It is stored next to `RecordingQuality` on iPhone and is never
/// synced to Apple Watch, which has a single microphone and stays mono.
///
/// Stereo is a request: the recorder falls back to mono, without failing the
/// recording, when the input is an external, Bluetooth or AirPods microphone or
/// the device has no stereo polar pattern.
public enum StereoRecordingPreference {
    public static let defaultsKey = "recordingStereo"

    public static func load(from defaults: UserDefaults?) -> Bool {
        defaults?.bool(forKey: defaultsKey) ?? false
    }

    public static func save(_ enabled: Bool, to defaults: UserDefaults?) {
        defaults?.set(enabled, forKey: defaultsKey)
    }

    /// True when a recording at `quality` should ask for stereo input.
    public static func requestsStereo(quality: RecordingQuality, enabled: Bool) -> Bool {
        enabled && quality.supportsStereo
    }

    /// Channel count used for storage hints and the storage guard.
    public static func requestedChannelCount(quality: RecordingQuality, enabled: Bool) -> Int {
        requestsStereo(quality: quality, enabled: enabled) ? 2 : 1
    }
}

/// iPhone setting that records High and Lossless with less of iOS's built-in
/// input processing (the `.measurement` session mode instead of `.default`),
/// for music, nature and room sound. Off by default; stored next to
/// `RecordingQuality` and never synced to Apple Watch.
///
/// The transcription stream comes from the same microphone input, so this is
/// opt-in: quiet speech can come out quieter without the automatic gain.
public enum NaturalRecordingPreference {
    public static let defaultsKey = "recordingNatural"

    public static func load(from defaults: UserDefaults?) -> Bool {
        defaults?.bool(forKey: defaultsKey) ?? false
    }

    public static func save(_ enabled: Bool, to defaults: UserDefaults?) {
        defaults?.set(enabled, forKey: defaultsKey)
    }

    /// True when a recording at `quality` in `layout` should use the natural
    /// input mode. Mono only: in the `.measurement` mode iOS offers no stereo
    /// polar pattern on the built-in microphones (seen on iPhone 13 Pro Max,
    /// iOS 27.2), so Natural would silently turn Stereo into mono. Stereo and
    /// Spatial Audio win and keep the standard mode.
    public static func requestsNatural(
        quality: RecordingQuality,
        enabled: Bool,
        layout: RecordingChannelLayout = .mono
    ) -> Bool {
        enabled && quality.recordsSeparateKeptAudio && layout == .mono
    }
}

/// Microphone options for the iPhone audio session, decided when listening
/// starts. Only a one-shot recording that can keep its audio (`eligible`) gets
/// anything beyond the standard session; Keyboard Listening and dictation keep
/// today's input so their transcripts don't change.
public struct KeptAudioInputOptions: Equatable, Sendable {
    /// Ask for full-bandwidth Bluetooth recording (iOS 26, supported AirPods),
    /// with the hands-free profile as the fallback. Automatic for High and
    /// Lossless: their whole point is a better saved file.
    public var highQualityBluetooth: Bool
    /// Use the `.measurement` session mode (see `NaturalRecordingPreference`).
    public var naturalInput: Bool

    public init(highQualityBluetooth: Bool = false, naturalInput: Bool = false) {
        self.highQualityBluetooth = highQualityBluetooth
        self.naturalInput = naturalInput
    }

    public static let standard = KeptAudioInputOptions()

    /// `layout` is the stored channel layout; anything but mono keeps the
    /// standard mode (see `NaturalRecordingPreference.requestsNatural`).
    public static func forRecording(
        quality: RecordingQuality,
        eligible: Bool,
        naturalEnabled: Bool,
        layout: RecordingChannelLayout = .mono
    ) -> KeptAudioInputOptions {
        guard eligible, quality.recordsSeparateKeptAudio else { return .standard }
        return KeptAudioInputOptions(
            highQualityBluetooth: true,
            naturalInput: NaturalRecordingPreference.requestsNatural(
                quality: quality,
                enabled: naturalEnabled,
                layout: layout
            )
        )
    }
}

/// Keeps High/Lossless from filling a device (Apple Watch above all), where a
/// long take waits on disk until it reaches iPhone. Before recording, the
/// requested quality must leave room for `reservedRecordingMinutes` of audio
/// on top of `minimumFreeBytes`. If it doesn't, the recorder steps down
/// (Lossless → High → Speech) instead of failing mid-take or mid-transfer.
public enum RecordingQualityStorageGuard {
    /// Length of recording the free space must cover before starting.
    public static let reservedRecordingMinutes = 90
    /// Space always left for the system, the transfer queue and other apps.
    public static let minimumFreeBytes: Int64 = 200_000_000

    public static func requiredFreeBytes(for quality: RecordingQuality, channelCount: Int = 1) -> Int64 {
        minimumFreeBytes
            + Int64(quality.approximateBytesPerMinute(channelCount: channelCount)) * Int64(reservedRecordingMinutes)
    }

    /// Quality to record with, given free space on the recordings volume.
    /// Unknown free space keeps the request; Speech is never downgraded.
    /// `channelCount` is the requested layout (2 for stereo); the space check
    /// covers that many channels.
    public static func effectiveQuality(
        requested: RecordingQuality,
        availableBytes: Int64?,
        channelCount: Int = 1
    ) -> RecordingQuality {
        guard requested != .speech, let availableBytes else { return requested }
        let candidates: [RecordingQuality] = requested == .lossless ? [.lossless, .high] : [.high]
        return candidates.first {
            availableBytes >= requiredFreeBytes(for: $0, channelCount: channelCount)
        } ?? .speech
    }

    /// Free space on the volume holding `url`, if the system reports it.
    public static func availableBytes(at url: URL) -> Int64? {
        guard let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            .volumeAvailableCapacity else { return nil }
        return Int64(capacity)
    }
}
