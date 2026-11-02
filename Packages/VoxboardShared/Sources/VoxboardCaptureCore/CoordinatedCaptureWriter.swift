import Foundation

public protocol CaptureFileCoordinating: Sendable {
    func coordinateWriting<T>(at url: URL, _ accessor: (URL) throws -> T) throws -> T
}

public final class ProcessLocalCaptureFileCoordinator: CaptureFileCoordinating, @unchecked Sendable {
    public static let shared = ProcessLocalCaptureFileCoordinator()

    private let lock = NSRecursiveLock()

    public init() {}

    public func coordinateWriting<T>(at url: URL, _ accessor: (URL) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try accessor(url)
    }
}

/// Coordinates writes with document providers and other app extensions. A
/// process-local lock covers callers in this process while NSFileCoordinator
/// provides the cross-process/document-provider boundary.
public final class NSFileCoordinatorCaptureFileCoordinator: CaptureFileCoordinating, @unchecked Sendable {
    public static let shared = NSFileCoordinatorCaptureFileCoordinator()

    private let processCoordinator: ProcessLocalCaptureFileCoordinator

    public init(processCoordinator: ProcessLocalCaptureFileCoordinator = .shared) {
        self.processCoordinator = processCoordinator
    }

    public func coordinateWriting<T>(at url: URL, _ accessor: (URL) throws -> T) throws -> T {
        try processCoordinator.coordinateWriting(at: url) { lockedURL in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordinationError: NSError?
            var result: Result<T, Error>?
            coordinator.coordinate(
                writingItemAt: lockedURL,
                options: .forMerging,
                error: &coordinationError
            ) { coordinatedURL in
                result = Result { try accessor(coordinatedURL) }
            }
            if let coordinationError { throw coordinationError }
            guard let result else {
                throw CaptureWriteError.coordinatorDidNotRun
            }
            return try result.get()
        }
    }
}

public enum CaptureWriteError: Error, Equatable, LocalizedError, Sendable {
    case coordinatorDidNotRun
    case verificationFailed(UUID)

    public var errorDescription: String? {
        switch self {
        case .coordinatorDidNotRun:
            return "The file coordinator did not perform the capture write."
        case .verificationFailed(let requestID):
            return "The capture write could not be verified for request \(requestID.uuidString)."
        }
    }
}

public struct CaptureWriteReceipt: Equatable, Sendable {
    public var fileURL: URL
    public var requestID: UUID
    public var byteCount: Int
    public var wasAlreadyApplied: Bool

    public init(fileURL: URL, requestID: UUID, byteCount: Int, wasAlreadyApplied: Bool) {
        self.fileURL = fileURL
        self.requestID = requestID
        self.byteCount = byteCount
        self.wasAlreadyApplied = wasAlreadyApplied
    }
}

public enum CaptureRequestMarker: Sendable {
    public static func text(for requestID: UUID) -> String {
        "<!-- vox-capture:\(requestID.uuidString.lowercased()) -->"
    }

    public static func isPresent(in markdown: String, requestID: UUID) -> Bool {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .contains(text(for: requestID))
    }
}

public protocol CaptureMutationWriting: Sendable {
    func write(_ mutation: MarkdownCaptureMutation, to fileURL: URL) async throws -> CaptureWriteReceipt
}

