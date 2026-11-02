import Foundation

// MARK: - Busy-file detection
//
// Vox.md never overwrites a note that another app is in the middle of
// editing. Before a coordinated write the writer asks
// `CaptureFileBusyDetector` whether the target note is open with unsaved
// changes elsewhere, locked, or read-only, and re-checks the file right before
// the bytes are replaced so a save that lands between read and write is not
// clobbered. A busy note either waits for the next retry (the default) or, when
// the person chose "Write a new note instead", receives its own sibling note.

/// Why a target note could not be written safely right now.
public enum CaptureFileBusyReason: String, Codable, CaseIterable, Sendable {
    /// Another editor holds a lock/swap file for the note (Vim, Emacs,
    /// LibreOffice, Microsoft Office), which means its buffer can differ from
    /// what is on disk.
    case unsavedChanges
    /// Another process holds an exclusive advisory lock, or the file is
    /// marked locked in Finder.
    case locked
    /// The note exists but cannot be written by Vox.md.
    case readOnly
    /// The note changed on disk while Vox.md was preparing its edit.
    case changedDuringWrite

    /// Activity headline, e.g. "Tasks.md is open with unsaved changes in
    /// another app".
    public func headline(fileName: String) -> String {
        switch self {
        case .unsavedChanges:
            return "\(fileName) is open with unsaved changes in another app"
        case .locked:
            return "\(fileName) is locked by another app"
        case .readOnly:
            return "\(fileName) is read-only"
        case .changedDuringWrite:
            return "\(fileName) is being saved by another app"
        }
    }
}

/// What to do when the target note is busy.
public enum CaptureFileBusyPolicy: String, Codable, CaseIterable, Sendable {
    /// Keep the capture queued and retry (the default).
    case waitAndRetry
    /// Write the capture into a new sibling note instead of waiting.
    case writeNewNote

    public static let storageKey = "capture.fileBusy.policy.v1"
}

/// Thrown by `CoordinatedCaptureWriter` instead of overwriting a busy note.
/// The capture stays queued; nothing in the note was changed.
public struct CaptureFileBusyError: Error, Equatable, LocalizedError, Sendable {
    public var requestID: UUID
    public var fileName: String
    public var relativeNotePath: String?
    public var reason: CaptureFileBusyReason

    public init(
        requestID: UUID,
        fileName: String,
        relativeNotePath: String?,
        reason: CaptureFileBusyReason
    ) {
        self.requestID = requestID
        self.fileName = fileName
        self.relativeNotePath = relativeNotePath
        self.reason = reason
    }

    public var errorDescription: String? {
        reason.headline(fileName: fileName)
            + ". Vox.md waits rather than overwrite. It retries automatically every minute."
    }
}

/// A capture that is waiting for its busy note.
public struct CaptureFileBusyEntry: Codable, Equatable, Identifiable, Sendable {
    public var requestID: UUID
    public var fileName: String
    public var relativeNotePath: String?
    public var reason: CaptureFileBusyReason
    /// The Markdown entry Vox.md will write (prefix, entry and suffix), so the
    /// person can copy it while the note is busy.
    public var markdown: String
    public var firstDetectedAt: Date
    public var lastAttemptAt: Date
    public var attemptCount: Int

    public var id: UUID { requestID }

    public init(
        requestID: UUID,
        fileName: String,
        relativeNotePath: String?,
        reason: CaptureFileBusyReason,
        markdown: String,
        firstDetectedAt: Date = Date(),
        lastAttemptAt: Date = Date(),
        attemptCount: Int = 1
    ) {
        self.requestID = requestID
        self.fileName = fileName
        self.relativeNotePath = relativeNotePath
        self.reason = reason
        self.markdown = markdown
        self.firstDetectedAt = firstDetectedAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
    }

    /// When the next automatic retry is due.
    public var nextRetryAt: Date {
        lastAttemptAt.addingTimeInterval(CaptureFileBusyMonitor.retryInterval)
    }
}

/// Stateless checks for a note another app is using.
public enum CaptureFileBusyDetector {
    /// Snapshot used to detect a save landing between read and write.
    public struct FileSnapshot: Equatable, Sendable {
        public var modificationDate: Date?
        public var size: Int?
        public var inode: Int?
    }

    /// Returns why `fileURL` is unsafe to write now, or nil when it is free.
    /// A missing file is never busy.
    public static func busyReason(
        for fileURL: URL,
        fileManager: FileManager = .default
    ) -> CaptureFileBusyReason? {
        let path = fileURL.path
        guard fileManager.fileExists(atPath: path) else { return nil }

        if hasEditorSidecar(for: fileURL, fileManager: fileManager) {
            return .unsavedChanges
        }
        let values = try? fileURL.resourceValues(forKeys: [.isUserImmutableKey, .isWritableKey])
        if values?.isUserImmutable == true {
            return .locked
        }
        if values?.isWritable == false || !fileManager.isWritableFile(atPath: path) {
            return .readOnly
        }
        if hasExclusiveAdvisoryLock(at: path) {
            return .locked
        }
        return nil
    }

    /// Editor lock or swap files that mark an open, possibly modified buffer.
    public static func sidecarNames(for fileName: String) -> [String] {
        [
            ".#\(fileName)",              // Emacs: buffer modified, not saved
            ".\(fileName).swp",           // Vim swap file
            ".\(fileName).swo",
            "~$\(fileName)",              // Microsoft Office owner file
            ".~lock.\(fileName)#",        // LibreOffice lock file
        ]
    }

