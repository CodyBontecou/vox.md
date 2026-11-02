import SwiftUI
import UniformTypeIdentifiers
import VoxboardShared

/// The single iOS Activity feed: what needs you, what is in flight (queued
/// recordings and Apple Watch transcriptions), and what was delivered today.
/// Activity keeps routes and status only, never captured content.
struct ActivityFeedView: View {
    @Bindable var viewModel: QuickCaptureViewModel
    @Bindable var persistentRecorder: PersistentRecorder
    /// Starts a new capture. Defaults to dismissing back to Capture.
    var onNewCapture: (() -> Void)?
    /// False when Activity is a sidebar section rather than a pushed screen.
    var showsBackButton = true

    @Environment(WatchRecordingPipeline.self) private var watchPipeline
    @Environment(TranscriptStore.self) private var transcriptStore
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss
    @State private var filter: ActivitySignalFilter = .all
    @State private var problems: [CaptureDeliveryProblem] = []
    @State private var reviewing: CaptureDeliveryProblem?
    @State private var fixingAccess: CaptureDeliveryProblem?
    @State private var showsFolderPicker = false
    @State private var errorMessage: String?
    @State private var showsPlans = false
    @State private var discardingWatchItem: WatchRecordingInboxItem?

    private var queue: RecordingJobQueue? { persistentRecorder.recordingQueue }
    private var captureRootURL: URL? { AppConstants.captureDirectoryURL }