public actor CoordinatedCaptureWriter: CaptureMutationWriting {
    private let coordinator: any CaptureFileCoordinating
    private let editor: MarkdownDocumentEditor
    private let fileManager: FileManager
    private let busyMonitor: CaptureFileBusyMonitor

    public init(
        coordinator: any CaptureFileCoordinating = NSFileCoordinatorCaptureFileCoordinator.shared,
        editor: MarkdownDocumentEditor = MarkdownDocumentEditor(),
        fileManager: FileManager = .default,
        busyMonitor: CaptureFileBusyMonitor = .shared
    ) {
        self.coordinator = coordinator
        self.editor = editor
        self.fileManager = fileManager
        self.busyMonitor = busyMonitor
    }

    public func write(
        _ mutation: MarkdownCaptureMutation,
        to fileURL: URL
    ) async throws -> CaptureWriteReceipt {
        let busyMonitor = busyMonitor
        return try coordinator.coordinateWriting(at: fileURL) { coordinatedURL in
            let marker = CaptureRequestMarker.text(for: mutation.requestID)
            let secureLocation = mutation.destinationRootURL.flatMap { root in
                mutation.relativeNotePath.map { (root: root, relativePath: $0) }
            }
            // Busy-file detection: never overwrite a note another app is
            // editing. Checked before reading and again right before writing.
            let detectsBusyFiles = busyMonitor.isDetectionEnabled
            let busyTargetURL = secureLocation.map {
                $0.root.appendingPathComponent($0.relativePath)
            } ?? coordinatedURL
            var busyReason = detectsBusyFiles
                ? CaptureFileBusyDetector.busyReason(for: busyTargetURL, fileManager: fileManager)
                : nil
            let preReadSnapshot = detectsBusyFiles
                ? CaptureFileBusyDetector.snapshot(of: busyTargetURL, fileManager: fileManager)
                : nil
            let existing: String
            if let secureLocation,
               let data = try SecureCaptureFileIO.read(
                    relativePath: secureLocation.relativePath,
                    rootURL: secureLocation.root
               ) {
                guard let decoded = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }
                existing = decoded
            } else if secureLocation != nil {
                existing = ""
            } else if fileManager.fileExists(atPath: coordinatedURL.path) {
                existing = try String(contentsOf: coordinatedURL, encoding: .utf8)
            } else {
                existing = ""
            }
            let wasAlreadyApplied = CaptureRequestMarker.isPresent(
                in: existing,
                requestID: mutation.requestID
            )
            let edited = try editor.applying(mutation, to: existing)

            if detectsBusyFiles, !wasAlreadyApplied {
                if busyReason == nil, let preReadSnapshot,
                   CaptureFileBusyDetector.snapshot(of: busyTargetURL, fileManager: fileManager) != preReadSnapshot {
                    busyReason = .changedDuringWrite
                }
                let forcedNewNote = busyMonitor.consumeNewNoteRequest(for: mutation.requestID)
                if forcedNewNote || busyReason != nil {
                    if forcedNewNote || busyMonitor.policy == .writeNewNote {
                        let receipt = try Self.writeNewNote(
                            mutation,
                            besideFileAt: coordinatedURL,
                            secureLocation: secureLocation,
                            editor: editor,
                            fileManager: fileManager
                        )
                        busyMonitor.clear(requestID: mutation.requestID)
                        return receipt
                    }
                    let busyError = CaptureFileBusyError(
                        requestID: mutation.requestID,
                        fileName: busyTargetURL.lastPathComponent,
                        relativeNotePath: mutation.relativeNotePath,
                        reason: busyReason ?? .changedDuringWrite
                    )
                    busyMonitor.record(CaptureFileBusyEntry(
                        requestID: mutation.requestID,
                        fileName: busyError.fileName,
                        relativeNotePath: busyError.relativeNotePath,
                        reason: busyError.reason,
                        markdown: (mutation.entryPrefix + mutation.entry + mutation.entrySuffix)
                            .trimmingCharacters(in: .newlines)
                    ))
                    throw busyError
                }
            }

            if !wasAlreadyApplied {
                if let secureLocation {
                    try SecureCaptureFileIO.writeAtomically(
                        Data(edited.utf8),
                        relativePath: secureLocation.relativePath,
                        rootURL: secureLocation.root
                    )
                } else {
                    try fileManager.createDirectory(
                        at: coordinatedURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data(edited.utf8).write(to: coordinatedURL, options: .atomic)
                }
            }

            let verified: String
            if let secureLocation,
               let data = try SecureCaptureFileIO.read(
                    relativePath: secureLocation.relativePath,
                    rootURL: secureLocation.root
               ), let decoded = String(data: data, encoding: .utf8) {
                verified = decoded
            } else {
                verified = try String(contentsOf: coordinatedURL, encoding: .utf8)
            }
            let writeWasVerified: Bool
            if wasAlreadyApplied || mutation.retryProtectionEnabled {
                writeWasVerified = verified.contains(marker)
            } else {
                writeWasVerified = verified == edited
            }
            guard writeWasVerified else {
                throw CaptureWriteError.verificationFailed(mutation.requestID)
            }
            if detectsBusyFiles { busyMonitor.clear(requestID: mutation.requestID) }
            return CaptureWriteReceipt(
                fileURL: coordinatedURL,
                requestID: mutation.requestID,
                byteCount: verified.utf8.count,
                wasAlreadyApplied: wasAlreadyApplied
            )
        }
    }

    /// "Write a new note instead": writes the entry into a new sibling note
    /// so the busy note is left untouched.
    nonisolated private static func writeNewNote(
        _ mutation: MarkdownCaptureMutation,
        besideFileAt coordinatedURL: URL,
        secureLocation: (root: URL, relativePath: String)?,
        editor: MarkdownDocumentEditor,
        fileManager: FileManager
    ) throws -> CaptureWriteReceipt {
        var newNoteMutation = mutation
        newNoteMutation.placement = .append
        let content = try editor.applying(newNoteMutation, to: "")
        let data = Data(content.utf8)
        let writtenURL: URL
        if let secureLocation {
            let relativePath = CaptureFileBusyDetector.newNoteRelativePath(
                for: secureLocation.relativePath
            ) { candidate in
                (try? SecureCaptureFileIO.exists(relativePath: candidate, rootURL: secureLocation.root)) ?? true
            }
            try SecureCaptureFileIO.writeAtomically(
                data,
                relativePath: relativePath,
                rootURL: secureLocation.root
            )
            writtenURL = secureLocation.root.appendingPathComponent(relativePath)
        } else {
            let directory = coordinatedURL.deletingLastPathComponent()
            let relativePath = CaptureFileBusyDetector.newNoteRelativePath(
                for: coordinatedURL.lastPathComponent
            ) { candidate in
                fileManager.fileExists(atPath: directory.appendingPathComponent(candidate).path)
            }
            writtenURL = directory.appendingPathComponent(relativePath)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: writtenURL, options: .atomic)
        }
        return CaptureWriteReceipt(
            fileURL: writtenURL,
            requestID: mutation.requestID,
            byteCount: data.count,
            wasAlreadyApplied: false
        )
    }
}
