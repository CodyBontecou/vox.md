import AppIntents
import SwiftUI
import UniformTypeIdentifiers
import VoxboardShared

// MARK: - Default vault

/// The folder new routes write into by default. Stored in the App Group so
/// Settings, onboarding and the Routes list agree. Existing installs without a
/// stored vault derive it from the capture library's default destination.
struct VoxVault: Equatable {
    var name: String
    var bookmark: Data
    /// "Obsidian vault · iCloud Drive", "Folder · On My iPhone", …
    var detail: String
}

enum VoxVaultStore {
    static let bookmarkKey = "vox.defaultVault.bookmark.v1"
    static let nameKey = "vox.defaultVault.name.v1"
    static let detailKey = "vox.defaultVault.detail.v1"

    static func stored(defaults: UserDefaults? = AppConstants.sharedDefaults) -> VoxVault? {
        guard let bookmark = defaults?.data(forKey: bookmarkKey), !bookmark.isEmpty,
              let name = defaults?.string(forKey: nameKey) else { return nil }
        return VoxVault(name: name, bookmark: bookmark,
                        detail: defaults?.string(forKey: detailKey) ?? String(localized: "Folder"))
    }

    static func save(_ vault: VoxVault, defaults: UserDefaults? = AppConstants.sharedDefaults) {
        defaults?.set(vault.bookmark, forKey: bookmarkKey)
        defaults?.set(vault.name, forKey: nameKey)
        defaults?.set(vault.detail, forKey: detailKey)
    }

    /// Stored vault, else the library default destination's root folder.
    static func current() async -> VoxVault? {
        if let stored = stored() { return stored }
        guard let url = AppConstants.captureLibraryURL,
              let library = try? await CapturePresetRouteLibrary.load(from: CaptureLibraryStore(fileURL: url)) else {
            return nil
        }
        let destination = library.defaultDestinationID.flatMap { id in
            library.destinations.first { $0.id == id }
        } ?? library.destinations.first
        guard let destination, !destination.rootBookmark.isEmpty else { return nil }
        return VoxVault(name: destination.rootName, bookmark: destination.rootBookmark,
                        detail: detail(forBookmark: destination.rootBookmark))
    }

    /// Creates a security-scoped vault record from a folder picked in Files.
    static func make(from url: URL) throws -> VoxVault {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        return VoxVault(name: url.lastPathComponent, bookmark: bookmark, detail: detail(for: url))
    }

    /// Makes `vault` the default and re-points every destination rooted in the
    /// previous default vault at it. Returns the number of routes moved.
    @discardableResult
    static func change(to vault: VoxVault) async throws -> Int {
        let previous = await current()
        save(vault)
        guard let previous, previous.bookmark != vault.bookmark,
              let url = AppConstants.captureLibraryURL else { return 0 }
        let oldBookmark = previous.bookmark
        let result = try await CaptureLibraryStore(fileURL: url).updateReturning { library -> Int in
            var moved = 0
            for index in library.destinations.indices
            where library.destinations[index].rootBookmark == oldBookmark {
                library.destinations[index].rootBookmark = vault.bookmark
                library.destinations[index].rootName = vault.name
                moved += 1
            }
            return moved
        }
        return result.result
    }

    private static func detail(forBookmark bookmark: Data) -> String {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else {
            return String(localized: "Folder")
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        return detail(for: url)
    }

    static func detail(for url: URL) -> String {
        let isObsidian = FileManager.default.fileExists(atPath: url.appendingPathComponent(".obsidian", isDirectory: true).path)
        let kind = isObsidian ? String(localized: "Obsidian vault") : String(localized: "Folder")
        let path = url.path
        let location: String
        if path.contains("/Mobile Documents/") {
            location = String(localized: "iCloud Drive")
        } else if path.contains("/File Provider Storage/") || path.contains("/Containers/Shared/AppGroup/") {
            location = String(localized: "On My iPhone")
        } else {
            location = String(localized: "Files")
        }
        return "\(kind) · \(location)"
    }
}

// MARK: - Route destination wording

/// Path and placement wording for a route's destination, shared by the Routes
/// list, the route editor and Setup. The path formatting mirrors the share
/// extension's `ShareViewController.destinationLine` (template, `.md` added
/// when missing, ` › ## Heading` for heading placements); it is copied here
/// because the extension target cannot see app sources.
enum RouteDestinationFormatter {
    /// The note path a destination writes, as a template: `Meetings/{date}.md`,
    /// `Inbox/{title}.md`, `Tasks.md`.
    static func notePath(_ destination: CaptureDestination) -> String {
        var path: String
        switch destination.noteTarget {
        case .newNote(let template), .rollingNote(let template, _): path = template
        case .existingNote(let relativePath): path = relativePath
        }
        path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if (path as NSString).pathExtension.isEmpty { path += ".md" }
        return path
    }

