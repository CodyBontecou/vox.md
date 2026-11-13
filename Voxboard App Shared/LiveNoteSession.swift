import Foundation
import Observation
import VoxboardShared

/// Which vault file an editor owns, and the exact bytes it last wrote there.
struct LiveNoteBinding: Codable, Equatable, Sendable {
    var destinationID: UUID
    var relativePath: String
    var savedVersion: VaultNoteVersion
    /// Append presets: the capture that created this binding, used to
    /// highlight the new entry inside the whole file.
    var entryRequestID: UUID?
    var presetID: String?

    var fileName: String { (relativePath as NSString).lastPathComponent }

    var title: String {
        (fileName as NSString).deletingPathExtension
    }
}

/// What the save pill under the preset shows.
enum LiveNoteStatus: Equatable {
    /// Nothing written yet; the first words create the file.
    case idle
    case saving
    case saved
    /// Both this editor and another app changed the file. Saving is paused.
    case conflict(VaultNoteSnapshot)
    /// The vault folder can't be reached. Text is kept in the app.
    case unreachable
    /// The file was deleted or moved in another app.
    case missing
    case failed(String)

    var needsAttention: Bool {
        switch self {
        case .conflict, .unreachable, .missing, .failed: true
        default: false
        }
    }
}

enum LiveNoteConflictChoice {
    case keepMine
    case useTheirs
    case saveCopy
}

/// Keeps one open vault note in sync with an editor: debounced whole-file
/// saves, compare-and-swap against the last written version, quiet reloads
/// when only another app changed the file, and a conflict when both did.
@MainActor
@Observable
final class LiveNoteSession {
    static let saveDebounce: Duration = .milliseconds(600)

    private(set) var binding: LiveNoteBinding
    private(set) var status: LiveNoteStatus = .saved
    private(set) var lastSavedAt: Date?

    /// Called with disk text when another app changed the file and the
    /// editor had nothing unsaved (or the person chose "Use theirs").
    @ObservationIgnored var applyExternalText: ((String) -> Void)?
    /// Called whenever the binding (its saved version or path) changes, so
    /// the owner can persist it and restore the session after relaunch.
    @ObservationIgnored var bindingDidChange: ((LiveNoteBinding) -> Void)?

    @ObservationIgnored private var latestText: String
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let resolveRoot: @MainActor (UUID) -> URL?

    init(
        binding: LiveNoteBinding,
        text: String,
        resolveRoot: @escaping @MainActor (UUID) -> URL?
    ) {
        self.binding = binding
        self.latestText = text
        self.resolveRoot = resolveRoot
        if VaultNoteVersion(text: text) != binding.savedVersion {
            status = .saving
        }
    }

    var text: String { latestText }

    var hasUnsavedChanges: Bool {
        VaultNoteVersion(text: latestText) != binding.savedVersion
    }

    /// The editor's text changed. Saves after a short pause in typing.
    func textDidChange(_ text: String) {
        guard text != latestText else { return }
        latestText = text
        if case .conflict = status { return }
        status = .saving
        scheduleSave()
    }

    /// Starts a save when the editor already differs from the file (e.g. a
    /// session restored with edits that never reached the vault).
    func saveIfNeeded() {
        guard hasUnsavedChanges else { return }
        if case .conflict = status { return }
        status = .saving
        scheduleSave()
    }

