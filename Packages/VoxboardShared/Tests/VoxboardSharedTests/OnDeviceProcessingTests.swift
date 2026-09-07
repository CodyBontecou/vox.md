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
        let start = ProcessInfo.processInfo.systemUptime
        do {
            _ = try await withRunningTask(timeout: 0.03) {
                try await gate.run {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) { continuation.resume(returning: 7) }
                    }
                }
            }
            XCTFail("Expected timeout")
        } catch { XCTAssertTrue(error is EnrichmentTimeoutError) }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 0.18)
        do { _ = try await gate.run { 9 }; XCTFail("Expired work must retain its slot") }
        catch { XCTAssertEqual(error as? LLMBackendFailure, .busy) }
        try await Task.sleep(nanoseconds: 300_000_000)
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
