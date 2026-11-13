import SwiftUI
import VoxboardShared

/// Files: the real vault as a folder tree. Each preset shows as a badge on
/// the folder or note it writes to; opening a note loads it into Capture,
/// where it autosaves like any Live Note.
struct VaultFilesView: View {
    @Bindable var viewModel: QuickCaptureViewModel
    /// Called after a note was opened in Capture (or New note was chosen).
    var onOpenedNote: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedRootID: UUID?
    @State private var children: [String: [VaultFileEntry]] = [:]
    @State private var expanded: Set<String> = []
    @State private var unreachable = false
    @State private var filter = ""
    @State private var openingFolder: VaultFolderRoute?

    private var roots: [VaultRoot] { viewModel.vaultRoots }

    private var root: VaultRoot? {
        roots.first(where: { $0.id == selectedRootID }) ?? roots.first
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Geist.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                            titleBlock
                            searchField
                            if roots.count > 1 { vaultPicker }
                            treeCard
                        }
                        .padding(.horizontal, Geist.Spacing.four)
                        .padding(.bottom, Geist.Spacing.six)
                    }
                    .refreshable { await reloadAll() }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $openingFolder) { route in
                VaultFolderView(
                    viewModel: viewModel,
                    route: route,
                    badges: badges,
                    onOpen: open(_:),
                    onNewNote: startNewNote
                )
            }
            .task(id: root?.id) { await reloadAll() }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Button { dismiss() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(SignalCircleButtonStyle())
                .accessibilityLabel("Back to Capture")
            Spacer()
            Button(action: startNewNote) { Image(systemName: "plus") }
                .buttonStyle(SignalCircleButtonStyle())
                .accessibilityLabel("New note")
        }
        .padding(.horizontal, Geist.Spacing.four)
        .padding(.vertical, Geist.Spacing.two)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: root?.name ?? String(localized: "Files"))
                .font(Geist.display(34))
                .foregroundStyle(Geist.text)
                .accessibilityAddTraits(.isHeader)
            Text("Your vault, as files. Every preset writes into one of these folders.")
                .font(Geist.body(.footnote))
                .foregroundStyle(Geist.muted)
        }
        .padding(.horizontal, 4)
        .padding(.top, Geist.Spacing.two)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Geist.muted)
            TextField("Filter files", text: $filter)
                .font(Geist.body())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: Geist.ControlHeight.medium)
        .background(Geist.card, in: Capsule())
        .overlay(Capsule().stroke(Geist.border, lineWidth: 1))
    }

    private var vaultPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(roots) { vault in
                    Button(vault.name) { selectedRootID = vault.id }
                        .buttonStyle(ActivitySignalPillButtonStyle(kind: vault.id == root?.id ? .primary : .secondary))
                }
            }
        }
    }

    // MARK: Tree

    @ViewBuilder
    private var treeCard: some View {
        if roots.isEmpty {
            emptyMessage("Set up a preset to choose your vault folder.")
        } else if unreachable {
            VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                Text("Can’t reach this folder")
                    .font(Geist.heading(.callout))
                    .foregroundStyle(Geist.text)
                Text("Folder access may have expired. Re-grant it from Activity or the preset's settings.")
                    .font(Geist.body(.subheadline))
                    .foregroundStyle(Geist.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Geist.Spacing.four)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            let rows = visibleRows
            VStack(spacing: 0) {
                if rows.isEmpty {
                    emptyMessage(filter.isEmpty ? "No Markdown files yet." : "No files match.")
                }
                ForEach(rows) { row in
                    rowView(row)
                }
            }
            .padding(.vertical, 6)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func emptyMessage(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Geist.body(.subheadline))
            .foregroundStyle(Geist.muted)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Geist.Spacing.six)
    }

    /// Folders show their first few notes inline; the rest are one tap away.
    private static let inlineFileLimit = 3

    private var visibleRows: [VaultTreeRow] {
        var rows: [VaultTreeRow] = []
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        func walk(_ directory: String, depth: Int) {
            let entries = children[directory] ?? []
            var shownFiles = 0
            for entry in entries {
                if entry.isDirectory {
                    let isOpen = expanded.contains(entry.relativePath) || !query.isEmpty
                    if query.isEmpty || entry.name.lowercased().contains(query) || isOpen {
                        rows.append(.folder(entry, depth: depth, isExpanded: isOpen))
                    }
                    if isOpen { walk(entry.relativePath, depth: depth + 1) }
                } else {
                    if !query.isEmpty {
                        if entry.name.lowercased().contains(query) {
                            rows.append(.file(entry, depth: depth))
                        }
                        continue
                    }
                    if depth > 0, shownFiles >= Self.inlineFileLimit {
                        continue
                    }
                    shownFiles += 1
                    rows.append(.file(entry, depth: depth))
                }
            }
            let fileCount = entries.filter { !$0.isDirectory }.count
            if query.isEmpty, depth > 0, fileCount > Self.inlineFileLimit {
                rows.append(.more(directory: directory, count: fileCount - Self.inlineFileLimit, depth: depth))
            }
        }
        walk("", depth: 0)
        return rows
    }

    private var badges: [String: [VaultPresetBadge]] {
        guard let root else { return [:] }
        return viewModel.presetBadges(inVaultOf: root.destinationID)
    }

    @ViewBuilder
    private func rowView(_ row: VaultTreeRow) -> some View {
        switch row {
        case .folder(let entry, let depth, let isExpanded):
            Button {
                toggle(entry)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Geist.faint)
                        .frame(width: 14)
                    Image(systemName: "folder")
                        .foregroundStyle(Geist.muted)
                    Text(verbatim: entry.name)
                        .font(Geist.mono(size: 14.5, relativeTo: .body))
                        .foregroundStyle(Geist.text)
                        .lineLimit(1)
                    badgeChips(for: entry.relativePath)
                    Spacer(minLength: 4)
                    if let count = entry.childCount {
                        Text(verbatim: "\(count)")
                            .font(Geist.mono(size: 12, relativeTo: .caption))
                            .foregroundStyle(Geist.faint)
                    }
                }
                .padding(.leading, 12 + CGFloat(depth) * 22)
                .padding(.trailing, 14)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(verbatim: "\(entry.name), folder"))
            .accessibilityHint(isExpanded ? "Collapses the folder" : "Expands the folder")
        case .file(let entry, let depth):
            let isOpen = viewModel.liveNote?.binding.relativePath == entry.relativePath
            Button {
                open(entry)
            } label: {
                HStack(spacing: 8) {
                    if depth == 0 {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Geist.muted)
                            .frame(width: 22)
                    }
                    Text(verbatim: entry.name)
                        .font(Geist.mono(size: 14.5, relativeTo: .body))
                        .foregroundStyle(Geist.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    badgeChips(for: entry.relativePath)
                    if let modified = entry.modifiedAt, Calendar.current.isDateInToday(modified) {
                        Text("today")
                            .font(Geist.caption(.caption2).weight(.medium))
                            .foregroundStyle(Geist.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Geist.Palette.green100, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 4)
                    if let modified = entry.modifiedAt {
                        Text(verbatim: Self.shortDate(modified))
                            .font(Geist.mono(size: 12, relativeTo: .caption))
                            .foregroundStyle(Geist.faint)
                    }
                }
                .padding(.leading, depth == 0 ? 12 : 12 + CGFloat(depth) * 22 + 20)
                .padding(.trailing, 14)
                .frame(minHeight: 44)
                .background(isOpen ? Geist.accentSoft.opacity(0.6) : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this note in Capture")
        case .more(let directory, let count, let depth):
            Button {
                if let root { openingFolder = VaultFolderRoute(rootDestinationID: root.destinationID, relativeDirectory: directory) }
            } label: {
                Text("\(count) more")
                    .font(Geist.mono(size: 14, relativeTo: .body))
                    .foregroundStyle(Geist.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12 + CGFloat(depth) * 22 + 20)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows every note in this folder")
        }
    }

    @ViewBuilder
    private func badgeChips(for path: String) -> some View {
        ForEach(badges[path] ?? []) { badge in
            VaultPresetBadgeChip(badge: badge)
        }
    }

    static func shortDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        if let days = calendar.dateComponents([.day], from: date, to: Date()).day, days < 7 {
            return date.formatted(.dateTime.weekday(.abbreviated))
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Actions

    private func reloadAll() async {
        guard let root else { return }
        guard let top = await viewModel.vaultChildren(rootDestinationID: root.destinationID, relativeDirectory: "") else {
            unreachable = true
            return
        }
        unreachable = false
        var next: [String: [VaultFileEntry]] = ["": top]
        // Folders a preset writes to open by default.
        let presetFolders = Set(badges.keys.filter { !$0.lowercased().hasSuffix(".md") && !$0.isEmpty })
        if expanded.isEmpty {
            expanded = Set(top.filter { $0.isDirectory && presetFolders.contains($0.relativePath) }.map(\.relativePath))
        }
        for folder in expanded {
            next[folder] = await viewModel.vaultChildren(rootDestinationID: root.destinationID, relativeDirectory: folder)
        }
        children = next
    }

    private func toggle(_ entry: VaultFileEntry) {
        if expanded.contains(entry.relativePath) {
            expanded.remove(entry.relativePath)
            return
        }
        expanded.insert(entry.relativePath)
        guard children[entry.relativePath] == nil, let root else { return }
        Task {
            children[entry.relativePath] = await viewModel.vaultChildren(
                rootDestinationID: root.destinationID,
                relativeDirectory: entry.relativePath
            ) ?? []
        }
    }

    private func open(_ entry: VaultFileEntry) {
        guard let root else { return }
        let folder = (entry.relativePath as NSString).deletingLastPathComponent
        let badge = (badges[entry.relativePath] ?? badges[folder])?.first
        let binding = LiveNoteBinding(
            destinationID: root.destinationID,
            relativePath: entry.relativePath,
            savedVersion: VaultNoteVersion(sha256: ""),
            entryRequestID: nil,
            presetID: badge?.presetID
        )
        Task {
            await viewModel.openLiveNote(binding: binding)
            onOpenedNote()
        }
    }

    private func startNewNote() {
        Task {
            await viewModel.startNewNote()
            onOpenedNote()
        }
    }
}

enum VaultTreeRow: Identifiable {
    case folder(VaultFileEntry, depth: Int, isExpanded: Bool)
    case file(VaultFileEntry, depth: Int)
    case more(directory: String, count: Int, depth: Int)

    var id: String {
        switch self {
        case .folder(let entry, _, _): "d:\(entry.relativePath)"
        case .file(let entry, _): "f:\(entry.relativePath)"
        case .more(let directory, _, _): "m:\(directory)"
        }
    }
}

struct VaultFolderRoute: Hashable {
    var rootDestinationID: UUID
    var relativeDirectory: String
}

/// A preset as a small chip: letter avatar plus name.
struct VaultPresetBadgeChip: View {
    let badge: VaultPresetBadge

    var body: some View {
        HStack(spacing: 4) {
            Text(verbatim: badge.initial)
                .font(.custom("Geist-SemiBold", fixedSize: 8.5))
                .foregroundStyle(Color.white)
                .frame(width: 15, height: 15)
                .background(badge.isSelected ? Geist.accent : Geist.text, in: Circle())
            Text(verbatim: badge.name)
                .font(Geist.caption(.caption2).weight(.medium))
                .foregroundStyle(badge.isSelected ? Geist.accentText : Geist.text)
                .lineLimit(1)
        }
        .padding(.leading, 2)
        .padding(.trailing, 8)
        .padding(.vertical, 2)
        .background(badge.isSelected ? Geist.accentSoft : Geist.well, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Preset \(badge.name)"))
    }
}

/// Every note in one folder, grouped by month, newest first.
struct VaultFolderView: View {
    @Bindable var viewModel: QuickCaptureViewModel
    let route: VaultFolderRoute
    let badges: [String: [VaultPresetBadge]]
    var onOpen: (VaultFileEntry) -> Void
    var onNewNote: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entries: [VaultFileEntry] = []
    @State private var previews: [String: String] = [:]
    @State private var filter = ""

    private var folderName: String { (route.relativeDirectory as NSString).lastPathComponent }
    private var parentPath: String {
        let parent = (route.relativeDirectory as NSString).deletingLastPathComponent
        let vault = viewModel.vaultRoots.first(where: { $0.destinationID == route.rootDestinationID })?.name ?? ""
        return parent.isEmpty ? "\(vault) /" : "\(vault) / \(parent) /"
    }

    private var files: [VaultFileEntry] {
        let query = filter.trimmingCharacters(in: .whitespaces).lowercased()
        return entries.filter { !$0.isDirectory && (query.isEmpty || $0.name.lowercased().contains(query)) }
    }

    private var months: [(title: String, files: [VaultFileEntry])] {
        var groups: [(title: String, files: [VaultFileEntry])] = []
        for file in files {
            let title = file.modifiedAt?.formatted(.dateTime.month(.wide).year()) ?? String(localized: "Older")
            if let last = groups.indices.last, groups[last].title == title {
                groups[last].files.append(file)
            } else {
                groups.append((title, [file]))
            }
        }
        return groups
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Geist.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(SignalCircleButtonStyle())
                        .accessibilityLabel("Back")
                    Spacer()
                }
                .padding(.horizontal, Geist.Spacing.four)
                .padding(.vertical, Geist.Spacing.two)
                ScrollView {
                    VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: parentPath)
                                .font(Geist.mono(size: 12, relativeTo: .caption))
                                .foregroundStyle(Geist.muted)
                            Text(verbatim: "\(folderName)/")
                                .font(Geist.mono(size: 32, relativeTo: .largeTitle))
                                .foregroundStyle(Geist.text)
                                .accessibilityAddTraits(.isHeader)
                            HStack(spacing: 8) {
                                ForEach(badges[route.relativeDirectory] ?? []) { VaultPresetBadgeChip(badge: $0) }
                                Text("\(files.count) files")
                                    .font(Geist.body(.footnote))
                                    .foregroundStyle(Geist.muted)
                            }
                            .padding(.top, 4)
                        }
                        .padding(.horizontal, 4)
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(Geist.muted)
                            TextField("Search \(folderName)", text: $filter)
                                .font(Geist.body())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: Geist.ControlHeight.medium)
                        .background(Geist.card, in: Capsule())
                        .overlay(Capsule().stroke(Geist.border, lineWidth: 1))

                        ForEach(months, id: \.title) { group in
                            HStack {
                                Text(verbatim: group.title)
                                Spacer()
                                Text(verbatim: "\(group.files.count)").font(Geist.mono(size: 12, relativeTo: .caption))
                            }
                            .font(Geist.label(.footnote))
                            .foregroundStyle(Geist.muted)
                            .padding(.horizontal, 6)
                            .padding(.top, Geist.Spacing.two)
                            VStack(spacing: 0) {
                                ForEach(Array(group.files.enumerated()), id: \.element.id) { index, file in
                                    if index > 0 { GeistDivider() }
                                    fileRow(file)
                                }
                            }
                            .background(Geist.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                    }
                    .padding(.horizontal, Geist.Spacing.four)
                    .padding(.bottom, 110)
                }
            }
            Button(action: onNewNote) {
                Label("New note", systemImage: "square.and.pencil")
                    .font(Geist.label(.body))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Geist.text, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Geist.Spacing.four)
            .padding(.bottom, Geist.Spacing.two)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            entries = await viewModel.vaultChildren(
                rootDestinationID: route.rootDestinationID,
                relativeDirectory: route.relativeDirectory
            ) ?? []
        }
    }

    private func fileRow(_ file: VaultFileEntry) -> some View {
        Button { onOpen(file) } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(verbatim: file.name)
                        .font(Geist.mono(size: 15, relativeTo: .body))
                        .foregroundStyle(Geist.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let modified = file.modifiedAt, Calendar.current.isDateInToday(modified) {
                        Text("today")
                            .font(Geist.caption(.caption2).weight(.medium))
                            .foregroundStyle(Geist.success)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Geist.Palette.green100, in: RoundedRectangle(cornerRadius: 6))
                    }
                    Spacer(minLength: 4)
                    if let modified = file.modifiedAt {
                        Text(verbatim: VaultFilesView.shortDate(modified))
                            .font(Geist.mono(size: 12, relativeTo: .caption))
                            .foregroundStyle(Geist.faint)
                    }
                }
                if let preview = previews[file.relativePath] {
                    Text(verbatim: preview)
                        .font(Geist.body(.subheadline))
                        .foregroundStyle(Geist.muted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .task(id: file.relativePath) {
            guard previews[file.relativePath] == nil else { return }
            if let preview = await viewModel.vaultNotePreview(
                rootDestinationID: route.rootDestinationID,
                relativePath: file.relativePath
            ) {
                previews[file.relativePath] = preview
            }
        }
    }
}
