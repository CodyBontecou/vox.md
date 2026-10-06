import AVFoundation
import XCTest
@testable import VoxboardShared

final class RecordingStitchTests: XCTestCase {
    func testNearbySuggestionsAreChronologicalAndNeverCrossPresetOrLargeGap() {
        let a = job(at: 100, preset: "a")
        let b = job(at: 200, preset: "a")
        let c = job(at: 1_000, preset: "a")
        let d = job(at: 1_010, preset: "b")
        let groups = RecordingStitchSuggestions.groups(in: [d, b, c, a])
        XCTAssertEqual(groups.map(\.recordingIDs), [[a.id, b.id]])
    }

    func testSuggestionsUseRecordedDurationAndIgnoreBusyAndDerivedJobs() {
        let a = job(at: 100)
        var b = job(at: 650)
        b.duration = 540 // The nine-minute clip ends near its predecessor.
        var busy = job(at: 655)
        busy.phase = .processing
        var derivative = job(at: 660)
        derivative.stitch = RecordingStitch(clips: [
            .init(recordingID: a.id, createdAt: a.createdAt, duration: a.duration),
            .init(recordingID: b.id, createdAt: b.createdAt, duration: b.duration),
        ])
        let groups = RecordingStitchSuggestions.groups(in: [derivative, b, busy, a])
        XCTAssertEqual(groups.map(\.recordingIDs), [[a.id, b.id]])
        XCTAssertFalse(derivative.canBeStitched)
    }

    func testLargeOverlappingFilesAreNotSuggestedAsSequentialClips() {
        var a = job(at: 200)
        var b = job(at: 210)
        a.duration = 100
        b.duration = 100
        XCTAssertTrue(RecordingStitchSuggestions.groups(in: [a, b]).isEmpty)
    }

