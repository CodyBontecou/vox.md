#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
import Foundation

/// File format of a Spatial Audio kept recording (#133).
///
/// An MPEG-4 file (`.mp4`) holding:
/// 1. a stereo compatibility track (AAC for High, ALAC for Lossless), first
///    and disabled, for players without APAC;
/// 2. a first-order ambisonics (FOA) track, four channels ACN/SN3D, encoded
///    as APAC; enabled, the default of the alternate group both tracks share,
///    so AVFoundation players (AVPlayer, Photos, Files) choose it;
/// 3. one timed-metadata sample describing the spatial audio, made by
///    `AVCaptureSpatialAudioMetadataSampleGenerator` on iOS 26, associated
///    with the FOA track.
///
/// Why this container and order: `.m4a` can't hold APAC (AVAssetWriter
/// rejects it). iOS's AudioFile (AVAudioFile, AVAudioPlayer) can't open
/// QuickTime `.mov` at all, but opens `.mp4` and reads its first audio
/// track, so with stereo first the app's existing duration checks, players
/// and 16 kHz conversion keep working on a spatial file.
public enum SpatialAudioRecordingFormat {
    public static let fileExtension = "mp4"
    public static let fileType: AVFileType = .mp4
    public static let ambisonicsChannelCount = 4
    /// `kAudioChannelLayoutTag_HOA_ACN_SN3D | 4`: first-order ambisonics.
    public static let ambisonicsLayoutTag: AudioChannelLayoutTag = kAudioChannelLayoutTag_HOA_ACN_SN3D | 4
    public static let sampleRate: Double = 48_000

    static func channelLayoutData(_ tag: AudioChannelLayoutTag) -> Data {
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = tag
        return Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)
    }

    /// Writer settings for the FOA track. Uses what the capture output
    /// recommends when that is APAC; otherwise 48 kHz four-channel APAC.
    public static func ambisonicsSettings(recommended: [String: Any]?) -> [String: Any] {
        if let recommended,
           (recommended[AVFormatIDKey] as? NSNumber)?.uint32Value == kAudioFormatAPAC {
            return recommended
        }
        return [
            AVFormatIDKey: kAudioFormatAPAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: ambisonicsChannelCount,
            AVChannelLayoutKey: channelLayoutData(ambisonicsLayoutTag),
        ]
    }

    /// Writer settings for the stereo compatibility track: the chosen
    /// quality's own stereo encoding (AAC ≈ 128 kbps for High, ALAC for
    /// Lossless), so a spatial take never sounds worse than a stereo one in a
    /// player that ignores the FOA track.
    public static func compatibilitySettings(quality: RecordingQuality) -> [String: Any] {
        var settings = quality.recorderSettings(channelCount: 2)
        settings[AVChannelLayoutKey] = channelLayoutData(kAudioChannelLayoutTag_Stereo)
        // AVAssetWriter takes the AAC bit rate; the quality key is an
        // AVAudioRecorder setting it doesn't need.
        settings.removeValue(forKey: AVEncoderAudioQualityKey)
        return settings
    }
}

/// Produces the spatial audio timed-metadata sample. On iPhone this wraps
/// `AVCaptureSpatialAudioMetadataSampleGenerator` (iOS 26); tests use a fake.
public protocol SpatialAudioMetadataSource: AnyObject {
    /// Format of the metadata track (`sourceFormatHint` of its writer input).
    var formatDescription: CMFormatDescription { get }
    /// Must see every FOA buffer that goes into the file, in order.
    func analyze(_ sampleBuffer: CMSampleBuffer) -> OSStatus
    /// The one metadata sample for everything analyzed; resets the analyzer.
    func makeMetadataSample() -> CMSampleBuffer?
}

