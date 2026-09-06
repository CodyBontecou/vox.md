import Foundation
import VoxboardShared

/// Deterministic decision bookkeeping for one continuous-dictation session.
///
/// Continuous mode turns end-of-speech into a segment commit instead of a
/// session end: `PersistentRecorder` keeps the microphone and the recording
/// segment alive, closes the finished span through the standard delivery
/// handoff, and re-arms a fresh `VoiceAutoStopCoordinator` from the buffer
/// cursor. This type owns the loop's decisions — the wall-clock session
/// budget, per-segment delivery identities, span deliverability, and the
/// manual-pause guard — so they can be tested without a microphone.
///
/// The session limit exists because end-of-speech no longer turns the
/// microphone off: a live mic, streaming speech recognition, and VAD inference
/// left running indefinitely would drain the battery and build thermal
/// pressure. When the budget is spent, the recorder ends the session through
/// the standard stop path so the final span still delivers.
@MainActor
final class ContinuousDictationSession {
    /// Maximum wall-clock duration of the continuous session, measured from
    /// the first arm. Defaults to
    /// `AppConstants.voiceAutoStopContinuousSessionLimit` (10 minutes).
    let sessionLimit: TimeInterval

    private let startedAt: TimeInterval
    /// Number of spans committed through the delivery handoff so far. Drives
    /// the per-segment delivery identities minted for the durable queue.
    private(set) var committedSegmentCount: Int = 0

    init(
        startedAt: TimeInterval,
        sessionLimit: TimeInterval = AppConstants.voiceAutoStopContinuousSessionLimit
    ) {
        self.startedAt = startedAt
        self.sessionLimit = sessionLimit
    }

    func hasReachedSessionLimit(now: TimeInterval) -> Bool {
        now - startedAt >= sessionLimit
    }

    /// A commit is allowed only while the session is within its budget and the
    /// recorder is actively recording. Paused dictation never commits: the
    /// paused span keeps accumulating into the next committed segment once
    /// resumed, which is the existing deliberate pause behavior.
    func canCommitSegment(isPaused: Bool, now: TimeInterval) -> Bool {
        guard !isPaused, !hasReachedSessionLimit(now: now) else { return false }
        return true
    }

    /// Delivery identities derive from the recorder's segment request so
    /// committed spans stay traceable to their session ("-c1", "-c2", …) while
    /// remaining unique for the durable queue, usage receipts, and the Capture
    /// draft's transcript de-duplication ledger.
    func nextDeliveryRequestID(for baseRequestID: String) -> String {
        "\(baseRequestID)-c\(committedSegmentCount + 1)"
    }

    /// Marks the span handed to the delivery pipeline as committed. Called
    /// only once the span has actually been staged (WAV written), so a failed
    /// staging attempt can retry with the same delivery identity.
    func recordCommittedSegment() {
        committedSegmentCount += 1
    }

    /// Mirrors the manual stop path's minimum-span guards: spans shorter than
    /// a third of a second or effectively silent are skipped rather than
    /// delivered as notes, without ending the continuous session.
    static func isDeliverableSpan(
        sampleCount: Int,
        maximumAmplitude: Float,
        sampleRate: Double
    ) -> Bool {
        sampleCount > Int(sampleRate * 0.3) && maximumAmplitude >= 0.005
    }
}
