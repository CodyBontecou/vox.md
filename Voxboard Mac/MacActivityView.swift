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
    @State private var showsDetail = false
    @State private var progressStarts: [UUID: (date: Date, fraction: Double)] = [:]
    @State private var busyStore = MacFileBusyStore.shared
    @State private var failedInboxEntries: [CaptureFailedInboxEntry] = []
    @Environment(ModelManager.self) private var modelManager

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
        signalPage
        .macUnderTitleBar()
        .background(Geist.bg)
        .groupBoxStyle(MacSignalGroupBoxStyle())
        .navigationTitle("Activity")
        // No window toolbar (MacActivity): Refresh and Retry All are in the
        // View menu.
        .focusedSceneValue(\.macActivityMenuActions, MacActivityMenuActions(
            refresh: { Task { await reloadActivity() } },
            isRefreshing: isRefreshing,
            retryAll: queue.retryAllEligibleJobs.isEmpty ? nil : { Task { await retryAllFailedJobs() } }
        ))
        .task {
            await reloadActivity()
        }
        .task {
            await queue.monitorDurableChanges()
        }
        .task(id: viewModel.failedInboxCount) {
            await reloadFailedInboxEntries()
        }
        .onChange(of: queue.transcriptionProgress?.exactFractionCompleted) { _, fraction in
            guard let id = queue.activeJobID, let fraction, fraction > 0 else { return }
            if progressStarts[id] == nil { progressStarts[id] = (Date(), fraction) }
        }
        .sheet(isPresented: $showsDetail) {
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Done") { showsDetail = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(12)
                GeistDivider()
                activityDetail
            }
            .frame(minWidth: 620, minHeight: 520)
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

    // MARK: Signal single page

    private var failedJobs: [RecordingJob] {
        queue.actionableJobs
            .filter { $0.phase == .failed && busyStore.entry(for: $0.id) == nil }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var inFlightJobs: [RecordingJob] {
        queue.actionableJobs
            .filter { $0.phase == .queued || $0.phase == .processing || $0.phase == .finalizing }
            .sorted { lhs, rhs in
                if lhs.id == queue.activeJobID { return true }
                if rhs.id == queue.activeJobID { return false }
                return lhs.createdAt < rhs.createdAt
            }
    }

    private var readyJobs: [RecordingJob] {
        queue.actionableJobs.filter { $0.phase == .completed }
    }

    private var deliveredRecords: [CaptureHistoryRecord] {
        viewModel.historyRecords
            .filter { $0.outcome == .delivered }
            .sorted { ($0.deliveredAt ?? $0.createdAt) > ($1.deliveredAt ?? $1.createdAt) }
    }

    private var jobsTodayCount: Int {
        let calendar = Calendar.current
        let records = viewModel.historyRecords.filter {
            calendar.isDateInToday($0.deliveredAt ?? $0.createdAt)
        }
        let recordIDs = Set(records.map(\.requestID))
        let jobs = queue.actionableJobs.filter {
            calendar.isDateInToday($0.createdAt) && !recordIDs.contains($0.id)
        }
        return records.count + jobs.count
    }

    private var hasNeedsYou: Bool {
        !busyStore.entries.isEmpty || !failedJobs.isEmpty || viewModel.failedInboxCount > 0 || !readyJobs.isEmpty
    }

    private var signalPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Activity")
                        .font(Geist.display(28))
                        .tracking(-0.56)
                    Spacer(minLength: 12)
                    Text(verbatim: String(localized: "Queue runs while Vox.md is open · \(jobsTodayCount) jobs today"))
                        .font(Geist.mono(size: 12, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                }

                if !hasNeedsYou && inFlightJobs.isEmpty && deliveredRecords.isEmpty && transcriptStore.transcripts.isEmpty {
                    firstRunEmptyState
                        .frame(minHeight: 360)
                }

                if hasNeedsYou {
                    MacSignalSectionHeader("Needs you", color: MacBrand.attention)
                        .padding(.top, 6)
                    ForEach(busyStore.entries) { entry in
                        busyCard(entry)
                    }
                    ForEach(failedJobs) { job in
                        failedJobCard(job)
                    }
                    ForEach(readyJobs) { job in
                        readyJobCard(job)
                    }
                    if viewModel.failedInboxCount > 0 {
                        if failedInboxEntries.isEmpty {
                            failedInboxCard
                        } else {
                            ForEach(failedInboxEntries) { entry in
                                failedInboxEntryCard(entry)
                            }
                        }
                    }
                }

                if !inFlightJobs.isEmpty {
                    MacSignalSectionHeader("In flight")
                        .padding(.top, 10)
                    VStack(spacing: 0) {
                        ForEach(Array(inFlightJobs.enumerated()), id: \.element.id) { index, job in
                            if index > 0 { Rectangle().fill(Geist.Palette.gray200).frame(height: 1) }
                            inFlightRow(job)
                        }
                    }
                    .padding(.horizontal, 18)
                    .background(Geist.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Geist.border, lineWidth: 1) }
                }

                if !deliveredRecords.isEmpty {
                    deliveredSection
                }
            }
            .padding(.horizontal, 36)
            .padding(.top, 28)
            .padding(.bottom, 40)
            .frame(maxWidth: 1_040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .bottomTrailing) {
            if isRefreshing {
                ProgressView().controlSize(.small).padding(10)
            }
        }
    }

    private func needsYouCard<Actions: View>(
        title: String,
        detail: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        // MacActivity: text (flex 1 1 320px) beside compact buttons; the
        // buttons wrap below only when that does not fit. The text's ideal
        // width is its 320pt basis so ViewThatFits does not measure the
        // whole sentence on one line.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                needsYouText(title: title, detail: detail)
                    .frame(minWidth: 320, idealWidth: 320, maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 8) { actions() }.fixedSize()
            }
            VStack(alignment: .leading, spacing: 12) {
                needsYouText(title: title, detail: detail)
                HStack(spacing: 8) { actions() }.fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MacBrand.attentionBorder, lineWidth: 1)
        }
    }

    private func needsYouText(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Circle()
                .fill(MacBrand.attentionIndicator)
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Geist.label(.body).weight(.semibold))
                    .foregroundStyle(Geist.text)
                Text(detail)
                    .font(Geist.body(.callout))
                    .foregroundStyle(Geist.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func busyCard(_ entry: CaptureFileBusyEntry) -> some View {
        let route = busyRouteName(entry)
        let items = entry.markdown.components(separatedBy: "\n").filter {
            let line = $0.trimmingCharacters(in: .whitespaces)
            return line.hasPrefix("- ") || line.hasPrefix("* ")
        }.count
        var meta = [route, entry.firstDetectedAt.formatted(date: .omitted, time: .shortened)]
        if items > 1 { meta.append(String(localized: "\(items) items")) }
        let detail = meta.compactMap { $0 }.joined(separator: " · ") + ". "
            + String(localized: "Vox.md waits rather than overwrite. It retries automatically every minute.")
        return needsYouCard(title: entry.reason.headline(fileName: entry.fileName), detail: detail) {
            Button("Retry now") { Task { await retryBusy(entry.requestID) } }
                .buttonStyle(GeistButtonStyle(variant: .primary, size: .small))
            Button("Write as new note") {
                CaptureFileBusyMonitor.shared.requestNewNote(for: entry.requestID)
                Task { await retryBusy(entry.requestID) }
            }
            .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
            Button("Copy Markdown") { copyToPasteboard(entry.markdown) }
                .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
        }
    }

    private func busyRouteName(_ entry: CaptureFileBusyEntry) -> String? {
        if let record = viewModel.historyRecords.first(where: { $0.requestID == entry.requestID }) {
            return record.voxName ?? record.destinationName
        }
        if let job = queue.actionableJobs.first(where: { $0.id == entry.requestID }) {
            return job.activityTitle
        }
        if entry.requestID == viewModel.draft.requestID {
            return viewModel.selectedVoxProfile.map(MacRouteCatalog.displayName)
        }
        return nil
    }

    private func failedJobCard(_ job: RecordingJob) -> some View {
        let detail = [
            job.createdAt.formatted(date: .omitted, time: .shortened),
            job.duration.activityDuration,
            job.statusMessage,
        ].compactMap { $0 }.joined(separator: " · ")
        return needsYouCard(title: String(localized: "\(job.activityTitle) could not finish"), detail: detail) {
            recordingPrimaryAction(for: job)
                .buttonStyle(GeistButtonStyle(variant: .primary, size: .small))
            if let transcript = job.transcriptText, !transcript.isEmpty {
                Button("Copy Markdown") { copyToPasteboard(transcript) }
                    .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
            }
            Button("Details…") { showDetail(.recording(job.id)) }
                .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
        }
    }

    private func readyJobCard(_ job: RecordingJob) -> some View {
        needsYouCard(
            title: String(localized: "\(job.activityTitle) is ready to copy"),
            detail: String(localized: "Deferred transcripts wait here so they never overwrite your clipboard later.")
        ) {
            if let transcript = job.transcriptText, !transcript.isEmpty {
                Button("Copy Transcript") {
                    if copyToPasteboard(transcript) {
                        Task { await queue.acknowledgeCopiedResult(job) }
                    }
                }
                .buttonStyle(GeistButtonStyle(variant: .primary, size: .small))
            }
            Button("Details…") { showDetail(.recording(job.id)) }
                .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
        }
    }

    private var failedInboxCard: some View {
        let count = viewModel.failedInboxCount
        let reasons = Set(viewModel.historyRecords
            .filter { $0.outcome == .failed && busyStore.entry(for: $0.requestID) == nil }
            .prefix(5)
            .compactMap { $0.failureCategory?.displayName })
        let detail = (reasons.isEmpty ? "" : reasons.sorted().joined(separator: " · ") + ". ")
            + String(localized: "Queued captures stay safe on this Mac and retry automatically.")
        return needsYouCard(
            title: count == 1
                ? String(localized: "1 capture could not be delivered")
                : String(localized: "\(count) captures could not be delivered"),
            detail: detail
        ) {
            Button("Retry now") { Task { await viewModel.retryFailedInbox() } }
                .buttonStyle(GeistButtonStyle(variant: .primary, size: .small))
            Button("Details…") { showDetail(.failedInbox) }
                .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
        }
    }

    /// One failed inbox request: its route, when it was captured and why it
    /// failed, with the Markdown it would have written ready to copy.
    private func failedInboxEntryCard(_ entry: CaptureFailedInboxEntry) -> some View {
        let record = viewModel.historyRecords.first {
            $0.requestID == entry.requestID && $0.outcome == .failed
        }
        let reason: String? = {
            if let failure = record?.failureReason, failure.kind == .headingNotFound,
               let heading = failure.headingMarkdown {
                return String(localized: "Heading not found: \(heading)")
            }
            return record?.failureCategory?.displayName
        }()
        let detail = [
            entry.createdAt.formatted(date: .omitted, time: .shortened),
            reason,
        ].compactMap { $0 }.joined(separator: " · ") + ". "
            + String(localized: "Queued captures stay safe on this Mac and retry automatically.")
        let title = entry.routeName.map { String(localized: "\($0) could not be delivered") }
            ?? String(localized: "A capture could not be delivered")
        return needsYouCard(title: title, detail: detail) {
            Button("Retry now") { Task { await viewModel.retryFailedInbox() } }
                .buttonStyle(GeistButtonStyle(variant: .primary, size: .small))
            if let markdown = entry.markdown, !markdown.isEmpty {
                Button("Copy Markdown") { copyToPasteboard(markdown) }
                    .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
            }
            Button("Details…") {
                if let record {
                    showDetail(.capture(record.requestID))
                } else {
                    showDetail(.failedInbox)
                }
            }
            .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
        }
    }

    private func reloadFailedInboxEntries() async {
        failedInboxEntries = viewModel.failedInboxCount > 0
            ? await viewModel.failedInboxEntries()
            : []
    }

    private func inFlightRow(_ job: RecordingJob) -> some View {
        let isActive = job.id == queue.activeJobID
        let fraction = isActive ? queue.transcriptionProgress?.exactFractionCompleted : nil
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(inFlightTitle(job))
                    .font(Geist.label(.callout).weight(.semibold))
                    .lineLimit(1)
                Text(inFlightSubtitle(job, isActive: isActive))
                    .font(Geist.body(.footnote))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ProgressView(value: fraction ?? (job.phase == .finalizing ? 0.95 : (isActive ? nil : 0.1)))
                .progressViewStyle(.linear)
                .tint(MacBrand.accent)
                .frame(maxWidth: 240)
                .accessibilityLabel(inFlightTitle(job))
            Text(verbatim: eta(for: job, fraction: fraction))
                .font(Geist.mono(size: 12, relativeTo: .caption))
                .foregroundStyle(Geist.muted)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture { showDetail(.recording(job.id)) }
        .contextMenu { contextMenu(for: .recording(job)) }
    }

    private func inFlightTitle(_ job: RecordingJob) -> String {
        if job.captureSource == .watch { return String(localized: "From Apple Watch") }
        if let name = job.originalFilename, !name.isEmpty {
            return "\(name) · \(job.duration.activityDuration)"
        }
        return "\(job.activityTitle) · \(job.duration.activityDuration)"
    }

    private func inFlightSubtitle(_ job: RecordingJob, isActive: Bool) -> String {
        let model = WhisperModelInfo.availableModels.first(where: { $0.id == job.modelID })?.name
            ?? (job.modelID == TranscriptionBackendID.automatic ? String(localized: "Automatic") : job.modelID)
        switch job.phase {
        case .processing:
            return job.activityTitle + " · " + String(localized: "transcribing with \(model)")
        case .finalizing:
            return job.activityTitle + " · " + String(localized: "writing to the vault")
        default:
            if job.captureSource == .watch {
                return job.activityTitle + " · " + String(localized: "waiting to transcribe on this Mac")
            }
            return job.activityTitle + " · " + (isActive ? String(localized: "starting") : String(localized: "queued"))
        }
    }

    private func eta(for job: RecordingJob, fraction: Double?) -> String {
        switch job.phase {
        case .queued: return String(localized: "queued")
        case .finalizing: return String(localized: "saving")
        default: break
        }
        guard let fraction, fraction > 0.02, let start = progressStarts[job.id], fraction > start.fraction else {
            return "…"
        }
        let elapsed = Date().timeIntervalSince(start.date)
        let remaining = elapsed / (fraction - start.fraction) * (1 - fraction)
        if remaining < 60 { return String(localized: "<1 min") }
        return String(localized: "~\(Int((remaining / 60).rounded())) min")
    }

    private var deliveredSection: some View {
        let calendar = Calendar.current
        let today = deliveredRecords.filter { calendar.isDateInToday($0.deliveredAt ?? $0.createdAt) }
        let earlier = Array(deliveredRecords.filter { !calendar.isDateInToday($0.deliveredAt ?? $0.createdAt) }.prefix(30))
        return VStack(alignment: .leading, spacing: 14) {
            MacSignalSectionHeader("Delivered")
                .padding(.top, 10)
            if !today.isEmpty {
                deliveredTable(today, showsDay: false)
            }
            if !earlier.isEmpty {
                MacSignalSectionHeader("Earlier")
                deliveredTable(earlier, showsDay: true)
            }
        }
    }

    private func deliveredTable(_ records: [CaptureHistoryRecord], showsDay: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(records.enumerated()), id: \.element.requestID) { index, record in
                if index > 0 { Rectangle().fill(Geist.Palette.gray200).frame(height: 1) }
                HStack(spacing: 8) {
                    Text(verbatim: "✓")
                        .foregroundStyle(MacBrand.success)
                        .frame(width: 20, alignment: .leading)
                    Text(record.voxName ?? record.destinationName)
                        .font(Geist.label(.callout))
                        .lineLimit(1)
                        .frame(minWidth: 120, alignment: .leading)
                    Text(verbatim: deliveredDestination(record))
                        .font(Geist.mono(size: 12, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(verbatim: showsDay
                         ? (record.deliveredAt ?? record.createdAt).formatted(.dateTime.month(.abbreviated).day().hour().minute())
                         : (record.deliveredAt ?? record.createdAt).formatted(date: .omitted, time: .shortened))
                        .font(Geist.mono(size: 12, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
                .onTapGesture { openDelivered(record) }
                .contextMenu { deliveredContextMenu(record) }
                .accessibilityElement(children: .combine)
            }
        }
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Geist.border, lineWidth: 1) }
    }

    private func deliveredDestination(_ record: CaptureHistoryRecord) -> String {
        let path = record.relativeNotePath ?? record.destinationName
        if let heading = record.placementHeading, !heading.isEmpty {
            return "\(path) · ## \(heading)"
        }
        if let destination = viewModel.destinations.first(where: { $0.id == record.destinationID }),
           let heading = MacRouteCatalog.headingMarkdown(for: destination) {
            return "\(path) · \(heading)"
        }
        return path
    }

    private func openDelivered(_ record: CaptureHistoryRecord) {
        if transcriptStore.transcripts.contains(where: { $0.id == record.requestID }) {
            showDetail(.transcript(record.requestID))
        } else {
            showDetail(.capture(record.requestID))
        }
    }

    @ViewBuilder
    private func deliveredContextMenu(_ record: CaptureHistoryRecord) -> some View {
        Button("Show Details") { openDelivered(record) }
        if record.relativeNotePath != nil {
            Button("Reveal Note in Finder", systemImage: "folder") { reveal(record) }
        }
        Divider()
        Button("Delete Capture Record", systemImage: "trash", role: .destructive) {
            pendingDeletion = .capture(record)
        }
    }

    private func showDetail(_ id: MacActivitySelection) {
        selection = id
        showsDetail = true
    }

    private func retryBusy(_ requestID: UUID) async {
        if requestID == viewModel.draft.requestID {
            if !viewModel.isSubmitting { await viewModel.submit() }
            return
        }
        if let job = queue.actionableJobs.first(where: { $0.id == requestID }) {
            await retry(job)
            return
        }
        await viewModel.retryFailedInbox()
        if viewModel.failedInboxCount == 0 {
            // Nothing is queued for this entry any more (delivered or removed).
            CaptureFileBusyMonitor.shared.clear(requestID: requestID)
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
                Section {
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
                } header: {
                    MacSignalSectionHeader("Now")
                }
            }

            if !recentItems.isEmpty {
                Section {
                    ForEach(recentItems) { item in
                        MacActivityRow(item: item)
                            .tag(item.id)
                            .contextMenu { contextMenu(for: item) }
                    }
                } header: {
                    MacSignalSectionHeader("Recent")
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(Geist.Palette.gray100)
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
            Menu("Retry with Route", systemImage: "arrow.clockwise") {
                if recoveryPresets.isEmpty {
                    Text("No Enabled Routes")
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
            String(localized: "Delete this recording?")
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
            String(localized: "The audio and any transcript are removed from this Mac. This can’t be undone.")
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
        if needsAttention { return MacBrand.attention }
        switch self {
        case .recording(let job) where job.phase == .processing || job.phase == .finalizing:
            return MacBrand.orange
        case .recording(let job) where job.phase == .completed:
            return MacBrand.success
        case .transcript(_, let delivery) where delivery?.outcome == .delivered:
            return MacBrand.success
        case .capture(let delivery) where delivery.outcome == .delivered:
            return MacBrand.success
        default:
            return Geist.muted
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
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(item.statusColor)
                .frame(width: 28, height: 28)
                .background(Geist.well, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title)
                        .font(Geist.label())
                        .foregroundStyle(Geist.text)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if item.date != .distantFuture {
                        Text(item.date, format: .dateTime.hour().minute())
                            .font(Geist.mono(size: 12, relativeTo: .caption))
                            .foregroundStyle(Geist.muted)
                    }
                }

                HStack(spacing: 6) {
                    Text(item.subtitle)
                        .font(Geist.caption())
                        .foregroundStyle(
                            item.needsAttention ? MacBrand.attention : Geist.muted
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
        .background(Geist.bg)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: job.activitySymbolName)
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(
                    job.phase == .failed ? MacBrand.attention : MacBrand.orange
                )
                .frame(width: 64, height: 64)
                .background(Geist.well, in: RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(job.activityTitle)
                    .font(Geist.display(28))
                    .textSelection(.enabled)
                Text("\(job.createdAt.formatted(date: .abbreviated, time: .shortened))  ·  \(job.duration.activityDuration)")
                    .font(Geist.mono(size: 12, relativeTo: .subheadline))
                    .foregroundStyle(Geist.muted)
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
                        job.phase == .failed ? MacBrand.attention : Color.primary
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
                        job.phase == .failed ? MacBrand.attention : Color.secondary
                    )
            }
        }
        .macSignalCard(
            padding: 16,
            border: job.phase == .failed ? MacBrand.attentionBorder : Geist.border
        )
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
            Menu("Retry with Route", systemImage: "arrow.clockwise") {
                if recoveryPresets.isEmpty {
                    Text("No Enabled Routes")
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
                        .background(Geist.well, in: RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(transcript.activityTitle)
                            .font(Geist.display(28))
                            .textSelection(.enabled)
                        Text("\(transcript.date.formatted(date: .long, time: .shortened))  ·  \(transcript.duration.activityDuration)")
                            .font(Geist.mono(size: 12, relativeTo: .subheadline))
                            .foregroundStyle(Geist.muted)
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
        .background(Geist.bg)
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
                                ? MacBrand.success
                                : MacBrand.attention
                        )
                        .frame(width: 64, height: 64)
                        .background(Geist.well, in: RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.destinationName)
                            .font(Geist.display(28))
                            .textSelection(.enabled)
                        Label(
                            record.outcome == .delivered ? "Delivered" : "Delivery Failed",
                            systemImage: record.outcome == .delivered
                                ? "checkmark.circle.fill"
                                : "exclamationmark.triangle.fill"
                        )
                        .font(Geist.label())
                        .foregroundStyle(
                            record.outcome == .delivered
                                ? MacBrand.success
                                : MacBrand.attention
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
        .background(Geist.bg)
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
                            : MacBrand.attention
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
                    LabeledContent("Route", value: preset)
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
                            .foregroundStyle(MacBrand.attention)
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
                .foregroundStyle(MacBrand.attention)
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
