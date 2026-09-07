import Foundation
import FoundationModels
import VoxboardShared

/// Compiled alongside the production backend by run-foundation-model-evaluations.py.
/// Every input is synthetic. It neither loads app history nor changes settings.
@main
struct FoundationModelsEvaluation {
    struct Row: Codable {
        let fixture: String
        let implementation: String
        let seconds: Double
        let outcome: String
        let preservedRequiredText: Bool
        let output: String?
    }

    struct Fixture {
        let name: String
        let text: String
        let mode: CapturePresetProcessingMode
        let required: [String]
    }

    static func main() async throws {
        guard #available(macOS 26, *) else { print("OS 26 is required"); return }
        guard FoundationModelsBackend.isAvailable else {
            print("Apple Intelligence is unavailable; no evaluation ran.")
            Foundation.exit(2)
        }
        let fixtures = [
            Fixture(name: "dictation", text: "tomorrow i need to email sam about the launch", mode: .clean, required: ["Sam", "launch"]),
            Fixture(name: "markdown", text: "## Notes\n\nKeep [[Project Atlas]] and https://example.com/plan\n\n```swift\nlet count = 3\n```", mode: .clean,
                    required: ["## Notes", "[[Project Atlas]]", "https://example.com/plan", "```swift", "let count = 3"]),
            Fixture(name: "checklist", text: "buy milk. email sam", mode: .todoList, required: ["- [ ]", "milk", "Sam"]),
            Fixture(name: "meeting", text: "Speaker 1:\nWe agreed to launch Friday.\n\nSpeaker 2:\nI will write the release notes.", mode: .meetingNotes,
                    required: ["Speaker 1:", "Speaker 2:", "Friday", "release notes"]),
            Fixture(name: "custom", text: "Remember [[Project Atlas]] and the Friday deadline.", mode: .custom,
                    required: ["[[Project Atlas]]", "Friday"]),
            Fixture(name: "spanish", text: "mañana tengo que llamar a ana sobre el proyecto", mode: .clean, required: ["Ana", "proyecto"]),
        ]
        var rows: [Row] = []
        for fixture in fixtures {
            let profile = CapturePresetProfile(id: fixture.name, name: fixture.name, symbolName: "note",
                                               postProcessingMode: fixture.mode,
                                               customPostProcessingInstruction: "Format as a single Markdown bullet while preserving every fact and link.",
                                               captureProcessingEnabled: true)
            for implementation in ["baseline", "candidate"] {
                let started = ProcessInfo.processInfo.systemUptime
                do {
                    let output = try await withRunningTask(timeout: 45) {
                        if implementation == "baseline" { return try await baseline(fixture, profile: profile) }
                        return try await TranscriptEnricher(backend: FoundationModelsBackend())
                            .enrich(rawText: fixture.text, profile: profile).cleanedText
                    }
                    let preserved = fixture.required.allSatisfy { output.localizedCaseInsensitiveContains($0) }
                    rows.append(Row(fixture: fixture.name, implementation: implementation,
                                    seconds: ProcessInfo.processInfo.systemUptime - started,
                                    outcome: "completed", preservedRequiredText: preserved, output: output))
                } catch {
                    rows.append(Row(fixture: fixture.name, implementation: implementation,
                                    seconds: ProcessInfo.processInfo.systemUptime - started,
                                    outcome: (error as? LLMBackendFailure)?.rawValue ?? "failed",
                                    preservedRequiredText: false, output: nil))
                }
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var rejectedOversize = false
        do {
            _ = try await withRunningTask(timeout: 45) {
                try await FoundationModelsBackend().enrichNative(rawText: String(repeating: "Synthetic source sentence. ", count: 4000))
            }
        } catch {
            rejectedOversize = (error as? LLMBackendFailure) == .inputTooLarge
        }
        let report = Report(os: ProcessInfo.processInfo.operatingSystemVersionString,
                            contextSize: SystemLanguageModel.default.contextSize,
                            preflightRejectedOversize: rejectedOversize, results: rows)
        print(String(decoding: try encoder.encode(report), as: UTF8.self))
        if !rejectedOversize || rows.contains(where: { $0.implementation == "candidate" && !$0.preservedRequiredText }) {
            Foundation.exit(1)
        }
    }

    struct Report: Codable { let os: String; let contextSize: Int; let preflightRejectedOversize: Bool; let results: [Row] }

    @available(macOS 26, *)
    static func baseline(_ fixture: Fixture, profile: CapturePresetProfile) async throws -> String {
        // Original plain-cleanup instructions and guided shape, before this change.
        if fixture.mode == .clean {
            let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: """
            You organize text for a private, local-first capture app. The text may be \
            typed Markdown, an on-device speech transcript, or OCR from a document. \
            Produce a title, single-word tags (no spaces; hyphens allowed), a category, \
            and a cleaned version. Preserve existing Markdown structure and the author's \
            meaning — never add information that wasn't in the original.
            """)
            return try await session.respond(to: "Captured text:\n\"\"\"\n\(fixture.text)\n\"\"\"",
                                             generating: BaselineEnrichment.self).content.cleanedText
        }
        // Exercise the production compatibility prompt path used by the prior workflows.
        return try await TranscriptEnricher(backend: BaselineStringBackend())
            .enrich(rawText: fixture.text, profile: profile).cleanedText
    }
}

@available(macOS 26, *)
private struct BaselineStringBackend: LLMBackend {
    func complete(prompt: String) async throws -> String {
        try await LanguageModelSession(model: SystemLanguageModel.default).respond(to: prompt).content
    }
}

@available(macOS 26, *)
@Generable
private struct BaselineEnrichment {
    @Guide(description: "A short descriptive title, at most 6 words, without surrounding quotation marks")
    let title: String
    @Guide(description: "0 to 5 lowercase single-word tags describing the content (no spaces; hyphens allowed for compound words like app-dev)")
    let tags: [String]
    @Guide(description: "The single best category for this captured text")
    let category: BaselineCategory
    @Guide(description: "The captured text cleaned up while preserving meaning and existing Markdown structure. Return plain text only — never wrap it in quotes, braces, code fences, or JSON syntax")
    let cleanedText: String
}

@available(macOS 26, *)
@Generable
private enum BaselineCategory: String { case note, idea, task, meeting, journal, message, reminder, other }
