import AVFoundation
import Foundation
import XCTest
@testable import VoxboardShared

final class RecordingQualityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RecordingQualityTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Setting

    func test_defaultsToSpeechAndPersists() throws {
        let suite = "RecordingQualityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(RecordingQuality.load(from: defaults), .speech)
        XCTAssertEqual(RecordingQuality.load(from: nil), .speech)

        RecordingQuality.save(.lossless, to: defaults)
        XCTAssertEqual(RecordingQuality.load(from: defaults), .lossless)

        defaults.set("studio", forKey: RecordingQuality.defaultsKey)
        XCTAssertEqual(RecordingQuality.load(from: defaults), .speech)
    }

    func test_speechSettingsMatchTheOriginalWatchRecorder() {
        let settings = RecordingQuality.speech.recorderSettings
        XCTAssertEqual(settings[AVFormatIDKey] as? Int, Int(kAudioFormatMPEG4AAC))
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 16_000)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(settings[AVEncoderAudioQualityKey] as? Int, AVAudioQuality.high.rawValue)
        XCTAssertNil(settings[AVEncoderBitRateKey])
        XCTAssertFalse(RecordingQuality.speech.recordsSeparateKeptAudio)
    }

    func test_highAndLosslessSettings() {
        let high = RecordingQuality.high.recorderSettings
        XCTAssertEqual(high[AVFormatIDKey] as? Int, Int(kAudioFormatMPEG4AAC))
        XCTAssertEqual(high[AVSampleRateKey] as? Double, 48_000)
        XCTAssertEqual(high[AVEncoderBitRateKey] as? Int, 64_000)

        let lossless = RecordingQuality.lossless.recorderSettings
        XCTAssertEqual(lossless[AVFormatIDKey] as? Int, Int(kAudioFormatAppleLossless))
        XCTAssertEqual(lossless[AVSampleRateKey] as? Double, 48_000)
        XCTAssertEqual(lossless[AVEncoderBitDepthHintKey] as? Int, 16)

        for quality in RecordingQuality.allCases {
            XCTAssertEqual(quality.fileExtension, "m4a")
        }
    }

    func test_storageHintsGrowWithQuality() {
        XCTAssertLessThan(
            RecordingQuality.speech.approximateBytesPerMinute,
            RecordingQuality.high.approximateBytesPerMinute
        )
        XCTAssertLessThan(
            RecordingQuality.high.approximateBytesPerMinute,
            RecordingQuality.lossless.approximateBytesPerMinute
        )
        XCTAssertTrue(RecordingQuality.high.approximateStoragePerMinuteDescription.hasSuffix("MB/min"))
    }

    // MARK: - Kept audio files

    func test_highRecordingIs48kAACAndTranscriptionCopyIs16kWAV() throws {
        let kept = try writeKeptRecording(.high, seconds: 1.5)

        let format = try XCTUnwrap(KeptAudioInspector.format(of: kept))
        XCTAssertEqual(format.formatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertEqual(format.channelCount, 1)
        XCTAssertTrue(KeptAudioInspector.needsTranscriptionCopy(kept))
        XCTAssertTrue(KeptAudioInspector.shouldPreserveEncoding(kept))

        try assertTranscriptionCopy(of: kept, expectedSeconds: 1.5)
    }

    func test_losslessRecordingIs48kALAC() throws {
        let kept = try writeKeptRecording(.lossless, seconds: 1)

        let format = try XCTUnwrap(KeptAudioInspector.format(of: kept))
        XCTAssertEqual(format.formatID, kAudioFormatAppleLossless)
        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertTrue(KeptAudioInspector.shouldPreserveEncoding(kept))

        try assertTranscriptionCopy(of: kept, expectedSeconds: 1)
    }

    func test_speechRecordingKeepsExistingPaths() throws {
        let kept = try writeKeptRecording(.speech, seconds: 1)

        let format = try XCTUnwrap(KeptAudioInspector.format(of: kept))
        XCTAssertEqual(format.formatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(format.sampleRate, 16_000)
        XCTAssertFalse(KeptAudioInspector.needsTranscriptionCopy(kept))
        XCTAssertFalse(KeptAudioInspector.shouldPreserveEncoding(kept))
    }

    func test_emptyWriterLeavesNoFile() throws {
        let url = root.appendingPathComponent("empty.m4a")
        let writer = try KeptAudioFileWriter(url: url, quality: .high)
        XCTAssertNil(writer.finalize())
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func test_resamplerConvertsTo48kMono() throws {
        let resampler = try XCTUnwrap(KeptAudioResampler(sampleRate: 48_000))
        let input = try XCTUnwrap(AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false
        ))
        var total = 0
        for _ in 0..<10 {
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: 4_410))
            buffer.frameLength = 4_410
            total += resampler.convert(buffer).count
        }
        // 0.1 s × 10 at 48 kHz, allowing for converter priming latency.
        XCTAssertEqual(Double(total), 48_000, accuracy: 600)
    }

    func test_audioAttachmentExportKeepsLosslessBytes() async throws {
        let kept = try writeKeptRecording(.lossless, seconds: 1)
        let transcript = root.appendingPathComponent("Note.md")
        try "note".write(to: transcript, atomically: true, encoding: .utf8)
        var flow = CapturePresetStore.makeCustomFlow()
        flow.audioSaveMode = .alongsideTranscript

        let exported = try await AudioAttachmentExporter.exportAudioIfNeeded(
            sourceAudioURL: kept,
            transcriptFileURL: transcript,
            flow: flow,
            transcriptFolderScopeURL: root
        )

        let url = try XCTUnwrap(exported)
        XCTAssertEqual(url.pathExtension, "m4a")
        XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: kept))
        XCTAssertEqual(KeptAudioInspector.format(of: url)?.formatID, kAudioFormatAppleLossless)
    }

    // MARK: - Helpers

    private func writeKeptRecording(_ quality: RecordingQuality, seconds: Double) throws -> URL {
        let url = root.appendingPathComponent("kept-\(quality.rawValue).m4a")
        let writer = try KeptAudioFileWriter(url: url, quality: quality)
        let count = Int(quality.sampleRate * seconds)
        let samples = (0..<count).map { index in
            Float(sin(2 * Double.pi * 440 * Double(index) / quality.sampleRate) * 0.3)
        }
        try writer.append(samples: samples)
        XCTAssertEqual(writer.duration, seconds, accuracy: 0.001)
        return try XCTUnwrap(writer.finalize())
    }

    private func assertTranscriptionCopy(of kept: URL, expectedSeconds: Double) throws {
        let copy = root.appendingPathComponent("copy-\(UUID().uuidString).wav")
        try KeptAudioInspector.makeTranscriptionCopy(of: kept, at: copy)
        let file = try AVAudioFile(forReading: copy)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / 16_000, expectedSeconds, accuracy: 0.1)
        XCTAssertFalse(KeptAudioInspector.needsTranscriptionCopy(copy))
    }
}
