import XCTest
@testable import VoxboardShared

final class RecordingJobRetryDeliveryTests: XCTestCase {
    func testExplicitRouteAlwaysWins() {
        let job = makeJob(url: "")
        let chosen = RecordingJobDelivery.captureDraft(attachAudio: true)
        XCTAssertEqual(RecordingJobRetryDelivery.resolve(for: job, override: chosen) { _ in
            XCTFail("Explicit routing must not consult mutable presets")
            return nil
        }, chosen)
    }

    func testValidFrozenEndpointIsNeverReplacedEvenAfterDeliveryFailure() {
        let job = makeJob(url: "https://example.invalid/original")
        XCTAssertNil(RecordingJobRetryDelivery.resolve(for: job) { _ in
            XCTFail("A valid endpoint must remain frozen")
            return nil
        })
    }

    func testStillInvalidDeletedDisabledOrDifferentTargetPresetDoesNotRepairRoute() {
        let job = makeJob(url: "")
        var current = CapturePreset(id: "http", name: "Current", symbolName: "mic")
        current.exportSettings.urlDelivery = .init(enabled: true, urlString: "")
        XCTAssertNil(RecordingJobRetryDelivery.resolve(for: job) { _ in nil })
        XCTAssertNil(RecordingJobRetryDelivery.resolve(for: job) { _ in current })
        current.exportSettings.urlDelivery.urlString = "https://example.invalid/repaired"
        current.isEnabled = false
        XCTAssertNil(RecordingJobRetryDelivery.resolve(for: job) { _ in current })
        current.isEnabled = true
        current.deliveryTarget = .directory
        XCTAssertNil(RecordingJobRetryDelivery.resolve(for: job) { _ in current })
        current.deliveryTarget = .http
        current.id = "unrelated"
        XCTAssertNil(RecordingJobRetryDelivery.resolve(for: job) { _ in current })
    }

    func testBackgroundQueuedJobAndDirectoryJobNeverConsultCurrentPresets() {
        var job = makeJob(url: "")
        job.phase = .queued
        XCTAssertNil(RecordingJobRetryDelivery.resolve(for: job) { _ in
            XCTFail("Only explicit failed-job retries may repair a route")
            return nil
        })
        job.phase = .failed
        var directoryPreset = CapturePresetStore.makeCustomFlow()
        directoryPreset.deliveryTarget = .directory
        job.delivery = .preset(directoryPreset)
        XCTAssertNil(RecordingJobRetryDelivery.resolve(for: job) { _ in
            XCTFail("Directory policy must remain frozen")
            return nil
        })
    }

    func testInsecureLocalEndpointStillRequiresExplicitConsent() {
        let job = makeJob(url: "")
        var current = CapturePreset(id: "http", name: "Current", symbolName: "mic")
        current.exportSettings.urlDelivery = .init(enabled: true, urlString: "http://127.0.0.1:8080/ingest")
        XCTAssertNil(RecordingJobRetryDelivery.resolve(for: job) { _ in current })
        current.exportSettings.urlDelivery.allowingInsecureLocal = true
        let resolved = RecordingJobRetryDelivery.resolve(for: job) { _ in current }
        guard case .preset(let repaired) = resolved else { return XCTFail("Expected repaired HTTP route") }
        XCTAssertEqual(repaired.exportSettings.urlDelivery, current.exportSettings.urlDelivery)
    }

    private func makeJob(url: String) -> RecordingJob {
        var preset = CapturePreset(id: "http", name: "Original", symbolName: "mic")
        preset.exportSettings.urlDelivery = .init(enabled: true, urlString: url)
        return RecordingJob(
            audioFilename: "retained.wav", duration: 540, source: .iOSApp,
            delivery: .preset(preset), modelID: "automatic", language: "en",
            retentionPolicy: .permanent, processingPolicy: .manual,
            phase: .failed, failureStage: .delivery
        )
    }
}
