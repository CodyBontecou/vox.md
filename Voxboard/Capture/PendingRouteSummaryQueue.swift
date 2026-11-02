import Foundation
import VoxboardShared

/// A Route summary step that could not run when its raw transcript was
/// delivered (Signal "Capture states C · Offline processing"). The summary is
/// added under the delivered note later, once on-device processing is
/// available again: on app foreground, or from "Retry summary".
struct PendingRouteSummaryJob: Codable, Equatable, Identifiable {
    var id: UUID { transcriptID }
    let transcriptID: UUID
    let flowID: String
    /// The note the raw transcript was delivered to, when known.
    var notePath: String?
    let createdAt: Date
    var attempts: Int = 0
    var lastAttemptAt: Date?
}

/// App-local queue of pending summary jobs (standard defaults; the jobs refer
/// to app-only transcript storage).
enum PendingRouteSummaryQueue {
    static let defaultsKey = "capture.routeSummary.pending.v1"
    static let maximumJobs = 20
    /// Jobs older than this are dropped; the raw transcript stays delivered.
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    static func load(defaults: UserDefaults = .standard, now: Date = Date()) -> [PendingRouteSummaryJob] {
        guard let data = defaults.data(forKey: defaultsKey),
              let jobs = try? JSONDecoder().decode([PendingRouteSummaryJob].self, from: data) else { return [] }
        return jobs.filter { now.timeIntervalSince($0.createdAt) < maximumAge }
    }

    static func save(_ jobs: [PendingRouteSummaryJob], defaults: UserDefaults = .standard) {
        let capped = Array(jobs.suffix(maximumJobs))
        if capped.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else if let data = try? JSONEncoder().encode(capped) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    static func enqueue(_ job: PendingRouteSummaryJob, defaults: UserDefaults = .standard) {
        var jobs = load(defaults: defaults)
        jobs.removeAll { $0.transcriptID == job.transcriptID }
        jobs.append(job)
        save(jobs, defaults: defaults)
    }

    static func remove(transcriptID: UUID, defaults: UserDefaults = .standard) {
        var jobs = load(defaults: defaults)
        jobs.removeAll { $0.transcriptID == transcriptID }
        save(jobs, defaults: defaults)
    }

    static func update(_ job: PendingRouteSummaryJob, defaults: UserDefaults = .standard) {
        var jobs = load(defaults: defaults)
        guard let index = jobs.firstIndex(where: { $0.transcriptID == job.transcriptID }) else { return }
        jobs[index] = job
        save(jobs, defaults: defaults)
    }
}

/// Inserts a late summary under the delivered raw transcript.
enum DeliveredNoteSummaryWriter {
    /// Markdown block added beneath the transcript.
    static func block(title: String, summary: String) -> String {
        let body = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return "**\(title)**\n\n\(body)"
    }

    /// Places `block` right after the last occurrence of `rawText`, or at the
    /// end of the document when the transcript can't be found. Idempotent: a
    /// document that already contains the block is returned unchanged.
    static func inserting(_ block: String, after rawText: String, in document: String) -> String {
        guard !document.contains(block) else { return document }
        let anchor = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !anchor.isEmpty, let range = document.range(of: anchor, options: .backwards) {
            var result = document
            result.insert(contentsOf: "\n\n" + block, at: range.upperBound)
            return result
        }
        let trimmed = document.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
        return trimmed + "\n\n" + block + "\n"
    }

    /// Writes the summary into the note at `noteURL`, inside the Route's
    /// security-scoped export folder when one is configured.
    static func write(
        block: String,
        after rawText: String,
        noteURL: URL,
        scopeURL: URL?
    ) throws {
        let scoped = scopeURL?.startAccessingSecurityScopedResource() == true
        let noteScoped = noteURL.startAccessingSecurityScopedResource()
        defer {
            if scoped { scopeURL?.stopAccessingSecurityScopedResource() }
            if noteScoped { noteURL.stopAccessingSecurityScopedResource() }
        }
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: noteURL, options: .forMerging, error: &coordinationError) { url in
            do {
                let document = try String(contentsOf: url, encoding: .utf8)
                let updated = inserting(block, after: rawText, in: document)
                guard updated != document else { return }
                try updated.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
    }
}
