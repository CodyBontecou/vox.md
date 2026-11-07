import SwiftUI
import UIKit
import VoxboardShared

/// The Signal Library: every capture this device delivered, grouped by day,
/// searchable and filterable by route. Rows open `CaptureDetailView`.
struct HistoryView: View {
    @Bindable var viewModel: QuickCaptureViewModel
    var isReadOnly = false
    /// When false the Library is pushed onto an existing navigation stack
    /// (for example from Activity) instead of owning one.
    var embedsInNavigationStack = true
    /// Opens the plans sheet from the read-only card. Defaults to dismissing,
    /// which returns to the paywall that presented the read-only Library.
    var onSeePlans: (() -> Void)?
    /// Regular-width list | detail Library: rows report their selection here
    /// instead of pushing `CaptureDetailView`, and the first row is selected
    /// when nothing is. `nil` keeps the phone's push navigation.
    var onSelectItem: ((LibraryItem, Bool) -> Void)?
    /// The row highlighted while `onSelectItem` drives a detail pane.
    var selectedItemID: UUID?
    /// When set, the header shows "New" (back to capture) instead of Back.
    var onNew: (() -> Void)?

    @Environment(TranscriptStore.self) private var store
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss
    /// "See plans" from the in-app read-only Library (trial ended).
    @State private var showsPlans = false
    @Environment(\.openURL) private var openURL
    @State private var showClearHistoryConfirmation = false
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var routeFilter: String?
    @State private var contentByID: [UUID: CaptureLibraryContent] = [:]
    @State private var editingTranscript: Transcript?
    @State private var sharePayload: TranscriptSharePayload?
    @State private var exportError: String?
    @State private var isExporting = false

    private var unifiedItems: [LibraryItem] {
        LibraryItem.build(
            transcripts: store.transcripts,
            records: viewModel.historyRecords,
            content: contentByID
        )
    }

    private var routeChips: [LibraryRouteChip] {
        var chips: [LibraryRouteChip] = []
        var seen = Set<String>()
        for profile in viewModel.voxProfiles where profile.isEnabled {
            guard seen.insert(profile.name).inserted else { continue }
            chips.append(LibraryRouteChip(name: profile.name))
        }
        for item in unifiedItems {
            guard let name = item.routeName, seen.insert(name).inserted else { continue }
            chips.append(LibraryRouteChip(name: name))
        }
        return chips
    }

    private var filteredItems: [LibraryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return unifiedItems.filter { item in
            if let routeFilter, item.routeName != routeFilter { return false }
            return query.isEmpty || item.matches(query)
        }
    }

    var body: some View {
        if embedsInNavigationStack {
            NavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
        ZStack {
            Geist.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        titleBlock
                            .padding(.horizontal, 4)
                            .padding(.bottom, 6)
                        if libraryIsReadOnly {
                            LibraryTrialEndedCard(onSeePlans: seePlans)
                                .padding(.bottom, 6)
                        }
                        if unifiedItems.isEmpty {
                            emptyState
                                .padding(.top, Geist.Spacing.ten)
                        } else if filteredItems.isEmpty {
                            noSearchResults
                                .padding(.top, Geist.Spacing.ten)
                        } else {
                            daySectionsView
                        }
                    }
                    .padding(.horizontal, Geist.Spacing.four)
                    .padding(.bottom, Geist.Spacing.eight)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable { await reload() }

                // Read-only (trial ended): the Speak bar stays visible but
                // locked, as on the "Trial ended" board.
                if libraryIsReadOnly, onSelectItem == nil {
                    LockedSpeakBar()
                        .padding(.horizontal, Geist.Spacing.four + 4)
                        .padding(.top, Geist.Spacing.two)
                        .padding(.bottom, Geist.Spacing.two)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsPlans) {
            PaywallView(context: .limit)
                .environment(usageTracker)
                .environment(storeManager)
        }
        .alert("Clear the Library?", isPresented: $showClearHistoryConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                store.clear()
                contentByID = [:]
                Task { await viewModel.clearHistory() }
            }
        } message: {
            Text("This clears transcript content and Capture delivery metadata. It does not delete exported Markdown notes or attachments.")
        }
        .alert("Library Error", isPresented: errorPresented) {
            Button("Dismiss Error") {
                exportError = nil
                store.clearPersistenceError()
            }
        } message: {
            Text(exportError ?? store.lastPersistenceError?.localizedDescription ?? String(localized: "Unknown error"))
        }
        .sheet(item: $editingTranscript) { transcript in
            TranscriptEditView(transcript: transcript) { edited in
                store.update(edited)
            }
        }
        .sheet(item: $sharePayload) { payload in
            TranscriptActivityView(activityItems: [payload.url])
                .ignoresSafeArea()
        }
        .onAppear { store.reload() }
        .task { await reload() }
        .onChange(of: selectionRefreshKey, initial: true) { _, _ in reportSelection() }
    }

