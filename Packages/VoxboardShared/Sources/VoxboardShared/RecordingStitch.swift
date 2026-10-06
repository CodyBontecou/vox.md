import Foundation

/// Provenance for a derived recording. Sources remain independent queue jobs;
/// this metadata never replaces their audio, transcript, or delivery state.
public struct RecordingStitch: Codable, Equatable, Sendable {
    public struct Clip: Codable, Equatable, Sendable {
        public var recordingID: UUID
        public var createdAt: Date
        public var duration: TimeInterval

        public init(recordingID: UUID, createdAt: Date, duration: TimeInterval) {
            self.recordingID = recordingID
            self.createdAt = createdAt
            self.duration = duration
        }
    }

    public var clips: [Clip]

    public init(clips: [Clip]) { self.clips = clips }
    public var recordingIDs: [UUID] { clips.map(\.recordingID) }
}

public enum RecordingStitchError: LocalizedError, Equatable, Sendable {
    case selectAtLeastTwo
    case duplicateSelection
    case unavailableClip
    case alreadyStitched
    case originalInUse
    case invalidAudio
    case choosePreset

    public var errorDescription: String? {
        switch self {
        case .selectAtLeastTwo: "Select at least two recordings to stitch."
        case .duplicateSelection: "A recording can only appear once in a stitch."
        case .unavailableClip: "A selected recording is unavailable or busy. Refresh and select saved, idle clips."
        case .alreadyStitched: "Undo the existing stitch before using its original clips in another stitch."
        case .originalInUse: "Undo Stitch before deleting an original clip."
        case .invalidAudio: "A selected clip could not be read as audio. The original recordings were not changed."
        case .choosePreset: "Choose a preset before processing the stitched recording."
        }
    }
}

public struct RecordingStitchSuggestion: Identifiable, Equatable, Sendable {
    public let recordings: [RecordingJob]
    public var id: UUID { recordings[0].id }
    public var recordingIDs: [UUID] { recordings.map(\.id) }
}

public enum RecordingStitchSuggestions {
    /// Time proximity is a review hint, never permission to join recordings.
    public static func groups(
        in recordings: [RecordingJob], maximumGap: TimeInterval = 120
    ) -> [RecordingStitchSuggestion] {
        guard maximumGap.isFinite, maximumGap >= 0 else { return [] }
        let ordered = recordings.filter(\.canBeStitched).sorted {
            $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt
        }
        var groups: [[RecordingJob]] = []
        for recording in ordered {
            if let previous = groups.last?.last {
                // Dates usually reflect handoff, not exact audio start/end.
                // Estimate the next clip's start, rejecting substantial overlap
                // (often duplicate recovery journals). This remains a hint.
                let gap = recording.createdAt.timeIntervalSince(previous.createdAt) - max(0, recording.duration)
                if gap >= -2, gap <= maximumGap, compatible(previous, recording) {
                    groups[groups.count - 1].append(recording)
                    continue
                }
            }
            groups.append([recording])
        }
        return groups.filter { $0.count >= 2 }.map { RecordingStitchSuggestion(recordings: $0) }
    }

    private static func compatible(_ lhs: RecordingJob, _ rhs: RecordingJob) -> Bool {
        guard lhs.source == rhs.source, lhs.language == rhs.language else { return false }
        if let a = sessionID(lhs.requestID), let b = sessionID(rhs.requestID), a != b { return false }
        switch (lhs.delivery, rhs.delivery) {
        case (.preset(let a), .preset(let b)): return a.id == b.id
        case (.recovery, .recovery), (.clipboard, .clipboard): return true
        case (.captureDraft, .captureDraft): return lhs.draftRequestID == rhs.draftRequestID
        case (.keyboard(let a), .keyboard(let b)): return a == b
        default: return false
        }
    }

    private static func sessionID(_ requestID: String?) -> String? {
        guard let requestID, requestID.hasPrefix("inapp-") else { return nil }
        if let suffix = requestID.range(of: "-c", options: .backwards),
           Int(requestID[suffix.upperBound...]) != nil {
            return String(requestID[..<suffix.lowerBound])
        }
        return requestID
    }
}

extension RecordingJob {
    public var canBeStitched: Bool {
        guard stitch == nil, audioDeletedAt == nil, resolvedArtifacts.count == 1 else { return false }
        switch phase {
        case .failed, .completed: return true
        case .queued: return processingPolicy == .manual
        default: return false
        }
    }
}
