import AVFoundation
import CoreMedia
import Foundation
import XCTest
@testable import VoxboardShared

/// Spatial Audio kept recordings (#133). The writer is fed synthetic FOA and
/// stereo `CMSampleBuffer`s; real capture needs an iPhone with an FOA mic.
final class SpatialAudioRecordingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SpatialAudioRecordingTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Setting

    func test_layoutDefaultsToMonoAndStoresStereoAndSpatialExclusively() throws {
        let suite = "SpatialAudioRecordingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(RecordingChannelLayout.load(from: defaults), .mono)
        XCTAssertEqual(RecordingChannelLayout.load(from: nil), .mono)

        // An existing Stereo choice (PR #120) reads as Stereo.
        StereoRecordingPreference.save(true, to: defaults)
        XCTAssertEqual(RecordingChannelLayout.load(from: defaults), .stereo)

        RecordingChannelLayout.save(.spatial, to: defaults)
        XCTAssertEqual(RecordingChannelLayout.load(from: defaults), .spatial)
        // A build that only knows Stereo sees mono, never stereo + spatial.
        XCTAssertFalse(StereoRecordingPreference.load(from: defaults))
        XCTAssertTrue(defaults.bool(forKey: RecordingChannelLayout.spatialDefaultsKey))

        RecordingChannelLayout.save(.stereo, to: defaults)
        XCTAssertEqual(RecordingChannelLayout.load(from: defaults), .stereo)
        XCTAssertFalse(defaults.bool(forKey: RecordingChannelLayout.spatialDefaultsKey))

        RecordingChannelLayout.save(.mono, to: defaults)
        XCTAssertEqual(RecordingChannelLayout.load(from: defaults), .mono)
        XCTAssertFalse(StereoRecordingPreference.load(from: defaults))
    }

    func test_requestedLayoutFallsBackFromSpatialAndSpeechIsAlwaysMono() {
        typealias Layout = RecordingChannelLayout
        for layout in Layout.allCases {
            XCTAssertEqual(Layout.requested(quality: .speech, stored: layout, spatialAvailable: true), .mono)
        }
        for quality in [RecordingQuality.high, .lossless] {
            XCTAssertEqual(Layout.requested(quality: quality, stored: .spatial, spatialAvailable: true), .spatial)
            XCTAssertEqual(Layout.requested(quality: quality, stored: .spatial, spatialAvailable: false), .stereo)
            XCTAssertEqual(Layout.requested(quality: quality, stored: .stereo, spatialAvailable: false), .stereo)
            XCTAssertEqual(Layout.requested(quality: quality, stored: .mono, spatialAvailable: true), .mono)
        }
        XCTAssertEqual(Layout.spatial.fallback, .stereo)
        XCTAssertEqual(Layout.stereo.fallback, .mono)
        XCTAssertNil(Layout.mono.fallback)
    }

    func test_spatialStorageHintsAndGuardCountTheAmbisonicsTrack() {
        typealias Layout = RecordingChannelLayout
        let english = Locale(identifier: "en")
        XCTAssertEqual(Layout.mono.approximateBytesPerMinute(quality: .high), 480_000)
        XCTAssertEqual(Layout.stereo.approximateBytesPerMinute(quality: .high), 960_000)
        XCTAssertEqual(Layout.spatial.approximateBytesPerMinute(quality: .high), 960_000 + 1_920_000)
        XCTAssertEqual(Layout.spatial.approximateBytesPerMinute(quality: .lossless), 5_800_000 + 1_920_000)
        XCTAssertEqual(Layout.spatial.approximateBytesPerMinute(quality: .speech), 240_000)
        XCTAssertEqual(Layout.spatial.approximateMegabytesPerMinuteText(quality: .high, locale: english), "3")
        XCTAssertEqual(Layout.spatial.approximateMegabytesPerMinuteText(quality: .lossless, locale: english), "8")
        XCTAssertEqual(Layout.mono.approximateMegabytesPerMinuteText(quality: .high, locale: english), "0.5")

        typealias Guard = RecordingQualityStorageGuard
        let spatialLossless = Guard.requiredFreeBytes(for: .lossless, layout: .spatial)
        let spatialHigh = Guard.requiredFreeBytes(for: .high, layout: .spatial)
        XCTAssertEqual(spatialLossless, 200_000_000 + 7_720_000 * 90)
        XCTAssertEqual(Guard.requiredFreeBytes(for: .high, layout: .stereo), Guard.requiredFreeBytes(for: .high, channelCount: 2))
        XCTAssertEqual(Guard.effectiveQuality(requested: .lossless, availableBytes: spatialLossless, layout: .spatial), .lossless)
        XCTAssertEqual(Guard.effectiveQuality(requested: .lossless, availableBytes: spatialLossless - 1, layout: .spatial), .high)
        XCTAssertEqual(Guard.effectiveQuality(requested: .high, availableBytes: spatialHigh - 1, layout: .spatial), .speech)
        XCTAssertEqual(Guard.effectiveQuality(requested: .high, availableBytes: nil, layout: .spatial), .high)
    }

    func test_compatibilitySettingsUseTheQualitysStereoEncoding() {
        let high = SpatialAudioRecordingFormat.compatibilitySettings(quality: .high)
        XCTAssertEqual(high[AVFormatIDKey] as? Int, Int(kAudioFormatMPEG4AAC))
        XCTAssertEqual(high[AVNumberOfChannelsKey] as? Int, 2)
        XCTAssertEqual(high[AVEncoderBitRateKey] as? Int, 128_000)
        let lossless = SpatialAudioRecordingFormat.compatibilitySettings(quality: .lossless)
        XCTAssertEqual(lossless[AVFormatIDKey] as? Int, Int(kAudioFormatAppleLossless))
        XCTAssertEqual(lossless[AVNumberOfChannelsKey] as? Int, 2)

        let fallback = SpatialAudioRecordingFormat.ambisonicsSettings(recommended: [AVFormatIDKey: kAudioFormatMPEG4AAC])
        XCTAssertEqual((fallback[AVFormatIDKey] as? NSNumber)?.uint32Value, kAudioFormatAPAC)
        XCTAssertEqual(fallback[AVNumberOfChannelsKey] as? Int, 4)
        let recommended: [String: Any] = [AVFormatIDKey: kAudioFormatAPAC, AVSampleRateKey: 48_000.0, AVNumberOfChannelsKey: 4]
        XCTAssertEqual(SpatialAudioRecordingFormat.ambisonicsSettings(recommended: recommended).count, 3)
    }

    // MARK: - Writer

    func test_writerMakesAPACAmbisonicsPlusDisabledStereoTrackAndOneMetadataSample() async throws {
        let metadata = FakeSpatialMetadata()
        let url = try writeSpatialTake(.high, seconds: 1, metadata: metadata)
        XCTAssertEqual(metadata.analyzed, 50, "every FOA buffer is analyzed once")

        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        XCTAssertEqual(audio.count, 2)
        // Stereo first, so AudioFile-based readers (AVAudioFile,
        // AVAudioPlayer) open it; FOA is the enabled default for AVPlayer.
        let stereo = try await formatAndEnabled(audio[0])
        XCTAssertEqual(stereo.formatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(stereo.channels, 2)
        XCTAssertFalse(stereo.enabled, "stereo is the fallback of the FOA track's alternate group")
        let ambisonics = try await formatAndEnabled(audio[1])
        XCTAssertEqual(ambisonics.formatID, kAudioFormatAPAC)
        XCTAssertEqual(ambisonics.channels, 4)
        XCTAssertTrue(ambisonics.enabled)
        let groups = try await audio[0].loadAssociatedTracks(ofType: .metadataReferent)
        XCTAssertTrue(groups.isEmpty, "only the metadata track refers to another track")
        XCTAssertEqual(KeptAudioInspector.format(of: url)?.channelCount, 2)
        XCTAssertNotNil(try? AVAudioPlayer(contentsOf: url))

        let metadataTracks = try await asset.loadTracks(withMediaType: .metadata)
        XCTAssertEqual(metadataTracks.count, 1)
        let described = try await metadataTracks[0].loadAssociatedTracks(ofType: .metadataReferent)
        XCTAssertEqual(described.map { $0.trackID }, [audio[1].trackID], "the metadata describes the FOA track")
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 1, accuracy: 0.05)
    }

    func test_spatialFileIsRecognizedPreservedAndTranscribedFromItsStereoTrack() throws {
        // Left: 440 Hz at 0.6; right: silence. The copy is the average (0.3).
        let url = try writeSpatialTake(.high, seconds: 2, metadata: FakeSpatialMetadata(), stereoRight: 0)
        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertTrue(KeptAudioInspector.isKeptSpatialRecording(url))
        XCTAssertTrue(KeptAudioInspector.isKeptMultichannelRecording(url))
        XCTAssertFalse(KeptAudioInspector.isKeptStereoRecording(url))
        XCTAssertTrue(KeptAudioInspector.needsTranscriptionCopy(url))
        XCTAssertTrue(KeptAudioInspector.shouldPreserveEncoding(url))
        XCTAssertEqual(KeptAudioInspector.exportFileExtension(for: url), "mp4")
        XCTAssertEqual(AudioFileConverter.duration(of: url) ?? 0, 2, accuracy: 0.05)

        let copy = root.appendingPathComponent("copy.wav")
        try KeptAudioInspector.makeTranscriptionCopy(of: url, at: copy)
        let file = try AVAudioFile(forReading: copy)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / 16_000, 2, accuracy: 0.1)
        XCTAssertFalse(KeptAudioInspector.needsTranscriptionCopy(copy))
        let peak = try peakOf(copy)
        XCTAssertEqual(peak, 0.3, accuracy: 0.05, "left and right are averaged, not added or dropped")
    }

    func test_monoAndStereoKeptFilesAreNotSpatial() throws {
        let mono = root.appendingPathComponent("kept.m4a")
        let writer = try KeptAudioFileWriter(url: mono, quality: .high)
        try writer.append(samples: [Float](repeating: 0.1, count: 48_000))
        XCTAssertNotNil(writer.finalize())
        XCTAssertFalse(KeptAudioInspector.isKeptSpatialRecording(mono))
        XCTAssertEqual(KeptAudioInspector.exportFileExtension(for: mono), "m4a")
        // A plain AAC file named `.mp4` is not treated as Vox.md spatial.
        let renamed = root.appendingPathComponent("kept.mp4")
        try FileManager.default.copyItem(at: mono, to: renamed)
        XCTAssertFalse(KeptAudioInspector.isKeptSpatialRecording(renamed))
    }

    func test_losslessSpatialKeepsAnALACStereoTrack() async throws {
        let url = try writeSpatialTake(.lossless, seconds: 0.5, metadata: FakeSpatialMetadata())
        let audio = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        let stereo = try await formatAndEnabled(audio[0])
        XCTAssertEqual(stereo.formatID, kAudioFormatAppleLossless)
        XCTAssertEqual(stereo.channels, 2)
    }

    func test_pausedAudioIsCutOutOfTheSpatialFile() async throws {
        let url = root.appendingPathComponent("paused.mp4")
        let writer = try makeWriter(url: url, quality: .high, metadata: FakeSpatialMetadata(), start: .zero)
        var time: Int64 = 0
        func feed(seconds: Double) {
            for _ in 0..<Int(seconds * 50) {
                writer.append(try! makeBuffer(channels: 4, start: time), to: .ambisonics, waitIfBusy: 1)
                writer.append(try! makeBuffer(channels: 2, start: time), to: .stereo, waitIfBusy: 1)
                time += 960
            }
        }
        feed(seconds: 1)
        writer.setPaused(true)
        feed(seconds: 1)
        writer.setPaused(false)
        feed(seconds: 1)
        let result = writer.finish()
        XCTAssertEqual(result.summary.droppedBuffers, 0)
        XCTAssertTrue(result.summary.wroteMetadata)
        let duration = try await AVURLAsset(url: try XCTUnwrap(result.url)).load(.duration).seconds
        XCTAssertEqual(duration, 2, accuracy: 0.05)
        XCTAssertEqual(writer.duration, 2, accuracy: 0.001)
    }

    func test_preRollBeforeTheStartTimeIsLeftOut() async throws {
        let url = root.appendingPathComponent("late-start.mp4")
        let start = CMTime(value: 24_000, timescale: 48_000)
        let writer = try makeWriter(url: url, quality: .high, metadata: FakeSpatialMetadata(), start: start)
        var time: Int64 = 0
        for _ in 0..<100 {
            writer.append(try makeBuffer(channels: 4, start: time), to: .ambisonics, waitIfBusy: 1)
            writer.append(try makeBuffer(channels: 2, start: time), to: .stereo, waitIfBusy: 1)
            time += 960
        }
        let result = writer.finish()
        let duration = try await AVURLAsset(url: try XCTUnwrap(result.url)).load(.duration).seconds
        XCTAssertEqual(duration, 1.5, accuracy: 0.05)
    }

    func test_emptyOrDiscardedTakeLeavesNoFile() throws {
        let url = root.appendingPathComponent("empty.mp4")
        let writer = try makeWriter(url: url, quality: .high, metadata: FakeSpatialMetadata(), start: .zero)
        XCTAssertNil(writer.finish().url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let other = root.appendingPathComponent("discarded.mp4")
        let discarded = try makeWriter(url: other, quality: .high, metadata: FakeSpatialMetadata(), start: .zero)
        discarded.append(try makeBuffer(channels: 4, start: 0), to: .ambisonics, waitIfBusy: 1)
        discarded.discard()
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.path))
        XCTAssertFalse(discarded.append(try makeBuffer(channels: 2, start: 0), to: .stereo))
    }

    func test_keptSpatialURLUsesTheUnrecoverablePrefixAndMov() {
        let url = KeptAudioArtifacts.makeURL(in: root, requestID: "req/1", fileExtension: SpatialAudioRecordingFormat.fileExtension)
        XCTAssertTrue(url.lastPathComponent.hasPrefix(KeptAudioArtifacts.filenamePrefix))
        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertFalse(url.lastPathComponent.contains("/"))
    }

    func test_claimedSpatialTakeRecoversAsOneJobWithA16kMonoCopy() async throws {
        let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let take = try writeSpatialTake(.high, seconds: 1, metadata: FakeSpatialMetadata())
        let kept = KeptAudioArtifacts.makeURL(in: recordings, requestID: "spatial", fileExtension: "mp4")
        try FileManager.default.moveItem(at: take, to: kept)
        let journal = recordings.appendingPathComponent("segment_active_spatial_2.wav")
        try Data("journal".utf8).write(to: journal)
        let jobID = UUID()
        try RecordingJobHandoffIntentStore(recordingsDirectoryURL: recordings).save(
            RecordingJobHandoffIntent(
                jobID: jobID,
                readiness: .ready,
                audioFilename: kept.lastPathComponent,
                relatedAudioFilenames: [journal.lastPathComponent],
                createdAt: Date().addingTimeInterval(-120),
                duration: 1,
                source: .iOSApp,
                delivery: .captureDraft(attachAudio: true),
                modelID: "automatic",
                language: "auto",
                configuration: .default
            )
        )
        XCTAssertTrue(KeptAudioArtifacts.removeUnclaimed(in: recordings).isEmpty)

        let store = RecordingJobStore(rootDirectoryURL: root.appendingPathComponent("queue"))
        let recovered = try await store.recoverExternalOrphans(recordingsDirectoryURL: recordings)
        XCTAssertEqual(recovered.map(\.id), [jobID])
        let audio = store.audioURL(for: try XCTUnwrap(recovered.first))
        XCTAssertEqual(audio.pathExtension, "mp4")
        XCTAssertTrue(KeptAudioInspector.isKeptMultichannelRecording(audio))
        let copy = root.appendingPathComponent("recovered-copy.wav")
        try KeptAudioInspector.makeTranscriptionCopy(of: audio, at: copy)
        XCTAssertEqual(try AVAudioFile(forReading: copy).fileFormat.sampleRate, 16_000)
        let again = try await store.recoverExternalOrphans(recordingsDirectoryURL: recordings)
        XCTAssertTrue(again.isEmpty)
    }

    func test_audioAttachmentExportCopiesSpatialBytesAsMov() async throws {
        let kept = try writeSpatialTake(.high, seconds: 1, metadata: FakeSpatialMetadata())
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
        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertEqual(try Data(contentsOf: url), try Data(contentsOf: kept))
        XCTAssertTrue(KeptAudioInspector.isKeptSpatialRecording(url))
    }

    // MARK: - Pre-roll ring and buffers

    func test_ringKeepsOnlyTheNewestWindowOfDeepCopies() throws {
        let ring = SpatialSampleBufferRing(maximumDuration: 0.5)
        var time: Int64 = 0
        for _ in 0..<50 {
            ring.append(try makeBuffer(channels: 4, start: time), track: .ambisonics)
            ring.append(try makeBuffer(channels: 2, start: time), track: .stereo)
            time += 960
        }
        let latest = try XCTUnwrap(ring.latestStereoEnd)
        XCTAssertEqual(latest.seconds, 1, accuracy: 0.001)
        let all = ring.buffers(.stereo, endingAfter: .zero)
        XCTAssertEqual(all.count, 26, "0.5 s window of 20 ms buffers, plus the boundary buffer")
        let recent = ring.buffers(.ambisonics, endingAfter: CMTime(value: 43_200, timescale: 48_000))
        XCTAssertEqual(recent.count, 5)
        ring.removeAll()
        XCTAssertNil(ring.latestStereoEnd)
    }

    func test_pcmBufferReadsStereoSamplesForTheTranscriptionFeed() throws {
        let buffer = try makeBuffer(channels: 2, start: 0, left: 0.5, right: 0.25)
        let pcm = try XCTUnwrap(SpatialAudioSampleBuffers.pcmBuffer(from: buffer))
        XCTAssertEqual(pcm.format.channelCount, 2)
        XCTAssertEqual(pcm.frameLength, 960)
        XCTAssertEqual(SpatialAudioSampleBuffers.channelCount(of: buffer), 2)
        let copy = try XCTUnwrap(SpatialAudioSampleBuffers.deepCopy(buffer))
        XCTAssertEqual(CMSampleBufferGetNumSamples(copy), 960)
        let retimed = try XCTUnwrap(SpatialAudioSampleBuffers.retimed(buffer, to: CMTime(value: 48_000, timescale: 48_000)))
        XCTAssertEqual(CMSampleBufferGetPresentationTimeStamp(retimed).seconds, 1, accuracy: 0.0001)
        XCTAssertEqual(SpatialAudioSampleBuffers.endTime(of: retimed).seconds, 1.02, accuracy: 0.0001)
    }

    // MARK: - Helpers

    private func makeWriter(
        url: URL,
        quality: RecordingQuality,
        metadata: SpatialAudioMetadataSource?,
        start: CMTime
    ) throws -> SpatialAudioFileWriter {
        try SpatialAudioFileWriter(
            url: url,
            quality: quality,
            ambisonicsSettings: SpatialAudioRecordingFormat.ambisonicsSettings(recommended: nil),
            metadata: metadata,
            startTime: start
        )
    }

    private func writeSpatialTake(
        _ quality: RecordingQuality,
        seconds: Double,
        metadata: SpatialAudioMetadataSource?,
        stereoRight: Float = 0.3
    ) throws -> URL {
        let url = root.appendingPathComponent("spatial-\(quality.rawValue)-\(UUID().uuidString).mp4")
        let writer = try makeWriter(url: url, quality: quality, metadata: metadata, start: .zero)
        var time: Int64 = 0
        for _ in 0..<Int(seconds * 50) {
            XCTAssertTrue(writer.append(try makeBuffer(channels: 4, start: time), to: .ambisonics, waitIfBusy: 1))
            XCTAssertTrue(writer.append(
                try makeBuffer(channels: 2, start: time, left: 0.6, right: stereoRight),
                to: .stereo,
                waitIfBusy: 1
            ))
            time += 960
        }
        let result = writer.finish()
        XCTAssertEqual(result.summary.droppedBuffers, 0)
        XCTAssertEqual(result.summary.wroteMetadata, metadata != nil)
        return try XCTUnwrap(result.url, "\(String(describing: writer.error))")
    }

    func test_spatialFileIsAudioOnlyMedia() throws {
        let url = try writeSpatialTake(.high, seconds: 0.5, metadata: FakeSpatialMetadata())
        XCTAssertTrue(MediaFileTracks.isAudioOnly(url))
        XCTAssertFalse(MediaFileTracks.isAudioOnly(url.deletingLastPathComponent().appendingPathComponent("missing.mp4")))
    }

    // MARK: Channel activity (PR #151: FOA with only W, dual-mono stereo)

    private func activity(channels: Int, buffers: Int = 10, left: Float, right: Float) throws -> SpatialChannelActivity {
        var activity = SpatialChannelActivity(channelCount: channels)
        for index in 0..<buffers {
            activity.add(try makeBuffer(channels: channels, start: Int64(index * 960), left: left, right: right))
        }
        return activity
    }

    func test_channelActivity_foaWithOnlyWIsCollapsed() throws {
        let foa = try activity(channels: 4, left: 0.5, right: 0)
        XCTAssertEqual(foa.verdict(minimumSignalFrames: 4_800), .collapsed)
        XCTAssertTrue(foa.summary.contains("-inf"), foa.summary)
    }

    func test_channelActivity_foaWithDirectionalSignalIsMultichannel() throws {
        let foa = try activity(channels: 4, left: 0.5, right: 0.1)
        XCTAssertEqual(foa.verdict(minimumSignalFrames: 4_800), .multichannel)
    }

    func test_channelActivity_dualMonoStereoIsCollapsed() throws {
        XCTAssertEqual(try activity(channels: 2, left: 0.4, right: 0.4).verdict(minimumSignalFrames: 4_800), .collapsed)
        XCTAssertEqual(try activity(channels: 2, left: 0.4, right: 0.2).verdict(minimumSignalFrames: 4_800), .multichannel)
    }

    func test_channelActivity_silenceOrTooLittleAudioIsUndetermined() throws {
        XCTAssertEqual(try activity(channels: 4, left: 0, right: 0).verdict(minimumSignalFrames: 4_800), .undetermined)
        // 2 buffers = 1,920 frames with signal: not enough to judge.
        XCTAssertEqual(try activity(channels: 4, buffers: 2, left: 0.5, right: 0).verdict(minimumSignalFrames: 4_800), .undetermined)
    }

    func test_channelActivity_quietBuffersDoNotCount() throws {
        var foa = SpatialChannelActivity(channelCount: 4)
        // Quiet start (W below the floor, directional louder) is ignored.
        for index in 0..<10 {
            foa.add(try makeBuffer(channels: 4, start: Int64(index * 960), left: 0.00001, right: 0.00005))
        }
        XCTAssertEqual(foa.signalFrames, 0)
        for index in 10..<20 {
            foa.add(try makeBuffer(channels: 4, start: Int64(index * 960), left: 0.5, right: 0))
        }
        XCTAssertEqual(foa.verdict(minimumSignalFrames: 4_800), .collapsed)
    }

    /// 20 ms of interleaved Float32 at 48 kHz: a 440 Hz tone, channel 0 at
    /// `left`, every other channel at `right`.
    private func makeBuffer(
        channels: Int,
        start: Int64,
        frames: Int = 960,
        left: Float = 0.5,
        right: Float = 0.2
    ) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * channels),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(4 * channels),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = channels == 4
            ? SpatialAudioRecordingFormat.ambisonicsLayoutTag
            : kAudioChannelLayoutTag_Stereo
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &asbd, layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &layout,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        ), noErr)
        var samples = [Float](repeating: 0, count: frames * channels)
        for frame in 0..<frames {
            let tone = Float(sin(Double(Int(start) + frame) * 2 * .pi * 440 / 48_000))
            for channel in 0..<channels {
                samples[frame * channels + channel] = tone * (channel == 0 ? left : right)
            }
        }
        let length = samples.count * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: length, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: length, flags: 0, blockBufferOut: &block
        ), noErr)
        let blockBuffer = try XCTUnwrap(block)
        samples.withUnsafeBytes {
            _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: length)
        }
        var sample: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: blockBuffer, formatDescription: try XCTUnwrap(format), sampleCount: frames,
            presentationTimeStamp: CMTime(value: start, timescale: 48_000), packetDescriptions: nil, sampleBufferOut: &sample
        ), noErr)
        return try XCTUnwrap(sample)
    }

    private func formatAndEnabled(_ track: AVAssetTrack) async throws -> (formatID: AudioFormatID, channels: UInt32, enabled: Bool) {
        let descriptions = try await track.load(.formatDescriptions)
        let asbd = try XCTUnwrap(descriptions.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee })
        let enabled = try await track.load(.isEnabled)
        return (asbd.mFormatID, asbd.mChannelsPerFrame, enabled)
    }

    private func peakOf(_ url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let data = try XCTUnwrap(buffer.floatChannelData?[0])
        // Skip the resampler's edges.
        let frames = Int(buffer.frameLength)
        return (frames / 10..<frames * 9 / 10).reduce(Float(0)) { max($0, abs(data[$1])) }
    }
}