    /// Changes whenever the visible rows or their loaded content change, so a
    /// split Library keeps its detail pane on a fresh copy of the row.
    private var selectionRefreshKey: [String] {
        guard onSelectItem != nil else { return [] }
        return filteredItems.map(\.id.uuidString) + ["\(contentByID.count)"]
    }

    private func reportSelection() {
        guard let onSelectItem else { return }
        let items = filteredItems
        if let selectedItemID, let current = items.first(where: { $0.id == selectedItemID }) {
            onSelectItem(current, isPrimaryRoute(current))
        } else if let first = items.first {
            onSelectItem(first, isPrimaryRoute(first))
        }
    }

    private func reload() async {
        store.reload()
        await viewModel.refreshHistory()
        contentByID = await LibraryContentLoader.loadAll()
    }

    /// Read-only when presented from the paywall, or in the app once a
    /// trial or subscription has ended (`UsageTracker.isLibraryReadOnly`).
    private var libraryIsReadOnly: Bool {
        isReadOnly || usageTracker.isLibraryReadOnly
    }

    private func seePlans() {
        if let onSeePlans {
            onSeePlans()
        } else if isReadOnly {
            // Opened from the paywall: going back shows the plans.
            dismiss()
        } else {
            showsPlans = true
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            if onNew == nil {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(SignalCircleButtonStyle())
                .accessibilityLabel("Back")
            }

            Spacer()

            if let onNew {
                Button(action: onNew) {
                    Text("New")
                        .font(Geist.label(.subheadline))
                        .foregroundStyle(Geist.bg)
                        .padding(.horizontal, 14)
                        .frame(height: Geist.ControlHeight.medium)
                        .background(Geist.text, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New capture")
                .accessibilityIdentifier("library_new_capture")
            }

            if !unifiedItems.isEmpty {
                Menu {
                    Button("Export all as Markdown", systemImage: "square.and.arrow.up") {
                        exportAll()
                    }
                    Divider()
                    Button("Clear Library…", systemImage: "trash", role: .destructive) {
                        showClearHistoryConfirmation = true
                    }
                } label: {
                    Text("Export")
                        .font(Geist.label(.subheadline))
                        .foregroundStyle(Geist.text)
                        .padding(.horizontal, 14)
                        .frame(height: Geist.ControlHeight.medium)
                        .background(Geist.card, in: Capsule())
                        .overlay(Capsule().stroke(Geist.border, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .disabled(isExporting)
                .accessibilityLabel("Export all")
            }
        }
        .padding(.horizontal, Geist.Spacing.four + 4)
        .padding(.top, Geist.Spacing.two)
        .padding(.bottom, Geist.Spacing.two)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Library")
                .font(Geist.display(34))
                .foregroundStyle(Geist.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, Geist.Spacing.three)

            searchField

            if !routeChips.isEmpty && !unifiedItems.isEmpty {
                ActivitySignalFlowLayout(spacing: 6) {
                    chip(title: String(localized: "All"), isOn: routeFilter == nil) { routeFilter = nil }
                    ForEach(routeChips) { chip in
                        self.chip(title: chip.name, isOn: routeFilter == chip.name) {
                            routeFilter = routeFilter == chip.name ? nil : chip.name
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Filter by route")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Geist.muted)
                .accessibilityHidden(true)
            TextField("Search words, routes, files", text: $searchText)
                .font(Geist.body(.body))
                .foregroundStyle(Geist.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($searchFocused)
                .accessibilityLabel("Search captures")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Geist.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: Geist.ControlHeight.medium)
        .background(Geist.card, in: Capsule())
        .overlay(
            Capsule().stroke(searchFocused ? Geist.accent : Geist.border, lineWidth: searchFocused ? 2 : 1)
        )
    }

    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(isOn ? Geist.label(.subheadline) : Geist.body(.subheadline))
                .foregroundStyle(isOn ? Geist.Palette.background100 : Geist.text)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(isOn ? Geist.text : Geist.card, in: Capsule())
                .overlay {
                    if !isOn { Capsule().stroke(Geist.border, lineWidth: 1) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // MARK: States

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { exportError != nil || store.lastPersistenceError != nil },
            set: { presented in
                if !presented {
                    exportError = nil
                    store.clearPersistenceError()
                }
            }
        )
    }

    private var emptyState: some View {
        ActivitySignalEmptyState(
            systemImage: "tray",
            tint: Geist.muted,
            title: "Nothing in Library Yet",
            message: "Record or send a Capture to add it to your Library."
        )
    }

    private var noSearchResults: some View {
        VStack(spacing: Geist.Spacing.three) {
            Text("No captures match")
                .font(Geist.heading(.title3))
                .foregroundStyle(Geist.text)
            Text("Library searches what Vox.md captured on this device. Older notes live in your vault.")
                .font(Geist.body(.callout))
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !query.isEmpty, let url = CaptureInboxRecovery.obsidianSearchURL(query: query) {
                Button("Search in Obsidian") { openURL(url) }
                    .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
                    .padding(.top, 6)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, Geist.Spacing.six)
    }

    // MARK: List

    private var daySections: [(day: Date, items: [LibraryItem])] {
        let calendar = Calendar.current
        var sections: [(day: Date, items: [LibraryItem])] = []
        for item in filteredItems {
            let day = calendar.startOfDay(for: item.date)
            if let last = sections.indices.last, sections[last].day == day {
                sections[last].items.append(item)
            } else {
                sections.append((day, [item]))
            }
        }
        return sections
    }

    private var routeOrder: [String] { routeChips.map(\.name) }

    /// Day groups, or one flat group in the read-only Library, whose rows
    /// carry their own dates ("Oct 28") as on the "Trial ended" board.
    private var listSections: [(day: Date, items: [LibraryItem])] {
        if libraryIsReadOnly {
            return filteredItems.isEmpty ? [] : [(day: .distantPast, items: filteredItems)]
        }
        return daySections
    }

    private var daySectionsView: some View {
        ForEach(listSections, id: \.day) { section in
            if !libraryIsReadOnly {
                Text(LibraryFormatting.dayLabel(section.day).uppercased())
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .tracking(0.66)
                    .foregroundStyle(Geist.muted)
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                    .padding(.bottom, 2)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(spacing: 0) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { GeistDivider() }
                    if let onSelectItem {
                        Button {
                            onSelectItem(item, isPrimaryRoute(item))
                        } label: {
                            row(item)
                                .padding(.horizontal, 8)
                                .background(
                                    selectedItemID == item.id ? Geist.accentSoft : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .padding(.horizontal, -8)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selectedItemID == item.id ? .isSelected : [])
                        .contextMenu { contextActions(for: item) }
                    } else {
                        NavigationLink {
                            CaptureDetailView(
                                item: item,
                                viewModel: viewModel,
                                isReadOnly: libraryIsReadOnly,
                                isPrimaryRoute: isPrimaryRoute(item)
                            )
                        } label: {
                            row(item)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { contextActions(for: item) }
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
        }
    }

    private func isPrimaryRoute(_ item: LibraryItem) -> Bool {
        guard let name = item.routeName else { return false }
        return routeOrder.first == name
    }

    private func row(_ item: LibraryItem) -> some View {
        HStack(spacing: Geist.Spacing.three) {
            LibraryRouteTileView(name: item.routeName, size: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Geist.Spacing.two) {
                    Text(verbatim: item.title)
                        .font(Geist.heading(.subheadline))
                        .foregroundStyle(Geist.text)
                        .lineLimit(1)
                    Spacer(minLength: Geist.Spacing.two)
                    if item.outcome == .failed {
                        Image(systemName: "exclamationmark.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Geist.Palette.amber900)
                            .accessibilityLabel("Delivery failed")
                    }
                    // Day-grouped rows carry the time beside the title.
                    if !libraryIsReadOnly { rowDate(item) }
                }
                if let excerpt = item.excerpt {
                    Text(verbatim: excerpt)
                        .font(Geist.body(.subheadline))
                        .foregroundStyle(Geist.muted)
                        .lineLimit(1)
                }
            }
            // The flat read-only list ("Trial ended" board) centers the date
            // ("Oct 28") at the trailing edge of the row.
            if libraryIsReadOnly { rowDate(item) }
        }
        .padding(.vertical, Geist.Spacing.three)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the capture")
    }

    private func rowDate(_ item: LibraryItem) -> some View {
        Text(item.date, format: libraryIsReadOnly
            ? .dateTime.month(.abbreviated).day()
            : .dateTime.hour().minute())
            .font(Geist.mono(size: 11, relativeTo: .caption))
            .foregroundStyle(Geist.muted)
            .fixedSize()
    }

    @ViewBuilder
    private func contextActions(for item: LibraryItem) -> some View {
        if let markdown = item.copyableMarkdown {
            Button("Copy Markdown", systemImage: "doc.on.doc") { UIPasteboard.general.string = markdown }
        }
        if let transcript = item.transcript {
            if !libraryIsReadOnly {
                Button("Edit", systemImage: "pencil") { editingTranscript = transcript }
            }
        }
        Button("Export", systemImage: "square.and.arrow.up") { export(item) }
        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
    }

    private func delete(_ item: LibraryItem) {
        if item.transcript != nil { store.delete(ids: [item.id]) }
        contentByID[item.id] = nil
        Task { await viewModel.deleteHistory(requestID: item.id) }
    }

    private func export(_ item: LibraryItem) {
        do {
            sharePayload = TranscriptSharePayload(url: try LibraryExporter.exportOne(item))
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportAll() {
        isExporting = true
        defer { isExporting = false }
        do {
            sharePayload = TranscriptSharePayload(url: try LibraryExporter.exportAll(unifiedItems))
        } catch {
            exportError = error.localizedDescription
        }
    }
}

// MARK: - Library model

struct LibraryRouteChip: Identifiable {
    let name: String
    var id: String { name }
}

/// One Library row: a transcript, a capture delivery record, or both, plus
/// the delivered content recorded for it.
struct LibraryItem: Identifiable {
    let id: UUID
    var transcript: Transcript?
    var record: CaptureHistoryRecord?
    var content: CaptureLibraryContent?

    static func build(
        transcripts: [Transcript],
        records: [CaptureHistoryRecord],
        content: [UUID: CaptureLibraryContent]
    ) -> [LibraryItem] {
        var recordByID: [UUID: CaptureHistoryRecord] = [:]
        for record in records { recordByID[record.requestID] = record }
        let transcriptIDs = Set(transcripts.map(\.id))
        let transcriptItems = transcripts.map {
            LibraryItem(id: $0.id, transcript: $0, record: recordByID[$0.id], content: content[$0.id])
        }
        let captureItems = records
            .filter { !transcriptIDs.contains($0.requestID) }
            .map { LibraryItem(id: $0.requestID, transcript: nil, record: $0, content: content[$0.requestID]) }
        return (transcriptItems + captureItems).sorted { $0.date > $1.date }
    }

    var date: Date {
        if let transcript { return transcript.date }
        return record?.createdAt ?? Date.distantPast
    }

    var deliveredAt: Date? { record?.deliveredAt }

    var outcome: CaptureHistoryOutcome? { record?.outcome }

    var routeName: String? {
        let name = record?.voxName ?? record?.destinationName
        return name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? name : nil
    }

    /// Words of the capture, best source first.
    var bodyText: String? {
        if let transcript {
            let text = transcript.cleanedText ?? transcript.text
            return text.isEmpty ? nil : text
        }
        return content?.text
    }

    var title: String {
        if let title = transcript?.title, !title.isEmpty { return title }
        if let line = Self.firstLine(of: bodyText) { return line }
        return record?.destinationName ?? String(localized: "Capture")
    }

    var excerpt: String? {
        guard let text = bodyText else { return record?.relativeNotePath }
        let hasExplicitTitle = transcript?.title?.isEmpty == false
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let remainder = hasExplicitTitle ? lines : Array(lines.dropFirst())
        let joined = remainder.map(Self.stripMarkdownPrefix).joined(separator: " · ")
        if joined.isEmpty { return record?.relativeNotePath }
        return joined
    }

    /// The Markdown exactly as delivered when recorded, else the best text.
    var copyableMarkdown: String? {
        content?.renderedMarkdown ?? bodyText
    }

    func matches(_ query: String) -> Bool {
        if let transcript, TranscriptSearch.matches(transcript, query: query) { return true }
        let haystack = [
            record?.destinationName,
            record?.voxName,
            record?.relativeNotePath,
            record?.placementHeading,
            record?.source.rawValue,
            content?.text,
            content?.renderedMarkdown,
            content?.audioFilename,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        let tokens = query.split(whereSeparator: \.isWhitespace).map(String.init)
        return tokens.allSatisfy { haystack.localizedCaseInsensitiveContains($0) }
    }

    nonisolated private static func firstLine(of text: String?) -> String? {
        guard let text else { return nil }
        let line = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        return line.map(stripMarkdownPrefix).flatMap { $0.isEmpty ? nil : String($0.prefix(120)) }
    }

    nonisolated private static func stripMarkdownPrefix(_ line: String) -> String {
        var result = line
        for prefix in ["- [ ] ", "- [x] ", "- ", "* ", "> "] where result.hasPrefix(prefix) {
            result.removeFirst(prefix.count)
            break
        }
        while result.hasPrefix("#") { result.removeFirst() }
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Markdown export with a small frontmatter header.
    var exportMarkdown: String {
        var lines = ["---"]
        lines.append("date: \(ISO8601DateFormatter().string(from: date))")
        if let routeName { lines.append("route: \"\(routeName.replacingOccurrences(of: "\"", with: "'"))\"") }
        if let path = record?.relativeNotePath { lines.append("delivered_to: \"\(path)\"") }
        if let transcript, transcript.duration > 0 { lines.append("duration: \(Int(transcript.duration.rounded()))") }
        lines.append("---")
        lines.append("")
        lines.append(copyableMarkdown ?? "")
        return lines.joined(separator: "\n") + "\n"
    }
}

enum LibraryContentLoader {
    static var historyStore: CaptureHistoryStore? {
        AppConstants.captureDirectoryURL.map {
            CaptureHistoryStore(fileURL: $0.appendingPathComponent(AppConstants.captureHistoryFilename))
        }
    }

    static func loadAll() async -> [UUID: CaptureLibraryContent] {
        await historyStore?.allContent() ?? [:]
    }
}

enum LibraryExporter {
    static func exportOne(_ item: LibraryItem) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxboardHistoryExports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename(for: item, used: []))
        try item.exportMarkdown.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Writes every capture as a Markdown file and zips the folder.
    static func exportAll(_ items: [LibraryItem]) throws -> URL {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("VoxboardLibraryExport-\(UUID().uuidString)", isDirectory: true)
        let folder = base.appendingPathComponent("Vox.md Library", isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        var used = Set<String>()
        for item in items {
            let name = filename(for: item, used: used)
            used.insert(name)
            try item.exportMarkdown.write(
                to: folder.appendingPathComponent(name),
                atomically: true,
                encoding: .utf8
            )
        }
        var zipURL: URL?
        var copyError: Error?
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(
            readingItemAt: folder,
            options: .forUploading,
            error: &coordinationError
        ) { temporaryZip in
            let destination = base.appendingPathComponent("Vox.md Library.zip")
            do {
                try fileManager.copyItem(at: temporaryZip, to: destination)
                zipURL = destination
            } catch {
                copyError = error
            }
        }
        if let zipURL { return zipURL }
        if coordinationError == nil, let copyError { throw copyError }
        return folder
    }

    private static func filename(for item: LibraryItem, used: Set<String>) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let slug = item.title
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
            .prefix(60)
        let stem = slug.isEmpty
            ? formatter.string(from: item.date)
            : "\(formatter.string(from: item.date)) \(slug)"
        var name = "\(stem).md"
        var counter = 2
        while used.contains(name) {
            name = "\(stem) \(counter).md"
            counter += 1
        }
        return name
    }
}

enum LibraryFormatting {
    static func dayLabel(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return String(localized: "Today") }
        if calendar.isDateInYesterday(day) { return String(localized: "Yesterday") }
        if calendar.isDate(day, equalTo: Date(), toGranularity: .year) {
            return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    static func clock(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Rounded route letter tile, or a neutral glyph when no route is known. The
/// color follows the route's place in the user's route order.
struct LibraryRouteTileView: View {
    let name: String?
    var size: CGFloat = 32

    var body: some View {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            SignalRouteTile(letter: name, size: size, tone: .forRoute(named: name))
        } else {
            Image(systemName: "tray")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(Geist.text)
                .frame(width: size, height: size)
                .background(Geist.well, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
                .accessibilityHidden(true)
        }
    }
}

/// Read-only card shown wherever the Library is read-only: "Your trial has
/// ended" once paid access ran out, otherwise a first-run read-only title.
struct LibraryTrialEndedCard: View {
    @Environment(UsageTracker.self) private var usageTracker
    let onSeePlans: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(usageTracker.readOnlyTitle)
                .font(Geist.heading(.callout))
                .foregroundStyle(Geist.Palette.background100)
            Text("You can still read, search, copy, export and delete everything here. New captures and edits need Vox.md.")
                .font(Geist.body(.subheadline))
                .foregroundStyle(Geist.Palette.gray500)
                .fixedSize(horizontal: false, vertical: true)
            Button("See plans", action: onSeePlans)
                .font(Geist.label(.subheadline))
                .foregroundStyle(Geist.text)
                .padding(.horizontal, Geist.Spacing.four)
                .frame(minHeight: 40)
                .background(Geist.Palette.background100, in: Capsule())
                .buttonStyle(.plain)
        }
        .padding(Geist.Spacing.four)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Geist.text, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// The disabled Speak bar shown on Capture when access is read-only. The
/// Capture screen can place this in place of its Speak control while
/// `UsageTracker.isLibraryReadOnly` is true.
struct LockedSpeakBar: View {
    @Environment(UsageTracker.self) private var usageTracker
    var body: some View {
        Label("Speak", systemImage: "lock")
            .font(Geist.label(.body))
            .foregroundStyle(Geist.muted)
            .frame(maxWidth: .infinity, minHeight: Geist.ControlHeight.hero)
            .background(Geist.well, in: Capsule())
            .accessibilityLabel("Speak, locked")
            .accessibilityHint(usageTracker.readOnlyHint)
            .accessibilityAddTraits(.isButton)
            .accessibilityRemoveTraits(.isButton)
    }
}

extension UsageTracker {
    /// True when the trial has ended: the Library stays readable but new
    /// captures and edits are disabled.
    var isLibraryReadOnly: Bool { !hasUnlocked }

    /// "Your trial has ended" is only true once paid access actually ended;
    /// a first-run user browsing from the onboarding paywall never had one.
    var readOnlyTitle: LocalizedStringKey {
        hasAccessEnded ? "Your trial has ended" : "Read-only for now"
    }

    var readOnlyHint: Text {
        hasAccessEnded
            ? Text("Your trial has ended. See plans to capture again.")
            : Text("Start a plan to capture.")
    }

    /// The single read-only gate (docs/launch/hard-paywall): read, search,
    /// copy, export and explicit deletion stay available; editing, new
    /// recordings, new Capture deliveries and queued Capture retries require
    /// paid access. Runs `action` with paid access, otherwise `showPlans`, so
    /// a locked control opens the paywall instead of failing silently.
    func requirePaidAccess(otherwise showPlans: () -> Void, _ action: () -> Void) {
        if isLibraryReadOnly {
            showPlans()
        } else {
            action()
        }
    }
}

/// Label for a control gated by `UsageTracker.requirePaidAccess`: the
/// control stays visible and shows a lock while access is read-only.
struct PaidAccessLabel: View {
    @Environment(UsageTracker.self) private var usageTracker
    let title: LocalizedStringKey
    var systemImage: String?
    let isLocked: Bool

    init(_ title: LocalizedStringKey, systemImage: String? = nil, isLocked: Bool) {
        self.title = title
        self.systemImage = systemImage
        self.isLocked = isLocked
    }

    var body: some View {
        if isLocked {
            Label(title, systemImage: "lock")
                .labelStyle(.titleAndIcon)
                .accessibilityHint(usageTracker.readOnlyHint)
        } else if let systemImage {
            Label(title, systemImage: systemImage)
        } else {
            Text(title)
        }
    }
}

private struct TranscriptEditView: View {
    @Environment(\.dismiss) private var dismiss
    let transcript: Transcript
    let onSave: (Transcript) -> Void

    @State private var rawText: String
    @State private var cleanedText: String
    @State private var title: String
    @State private var tags: String
    @State private var category: String

    init(transcript: Transcript, onSave: @escaping (Transcript) -> Void) {
        self.transcript = transcript
        self.onSave = onSave
        _rawText = State(initialValue: transcript.text)
        _cleanedText = State(initialValue: transcript.cleanedText ?? "")
        _title = State(initialValue: transcript.title ?? "")
        _tags = State(initialValue: transcript.tags?.joined(separator: ", ") ?? "")
        _category = State(initialValue: transcript.category ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title and organization") {
                    TextField("Title", text: $title)
                    TextField("Tags, comma separated", text: $tags)
                    TextField("Category", text: $category)
                }
                Section("Cleaned text") {
                    TextEditor(text: $cleanedText).frame(minHeight: 140)
                }
                Section("Raw transcript") {
                    TextEditor(text: $rawText).frame(minHeight: 180)
                }
            }
            .navigationTitle("Edit Transcript")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let parsedTags = tags
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                        onSave(transcript.withEdits(
                            text: rawText,
                            title: nilIfEmpty(title),
                            tags: parsedTags.isEmpty ? nil : parsedTags,
                            category: nilIfEmpty(category),
                            cleanedText: nilIfEmpty(cleanedText)
                        ))
                        dismiss()
                    }
                }
            }
        }
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct TranscriptSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct TranscriptActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
