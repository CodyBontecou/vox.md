import Foundation

/// A fixed-capacity circular buffer for Float audio samples.
///
/// Thread-safe for concurrent append (writer) and extract (reader).
/// Used by the persistent recorder to maintain a rolling window of audio
/// that the keyboard can request transcription of at any time.
public final class CircularAudioBuffer: @unchecked Sendable {
    private var buffer: [Float]
    private let capacity: Int
    private var writeIndex: Int = 0
    /// Total number of samples written since creation (monotonically increasing).
    private var samplesWritten: Int64 = 0
    private let lock = NSLock()

    public var totalSamplesWritten: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return samplesWritten
    }

    /// - Parameter capacity: Maximum number of Float samples to store.
    ///   At 16 kHz mono, 5 minutes ≈ 4,800,000 samples ≈ 19.2 MB.
    public init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    /// Append samples from an unsafe buffer pointer (zero-copy from audio tap).
    public func append(_ samples: UnsafeBufferPointer<Float>) {
        lock.lock()
        defer { lock.unlock() }

        let count = samples.count
        var remaining = count
        var srcOffset = 0

        while remaining > 0 {
            let spaceToEnd = capacity - writeIndex
            let chunk = min(remaining, spaceToEnd)

            buffer.withUnsafeMutableBufferPointer { dst in
                let dstStart = dst.baseAddress! + writeIndex
                let srcStart = samples.baseAddress! + srcOffset
                dstStart.initialize(from: srcStart, count: chunk)
            }

            writeIndex = (writeIndex + chunk) % capacity
            srcOffset += chunk
            remaining -= chunk
        }

        samplesWritten += Int64(count)
    }

    /// Append samples from an array.
    public func append(_ samples: [Float]) {
        samples.withUnsafeBufferPointer { append($0) }
    }

    /// Extract samples from absolute index range [start, end).
    /// Returns nil if the requested range has been overwritten (too old) or is invalid.
    public func extract(from startAbsolute: Int64, to endAbsolute: Int64) -> [Float]? {
        lock.lock()
        defer { lock.unlock() }

        let earliestAvailable = max(0, samplesWritten - Int64(capacity))
        guard startAbsolute >= earliestAvailable,
              endAbsolute <= samplesWritten,
              endAbsolute > startAbsolute else {
            return nil
        }

        let count = Int(endAbsolute - startAbsolute)
        var result = [Float](repeating: 0, count: count)

        // Map absolute index to buffer position
        let startPos = Int(startAbsolute % Int64(capacity))

        var remaining = count
        var dstOffset = 0
        var srcPos = startPos

        while remaining > 0 {
            let spaceToEnd = capacity - srcPos
            let chunk = min(remaining, spaceToEnd)

            buffer.withUnsafeBufferPointer { src in
                for i in 0..<chunk {
                    result[dstOffset + i] = src[srcPos + i]
                }
            }

            srcPos = (srcPos + chunk) % capacity
            dstOffset += chunk
            remaining -= chunk
        }

        return result
    }

    /// Atomically extracts up to `maxCount` currently available samples from an
    /// absolute cursor, optionally capped at an exact stop boundary.
    public func extractAvailable(
        from startAbsolute: Int64,
        through endLimit: Int64? = nil,
        maxCount: Int
    ) -> (samples: [Float], nextIndex: Int64)? {
        lock.lock()
        defer { lock.unlock() }

        guard maxCount > 0 else { return nil }
        let earliestAvailable = max(0, samplesWritten - Int64(capacity))
        let availableEnd = min(endLimit ?? samplesWritten, samplesWritten)
        guard startAbsolute >= earliestAvailable,
              startAbsolute < availableEnd else {
            return nil
        }

        let endAbsolute = min(availableEnd, startAbsolute + Int64(maxCount))
        let count = Int(endAbsolute - startAbsolute)
        var result = [Float](repeating: 0, count: count)
        var srcPos = Int(startAbsolute % Int64(capacity))
        var remaining = count
        var dstOffset = 0

        while remaining > 0 {
            let chunk = min(remaining, capacity - srcPos)
            buffer.withUnsafeBufferPointer { source in
                result.withUnsafeMutableBufferPointer { destination in
                    guard let sourceBase = source.baseAddress,
                          let destinationBase = destination.baseAddress else { return }
                    destinationBase.advanced(by: dstOffset).update(
                        from: sourceBase.advanced(by: srcPos),
                        count: chunk
                    )
                }
            }
            srcPos = (srcPos + chunk) % capacity
            dstOffset += chunk
            remaining -= chunk
        }

        return (result, endAbsolute)
    }

    /// The earliest absolute sample index still available in the buffer.
    public var earliestAvailableIndex: Int64 {
        lock.lock()
        defer { lock.unlock() }
        return max(0, samplesWritten - Int64(capacity))
    }

    /// Reset the buffer, clearing all data.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        samplesWritten = 0
    }
}

/// Reads a complete recording even after the rolling preview buffer wraps.
/// The journal contains pre-roll and recorded audio only; paused samples have
/// already been excluded by the recorder's journal gate.
public enum RecordingAudioExtraction {
    public static func samples(
        from buffer: CircularAudioBuffer,
        startIndex: Int64,
        endIndex: Int64,
        pausedRanges: [(start: Int64, end: Int64)],
        journalURL: URL? = nil
    ) -> [Float]? {
        guard endIndex > startIndex else { return nil }
        var spans: [(Int64, Int64)] = []
        var cursor = startIndex
        for (pauseStart, pauseEnd) in pausedRanges {
            let stop = min(endIndex, pauseStart)
            if stop > cursor { spans.append((cursor, stop)) }
            cursor = max(cursor, min(endIndex, pauseEnd))
        }
        if cursor < endIndex { spans.append((cursor, endIndex)) }

        var samples: [Float] = []
        for (start, end) in spans {
            guard let chunk = buffer.extract(from: start, to: end) else {
                guard let journalURL else { return nil }
                let count = spans.reduce(Int64(0)) { $0 + $1.1 - $1.0 }
                return try? readJournal(journalURL, sampleCount: Int(count))
            }
            samples.append(contentsOf: chunk)
        }
        return samples
    }

    /// Reads only the requested prefix of our 16-bit mono journal. A live
    /// continuous recording may already have appended beyond the commit cursor.
    private static func readJournal(_ url: URL, sampleCount: Int) throws -> [Float] {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= 44 + UInt64(sampleCount) * 2 else {
            // Never deliver a truncated journal as a successful full recording.
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.seek(toOffset: 0)
        let header = try file.read(upToCount: 44) ?? Data()
        guard header.count == 44,
              String(decoding: header[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: header[8..<12], as: UTF8.self) == "WAVE",
              String(decoding: header[36..<40], as: UTF8.self) == "data",
              header[20] == 1, header[22] == 1, header[34] == 16 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var result: [Float] = []
        result.reserveCapacity(sampleCount)
        while result.count < sampleCount {
            let byteCount = min(32_768, sampleCount - result.count) * 2
            let data = try file.read(upToCount: byteCount) ?? Data()
            guard data.count == byteCount else { throw CocoaError(.fileReadCorruptFile) }
            for offset in stride(from: 0, to: data.count, by: 2) {
                let bits = UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
                result.append(Float(Int16(bitPattern: bits)) / 32_767)
            }
        }
        return result
    }
}