/// Sample buffer helpers for spatial capture.
public enum SpatialAudioSampleBuffers {
    /// A copy that owns its audio bytes, so pre-roll can hold buffers without
    /// keeping the capture output's buffers alive.
    public static func deepCopy(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let source = CMSampleBufferGetDataBuffer(sampleBuffer),
              let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        var copy: CMBlockBuffer?
        guard CMBlockBufferCreateContiguous(
            allocator: kCFAllocatorDefault,
            sourceBuffer: source,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: 0,
            flags: kCMBlockBufferAlwaysCopyDataFlag,
            blockBufferOut: &copy
        ) == noErr, let copy else { return nil }
        var result: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: copy,
            formatDescription: format,
            sampleCount: CMSampleBufferGetNumSamples(sampleBuffer),
            presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
            packetDescriptions: nil,
            sampleBufferOut: &result
        ) == noErr else { return nil }
        return result
    }

    /// The same audio at `presentationTime`.
    public static func retimed(_ sampleBuffer: CMSampleBuffer, to presentationTime: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sampleBuffer, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard count > 0 else { return nil }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
        guard CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count
        ) == noErr else { return nil }
        let shift = CMTimeSubtract(presentationTime, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        for index in timing.indices {
            timing[index].presentationTimeStamp = CMTimeAdd(timing[index].presentationTimeStamp, shift)
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = CMTimeAdd(timing[index].decodeTimeStamp, shift)
            }
        }
        var result: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: count,
            sampleTimingArray: &timing,
            sampleBufferOut: &result
        ) == noErr else { return nil }
        return result
    }

    public static func endTime(of sampleBuffer: CMSampleBuffer) -> CMTime {
        let start = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let duration = CMSampleBufferGetDuration(sampleBuffer)
        if duration.isValid, duration > .zero { return CMTimeAdd(start, duration) }
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
              asbd.mSampleRate > 0 else { return start }
        let frames = CMTime(
            value: CMTimeValue(CMSampleBufferGetNumSamples(sampleBuffer)),
            timescale: CMTimeScale(asbd.mSampleRate)
        )
        return CMTimeAdd(start, frames)
    }

    /// Channels of an LPCM sample buffer (0 when unknown).
    public static func channelCount(of sampleBuffer: CMSampleBuffer) -> Int {
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else { return 0 }
        return Int(asbd.mChannelsPerFrame)
    }

    /// The audio of an LPCM sample buffer as an `AVAudioPCMBuffer`, in the
    /// buffer's own format (for the live 16 kHz transcription feed).
    public static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        // The buffer list's byte sizes follow frameLength; size it first.
        buffer.frameLength = frames
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList
        ) == noErr else { return nil }
        return buffer
    }
}

/// Recent FOA and stereo capture buffers, so a spatial take gets the same
/// pre-roll as the 16 kHz journal. Holds deep copies, bounded by duration.
/// Thread-safe.
public final class SpatialSampleBufferRing: @unchecked Sendable {
    public enum Track: Sendable { case ambisonics, stereo }

    public let maximumDuration: CMTime
    private let lock = NSLock()
    private var ambisonics: [CMSampleBuffer] = []
    private var stereo: [CMSampleBuffer] = []

    public init(maximumDuration seconds: TimeInterval) {
        maximumDuration = CMTime(seconds: seconds, preferredTimescale: 48_000)
    }

    public func append(_ sampleBuffer: CMSampleBuffer, track: Track) {
        guard let copy = SpatialAudioSampleBuffers.deepCopy(sampleBuffer) else { return }
        lock.withLock {
            switch track {
            case .ambisonics: Self.append(copy, to: &ambisonics, keeping: maximumDuration)
            case .stereo: Self.append(copy, to: &stereo, keeping: maximumDuration)
            }
        }
    }

    /// End time of the newest stereo buffer, the clock the 16 kHz journal
    /// follows (it is fed from the stereo output).
    public var latestStereoEnd: CMTime? {
        lock.withLock { stereo.last.map(SpatialAudioSampleBuffers.endTime(of:)) }
    }

    /// Buffers of `track` that end after `time`, oldest first.
    public func buffers(_ track: Track, endingAfter time: CMTime) -> [CMSampleBuffer] {
        lock.withLock {
            (track == .ambisonics ? ambisonics : stereo)
                .filter { SpatialAudioSampleBuffers.endTime(of: $0) > time }
        }
    }

    public func removeAll() {
        lock.withLock {
            ambisonics.removeAll()
            stereo.removeAll()
        }
    }

    private static func append(_ buffer: CMSampleBuffer, to list: inout [CMSampleBuffer], keeping window: CMTime) {
        list.append(buffer)
        let newest = SpatialAudioSampleBuffers.endTime(of: buffer)
        while let first = list.first,
              CMTimeSubtract(newest, SpatialAudioSampleBuffers.endTime(of: first)) > window {
            list.removeFirst()
        }
    }
}