    /// Writes any pending text now (backgrounding, New note, leaving a file).
    func flush() async {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return }
        await save()
    }

    /// Compares the editor with the file on disk, e.g. when the app returns
    /// to the foreground. Reloads quietly when only the file changed.
    func checkDisk() async {
        if case .conflict = status { return }
        guard let rootURL = resolveRoot(binding.destinationID) else {
            status = .unreachable
            return
        }
        let binding = self.binding
        let editorText = latestText
        let result: Result<VaultNoteReconciliation, Error> = await Self.withRoot(rootURL) {
            let document = try VaultNoteDocument(rootURL: rootURL, relativePath: binding.relativePath)
            let disk = try document.read()
            return VaultNoteReconciliation.decide(
                lastSaved: binding.savedVersion,
                editorText: editorText,
                disk: disk
            )
        }
        switch result {
        case .success(let decision):
            await apply(decision)
        case .failure(let error):
            status = .failed(error.localizedDescription)
        }
    }

    func resolveConflict(_ choice: LiveNoteConflictChoice) async {
        guard case .conflict(let disk) = status else { return }
        switch choice {
        case .useTheirs:
            adopt(disk)
            applyExternalText?(disk.text)
        case .keepMine:
            // Overwrite exactly the version the person saw.
            binding.savedVersion = disk.version
            bindingDidChange?(binding)
            status = .saving
            await save()
        case .saveCopy:
            guard let rootURL = resolveRoot(binding.destinationID) else {
                status = .unreachable
                return
            }
            let binding = self.binding
            let mine = latestText
            let copied: Result<String, Error> = await Self.withRoot(rootURL) {
                try VaultNoteDocument(rootURL: rootURL, relativePath: binding.relativePath).writeCopy(mine)
            }
            switch copied {
            case .success(let copyPath):
                // Keep editing the copy; the original stays as the other app left it.
                self.binding.relativePath = copyPath
                self.binding.savedVersion = VaultNoteVersion(text: mine)
                bindingDidChange?(self.binding)
                lastSavedAt = Date()
                status = .saved
            case .failure(let error):
                status = .failed(error.localizedDescription)
            }
        }
    }

    /// Re-creates a file that was deleted elsewhere from the editor's text.
    func recreateMissingFile() async {
        guard status == .missing, let rootURL = resolveRoot(binding.destinationID) else { return }
        let binding = self.binding
        let text = latestText
        let result: Result<VaultNoteVersion, Error> = await Self.withRoot(rootURL) {
            try VaultNoteDocument(rootURL: rootURL, relativePath: binding.relativePath)
                .replace(with: text, expecting: nil)
        }
        handleSaveResult(result, text: text)
    }

    // MARK: Saving

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: Self.saveDebounce)
            guard !Task.isCancelled else { return }
            await self?.save()
        }
    }

    private func save() async {
        guard let rootURL = resolveRoot(binding.destinationID) else {
            status = .unreachable
            return
        }
        let binding = self.binding
        let text = latestText
        let result: Result<VaultNoteVersion, Error> = await Self.withRoot(rootURL) {
            try VaultNoteDocument(rootURL: rootURL, relativePath: binding.relativePath)
                .replace(with: text, expecting: binding.savedVersion)
        }
        handleSaveResult(result, text: text)
    }

    private func handleSaveResult(_ result: Result<VaultNoteVersion, Error>, text: String) {
        switch result {
        case .success(let version):
            binding.savedVersion = version
            bindingDidChange?(binding)
            lastSavedAt = Date()
            // Typing may have continued while the write ran.
            status = latestText == text ? .saved : .saving
            if latestText != text { scheduleSave() }
        case .failure(VaultNoteDocumentError.changedOnDisk(let current)):
            let decision = VaultNoteReconciliation.decide(
                lastSaved: binding.savedVersion,
                editorText: latestText,
                disk: current
            )
            Task { await self.apply(decision) }
        case .failure(let error as CocoaError) where error.code == .fileReadNoPermission
            || error.code == .fileWriteNoPermission
            || error.code == .fileNoSuchFile:
            status = .unreachable
        case .failure(let error):
            status = .failed(error.localizedDescription)
        }
    }

    private func apply(_ decision: VaultNoteReconciliation) async {
        switch decision {
        case .inSync:
            status = .saved
        case .save:
            status = .saving
            await save()
        case .reload(let disk):
            adopt(disk)
            applyExternalText?(disk.text)
        case .conflict(let disk):
            saveTask?.cancel()
            status = .conflict(disk)
        case .missing:
            saveTask?.cancel()
            status = .missing
        }
    }

    private func adopt(_ disk: VaultNoteSnapshot) {
        latestText = disk.text
        binding.savedVersion = disk.version
        bindingDidChange?(binding)
        lastSavedAt = disk.modifiedAt ?? Date()
        status = .saved
    }

    /// Runs blocking file work off the main actor inside the root's
    /// security scope.
    private static func withRoot<T: Sendable>(
        _ rootURL: URL,
        _ work: @escaping @Sendable () throws -> T
    ) async -> Result<T, Error> {
        await Task.detached(priority: .userInitiated) {
            let didAccess = rootURL.startAccessingSecurityScopedResource()
            defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
            return Result { try work() }
        }.value
    }
}

/// Persists the composer's open-file binding beside the drafts so a relaunch
/// reopens the same file instead of starting a duplicate.
struct LiveNoteBindingStore {
    let fileURL: URL

    func load() -> LiveNoteBinding? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(LiveNoteBinding.self, from: data)
    }

    func save(_ binding: LiveNoteBinding?) {
        guard let binding else {
            try? FileManager.default.removeItem(at: fileURL)
            return
        }
        guard let data = try? JSONEncoder().encode(binding) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// A note the composer just closed with New note; drives the Reopen toast.
struct ClosedLiveNote: Equatable, Identifiable {
    var binding: LiveNoteBinding
    var presetName: String
    var closedAt: Date

    var id: Date { closedAt }
}
