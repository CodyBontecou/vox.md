import XCTest
@testable import VoxboardShared

@MainActor
final class RecordingRouteOwnershipTests: XCTestCase {
    func testImportLeaseIsVisibleBeforeAnyTranscriptionJobExists() throws {
        let queue = try makeQueue()
        XCTAssertFalse(queue.isCaptureActive)
        let lease = queue.beginCaptureLease()
        XCTAssertTrue(queue.isCaptureActive)
        XCTAssertFalse(queue.isProcessing)
        XCTAssertNil(queue.activeJobID)
        queue.endCaptureLease(lease)
        XCTAssertFalse(queue.isCaptureActive)
    }

    func testLegacyCaptureAndOverlappingLeasesCannotReleaseEachOther() throws {
        let queue = try makeQueue()
        queue.setCaptureActive(true)
        let start = queue.beginCaptureLease()
        let finalization = queue.beginCaptureLease()
        queue.setCaptureActive(false)
        XCTAssertTrue(queue.isCaptureActive)
        queue.endCaptureLease(start)
        XCTAssertTrue(queue.isCaptureActive)
        queue.endCaptureLease(start)
        XCTAssertTrue(queue.isCaptureActive)
        queue.endCaptureLease(finalization)
        XCTAssertFalse(queue.isCaptureActive)
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
