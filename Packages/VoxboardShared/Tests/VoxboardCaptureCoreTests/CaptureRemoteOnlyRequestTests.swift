import XCTest
@testable import VoxboardCaptureCore

final class CaptureRemoteOnlyRequestTests: XCTestCase {
    func test_remoteOnlyRequestNeedsNoDestination() throws {
        let draft = CaptureDraft(text: "Synthetic remote thought")

        let request = try draft.makeRequest(source: .app, remoteOnly: true)

        XCTAssertEqual(request.id, draft.requestID)
        XCTAssertEqual(request.destinationID, CaptureRequest.remoteOnlyDestinationID)
        XCTAssertTrue(request.isRemoteOnly)
        XCTAssertEqual(request.payloads, [.text("Synthetic remote thought")])
    }

    func test_remoteOnlyRequestNeverCarriesAVaultDestination() throws {
        let draft = CaptureDraft(text: "Synthetic", destinationID: UUID())

        let request = try draft.makeRequest(source: .app, resolvedDestinationID: UUID(), remoteOnly: true)

        XCTAssertTrue(request.isRemoteOnly)
    }

    func test_localRequestStillRequiresDestination() throws {
        let draft = CaptureDraft(text: "Synthetic local thought")

        XCTAssertThrowsError(try draft.makeRequest(source: .app)) { error in
            XCTAssertEqual(error as? CaptureDraftError, .destinationRequired)
        }
        let destinationID = UUID()
        let request = try draft.makeRequest(source: .app, resolvedDestinationID: destinationID)
        XCTAssertEqual(request.destinationID, destinationID)
        XCTAssertFalse(request.isRemoteOnly)
    }
}

final class CaptureRemoteOnlyMeteringTests: XCTestCase {
    private func remoteOnlyRequest() -> CaptureRequest {
        CaptureRequest(
            source: .app,
            destinationID: CaptureRequest.remoteOnlyDestinationID,
            payloads: [.text("Synthetic remote thought")]
        )
    }

    func test_successfulHandoffCommitsReservedDelivery() async throws {
        let accounting = RemoteOnlyRecordingAccounting()
        let request = remoteOnlyRequest()

        let result = try await CapturePipeline(deliveryAccounting: accounting)
            .meterRemoteOnlyDelivery(request) { "queued" }

        XCTAssertEqual(result, "queued")
        let events = await accounting.events
        XCTAssertEqual(events, ["reserve", "commit"])
    }

    func test_failedHandoffReleasesReservedDelivery() async {
        let accounting = RemoteOnlyRecordingAccounting()
        do {
            _ = try await CapturePipeline(deliveryAccounting: accounting)
                .meterRemoteOnlyDelivery(remoteOnlyRequest()) { () async throws -> String in
                    throw RemoteOnlyTestError.expected
                }
            XCTFail("Expected the handoff error")
        } catch {
            XCTAssertEqual(error as? RemoteOnlyTestError, .expected)
        }
        let events = await accounting.events
        XCTAssertEqual(events, ["reserve", "release"])
    }

    func test_quotaLimitStopsHandoff() async {
        let ran = RemoteOnlyFlag()
        do {
            _ = try await CapturePipeline(deliveryAccounting: RemoteOnlyDenyingAccounting())
                .meterRemoteOnlyDelivery(remoteOnlyRequest()) { await ran.set(); return "queued" }
            XCTFail("Expected the free-capture limit")
        } catch {
            XCTAssertEqual(error as? CaptureDeliveryQuotaError, .limitReached(limit: 3))
        }
        let didRun = await ran.value
        XCTAssertFalse(didRun)
    }

    func test_alreadyCountedRequestDoesNotRunHandoffAgain() async throws {
        let ran = RemoteOnlyFlag()
        let result = try await CapturePipeline(deliveryAccounting: RemoteOnlyAlreadyCountedAccounting())
            .meterRemoteOnlyDelivery(remoteOnlyRequest()) { await ran.set(); return "queued" }
        XCTAssertNil(result)
        let didRun = await ran.value
        XCTAssertFalse(didRun)
    }

    func test_vaultRequestCannotBeMeteredAsRemoteOnly() async {
        let request = CaptureRequest(source: .app, destinationID: UUID(), payloads: [.text("Synthetic")])
        do {
            _ = try await CapturePipeline().meterRemoteOnlyDelivery(request) { "queued" }
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? CapturePipelineError, .remoteOnlyRequestRequired)
        }
    }

    func test_remoteOnlyRequestIsNeverWrittenToAVaultOrInbox() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RemoteOnlyGuard-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = CaptureDestination(
            id: CaptureRequest.remoteOnlyDestinationID,
            name: "Synthetic",
            rootBookmark: Data(),
            rootName: "Synthetic",
            noteTarget: .existingNote(relativePath: "Inbox.md")
        )
        do {
            _ = try await CapturePipeline().capture(remoteOnlyRequest(), destination: destination, rootURL: root)
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? CapturePipelineError, .remoteOnlyRequestHasNoVault)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])

        do {
            try await CaptureInbox(rootDirectoryURL: root).enqueue(remoteOnlyRequest())
            XCTFail("Expected rejection")
        } catch {
            XCTAssertEqual(error as? CapturePipelineError, .remoteOnlyRequestHasNoVault)
        }
    }
}

private enum RemoteOnlyTestError: Error, Equatable { case expected }

private actor RemoteOnlyFlag {
    private(set) var value = false
    func set() { value = true }
}

private actor RemoteOnlyRecordingAccounting: CaptureDeliveryAccounting {
    private(set) var events: [String] = []
    func reserve(for request: CaptureRequest) async throws -> CaptureDeliveryReservation {
        events.append("reserve")
        return .reserved(requestID: request.id, token: UUID())
    }
    func commit(_ reservation: CaptureDeliveryReservation) async throws { events.append("commit") }
    func release(_ reservation: CaptureDeliveryReservation) async { events.append("release") }
}

private struct RemoteOnlyDenyingAccounting: CaptureDeliveryAccounting {
    func reserve(for request: CaptureRequest) async throws -> CaptureDeliveryReservation {
        throw CaptureDeliveryQuotaError.limitReached(limit: 3)
    }
    func commit(_ reservation: CaptureDeliveryReservation) async throws {}
    func release(_ reservation: CaptureDeliveryReservation) async {}
}

private struct RemoteOnlyAlreadyCountedAccounting: CaptureDeliveryAccounting {
    func reserve(for request: CaptureRequest) async throws -> CaptureDeliveryReservation {
        .alreadyCounted(requestID: request.id)
    }
    func commit(_ reservation: CaptureDeliveryReservation) async throws {}
    func release(_ reservation: CaptureDeliveryReservation) async {}
}
