import XCTest
@testable import VoxboardShared

final class VoxboardLiveActivityStateTests: XCTestCase {

    func test_defaultState_isIdleAndNotRecording() {
        let state = VoxboardLiveActivityState()
        XCTAssertFalse(state.isSegmentActive)
        XCTAssertFalse(state.isTranscribing)
        XCTAssertNil(state.segmentStartedAt)
        XCTAssertNil(state.segmentRequestId)
        XCTAssertNil(state.transcriptionProgress)
    }

    func test_recordingState_carriesStartTimeAndRequestId() {
        let now = Date().timeIntervalSince1970
        let state = VoxboardLiveActivityState(
            isSegmentActive: true,
            segmentStartedAt: now,
            segmentRequestId: "request-1"
        )
        XCTAssertTrue(state.isSegmentActive)
        XCTAssertFalse(state.isTranscribing)
        XCTAssertEqual(state.segmentStartedAt, now)
        XCTAssertEqual(state.segmentRequestId, "request-1")
        XCTAssertNil(state.transcriptionProgress)
    }

    func test_transcribingState_isNotRecording() {
        let state = VoxboardLiveActivityState(
            isTranscribing: true,
            transcriptionProgress: 0.42
        )
        XCTAssertFalse(state.isSegmentActive)
        XCTAssertTrue(state.isTranscribing)
        XCTAssertNil(state.segmentStartedAt)
        XCTAssertNil(state.segmentRequestId)
        XCTAssertEqual(state.transcriptionProgress, 0.42)
    }

