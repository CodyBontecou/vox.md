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
}