/// Writes one Spatial Audio take (see `SpatialAudioRecordingFormat`) from the
/// capture session's FOA and stereo buffers.
///
/// Appends come from the capture queue and never block it for long: a buffer
/// the encoder isn't ready for is dropped and counted. Paused intervals are
/// cut out (later buffers are shifted back), like the mono and stereo kept
/// files. Thread-safe.
public final class SpatialAudioFileWriter: @unchecked Sendable {
    public typealias Track = SpatialSampleBufferRing.Track

    public enum WriterError: Error {
        case cannotAddInput(String)
        case cannotStart(Error?)
    }

    public let url: URL
    public let quality: RecordingQuality
    /// Source time (capture clock) where the file starts.
    public let startTime: CMTime

    private let lock = NSLock()
    private let writer: AVAssetWriter
    private let ambisonicsInput: AVAssetWriterInput
    private let stereoInput: AVAssetWriterInput
    private let metadataInput: AVAssetWriterInput?
    private let metadata: SpatialAudioMetadataSource?

    private var finished = false
    private var paused = false
    /// Set when a pause ends; the next buffer closes the gap.
    private var resumePending = false
    /// Total paused time removed from the timeline so far.
    private var offset = CMTime.zero
    /// Source end time of the newest buffer written on either track.
    private var latestSourceEnd = CMTime.invalid
    private var lastWrittenEnd: [Track: CMTime] = [:]
    private var framesWritten: [Track: Int64] = [:]
    private var droppedBuffers = 0
    private var analyzeFailures = 0
    /// True when the container refused the metadata track.
    public private(set) var metadataUnavailable = false

    /// - Parameters:
    ///   - ambisonicsSettings: from `SpatialAudioRecordingFormat.ambisonicsSettings`.
    ///   - metadata: nil writes no metadata track (only in tests; players then
    ///     may not treat the file as spatial).
    public init(
        url: URL,
        quality: RecordingQuality,
        ambisonicsSettings: [String: Any],
        stereoSettings: [String: Any]? = nil,
        metadata: SpatialAudioMetadataSource?,
        startTime: CMTime
    ) throws {
        self.url = url
        self.quality = quality
        self.startTime = startTime
        self.metadata = metadata
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: SpatialAudioRecordingFormat.fileType)

        ambisonicsInput = AVAssetWriterInput(mediaType: .audio, outputSettings: ambisonicsSettings)
        let stereoSettings = stereoSettings ?? SpatialAudioRecordingFormat.compatibilitySettings(quality: quality)
        stereoInput = AVAssetWriterInput(mediaType: .audio, outputSettings: stereoSettings)
        for input in [ambisonicsInput, stereoInput] {
            input.expectsMediaDataInRealTime = true
        }
        // Stereo first: AudioFile-based readers take the first audio track.
        guard writer.canAdd(stereoInput) else { throw WriterError.cannotAddInput("stereo") }
        writer.add(stereoInput)
        guard writer.canAdd(ambisonicsInput) else { throw WriterError.cannotAddInput("ambisonics") }
        writer.add(ambisonicsInput)
        // One alternate group with FOA as its default: spatial-aware players
        // pick it, others fall back to the stereo track (written disabled).
        let group = AVAssetWriterInputGroup(inputs: [ambisonicsInput, stereoInput], defaultInput: ambisonicsInput)
        if writer.canAdd(group) { writer.add(group) }