    /// ` › ## Today` for heading placements, otherwise empty.
    static func headingSuffix(_ destination: CaptureDestination) -> String {
        guard let heading = headingMarkdown(destination) else { return "" }
        return " › \(heading)"
    }

    /// `## Today` for heading placements.
    static func headingMarkdown(_ destination: CaptureDestination) -> String? {
        guard case .beneathHeading(let heading, _, _) = destination.placement else { return nil }
        let level = max(1, min(6, heading.level ?? 2))
        return "\(String(repeating: "#", count: level)) \(heading.title)"
    }

    /// Mono path line: `Vox Notes / Meetings / {date}.md`, or with the heading
    /// `Vox Notes / Tasks.md › ## Today`.
    static func displayPath(
        _ destination: CaptureDestination,
        includesRoot: Bool = true,
        includesHeading: Bool
    ) -> String {
        var components = notePath(destination)
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        if includesRoot, !destination.rootName.isEmpty {
            components.insert(destination.rootName, at: 0)
        }
        let path = components.joined(separator: " / ")
        return includesHeading ? path + headingSuffix(destination) : path
    }

    /// The Routes list shows the heading in the path only for an existing
    /// note; rolling and new notes name it in the editor's Deliver step.
    static func listPath(_ destination: CaptureDestination) -> String {
        if case .existingNote = destination.noteTarget {
            return displayPath(destination, includesHeading: true)
        }
        return displayPath(destination, includesHeading: false)
    }

    /// "append" / "prepend": where in the note (or heading section) the
    /// entry goes.
    static func placementWord(_ destination: CaptureDestination) -> String {
        switch destination.placement {
        case .append: String(localized: "append")
        case .prepend: String(localized: "prepend")
        case .beneathHeading(_, _, let position):
            position == .bottom ? String(localized: "append") : String(localized: "prepend")
        }
    }

    static func periodNoteName(_ period: CaptureRollingPeriod) -> String {
        switch period {
        case .daily: String(localized: "Daily note")
        case .weekly: String(localized: "Weekly note")
        case .monthly: String(localized: "Monthly note")
        case .quarterly: String(localized: "Quarterly note")
        case .yearly: String(localized: "Yearly note")
        }
    }

    /// Editor Deliver title: "Daily note, under “## Notes”", "New note",
    /// "Tasks.md, under “## Today”".
    static func deliverTitle(_ destination: CaptureDestination) -> String {
        let base: String
        switch destination.noteTarget {
        case .newNote: base = String(localized: "New note")
        case .rollingNote(_, let period): base = periodNoteName(period)
        case .existingNote: base = (notePath(destination) as NSString).lastPathComponent
        }
        guard let heading = headingMarkdown(destination) else { return base }
        return String(localized: "\(base), under “\(heading)”")
    }

    /// Editor Deliver detail: `Vox Notes / Meetings / {date}.md · append`.
    static func deliverDetail(_ destination: CaptureDestination) -> String {
        "\(displayPath(destination, includesHeading: false)) · \(placementWord(destination))"
    }
}

// MARK: - Starter routes

/// The four routes offered during setup. Each becomes a real, editable route
/// with its own destination in the chosen vault. `allCases` is the Setup
/// board's row order; `installOrder` is the Routes board's order.
enum StarterRoute: String, CaseIterable, Identifiable {
    case inbox, meetingNotes, tasks, journal

    var id: String { rawValue }

    var name: String {
        switch self {
        case .inbox: String(localized: "Inbox")
        case .meetingNotes: String(localized: "Meeting Notes")
        case .tasks: String(localized: "Tasks")
        case .journal: String(localized: "Journal")
        }
    }

    /// Path label shown on the setup row, matching the destination below.
    var pathLabel: String {
        switch self {
        case .inbox: "Inbox/{title}.md"
        case .meetingNotes: "Meetings/{date}.md"
        case .tasks: "Tasks.md › ## Today"
        case .journal: "Journal/{week}.md"
        }
    }