    public static func hasEditorSidecar(
        for fileURL: URL,
        fileManager: FileManager = .default
    ) -> Bool {
        let directory = fileURL.deletingLastPathComponent()
        return sidecarNames(for: fileURL.lastPathComponent).contains { name in
            let sidecar = directory.appendingPathComponent(name).path
            // Emacs lock files are dangling symlinks, so check the link itself.
            return (try? fileManager.attributesOfItem(atPath: sidecar)) != nil
                || fileManager.fileExists(atPath: sidecar)
        }
    }

    /// True when another process holds an exclusive `flock` on the file.
    public static func hasExclusiveAdvisoryLock(at path: String) -> Bool {
        let descriptor = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_SH | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK
    }

    public static func snapshot(
        of fileURL: URL,
        fileManager: FileManager = .default
    ) -> FileSnapshot? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path) else {
            return nil
        }
        return FileSnapshot(
            modificationDate: attributes[.modificationDate] as? Date,
            size: (attributes[.size] as? NSNumber)?.intValue,
            inode: (attributes[.systemFileNumber] as? NSNumber)?.intValue
        )
    }

    /// A sibling path for "Write a new note instead", e.g.
    /// `Tasks/Tasks (Vox.md 2026-11-01 1105).md`.
    public static func newNoteRelativePath(
        for relativePath: String,
        at date: Date = Date(),
        exists: (String) -> Bool
    ) -> String {
        let nsPath = relativePath as NSString
        let directory = nsPath.deletingLastPathComponent
        let stem = (nsPath.lastPathComponent as NSString).deletingPathExtension
        let pathExtension = nsPath.pathExtension.isEmpty ? "md" : nsPath.pathExtension
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        let base = "\(stem) (Vox.md \(formatter.string(from: date)))"
        var attempt = 1
        while true {
            let name = attempt == 1 ? base : "\(base) \(attempt)"
            let filename = "\(name).\(pathExtension)"
            let candidate = directory.isEmpty ? filename : directory + "/" + filename
            if !exists(candidate) { return candidate }
            attempt += 1
        }
    }
}

/// Process-wide busy-file state shared by the writer and the app UI.
///
/// Detection is opt-in per process (`isDetectionEnabled`) so command-line
/// tools and tests keep the original writer behavior unless they enable it.
public final class CaptureFileBusyMonitor: @unchecked Sendable {
    public static let shared = CaptureFileBusyMonitor()
    /// Posted on the main queue whenever `entries` changes.
    public static let didChangeNotification = Notification.Name("CaptureFileBusyMonitorDidChange")
    /// Busy captures are retried automatically on this cadence.
    public static let retryInterval: TimeInterval = 60

    private let lock = NSLock()
    private var storedDetectionEnabled = false
    private var storedPolicy: CaptureFileBusyPolicy = .waitAndRetry
    private var storedEntries: [UUID: CaptureFileBusyEntry] = [:]
    private var newNoteRequests: Set<UUID> = []

    public init() {}

    public var isDetectionEnabled: Bool {
        get { lock.withLock { storedDetectionEnabled } }
        set { lock.withLock { storedDetectionEnabled = newValue } }
    }

    public var policy: CaptureFileBusyPolicy {
        get { lock.withLock { storedPolicy } }
        set { lock.withLock { storedPolicy = newValue } }
    }

    /// Busy captures, oldest first.
    public var entries: [CaptureFileBusyEntry] {
        lock.withLock { storedEntries.values.sorted { $0.firstDetectedAt < $1.firstDetectedAt } }
    }

    public func entry(for requestID: UUID) -> CaptureFileBusyEntry? {
        lock.withLock { storedEntries[requestID] }
    }

    public func record(_ entry: CaptureFileBusyEntry) {
        lock.withLock {
            var updated = entry
            if let existing = storedEntries[entry.requestID] {
                updated.firstDetectedAt = existing.firstDetectedAt
                updated.attemptCount = existing.attemptCount + 1
            }
            storedEntries[entry.requestID] = updated
        }
        postChange()
    }

    public func clear(requestID: UUID) {
        let removed = lock.withLock { () -> Bool in
            newNoteRequests.remove(requestID)
            return storedEntries.removeValue(forKey: requestID) != nil
        }
        if removed { postChange() }
    }

    /// Asks the next write of `requestID` to go to a new note even when the
    /// policy is "Wait and retry".
    public func requestNewNote(for requestID: UUID) {
        lock.withLock { _ = newNoteRequests.insert(requestID) }
    }

    func consumeNewNoteRequest(for requestID: UUID) -> Bool {
        lock.withLock { newNoteRequests.remove(requestID) != nil }
    }

    func hasNewNoteRequest(for requestID: UUID) -> Bool {
        lock.withLock { newNoteRequests.contains(requestID) }
    }

    private func postChange() {
        let post = {
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        }
        if Thread.isMainThread { post() } else { DispatchQueue.main.async(execute: post) }
    }
}

extension CaptureDestination {
    /// Sentinel `attachmentsFolderName` meaning "beside the note": the
    /// pipeline resolves it to the delivered note's own folder.
    public static let besideNoteAttachmentsFolder = "{{note-folder}}"
}
