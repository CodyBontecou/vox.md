import Foundation
import XCTest
@testable import VoxboardShared

final class RecordingAudioExtractionTests: XCTestCase {
    func testFullRecordingSurvivesMultipleRollingBufferWraps() throws {
        try withJournal { writer, buffer, url in
            let samples = (0..<35).map { Float($0) / 40 }
            // Includes the pre-roll prefix seeded before live capture starts.
            try writer.append(samples: Array(samples.prefix(2)))
            buffer.append(Array(samples.prefix(2)))
            for chunk in [Array(samples[2..<20]), Array(samples[20..<35])] {
                try writer.append(samples: chunk)
                buffer.append(chunk)
            }
            XCTAssertNil(buffer.extract(from: 0, to: 35))
            let recovered = try XCTUnwrap(RecordingAudioExtraction.samples(
                from: buffer, startIndex: 0, endIndex: 35,
                pausedRanges: [], journalURL: try writer.finalize()
            ))
            XCTAssertEqual(recovered.count, samples.count)
            for (actual, expected) in zip(recovered, samples) {
                XCTAssertEqual(actual, expected, accuracy: 1 / 32_767)
            }
        }
    }

    func testPausedAudioIsExcludedAfterBufferWrapAndCommitReadsOnlyItsPrefix() throws {
        try withJournal { writer, buffer, url in
            buffer.append([Float](repeating: 0.25, count: 5))
            try writer.append(samples: [Float](repeating: 0.25, count: 5))
            // Pausing longer than the entire ring must not lose the recording.
            buffer.append([Float](repeating: 0.75, count: 20))
            buffer.append([Float](repeating: -0.25, count: 5))
            try writer.append(samples: [Float](repeating: -0.25, count: 5))
            // Audio arriving after a continuous-mode commit cursor stays for
            // the next span, even when present in the active journal snapshot.
            try writer.append(samples: [0.9, 0.9])
            let recovered = try XCTUnwrap(RecordingAudioExtraction.samples(
                from: buffer, startIndex: 0, endIndex: 30,
                pausedRanges: [(5, 25)], journalURL: url
            ))
            XCTAssertEqual(recovered.count, 10)
            XCTAssertEqual(recovered.first!, 0.25, accuracy: 1 / 32_767)
            XCTAssertEqual(recovered.last!, -0.25, accuracy: 1 / 32_767)
        }
    }

    func testTruncatedJournalCannotSilentlyDeliverPartialRecording() throws {
        try withJournal { writer, buffer, url in
            buffer.append([Float](repeating: 0.25, count: 30))
            try writer.append(samples: [Float](repeating: 0.25, count: 20))
            XCTAssertNil(RecordingAudioExtraction.samples(
                from: buffer, startIndex: 0, endIndex: 30,
                pausedRanges: [], journalURL: url
            ))
        }
    }

    private func withJournal(
        _ body: (IncrementalWAVWriter, CircularAudioBuffer, URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("recording.wav")
        let writer = try IncrementalWAVWriter(url: url)
        defer { _ = try? writer.finalize() }
        try body(writer, CircularAudioBuffer(capacity: 10), url)
    }
}
