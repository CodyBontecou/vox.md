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

    // MARK: Recording line window

    /// Wall-clock start of the current recording-line window. The Live
    /// Activity fills its red line with `ProgressView(timerInterval:)` from
    /// here to `lineWindowStart + lineWindowDuration`, so the system animates
    /// it with no app updates; the app sends one update per window to start
    /// the next one. Nil while paused (the line freezes at `pausedLineFraction`).
    public var lineWindowStart: TimeInterval?
    /// Length of one recording-line window, in seconds.
    public var lineWindowDuration: TimeInterval?

    public static let maximumAudioLevelCount = 40
    /// Default recording-line window: the line fills once every 5 minutes.
    public static let defaultLineWindowDuration: TimeInterval = 300

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
        audioLevels: [UInt8]? = nil,
        lineWindowStart: TimeInterval? = nil,
        lineWindowDuration: TimeInterval? = nil
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
        self.lineWindowStart = lineWindowStart.flatMap { $0.isFinite ? $0 : nil }
        self.lineWindowDuration = lineWindowDuration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    public var isPaused: Bool { isSegmentActive && pausedElapsed != nil }

    /// Start of the window that contains `elapsed` recorded seconds, as wall
    /// clock time. `effectiveStartedAt` is the wall-clock start minus recorded
    /// time, so paused time never counts and the fill resumes where it froze.
    public static func lineWindowStart(
        effectiveStartedAt: TimeInterval,
        elapsed: TimeInterval,
        window: TimeInterval
    ) -> TimeInterval? {
        guard effectiveStartedAt.isFinite, elapsed.isFinite, window.isFinite, window > 0 else {
            return nil
        }
        let index = (max(0, elapsed) / window).rounded(.down)
        return effectiveStartedAt + index * window
    }

    /// True when the shown line window must be replaced: recorded time has
    /// moved into a later window, or no window was sent yet (e.g. the first
    /// state went out before the recorder's segment context existed).
    public static func lineWindowNeedsUpdate(
        shown: TimeInterval?,
        current: TimeInterval?
    ) -> Bool {
        guard let current else { return false }
        guard let shown else { return true }
        return current > shown + 0.5
    }

    /// Fraction (0..<1) of the current window filled after `elapsed` recorded seconds.
    public static func lineWindowFraction(elapsed: TimeInterval, window: TimeInterval) -> Double {
        guard elapsed.isFinite, window.isFinite, window > 0 else { return 0 }
        let remainder = max(0, elapsed).truncatingRemainder(dividingBy: window)
        return min(1, max(0, remainder / window))
    }

    /// Frozen fill of the recording line while paused.
    public var pausedLineFraction: Double? {
        guard isPaused, let pausedElapsed else { return nil }
        return Self.lineWindowFraction(
            elapsed: pausedElapsed,
            window: lineWindowDuration ?? Self.defaultLineWindowDuration
        )
    }

    /// Converts a normalized 0...1 level to the compact wire value.
    public static func encodedLevel(_ level: Float) -> UInt8 {
        guard level.isFinite else { return 0 }
        return UInt8((min(1, max(0, level)) * 100).rounded())
    }

    /// Single display glyph for a route tile: the first initial of the visible
    /// name, else the emoji, else nil.
    public static func monogram(name: String?, emoji: String?) -> String? {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return routeInitial(of: trimmed) }
        let trimmedEmoji = emoji?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedEmoji.isEmpty ? nil : trimmedEmoji
    }

    /// First letter of a route name for its tile. Skips the Arabic definite article
    /// ("ال"), which otherwise gives every Arabic route the same "ا" tile.
    public static func routeInitial(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = trimmed.hasPrefix("ال") && trimmed.count > 2 ? String(trimmed.dropFirst(2)) : trimmed
        return body.first.map { String($0).uppercased() } ?? ""
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
