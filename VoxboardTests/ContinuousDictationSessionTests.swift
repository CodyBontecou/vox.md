import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class ContinuousDictationSessionTests: XCTestCase {

    // MARK: - Session duration cap (battery/thermal guardrail)

    func testDefaultSessionLimitMatchesDocumentedGuardrail() {
        let session = ContinuousDictationSession(startedAt: 1_000)

        XCTAssertEqual(session.sessionLimit, 600)
        XCTAssertEqual(
            session.sessionLimit,
            AppConstants.voiceAutoStopContinuousSessionLimit
        )
    }

    func testSessionStaysCommittableUntilTheLimitAndEndsAtIt() {
        let session = ContinuousDictationSession(startedAt: 1_000, sessionLimit: 600)

        XCTAssertTrue(session.canCommitSegment(isPaused: false, now: 1_599.9))
        XCTAssertFalse(session.hasReachedSessionLimit(now: 1_599.9))

        XCTAssertFalse(session.canCommitSegment(isPaused: false, now: 1_600))
        XCTAssertTrue(session.hasReachedSessionLimit(now: 1_600))
        // Beyond the budget the session stays terminal — a late commit cannot
        // resurrect it.
        XCTAssertFalse(session.canCommitSegment(isPaused: false, now: 2_000))
    }

    // MARK: - Manual pause never commits

    func testManualPauseNeverCommitsMidSession() {
        let session = ContinuousDictationSession(startedAt: 0, sessionLimit: 600)

        XCTAssertFalse(
            session.canCommitSegment(isPaused: true, now: 10),
            "paused dictation must accumulate into the next span instead of committing"
        )
        // Once resumed, commits are allowed again — the session survived.
        XCTAssertTrue(session.canCommitSegment(isPaused: false, now: 10))
    }

    // MARK: - Per-segment delivery identities

    func testDeliveryRequestIDsAdvancePerCommittedSegment() {
        let session = ContinuousDictationSession(startedAt: 0)

        XCTAssertEqual(session.nextDeliveryRequestID(for: "inapp-r"), "inapp-r-c1")
        // The identity is stable until the segment is actually staged, so a
        // failed staging attempt retries with the same delivery ID.
        XCTAssertEqual(session.nextDeliveryRequestID(for: "inapp-r"), "inapp-r-c1")

        session.recordCommittedSegment()
        XCTAssertEqual(session.nextDeliveryRequestID(for: "inapp-r"), "inapp-r-c2")
        XCTAssertEqual(session.committedSegmentCount, 1)
    }

    // MARK: - Span deliverability mirrors the stop path guards

    func testIsDeliverableSpanMirrorsStopPathGuards() {
        // Minimum span: a third of a second at 16 kHz (4,800 samples).
        XCTAssertFalse(ContinuousDictationSession.isDeliverableSpan(
            sampleCount: 4_800,
            maximumAmplitude: 0.5,
            sampleRate: 16_000
        ))
        XCTAssertTrue(ContinuousDictationSession.isDeliverableSpan(
            sampleCount: 4_801,
            maximumAmplitude: 0.5,
            sampleRate: 16_000
        ))
        // Effectively silent spans are skipped rather than delivered.
        XCTAssertFalse(ContinuousDictationSession.isDeliverableSpan(
            sampleCount: 16_000,
            maximumAmplitude: 0.004,
            sampleRate: 16_000
        ))
        XCTAssertTrue(ContinuousDictationSession.isDeliverableSpan(
            sampleCount: 16_000,
            maximumAmplitude: 0.005,
            sampleRate: 16_000
        ))
    }

    // MARK: - Coordinator re-arm from the commit boundary cursor

    func testRearmedCoordinatorIgnoresAudioBeforeItsCursorAndDetectsNextSpeech() async throws {
        let buffer = CircularAudioBuffer(capacity: 40_000)
        let session = FakeContinuousVoiceActivitySession(events: [
            .speechStarted(sampleIndex: 8_192),
            // 13,000 - 8,192 = 4,808 samples ≥ the 0.3 s minimum-speech gate.
            .speechEnded(sampleIndex: 13_000),
        ])
        var endCount = 0
        // A fresh coordinator armed from the commit boundary cursor (8,192).
        let rearmed = VoiceAutoStopCoordinator(
            requestID: "request",
            session: session,
            circularBuffer: buffer,
            startIndex: 8_192
        ) {
            endCount += 1
        }

        // Audio from the committed span still sits in the rolling buffer; the
        // re-armed coordinator must not re-process it.
        buffer.append([Float](repeating: 0.25, count: 8_192))
        try await rearmed.processAvailableAudio()
        var processedFrames = await session.processedFrameCount
        XCTAssertEqual(processedFrames, 0, "pre-cursor audio must not reach the fresh VAD session")

        // The next thought, after the cursor, is detected normally.
        buffer.append([Float](repeating: 0.25, count: 8_192))
        try await rearmed.processAvailableAudio()
        processedFrames = await session.processedFrameCount
        XCTAssertGreaterThanOrEqual(processedFrames, 1)
        XCTAssertEqual(endCount, 1)
        await rearmed.cancel()
    }

    func testFinishedCoordinatorCannotFireAgainWithoutRearm() async throws {
        let buffer = CircularAudioBuffer(capacity: 40_000)
        let session = FakeContinuousVoiceActivitySession(events: [
            .speechStarted(sampleIndex: 0),
            .speechEnded(sampleIndex: 8_000),
        ])
        var endCount = 0
        let coordinator = VoiceAutoStopCoordinator(
            requestID: "request",
            session: session,
            circularBuffer: buffer,
            startIndex: 0
        ) {
            endCount += 1
        }

        buffer.append([Float](repeating: 0.25, count: 8_192))
        try await coordinator.processAvailableAudio()
        XCTAssertEqual(endCount, 1)

        // More speech arrives after the coordinator finished itself: without a
        // re-arm no further end-of-speech fires, proving the loop's fresh
        // coordinator per span is what keeps the session going.
        buffer.append([Float](repeating: 0.25, count: 8_192))
        try await coordinator.processAvailableAudio()
        XCTAssertEqual(endCount, 1)
    }
}

private actor FakeContinuousVoiceActivitySession: VoiceActivityStreamingSession {
    private var events: [VoiceActivityStreamEvent?]
    private var frameCount = 0

    init(events: [VoiceActivityStreamEvent?]) {
        self.events = events
    }

    func process(_ samples: [Float]) async throws -> VoiceActivityStreamEvent? {
        frameCount += 1
        guard !events.isEmpty else { return nil }
        return events.removeFirst()
    }

    var processedFrameCount: Int {
        frameCount
    }
}
