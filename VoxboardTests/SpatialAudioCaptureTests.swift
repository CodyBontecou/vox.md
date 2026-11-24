import AVFoundation
import CoreMedia
import VoxboardShared
import XCTest
@testable import Voxboard

/// Spatial Audio (#133) decisions and fallbacks that run without an FOA
/// microphone. Real spatial capture needs an iPhone that supports it.
@MainActor
final class SpatialAudioCaptureTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpatialAudioCaptureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSupportNeedsAnIPhoneOnIOS26WithMicAccessAndAnFOAMicrophone() {
        typealias Support = SpatialAudioCaptureSupport
        var checkedHardware = false
        func evaluate(phone: Bool = true, os: Bool = true, authorized: Bool = true, foa: Bool = true) -> Support {
            Support.evaluate(
                isPhone: phone,
                osSupportsSpatialCapture: os,
                microphoneAuthorized: authorized,
                microphoneSupportsAmbisonics: { checkedHardware = true; return foa }
            )
        }
        XCTAssertEqual(evaluate(), .supported)
        XCTAssertEqual(evaluate(foa: false), .unavailable)
        checkedHardware = false
        XCTAssertEqual(evaluate(phone: false), .unavailable)
        XCTAssertEqual(evaluate(os: false), .unavailable)
        XCTAssertFalse(checkedHardware, "no capture input is created where spatial can't apply")
        XCTAssertEqual(evaluate(authorized: false), .needsMicrophoneAccess)
        XCTAssertFalse(checkedHardware, "the mic is never probed without access")
    }

    func testSimulatorHasNoSpatialMicrophone() {
        // The simulator's microphone has no first-order ambisonics mode.
        XCTAssertNotEqual(SpatialAudioCaptureSupport.current, .supported)
    }

    func testSpatialCaptureStartFailsCleanlyWithoutAnFOAMicrophone() {
        var samples = 0
        var interruptions: [String] = []
        let result = SpatialAudioRecording.start(
            preRollSeconds: 4,
            onTranscriptionSamples: { samples += $0.count },
            onInterruption: { interruptions.append($0) }
        )
        guard case .failure(let failure) = result else {
            return XCTFail("spatial capture must not start without an FOA microphone")
        }
        XCTAssertFalse(failure.description.isEmpty)
        XCTAssertTrue(interruptions.isEmpty)
    }

    func testSettingsShowTheEffectiveLayout() {
        typealias Layout = RecordingChannelLayout
        XCTAssertEqual(Layout.effective(quality: .high, stored: .spatial, support: .supported), .spatial)
        XCTAssertEqual(Layout.effective(quality: .high, stored: .spatial, support: .unavailable), .stereo)
        XCTAssertEqual(Layout.effective(quality: .high, stored: .spatial, support: .needsMicrophoneAccess), .stereo)
        XCTAssertEqual(Layout.effective(quality: .speech, stored: .spatial, support: .supported), .mono)
        XCTAssertEqual(Layout.effective(quality: .lossless, stored: .mono, support: .supported), .mono)
    }

    func testSpatialFormatLinesAndSummaries() {
        XCTAssertEqual(RecordingQuality.high.formatSummary(layout: .stereo), RecordingQuality.high.formatSummary(stereo: true))
        XCTAssertEqual(RecordingQuality.lossless.formatSummary(layout: .mono), RecordingQuality.lossless.formatSummary(stereo: false))
        XCTAssertNotEqual(RecordingQuality.high.formatSummary(layout: .spatial), RecordingQuality.high.formatSummary(stereo: true))
        XCTAssertEqual(RecordingQuality.speech.formatSummary(layout: .spatial), RecordingQuality.speech.formatSummary(stereo: false))
        XCTAssertEqual(
            RecordingQuality.high.localizedStoragePerMinute(layout: .stereo),
            RecordingQuality.high.localizedStoragePerMinute(stereo: true)
        )
        XCTAssertNotEqual(
            RecordingQuality.high.localizedStoragePerMinute(layout: .spatial),
            RecordingQuality.high.localizedStoragePerMinute(stereo: true)
        )
        XCTAssertNil(RecordingQuality.high.spatialSettingsSummary(storedLayout: .stereo))
        XCTAssertNil(RecordingQuality.speech.spatialSettingsSummary(storedLayout: .spatial))
        // No FOA mic here, so a stored Spatial choice summarizes as Stereo.
        let summary = try? XCTUnwrap(RecordingQuality.high.spatialSettingsSummary(storedLayout: .spatial))
        XCTAssertEqual(summary?.contains(RecordingChannelLayout.stereo.displayName), true)
    }

    func testMetadataGeneratorWritesASpatialFileFromSyntheticFOA() throws {
        #if targetEnvironment(simulator)
        // The simulator's generator raises "Not supported" (an Objective-C
        // exception) on first use; this runs on a device only.
        throw XCTSkip("AVCaptureSpatialAudioMetadataSampleGenerator is device-only")
        #endif
        guard #available(iOS 26.0, *) else { throw XCTSkip("needs iOS 26") }
        let url = root.appendingPathComponent("kept_spatial.mp4")
        let metadata = CaptureSpatialAudioMetadataSource()
        let writer: SpatialAudioFileWriter
        do {
            writer = try SpatialAudioFileWriter(
                url: url,
                quality: .high,
                ambisonicsSettings: SpatialAudioRecordingFormat.ambisonicsSettings(recommended: nil),
                metadata: metadata,
                startTime: .zero
            )
        } catch {
            throw XCTSkip("APAC encoding unavailable on this runtime: \(error)")
        }
        var time: Int64 = 0
        for _ in 0..<50 {
            XCTAssertTrue(writer.append(try Self.buffer(channels: 4, start: time), to: .ambisonics, waitIfBusy: 1))
            XCTAssertTrue(writer.append(try Self.buffer(channels: 2, start: time), to: .stereo, waitIfBusy: 1))
            time += 960
        }
        let result = writer.finish()
        let saved = try XCTUnwrap(result.url, "\(String(describing: writer.error))")
        XCTAssertEqual(result.summary.analyzeFailures, 0)
        XCTAssertTrue(KeptAudioInspector.isKeptSpatialRecording(saved))
        // Whether the generator produces a value for synthetic audio on this
        // runtime is recorded, not required: real capture is device-only.
        print("SpatialAudioCaptureTests: generator metadata written = \(result.summary.wroteMetadata)")
    }

    func testRecoveredSpatialTakeGetsAStereoMixedCopy() async throws {
        let kept = root.appendingPathComponent("kept_recovered.mp4")
        let writer: SpatialAudioFileWriter
        do {
            writer = try SpatialAudioFileWriter(
                url: kept,
                quality: .high,
                ambisonicsSettings: SpatialAudioRecordingFormat.ambisonicsSettings(recommended: nil),
                metadata: nil,
                startTime: .zero
            )
        } catch {
            throw XCTSkip("APAC encoding unavailable on this runtime: \(error)")
        }
        var time: Int64 = 0
        for _ in 0..<50 {
            writer.append(try Self.buffer(channels: 4, start: time), to: .ambisonics, waitIfBusy: 1)
            writer.append(try Self.buffer(channels: 2, start: time), to: .stereo, waitIfBusy: 1)
            time += 960
        }
        XCTAssertNotNil(writer.finish().url)

        let copy = try await PersistentRecorder.transcriptionAudio(for: kept, source: .recovered)
        defer { try? FileManager.default.removeItem(at: copy) }
        XCTAssertNotEqual(copy, kept)
        let file = try AVAudioFile(forReading: copy)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / 16_000, 1, accuracy: 0.1)

        let app = try await PersistentRecorder.transcriptionAudio(for: kept, source: .iOSApp)
        defer { try? FileManager.default.removeItem(at: app) }
        XCTAssertEqual(app.pathExtension, "wav")
        let imported = try await PersistentRecorder.transcriptionAudio(for: kept, source: .importedAudio)
        XCTAssertEqual(imported, kept)
    }

    /// 20 ms of interleaved Float32 at 48 kHz (a 440 Hz tone).
    nonisolated static func buffer(channels: Int, start: Int64, frames: Int = 960) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0
        )
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 4 ? SpatialAudioRecordingFormat.ambisonicsLayoutTag : kAudioChannelLayoutTag_Stereo
        var format: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &layout,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        )
        var samples = [Float](repeating: 0, count: frames * channels)
        for frame in 0..<frames {
            let tone = Float(sin(Double(Int(start) + frame) * 2 * .pi * 440 / 48_000)) * 0.4
            for channel in 0..<channels { samples[frame * channels + channel] = channel == 0 ? tone : tone * 0.5 }
        }
        let length = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block
        )
        let blockBuffer = try XCTUnwrap(block)
        samples.withUnsafeBytes {
            _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: length)
        }
        var sample: CMSampleBuffer?
        CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: blockBuffer, formatDescription: try XCTUnwrap(format), sampleCount: frames,
            presentationTimeStamp: CMTime(value: start, timescale: 48_000), packetDescriptions: nil, sampleBufferOut: &sample
        )
        return try XCTUnwrap(sample)
    }
}
