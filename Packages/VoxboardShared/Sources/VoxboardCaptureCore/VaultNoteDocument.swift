import CryptoKit
import Foundation

/// Identifies one exact byte state of a vault note. Content-addressed rather
/// than modification-date based, because iCloud and other file providers
/// rewrite dates without changing bytes (and sometimes the reverse).
public struct VaultNoteVersion: Codable, Equatable, Hashable, Sendable {
    public var sha256: String

    public init(sha256: String) {
        self.sha256 = sha256
    }

    public init(data: Data) {
        self.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public init(text: String) {
        self.init(data: Data(text.utf8))
    }
}

public struct VaultNoteSnapshot: Equatable, Sendable {
    public var text: String
    public var version: VaultNoteVersion
    public var modifiedAt: Date?

    public init(text: String, version: VaultNoteVersion, modifiedAt: Date? = nil) {
        self.text = text
        self.version = version
        self.modifiedAt = modifiedAt
    }
}

public enum VaultNoteDocumentError: Error, Equatable, LocalizedError, Sendable {
    /// The file no longer matches the version the editor last saw. Carries
    /// what is on disk now (`nil` when the file was deleted or moved).
    case changedOnDisk(current: VaultNoteSnapshot?)
    case notMarkdown(String)
    case tooLarge(String)
    case notText(String)

    public var errorDescription: String? {
        switch self {
        case .changedOnDisk:
            return "This file changed in another app."
        case .notMarkdown(let path):
            return "Only Markdown files can be edited here: \(path)"
        case .tooLarge(let path):
            return "This file is too large to edit in Vox.md: \(path)"
        case .notText(let path):
            return "This file isn't UTF-8 text: \(path)"
        }
    }
}

/// Reads and whole-file replaces one Markdown note inside a vault root.
///
/// Every replace is a compare-and-swap inside a coordinated write: the bytes
/// on disk must still match `expecting`, or nothing is written and
/// `.changedOnDisk` reports what is there now. This is what lets the composer
/// autosave into a file other apps (Obsidian, iA Writer, Files) also edit.
public struct VaultNoteDocument: Sendable {
    /// Notes are human-written Markdown; anything larger is almost certainly
    /// not something to load into a text view on a phone.
    public static let maximumByteCount = 4 * 1024 * 1024

    public let rootURL: URL
    public let relativePath: String
    private let coordinator: any CaptureFileCoordinating

    public init(
        rootURL: URL,
        relativePath: String,
        coordinator: any CaptureFileCoordinating = NSFileCoordinatorCaptureFileCoordinator.shared
    ) throws {
        try CapturePathValidation.validateRelativePath(relativePath)
        guard relativePath.lowercased().hasSuffix(".md") else {
            throw VaultNoteDocumentError.notMarkdown(relativePath)
        }
        self.rootURL = rootURL
        self.relativePath = relativePath
        self.coordinator = coordinator
    }

    public var fileURL: URL {
        rootURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    public var fileName: String {
        (relativePath as NSString).lastPathComponent
    }

    /// The note as it is on disk now, or `nil` when it does not exist.
    public func read() throws -> VaultNoteSnapshot? {
        try coordinator.coordinateWriting(at: fileURL) { _ in
            try unlockedRead()
        }
    }

    /// Writes `text` only if the note still matches `expecting`. Pass `nil`
    /// to require that the note does not exist yet.
    @discardableResult
    public func replace(with text: String, expecting: VaultNoteVersion?) throws -> VaultNoteVersion {
        let data = Data(text.utf8)
        guard data.count <= Self.maximumByteCount else {
            throw VaultNoteDocumentError.tooLarge(relativePath)
        }
        return try coordinator.coordinateWriting(at: fileURL) { _ in
            let current = try unlockedRead()
            guard current?.version == expecting else {
                throw VaultNoteDocumentError.changedOnDisk(current: current)
            }
            let next = VaultNoteVersion(data: data)
            // Nothing to do; avoids bumping the date and waking other apps.
            if current?.version == next { return next }
            try SecureCaptureFileIO.writeAtomically(data, relativePath: relativePath, rootURL: rootURL)
            return next
        }
    }

    /// Writes `text` beside the note as "<name> (Vox).md" (or "(Vox 2)", …)
    /// and returns the new note's relative path. Used by "Save a copy".
    public func writeCopy(_ text: String) throws -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        let stem = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
        for index in 1...500 {
            let suffix = index == 1 ? " (Vox)" : " (Vox \(index))"
            let name = "\(stem)\(suffix).md"
            let candidate = directory.isEmpty ? name : "\(directory)/\(name)"
            let document = try VaultNoteDocument(rootURL: rootURL, relativePath: candidate, coordinator: coordinator)
            do {
                try document.replace(with: text, expecting: nil)
                return candidate
            } catch VaultNoteDocumentError.changedOnDisk {
                continue
            }
        }
        throw CaptureModelError.invalidRelativePath(relativePath)
    }