    var isOnByDefault: Bool { self != .journal }

    /// Route order after setup, as on the Routes board: Meeting Notes first
    /// (the default, indigo tile), then Inbox (ink), Journal and Tasks.
    static let installOrder: [StarterRoute] = [.meetingNotes, .inbox, .journal, .tasks]

    private var symbolName: String {
        switch self {
        case .inbox: "tray"
        case .meetingNotes: "person.2"
        case .tasks: "checklist"
        case .journal: "book"
        }
    }

    private var noteTarget: CaptureNoteTarget {
        switch self {
        case .inbox: .newNote(pathTemplate: "Inbox/{title}")
        case .meetingNotes: .rollingNote(pathTemplate: "Meetings/{date}", period: .daily)
        case .tasks: .existingNote(relativePath: "Tasks.md")
        case .journal: .rollingNote(pathTemplate: "Journal/{week}", period: .weekly)
        }
    }

    private var placement: CapturePlacement {
        switch self {
        case .inbox: .append
        case .meetingNotes:
            .beneathHeading(CaptureHeadingSelector(title: "Notes", level: 2),
                            missingHeadingBehavior: .create, headingPosition: .bottom)
        case .tasks:
            .beneathHeading(CaptureHeadingSelector(title: "Today", level: 2),
                            missingHeadingBehavior: .create, headingPosition: .top)
        case .journal: .prepend
        }
    }

    private var processingMode: CapturePresetProcessingMode {
        switch self {
        case .inbox: .clean
        case .meetingNotes: .meetingNotes
        case .tasks: .todoList
        case .journal: .none
        }
    }

    /// Text quick actions pinned above the keyboard for this route, as on the
    /// Signal "Route quick actions" and "Capture · keyboard" boards. Media
    /// actions stay behind the composer's Attach control and the ••• panel.
    var quickActionPins: [CaptureQuickAction] {
        switch self {
        case .inbox: [.checklist, .internalLink, .tag, .heading, .bulletList, .timestamp]
        case .meetingNotes: [.timestamp, .checklist, .internalLink, .heading, .bulletList, .tag]
        case .tasks: [.checklist, .dueDate, .tag, .internalLink, .currentLocation]
        case .journal: [.timestamp, .date, .currentLocation, .tag, .bulletList]
        }
    }

    private var prompt: String {
        switch self {
        case .inbox: String(localized: "What’s on your mind?")
        case .meetingNotes: String(localized: "What was decided?")
        case .tasks: String(localized: "What needs doing?")
        case .journal: String(localized: "How was today?")
        }
    }

    /// SHAPE on the Routes / RouteEditor boards: Meeting Notes writes a
    /// timestamped entry (`### 10:42 · Project sync`, then the body); the
    /// other starter routes write the capture as typed.
    var entryPrefix: String {
        switch self {
        case .meetingNotes: "### {hour}:{minute} · {title}\n"
        case .inbox, .tasks, .journal: ""
        }
    }

    fileprivate func make(in vault: VoxVault) -> (CapturePreset, CaptureDestination) {
        var destination = CaptureDestination(
            name: name,
            rootBookmark: vault.bookmark,
            rootName: vault.name,
            noteTarget: noteTarget,
            placement: placement
        )
        destination.entryPrefix = entryPrefix
        var preset = CapturePresetStore.makeCustomFlow()
        preset.name = name
        preset.symbolName = symbolName
        preset.postProcessingMode = processingMode
        // Starter routes ship with their processing on; delivery falls back to the raw capture when Apple Intelligence is unavailable.
        preset.captureProcessingEnabled = processingMode != .none
        preset.capturePrompt = prompt
        preset.captureDestinationID = destination.id
        preset.exportSettings.usesCustomExportSettings = true
        return (preset, destination)
    }
}

enum StarterRouteInstaller {
    enum InstallError: LocalizedError {
        case storageUnavailable
        var errorDescription: String? { String(localized: "Shared capture storage is unavailable.") }
    }

