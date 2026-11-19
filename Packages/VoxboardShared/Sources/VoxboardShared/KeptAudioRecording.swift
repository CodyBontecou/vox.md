#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// Resamples Float32 microphone samples to the kept recording's rate.
/// Samples are interleaved when `channelCount` is above 1 (L R L R …).
/// Holds one `AVAudioConverter` so sample-rate conversion stays continuous
/// across chunks; rebuilds it when the input rate changes (route change or
/// engine restart).
///
/// Not thread-safe: `KeptAudioFileWriter` drives it from its serial write
/// queue, never from the audio tap.
public final class KeptAudioResampler: @unchecked Sendable {
    public let outputFormat: AVAudioFormat
    public let channelCount: Int

    private var converter: AVAudioConverter?
    private var converterInputRate: Double?

    public init?(sampleRate: Double, channelCount: Int = 1) {
        guard channelCount >= 1, let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else { return nil }
        outputFormat = format
        self.channelCount = channelCount
    }

    /// Converts samples recorded at `sampleRate`, interleaved for stereo.
    public func convert(samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        if sampleRate == outputFormat.sampleRate { return samples }
        let frames = samples.count / channelCount
        guard frames > 0, let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ), let input = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(frames)
        ) else { return [] }
        guard KeptAudioPCM.deinterleave(samples, frames: frames, into: input) else { return [] }

        if converterInputRate != sampleRate {
            converter = AVAudioConverter(from: inputFormat, to: outputFormat)
            converterInputRate = sampleRate
        }
        return run(input: input, endOfStream: false)
    }

    /// Drains the samples the converter holds back for filtering.
    public func flush() -> [Float] {
        guard converter != nil else { return [] }
        defer {
            converter = nil
            converterInputRate = nil
        }
        return run(input: nil, endOfStream: true)
    }

    private func run(input: AVAudioPCMBuffer?, endOfStream: Bool) -> [Float] {
        guard let converter else { return [] }
        let inputFrames = Double(input?.frameLength ?? 0)
        let ratio = outputFormat.sampleRate / (converterInputRate ?? outputFormat.sampleRate)
        let capacity = AVAudioFrameCount((inputFrames * ratio).rounded(.up)) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return []
        }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied || input == nil {
                status.pointee = endOfStream ? .endOfStream : .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard error == nil, output.frameLength > 0 else { return [] }
        return KeptAudioPCM.interleave(output)
    }
}

/// Interleaved ↔ non-interleaved Float32 helpers for kept audio.
enum KeptAudioPCM {
    /// Copies `frames` interleaved frames from `samples` (starting at frame
    /// `offset`) into the non-interleaved `buffer`.
    static func deinterleave(
        _ samples: [Float],
        frames: Int,
        offset: Int = 0,
        into buffer: AVAudioPCMBuffer
    ) -> Bool {
        let channels = Int(buffer.format.channelCount)
        guard let data = buffer.floatChannelData,
              Int(buffer.frameCapacity) >= frames,
              samples.count >= (offset + frames) * channels else { return false }
        samples.withUnsafeBufferPointer { source in
            guard let base = source.baseAddress else { return }
            if channels == 1 {
                data[0].update(from: base + offset, count: frames)
            } else {
                for channel in 0..<channels {
                    let destination = data[channel]
                    var index = offset * channels + channel
                    for frame in 0..<frames {
                        destination[frame] = base[index]
                        index += channels
                    }
                }
            }
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        return true
    }

    /// Interleaved samples of a non-interleaved Float32 buffer.
    static func interleave(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let data = buffer.floatChannelData else { return [] }
        let frames = Int(buffer.frameLength)
        let channels = Int(buffer.format.channelCount)
        if channels == 1 { return Array(UnsafeBufferPointer(start: data[0], count: frames)) }
        var result = [Float](repeating: 0, count: frames * channels)
        for channel in 0..<channels {
            let source = data[channel]
            var index = channel
            for frame in 0..<frames {
                result[index] = source[frame]
                index += channels
            }
        }
        return result
    }
}

/// Encodes a kept recording (AAC or ALAC in `.m4a`) at the chosen
/// `RecordingQuality`, mono or stereo. Callers append raw microphone samples
/// (interleaved for stereo) from one serial queue; resampling to 48 kHz
/// happens there, never on the audio tap.
public final class KeptAudioFileWriter: @unchecked Sendable {
    public let url: URL
    public let quality: RecordingQuality
    /// Channels in the file and in every appended sample array.
    public let channelCount: Int