/// Stands in for `AVCaptureSpatialAudioMetadataSampleGenerator` (iOS only):
/// a boxed metadata track with one raw-data item, and one sample covering
/// every analyzed buffer.
private final class FakeSpatialMetadata: SpatialAudioMetadataSource {
    private(set) var analyzed = 0
    private var start = CMTime.invalid
    private var end = CMTime.zero
    let formatDescription: CMFormatDescription

    init() {
        let specifications: [[String: Any]] = [[
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.example.spatial",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: kCMMetadataBaseDataType_RawData as String,
        ]]
        var description: CMFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
            allocator: nil,
            metadataType: kCMMetadataFormatType_Boxed,
            metadataSpecifications: specifications as CFArray,
            formatDescriptionOut: &description
        )
        formatDescription = description!
    }

    func analyze(_ sampleBuffer: CMSampleBuffer) -> OSStatus {
        analyzed += 1
        if !start.isValid { start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer) }
        end = SpatialAudioSampleBuffers.endTime(of: sampleBuffer)
        return noErr
    }

    func makeMetadataSample() -> CMSampleBuffer? {
        guard start.isValid else { return nil }
        // Boxed metadata: [size 'local key id'=1 [size 'data' type locale payload]].
        let payload: [UInt8] = [1, 2, 3, 4]
        func be(_ value: UInt32) -> [UInt8] { withUnsafeBytes(of: value.bigEndian, Array.init) }
        let dataBox = be(UInt32(16 + payload.count)) + Array("data".utf8) + be(0) + be(0) + payload
        let bytes = be(UInt32(8 + dataBox.count)) + be(1) + dataBox
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil,
            customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block
        )
        bytes.withUnsafeBytes {
            _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes.count)
        }
        var timing = CMSampleTimingInfo(duration: CMTimeSubtract(end, start), presentationTimeStamp: start, decodeTimeStamp: .invalid)
        var size = bytes.count
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: formatDescription, sampleCount: 1,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
            sampleSizeArray: &size, sampleBufferOut: &sample
        )
        start = .invalid
        return sample
    }
}
