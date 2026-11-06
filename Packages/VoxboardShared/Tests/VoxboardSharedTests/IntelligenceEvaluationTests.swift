import Foundation
import Testing
@testable import VoxboardShared

struct IntelligenceEvaluationTests {
    private struct ScorerExample: Decodable { let caseID: String; let response: String; let passed: Bool }
    private struct SpeakerExample: Decodable { let reference: [String]; let predicted: [String]; let durations: [Double]; let error: Double }
    private struct Corpus: Decodable { let instructionCases: [InstructionEvaluationCase]; let scorerExamples: [ScorerExample]; let speakerScorerExamples: [SpeakerExample] }
    private func corpus() throws -> Corpus {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../evaluations/local-intelligence/v1/corpus.json").standardizedFileURL
        return try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: url))
    }
    @Test func sharedInstructionScorerAcceptsReferencesAndRejectsMutations() throws {
        let corpus = try corpus()
        let cases = Dictionary(uniqueKeysWithValues: corpus.instructionCases.map { ($0.id, $0) })
        #expect(Set(cases.keys) == ["sorted-people", "formal-request", "spanish-extraction", "factual-summary", "link-preservation", "speaker-ownership"])
        for example in corpus.scorerExamples {
            let test = try #require(cases[example.caseID])
            #expect(IntelligenceEvaluation.passes(test, response: example.response) == example.passed)
        }
    }
    @Test func speakerScoringUsesTheSamePermutationAndErrorRules() throws {
        for example in try corpus().speakerScorerExamples {
            let value = IntelligenceEvaluation.speakerAttributionError(reference: example.reference, predicted: example.predicted, durations: example.durations)
            #expect(abs(value - example.error) < 0.000001)
        }
        #expect(IntelligenceEvaluation.speakerAttributionError(reference: ["a"], predicted: ["1"], durations: [.nan]) == 1)
    }
}
