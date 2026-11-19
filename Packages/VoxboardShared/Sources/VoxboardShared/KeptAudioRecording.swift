#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// Resamples mono Float32 microphone samples to the kept recording's rate.
/// Holds one `AVAudioConverter` so sample-rate conversion stays continuous
/// across chunks; rebuilds it when the input rate changes (route change or
/// engine restart).
///
/// Not thread-safe: `KeptAudioFileWriter` drives it from its serial write
/// queue, never from the audio tap.
public final class KeptAudioResampler: @unchecked Sendable {
    public let outputFormat: AVAudioFormat

    private var converter: AVAudioConverter?
    private var converterInputRate: Double?

    public init?(sampleRate: Double) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }
        outputFormat = format
    }

    /// Converts mono samples recorded at `sampleRate`.
    public func convert(samples: [Float], sampleRate: Double) -> [Float] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        if sampleRate == outputFormat.sampleRate { return samples }
        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let input = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: AVAudioFrameCount(samples.count)
        ), let channel = input.floatChannelData?[0] else { return [] }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        input.frameLength = AVAudioFrameCount(samples.count)

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
        guard error == nil, let data = output.floatChannelData?[0], output.frameLength > 0 else {
            return []
        }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}

/// Encodes a kept recording (AAC or ALAC in `.m4a`) at the chosen
/// `RecordingQuality`. Callers append raw mono microphone samples from one
/// serial queue; resampling to 48 kHz happens there, never on the audio tap.
public final class KeptAudioFileWriter: @unchecked Sendable {
    public let url: URL
    public let quality: RecordingQuality

    private let lock = NSLock()
    private var file: AVAudioFile?
    private let processingFormat: AVAudioFormat
    private let resampler: KeptAudioResampler?
    private var framesWritten: AVAudioFramePosition = 0

    public init(url: URL, quality: RecordingQuality) throws {
        self.url = url
        self.quality = quality
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: url)
        let file = try AVAudioFile(
            forWriting: url,
            settings: quality.recorderSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.file = file
        processingFormat = file.processingFormat
        resampler = KeptAudioResampler(sampleRate: file.processingFormat.sampleRate)
    }

    public var sampleRate: Double { processingFormat.sampleRate }

    public var duration: TimeInterval {
        lock.withLock { Double(framesWritten) / processingFormat.sampleRate }
    }

    /// Appends mono samples captured at `sourceSampleRate`, resampling them
    /// to the kept rate.
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
        var offset = 0
        // Bound the PCM buffer so a long pre-roll seed does not allocate
        // one huge buffer.
        let chunk = 16_384
        while offset < samples.count {
            let count = min(chunk, samples.count - offset)
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: AVAudioFrameCount(count)
            ), let channel = buffer.floatChannelData?[0] else {
                throw CocoaError(.fileWriteUnknown)
            }
            samples.withUnsafeBufferPointer { source in
                channel.update(from: source.baseAddress! + offset, count: count)
            }
            buffer.frameLength = AVAudioFrameCount(count)
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
    public static func preRollSeed(
        from history: CircularAudioBuffer,
        historySampleRate: Double,
        journalSeedCount: Int,
        journalSampleRate: Double = AudioFileConverter.whisperSampleRate
    ) -> [Float] {
        guard journalSeedCount > 0, historySampleRate > 0, journalSampleRate > 0 else { return [] }
        let wanted = Int((Double(journalSeedCount) * historySampleRate / journalSampleRate).rounded())
        guard wanted > 0 else { return [] }
        let end = history.totalSamplesWritten
        let start = max(end - Int64(wanted), history.earliestAvailableIndex, 0)
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
    @discardableResult
    public static func makeTranscriptionCopy(of sourceURL: URL, at outputURL: URL) throws -> URL {
        try AudioFileConverter.convertToWhisperWAVStreaming(inputURL: sourceURL, outputURL: outputURL)
    }
}
#endif