    func test_state_isCodable() throws {
        let original = VoxboardLiveActivityState(
            isSegmentActive: false,
            isTranscribing: true,
            segmentStartedAt: nil,
            segmentRequestId: nil,
            transcriptionProgress: 0.42
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(VoxboardLiveActivityState.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_idle_factory_isNotActive() {
        let state = VoxboardLiveActivityState.idle
        XCTAssertFalse(state.isSegmentActive)
        XCTAssertFalse(state.isTranscribing)
        XCTAssertNil(state.segmentStartedAt)
        XCTAssertNil(state.segmentRequestId)
        XCTAssertNil(state.transcriptionProgress)
    }

    func test_legacyState_decodesWithoutRequestIdOrProgress() throws {
        let data = Data(#"{"isSegmentActive":true,"isTranscribing":false,"segmentStartedAt":12345}"#.utf8)
        let state = try JSONDecoder().decode(VoxboardLiveActivityState.self, from: data)

        XCTAssertTrue(state.isSegmentActive)
        XCTAssertEqual(state.segmentStartedAt, 12_345)
        XCTAssertNil(state.segmentRequestId)
        XCTAssertNil(state.transcriptionProgress)
    }

    func test_transcriptionProgressClampsInInitializer() {
        XCTAssertEqual(
            VoxboardLiveActivityState(
                isTranscribing: true,
                transcriptionProgress: 4
            ).transcriptionProgress,
            1
        )
        XCTAssertNil(
            VoxboardLiveActivityState(
                isTranscribing: true,
                transcriptionProgress: .infinity
            ).transcriptionProgress
        )
    }

    func test_routeAndPauseFields_roundTripAndLegacyDecodeLeavesThemNil() throws {
        let original = VoxboardLiveActivityState(
            isSegmentActive: true,
            segmentStartedAt: 100,
            segmentRequestId: "r",
            routeName: "Meeting Notes",
            routeMonogram: "M",
            destinationPath: "Meetings/2026-11-01.md",
            pausedElapsed: 12,
            canPause: true,
            audioLevels: [0, 50, 100]
        )
        let decoded = try JSONDecoder().decode(
            VoxboardLiveActivityState.self,
            from: JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.isPaused)

        let legacy = try JSONDecoder().decode(
            VoxboardLiveActivityState.self,
            from: Data(#"{"isSegmentActive":true,"isTranscribing":false}"#.utf8)
        )
        XCTAssertNil(legacy.routeName)
        XCTAssertNil(legacy.destinationPath)
        XCTAssertNil(legacy.audioLevels)
        XCTAssertFalse(legacy.isPaused)
    }

    func test_audioLevels_areClampedAndCapped() {
        let state = VoxboardLiveActivityState(
            isSegmentActive: true,
            audioLevels: Array(repeating: 200, count: 100)
        )
        XCTAssertEqual(state.audioLevels?.count, VoxboardLiveActivityState.maximumAudioLevelCount)
        XCTAssertEqual(state.audioLevels?.max(), 100)
        XCTAssertEqual(VoxboardLiveActivityState.encodedLevel(0.5), 50)
        XCTAssertEqual(VoxboardLiveActivityState.encodedLevel(.nan), 0)
        XCTAssertEqual(VoxboardLiveActivityState.encodedLevel(3), 100)
    }

    func test_monogram_prefersInitialThenEmoji() {
        XCTAssertEqual(VoxboardLiveActivityState.monogram(name: "meeting Notes", emoji: nil), "M")
        XCTAssertEqual(VoxboardLiveActivityState.monogram(name: "  ", emoji: "📝"), "📝")
        XCTAssertNil(VoxboardLiveActivityState.monogram(name: nil, emoji: nil))
    }

    // MARK: Recording line window (#189)

    func test_lineWindowStart_advancesOncePerWindowOfRecordedTime() {
        let start: TimeInterval = 1_000
        XCTAssertEqual(VoxboardLiveActivityState.lineWindowStart(effectiveStartedAt: start, elapsed: 0, window: 300), 1_000)
        XCTAssertEqual(VoxboardLiveActivityState.lineWindowStart(effectiveStartedAt: start, elapsed: 299.9, window: 300), 1_000)
        XCTAssertEqual(VoxboardLiveActivityState.lineWindowStart(effectiveStartedAt: start, elapsed: 300, window: 300), 1_300)
        XCTAssertEqual(VoxboardLiveActivityState.lineWindowStart(effectiveStartedAt: start, elapsed: 905, window: 300), 1_900)
        XCTAssertNil(VoxboardLiveActivityState.lineWindowStart(effectiveStartedAt: start, elapsed: 10, window: 0))
        XCTAssertNil(VoxboardLiveActivityState.lineWindowStart(effectiveStartedAt: .nan, elapsed: 10, window: 300))
    }

    func test_lineWindow_resumeContinuesFromPausedFill() {
        // Record 120 s, pause for 60 s, resume. The effective start moves by the
        // paused time, so the fill at resume equals the frozen paused fill.
        let window: TimeInterval = 300
        let paused = VoxboardLiveActivityState(isSegmentActive: true, segmentStartedAt: 1_000, pausedElapsed: 120, lineWindowDuration: window)
        XCTAssertEqual(paused.pausedLineFraction ?? -1, 0.4, accuracy: 0.0001)

        let resumeWallClock: TimeInterval = 1_180
        let effectiveStart = resumeWallClock - 120
        let windowStart = VoxboardLiveActivityState.lineWindowStart(effectiveStartedAt: effectiveStart, elapsed: 120, window: window)!
        XCTAssertEqual((resumeWallClock - windowStart) / window, 0.4, accuracy: 0.0001)
    }

    func test_pausedLineFraction_wrapsAndIsNilWhileRecording() {
        let paused = VoxboardLiveActivityState(isSegmentActive: true, pausedElapsed: 330, lineWindowDuration: 300)
        XCTAssertEqual(paused.pausedLineFraction ?? -1, 0.1, accuracy: 0.0001)
        let defaultWindow = VoxboardLiveActivityState(isSegmentActive: true, pausedElapsed: 150)
        XCTAssertEqual(defaultWindow.pausedLineFraction ?? -1, 0.5, accuracy: 0.0001)
        XCTAssertNil(VoxboardLiveActivityState(isSegmentActive: true, segmentStartedAt: 1).pausedLineFraction)
        XCTAssertNil(VoxboardLiveActivityState(lineWindowDuration: -1).lineWindowDuration)
    }

    func test_lineWindowNeedsUpdate_onceWhenMissingOrNextWindow() {
        // Missing window (first state sent before the segment context): push once.
        XCTAssertTrue(VoxboardLiveActivityState.lineWindowNeedsUpdate(shown: nil, current: 1_000))
        // Same window: no update.
        XCTAssertFalse(VoxboardLiveActivityState.lineWindowNeedsUpdate(shown: 1_000, current: 1_000))
        XCTAssertFalse(VoxboardLiveActivityState.lineWindowNeedsUpdate(shown: 1_000, current: 1_000.3))
        // Next window: one update.
        XCTAssertTrue(VoxboardLiveActivityState.lineWindowNeedsUpdate(shown: 1_000, current: 1_300))
        // No computable window: nothing to send.
        XCTAssertFalse(VoxboardLiveActivityState.lineWindowNeedsUpdate(shown: nil, current: nil))
    }
}
