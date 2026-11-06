import Foundation

#if os(iOS)
import ActivityKit
#endif

/// Serializable state shared by the Live Activity's lock-screen banner and
/// Dynamic Island presentations. Kept platform-independent so it can be
/// unit-tested without ActivityKit.
public struct VoxboardLiveActivityState: Codable, Hashable, Sendable {
    public var isSegmentActive: Bool
    public var isTranscribing: Bool
    public var segmentStartedAt: TimeInterval?
    /// Recorder-owned segment identity used by the Stop intent. Optional so
    /// activities created by older app versions still decode safely.
    public var segmentRequestId: String?
    /// Exact source-audio coverage while transcribing, or nil for an
    /// indeterminate backend/preparation phase.
    public var transcriptionProgress: Double?

    // MARK: Route context (all optional so older encoded states still decode)

    /// Visible name of the Route the segment will be delivered to.
    public var routeName: String?
    /// One-glyph route tile (first initial or emoji).
    public var routeMonogram: String?
    /// Destination preview shown as "→ path", e.g. `Meetings/2026-11-01.md`.
    public var destinationPath: String?

    // MARK: Pause + waveform

    /// Non-nil while the segment is paused: the recorded time to freeze the
    /// timer at. `segmentStartedAt` is always the *effective* start (wall
    /// clock minus recorded time) so `start + pausedElapsed` is the pause time.
    public var pausedElapsed: TimeInterval?
    /// True when the recorder supports pausing this segment (app-owned
    /// recordings). Keyboard dictation cannot be paused.
    public var canPause: Bool?
    /// Recent microphone level history, oldest first, each 0...100.
    public var audioLevels: [UInt8]?

    public static let maximumAudioLevelCount = 40

    public init(
        isSegmentActive: Bool = false,
        isTranscribing: Bool = false,
        segmentStartedAt: TimeInterval? = nil,
        segmentRequestId: String? = nil,
        transcriptionProgress: Double? = nil,
        routeName: String? = nil,
        routeMonogram: String? = nil,
        destinationPath: String? = nil,
        pausedElapsed: TimeInterval? = nil,
        canPause: Bool? = nil,
        audioLevels: [UInt8]? = nil
    ) {
        self.isSegmentActive = isSegmentActive
        self.isTranscribing = isTranscribing
        self.segmentStartedAt = segmentStartedAt
        self.segmentRequestId = segmentRequestId
        self.transcriptionProgress = transcriptionProgress.flatMap {
            $0.isFinite ? min(1, max(0, $0)) : nil
        }
        self.routeName = routeName
        self.routeMonogram = routeMonogram
        self.destinationPath = destinationPath
        self.pausedElapsed = pausedElapsed.flatMap { $0.isFinite ? max(0, $0) : nil }
        self.canPause = canPause
        self.audioLevels = audioLevels.map {
            Array($0.suffix(Self.maximumAudioLevelCount).map { min($0, 100) })
        }
    }

    public var isPaused: Bool { isSegmentActive && pausedElapsed != nil }

    /// Converts a normalized 0...1 level to the compact wire value.
    public static func encodedLevel(_ level: Float) -> UInt8 {
        guard level.isFinite else { return 0 }
        return UInt8((min(1, max(0, level)) * 100).rounded())
    }

    /// Single display glyph for a route tile: the first initial of the visible
    /// name, else the emoji, else nil.
    public static func monogram(name: String?, emoji: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if let first = trimmed.first { return String(first).uppercased() }
        let trimmedEmoji = emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedEmoji.isEmpty ? nil : trimmedEmoji
    }

    public static let idle = VoxboardLiveActivityState(
        isSegmentActive: false,
        isTranscribing: false,
        segmentStartedAt: nil,
        segmentRequestId: nil,
        transcriptionProgress: nil
    )
}

/// Lock Screen widget kinds shared by the app (reloads) and the extension.
public enum VoxboardRouteWidgetKinds {
    public static let speak = "VoxboardRouteSpeakWidget"
    public static let today = "VoxboardRouteTodayWidget"
    public static let scan = "VoxboardRouteScanWidget"
}

#if os(iOS)
@available(iOS 16.1, *)
public struct VoxboardActivityAttributes: ActivityAttributes {
    public typealias ContentState = VoxboardLiveActivityState
    public init() {}
}
#endif