    private let lock = NSLock()
    private var file: AVAudioFile?
    private let processingFormat: AVAudioFormat
    private let resampler: KeptAudioResampler?
    private var framesWritten: AVAudioFramePosition = 0

    public init(url: URL, quality: RecordingQuality, channelCount: Int = 1) throws {
        self.url = url
        self.quality = quality
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(
            forWriting: url,
            settings: quality.recorderSettings(channelCount: channelCount),
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.file = file
        processingFormat = file.processingFormat
        self.channelCount = Int(file.processingFormat.channelCount)
        resampler = KeptAudioResampler(
            sampleRate: file.processingFormat.sampleRate,
            channelCount: Int(file.processingFormat.channelCount)
        )
    }

    public var sampleRate: Double { processingFormat.sampleRate }

    public var duration: TimeInterval {
        lock.withLock { Double(framesWritten) / processingFormat.sampleRate }
    }

    /// Appends samples captured at `sourceSampleRate` (interleaved for
    /// stereo), resampling them to the kept rate.
    public func append(samples: [Float], sourceSampleRate: Double) throws {
        guard !samples.isEmpty else { return }
        try lock.withLock {
            guard let resampler else { throw CocoaError(.fileWriteUnknown) }
            try writeUnlocked(resampler.convert(samples: samples, sampleRate: sourceSampleRate))
        }
    }

    /// Appends samples already at the kept sample rate.
    public func append(samples: [Float]) throws {
        try lock.withLock { try writeUnlocked(samples) }
    }

    private func writeUnlocked(_ samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        guard let file else { throw CocoaError(.fileWriteUnknown) }
        let totalFrames = samples.count / channelCount
        var offset = 0
        // Bound the PCM buffer so a long pre-roll seed does not allocate
        // one huge buffer.
        let chunk = 16_384
        while offset < totalFrames {
            let count = min(chunk, totalFrames - offset)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: AVAudioFrameCount(count)
            ), KeptAudioPCM.deinterleave(samples, frames: count, offset: offset, into: buffer) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try file.write(from: buffer)
            framesWritten += AVAudioFramePosition(count)
            offset += count
        }
    }

    /// Closes the encoder so the `.m4a` is complete on disk. Returns nil when
    /// nothing was written; the empty file is removed.
    @discardableResult
    public func finalize() -> URL? {
        let wrote = lock.withLock { () -> Bool in
            if let tail = resampler?.flush() { try? writeUnlocked(tail) }
            file = nil
            return framesWritten > 0
        }
        guard wrote else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return url
    }

    /// Stops writing and deletes the partial file.
    public func discard() {
        lock.withLock { file = nil }
        try? FileManager.default.removeItem(at: url)
    }

    /// Pre-roll for a kept recording, aligned to the 16 kHz journal's seed.
    ///
    /// Both histories are appended under one lock from the same tap buffers,
    /// so their tails end at the same instant. Returns exactly the raw-rate
    /// equivalent of `journalSeedCount` samples. When the history is shorter
    /// it is padded with leading silence so the kept file and the transcript
    /// stay on the same timeline.
    ///
    /// A stereo history holds interleaved frames (`channelCount` samples per
    /// frame); the seed is whole frames, interleaved the same way.
    public static func preRollSeed(
        from history: CircularAudioBuffer,
        historySampleRate: Double,
        journalSeedCount: Int,
        journalSampleRate: Double = AudioFileConverter.whisperSampleRate,
        channelCount: Int = 1
    ) -> [Float] {
        guard journalSeedCount > 0, historySampleRate > 0, journalSampleRate > 0,
              channelCount >= 1 else { return [] }
        let wantedFrames = Int((Double(journalSeedCount) * historySampleRate / journalSampleRate).rounded())
        guard wantedFrames > 0 else { return [] }
        let wanted = wantedFrames * channelCount
        let end = history.totalSamplesWritten
        let channels = Int64(channelCount)
        // Round the oldest index up to a frame boundary so channels never swap.
        let earliest = (history.earliestAvailableIndex + channels - 1) / channels * channels
        let start = max(end - Int64(wanted), earliest, 0)
        let available = end > start ? (history.extract(from: start, to: end) ?? []) : []
        guard available.count < wanted else { return available }
        return [Float](repeating: 0, count: wanted - available.count) + available
    }
}

/// Files of kept (High/Lossless) recordings in the app's recordings folder.
///
/// They never use a prefix that orphan recovery scans (`segment_`,
/// `recording_`, …). Only a handoff intent can claim one, so a crash can't
/// turn one take into two recovered jobs: without an intent the 16 kHz
/// journal/WAV is the single recovery copy and the kept file is removed.
public enum KeptAudioArtifacts {
    public static let filenamePrefix = "kept_"

