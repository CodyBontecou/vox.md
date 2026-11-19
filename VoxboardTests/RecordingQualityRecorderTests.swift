import AVFoundation
import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class RecordingQualityRecorderTests: XCTestCase {
    func testHighQualityAppRecordingTranscribesA16kCopy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingQualityRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let kept = root.appendingPathComponent("segment_kept.m4a")
        let writer = try KeptAudioFileWriter(url: kept, quality: .high)
        try writer.append(samples: (0..<48_000).map { Float(sin(Double($0) / 20) * 0.2) })
        XCTAssertNotNil(writer.finalize())

        let copy = try await PersistentRecorder.transcriptionAudio(for: kept, source: .iOSApp)
        defer { try? FileManager.default.removeItem(at: copy) }
        XCTAssertNotEqual(copy, kept)
        XCTAssertEqual(copy.pathExtension, "wav")
        XCTAssertEqual(try AVAudioFile(forReading: copy).fileFormat.sampleRate, 16_000)

        // Imports keep handing the engine their original file.
        let imported = try await PersistentRecorder.transcriptionAudio(for: kept, source: .importedAudio)
        XCTAssertEqual(imported, kept)
    }

    func testSpeechWAVIsTranscribedUnchanged() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingQualityRecorderTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let wav = root.appendingPathComponent("segment_speech.wav")
        let writer = try IncrementalWAVWriter(url: wav)
        try writer.append(samples: [Float](repeating: 0.1, count: 16_000))
        try writer.finalize()

        let url = try await PersistentRecorder.transcriptionAudio(for: wav, source: .iOSApp)
        XCTAssertEqual(url, wav)
    }
}