        if let metadata {
            let input = AVAssetWriterInput(
                mediaType: .metadata,
                outputSettings: nil,
                sourceFormatHint: metadata.formatDescription
            )
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                // The metadata describes the FOA track.
                let referent = AVAssetTrack.AssociationType.metadataReferent.rawValue
                if input.canAddTrackAssociation(withTrackOf: ambisonicsInput, type: referent) {
                    input.addTrackAssociation(withTrackOf: ambisonicsInput, type: referent)
                }
                metadataInput = input
            } else {
                // Keep the take: FOA + stereo without the metadata sample.
                metadataInput = nil
                metadataUnavailable = true
            }
        } else {
            metadataInput = nil
        }

        guard writer.startWriting() else {
            throw WriterError.cannotStart(writer.error)
        }
        writer.startSession(atSourceTime: startTime)
    }

    /// Recorded length so far (stereo track), excluding pauses.
    public var duration: TimeInterval {
        lock.withLock { Double(framesWritten[.stereo] ?? 0) / SpatialAudioRecordingFormat.sampleRate }
    }

    /// Buffers dropped because the encoder was busy or timing went backwards.
    public var droppedBufferCount: Int { lock.withLock { droppedBuffers } }

    public func setPaused(_ paused: Bool) {
        lock.withLock {
            guard self.paused != paused else { return }
            self.paused = paused
            if !paused { resumePending = true }
        }
    }

    /// Appends one capture buffer. `waitIfBusy` lets the pre-roll burst wait
    /// briefly for the encoder; live buffers use 0 and are dropped instead.
    @discardableResult
    public func append(_ sampleBuffer: CMSampleBuffer, to track: Track, waitIfBusy: TimeInterval = 0) -> Bool {
        lock.withLock {
            guard !finished, !paused, writer.status == .writing else { return false }
            let sourceStart = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let sourceEnd = SpatialAudioSampleBuffers.endTime(of: sampleBuffer)
            // Before the take (pre-roll older than the journal's seed).
            guard sourceEnd > startTime else { return false }
            if resumePending {
                resumePending = false
                if latestSourceEnd.isValid, sourceStart > latestSourceEnd {
                    offset = CMTimeAdd(offset, CMTimeSubtract(sourceStart, latestSourceEnd))
                }
            }
            let buffer: CMSampleBuffer
            if offset == .zero {
                buffer = sampleBuffer
            } else {
                guard let shifted = SpatialAudioSampleBuffers.retimed(
                    sampleBuffer, to: CMTimeSubtract(sourceStart, offset)
                ) else { droppedBuffers += 1; return false }
                buffer = shifted
            }
            let start = CMSampleBufferGetPresentationTimeStamp(buffer)
            // A track's timeline must not go backwards (possible for the
            // first buffer of the other track after a pause).
            if let last = lastWrittenEnd[track], start < CMTimeSubtract(last, CMTime(value: 1, timescale: 1_000)) {
                droppedBuffers += 1
                return false
            }
            let input = track == .ambisonics ? ambisonicsInput : stereoInput
            if !input.isReadyForMoreMediaData, waitIfBusy > 0 {
                let deadline = Date().addingTimeInterval(waitIfBusy)
                while !input.isReadyForMoreMediaData, Date() < deadline { usleep(2_000) }
            }
            guard input.isReadyForMoreMediaData, input.append(buffer) else {
                droppedBuffers += 1
                return false
            }
            if track == .ambisonics, let metadata, metadata.analyze(buffer) != noErr {
                analyzeFailures += 1
            }
            lastWrittenEnd[track] = SpatialAudioSampleBuffers.endTime(of: buffer)
            framesWritten[track, default: 0] += Int64(CMSampleBufferGetNumSamples(buffer))
            if !latestSourceEnd.isValid || sourceEnd > latestSourceEnd { latestSourceEnd = sourceEnd }
            return true
        }
    }

    public struct Summary: Equatable, Sendable {
        public var ambisonicsFrames: Int64
        public var stereoFrames: Int64
        public var droppedBuffers: Int
        public var analyzeFailures: Int
        public var wroteMetadata: Bool
    }

    /// Finishes the file. Returns its URL, or nil (and removes the file) when
    /// nothing was written or the writer failed; the caller then keeps the
    /// 16 kHz journal as the recording.
    public func finish(timeout: TimeInterval = 10) -> (url: URL?, summary: Summary) {
        let (wroteMetadata, summary) = lock.withLock { () -> (Bool, Summary) in
            finished = true
            ambisonicsInput.markAsFinished()
            stereoInput.markAsFinished()
            var wroteMetadata = false
            if let metadataInput {
                if let sample = metadata?.makeMetadataSample() {
                    let deadline = Date().addingTimeInterval(1)
                    while !metadataInput.isReadyForMoreMediaData, Date() < deadline { usleep(2_000) }
                    wroteMetadata = metadataInput.isReadyForMoreMediaData && metadataInput.append(sample)
                }
                metadataInput.markAsFinished()
            }
            return (wroteMetadata, Summary(
                ambisonicsFrames: framesWritten[.ambisonics] ?? 0,
                stereoFrames: framesWritten[.stereo] ?? 0,
                droppedBuffers: droppedBuffers,
                analyzeFailures: analyzeFailures,
                wroteMetadata: false
            ))
        }
        var result = summary
        result.wroteMetadata = wroteMetadata
        guard summary.ambisonicsFrames > 0, summary.stereoFrames > 0, writer.status == .writing else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return (nil, result)
        }
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        guard done.wait(timeout: .now() + timeout) == .success, writer.status == .completed else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return (nil, result)
        }
        return (url, result)
    }

    /// Stops writing and deletes the partial file.
    public func discard() {
        lock.withLock {
            finished = true
            if writer.status == .writing { writer.cancelWriting() }
        }
        try? FileManager.default.removeItem(at: url)
    }

    public var error: Error? { writer.error }
}

