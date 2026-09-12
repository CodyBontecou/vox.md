import AppKit
import SwiftUI
import VoxboardShared

/// A Mac-first activity workspace that brings durable recording work and
/// completed Capture history into one searchable place.
struct MacActivityView: View {
    @Bindable var queue: RecordingJobQueue
    @Bindable var viewModel: QuickCaptureViewModel
    @Environment(TranscriptStore.self) private var transcriptStore

    @State private var searchText = ""
    @State private var scope: MacActivityScope = .all
    @State private var selection: MacActivitySelection?
    @State private var localErrorMessage: String?
    @State private var isRefreshing = false
    @State private var pendingDeletion: MacActivityDeletion?

    private let retryCoordinator: MacActivityRetryCoordinator?
    private let recoveryPresets: [CapturePreset]
    private let openCapture: () -> Void

    init(
        queue: RecordingJobQueue,
        viewModel: QuickCaptureViewModel,
        retryOverride: (@MainActor (RecordingJob, RecordingJobDelivery?) async -> Void)? = nil,
        openCapture: @escaping () -> Void = {}
    ) {
        self.queue = queue
        self.viewModel = viewModel
        self.retryCoordinator = retryOverride.map(MacActivityRetryCoordinator.init(action:))
        self.recoveryPresets = CapturePresetStore.loadFlows().filter(\.isEnabled)
        self.openCapture = openCapture
    }

