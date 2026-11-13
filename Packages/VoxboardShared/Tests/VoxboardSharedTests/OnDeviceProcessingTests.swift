import XCTest
@testable import VoxboardShared

final class OnDeviceProcessingTests: XCTestCase {
    func test_damagedLinksCodeHeadingsOrSpeakerOrderRetainSource() {
        for source in ["## Notes\nBody", "Keep [[Project Atlas]]", "Open https://example.com/plan",
                       "```swift\nlet count = 3\n```", "Speaker 1:\nHello\nSpeaker 2:\nHi"] {
            let damaged = TranscriptEnrichment(title: "Title", tags: [], category: "note", cleanedText: "Body")
            XCTAssertEqual(TranscriptEnricher.preservingSourceStructure(damaged, source: source, profile: nil).cleanedText, source)
            let intact = TranscriptEnrichment(title: "Title", tags: [], category: "note", cleanedText: source + "\n")
            XCTAssertEqual(TranscriptEnricher.preservingSourceStructure(intact, source: source, profile: nil), intact)
        }
    }

    func test_presetImageOptionSurvivesFullAndLightweightCoding() throws {
        let preset = CapturePreset(id: "images", name: "Images", symbolName: "photo",
                                   captureProcessingEnabled: true, generateImageAltText: true)
        let data = try JSONEncoder().encode(preset)
        XCTAssertTrue(try JSONDecoder().decode(CapturePreset.self, from: data).generateImageAltText)
        XCTAssertTrue(try JSONDecoder().decode(CapturePresetProfile.self, from: data).generateImageAltText)
        XCTAssertTrue(preset.captureProfile.generateImageAltText)
    }

    func test_terminalModelOutcomesNeverRetryAsPrompt() async throws {
        for outcome in [LLMBackendFailure.unavailable, .unsupportedLanguage, .inputTooLarge, .refusal, .busy, .timedOut] {
            let backend = EnrichmentOutcomeFixture(outcome: outcome)
            do {
                _ = try await TranscriptEnricher(backend: backend).enrich(rawText: "Source")
                XCTFail("Expected the terminal failure")
            } catch { XCTAssertEqual(error as? LLMBackendFailure, outcome) }
            let attempts = await backend.promptAttempts
            XCTAssertEqual(attempts, 0)
        }
    }

    func test_nativeBackendReceivesCustomProfileAndSpeakerLabels() async throws {
        let backend = EnrichmentOutcomeFixture()
        let profile = CapturePresetProfile(id: "meeting", name: "Meeting", symbolName: "person.2",
                                            postProcessingMode: .custom, customPostProcessingInstruction: "Keep a checklist")
        let source = "Speaker 1:\nKeep [[Link]] and https://example.com"
        _ = try await TranscriptEnricher(backend: backend).enrich(rawText: source, profile: profile)
        let received = await backend.received
        XCTAssertEqual(received?.0, source)
        XCTAssertEqual(received?.1, profile)
    }

    func test_nonCooperativeWorkTimesOutAndKeepsInferenceSlotUntilFinished() async throws {
        let gate = OnDeviceInferenceGate()
        let entered = expectation(description: "Non-cooperative work entered the inference gate")
        let finished = expectation(description: "Timed-out work actually returned from the gate")
        let work = ControlledInferenceWork(entered: entered)
        let deadlineReturned = expectation(description: "Deadline returns while non-cooperative work is suspended")
        let task = Task {
            defer { deadlineReturned.fulfill() }
            return try await withRunningTask(timeout: 0.03) {
                defer { finished.fulfill() }
                return try await gate.run {
                    await work.run()
                }
            }
        }
        await fulfillment(of: [entered], timeout: 2)
        // Assert ordering, not a sub-180 ms scheduling budget on a shared CI
        // runner. The operation cannot return until finish() below, so this
        // proves the deadline returns independently of non-cooperative work.
        await fulfillment(of: [deadlineReturned], timeout: 2)
        do { _ = try await gate.run { 9 }; XCTFail("Expired work must retain its slot") }
        catch { XCTAssertEqual(error as? LLMBackendFailure, .busy) }
        // A deadline or a fixed sleep cannot establish that a cancellation-ignoring
        // callback returned. Release it explicitly, then join its gate lifetime.
        await work.finish()
        await fulfillment(of: [finished], timeout: 2)
        do {
            _ = try await task.value
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error is EnrichmentTimeoutError) }
        let recovered = try await gate.run { 11 }
        XCTAssertEqual(recovered, 11)
    }

    func test_parentCancellationStopsDeadlineImmediately() async throws {
        let task = Task {
            try await withRunningTask(timeout: 10) {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { continuation.resume(returning: 1) }
                }
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
}

private actor ControlledInferenceWork {
    private let entered: XCTestExpectation
    private var continuation: CheckedContinuation<Int, Never>?

    init(entered: XCTestExpectation) { self.entered = entered }

    func run() async -> Int {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            entered.fulfill()
        }
    }

    func finish() {
        continuation?.resume(returning: 7)
        continuation = nil
    }
}

private actor EnrichmentOutcomeFixture: LLMBackend {
    var promptAttempts = 0
    var received: (String, CapturePresetProfile?)?
    let outcome: LLMBackendFailure?
    init(outcome: LLMBackendFailure? = nil) { self.outcome = outcome }
    func complete(prompt: String) async throws -> String { promptAttempts += 1; return "{}" }
    func enrichNative(rawText: String, profile: CapturePresetProfile?) async throws -> TranscriptEnrichment? {
        received = (rawText, profile)
        if let outcome { throw outcome }
        return TranscriptEnrichment(title: "Title", tags: [], category: "note", cleanedText: rawText)
    }
}