    var body: some View {
        NavigationStack {
            ZStack {
                Geist.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            Text("Activity")
                                .font(Geist.display(34))
                                .foregroundStyle(Geist.text)
                                .accessibilityAddTraits(.isHeader)
                                .padding(.horizontal, 4)
                                .padding(.top, Geist.Spacing.three)

                            if isAllCaughtUp {
                                allCaughtUp
                            } else {
                                filterControl
                                    .padding(.top, 6)
                                    .padding(.bottom, 6)
                                feed
                            }

                            moreLinks
                                .padding(.top, Geist.Spacing.four)
                        }
                        .padding(.horizontal, Geist.Spacing.four)
                        .padding(.bottom, Geist.Spacing.four)
                    }
                    .refreshable { await reload() }
                    if isAllCaughtUp {
                        // EmptyStates board A: the action sits at the bottom.
                        newCaptureButton
                            .padding(.horizontal, Geist.Spacing.four + 4)
                            .padding(.top, Geist.Spacing.three)
                            .padding(.bottom, Geist.Spacing.two)
                    } else {
                        privacyFooter
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task { await reload() }
            .task { await queue?.monitorDurableChanges() }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(5))
                    await reloadProblems()
                }
            }
            .sheet(item: $reviewing) { problem in
                DeliveryRecoverySheet(problem: problem) { await deliverQueued() }
            }
            .confirmationDialog(
                "Discard this recording?",
                isPresented: Binding(
                    get: { discardingWatchItem != nil },
                    set: { if !$0 { discardingWatchItem = nil } }
                ),
                titleVisibility: .visible,
                presenting: discardingWatchItem
            ) { item in
                Button("Discard", role: .destructive) { watchPipeline.discard(item) }
            }
            .sheet(isPresented: $showsPlans) {
                PaywallView(context: .captureLimit)
                    .environment(usageTracker)
                    .environment(storeManager)
            }
            .fileImporter(
                isPresented: $showsFolderPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                handleFolderPick(result)
            }
            .alert("Activity", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: Data

    private func reload() async {
        await queue?.refresh(recoverInterrupted: true)
        watchPipeline.refresh()
        await viewModel.refreshHistory()
        await reloadProblems()
    }

    private func reloadProblems() async {
        guard let captureRootURL else { return }
        let watchRequestIDs = Set(watchPipeline.items.map(\.requestID))
        problems = await CaptureInboxRecovery.problems(captureRootURL: captureRootURL)
            .filter { !watchRequestIDs.contains($0.requestID) }
    }

    /// Trial or subscription ended: Activity stays readable, and Review,
    /// Copy and Discard stay available, but retries, route fixes and new
    /// deliveries are locked and open the paywall.
    private var isReadOnly: Bool { usageTracker.isLibraryReadOnly }

    private func requirePaidAccess(_ action: () -> Void) {
        usageTracker.requirePaidAccess(otherwise: { showsPlans = true }, action)
    }

    private func deliverQueued() async {
        await viewModel.processPendingInbox()
        await viewModel.refreshHistory()
        await reloadProblems()
    }

    private var failedJobs: [RecordingJob] {
        queue?.actionableJobs.filter { $0.phase == .failed } ?? []
    }

    private var inFlightJobs: [RecordingJob] {
        queue?.actionableJobs.filter {
            $0.phase == .queued || $0.phase == .processing || $0.phase == .finalizing
        } ?? []
    }

    private var failedWatchItems: [WatchRecordingInboxItem] { watchPipeline.failedItems }

    private var inFlightWatchItems: [WatchRecordingInboxItem] {
        watchPipeline.activeItems.filter { $0.phase != .failed }
    }

    private var needsYouCount: Int {
        problems.count + failedJobs.count + failedWatchItems.count
    }

    private var inFlightCount: Int { inFlightJobs.count + inFlightWatchItems.count }

    private var deliveredToday: [CaptureHistoryRecord] {
        viewModel.historyRecords.filter {
            $0.outcome == .delivered && Calendar.current.isDateInToday($0.deliveredAt ?? $0.createdAt)
        }
    }

    private var isAllCaughtUp: Bool {
        needsYouCount == 0 && inFlightCount == 0 && deliveredToday.isEmpty
    }

    // MARK: Header

    private var header: some View {
        HStack {
            if showsBackButton {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(SignalCircleButtonStyle())
                    .accessibilityLabel("Back to capture")
            }
            Spacer()
            // As a sidebar section, Library sits in the sidebar under
            // Activity (iPad board), so the header skips its own link.
            if showsBackButton {
                NavigationLink {
                    HistoryView(viewModel: viewModel, embedsInNavigationStack: false)
                        .environment(transcriptStore)
                } label: {
                    Text("Library")
                        .font(Geist.label(.subheadline))
                        .foregroundStyle(Geist.text)
                        .padding(.horizontal, 14)
                        .frame(height: Geist.ControlHeight.medium)
                        .background(Geist.card, in: Capsule())
                        .overlay(Capsule().stroke(Geist.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens every capture on this iPhone")
            }
        }
        .padding(.horizontal, Geist.Spacing.four + 4)
        .padding(.vertical, Geist.Spacing.two)
    }

    private var filterControl: some View {
        ActivitySignalSegmentedControl(
            selection: $filter,
            segments: [
                (.all, String(localized: "All")),
                (
                    .needsAttention,
                    needsYouCount == 0
                        ? String(localized: "Needs you")
                        : String(localized: "Needs you · \(needsYouCount)")
                ),
                (.inFlight, String(localized: "In flight")),
            ]
        )
        .accessibilityLabel("Filter")
    }

    // MARK: Feed

    @ViewBuilder
    private var feed: some View {
        let showsNeeds = filter != .inFlight
        let showsFlight = filter != .needsAttention

        if showsNeeds {
            ForEach(problems) { problem in problemCard(problem) }
            ForEach(failedWatchItems) { item in watchFailureCard(item) }
            if let queue {
                ForEach(failedJobs) { job in
                    RecordingQueueJobCard(job: job, queue: queue, recoveryPresets: CapturePresetStore.loadFlows())
                }
            }
        }
        if showsFlight {
            ForEach(inFlightWatchItems) { item in watchInFlightCard(item) }
            if let queue {
                ForEach(inFlightJobs) { job in
                    RecordingQueueJobCard(job: job, queue: queue, recoveryPresets: CapturePresetStore.loadFlows())
                }
            }
        }

        if filter == .needsAttention && needsYouCount == 0 {
            filteredEmpty(String(localized: "Nothing needs you right now."))
        } else if filter == .inFlight && inFlightCount == 0 {
            filteredEmpty(String(localized: "Nothing is in flight right now."))
        }

        if filter == .all && !deliveredToday.isEmpty {
            Text("DELIVERED TODAY")
                .font(Geist.mono(size: 11, relativeTo: .caption))
                .tracking(0.66)
                .foregroundStyle(Geist.muted)
                .padding(.horizontal, 4)
                .padding(.top, 10)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(Array(deliveredToday.enumerated()), id: \.element.id) { index, record in
                    if index > 0 { GeistDivider() }
                    deliveredRow(record)
                }
            }
            .padding(.horizontal, 14)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
        }
    }

    private func filteredEmpty(_ text: String) -> some View {
        Text(text)
            .font(Geist.body(.subheadline))
            .foregroundStyle(Geist.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Geist.Spacing.six)
    }

    private func isVaultProblem(_ problem: CaptureDeliveryProblem) -> Bool {
        switch problem.failureReason?.kind {
        case .vaultUnreachable?, .permissionDenied?: return true
        case .headingNotFound?: return false
        default:
            return problem.failureCategory == .destinationUnavailable
                || problem.failureCategory == .permissionDenied
        }
    }

    private func problemCard(_ problem: CaptureDeliveryProblem) -> some View {
        let vault = isVaultProblem(problem)
        let time = problem.createdAt.formatted(.dateTime.hour().minute())
        let title: String
        let detail: String
        if vault {
            title = String(localized: "Can’t reach your vault")
            detail = String(localized: "\(problem.displayRouteName) · \(time) · saved safely on this iPhone. Re-grant folder access to deliver.")
        } else if problem.failureReason?.kind == .headingNotFound, let heading = problem.failureReason?.headingMarkdown {
            title = String(localized: "Heading not found")
            detail = String(localized: "\(problem.displayRouteName) · \(time) · \(heading) is missing. Saved safely on this iPhone.")
        } else {
            title = String(localized: "Couldn’t deliver")
            detail = String(localized: "\(problem.displayRouteName) · \(time) · \(problem.failureCategory?.displayName ?? String(localized: "Delivery failed")). Saved safely on this iPhone.")
        }
        return VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            HStack(alignment: .top, spacing: Geist.Spacing.three) {
                ActivitySignalDot(color: Geist.warning).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Geist.heading(.callout))
                        .foregroundStyle(Geist.text)
                    Text(detail)
                        .font(Geist.body(.subheadline))
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Geist.Spacing.two) {
                if vault {
                    Button {
                        requirePaidAccess {
                            fixingAccess = problem
                            showsFolderPicker = true
                        }
                    } label: {
                        PaidAccessLabel("Fix access", isLocked: isReadOnly)
                    }
                    .buttonStyle(ActivitySignalPillButtonStyle(kind: isReadOnly ? .secondary : .primary))
                } else {
                    // Review stays available read-only: the sheet keeps Copy
                    // Markdown and Discard, and locks its delivery actions.
                    Button("Review") { reviewing = problem }
                        .buttonStyle(ActivitySignalPillButtonStyle(kind: .primary))
                }
                Button {
                    requirePaidAccess { retry(problem) }
                } label: {
                    PaidAccessLabel("Retry", isLocked: isReadOnly)
                }
                .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
                if vault {
                    Button("More", systemImage: "ellipsis") { reviewing = problem }
                        .labelStyle(.iconOnly)
                        .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
                        .accessibilityLabel("More options")
                }
            }
            .padding(.leading, 22)
        }
        .activitySignalCard(needsAttention: true)
    }

    private func watchFailureCard(_ item: WatchRecordingInboxItem) -> some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            HStack(alignment: .top, spacing: Geist.Spacing.three) {
                ActivitySignalDot(color: Geist.warning).padding(.top, 6)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(item.watchStatusTitle)
                            .font(Geist.heading(.callout))
                            .foregroundStyle(Geist.text)
                        Spacer()
                        Text(item.createdAt, format: .dateTime.hour().minute())
                            .font(Geist.mono(size: 11.5, relativeTo: .caption))
                            .foregroundStyle(Geist.muted)
                    }
                    Text(item.watchStatusSubtitle)
                        .font(Geist.body(.subheadline))
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Geist.Spacing.two) {
                Button {
                    requirePaidAccess { watchPipeline.retry(item) }
                } label: {
                    PaidAccessLabel("Retry", isLocked: isReadOnly)
                }
                .buttonStyle(ActivitySignalPillButtonStyle(kind: isReadOnly ? .secondary : .primary))
                if item.canCaptureRecordingWithoutTranscript {
                    Button {
                        requirePaidAccess { watchPipeline.captureRecordingWithoutTranscript(item) }
                    } label: {
                        PaidAccessLabel("Save audio only", isLocked: isReadOnly)
                    }
                    .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
                }
                Button("Discard", role: .destructive) { discardingWatchItem = item }
                    .buttonStyle(ActivitySignalPillButtonStyle(kind: .destructive))
            }
            .padding(.leading, 22)
        }
        .activitySignalCard(needsAttention: true)
    }

    private func watchInFlightCard(_ item: WatchRecordingInboxItem) -> some View {
        let fraction = item.phase == .transcribing
            ? persistentRecorder.transcriptionProgress?.exactFractionCompleted
            : nil
        let subtitle: String = {
            switch item.phase {
            case .queued: return String(localized: "\(item.displayPresetName) · waiting on iPhone")
            case .transcribing: return String(localized: "\(item.displayPresetName) · transcribing on iPhone")
            case .delivering: return String(localized: "\(item.displayPresetName) · delivering")
            default: return item.watchStatusSubtitle
            }
        }()
        return HStack(alignment: .top, spacing: Geist.Spacing.three) {
            ActivitySignalDot(color: Geist.accent).padding(.top, 6)
            VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                HStack(alignment: .firstTextBaseline) {
                    Text("From Apple Watch")
                        .font(Geist.heading(.callout))
                        .foregroundStyle(Geist.text)
                    Spacer()
                    Text(item.createdAt, format: .dateTime.hour().minute())
                        .font(Geist.mono(size: 11.5, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                }
                Text(subtitle)
                    .font(Geist.body(.subheadline))
                    .foregroundStyle(Geist.muted)
                if let fraction {
                    ActivitySignalProgressBar(fraction: fraction)
                        .accessibilityLabel("Transcribing")
                        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
                } else if item.phase == .transcribing || item.phase == .delivering {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(Geist.accent)
                        .accessibilityLabel(subtitle)
                }
                if item.isWaitingForTranscriptionUpgrade {
                    Text("Waiting for Vox.md Unlimited to transcribe.")
                        .font(Geist.caption(.footnote))
                        .foregroundStyle(Geist.Palette.amber900)
                }
            }
        }
        .activitySignalCard()
    }

    private func deliveredRow(_ record: CaptureHistoryRecord) -> some View {
        HStack(spacing: Geist.Spacing.three) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Geist.success)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: record.voxName ?? record.destinationName)
                    .font(Geist.body(.subheadline).weight(.medium))
                    .foregroundStyle(Geist.text)
                Text(verbatim: deliveredDestination(record))
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Geist.Spacing.two)
            Text(record.deliveredAt ?? record.createdAt, format: .dateTime.hour().minute())
                .font(Geist.mono(size: 11.5, relativeTo: .caption))
                .foregroundStyle(Geist.muted)
        }
        .padding(.vertical, Geist.Spacing.three)
        .accessibilityElement(children: .combine)
    }

    private func deliveredDestination(_ record: CaptureHistoryRecord) -> String {
        let path = record.relativeNotePath ?? record.destinationName
        if let heading = record.placementHeading {
            return "\(path) · ## \(heading)"
        }
        return path
    }

    // MARK: Empty, links, footer

    private var allCaughtUp: some View {
        VStack(spacing: Geist.Spacing.six) {
            ActivitySignalEmptyState(
                systemImage: "checkmark",
                tint: Geist.success,
                title: "All caught up",
                message: "Nothing waiting. Captures from the keyboard, Watch and Mac show up here while they’re on the way to your vault."
            )
            .padding(.top, Geist.Spacing.sixteen * 2)
        }
        .frame(maxWidth: .infinity)
    }

    private var newCaptureButton: some View {
        Button("New capture") {
            if let onNewCapture { onNewCapture() } else { dismiss() }
        }
        .buttonStyle(GeistButtonStyle(variant: .primary))
    }

    @ViewBuilder
    private var moreLinks: some View {
        if let queue {
            NavigationLink {
                RecordingQueueView(queue: queue, recoveryPresets: CapturePresetStore.loadFlows())
            } label: {
                HStack {
                    Label("Recording queue & recovery", systemImage: "waveform")
                        .font(Geist.label(.subheadline))
                        .foregroundStyle(Geist.text)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Geist.faint)
                }
                .activitySignalCard()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Retention, processing defaults and finished recordings")
        }
    }

    private var privacyFooter: some View {
        HStack(alignment: .top, spacing: Geist.Spacing.two) {
            Image(systemName: "lock")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Geist.muted)
                .padding(.top, 2)
                .accessibilityHidden(true)
            Text("Activity keeps routes and status only — never your words, links or locations.")
                .font(Geist.body(.footnote))
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Geist.Spacing.six)
        .padding(.top, 14)
        .padding(.bottom, Geist.Spacing.two)
        .background(Geist.bg)
        .accessibilityElement(children: .combine)
    }

    // MARK: Actions

    private func retry(_ problem: CaptureDeliveryProblem) {
        guard !isReadOnly else {
            showsPlans = true
            return
        }
        guard let captureRootURL else { return }
        Task {
            do {
                try await CaptureInboxRecovery.retry(requestID: problem.requestID, captureRootURL: captureRootURL)
                await deliverQueued()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func handleFolderPick(_ result: Result<[URL], Error>) {
        guard let problem = fixingAccess, let captureRootURL else { return }
        fixingAccess = nil
        guard !isReadOnly else {
            showsPlans = true
            return
        }
        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
            do {
                let bookmark = try url.bookmarkData(
                    options: .minimalBookmark,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                Task {
                    do {
                        try await CaptureInboxRecovery.replaceFolderAccess(
                            destinationID: problem.destinationID,
                            bookmark: bookmark,
                            rootName: url.lastPathComponent,
                            captureRootURL: captureRootURL
                        )
                        await viewModel.refreshLibrary()
                        await deliverQueued()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
