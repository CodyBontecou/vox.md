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
        let english = Locale(identifier: "en")
        let german = Locale(identifier: "de")
        XCTAssertEqual(RecordingQuality.speech.approximateMegabytesPerMinuteText(locale: english), "0.2")
        XCTAssertEqual(RecordingQuality.speech.approximateMegabytesPerMinuteText(locale: german), "0,2")
        XCTAssertEqual(RecordingQuality.lossless.approximateMegabytesPerMinuteText(locale: english), "3")
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

    func test_resamplerConvertsTo48kMonoAcrossChunks() throws {
        let resampler = try XCTUnwrap(KeptAudioResampler(sampleRate: 48_000))
        var total = 0
        for _ in 0..<10 {
            total += resampler.convert(samples: [Float](repeating: 0.1, count: 4_410), sampleRate: 44_100).count
        }
        total += resampler.flush().count
        // 0.1 s × 10 at 48 kHz once the converter's held-back tail is flushed.
        XCTAssertEqual(Double(total), 48_000, accuracy: 100)
        XCTAssertEqual(resampler.convert(samples: [1, 2, 3], sampleRate: 48_000), [1, 2, 3])
    }

    func test_writerResamplesRawMicrophoneSamples() throws {
        let url = root.appendingPathComponent("raw.m4a")
        let writer = try KeptAudioFileWriter(url: url, quality: .high)
        for _ in 0..<20 {
            try writer.append(samples: [Float](repeating: 0.05, count: 4_410), sourceSampleRate: 44_100)
        }
        XCTAssertNotNil(writer.finalize())
        XCTAssertEqual(writer.duration, 2, accuracy: 0.01)
        XCTAssertEqual(KeptAudioInspector.format(of: url)?.sampleRate, 48_000)
    }

    // MARK: - Pre-roll alignment

    func test_preRollSeedCoversTheSameSpanAsTheJournalSeed() {
        // Hardware-rate history and 16 kHz journal fed from the same buffers.
        let history = CircularAudioBuffer(capacity: 48_000 * 4)
        history.append((0..<(48_000 * 3)).map { Float($0) })

        let seed = KeptAudioFileWriter.preRollSeed(
            from: history,
            historySampleRate: 48_000,
            journalSeedCount: 32_000 // 2 s at 16 kHz
        )

        XCTAssertEqual(seed.count, 96_000)
        XCTAssertEqual(seed.first, Float(48_000))
        XCTAssertEqual(seed.last, Float(48_000 * 3 - 1), "Seed must end where the journal seed ends")

        // 44.1 kHz input, odd journal length: duration still matches.
        let other = CircularAudioBuffer(capacity: 44_100 * 4)
        other.append([Float](repeating: 1, count: 44_100 * 3))
        let otherSeed = KeptAudioFileWriter.preRollSeed(
            from: other, historySampleRate: 44_100, journalSeedCount: 24_321
        )
        XCTAssertEqual(Double(otherSeed.count) / 44_100, 24_321 / 16_000, accuracy: 1 / 44_100)
    }

    func test_preRollSeedPadsShortHistoryWithLeadingSilence() {
        let history = CircularAudioBuffer(capacity: 48_000)
        history.append([Float](repeating: 0.5, count: 1_000))

        let seed = KeptAudioFileWriter.preRollSeed(
            from: history, historySampleRate: 48_000, journalSeedCount: 16_000
        )

        XCTAssertEqual(seed.count, 48_000, "Kept file keeps the journal's timeline")
        XCTAssertTrue(seed.prefix(47_000).allSatisfy { $0 == 0 })
        XCTAssertTrue(seed.suffix(1_000).allSatisfy { $0 == 0.5 })
        XCTAssertTrue(KeptAudioFileWriter.preRollSeed(
            from: history, historySampleRate: 48_000, journalSeedCount: 0
        ).isEmpty)
    }

    // MARK: - Crash recovery

    func test_unclaimedKeptTakeIsNeverRecoveredAndJournalIsRecoveredOnce() async throws {
        let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        // Crash after Stop closed the kept file, before the intent was saved.
        let kept = KeptAudioArtifacts.makeURL(in: recordings, requestID: "req", quality: .lossless)
        try Data("kept-lossless".utf8).write(to: kept)
        let journal = recordings.appendingPathComponent("segment_active_req_1.wav")
        try Data("journal".utf8).write(to: journal)
        XCTAssertTrue(kept.lastPathComponent.hasPrefix(KeptAudioArtifacts.filenamePrefix))

        let store = RecordingJobStore(rootDirectoryURL: root.appendingPathComponent("queue"))
        let first = try await store.recoverExternalOrphans(
            recordingsDirectoryURL: recordings, olderThan: Date().addingTimeInterval(60)
        )
        XCTAssertEqual(first.map(\.originalFilename), [journal.lastPathComponent])

        // Next launch: the unclaimed kept file goes, nothing is recovered twice.
        XCTAssertEqual(
            KeptAudioArtifacts.removeUnclaimed(in: recordings).map(\.lastPathComponent),
            [kept.lastPathComponent]
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: kept.path))
        let second = try await store.recoverExternalOrphans(
            recordingsDirectoryURL: recordings, olderThan: Date().addingTimeInterval(60)
        )
        XCTAssertTrue(second.isEmpty)
        let jobs = try await store.load(recoverInterrupted: false)
        XCTAssertEqual(jobs.count, 1)
    }

    func test_claimedKeptTakeRecoversAsOneJobAcrossRepeatedRecovery() async throws {
        let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let kept = KeptAudioArtifacts.makeURL(in: recordings, requestID: "req", quality: .high)
        try Data("kept-high".utf8).write(to: kept)
        let wav = recordings.appendingPathComponent("segment_\(UUID().uuidString).wav")
        try Data("wav".utf8).write(to: wav)
        let journal = recordings.appendingPathComponent("segment_active_req_2.wav")
        try Data("journal".utf8).write(to: journal)
        let createdAt = Date().addingTimeInterval(-120)
        let jobID = UUID()
        // Crash after the handoff intent was saved, before the queue enqueue.
        try RecordingJobHandoffIntentStore(recordingsDirectoryURL: recordings).save(
            RecordingJobHandoffIntent(
                jobID: jobID,
                readiness: .ready,
                audioFilename: kept.lastPathComponent,
                relatedAudioFilenames: [wav.lastPathComponent, journal.lastPathComponent],
                createdAt: createdAt,
                duration: 3,
                source: .iOSApp,
                delivery: .captureDraft(attachAudio: true),
                modelID: "automatic",
                language: "auto",
                configuration: .default
            )
        )

        // Start-up cleanup keeps a claimed kept file.
        XCTAssertTrue(KeptAudioArtifacts.removeUnclaimed(in: recordings).isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))

        let store = RecordingJobStore(rootDirectoryURL: root.appendingPathComponent("queue"))
        let first = try await store.recoverExternalOrphans(recordingsDirectoryURL: recordings)
        XCTAssertEqual(first.map(\.id), [jobID])
        XCTAssertEqual(first.first?.originalFilename, kept.lastPathComponent)
        XCTAssertEqual(first.first?.audioFilename, "\(jobID.uuidString.lowercased()).m4a")
        for leftover in [kept, wav, journal] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: leftover.path), leftover.lastPathComponent)
        }

        let second = try await store.recoverExternalOrphans(recordingsDirectoryURL: recordings)
        XCTAssertTrue(second.isEmpty)
        let jobs = try await store.load(recoverInterrupted: false)
        XCTAssertEqual(jobs.map(\.id), [jobID])
    }

    func test_claimedStereoTakeRecoversAsOneStereoJobWithA16kMonoCopy() async throws {
        let recordings = root.appendingPathComponent("Recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        let kept = KeptAudioArtifacts.makeURL(in: recordings, requestID: "stereo", quality: .lossless)
        let writer = try KeptAudioFileWriter(url: kept, quality: .lossless, channelCount: 2)
        try writer.append(samples: (0..<(48_000 * 2)).map { Float(sin(Double($0 / 2) / 15) * 0.3) })
        XCTAssertNotNil(writer.finalize())
        let journal = recordings.appendingPathComponent("segment_active_stereo_2.wav")
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
        let job = try XCTUnwrap(recovered.first)
        XCTAssertEqual(recovered.map(\.id), [jobID])
        let audio = store.audioURL(for: job)
        let format = try XCTUnwrap(KeptAudioInspector.format(of: audio))
        XCTAssertEqual(format.channelCount, 2)
        XCTAssertEqual(format.sampleRate, 48_000)
        XCTAssertTrue(KeptAudioInspector.isKeptRecordingFormat(audio))
        try assertTranscriptionCopy(of: audio, expectedSeconds: 1)
        let again = try await store.recoverExternalOrphans(recordingsDirectoryURL: recordings)
        XCTAssertTrue(again.isEmpty)
    }

    // MARK: - Storage guard (Watch transfers)

    func test_storageGuardStepsDownWhenSpaceIsShort() {
        let lossless = RecordingQualityStorageGuard.requiredFreeBytes(for: .lossless)
        let high = RecordingQualityStorageGuard.requiredFreeBytes(for: .high)
        XCTAssertGreaterThan(lossless, high)
        // 90 minutes of Lossless ≈ 261 MB on top of the 200 MB floor.
        XCTAssertEqual(lossless, 200_000_000 + 2_900_000 * 90)

        typealias Guard = RecordingQualityStorageGuard
        XCTAssertEqual(Guard.effectiveQuality(requested: .lossless, availableBytes: lossless), .lossless)
        XCTAssertEqual(Guard.effectiveQuality(requested: .lossless, availableBytes: lossless - 1), .high)
        XCTAssertEqual(Guard.effectiveQuality(requested: .lossless, availableBytes: high - 1), .speech)
        XCTAssertEqual(Guard.effectiveQuality(requested: .high, availableBytes: high), .high)
        XCTAssertEqual(Guard.effectiveQuality(requested: .high, availableBytes: high - 1), .speech)
        XCTAssertEqual(Guard.effectiveQuality(requested: .speech, availableBytes: 0), .speech)
        XCTAssertEqual(Guard.effectiveQuality(requested: .lossless, availableBytes: nil), .lossless)
        XCTAssertNotNil(Guard.availableBytes(at: root))
    }

    func test_longLosslessTakeStreamsToA16kTranscriptionCopy() throws {
        // A 5-minute Lossless Watch take: the copy is streamed, not loaded whole.
        let url = root.appendingPathComponent("watch-long.m4a")
        let writer = try KeptAudioFileWriter(url: url, quality: .lossless)
        let minute = (0..<48_000 * 60).map { Float(sin(Double($0) / 30) * 0.2) }
        for _ in 0..<5 { try writer.append(samples: minute) }
        XCTAssertNotNil(writer.finalize())
        let size = try XCTUnwrap(
            try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
        )
        XCTAssertLessThan(size, RecordingQuality.lossless.approximateBytesPerMinute * 5 * 2)

        try assertTranscriptionCopy(of: url, expectedSeconds: 300)
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

    // MARK: - Natural sound and high-quality AirPods

    func test_naturalPreferenceDefaultsOffAndOnlyAppliesToHighAndLossless() throws {
        let suite = "RecordingQualityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(NaturalRecordingPreference.load(from: defaults))
        XCTAssertFalse(NaturalRecordingPreference.load(from: nil))
        NaturalRecordingPreference.save(true, to: defaults)
        XCTAssertTrue(NaturalRecordingPreference.load(from: defaults))
        XCTAssertNotEqual(NaturalRecordingPreference.defaultsKey, StereoRecordingPreference.defaultsKey)
        XCTAssertNotEqual(NaturalRecordingPreference.defaultsKey, RecordingQuality.watchPayloadKey)

        XCTAssertFalse(NaturalRecordingPreference.requestsNatural(quality: .speech, enabled: true))
        XCTAssertTrue(NaturalRecordingPreference.requestsNatural(quality: .high, enabled: true))
        XCTAssertTrue(NaturalRecordingPreference.requestsNatural(quality: .lossless, enabled: true))
        XCTAssertFalse(NaturalRecordingPreference.requestsNatural(quality: .high, enabled: false))
    }

    func test_naturalOnlyAppliesToMonoBecauseMeasurementModeHasNoStereoPattern() {
        // On iPhone 13 Pro Max (iOS 27.2) the `.measurement` mode offers no
        // stereo polar pattern, so Natural would turn Stereo into mono.
        // Stereo and Spatial Audio win and keep the standard mode.
        XCTAssertTrue(NaturalRecordingPreference.requestsNatural(quality: .high, enabled: true, layout: .mono))
        for layout in [RecordingChannelLayout.stereo, .spatial] {
            for quality in [RecordingQuality.high, .lossless] {
                XCTAssertFalse(NaturalRecordingPreference.requestsNatural(quality: quality, enabled: true, layout: layout))
                XCTAssertEqual(
                    KeptAudioInputOptions.forRecording(quality: quality, eligible: true, naturalEnabled: true, layout: layout),
                    KeptAudioInputOptions(highQualityBluetooth: false, naturalInput: false, builtInMicrophone: true),
                    "\(quality) \(layout)"
                )
            }
        }
        XCTAssertEqual(
            KeptAudioInputOptions.forRecording(quality: .lossless, eligible: true, naturalEnabled: true, layout: .mono),
            KeptAudioInputOptions(highQualityBluetooth: true, naturalInput: true)
        )
    }

    func test_stereoAndSpatialRecordFromTheBuiltInMicrophonesWithAirPodsConnected() {
        // 2026-11-24, iPhone 17 Pro with AirPods connected: Spatial Audio was
        // selected, the input was the AirPods (BluetoothHFP) and the take
        // silently recorded mono. Stereo and Spatial pin the built-in mics.
        for layout in [RecordingChannelLayout.stereo, .spatial] {
            for quality in [RecordingQuality.high, .lossless] {
                let options = KeptAudioInputOptions.forRecording(
                    quality: quality, eligible: true, naturalEnabled: false, layout: layout
                )
                XCTAssertTrue(options.builtInMicrophone, "\(quality) \(layout)")
                XCTAssertFalse(options.highQualityBluetooth, "\(quality) \(layout)")
            }
        }
        // Mono keeps recording from AirPods, at high quality.
        let mono = KeptAudioInputOptions.forRecording(quality: .lossless, eligible: true, naturalEnabled: false, layout: .mono)
        XCTAssertFalse(mono.builtInMicrophone)
        XCTAssertTrue(mono.highQualityBluetooth)
        // Dictation, Keyboard Listening and Speech never change the input.
        XCTAssertEqual(KeptAudioInputOptions.forRecording(quality: .lossless, eligible: false, naturalEnabled: false, layout: .spatial), .standard)
        XCTAssertEqual(KeptAudioInputOptions.forRecording(quality: .speech, eligible: true, naturalEnabled: false, layout: .stereo), .standard)
    }

    func test_inputOptionsOnlyChangeForKeptAudioRecordings() {
        // Keyboard Listening, dictation and Speech keep the standard input.
        for quality in RecordingQuality.allCases {
            XCTAssertEqual(
                KeptAudioInputOptions.forRecording(quality: quality, eligible: false, naturalEnabled: true),
                .standard
            )
        }
        XCTAssertEqual(
            KeptAudioInputOptions.forRecording(quality: .speech, eligible: true, naturalEnabled: true),
            .standard
        )

        // High-quality Bluetooth is automatic for High and Lossless; Natural
        // follows its setting.
        XCTAssertEqual(
            KeptAudioInputOptions.forRecording(quality: .high, eligible: true, naturalEnabled: false),
            KeptAudioInputOptions(highQualityBluetooth: true, naturalInput: false)
        )
        XCTAssertEqual(
            KeptAudioInputOptions.forRecording(quality: .lossless, eligible: true, naturalEnabled: true),
            KeptAudioInputOptions(highQualityBluetooth: true, naturalInput: true)
        )
    }

    // MARK: - Stereo (#118)

    func test_stereoPreferenceDefaultsOffAndOnlyAppliesToHighAndLossless() throws {
        let suite = "RecordingQualityTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertFalse(StereoRecordingPreference.load(from: defaults))
        XCTAssertFalse(StereoRecordingPreference.load(from: nil))
        StereoRecordingPreference.save(true, to: defaults)
        XCTAssertTrue(StereoRecordingPreference.load(from: defaults))
        XCTAssertNotEqual(StereoRecordingPreference.defaultsKey, RecordingQuality.watchPayloadKey)

        XCTAssertFalse(StereoRecordingPreference.requestsStereo(quality: .speech, enabled: true))
        XCTAssertTrue(StereoRecordingPreference.requestsStereo(quality: .high, enabled: true))
        XCTAssertTrue(StereoRecordingPreference.requestsStereo(quality: .lossless, enabled: true))
        XCTAssertFalse(StereoRecordingPreference.requestsStereo(quality: .lossless, enabled: false))
        XCTAssertEqual(StereoRecordingPreference.requestedChannelCount(quality: .speech, enabled: true), 1)
        XCTAssertEqual(StereoRecordingPreference.requestedChannelCount(quality: .high, enabled: true), 2)
    }

    func test_stereoSettingsAndStorageHints() {
        let high = RecordingQuality.high.recorderSettings(channelCount: 2)
        XCTAssertEqual(high[AVNumberOfChannelsKey] as? Int, 2)
        XCTAssertEqual(high[AVEncoderBitRateKey] as? Int, 128_000)
        XCTAssertEqual(RecordingQuality.lossless.recorderSettings(channelCount: 2)[AVNumberOfChannelsKey] as? Int, 2)
        // Speech is the transcription format and never records stereo.
        XCTAssertEqual(RecordingQuality.speech.recorderSettings(channelCount: 2)[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(RecordingQuality.high.recorderSettings[AVNumberOfChannelsKey] as? Int, 1)

        XCTAssertEqual(RecordingQuality.high.approximateBytesPerMinute(channelCount: 2), 960_000)
        XCTAssertEqual(RecordingQuality.lossless.approximateBytesPerMinute(channelCount: 2), 5_800_000)
        XCTAssertEqual(RecordingQuality.speech.approximateBytesPerMinute(channelCount: 2), 240_000)
        let english = Locale(identifier: "en")
        XCTAssertEqual(RecordingQuality.high.approximateMegabytesPerMinuteText(channelCount: 2, locale: english), "1")
        XCTAssertEqual(RecordingQuality.lossless.approximateMegabytesPerMinuteText(channelCount: 2, locale: english), "6")

        typealias Guard = RecordingQualityStorageGuard
        let stereoLossless = Guard.requiredFreeBytes(for: .lossless, channelCount: 2)
        XCTAssertGreaterThan(stereoLossless, Guard.requiredFreeBytes(for: .lossless))
        XCTAssertEqual(
            Guard.effectiveQuality(requested: .lossless, availableBytes: stereoLossless - 1, channelCount: 2),
            .high
        )
        XCTAssertEqual(
            Guard.effectiveQuality(requested: .lossless, availableBytes: stereoLossless, channelCount: 2),
            .lossless
        )
    }

    func test_stereoHighAndLosslessAreTwoChannel48kAndTranscriptionCopyIs16kMono() throws {
        for quality in [RecordingQuality.high, .lossless] {
            let kept = try writeStereoRecording(quality, seconds: 1.5)
            let format = try XCTUnwrap(KeptAudioInspector.format(of: kept))
            XCTAssertEqual(format.sampleRate, 48_000)
            XCTAssertEqual(format.channelCount, 2, "\(quality)")
            XCTAssertEqual(format.formatID, quality.formatID)
            XCTAssertTrue(KeptAudioInspector.needsTranscriptionCopy(kept))
            XCTAssertTrue(KeptAudioInspector.shouldPreserveEncoding(kept))
            try assertTranscriptionCopy(of: kept, expectedSeconds: 1.5)
        }
    }

    func test_stereoTranscriptionCopyMixesBothChannels() throws {
        // Left silent, right a tone: the mono copy must still hear the tone,
        // so a person on one side of the phone is transcribed.
        let url = root.appendingPathComponent("stereo-right.m4a")
        let writer = try KeptAudioFileWriter(url: url, quality: .lossless, channelCount: 2)
        var samples = [Float](repeating: 0, count: 48_000 * 2)
        for frame in 0..<48_000 {
            samples[frame * 2 + 1] = Float(sin(2 * Double.pi * 440 * Double(frame) / 48_000) * 0.5)
        }
        try writer.append(samples: samples)
        XCTAssertNotNil(writer.finalize())

        let copy = root.appendingPathComponent("stereo-right.wav")
        try KeptAudioInspector.makeTranscriptionCopy(of: url, at: copy)
        let file = try AVAudioFile(forReading: copy)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        let mono = try XCTUnwrap(buffer.floatChannelData?[0])
        let peak = (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(mono[$1])) }
        XCTAssertGreaterThan(peak, 0.1)
    }

    func test_importConvertersKeepTodaysChannelAndKeptCopiesMixBoth() throws {
        // Right-only stereo file in the kept format.
        let url = root.appendingPathComponent("right-only.m4a")
        let writer = try KeptAudioFileWriter(url: url, quality: .lossless, channelCount: 2)
        var samples = [Float](repeating: 0, count: 48_000 * 2)
        for frame in 0..<48_000 {
            samples[frame * 2 + 1] = Float(sin(2 * Double.pi * 440 * Double(frame) / 48_000) * 0.5)
        }
        try writer.append(samples: samples)
        XCTAssertNotNil(writer.finalize())
        XCTAssertTrue(KeptAudioInspector.isKeptRecordingFormat(url))

        // Imports are transcribed exactly as before: first channel only.
        let whole = root.appendingPathComponent("whole.wav")
        try AudioFileConverter.convertToWhisperWAV(inputURL: url, outputURL: whole)
        let streamed = root.appendingPathComponent("streamed.wav")
        try AudioFileConverter.convertToWhisperWAVStreaming(inputURL: url, outputURL: streamed)
        XCTAssertEqual(try peak(of: whole), 0, accuracy: 0.001)
        XCTAssertEqual(try peak(of: streamed), 0, accuracy: 0.001)

        // Opting in mixes both sides, in either converter.
        let mixedWhole = root.appendingPathComponent("mixed-whole.wav")
        try AudioFileConverter.convertToWhisperWAV(inputURL: url, outputURL: mixedWhole, downmix: true)
        let mixedStreamed = root.appendingPathComponent("mixed-streamed.wav")
        try AudioFileConverter.convertToWhisperWAVStreaming(inputURL: url, outputURL: mixedStreamed, downmix: true)
        XCTAssertGreaterThan(try peak(of: mixedWhole), 0.1)
        XCTAssertGreaterThan(try peak(of: mixedStreamed), 0.1)
    }

    func test_centredStereoMixesToTheSame16kSignalAsMonoWithoutClipping() throws {
        // A loud source heard equally by both mics (a speaker in front of the
        // phone). The downmix averages, so the transcription input matches a
        // mono take of the same signal and never clips.
        let frames = 48_000
        let signal = (0..<frames).map { Float(sin(2 * Double.pi * 300 * Double($0) / 48_000) * 0.9) }
        let mono = root.appendingPathComponent("centre-mono.m4a")
        let monoWriter = try KeptAudioFileWriter(url: mono, quality: .lossless)
        try monoWriter.append(samples: signal)
        XCTAssertNotNil(monoWriter.finalize())
        let stereo = root.appendingPathComponent("centre-stereo.m4a")
        let stereoWriter = try KeptAudioFileWriter(url: stereo, quality: .lossless, channelCount: 2)
        try stereoWriter.append(samples: signal.flatMap { [$0, $0] })
        XCTAssertNotNil(stereoWriter.finalize())

        let monoCopy = root.appendingPathComponent("centre-mono.wav")
        try KeptAudioInspector.makeTranscriptionCopy(of: mono, at: monoCopy)
        let stereoCopy = root.appendingPathComponent("centre-stereo.wav")
        try KeptAudioInspector.makeTranscriptionCopy(of: stereo, at: stereoCopy)
        let monoSamples = try samples(of: monoCopy)
        let stereoSamples = try samples(of: stereoCopy)
        XCTAssertEqual(monoSamples.count, stereoSamples.count)
        let maxDifference = zip(monoSamples, stereoSamples).map { abs($0 - $1) }.max() ?? 1
        XCTAssertLessThan(maxDifference, 0.002, "Centred stereo must transcribe from the mono signal")
        let stereoPeak = stereoSamples.map(abs).max() ?? 0
        XCTAssertEqual(stereoPeak, 0.9, accuracy: 0.02, "Average, not sum: no clipping")

        // The whole-file converter mixes at the same level.
        let wholeCopy = root.appendingPathComponent("centre-whole.wav")
        try AudioFileConverter.convertToWhisperWAV(inputURL: stereo, outputURL: wholeCopy, downmix: true)
        XCTAssertEqual(try samples(of: wholeCopy).map(abs).max() ?? 0, 0.9, accuracy: 0.02)
    }

    func test_keptRecordingFormatExcludesSpeechAndWAV() throws {
        let speech = try writeKeptRecording(.speech, seconds: 0.5)
        XCTAssertFalse(KeptAudioInspector.isKeptRecordingFormat(speech))
        XCTAssertTrue(KeptAudioInspector.isKeptRecordingFormat(try writeKeptRecording(.high, seconds: 0.5)))
        let wav = root.appendingPathComponent("speech.wav")
        try KeptAudioInspector.makeTranscriptionCopy(of: speech, at: wav)
        XCTAssertFalse(KeptAudioInspector.isKeptRecordingFormat(wav))
        // Only stereo takes change their recovered path.
        XCTAssertFalse(KeptAudioInspector.isKeptStereoRecording(try writeKeptRecording(.lossless, seconds: 0.5)))
        XCTAssertTrue(KeptAudioInspector.isKeptStereoRecording(try writeStereoRecording(.high, seconds: 0.5)))
        XCTAssertFalse(KeptAudioInspector.isKeptStereoRecording(wav))
    }

    func test_stereoWriterResamplesInterleavedFramesAndKeepsChannelsApart() throws {
        let resampler = try XCTUnwrap(KeptAudioResampler(sampleRate: 48_000, channelCount: 2))
        var out: [Float] = []
        for _ in 0..<10 {
            var chunk = [Float](repeating: 0, count: 4_410 * 2)
            for frame in 0..<4_410 { chunk[frame * 2] = 0.25; chunk[frame * 2 + 1] = -0.25 }
            out += resampler.convert(samples: chunk, sampleRate: 44_100)
        }
        out += resampler.flush()
        XCTAssertEqual(out.count % 2, 0)
        XCTAssertEqual(Double(out.count / 2), 48_000, accuracy: 100)
        // Away from the filter edges, left stays positive and right negative.
        let middle = out.count / 4 * 2
        XCTAssertEqual(out[middle], 0.25, accuracy: 0.01)
        XCTAssertEqual(out[middle + 1], -0.25, accuracy: 0.01)

        let url = root.appendingPathComponent("raw-stereo.m4a")
        let writer = try KeptAudioFileWriter(url: url, quality: .high, channelCount: 2)
        XCTAssertEqual(writer.channelCount, 2)
        for _ in 0..<20 {
            try writer.append(samples: [Float](repeating: 0.05, count: 4_410 * 2), sourceSampleRate: 44_100)
        }
        XCTAssertNotNil(writer.finalize())
        XCTAssertEqual(writer.duration, 2, accuracy: 0.01)
        XCTAssertEqual(KeptAudioInspector.format(of: url)?.channelCount, 2)
    }

    func test_stereoPreRollSeedIsWholeFramesOnTheJournalTimeline() {
        // Interleaved history: frame n is (n, -n).
        let frames = 48_000 * 3
        let history = CircularAudioBuffer(capacity: 48_000 * 4 * 2)
        var interleaved = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames { interleaved[frame * 2] = Float(frame); interleaved[frame * 2 + 1] = -Float(frame) }
        history.append(interleaved)

        let seed = KeptAudioFileWriter.preRollSeed(
            from: history, historySampleRate: 48_000, journalSeedCount: 32_000, channelCount: 2
        )
        XCTAssertEqual(seed.count, 96_000 * 2)
        XCTAssertEqual(seed[0], Float(48_000))
        XCTAssertEqual(seed[1], -Float(48_000))
        XCTAssertEqual(seed[seed.count - 2], Float(frames - 1))
        XCTAssertEqual(seed[seed.count - 1], -Float(frames - 1))

        // Short history pads whole silent frames in front.
        let short = CircularAudioBuffer(capacity: 48_000 * 2)
        short.append([Float](repeating: 0.5, count: 1_000 * 2))
        let padded = KeptAudioFileWriter.preRollSeed(
            from: short, historySampleRate: 48_000, journalSeedCount: 16_000, channelCount: 2
        )
        XCTAssertEqual(padded.count, 48_000 * 2)
        XCTAssertTrue(padded.prefix(47_000 * 2).allSatisfy { $0 == 0 })
        XCTAssertTrue(padded.suffix(1_000 * 2).allSatisfy { $0 == 0.5 })
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

    private func writeStereoRecording(_ quality: RecordingQuality, seconds: Double) throws -> URL {
        let url = root.appendingPathComponent("kept-stereo-\(quality.rawValue).m4a")
        let writer = try KeptAudioFileWriter(url: url, quality: quality, channelCount: 2)
        let frames = Int(quality.sampleRate * seconds)
        var samples = [Float](repeating: 0, count: frames * 2)
        for frame in 0..<frames {
            let t = Double(frame) / quality.sampleRate
            samples[frame * 2] = Float(sin(2 * Double.pi * 440 * t) * 0.3)
            samples[frame * 2 + 1] = Float(sin(2 * Double.pi * 660 * t) * 0.3)
        }
        try writer.append(samples: samples)
        XCTAssertEqual(writer.duration, seconds, accuracy: 0.001)
        return try XCTUnwrap(writer.finalize())
    }

    private func samples(of url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        let data = try XCTUnwrap(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }

    private func peak(of url: URL) throws -> Float {
        let file = try AVAudioFile(forReading: url)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ))
        try file.read(into: buffer)
        let mono = try XCTUnwrap(buffer.floatChannelData?[0])
        return (0..<Int(buffer.frameLength)).reduce(Float(0)) { max($0, abs(mono[$1])) }
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