    func testStitchPreservesOriginalBytesAndStateAndSurvivesRelaunch() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let first = try await f.recording(at: 100, sample: 0.25)
        let second = try await f.recording(at: 200, sample: -0.25)
        let originalBytes = try [first, second].map { try Data(contentsOf: f.store.audioURL(for: $0)) }
        let stitched = try await f.store.stitch(recordingIDs: [second.id, first.id])
        XCTAssertEqual(stitched.stitch?.recordingIDs, [first.id, second.id])
        XCTAssertEqual(stitched.delivery, .recovery)
        XCTAssertEqual(stitched.processingPolicy, .manual)
        XCTAssertEqual(stitched.phase, .queued)
        XCTAssertEqual(stitched.retentionPolicy, .permanent)
        XCTAssertEqual(stitched.duration, 0.2, accuracy: 0.002)
        let file = try AVAudioFile(forReading: f.store.audioURL(for: stitched))
        XCTAssertEqual(file.length, 3_200)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 3_200))
        try file.read(into: buffer)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        XCTAssertEqual(samples[0], 0.25, accuracy: 0.0001)
        XCTAssertEqual(samples[1_600], -0.25, accuracy: 0.0001)
        let relaunched = RecordingJobStore(rootDirectoryURL: f.store.rootDirectoryURL, coordinator: ProcessLocalCaptureFileCoordinator())
        let loaded = try await relaunched.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.first(where: { $0.id == stitched.id })?.stitch, stitched.stitch)
        for (index, original) in [first, second].enumerated() {
            XCTAssertEqual(loaded.first(where: { $0.id == original.id }), original)
            XCTAssertEqual(try Data(contentsOf: f.store.audioURL(for: original)), originalBytes[index])
        }
    }

    func testStitchedOriginalsSurviveRetentionAndUndoOnlyRemovesDerivative() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let originals = try await [f.recording(at: 100), f.recording(at: 200)]
        for original in originals {
            _ = try await f.store.claim(id: original.id)
            _ = try await f.store.updateRetention(id: original.id, policy: .timed(60))
            _ = try await f.store.markCompleted(id: original.id)
        }
        let stitched = try await f.store.stitch(recordingIDs: originals.map(\.id))
        let cleaned = try await f.store.performRetentionCleanup(now: .distantFuture)
        XCTAssertFalse(cleaned.contains(where: { originals.map(\.id).contains($0) }))
        do {
            _ = try await f.store.discard(id: originals[0].id)
            XCTFail("An original must not be deleted while its stitch owns it")
        } catch { XCTAssertEqual(error as? RecordingStitchError, .originalInUse) }
        _ = try await f.store.discard(id: stitched.id)
        _ = try await f.store.performRetentionCleanup(now: .distantFuture)
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.store.audioURL(for: stitched).path))
        for original in originals {
            let remaining = try await f.store.job(id: original.id)
            XCTAssertEqual(remaining?.phase, .completed)
            XCTAssertNil(remaining?.audioDeletedAt)
            XCTAssertTrue(FileManager.default.fileExists(atPath: f.store.audioURL(for: original).path))
        }
    }

    func testDuplicateBusyMissingOrAlreadyGroupedSelectionsFailWithoutChangingOriginals() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let a = try await f.recording(at: 100)
        let b = try await f.recording(at: 200)
        for ids in [[a.id], [a.id, a.id], [a.id, UUID()]] {
            do { _ = try await f.store.stitch(recordingIDs: ids); XCTFail("Invalid selection was stitched") }
            catch {}
        }
        _ = try await f.store.claim(id: a.id)
        do { _ = try await f.store.stitch(recordingIDs: [a.id, b.id]); XCTFail("Busy recording was stitched") }
        catch { XCTAssertEqual(error as? RecordingStitchError, .unavailableClip) }
        _ = try await f.store.markFailed(id: a.id, stage: .transcription, message: "Synthetic failure")
        _ = try await f.store.stitch(recordingIDs: [a.id, b.id])
        do { _ = try await f.store.stitch(recordingIDs: [a.id, b.id]); XCTFail("Originals were grouped twice") }
        catch { XCTAssertEqual(error as? RecordingStitchError, .alreadyStitched) }
    }

    func testCopyFailureAndInvalidAudioDoNotPublishPartialStitchOrLoseOriginals() async throws {
        let fm = StitchCopyFailureFileManager()
        let f = try Fixture(fileManager: fm)
        defer { f.cleanup() }
        let a = try await f.recording(at: 100)
        let b = try await f.recording(at: 200)
        fm.failCopy = true
        do { _ = try await f.store.stitch(recordingIDs: [a.id, b.id]); XCTFail("Expected copy failure") }
        catch {}
        fm.failCopy = false
        let before = try await f.store.load()
        XCTAssertEqual(Set(before.map(\.id)), Set([a.id, b.id]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.store.audioURL(for: a).path))
        try Data(repeating: 1, count: 64).write(to: f.store.audioURL(for: b))
        do { _ = try await f.store.stitch(recordingIDs: [a.id, b.id]); XCTFail("Malformed audio was accepted") }
        catch { XCTAssertEqual(error as? RecordingStitchError, .invalidAudio) }
        let after = try await f.store.load()
        XCTAssertEqual(Set(after.map(\.id)), Set([a.id, b.id]))
    }

    @MainActor
    func testQueueHidesGroupedOriginalsButIndividualViewRestoresThemWithoutImplicitDelivery() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let a = try await f.recording(at: 100)
        let b = try await f.recording(at: 200)
        _ = try await f.store.markFailed(id: a.id, stage: .delivery, message: "Synthetic delivery error")
        _ = try await f.store.markFailed(id: b.id, stage: .delivery, message: "Synthetic delivery error")
        var executions = 0
        let queue = RecordingJobQueue(store: f.store) { _, _, _ in
            executions += 1
            return .init()
        }
        await queue.refresh()
        XCTAssertEqual(queue.retryAllEligibleJobs.count, 2)
        let stitched = try await queue.stitchRecordings([b.id, a.id])
        XCTAssertFalse(queue.isStitching)
        XCTAssertFalse(queue.isCaptureActive)
        XCTAssertEqual(queue.visibleJobs(showIndividualClips: false).map(\.id), [stitched.id])
        XCTAssertEqual(Set(queue.visibleJobs(showIndividualClips: true).map(\.id)), Set([a.id, b.id]))
        XCTAssertTrue(queue.retryAllEligibleJobs.isEmpty)
        XCTAssertEqual(queue.retryAllEligibleJobs(showIndividualClips: true).count, 2)
        XCTAssertEqual(queue.pendingCount, 1)
        queue.resume(includeIdle: true)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(executions, 0)
        await queue.discard(stitched)
        XCTAssertEqual(Set(queue.visibleJobs(showIndividualClips: false).map(\.id)), Set([a.id, b.id]))
    }

    func testCancelledStitchLeavesOriginalsAndNoDerivative() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let a = try await f.recording(at: 100)
        let b = try await f.recording(at: 200)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await f.store.stitch(recordingIDs: [a.id, b.id])
        }
        do { _ = try await task.value; XCTFail("Cancelled stitch was committed") }
        catch is CancellationError {}
        let loaded = try await f.store.load()
        XCTAssertEqual(Set(loaded.map(\.id)), Set([a.id, b.id]))
        XCTAssertTrue(loaded.allSatisfy { $0.stitch == nil })
    }

    func testLongRecordingStreamsWithoutTruncation() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let a = try await f.recording(at: 100)
        let longURL = f.root.appendingPathComponent("nine-minutes.wav")
        let writer = try IncrementalWAVWriter(url: longURL)
        let block = [Float](repeating: 0.15, count: 160_000)
        for _ in 0..<54 { try writer.append(samples: block) }
        try writer.finalize()
        let b = try await f.store.enqueue(sourceURL: longURL, createdAt: Date(timeIntervalSince1970: 700),
            duration: 540, source: .iOSApp, delivery: a.delivery, modelID: "automatic", language: "en",
            configuration: .init(sourceAudioRetention: .permanent, processingPolicy: .manual))
        let stitched = try await f.store.stitch(recordingIDs: [a.id, b.id])
        XCTAssertEqual(stitched.duration, 540.1, accuracy: 0.002)
        let file = try AVAudioFile(forReading: f.store.audioURL(for: stitched))
        XCTAssertEqual(file.length, 8_641_600)
    }

    func testSuggestionsDoNotCrossKnownContinuousSessions() {
        var a = job(at: 100)
        var b = job(at: 120)
        a.requestID = "inapp-session-one-c1"
        b.requestID = "inapp-session-two-c2"
        XCTAssertTrue(RecordingStitchSuggestions.groups(in: [a, b]).isEmpty)
        b.requestID = "inapp-session-one"
        XCTAssertEqual(RecordingStitchSuggestions.groups(in: [a, b]).count, 1)
    }

    func testMixedSampleRatesAreNormalizedWithoutLosingClipTails() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let a = try await f.recording(at: 100)
        let b = try await f.recording(at: 200, sample: -0.2, sampleRate: 8_000)
        let stitched = try await f.store.stitch(recordingIDs: [a.id, b.id])
        XCTAssertEqual(stitched.duration, 0.3, accuracy: 0.001)
        let file = try AVAudioFile(forReading: f.store.audioURL(for: stitched))
        XCTAssertEqual(file.processingFormat.sampleRate, 16_000)
        XCTAssertEqual(file.processingFormat.channelCount, 1)
        file.framePosition = file.length - 64
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 32))
        try file.read(into: buffer, frameCount: 32)
        XCTAssertEqual(try XCTUnwrap(buffer.floatChannelData?[0])[0], -0.2, accuracy: 0.002)
    }

    func testInterruptedBundleCommitRecoversStitchProvenanceBeforeRetention() async throws {
        for audioAlreadyPublished in [false, true] {
            try await verifyInterruptedBundleCommit(audioAlreadyPublished: audioAlreadyPublished)
        }
    }

    private func verifyInterruptedBundleCommit(audioAlreadyPublished: Bool) async throws {
        let fm = StitchCopyFailureFileManager()
        let f = try Fixture(fileManager: fm)
        defer { f.cleanup() }
        let a = try await f.recording(at: 100)
        let b = try await f.recording(at: 200)
        for original in [a, b] {
            _ = try await f.store.claim(id: original.id)
            _ = try await f.store.updateRetention(id: original.id, policy: .timed(60))
            _ = try await f.store.markCompleted(id: original.id)
        }
        let id = UUID()
        let filename = "\(id.uuidString.lowercased())-primaryAudio.wav"
        let temporary = f.root.appendingPathComponent("stitch-interrupted.wav")
        try AudioFileConverter.concatenateToWhisperWAVStreaming(
            inputURLs: [f.store.audioURL(for: a), f.store.audioURL(for: b)], outputURL: temporary)
        let expected = RecordingJob(id: id, audioFilename: filename,
            artifacts: [.init(role: .primaryAudio, filename: filename, originalFilename: temporary.lastPathComponent)],
            stitch: .init(clips: [a, b].map { .init(recordingID: $0.id, createdAt: $0.createdAt, duration: $0.duration) }),
            duration: 0.2, source: .recovered, delivery: .recovery, modelID: "automatic", language: "en",
            retentionPolicy: .permanent, processingPolicy: .manual)
        let intent = try RecordingBundleEnqueueIntent(job: expected, sources: [.init(
            role: .primaryAudio, sourcePath: temporary.path, expectedByteCount: Int64(Data(contentsOf: temporary).count),
            filename: filename, originalFilename: temporary.lastPathComponent)], removeSourcesAfterCommit: true)
        let intentURL = f.store.rootDirectoryURL.appendingPathComponent("bundle-intents/\(id.uuidString.lowercased()).json")
        try JSONEncoder().encode(intent).write(to: intentURL)
        // Simulate exit both before and after audio publication. A full disk
        // may prevent reconciliation, but must not release the original hold.
        if audioAlreadyPublished {
            try FileManager.default.copyItem(at: temporary, to: f.store.audioURL(for: expected))
        } else { fm.failCopy = true }
        let relaunched = RecordingJobStore(rootDirectoryURL: f.store.rootDirectoryURL,
            coordinator: ProcessLocalCaptureFileCoordinator(), fileManager: fm)
        // Cleanup may run before load/reconciliation in another process. The
        // pending commit's provenance must already protect its source clips.
        let removed = try await relaunched.performRetentionCleanup(now: .distantFuture)
        XCTAssertTrue(removed.isEmpty)
        if !audioAlreadyPublished {
            do { _ = try await relaunched.discard(id: a.id); XCTFail("Pending stitch lost its original hold") }
            catch { XCTAssertEqual(error as? RecordingStitchError, .originalInUse) }
            do { _ = try await relaunched.stitch(recordingIDs: [a.id, b.id]); XCTFail("Pending stitch was duplicated") }
            catch { XCTAssertEqual(error as? RecordingStitchError, .alreadyStitched) }
        }
        fm.failCopy = false
        let loaded = try await relaunched.load()
        XCTAssertEqual(loaded.count, 3)
        XCTAssertEqual(loaded.first(where: { $0.id == id }), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: intentURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.store.audioURL(for: a).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.store.audioURL(for: b).path))
    }

    @MainActor
    func testProcessingRequiresExplicitPresetAndExecutesOnlyTheDerivative() async throws {
        let f = try Fixture()
        defer { f.cleanup() }
        let a = try await f.recording(at: 100)
        let b = try await f.recording(at: 200)
        var executions: [UUID] = []
        let queue = RecordingJobQueue(store: f.store) { job, _, _ in
            executions.append(job.id)
            return .init()
        }
        let stitched = try await queue.stitchRecordings([a.id, b.id])
        do { _ = try await f.store.processNow(id: stitched.id); XCTFail("No preset was chosen") }
        catch { XCTAssertEqual(error as? RecordingStitchError, .choosePreset) }
        await queue.retry(stitched, delivery: a.delivery)
        for _ in 0..<100 {
            if !queue.isProcessing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(executions, [stitched.id])
        XCTAssertNil(queue.lastError)
    }

    private func job(at seconds: TimeInterval, preset: String = "same") -> RecordingJob {
        RecordingJob(audioFilename: "\(UUID()).wav", createdAt: Date(timeIntervalSince1970: seconds),
            duration: 10, source: .iOSApp,
            delivery: .preset(CapturePreset(id: preset, name: preset, symbolName: "mic")),
            modelID: "automatic", language: "en", retentionPolicy: .permanent,
            processingPolicy: .manual, phase: .failed)
    }

    private struct Fixture {
        let root: URL
        let store: RecordingJobStore
        init(fileManager: FileManager = .default) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("RecordingStitchTests-\(UUID())")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            store = RecordingJobStore(rootDirectoryURL: root.appendingPathComponent("queue"),
                coordinator: ProcessLocalCaptureFileCoordinator(), fileManager: fileManager)
        }
        func recording(at seconds: TimeInterval, sample: Float = 0.2, sampleRate: Double = 16_000) async throws -> RecordingJob {
            let url = root.appendingPathComponent("\(UUID()).wav")
            try AudioFileConverter.writeWAV(samples: [Float](repeating: sample, count: 1_600), to: url, sampleRate: sampleRate)
            return try await store.enqueue(sourceURL: url, createdAt: Date(timeIntervalSince1970: seconds),
                duration: 1_600 / sampleRate, source: .iOSApp,
                delivery: .preset(CapturePreset(id: "same", name: "Same", symbolName: "mic")),
                modelID: "automatic", language: "en",
                configuration: .init(sourceAudioRetention: .permanent, processingPolicy: .manual))
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }
}

private final class StitchCopyFailureFileManager: FileManager, @unchecked Sendable {
    var failCopy = false
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if failCopy { throw CocoaError(.fileWriteOutOfSpace) }
        try super.copyItem(at: srcURL, to: dstURL)
    }
}