/// 16 kHz mono transcription copy of a spatial kept recording, read from its
/// stereo compatibility track and averaged (left + right) / 2, the same mix
/// the live transcription stream and stereo kept files use. Reads the track
/// explicitly (AVAssetReader) instead of relying on AudioFile's choice of
/// the first track.
enum SpatialAudioTranscriptionCopy {
    enum CopyError: Error {
        case noStereoTrack
        case readFailed(Error?)
    }

    /// True when the file has a four-channel APAC audio track.
    static func hasAmbisonicsTrack(_ url: URL) -> Bool {
        AVURLAsset(url: url).tracks(withMediaType: .audio).contains { track in
            (track.formatDescriptions as? [CMFormatDescription])?.contains { description in
                guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else {
                    return false
                }
                return asbd.mFormatID == kAudioFormatAPAC
                    && Int(asbd.mChannelsPerFrame) == SpatialAudioRecordingFormat.ambisonicsChannelCount
            } ?? false
        }
    }

    /// The stereo (non-APAC) audio track of a spatial file.
    static func compatibilityTrack(of asset: AVAsset) -> AVAssetTrack? {
        asset.tracks(withMediaType: .audio).first { track in
            (track.formatDescriptions as? [CMFormatDescription])?.contains { description in
                CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee.mFormatID != kAudioFormatAPAC
            } ?? false
        }
    }

    static func make(from sourceURL: URL, at outputURL: URL) throws -> URL {
        try Task.checkCancellation()
        let asset = AVURLAsset(url: sourceURL)
        guard let track = compatibilityTrack(of: asset) else { throw CopyError.noStereoTrack }
        let reader = try AVAssetReader(asset: asset)
        let readRate = SpatialAudioRecordingFormat.sampleRate
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: readRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        guard reader.canAdd(output) else { throw CopyError.readFailed(nil) }
        reader.add(output)
        guard reader.startReading() else { throw CopyError.readFailed(reader.error) }
        defer { if reader.status == .reading { reader.cancelReading() } }

        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: readRate, channels: 1, interleaved: false
        ), let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: AudioFileConverter.whisperSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: monoFormat, to: targetFormat) else {
            throw CopyError.readFailed(nil)
        }
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: outputURL)
        let file = try AVAudioFile(
            forWriting: outputURL,
            settings: targetFormat.settings,
            commonFormat: targetFormat.commonFormat,
            interleaved: targetFormat.isInterleaved
        )
        var wrote = false

        func convert(_ mono: AVAudioPCMBuffer?) throws {
            let inputFrames = Double(mono?.frameLength ?? 0)
            let capacity = AVAudioFrameCount((inputFrames * targetFormat.sampleRate / readRate).rounded(.up)) + 1_024
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: converted, error: &error) { _, status in
                guard let mono, !supplied else {
                    status.pointee = mono == nil ? .endOfStream : .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return mono
            }
            if let error { throw error }
            if converted.frameLength > 0 {
                try file.write(from: converted)
                wrote = true
            }
        }

        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let frames = CMSampleBufferGetNumSamples(sample)
            guard frames > 0, let block = CMSampleBufferGetDataBuffer(sample),
                  let mono = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: AVAudioFrameCount(frames)),
                  let destination = mono.floatChannelData?[0] else { continue }
            var interleaved = [Float](repeating: 0, count: frames * 2)
            let status = interleaved.withUnsafeMutableBytes { raw in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: raw.count, destination: raw.baseAddress!)
            }
            guard status == noErr else { throw CopyError.readFailed(nil) }
            for frame in 0..<frames {
                destination[frame] = (interleaved[frame * 2] + interleaved[frame * 2 + 1]) * 0.5
            }
            mono.frameLength = AVAudioFrameCount(frames)
            try convert(mono)
        }
        guard reader.status == .completed else { throw CopyError.readFailed(reader.error) }
        try convert(nil)
        guard wrote else { throw AudioFileConverter.ConversionError.noAudioSamples }
        return outputURL
    }
}
#endif
