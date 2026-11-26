import Foundation

/// Channel layout of a High or Lossless kept recording on iPhone (#118, #133).
///
/// Stored as two booleans next to `RecordingQuality`: the existing
/// `recordingStereo` key and `recordingSpatialAudio`. Saving a layout writes
/// both, so they are never on together, and a build that only knows about
/// Stereo reads a Spatial choice as mono. Neither key is synced to Apple
/// Watch, which has one microphone and always records mono.
///
/// Every layout other than mono is a request. The recorder falls back
/// (Spatial → Stereo → mono) without failing the recording when the device,
/// the input route or the capture setup can't provide it.
public enum RecordingChannelLayout: String, CaseIterable, Codable, Sendable, Identifiable {
    case mono
    case stereo
    /// First-order ambisonics from the built-in microphones (iOS 26+, on
    /// iPhones whose microphones support it), with a stereo track for players
    /// that can't render spatial audio.
    case spatial

    public var id: String { rawValue }

    /// Shared-defaults key for the Spatial Audio choice. Never synced to Watch.
    public static let spatialDefaultsKey = "recordingSpatialAudio"

    public static func load(from defaults: UserDefaults?) -> RecordingChannelLayout {
        if defaults?.bool(forKey: spatialDefaultsKey) == true { return .spatial }
        return StereoRecordingPreference.load(from: defaults) ? .stereo : .mono
    }

    public static func save(_ layout: RecordingChannelLayout, to defaults: UserDefaults?) {
        defaults?.set(layout == .spatial, forKey: spatialDefaultsKey)
        StereoRecordingPreference.save(layout == .stereo, to: defaults)
    }

    /// The layout a new recording at `quality` asks for. Speech is always mono
    /// (it is the transcription format). A stored Spatial choice on a device
    /// that can't record it (an older iPhone, iOS before 26, a restored
    /// backup) asks for Stereo instead.
    public static func requested(
        quality: RecordingQuality,
        stored: RecordingChannelLayout,
        spatialAvailable: Bool
    ) -> RecordingChannelLayout {
        guard quality.supportsStereo else { return .mono }
        if stored == .spatial, !spatialAvailable { return .stereo }
        return stored
    }

    /// What the recorder falls back to when this layout can't be set up.
    /// Spatial falls back to Stereo, which itself falls back to mono.
    public var fallback: RecordingChannelLayout? {
        switch self {
        case .spatial: return .stereo
        case .stereo: return .mono
        case .mono: return nil
        }
    }

    /// Channels of the stereo-or-mono audio in the kept file. A spatial file
    /// also carries a stereo track, which is what non-spatial players play.
    public var compatibilityChannelCount: Int { self == .mono ? 1 : 2 }

    /// Rough size of one minute of the first-order ambisonics (APAC) track of
    /// a spatial recording. The encoder's rate depends on the capture
    /// settings iOS recommends; this assumes about 256 kbps for four channels.
    public static let spatialTrackBytesPerMinute = 1_920_000

    /// Rough size of one minute of kept audio at `quality` in this layout.
    /// Spatial is the stereo file (AAC for High, ALAC for Lossless) plus the
    /// ambisonics track.
    public func approximateBytesPerMinute(quality: RecordingQuality) -> Int {
        let compatibility = quality.approximateBytesPerMinute(channelCount: compatibilityChannelCount)
        guard self == .spatial, quality.supportsStereo else { return compatibility }
        return compatibility + Self.spatialTrackBytesPerMinute
    }

    /// Megabytes per minute for the storage hint, formatted like
    /// `RecordingQuality.approximateMegabytesPerMinuteText`.
    public func approximateMegabytesPerMinuteText(
        quality: RecordingQuality,
        locale: Locale = .current
    ) -> String {
        let megabytes = Double(approximateBytesPerMinute(quality: quality)) / 1_000_000
        // Decide on the rounded value so 0.96 reads "1", not "1.0".
        let digits = (megabytes * 10).rounded() / 10 >= 1 ? 0 : 1
        return megabytes.formatted(.number.precision(.fractionLength(digits)).locale(locale))
    }
}

extension RecordingQualityStorageGuard {
    /// Free space a recording at `quality` in `layout` needs before it starts.
    public static func requiredFreeBytes(for quality: RecordingQuality, layout: RecordingChannelLayout) -> Int64 {
        minimumFreeBytes
            + Int64(layout.approximateBytesPerMinute(quality: quality)) * Int64(reservedRecordingMinutes)
    }

    /// Quality to record with in `layout`, given free space on the recordings
    /// volume. Same rules as `effectiveQuality(requested:availableBytes:channelCount:)`
    /// (Lossless → High → Speech), with the spatial track counted.
    public static func effectiveQuality(
        requested: RecordingQuality,
        availableBytes: Int64?,
        layout: RecordingChannelLayout
    ) -> RecordingQuality {
        guard requested != .speech, let availableBytes else { return requested }
        let candidates: [RecordingQuality] = requested == .lossless ? [.lossless, .high] : [.high]
        return candidates.first {
            availableBytes >= requiredFreeBytes(for: $0, layout: layout)
        } ?? .speech
    }
}