    /// Creates the selected starter routes in `vault`, skipping any route whose
    /// name already exists, and makes Meeting Notes (else the first new route)
    /// the default route. On a fresh install the new routes lead the list in
    /// `StarterRoute.installOrder`, so tile tones match the Routes board.
    @MainActor
    static func install(_ routes: [StarterRoute], in vault: VoxVault) async throws {
        VoxVaultStore.save(vault)
        guard !routes.isEmpty else { return }
        guard let url = AppConstants.captureLibraryURL else { throw InstallError.storageUnavailable }
        // Finish the one-time owned-route migration before adding routes. On a
        // fresh install it would otherwise run after the destinations below
        // are written but before their presets are saved, promote them as
        // orphans ("route-…" presets) and leave every starter route listed
        // twice.
        _ = try await CapturePresetRouteLibrary.load(from: CaptureLibraryStore(fileURL: url))
        var flows = CapturePresetStore.loadFlows()
        let existingNames = Set(flows.compactMap { $0.visibleName?.lowercased() })
        let selected = Set(routes)
        let created = StarterRoute.installOrder
            .filter { selected.contains($0) && !existingNames.contains($0.name.lowercased()) }
            .map { ($0, $0.make(in: vault)) }
        guard !created.isEmpty else { return }
        let defaultPreset = (created.first { $0.0 == .meetingNotes } ?? created.first)?.1.0
        let defaultDestinationID = defaultPreset?.captureDestinationID
        // Setup on a fresh install (nothing but built-in routes yet): the
        // starter routes replace the built-in Default route, which stays in
        // the library but disabled, and Meeting Notes becomes the default.
        // Anyone who already made routes keeps them exactly as they were.
        let isFreshSetup = flows.allSatisfy(\.isBuiltIn)
        _ = try await CaptureLibraryStore(fileURL: url).update { library in
            library.destinations.append(contentsOf: created.map(\.1.1))
            if library.defaultDestinationID == nil || isFreshSetup {
                library.defaultDestinationID = defaultDestinationID
            }
        }
        let presets = created.map(\.1.0)
        if isFreshSetup {
            for index in flows.indices where flows[index].isBuiltIn {
                flows[index].isEnabled = false
            }
            flows.insert(contentsOf: presets, at: 0)
        } else {
            flows.append(contentsOf: presets)
        }
        CapturePresetStore.saveFlows(flows)
        if isFreshSetup, let defaultPreset {
            CapturePresetStore.selectFlow(id: defaultPreset.id)
        }
        let toolbar = CaptureToolbarPreferences.shared
        for (route, made) in created where !toolbar.hasCustomPins(forRoute: made.0.id) {
            toolbar.setPinnedActions(route.quickActionPins, forRoute: made.0.id)
        }
        if let defaultPreset {
            CapturePresetProfileStore.selectCaptureProfile(id: defaultPreset.id, defaults: AppConstants.sharedDefaults)
        }
        if #available(iOS 18.0, *) {
            VoxboardShortcutsProvider.updateAppShortcutParameters()
        }
        WatchRecordingController.shared.publishState()
    }
}

// MARK: - Vault card

/// Bordered card naming the default vault with a Change affordance. Tapping
/// opens a Files folder picker; `onPick` receives the new vault.
struct VaultPickerCard: View {
    let vault: VoxVault?
    @Binding var isPicking: Bool
    /// Drops the card chrome when placed inside an existing grouped card.
    var embedded = false
    let onPick: (VoxVault) -> Void
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { isPicking = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Geist.onAccent)
                        .frame(width: 44, height: 44)
                        .background(Geist.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vault?.name ?? String(localized: "Choose a folder"))
                            .font(.custom("Geist-SemiBold", size: 17, relativeTo: .body))
                            .foregroundStyle(Geist.text)
                        Text(vault?.detail ?? String(localized: "An Obsidian vault or any folder in Files"))
                            .font(Geist.caption())
                            .foregroundStyle(Geist.muted)
                    }
                    Spacer(minLength: 8)
                    Text(vault == nil ? String(localized: "Choose") : String(localized: "Change"))
                        .font(Geist.label())
                        .foregroundStyle(Geist.accentText)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(embedded ? Color.clear : Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(embedded ? Color.clear : Geist.border, lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Opens Files to choose the folder notes are written to."))
            .accessibilityIdentifier("vault.change")
            if let errorMessage {
                Text(errorMessage).font(Geist.caption()).foregroundStyle(Geist.error)
            }
        }
        .fileImporter(isPresented: $isPicking, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    onPick(try VoxVaultStore.make(from: url))
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}
