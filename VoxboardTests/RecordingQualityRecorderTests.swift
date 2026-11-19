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

    func testStereoHighRecordingTranscribesA16kMonoCopy() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingQualityRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let kept = root.appendingPathComponent("segment_kept_stereo.m4a")
        let writer = try KeptAudioFileWriter(url: kept, quality: .high, channelCount: 2)
        try writer.append(samples: (0..<96_000).map { Float(sin(Double($0 / 2) / 20) * 0.2) })
        XCTAssertNotNil(writer.finalize())
        XCTAssertEqual(try AVAudioFile(forReading: kept).fileFormat.channelCount, 2)

        let copy = try await PersistentRecorder.transcriptionAudio(for: kept, source: .iOSApp)
        defer { try? FileManager.default.removeItem(at: copy) }
        let format = try AVAudioFile(forReading: copy).fileFormat
        XCTAssertEqual(format.sampleRate, 16_000)
        XCTAssertEqual(format.channelCount, 1)
    }

    func testRecoveredStereoTakeGetsADownmixedCopyButImportsDoNot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingQualityRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Right channel only: a left-only conversion would be silent.
        let kept = root.appendingPathComponent("recovered.m4a")
        let writer = try KeptAudioFileWriter(url: kept, quality: .lossless, channelCount: 2)
        var samples = [Float](repeating: 0, count: 48_000 * 2)
        for frame in 0..<48_000 { samples[frame * 2 + 1] = Float(sin(Double(frame) / 15) * 0.5) }
        try writer.append(samples: samples)
        XCTAssertNotNil(writer.finalize())

        let copy = try await PersistentRecorder.transcriptionAudio(for: kept, source: .recovered)
        defer { try? FileManager.default.removeItem(at: copy) }
        XCTAssertNotEqual(copy, kept)
        let file = try AVAudioFile(forReading: copy)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        let mono = try XCTUnwrap(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(mono[$1])) }
        XCTAssertGreaterThan(peak, 0.1)

        // Imported files keep their existing path to the engine.
        let imported = try await PersistentRecorder.transcriptionAudio(for: kept, source: .importedAudio)
        XCTAssertEqual(imported, kept)
    }

    func testRecoveredMonoTakeKeepsItsExistingPath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingQualityRecorderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A mono High take recovered after a crash reaches the engine exactly
        // as before this change: the original file, converted by the engine.
        let kept = root.appendingPathComponent("recovered-mono.m4a")
        let writer = try KeptAudioFileWriter(url: kept, quality: .high)
        try writer.append(samples: (0..<48_000).map { Float(sin(Double($0) / 20) * 0.2) })
        XCTAssertNotNil(writer.finalize())

        let audio = try await PersistentRecorder.transcriptionAudio(for: kept, source: .recovered)
        XCTAssertEqual(audio, kept)
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
