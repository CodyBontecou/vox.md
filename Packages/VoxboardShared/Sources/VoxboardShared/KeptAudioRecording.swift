#if canImport(AVFoundation)
import AVFoundation
import Foundation

/// Converts microphone buffers to the mono Float32 stream a kept recording is
/// written from. Holds one `AVAudioConverter` so sample-rate conversion stays
/// continuous across buffers; rebuilds it when the input format changes
/// (route change or engine restart).
///
/// Not thread-safe: call from the audio tap only.
public final class KeptAudioResampler: @unchecked Sendable {
    public let outputFormat: AVAudioFormat

    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    public init?(sampleRate: Double) {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else { return nil }
        outputFormat = format
    }

    /// Returns an owned copy of `buffer` in `outputFormat`.
    public func convert(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard buffer.frameLength > 0 else { return [] }
        let input = buffer.format
        if input.sampleRate == outputFormat.sampleRate,
           input.channelCount == 1,
           input.commonFormat == .pcmFormatFloat32,
           let data = buffer.floatChannelData?[0] {
            return Array(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
        }

        if converterInputFormat != input {
            converter = AVAudioConverter(from: input, to: outputFormat)
            converterInputFormat = input
        }
        guard let converter else { return [] }
        let ratio = outputFormat.sampleRate / input.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return []
        }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let data = output.floatChannelData?[0], output.frameLength > 0 else {
            return []
        }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}

/// Encodes a kept recording (AAC or ALAC in `.m4a`) at the chosen
/// `RecordingQuality`. Appends are serialized by the caller's write queue.
public final class KeptAudioFileWriter: @unchecked Sendable {
    public let url: URL
    public let quality: RecordingQuality

    private let lock = NSLock()
    private var file: AVAudioFile?
    private let processingFormat: AVAudioFormat
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
    }

    public var sampleRate: Double { processingFormat.sampleRate }

    public var duration: TimeInterval {
        lock.withLock { Double(framesWritten) / processingFormat.sampleRate }
    }

    public func append(samples: [Float]) throws {
        guard !samples.isEmpty else { return }
        try lock.withLock {
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
    }

    /// Closes the encoder so the `.m4a` is complete on disk. Returns nil when
    /// nothing was written; the empty file is removed.
    @discardableResult
    public func finalize() -> URL? {
        let wrote = lock.withLock { () -> Bool in
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