    private func unlockedRead() throws -> VaultNoteSnapshot? {
        guard let data = try SecureCaptureFileIO.read(relativePath: relativePath, rootURL: rootURL) else {
            return nil
        }
        guard data.count <= Self.maximumByteCount else {
            throw VaultNoteDocumentError.tooLarge(relativePath)
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw VaultNoteDocumentError.notText(relativePath)
        }
        let modifiedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate
        return VaultNoteSnapshot(text: text, version: VaultNoteVersion(data: data), modifiedAt: modifiedAt)
    }
}

/// What the editor should do after comparing its last-saved state, its
/// current text and the note on disk. Pure, so every branch is unit tested.
public enum VaultNoteReconciliation: Equatable, Sendable {
    /// Disk and editor agree; nothing to do.
    case inSync
    /// Only the editor changed: write it.
    case save
    /// Only the file changed (in another app): take the disk text.
    case reload(VaultNoteSnapshot)
    /// Both changed since the last save: ask the person.
    case conflict(VaultNoteSnapshot)
    /// The note is gone from disk.
    case missing

    public static func decide(
        lastSaved: VaultNoteVersion,
        editorText: String,
        disk: VaultNoteSnapshot?
    ) -> VaultNoteReconciliation {
        let editorChanged = VaultNoteVersion(text: editorText) != lastSaved
        guard let disk else { return .missing }
        let diskChanged = disk.version != lastSaved
        switch (editorChanged, diskChanged) {
        case (false, false): return .inSync
        case (true, false): return .save
        case (false, true): return .reload(disk)
        case (true, true):
            // Both sides converged on the same bytes.
            if disk.version == VaultNoteVersion(text: editorText) { return .inSync }
            return .conflict(disk)
        }
    }
}

/// One row in the Files tree: a folder or a Markdown note under a vault root.
public struct VaultFileEntry: Identifiable, Equatable, Hashable, Sendable {
    public var relativePath: String
    public var name: String
    public var isDirectory: Bool
    public var modifiedAt: Date?
    /// Folders only: how many Markdown notes and folders sit directly inside.
    public var childCount: Int?

    public var id: String { relativePath }

    public init(relativePath: String, name: String, isDirectory: Bool, modifiedAt: Date?, childCount: Int? = nil) {
        self.relativePath = relativePath
        self.name = name
        self.isDirectory = isDirectory
        self.modifiedAt = modifiedAt
        self.childCount = childCount
    }
}

/// Lists one level of a vault folder for the Files tree. Hidden items
/// (".obsidian", ".trash", Vox's own temp files) and non-Markdown files are
/// skipped; folders sort first, then notes newest first.
public enum VaultFileIndex {
    public static func children(
        of relativeDirectory: String,
        rootURL: URL,
        countChildren: Bool = true,
        fileManager: FileManager = .default
    ) throws -> [VaultFileEntry] {
        if !relativeDirectory.isEmpty {
            try CapturePathValidation.validateRelativePath(relativeDirectory)
        }
        let directoryURL = relativeDirectory.isEmpty
            ? rootURL
            : rootURL.appendingPathComponent(relativeDirectory, isDirectory: true)
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey]
        let urls = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )
        var entries: [VaultFileEntry] = []
        for url in urls {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { continue }
            let name = url.lastPathComponent
            let isDirectory = values?.isDirectory ?? false
            if !isDirectory, !name.lowercased().hasSuffix(".md") { continue }
            let relativePath = relativeDirectory.isEmpty ? name : "\(relativeDirectory)/\(name)"
            var count: Int?
            if isDirectory, countChildren {
                count = (try? Self.children(
                    of: relativePath,
                    rootURL: rootURL,
                    countChildren: false,
                    fileManager: fileManager
                ).count)
            }
            entries.append(VaultFileEntry(
                relativePath: relativePath,
                name: name,
                isDirectory: isDirectory,
                modifiedAt: values?.contentModificationDate,
                childCount: count
            ))
        }
        return entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            if lhs.isDirectory {
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            switch (lhs.modifiedAt, rhs.modifiedAt) {
            case let (l?, r?) where l != r: return l > r
            default: return lhs.name.localizedStandardCompare(rhs.name) == .orderedDescending
            }
        }
    }

    /// The vault folder a note target writes into: the static directory part
    /// of its path template (`Daily/{date}.md` → `Daily`), or the containing
    /// folder of a fixed note. `""` is the vault root. Template tokens in a
    /// folder name stop the walk, since that folder changes per capture.
    public static func folder(for target: CaptureNoteTarget) -> String {
        let path: String
        switch target {
        case .newNote(let template): path = template
        case .rollingNote(let template, _): path = template
        case .existingNote(let relativePath): path = relativePath
        }
        let components = path.split(separator: "/").map(String.init).dropLast()
        var folder: [String] = []
        for component in components {
            if component.contains("{") { break }
            folder.append(component)
        }
        return folder.joined(separator: "/")
    }

    /// The fixed note a target always writes to, if it has one.
    public static func fixedNote(for target: CaptureNoteTarget) -> String? {
        if case .existingNote(let relativePath) = target { return relativePath }
        return nil
    }
}
