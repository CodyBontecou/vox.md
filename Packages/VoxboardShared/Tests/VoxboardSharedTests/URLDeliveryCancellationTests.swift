import XCTest
@testable import VoxboardShared

@MainActor
final class URLDeliveryCancellationTests: XCTestCase {
    func testCancellationBeforeMainActorFactoryDoesNotCreateTask() async {
        let gate = URLDeliveryCancellation()
        var created = false
        let parent = Task {
            try await gate.valueOfMainActorTask { created = true; return Task { true } }
        }
        parent.cancel()
        do { _ = try await parent.value; XCTFail("Expected cancellation") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertFalse(created)
        XCTAssertTrue(gate.isCancelled)
    }

    func testParentCancellationCancelsDetachedLocalDeliveryTask() async {
        let started = expectation(description: "Owned local task started")
        let stopped = expectation(description: "Local task canceled")
        let gate = URLDeliveryCancellation()
        let parent = Task {
            await gate.runDetached(priority: .utility) {
                started.fulfill()
                do { try await Task.sleep(for: .seconds(30)); return true }
                catch { stopped.fulfill(); return false }
            }
        }
        await fulfillment(of: [started], timeout: 2)
        parent.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        let succeeded = await parent.value
        XCTAssertFalse(succeeded)
    }

    func testSourceCancellationBeforeHTTPRegistrationMakesNoPOST() async throws {
        let directory = makeDirectory()
        defer { cleanup(directory) }
        let sender = makeSender(directory: directory)
        let id = await enqueue(sender)
        let owner = URLDeliveryCoordinator(deliverer: sender)
        let gate = URLDeliveryCancellation()
        gate.cancel()
        owner.dispatch(id: id, cancellation: gate)
        await owner.refresh()
        XCTAssertTrue(owner.activeIDs.isEmpty)
        XCTAssertTrue(StubURLProtocol.capturedRequests.isEmpty)
        XCTAssertEqual(owner.receipts.first?.attempt, 0)
    }

    func testSourceCancellationAfterHandoffCancelsHTTPBackoff() async {
        let directory = makeDirectory()
        defer { cleanup(directory) }
        let sleeping = expectation(description: "HTTP reached backoff")
        let stopped = expectation(description: "Source cancellation canceled HTTP")
        let sender = makeSender(directory: directory, sleeper: { _ in
            sleeping.fulfill()
            do { try await Task.sleep(for: .seconds(30)) }
            catch { stopped.fulfill(); throw error }
        })
        let id = await enqueue(sender)
        let owner = URLDeliveryCoordinator(deliverer: sender)
        let gate = URLDeliveryCancellation()
        owner.dispatch(id: id, cancellation: gate)
        await fulfillment(of: [sleeping], timeout: 2)
        gate.cancel()
        await fulfillment(of: [stopped], timeout: 2)
        await owner.cancelAll()
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
        XCTAssertTrue(owner.activeIDs.isEmpty)
        XCTAssertEqual(owner.receipts.first?.outcome, .retryable)
    }

    func testNormalSourceCompletionDoesNotCancelTransferredHTTP() async {
        let directory = makeDirectory()
        defer { cleanup(directory) }
        let sleeping = expectation(description: "Transferred HTTP remains alive")
        let sender = makeSender(directory: directory, sleeper: { _ in
            sleeping.fulfill()
            try await Task.sleep(for: .seconds(30))
        })
        let id = await enqueue(sender)
        let owner = URLDeliveryCoordinator(deliverer: sender)
        do {
            let gate = URLDeliveryCancellation()
            owner.dispatch(id: id, cancellation: gate)
        }
        await fulfillment(of: [sleeping], timeout: 2)
        XCTAssertTrue(owner.activeIDs.contains(id))
        await owner.cancelAll()
        XCTAssertEqual(StubURLProtocol.capturedRequests.count, 1)
    }

    private func enqueue(_ sender: TranscriptURLDeliverer) async -> UUID {
        let id = UUID()
        let event = await sender.enqueueCapture(id: id, text: "Synthetic", date: Date(),
            settings: .init(enabled: true, urlString: "https://example.invalid/ingest", maxAttempts: 2))
        XCTAssertEqual(event.result, .queued)
        return id
    }

    private func makeDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("URLCancellation-\(UUID().uuidString)")
    }

    private func cleanup(_ directory: URL) {
        StubURLProtocol.reset()
        try? FileManager.default.removeItem(at: directory)
    }

    private func makeSender(directory: URL, sleeper: @escaping TranscriptURLDeliverer.Sleeper = { _ in }) -> TranscriptURLDeliverer {
        StubURLProtocol.configure(responses: [.init(statusCode: 503), .init(statusCode: 200)], error: nil)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return TranscriptURLDeliverer(session: URLSession(configuration: configuration), receiptsDirectoryURL: directory,
                                      credentialsProvider: { _ in nil }, logger: { _ in }, sleeper: sleeper)
    }
}
