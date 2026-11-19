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

    /// Target AAC bit rate, when the format uses one.
    public var encoderBitRate: Int? {
        switch self {
        case .high: return 64_000
        case .speech, .lossless: return nil
        }
    }

    /// Bit depth of the lossless encoding.
    public static let losslessBitDepth = 16

    /// Rough size of one minute of kept audio, used for the storage hint.
    /// Speech and High are AAC bit rates; Lossless assumes ALAC compresses
    /// 16-bit 48 kHz mono PCM (5.76 MB/min) to roughly half.
    public var approximateBytesPerMinute: Int {
        switch self {
        case .speech: return 240_000
        case .high: return 480_000
        case .lossless: return 2_900_000
        }
    }

    /// Megabytes per minute for the storage hint, formatted for the current
    /// locale ("0.5", "3"). The app wraps it in its localized "≈ … MB/min".
    public var approximateMegabytesPerMinuteText: String {
        let megabytes = Double(approximateBytesPerMinute) / 1_000_000
        if megabytes >= 1 {
            return megabytes.formatted(.number.precision(.fractionLength(0)))
        }
        return megabytes.formatted(.number.precision(.fractionLength(1)))
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
    public var recorderSettings: [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: Int(formatID),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1,
        ]
        switch self {
        case .speech:
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        case .high:
            settings[AVEncoderBitRateKey] = encoderBitRate ?? 64_000
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        case .lossless:
            settings[AVEncoderBitDepthHintKey] = Self.losslessBitDepth
        }
        return settings
    }
    #endif
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

    public static func requiredFreeBytes(for quality: RecordingQuality) -> Int64 {
        minimumFreeBytes + Int64(quality.approximateBytesPerMinute) * Int64(reservedRecordingMinutes)
    }

    /// Quality to record with, given free space on the recordings volume.
    /// Unknown free space keeps the request; Speech is never downgraded.
    public static func effectiveQuality(
        requested: RecordingQuality,
        availableBytes: Int64?
    ) -> RecordingQuality {
        guard requested != .speech, let availableBytes else { return requested }
        let candidates: [RecordingQuality] = requested == .lossless ? [.lossless, .high] : [.high]
        return candidates.first { availableBytes >= requiredFreeBytes(for: $0) } ?? .speech
    }

    /// Free space on the volume holding `url`, if the system reports it.
    public static func availableBytes(at url: URL) -> Int64? {
        guard let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
            .volumeAvailableCapacity else { return nil }
        return Int64(capacity)
    }
}
