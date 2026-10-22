import Foundation
import VoxboardShared

/// Deterministic decision bookkeeping for one continuous-dictation session.
///
/// Continuous mode turns end-of-speech into a segment commit instead of a
/// session end: `PersistentRecorder` keeps the microphone and the recording
/// segment alive, closes the finished span through the standard delivery
/// handoff, and re-arms a fresh `VoiceAutoStopCoordinator` from the buffer
/// cursor. This type owns per-segment delivery identities and span
/// deliverability. Sessions continue until explicitly stopped.
@MainActor
final class ContinuousDictationSession {
    private(set) var committedSegmentCount: Int = 0

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

    /// Every nonempty span contains audio worth preserving. Duration and
    /// amplitude cannot establish whether the sounds matter to the user.
    static func isDeliverableSpan(
        sampleCount: Int,
        maximumAmplitude _: Float,
        sampleRate _: Double
    ) -> Bool {
        sampleCount > 0
    }
}