    public static func makeURL(in directory: URL, requestID: String, quality: RecordingQuality) -> URL {
        let safeRequestID = requestID
            .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            .prefix(80)
        return directory
            .appendingPathComponent("\(filenamePrefix)\(safeRequestID)_\(UUID().uuidString.lowercased())")
            .appendingPathExtension(quality.fileExtension)
    }

    /// Removes kept files no handoff intent claims. Call only when no
    /// recording is in progress in this process (at recorder start-up).
    @discardableResult
    public static func removeUnclaimed(in recordingsDirectoryURL: URL) -> [URL] {
        let claimed = RecordingJobHandoffIntentStore(recordingsDirectoryURL: recordingsDirectoryURL)
            .claimedAudioFilenames()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: recordingsDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        var removed: [URL] = []
        for url in contents
            where url.lastPathComponent.hasPrefix(filenamePrefix)
                && !claimed.contains(url.lastPathComponent) {
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed.append(url)
            }
        }
        return removed
    }
}

/// Facts about a kept recording, used to decide whether it needs a 16 kHz
/// copy for transcription and whether export can keep its encoding.
public enum KeptAudioInspector {
    public struct Format: Equatable, Sendable {
        public let formatID: AudioFormatID
        public let sampleRate: Double
        public let channelCount: AVAudioChannelCount
    }

    public static func format(of url: URL) -> Format? {
        guard AudioFileConverter.hasAudioContainerHeader(url),
              let file = try? AVAudioFile(forReading: url) else { return nil }
        let description = file.fileFormat.streamDescription.pointee
        return Format(
            formatID: description.mFormatID,
            sampleRate: file.fileFormat.sampleRate,
            channelCount: file.fileFormat.channelCount
        )
    }

    /// True for a recording above the 16 kHz the transcription engines use.
    /// Those need a downsampled temporary copy before transcription.
    public static func needsTranscriptionCopy(_ url: URL) -> Bool {
        guard let format = format(of: url) else { return false }
        return format.sampleRate > AudioFileConverter.whisperSampleRate
    }

    /// True when re-encoding with the AAC export preset would lose quality:
    /// an Apple Lossless file, or a High-quality (48 kHz) AAC recording.
    /// 16 kHz Speech recordings keep the existing export path.
    public static func shouldPreserveEncoding(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "m4a",
              let format = format(of: url) else { return false }
        if format.formatID == kAudioFormatAppleLossless { return true }
        return format.formatID == kAudioFormatMPEG4AAC
            && format.sampleRate > AudioFileConverter.whisperSampleRate
    }

    /// Writes the 16 kHz mono WAV copy the transcription engine reads. Streams
    /// the source so hour-long 48 kHz recordings do not load into memory.
    /// A stereo kept recording is downmixed (left and right averaged), so the
    /// engine hears both microphones, as it does with a mono take.
    @discardableResult
    public static func makeTranscriptionCopy(of sourceURL: URL, at outputURL: URL) throws -> URL {
        try AudioFileConverter.convertToWhisperWAVStreaming(
            inputURL: sourceURL,
            outputURL: outputURL,
            downmix: true
        )
    }
}
#endif
