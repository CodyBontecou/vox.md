import Foundation

public struct InstructionEvaluationCase: Codable, Sendable {
    public let id: String
    public let instruction: String
    public let source: String
    public let containsAll: [String]
    public let containsAny: [[String]]
    public let ordered: [String]
    public let forbiddenTerms: [String]
    public let speakerOwnership: [String: [String]]
    public let outputFormat: String
    public let maximumWords: Int
}

public struct SpeakerAudioEvaluationClip: Decodable, Sendable {
    public let id: String
    public let file: String
    public let speaker: String
    public let durationSeconds: Double
    public let sha256: String
}

public struct IntelligenceEvaluationCorpus: Decodable, Sendable {
    public let schemaVersion: Int
    public let corpusID: String
    public let instructionCases: [InstructionEvaluationCase]
    public let speakerAudio: [SpeakerAudioEvaluationClip]
    public let speakerSequence: [String]
}

/// Identical scoring semantics to Android's IntelligenceEvaluation. These bounded
/// functional checks do not replace human review of semantic correctness.
public enum IntelligenceEvaluation {
    public static func passes(_ test: InstructionEvaluationCase, response: String) -> Bool {
        let value = normalize(response)
        guard !value.isEmpty, value.split(whereSeparator: \.isWhitespace).count <= test.maximumWords,
              test.containsAll.allSatisfy({ value.contains(normalize($0)) }),
              test.containsAny.allSatisfy({ group in group.contains { value.contains(normalize($0)) } }) else {
            return false
        }
        if test.outputFormat == "one-term-per-line",
           response.split(whereSeparator: \.isNewline).map({ normalize(String($0)) }) != test.ordered.map(normalize) { return false }
        if test.outputFormat == "comma-separated-terms",
           response.components(separatedBy: ",").map(normalize) != test.containsAll.map(normalize) { return false }
        guard ["free-form", "one-term-per-line", "comma-separated-terms"].contains(test.outputFormat) else { return false }
        if test.forbiddenTerms.contains(where: { value.range(of: "\\b" + NSRegularExpression.escapedPattern(for: normalize($0)) + "\\b", options: .regularExpression) != nil }) { return false }
        for (label, terms) in test.speakerOwnership {
            guard let range = response.range(of: label) else { return false }
            let rest = String(response[range.upperBound...])
            let next = rest.range(of: "Speaker \\d+:", options: .regularExpression)?.lowerBound ?? rest.endIndex
            let attributed = normalize(String(rest[..<next]))
            guard terms.allSatisfy({ attributed.contains(normalize($0)) }) else { return false }
        }
        var remaining = value.startIndex..<value.endIndex
        for term in test.ordered {
            guard let range = value.range(of: normalize(term), range: remaining) else { return false }
            remaining = range.upperBound..<value.endIndex
        }
        return true
    }

    public static func speakerAttributionError(reference: [String], predicted: [String], durations: [Double]) -> Double {
        guard !reference.isEmpty, reference.count == predicted.count, reference.count == durations.count,
              durations.allSatisfy({ $0.isFinite && $0 > 0 }), predicted.allSatisfy({ !$0.isEmpty }) else { return 1 }
        let truth = Array(Set(reference)).sorted()
        let labels = Array(Set(predicted)).sorted()
        guard truth.count <= 8, labels.count <= 8 else { return 1 }
        var best = 0.0
        func assign(_ index: Int, mapping: [String: String], used: Set<String>) {
            if index == labels.count {
                let correct = reference.indices.reduce(0.0) { sum, i in
                    sum + (mapping[predicted[i]] == reference[i] ? durations[i] : 0)
                }
                best = max(best, correct)
                return
            }
            for speaker in truth where !used.contains(speaker) {
                var next = mapping
                next[labels[index]] = speaker
                assign(index + 1, mapping: next, used: used.union([speaker]))
            }
            assign(index + 1, mapping: mapping, used: used)
        }
        assign(0, mapping: [:], used: [])
        return 1 - best / durations.reduce(0, +)
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