    var body: some View {
        Group {
            if allItems.isEmpty {
                firstRunEmptyState
            } else if visibleItems.isEmpty {
                filteredEmptyState
            } else {
                HSplitView {
                    activityList
                        .frame(minWidth: 300, idealWidth: 350, maxWidth: 430)
                    activityDetail
                        .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .navigationTitle("Activity")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search Activity")
        .toolbar {
            ToolbarItem {
                Picker("Activity Filter", selection: $scope) {
                    ForEach(MacActivityScope.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
            }

            ToolbarItemGroup {
                if !queue.retryAllEligibleJobs.isEmpty {
                    Button("Retry All", systemImage: "arrow.clockwise") {
                        Task { await retryAllFailedJobs() }
                    }
                }

                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await reloadActivity() }
                }
                .disabled(isRefreshing)
            }
        }
        .task {
            await reloadActivity()
        }
        .task {
            await queue.monitorDurableChanges()
        }
        .onChange(of: visibleItems.map(\.id)) { _, _ in
            reconcileSelection()
        }
        .alert("Activity Error", isPresented: errorPresented) {
            Button("Dismiss") {}
        } message: {
            Text(activityErrorMessage ?? String(localized: "Unknown error"))
        }
        .confirmationDialog(
            pendingDeletion?.title ?? String(localized: "Delete Item?"),
            isPresented: deletionPresented,
            titleVisibility: .visible
        ) {
            Button(pendingDeletion?.actionTitle ?? String(localized: "Delete"), role: .destructive) {
                confirmPendingDeletion()
            }
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(pendingDeletion?.message ?? "")
        }
    }

    private var allItems: [MacActivityItem] {
        let transcriptIDs = Set(transcriptStore.transcripts.map(\.id))
        let actionableJobs = queue.actionableJobs
        let actionableJobIDs = Set(actionableJobs.map(\.id))
        let now = actionableJobs
            .sorted { $0.createdAt > $1.createdAt }
            .map(MacActivityItem.recording)

        var captureByID: [UUID: CaptureHistoryRecord] = [:]
        for record in viewModel.historyRecords {
            captureByID[record.requestID] = record
        }

        let transcripts = transcriptStore.transcripts
            .filter { !actionableJobIDs.contains($0.id) }
            .map { transcript in
                MacActivityItem.transcript(
                    transcript,
                    delivery: captureByID[transcript.id]
                )
            }
        let captureOnly = viewModel.historyRecords
            .filter {
                !transcriptIDs.contains($0.requestID)
                    && !actionableJobIDs.contains($0.requestID)
            }
            .map(MacActivityItem.capture)
        let recent = (transcripts + captureOnly).sorted { $0.date > $1.date }

        let failedInbox: [MacActivityItem] = viewModel.failedInboxCount > 0
            ? [.failedInbox(viewModel.failedInboxCount)]
            : []
        return failedInbox + now + recent
    }

    private var visibleItems: [MacActivityItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return allItems.filter { item in
            scope.includes(item) && (query.isEmpty || item.matches(query))
        }
    }

    private var nowItems: [MacActivityItem] {
        visibleItems.filter(\.isCurrent)
    }

    private var recentItems: [MacActivityItem] {
        visibleItems.filter { !$0.isCurrent }
    }

    private var selectedItem: MacActivityItem? {
        guard let selection else { return nil }
        return visibleItems.first(where: { $0.id == selection })
    }

    private var activityList: some View {
        List(selection: $selection) {
            if !nowItems.isEmpty {
                Section("Now") {
                    ForEach(nowItems) { item in
                        MacActivityRow(
                            item: item,
                            isActive: item.activeJobID == queue.activeJobID,
                            progress: item.activeJobID == queue.activeJobID
                                ? queue.transcriptionProgress?.exactFractionCompleted
                                : nil
                        )
                        .tag(item.id)
                        .contextMenu { contextMenu(for: item) }
                    }
                }
            }

            if !recentItems.isEmpty {
                Section("Recent") {
                    ForEach(recentItems) { item in
                        MacActivityRow(item: item)
                            .tag(item.id)
                            .contextMenu { contextMenu(for: item) }
                    }
                }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .overlay(alignment: .bottomTrailing) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
            }
        }
        .onAppear { reconcileSelection() }
    }

    @ViewBuilder
    private var activityDetail: some View {
        if let selectedItem {
            switch selectedItem {
            case .recording(let job):
                MacActivityRecordingDetail(
                    job: job,
                    queue: queue,
                    retryCoordinator: retryCoordinator,
                    recoveryPresets: recoveryPresets,
                    onDelete: { pendingDeletion = .recording(job) },
                    onError: { localErrorMessage = $0 }
                )

            case .transcript(let transcript, let delivery):
                MacActivityTranscriptDetail(
                    transcript: transcript,
                    delivery: delivery,
                    onCopy: { copyToPasteboard($0) },
                    onReveal: { reveal($0) },
                    onDelete: { pendingDeletion = .transcript(transcript) }
                )

            case .capture(let record):
                MacActivityCaptureDetail(
                    record: record,
                    onReveal: { reveal(record) },
                    onDelete: { pendingDeletion = .capture(record) }
                )

            case .failedInbox(let count):
                MacActivityInboxDetail(count: count) {
                    Task { await viewModel.retryFailedInbox() }
                }
            }
        } else {
            ContentUnavailableView(
                "Select an Activity",
                systemImage: "sidebar.left",
                description: Text("Choose an item to see its status, transcript, and available actions.")
            )
        }
    }

    private var firstRunEmptyState: some View {
        ContentUnavailableView {
            VStack(spacing: 10) {
                MacAppIconView(size: 52)
                    .accessibilityHidden(true)
                Label("No Activity Yet", systemImage: "clock.arrow.circlepath")
            }
        } description: {
            Text("Record or send a Capture and its progress will appear here.")
        } actions: {
            Button("Start a Capture", systemImage: "mic.fill", action: openCapture)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView {
            Label(
                searchText.isEmpty ? "No Matching Activity" : "No Search Results",
                systemImage: searchText.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass"
            )
        } description: {
            Text(
                searchText.isEmpty
                    ? "There are no items in this activity filter."
                    : "No activity matches “\(searchText)”."
            )
        } actions: {
            Button("Show All") {
                scope = .all
                searchText = ""
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func contextMenu(for item: MacActivityItem) -> some View {
        switch item {
        case .recording(let job):
            recordingPrimaryAction(for: job)

            if let transcript = job.transcriptText, !transcript.isEmpty {
                Button("Copy Transcript", systemImage: "doc.on.doc") {
                    if copyToPasteboard(transcript) {
                        Task { await queue.acknowledgeCopiedResult(job) }
                    }
                }
            }

            if let audioURL = queue.audioURL(for: job) {
                Button("Reveal Audio in Finder", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([audioURL])
                }
            }

            if job.phase != .processing && job.phase != .finalizing {
                Divider()
                Button("Delete Recording", systemImage: "trash", role: .destructive) {
                    pendingDeletion = .recording(job)
                }
            }

        case .transcript(let transcript, let delivery):
            Button("Copy Transcript", systemImage: "doc.on.doc") {
                copyToPasteboard(transcript.cleanedText ?? transcript.text)
            }
            if let delivery, delivery.outcome == .delivered, delivery.relativeNotePath != nil {
                Button("Reveal Note in Finder", systemImage: "folder") { reveal(delivery) }
            }
            Divider()
            Button("Delete Transcript", systemImage: "trash", role: .destructive) {
                pendingDeletion = .transcript(transcript)
            }

        case .capture(let record):
            if record.outcome == .delivered, record.relativeNotePath != nil {
                Button("Reveal Note in Finder", systemImage: "folder") { reveal(record) }
                Divider()
            }
            Button("Delete Capture Record", systemImage: "trash", role: .destructive) {
                pendingDeletion = .capture(record)
            }

        case .failedInbox(let count):
            Button(
                count == 1 ? "Retry Queued Capture" : "Retry \(count) Queued Captures",
                systemImage: "arrow.clockwise"
            ) {
                Task { await viewModel.retryFailedInbox() }
            }
        }
    }

    @ViewBuilder
    private func recordingPrimaryAction(for job: RecordingJob) -> some View {
        switch job.phase {
        case .queued:
            Button("Process Now", systemImage: "play.fill") {
                Task { await queue.processNow(job) }
            }

        case .failed where job.delivery == .recovery:
            Menu("Retry with Preset", systemImage: "arrow.clockwise") {
                if recoveryPresets.isEmpty {
                    Text("No Enabled Capture Presets")
                } else {
                    ForEach(recoveryPresets) { preset in
                        Button(preset.accessibilityName) {
                            Task { await retry(job, delivery: .preset(preset)) }
                        }
                    }
                }
            }

        case .failed:
            Button("Retry", systemImage: "arrow.clockwise") {
                Task { await retry(job) }
            }

        default:
            EmptyView()
        }
    }

    private func retry(
        _ job: RecordingJob,
        delivery: RecordingJobDelivery? = nil
    ) async {
        if let retryCoordinator {
            await retryCoordinator.retry(job, delivery: delivery)
        } else {
            await queue.retry(job, delivery: delivery)
        }
    }

    private func retryAllFailedJobs() async {
        for job in queue.retryAllEligibleJobs {
            await retry(job)
        }
    }

    private func reloadActivity() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await queue.refresh(recoverInterrupted: true)
        await viewModel.load()
        await viewModel.refreshHistory()
        transcriptStore.reload()
        reconcileSelection()
    }

    private func reconcileSelection() {
        let candidates = visibleItems
        guard !candidates.isEmpty else {
            selection = nil
            return
        }
        if let selection, candidates.contains(where: { $0.id == selection }) {
            return
        }
        selection = candidates.first?.id
    }

    private func deleteTranscript(_ transcript: Transcript) {
        selectFallback(removing: .transcript(transcript.id))
        transcriptStore.delete(ids: [transcript.id])
        if let persistenceError = transcriptStore.lastPersistenceError {
            localErrorMessage = persistenceError.localizedDescription
        }
        Task {
            await viewModel.deleteHistory(requestID: transcript.id)
            reconcileSelection()
        }
    }

    private func deleteCapture(_ record: CaptureHistoryRecord) {
        selectFallback(removing: .capture(record.requestID))
        Task {
            await viewModel.deleteHistory(requestID: record.requestID)
            reconcileSelection()
        }
    }

    private func confirmPendingDeletion() {
        guard let deletion = pendingDeletion else { return }
        pendingDeletion = nil
        switch deletion {
        case .recording(let job):
            Task { await queue.discard(job) }
        case .transcript(let transcript):
            deleteTranscript(transcript)
        case .capture(let record):
            deleteCapture(record)
        }
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { presented in
                if !presented { pendingDeletion = nil }
            }
        )
    }

    private func selectFallback(removing removedID: MacActivitySelection) {
        let candidates = visibleItems.filter { $0.id != removedID }
        selection = candidates.first?.id
    }

    private func reveal(_ record: CaptureHistoryRecord) {
        Task { @MainActor in
            do {
                guard let libraryURL = AppConstants.captureLibraryURL,
                      let relativePath = record.relativeNotePath else {
                    throw MacActivityRevealError.noteUnavailable
                }
                let library = try await CaptureLibraryStore(fileURL: libraryURL).load()
                guard let destination = library.destinations.first(where: {
                    $0.id == record.destinationID
                }) else {
                    throw MacActivityRevealError.destinationMissing
                }
                let resolution = try CaptureBookmarkResolver.resolve(destination.rootBookmark)
                guard !resolution.isStale else {
                    throw MacActivityRevealError.permissionExpired
                }
                let rootURL = resolution.url
                let didAccess = rootURL.startAccessingSecurityScopedResource()
                defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
                let noteURL = try CapturePathValidation.containedFileURL(
                    relativePath: relativePath,
                    rootURL: rootURL
                )
                NSWorkspace.shared.activateFileViewerSelecting([noteURL])
            } catch {
                localErrorMessage = error.localizedDescription
            }
        }
    }

    @discardableResult
    private func copyToPasteboard(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    private var activityErrorMessage: String? {
        localErrorMessage ?? viewModel.errorMessage ?? queue.lastError
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { activityErrorMessage != nil },
            set: { presented in
                if !presented {
                    localErrorMessage = nil
                    viewModel.errorMessage = nil
                    queue.clearError()
                }
            }
        )
    }
}

@MainActor
private final class MacActivityRetryCoordinator: @unchecked Sendable {
    private let action: @MainActor (RecordingJob, RecordingJobDelivery?) async -> Void

    init(action: @escaping @MainActor (RecordingJob, RecordingJobDelivery?) async -> Void) {
        self.action = action
    }

    func retry(_ job: RecordingJob, delivery: RecordingJobDelivery? = nil) async {
        await action(job, delivery)
    }
}

private enum MacActivityScope: String, CaseIterable, Identifiable {
    case all
    case inProgress
    case needsAttention

    var id: Self { self }

    var title: String {
        switch self {
        case .all: String(localized: "All")
        case .inProgress: String(localized: "In Progress")
        case .needsAttention: String(localized: "Needs Attention")
        }
    }

    func includes(_ item: MacActivityItem) -> Bool {
        switch self {
        case .all:
            true
        case .inProgress:
            item.isInProgress
        case .needsAttention:
            item.needsAttention
        }
    }
}

private enum MacActivitySelection: Hashable {
    case recording(UUID)
    case transcript(UUID)
    case capture(UUID)
    case failedInbox
}

private enum MacActivityDeletion {
    case recording(RecordingJob)
    case transcript(Transcript)
    case capture(CaptureHistoryRecord)

    var title: String {
        switch self {
        case .recording:
            String(localized: "Delete Recording?")
        case .transcript:
            String(localized: "Delete Transcript?")
        case .capture:
            String(localized: "Delete Capture Record?")
        }
    }

    var actionTitle: String {
        switch self {
        case .recording:
            String(localized: "Delete Recording")
        case .transcript:
            String(localized: "Delete Transcript")
        case .capture:
            String(localized: "Delete Record")
        }
    }

    var message: String {
        switch self {
        case .recording:
            String(localized: "This removes the queued recording and its retained audio. This action can’t be undone.")
        case .transcript:
            String(localized: "This deletes the saved transcript and its Activity and Library record. Any delivered Markdown file stays in place.")
        case .capture:
            String(localized: "This deletes the Activity and Library record. Any delivered Markdown file stays in place.")
        }
    }
}

private enum MacActivityItem: Identifiable {
    case recording(RecordingJob)
    case transcript(Transcript, delivery: CaptureHistoryRecord?)
    case capture(CaptureHistoryRecord)
    case failedInbox(Int)

    var id: MacActivitySelection {
        switch self {
        case .recording(let job): .recording(job.id)
        case .transcript(let transcript, _): .transcript(transcript.id)
        case .capture(let record): .capture(record.requestID)
        case .failedInbox: .failedInbox
        }
    }

    var date: Date {
        switch self {
        case .recording(let job): job.createdAt
        case .transcript(let transcript, _): transcript.date
        case .capture(let record): record.deliveredAt ?? record.createdAt
        case .failedInbox: .distantFuture
        }
    }

    var isCurrent: Bool {
        switch self {
        case .recording(let job): job.phase != .completed
        case .failedInbox: true
        case .transcript, .capture: false
        }
    }

    var activeJobID: UUID? {
        guard case .recording(let job) = self else { return nil }
        return job.id
    }

    var isInProgress: Bool {
        guard case .recording(let job) = self else { return false }
        return job.phase == .queued || job.phase == .processing || job.phase == .finalizing
    }

    var needsAttention: Bool {
        switch self {
        case .recording(let job):
            job.phase == .failed
        case .transcript(_, let delivery):
            delivery?.outcome == .failed
        case .capture(let record):
            record.outcome == .failed
        case .failedInbox:
            true
        }
    }

    var title: String {
        switch self {
        case .recording(let job):
            job.activityTitle
        case .transcript(let transcript, _):
            transcript.activityTitle
        case .capture(let record):
            record.destinationName
        case .failedInbox(let count):
            count == 1 ? String(localized: "Queued Capture") : String(localized: "Queued Captures")
        }
    }

    var subtitle: String {
        switch self {
        case .recording(let job):
            return job.activityStatus
        case .transcript(_, let delivery):
            guard let delivery else { return String(localized: "Transcript") }
            return delivery.outcome == .delivered
                ? String(localized: "Delivered")
                : String(localized: "Delivery Failed")
        case .capture(let record):
            if record.outcome == .failed {
                return record.failureCategory?.displayName ?? String(localized: "Delivery Failed")
            }
            return record.relativeNotePath ?? String(localized: "Delivered")
        case .failedInbox(let count):
            return count == 1
                ? String(localized: "1 capture needs attention")
                : String(localized: "\(count) captures need attention")
        }
    }

    var symbolName: String {
        switch self {
        case .recording(let job): job.activitySymbolName
        case .transcript: "waveform"
        case .capture(let record):
            record.outcome == .delivered ? "paperplane.fill" : "exclamationmark.triangle.fill"
        case .failedInbox: "tray.and.arrow.up.fill"
        }
    }

    var statusColor: Color {
        if needsAttention { return MacBrand.orangeText }
        switch self {
        case .recording(let job) where job.phase == .processing || job.phase == .finalizing:
            return MacBrand.orange
        case .recording(let job) where job.phase == .completed:
            return MacBrand.complete
        case .transcript(_, let delivery) where delivery?.outcome == .delivered:
            return MacBrand.complete
        case .capture(let delivery) where delivery.outcome == .delivered:
            return MacBrand.complete
        default:
            return .secondary
        }
    }

    func matches(_ query: String) -> Bool {
        searchCorpus.localizedCaseInsensitiveContains(query)
    }

    private var searchCorpus: String {
        switch self {
        case .recording(let job):
            return [
                title, subtitle, job.originalFilename, job.statusMessage,
                job.transcriptText, job.modelID, job.language,
            ].compactMap { $0 }.joined(separator: " ")
        case .transcript(let transcript, let delivery):
            return [
                title, subtitle, transcript.text, transcript.cleanedText,
                transcript.modelUsed, transcript.language, transcript.category,
                transcript.tags?.joined(separator: " "), delivery?.destinationName,
                delivery?.relativeNotePath,
            ].compactMap { $0 }.joined(separator: " ")
        case .capture(let record):
            return [
                title, subtitle, record.voxName, record.relativeNotePath,
                record.failureCategory?.displayName,
            ].compactMap { $0 }.joined(separator: " ")
        case .failedInbox:
            return "\(title) \(subtitle)"
        }
    }
}

private struct MacActivityRow: View {
    let item: MacActivityItem
    var isActive = false
    var progress: Double?

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.symbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(item.statusColor)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if item.date != .distantFuture {
                        Text(item.date, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 6) {
                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(
                            item.needsAttention ? MacBrand.orangeText : Color.secondary
                        )
                        .lineLimit(1)
                    if isActive {
                        Spacer(minLength: 4)
                        if let progress {
                            ProgressView(value: progress)
                                .controlSize(.mini)
                                .frame(width: 66)
                        } else {
                            ProgressView()
                                .controlSize(.mini)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct MacActivityRecordingDetail: View {
    let job: RecordingJob
    @Bindable var queue: RecordingJobQueue
    let retryCoordinator: MacActivityRetryCoordinator?
    let recoveryPresets: [CapturePreset]
    let onDelete: () -> Void
    let onError: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                processingStatus

                if let transcript = job.transcriptText, !transcript.isEmpty {
                    GroupBox("Transcript") {
                        Text(transcript)
                            .font(.body)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                }

                metadata
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: job.activitySymbolName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(
                    job.phase == .failed ? MacBrand.orangeText : MacBrand.orange
                )
                .frame(width: 64, height: 64)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(job.activityTitle)
                    .font(.largeTitle.weight(.semibold))
                    .textSelection(.enabled)
                Text("\(job.createdAt.formatted(date: .abbreviated, time: .shortened))  ·  \(job.duration.activityDuration)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)
            actions
        }
    }

    private var processingStatus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(job.activityStatus, systemImage: job.activitySymbolName)
                    .font(.headline)
                    .foregroundStyle(
                        job.phase == .failed ? MacBrand.orangeText : Color.primary
                    )
                Spacer()
                if queue.activeJobID == job.id,
                   let fraction = queue.transcriptionProgress?.exactFractionCompleted {
                    Text(fraction, format: .percent.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if queue.activeJobID == job.id {
                if let fraction = queue.transcriptionProgress?.exactFractionCompleted {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }
            }

            if let message = job.statusMessage, !message.isEmpty {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(
                        job.phase == .failed ? MacBrand.orangeText : Color.secondary
                    )
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
    }

    private var metadata: some View {
        GroupBox("Recording") {
            VStack(spacing: 9) {
                LabeledContent("Duration", value: job.duration.activityDuration)
                Divider()
                LabeledContent("Model", value: job.modelID)
                Divider()
                LabeledContent("Language", value: job.language.uppercased())
                Divider()
                LabeledContent("Attempts", value: job.attemptCount.formatted())
                if let filename = job.originalFilename {
                    Divider()
                    LabeledContent("Original File", value: filename)
                }
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            primaryAction

            if let transcript = job.transcriptText, !transcript.isEmpty {
                Button("Copy", systemImage: "doc.on.doc") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    if pasteboard.setString(transcript, forType: .string) {
                        Task { await queue.acknowledgeCopiedResult(job) }
                    }
                }
                .help("Copy Transcript")
            }

            if let audioURL = queue.audioURL(for: job) {
                Button("Reveal", systemImage: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([audioURL])
                }
                .help("Reveal Audio in Finder")
            }

            if job.phase != .processing && job.phase != .finalizing {
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                .help("Delete Recording")
            }
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch job.phase {
        case .queued:
            Button("Process Now", systemImage: "play.fill") {
                Task { await queue.processNow(job) }
            }
            .labelStyle(.titleAndIcon)
            .help("Process Now")

        case .failed where job.delivery == .recovery:
            Menu("Retry with Preset", systemImage: "arrow.clockwise") {
                if recoveryPresets.isEmpty {
                    Text("No Enabled Capture Presets")
                } else {
                    ForEach(recoveryPresets) { preset in
                        Button(preset.accessibilityName) {
                            Task { await retry(delivery: .preset(preset)) }
                        }
                    }
                }
            }
            .labelStyle(.titleAndIcon)

        case .failed:
            Button("Retry", systemImage: "arrow.clockwise") {
                Task { await retry() }
            }
            .labelStyle(.titleAndIcon)
            .help("Retry Recording")

        default:
            EmptyView()
        }
    }

    private func retry(delivery: RecordingJobDelivery? = nil) async {
        if let retryCoordinator {
            await retryCoordinator.retry(job, delivery: delivery)
        } else {
            await queue.retry(job, delivery: delivery)
        }
        if let error = queue.lastError { onError(error) }
    }
}

private struct MacActivityTranscriptDetail: View {
    let transcript: Transcript
    let delivery: CaptureHistoryRecord?
    let onCopy: (String) -> Void
    let onReveal: (CaptureHistoryRecord) -> Void
    let onDelete: () -> Void

    private var primaryText: String {
        guard let cleaned = transcript.cleanedText,
              !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return transcript.text
        }
        return cleaned
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(MacBrand.orange)
                        .frame(width: 64, height: 64)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(transcript.activityTitle)
                            .font(.largeTitle.weight(.semibold))
                            .textSelection(.enabled)
                        Text("\(transcript.date.formatted(date: .long, time: .shortened))  ·  \(transcript.duration.activityDuration)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    Button("Copy", systemImage: "doc.on.doc") { onCopy(primaryText) }
                        .help("Copy Transcript")
                    if let delivery,
                       delivery.outcome == .delivered,
                       delivery.relativeNotePath != nil {
                        Button("Reveal", systemImage: "folder") { onReveal(delivery) }
                            .help("Reveal Note in Finder")
                    }
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        .help("Delete from Activity")
                }
                .labelStyle(.iconOnly)

                GroupBox(transcript.cleanedText == nil ? "Transcript" : "Cleaned Transcript") {
                    Text(primaryText)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }

                if let cleaned = transcript.cleanedText,
                   cleaned != transcript.text {
                    DisclosureGroup("Raw Transcript") {
                        Text(transcript.text)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }

                transcriptMetadata
                if let delivery { MacActivityDeliveryMetadata(record: delivery, onReveal: onReveal) }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var transcriptMetadata: some View {
        GroupBox("Details") {
            VStack(spacing: 9) {
                LabeledContent("Model", value: transcript.modelUsed)
                Divider()
                LabeledContent("Language", value: transcript.language.uppercased())
                if transcript.speakerCount > 0 {
                    Divider()
                    LabeledContent("Speakers", value: transcript.speakerCount.formatted())
                }
                if let category = transcript.category, !category.isEmpty {
                    Divider()
                    LabeledContent("Category", value: category)
                }
                if let tags = transcript.tags, !tags.isEmpty {
                    Divider()
                    LabeledContent("Tags", value: tags.map { "#\($0)" }.joined(separator: "  "))
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct MacActivityCaptureDetail: View {
    let record: CaptureHistoryRecord
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: record.outcome == .delivered
                          ? "paperplane.fill"
                          : "exclamationmark.triangle.fill")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(
                            record.outcome == .delivered
                                ? MacBrand.complete
                                : MacBrand.orangeText
                        )
                        .frame(width: 64, height: 64)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.destinationName)
                            .font(.largeTitle.weight(.semibold))
                            .textSelection(.enabled)
                        Label(
                            record.outcome == .delivered ? "Delivered" : "Delivery Failed",
                            systemImage: record.outcome == .delivered
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .foregroundStyle(
                            record.outcome == .delivered
                                ? Color.secondary
                                : MacBrand.orangeText
                        )
                    }
                    Spacer(minLength: 16)
                    if record.outcome == .delivered, record.relativeNotePath != nil {
                        Button("Reveal", systemImage: "folder", action: onReveal)
                            .help("Reveal Note in Finder")
                    }
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                        .help("Delete from Activity")
                }
                .labelStyle(.iconOnly)

                MacActivityDeliveryMetadata(record: record) { _ in onReveal() }
            }
            .frame(maxWidth: 780, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct MacActivityDeliveryMetadata: View {
    let record: CaptureHistoryRecord
    var onReveal: ((CaptureHistoryRecord) -> Void)?

    var body: some View {
        GroupBox("Delivery") {
            VStack(spacing: 9) {
                LabeledContent("Status") {
                    Label(
                        record.outcome == .delivered ? "Delivered" : "Failed",
                        systemImage: record.outcome == .delivered
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(
                        record.outcome == .delivered
                            ? Color.secondary
                            : MacBrand.orangeText
                    )
                }
                Divider()
                LabeledContent("Destination", value: record.destinationName)
                Divider()
                LabeledContent("Created", value: record.createdAt.formatted(date: .long, time: .shortened))
                if let deliveredAt = record.deliveredAt {
                    Divider()
                    LabeledContent("Delivered", value: deliveredAt.formatted(date: .long, time: .shortened))
                }
                if let preset = record.voxName, !preset.isEmpty {
                    Divider()
                    LabeledContent("Capture Preset", value: preset)
                }
                if let path = record.relativeNotePath {
                    Divider()
                    LabeledContent("Note") {
                        Button(path) { onReveal?(record) }
                            .buttonStyle(.link)
                            .disabled(onReveal == nil || record.outcome != .delivered)
                    }
                }
                Divider()
                LabeledContent("Attachments", value: record.attachmentCount.formatted())
                if let failure = record.failureCategory {
                    Divider()
                    LabeledContent("Failure") {
                        Text(failure.displayName)
                            .foregroundStyle(MacBrand.orangeText)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

private struct MacActivityInboxDetail: View {
    let count: Int
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Captures Need Attention", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(MacBrand.orangeText)
        } description: {
            Text(
                count == 1
                    ? "One queued Capture could not be delivered. Its content is still stored locally."
                    : "\(count) queued Captures could not be delivered. Their content is still stored locally."
            )
        } actions: {
            Button("Retry Now", systemImage: "arrow.clockwise", action: retry)
        }
    }
}

private enum MacActivityRevealError: Error, LocalizedError {
    case noteUnavailable
    case destinationMissing
    case permissionExpired

    var errorDescription: String? {
        switch self {
        case .noteUnavailable:
            String(localized: "The note location is not available in Activity.")
        case .destinationMissing:
            String(localized: "The Capture destination no longer exists.")
        case .permissionExpired:
            String(localized: "Vox.md no longer has permission to access this destination. Choose the folder again in Settings.")
        }
    }
}

private extension RecordingJob {
    var activityTitle: String {
        switch delivery {
        case .preset(let preset): preset.accessibilityName
        case .captureDraft: String(localized: "Capture Recording")
        case .clipboard: String(localized: "Clipboard Transcription")
        case .keyboard: String(localized: "Keyboard Transcription")
        case .recovery: String(localized: "Recovered Recording")
        }
    }

    var activityStatus: String {
        if phase == .completed, transcriptText != nil {
            return String(localized: "Ready to Copy")
        }
        switch phase {
        case .queued: return String(localized: "Queued")
        case .processing: return String(localized: "Transcribing")
        case .finalizing: return String(localized: "Saving")
        case .completed: return String(localized: "Completed")
        case .failed: return String(localized: "Needs Attention")
        case .discarded: return String(localized: "Deleted")
        }
    }

    var activitySymbolName: String {
        switch phase {
        case .queued: "clock"
        case .processing, .finalizing: "waveform"
        case .completed: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .discarded: "trash"
        }
    }
}

private extension Transcript {
    var activityTitle: String {
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            return title
        }
        let source = (cleanedText ?? text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let source, !source.isEmpty else { return String(localized: "Transcript") }
        return source.count > 64 ? String(source.prefix(61)) + "…" : source
    }
}

private extension TimeInterval {
    var activityDuration: String {
        let seconds = max(0, Int(rounded()))
        if seconds < 60 { return String(localized: "\(seconds) sec") }
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainder)
        }
        return String(format: "%d:%02d", minutes, remainder)
    }
}
