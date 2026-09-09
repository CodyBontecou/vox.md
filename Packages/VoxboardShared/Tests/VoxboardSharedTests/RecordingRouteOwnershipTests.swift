import XCTest
@testable import VoxboardShared

@MainActor
final class RecordingRouteOwnershipTests: XCTestCase {
    func testImportLeaseIsVisibleBeforeAnyTranscriptionJobExists() throws {
        let queue = try makeQueue()
        XCTAssertFalse(queue.isCaptureActive)
        XCTAssertFalse(queue.ownsCaptureRoute)
        XCTAssertFalse(queue.blocksCapturePresetSelection)
        let lease = queue.beginCaptureLease()
        XCTAssertTrue(queue.isCaptureActive)
        XCTAssertTrue(queue.ownsCaptureRoute)
        XCTAssertTrue(queue.blocksCapturePresetSelection)
        XCTAssertFalse(queue.isProcessing)
        XCTAssertNil(queue.activeJobID)
        queue.endCaptureLease(lease)
        XCTAssertFalse(queue.isCaptureActive)
        XCTAssertFalse(queue.ownsCaptureRoute)
        XCTAssertFalse(queue.blocksCapturePresetSelection)
    }

    func testScheduledEmptyDrainDoesNotOwnCaptureRoute() throws {
        let queue = try makeQueue()
        queue.resume(includeIdle: true)

        // Scheduling creates the worker task synchronously, before that task can
        // scan or claim a job on the main actor. This is the cold-launch state
        // that must not reject a pending Lock Screen Quick Record.
        XCTAssertTrue(queue.isProcessing)
        XCTAssertNil(queue.activeJobID)
        XCTAssertFalse(queue.ownsCaptureRoute)
        XCTAssertFalse(queue.blocksCapturePresetSelection)
        queue.interruptForSystemExpiration()
    }

    func testLegacyCaptureAndOverlappingLeasesCannotReleaseEachOther() throws {
        let queue = try makeQueue()
        queue.setCaptureActive(true)
        let start = queue.beginCaptureLease()
        let finalization = queue.beginCaptureLease()
        queue.setCaptureActive(false)
        XCTAssertTrue(queue.isCaptureActive)
        XCTAssertTrue(queue.ownsCaptureRoute)
        XCTAssertTrue(queue.blocksCapturePresetSelection)
        queue.endCaptureLease(start)
        XCTAssertTrue(queue.isCaptureActive)
        XCTAssertTrue(queue.ownsCaptureRoute)
        queue.endCaptureLease(start)
        XCTAssertTrue(queue.isCaptureActive)
        XCTAssertTrue(queue.ownsCaptureRoute)
        queue.endCaptureLease(finalization)
        XCTAssertFalse(queue.isCaptureActive)
        XCTAssertFalse(queue.ownsCaptureRoute)
        XCTAssertFalse(queue.blocksCapturePresetSelection)
    }

    private func makeQueue() throws -> RecordingJobQueue {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecordingRouteOwnershipTests-\(UUID().uuidString)", isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RecordingJobQueue(store: RecordingJobStore(
            rootDirectoryURL: root,
            coordinator: ProcessLocalCaptureFileCoordinator()
        )) { _, _, _ in RecordingJobExecutionResult() }
    }
}
