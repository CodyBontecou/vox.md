import CryptoKit
import Foundation
import VoxboardShared

private struct SpeakerReport: Encodable {
    let schemaVersion = 1
    let corpusID: String
    let platform = "apple"
    let runtime = "FluidAudio / SpeakerDiarizationService"
    let metric = "known-turn-duration-weighted-attribution-error"
    let reference: [String]
    let predicted: [String]
    let durations: [Double]
    let attributionError: Double
    let elapsedSeconds: Double
    let status: String
    let meetsZeroErrorTarget: Bool
}

func runSpeakerBenchmark(corpus: IntelligenceEvaluationCorpus, root: URL, output: URL) async throws {
    var pcm = Data()
    var segments: [TimedTranscriptionSegment] = []
    var reference: [String] = []
    var durations: [Double] = []
    var cursor = 0.0
    for (index, identifier) in corpus.speakerSequence.enumerated() {
        guard let clip = corpus.speakerAudio.first(where: { $0.id == identifier }) else { throw benchmarkError("missing clip") }
        let data = try Data(contentsOf: root.appendingPathComponent(clip.file))
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == clip.sha256 else { throw benchmarkError("clip digest") }
        let audio = try wavPCM(data)
        pcm.append(audio)
        let duration = Double(audio.count) / 32_000
        guard abs(duration - clip.durationSeconds) < 0.0001 else { throw benchmarkError("clip duration") }
        segments.append(TimedTranscriptionSegment(text: "Clip-\(index)", startTime: cursor, endTime: cursor + duration))
        reference.append(clip.speaker)
        durations.append(duration)
        cursor += duration + 1
        pcm.append(Data(repeating: 0, count: 32_000))
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let wav = directory.appendingPathComponent("speaker-benchmark.wav")
    try wavData(pcm).write(to: wav)
    let started = Date()
    let result = try await SpeakerDiarizationService().diarize(audioURL: wav,
        transcriptText: segments.map(\.text).joined(separator: " "), transcriptionSegments: segments)
    let predicted = segments.map { segment in result.turns.first(where: { $0.text.contains(segment.text) }).map { String($0.speaker) } ?? "" }
    let error = IntelligenceEvaluation.speakerAttributionError(reference: reference, predicted: predicted, durations: durations)
    let report = SpeakerReport(corpusID: corpus.corpusID, reference: reference, predicted: predicted, durations: durations,
        attributionError: error, elapsedSeconds: Date().timeIntervalSince(started), status: "completed", meetsZeroErrorTarget: error < 0.000001)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: output, options: .atomic)
    // This is an unchanged Apple reference measurement. Android's parity gate
    // independently requires zero attribution error; poor baseline quality stays
    // explicit in the report rather than masquerading as a runtime/test failure.

}

private func benchmarkError(_ message: String) -> NSError { NSError(domain: "VoxSpeakerBenchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
private func wavPCM(_ data: Data) throws -> Data {
    func integer(_ offset: Int) -> Int {
        Int(data[offset]) | Int(data[offset + 1]) << 8 | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
    }
    guard data.count > 44, String(data: data.prefix(4), encoding: .ascii) == "RIFF" else { throw benchmarkError("WAV header") }
    var offset = 12
    while offset + 8 <= data.count {
        let size = integer(offset + 4)
        guard size >= 0, offset + 8 + size <= data.count else { throw benchmarkError("WAV bounds") }
        if String(data: data[offset..<(offset + 4)], encoding: .ascii) == "data" { return data.subdata(in: (offset + 8)..<(offset + 8 + size)) }
        offset += 8 + size + size % 2
    }
    throw benchmarkError("WAV samples")
}
private func wavData(_ pcm: Data) -> Data {
    var data = Data("RIFF".utf8)
    func append<T: FixedWidthInteger>(_ value: T) { var bytes = value.littleEndian; withUnsafeBytes(of: &bytes) { data.append(contentsOf: $0) } }
    append(UInt32(pcm.count + 36)); data.append(Data("WAVEfmt ".utf8)); append(UInt32(16))
    append(UInt16(1)); append(UInt16(1)); append(UInt32(16_000)); append(UInt32(32_000)); append(UInt16(2)); append(UInt16(16))
    data.append(Data("data".utf8)); append(UInt32(pcm.count)); data.append(pcm)
    return data
}
