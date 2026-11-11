import SwiftUI
import VoxboardShared

#if os(macOS)
import AppKit
#else
import UIKit
#endif

private struct RecordingQueuePreferencesView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isExpanded = false
    @State private var retentionMode: SourceAudioRetentionMode
    @State private var timedRetentionDays: Int
    @State private var processingPolicy: RecordingJobProcessingPolicy

    init() {
        let configuration = RecordingQueuePreferences.load()
        _retentionMode = State(initialValue: configuration.sourceAudioRetention.mode)
        let interval = configuration.sourceAudioRetention.retentionInterval
            ?? SourceAudioRetentionPolicy.defaultTimedRetention
        _timedRetentionDays = State(initialValue: max(1, Int((interval / 86_400).rounded())))
        _processingPolicy = State(initialValue: configuration.processingPolicy)
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: Geist.Spacing.four) {
                GeistDivider()

                preferenceField(
                    title: "After Recording",
                    detail: processingDetail
                ) {
                    Menu {
                        Button("Immediately") {
                            processingPolicy = .immediate
                        }
                        Button("When Idle") {
                            processingPolicy = .whenIdle
                        }
                        Button("Manually") {
                            processingPolicy = .manual
                        }
                    } label: {
                        queueMenuLabel(processingSummary)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("After Recording")
                    .accessibilityValue(processingSummary)
                }

                GeistDivider()

                preferenceField(
                    title: "Original Audio",
                    detail: String(localized: "Failed recordings stay here until you retry or delete them.")
                ) {
                    Menu {
                        Button("After Processing") {
                            retentionMode = .deleteAfterSuccess
                        }
                        Button("For a Period") {
                            retentionMode = .timed
                        }
                        Button("Permanently") {
                            retentionMode = .permanent
                        }
                    } label: {
                        queueMenuLabel(retentionMenuLabel)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Original Audio")
                    .accessibilityValue(retentionMenuLabel)

                    if retentionMode == .timed {
                        Stepper(value: $timedRetentionDays, in: 1...365) {
                            Text("Keep for \(timedRetentionDays) days")
                                .font(Geist.label())
                                .foregroundStyle(Geist.text)
                        }
                        .tint(Geist.focus)
                        .accessibilityLabel("Original Audio Retention")
                        .accessibilityValue("\(timedRetentionDays) days")
                    }
                }
            }
            .padding(.top, Geist.Spacing.four)
        } label: {
            VStack(alignment: .leading, spacing: Geist.Spacing.one) {
                Text("Queue Settings")
                    .font(Geist.heading(.headline))
                    .foregroundStyle(Geist.text)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(configurationSummary)
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                }
            }
        }
        .tint(Geist.text)
        .geistCard(padding: Geist.Spacing.four)
        .onChange(of: retentionMode) { _, _ in save() }
        .onChange(of: timedRetentionDays) { _, _ in save() }
        .onChange(of: processingPolicy) { _, _ in save() }
    }

    private var configurationSummary: String {
        String(
            localized: "\(processingSummary) · \(retentionSummary)"
        )
    }

    private var processingSummary: String {
        switch processingPolicy {
        case .immediate: return String(localized: "Immediately")
        case .whenIdle: return String(localized: "When Idle")
        case .manual: return String(localized: "Manually")
        }
    }

    private var retentionSummary: String {
        switch retentionMode {
        case .deleteAfterSuccess: return String(localized: "Delete Audio After Processing")
        case .timed: return String(localized: "Keep Audio for \(timedRetentionDays) Days")
        case .permanent: return String(localized: "Keep Audio Permanently")
        }
    }

    private var retentionMenuLabel: String {
        switch retentionMode {
        case .deleteAfterSuccess: return String(localized: "After Processing")
        case .timed: return String(localized: "For a Period")
        case .permanent: return String(localized: "Permanently")
        }
    }

    private func queueMenuLabel(_ title: String) -> some View {
        HStack(spacing: Geist.Spacing.two) {
            Text(title)
                .lineLimit(1)
            Spacer(minLength: Geist.Spacing.two)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(.caption, weight: .semibold))
                .accessibilityHidden(true)
        }
        .font(Geist.label())
        .foregroundStyle(Geist.text)
        .frame(
            maxWidth: .infinity,
            minHeight: Geist.ControlHeight.medium,
            alignment: .leading
        )
        .padding(.horizontal, Geist.Spacing.three)
        .background(Geist.Palette.background100)
        .overlay(
            RoundedRectangle(cornerRadius: Geist.Radius.small, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        )
        .clipShape(
            RoundedRectangle(cornerRadius: Geist.Radius.small, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private func preferenceField<Control: View>(
        title: LocalizedStringKey,
        detail: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.two) {
            Text(title)
                .font(Geist.label())
                .foregroundStyle(Geist.text)
            control()
            Text(detail)
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
        }
    }

    private var processingDetail: String {
        switch processingPolicy {
        case .immediate:
            return String(localized: "Recordings enter the durable queue and start as soon as the microphone is free.")
        case .whenIdle:
            #if os(macOS)
            return String(localized: "Queued recordings run while Vox.md is open and no recording is active.")
            #else
            return String(localized: "Queued recordings run when Vox.md is active and idle. iOS background execution is not guaranteed.")
            #endif
        case .manual:
            return String(localized: "Recordings remain queued until you choose Process Now.")
        }
    }

    private func save() {
        let retention: SourceAudioRetentionPolicy
        switch retentionMode {
        case .deleteAfterSuccess:
            retention = .deleteAfterSuccess
        case .timed:
            retention = .timed(TimeInterval(timedRetentionDays) * 86_400)
        case .permanent:
            retention = .permanent
        }
        RecordingQueuePreferences.save(RecordingQueueConfiguration(
            sourceAudioRetention: retention,
            processingPolicy: processingPolicy
        ))
    }
}

@MainActor
private final class RecordingQueueRetryCoordinator: @unchecked Sendable {
    let action: (RecordingJob, RecordingJobDelivery?) async -> Void

    init(action: @escaping (RecordingJob, RecordingJobDelivery?) async -> Void) {
        self.action = action
    }

    func retry(
        _ job: RecordingJob,
        delivery: RecordingJobDelivery? = nil
    ) async {
        await action(job, delivery)
    }
}

struct RecordingQueueView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var queue: RecordingJobQueue
    #if DEBUG
    @State private var runtimeValidationStatus: String?
    #endif
    private let retryCoordinator: RecordingQueueRetryCoordinator?
    private let recoveryPresets: [CapturePreset]

    init(
        queue: RecordingJobQueue,
        recoveryPresets: [CapturePreset] = [],
        retryOverride: (@MainActor (RecordingJob, RecordingJobDelivery?) async -> Void)? = nil
    ) {
        self.queue = queue
        self.recoveryPresets = recoveryPresets.filter(\.isEnabled)
        self.retryCoordinator = retryOverride.map(RecordingQueueRetryCoordinator.init(action:))
    }

    @State private var filter: ActivitySignalFilter = .all

    var body: some View {
        ZStack {
            Geist.bg.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if queue.actionableJobs.isEmpty {
                        emptyQueueView
                    } else {
                        filterControl
                            .padding(.bottom, 6)

                        if visibleOpenJobs.isEmpty && visibleCompletedJobs.isEmpty {
                            filteredEmptyView
                        }

                        ForEach(visibleOpenJobs) { job in
                            queueRow(job)
                        }

                        if !visibleCompletedJobs.isEmpty {
                            GeistSectionLabel(number: "", title: "Done")
                                .padding(.horizontal, 4)
                                .padding(.top, 10)
                            ForEach(visibleCompletedJobs) { job in
                                queueRow(job)
                            }
                        }
                    }

                    RecordingQueuePreferencesView()
                        .padding(.top, 14)
                }
                .frame(maxWidth: 1_200)
                .padding(.horizontal, Geist.Spacing.four)
                .padding(.vertical, Geist.Spacing.four)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Activity")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
        #endif
        .toolbar {
            if !queue.retryAllEligibleJobs.isEmpty {
                ToolbarItem {
                    Button("Retry All", systemImage: "arrow.clockwise") {
                        Task { await retryAllFailedJobs() }
                    }
                }
            }
        }
        .task {
            await queue.refresh(recoverInterrupted: true)
        }
        .task {
            await queue.monitorDurableChanges()
        }
        .refreshable {
            await queue.refresh(recoverInterrupted: true)
        }
        #if DEBUG
        .task {
            let processInfo = ProcessInfo.processInfo
            guard processInfo.arguments.contains("--runtime-queue-validation"),
                  processInfo.arguments.contains("--runtime-queue-activate-actions"),
                  let overridePath = processInfo.environment[
                    AppConstants.debugSharedContainerOverrideEnvironmentKey
                  ],
                  !overridePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let overrideURL = Optional(
                    URL(fileURLWithPath: overridePath, isDirectory: true)
                        .standardizedFileURL
                  ),
                  overrideURL.path.hasPrefix(
                    URL(
                        fileURLWithPath: "/tmp/VoxQueueRuntimeValidation",
                        isDirectory: true
                    ).standardizedFileURL.path + "/"
                  ),
                  AppConstants.sharedContainerURL?.standardizedFileURL.path
                    == overrideURL.path else { return }
            runtimeValidationStatus = await activateRuntimeValidationActions(
                includeExtendedActions: processInfo.arguments.contains(
                    "--runtime-queue-activate-extended-actions"
                )
            )
        }
        .accessibilityIdentifier("recording-queue-runtime-actions")
        .accessibilityLabel(runtimeValidationStatus ?? "Runtime queue actions pending")
        #endif
        .alert("Activity Error", isPresented: errorPresented) {
            Button("Dismiss Error") {}
        } message: {
            Text(queue.lastError ?? String(localized: "Unknown error"))
        }
    }

    private func queueRow(_ job: RecordingJob) -> some View {
        RecordingQueueRow(
            job: job,
            queue: queue,
            retryCoordinator: retryCoordinator,
            recoveryPresets: recoveryPresets
        )
        .activitySignalCard(needsAttention: job.phase == .failed)
    }

    private var needsAttentionJobs: [RecordingJob] {
        queue.actionableJobs.filter { $0.phase == .failed }
    }

    private var inFlightJobs: [RecordingJob] {
        queue.actionableJobs.filter {
            $0.phase == .queued || $0.phase == .processing || $0.phase == .finalizing
        }
    }

    /// Jobs that still need the queue: failures first (they need you), then
    /// work in flight, matching the Signal Activity ordering.
    private var visibleOpenJobs: [RecordingJob] {
        switch filter {
        case .all: return needsAttentionJobs + inFlightJobs
        case .needsAttention: return needsAttentionJobs
        case .inFlight: return inFlightJobs
        }
    }

    private var visibleCompletedJobs: [RecordingJob] {
        guard filter == .all else { return [] }
        return queue.actionableJobs.filter { $0.phase == .completed }
    }

    private var filterControl: some View {
        ActivitySignalSegmentedControl(
            selection: $filter,
            segments: [
                (.all, String(localized: "All")),
                (
                    .needsAttention,
                    needsAttentionJobs.isEmpty
                        ? String(localized: "Needs you")
                        : String(localized: "Needs you · \(needsAttentionJobs.count)")
                ),
                (.inFlight, String(localized: "In flight")),
            ]
        )
        .accessibilityLabel("Filter recordings")
    }

    private var filteredEmptyView: some View {
        Text(filter == .needsAttention
             ? String(localized: "Nothing needs you right now.")
             : String(localized: "Nothing is in flight right now."))
            .font(Geist.body(.subheadline))
            .foregroundStyle(Geist.muted)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, Geist.Spacing.six)
    }

    private var emptyQueueView: some View {
        ActivitySignalEmptyState(
            systemImage: "checkmark",
            tint: Geist.success,
            title: "All caught up",
            message: "Nothing waiting. Recordings show up here while they’re queued or transcribing, and interrupted recordings return here for recovery."
        )
        .padding(.vertical, Geist.Spacing.eight)
    }

    #if DEBUG
    private func activateRuntimeValidationActions(
        includeExtendedActions: Bool
    ) async -> String {
        if includeExtendedActions {
            return await activateExtendedRuntimeValidationActions()
        }
        for _ in 0..<100 {
            await queue.refresh(clearExistingError: false)
            let hasFailed = queue.actionableJobs.contains {
                $0.phase == .failed && $0.delivery != .recovery
                    && (!includeExtendedActions
                        || $0.originalFilename == "runtime-primary-failed.wav")
            }
            let hasQueued = queue.actionableJobs.contains {
                $0.phase == .queued
                    && (!includeExtendedActions
                        || $0.originalFilename == "runtime-primary-queued.wav")
            }
            let hasCopy = queue.actionableJobs.contains {
                $0.phase == .completed && $0.transcriptText != nil
                    && (!includeExtendedActions
                        || $0.originalFilename == "runtime-primary-copy.wav")
            }
            if hasFailed && hasQueued && hasCopy { break }
            try? await Task.sleep(for: .milliseconds(50))
        }
        guard let failed = queue.actionableJobs.first(where: {
            $0.phase == .failed && $0.delivery != .recovery
                && (!includeExtendedActions
                    || $0.originalFilename == "runtime-primary-failed.wav")
        }),
        let queued = queue.actionableJobs.first(where: {
            $0.phase == .queued
                && (!includeExtendedActions
                    || $0.originalFilename == "runtime-primary-queued.wav")
        }),
        let copyReady = queue.actionableJobs.first(where: {
            $0.phase == .completed && $0.transcriptText != nil
                && (!includeExtendedActions
                    || $0.originalFilename == "runtime-primary-copy.wav")
        }) else {
            return "Runtime queue action fixtures missing"
        }

        queue.clearError()
        queue.setCaptureActive(true)
        await queue.retry(failed)
        guard queue.lastError == nil else { return "Retry failed" }
        await queue.processNow(queued)
        guard queue.lastError == nil else { return "Process Now failed" }
        let processedQueuedID = queued.id
        await queue.updateRetention(queued, policy: .permanent)
        guard queue.lastError == nil else { return "Retention failed" }
        await queue.acknowledgeCopiedResult(copyReady)
        guard queue.lastError == nil else { return "Copy acknowledgement failed" }
        let currentQueued = queue.jobs.first(where: { $0.id == queued.id }) ?? queued
        await queue.discard(currentQueued)
        guard queue.lastError == nil else { return "Delete failed" }

        return "Runtime queue actions passed \(processedQueuedID.uuidString.lowercased()) \(failed.id.uuidString.lowercased())"
    }

    private func activateExtendedRuntimeValidationActions() async -> String {
        for _ in 0..<100 {
            await queue.refresh(clearExistingError: false)
            let failedCount = queue.actionableJobs.filter { $0.phase == .failed }.count
            let queuedCount = queue.actionableJobs.filter { $0.phase == .queued }.count
            if failedCount >= 3 && queuedCount >= 1 { break }
            try? await Task.sleep(for: .milliseconds(50))
        }

        queue.clearError()
        queue.setCaptureActive(true)
        let retryFilenames = Set([
            "runtime-retry-one.wav",
            "runtime-retry-two.wav",
        ])
        let retryAllJobs = queue.retryAllEligibleJobs.filter {
            $0.originalFilename.map(retryFilenames.contains) == true
        }
        guard retryAllJobs.count == retryFilenames.count,
              let timed = queue.jobs.first(where: {
                  $0.originalFilename == "runtime-timed.wav"
              }) else {
            return "Runtime Retry All fixtures missing"
        }
        let retryAllIDs = retryAllJobs.map(\.id)
        for job in retryAllJobs {
            if let retryCoordinator {
                await retryCoordinator.retry(job)
            } else {
                await queue.retry(job)
            }
        }
        guard queue.lastError == nil else { return "Retry All failed" }
        let retryAllSucceeded = retryAllIDs.allSatisfy { id in
            queue.jobs.first(where: { $0.id == id }).map {
                $0.phase == .queued && $0.processingPolicy == .immediate
            } ?? false
        }
        guard retryAllSucceeded else { return "Retry All state failed" }

        guard let deleteAfterSuccess = queue.jobs.first(where: {
            $0.originalFilename == "runtime-delete-after.wav"
        }) else {
            return "Runtime retention fixtures missing"
        }
        await queue.updateRetention(
            timed,
            policy: .timed(SourceAudioRetentionPolicy.defaultTimedRetention)
        )
        await queue.updateRetention(
            deleteAfterSuccess,
            policy: .deleteAfterSuccess
        )
        guard queue.lastError == nil else { return "Extended retention failed" }
        let timedSucceeded = queue.jobs.first(where: { $0.id == timed.id })?
            .retentionPolicy.mode == .timed
        let deleteAfterSucceeded = queue.jobs.first(where: {
            $0.id == deleteAfterSuccess.id
        })?.retentionPolicy.mode == .deleteAfterSuccess
        guard timedSucceeded, deleteAfterSucceeded else {
            return "Extended retention state failed"
        }
        return "Runtime extended queue actions passed \(retryAllIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")) retention \(timed.id.uuidString.lowercased()),\(deleteAfterSuccess.id.uuidString.lowercased())"
    }
    #endif

    private func retryAllFailedJobs() async {
        for job in queue.retryAllEligibleJobs {
            if let retryCoordinator {
                await retryCoordinator.retry(job)
            } else {
                await queue.retry(job)
            }
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { queue.lastError != nil },
            set: { presented in
                if !presented { queue.clearError() }
            }
        )
    }
}

/// One recording job rendered as a Signal Activity card, with the same
/// retry, copy, retention and delete actions as the full queue. Used by the
/// combined iOS Activity feed.
struct RecordingQueueJobCard: View {
    let job: RecordingJob
    @Bindable var queue: RecordingJobQueue
    let recoveryPresets: [CapturePreset]
    private let retryCoordinator: RecordingQueueRetryCoordinator?

    init(
        job: RecordingJob,
        queue: RecordingJobQueue,
        recoveryPresets: [CapturePreset] = [],
        retryOverride: (@MainActor (RecordingJob, RecordingJobDelivery?) async -> Void)? = nil
    ) {
        self.job = job
        self.queue = queue
        self.recoveryPresets = recoveryPresets.filter(\.isEnabled)
        self.retryCoordinator = retryOverride.map(RecordingQueueRetryCoordinator.init(action:))
    }

    var body: some View {
        RecordingQueueRow(
            job: job,
            queue: queue,
            retryCoordinator: retryCoordinator,
            recoveryPresets: recoveryPresets
        )
        .activitySignalCard(needsAttention: job.phase == .failed)
    }
}

private struct RecordingQueueRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmsDelete = false
    let job: RecordingJob
    @Bindable var queue: RecordingJobQueue
    let retryCoordinator: RecordingQueueRetryCoordinator?
    let recoveryPresets: [CapturePreset]

    var body: some View {
        HStack(alignment: .top, spacing: Geist.Spacing.three) {
            leadingIndicator
                .padding(.top, job.phase == .completed ? 2 : 6)

            VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                        titleLabel
                        statusLabel
                    }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: Geist.Spacing.three) {
                        titleLabel
                        Spacer()
                        statusLabel
                    }
                }

                Text("\(job.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(formattedDuration(job.duration))")
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)

                if !dynamicTypeSize.isAccessibilitySize,
                   let message = job.statusMessage,
                   !message.isEmpty {
                    Text(message)
                        .font(Geist.body(.subheadline))
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if queue.activeJobID == job.id,
                   let progress = queue.transcriptionProgress,
                   let fraction = progress.exactFractionCompleted {
                    ActivitySignalProgressBar(fraction: fraction)
                        .accessibilityLabel(status)
                        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
                }

                actionArea
                    .padding(.top, Geist.Spacing.one)
            }
        }
    }

    @ViewBuilder
    private var leadingIndicator: some View {
        switch job.phase {
        case .completed:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Geist.success)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        case .failed:
            ActivitySignalDot(color: Geist.warning)
        case .discarded:
            ActivitySignalDot(color: Geist.faint)
        case .queued:
            ActivitySignalDot(color: Geist.Palette.gray600)
        case .processing, .finalizing:
            ActivitySignalDot(color: Geist.accent)
        }
    }

    private var titleLabel: some View {
        Text(title)
            .font(Geist.heading(.callout))
            .foregroundStyle(Geist.text)
            .accessibilityLabel(title)
    }

    private var statusLabel: some View {
        Label(status, systemImage: statusSymbolName)
            .labelStyle(.titleOnly)
            .font(Geist.mono(size: 11.5, relativeTo: .caption, medium: job.phase == .failed))
            .foregroundStyle(statusColor)
    }

    @ViewBuilder
    private var actionArea: some View {
        Group {
            #if os(macOS)
            HStack(spacing: 12) {
                applicableActions
                Spacer()
                deleteAction
            }
            #else
            // Activity board: one primary pill, an optional secondary and a •••
            // menu, on one line (the 2×2 grid wrapped "Retry↵Recording").
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Geist.Spacing.two) { compactActions }
            } else {
                HStack(spacing: Geist.Spacing.two) { compactActions }
            }
            #endif
        }
        .confirmationDialog(
            String(localized: "Delete this recording?"),
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete Recording", role: .destructive) {
                Task { await queue.discard(job) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            #if os(macOS)
            Text("The audio and any transcript are removed from this Mac. This can’t be undone.")
            #else
            Text("The audio and any transcript are removed from this iPhone. This can’t be undone.")
            #endif
        }
    }

    #if !os(macOS)
    @ViewBuilder
    private var compactActions: some View {
        primaryAction
        if let text = job.transcriptText, !text.isEmpty {
            Button("Copy Transcript", systemImage: "doc.on.doc") {
                if copy(text) {
                    Task { await queue.acknowledgeCopiedResult(job) }
                }
            }
            .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
        }
        Menu {
            if let audioURL = queue.audioURL(for: job) {
                ShareLink(item: audioURL) {
                    Label("Share Audio", systemImage: "square.and.arrow.up")
                }
            }
            keepAudioMenu
            if job.phase != .processing && job.phase != .finalizing {
                Divider()
                Button("Delete Recording", systemImage: "trash", role: .destructive) {
                    confirmsDelete = true
                }
            }
        } label: {
            Label("More options", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
        .accessibilityLabel("More options")
    }
    #endif

    private var keepAudioMenu: some View {
        Menu("Keep Audio", systemImage: "externaldrive") {
            Button("Delete After Processing") {
                Task { await queue.updateRetention(job, policy: .deleteAfterSuccess) }
            }
            Button("Use Timed Retention") {
                let configured = RecordingQueuePreferences.load().sourceAudioRetention
                let interval = configured.mode == .timed
                    ? configured.retentionInterval ?? SourceAudioRetentionPolicy.defaultTimedRetention
                    : SourceAudioRetentionPolicy.defaultTimedRetention
                Task { await queue.updateRetention(job, policy: .timed(interval)) }
            }
            Button("Keep Permanently") {
                Task { await queue.updateRetention(job, policy: .permanent) }
            }
        }
    }

    @ViewBuilder
    private var applicableActions: some View {
        primaryAction

        if let text = job.transcriptText, !text.isEmpty {
            Button("Copy Transcript", systemImage: "doc.on.doc") {
                if copy(text) {
                    Task { await queue.acknowledgeCopiedResult(job) }
                }
            }
            .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
        }

        if let audioURL = queue.audioURL(for: job) {
            audioAction(audioURL)
        }

        keepAudioMenu
            .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
    }

    @ViewBuilder
    private var deleteAction: some View {
        if job.phase != .processing && job.phase != .finalizing {
            Button("Delete Recording", systemImage: "trash", role: .destructive) {
                confirmsDelete = true
            }
            .buttonStyle(ActivitySignalPillButtonStyle(kind: .destructive))
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch job.phase {
        case .queued:
            Button("Process Now", systemImage: "play.fill") {
                Task { await queue.processNow(job) }
            }
            .buttonStyle(ActivitySignalPillButtonStyle(kind: .primary))
        case .failed where job.delivery == .recovery:
            Menu("Choose Route", systemImage: "arrow.triangle.branch") {
                if recoveryPresets.isEmpty {
                    Text("No enabled Routes")
                } else {
                    ForEach(recoveryPresets) { preset in
                        Button(preset.accessibilityName) {
                            Task {
                                if let retryCoordinator {
                                    await retryCoordinator.retry(
                                        job,
                                        delivery: .preset(preset)
                                    )
                                } else {
                                    await queue.retry(
                                        job,
                                        delivery: .preset(preset)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .buttonStyle(ActivitySignalPillButtonStyle(kind: .primary))
        case .failed:
            Button {
                Task {
                    if let retryCoordinator {
                        await retryCoordinator.retry(job)
                    } else {
                        await queue.retry(job)
                    }
                }
            } label: {
                #if os(macOS)
                Label("Retry Recording", systemImage: "arrow.clockwise")
                #else
                // Short pill label, as on the Activity board.
                Text("Retry")
                #endif
            }
            .buttonStyle(ActivitySignalPillButtonStyle(kind: .primary))
            .accessibilityLabel("Retry Recording")
        case .completed where job.transcriptText != nil:
            EmptyView()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func audioAction(_ url: URL) -> some View {
        #if os(macOS)
        Button("Reveal Audio", systemImage: "folder") {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
        #else
        ShareLink(item: url) {
            Label("Share Audio", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
        #endif
    }

    private var title: String {
        switch job.delivery {
        case .preset(let preset):
            return preset.accessibilityName
        case .captureDraft:
            return String(localized: "Capture Draft Recording")
        case .clipboard:
            return String(localized: "Clipboard Transcription")
        case .keyboard:
            return String(localized: "Keyboard Transcription")
        case .recovery:
            return String(localized: "Recovered Recording")
        }
    }

    private var symbolName: String {
        switch job.phase {
        case .queued: return "clock"
        case .processing, .finalizing: return "waveform"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .discarded: return "trash"
        }
    }

    private var status: String {
        if job.phase == .completed, job.transcriptText != nil {
            return String(localized: "Ready to copy")
        }
        switch job.phase {
        case .queued: return String(localized: "Queued")
        case .processing: return String(localized: "Transcribing")
        case .finalizing: return String(localized: "Saving")
        case .completed: return String(localized: "Completed")
        case .failed: return String(localized: "Needs attention")
        case .discarded: return String(localized: "Discarded")
        }
    }

    private var statusSymbolName: String {
        switch job.phase {
        case .queued: return "clock"
        case .processing, .finalizing: return "waveform"
        case .completed: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        case .discarded: return "trash"
        }
    }

    private var statusColor: Color {
        switch job.phase {
        case .failed: return Geist.Palette.amber900
        case .completed: return Geist.success
        case .processing, .finalizing: return Geist.accentText
        default: return Geist.muted
        }
    }

    @discardableResult
    private func copy(_ text: String) -> Bool {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        return UIPasteboard.general.string == text
        #endif
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Signal Activity components

enum ActivitySignalFilter: Hashable {
    case all
    case needsAttention
    case inFlight
}

/// White Activity card; an orange border marks work that needs the user.
struct ActivitySignalCardModifier: ViewModifier {
    var needsAttention = false

    func body(content: Content) -> some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Geist.card,
                in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .stroke(needsAttention ? Geist.Palette.amber400 : Geist.border, lineWidth: 1)
            )
    }
}

extension View {
    func activitySignalCard(needsAttention: Bool = false) -> some View {
        modifier(ActivitySignalCardModifier(needsAttention: needsAttention))
    }
}

/// 10pt status dot used at the leading edge of Activity cards.
struct ActivitySignalDot: View {
    let color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .frame(width: 18, alignment: .leading)
            .accessibilityHidden(true)
    }
}

/// Thin 4pt accent progress track.
struct ActivitySignalProgressBar: View {
    let fraction: Double

    /// Indigo that lifts to #6E78FF in dark mode, per the dark Activity board.
    private static var fill: Color {
        #if os(macOS)
        Geist.accent
        #else
        Geist.Palette.blue700
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Geist.well)
                Capsule()
                    .fill(Self.fill)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
    }
}

/// Content-sized pill used for card actions (Fix, Retry, Discard…).
struct ActivitySignalPillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }

    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Geist.label(.subheadline))
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, Geist.Spacing.four)
            .padding(.vertical, 6)
            .frame(minHeight: Geist.ControlHeight.medium)
            .background(background(configuration.isPressed), in: Capsule(style: .continuous))
            .overlay {
                if kind != .primary {
                    Capsule(style: .continuous).stroke(Geist.border, lineWidth: 1)
                }
            }
            .contentShape(Capsule(style: .continuous))
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return Geist.Palette.background100
        case .secondary: return Geist.text
        case .destructive: return Geist.error
        }
    }

    private func background(_ pressed: Bool) -> Color {
        switch kind {
        case .primary: return pressed ? Geist.Palette.gray900 : Geist.text
        case .secondary, .destructive: return pressed ? Geist.Palette.gray200 : Geist.card
        }
    }
}

/// Track-and-thumb segmented control from the Signal Activity layout.
struct ActivitySignalSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let segments: [(Value, String)]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                let isSelected = segment.0 == selection
                Button {
                    selection = segment.0
                } label: {
                    Text(segment.1)
                        .font(isSelected ? Geist.label(.subheadline) : Geist.body(.subheadline))
                        .foregroundStyle(isSelected ? Geist.text : Geist.Palette.gray800)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            isSelected ? Geist.card : Color.clear,
                            in: Capsule(style: .continuous)
                        )
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Geist.well, in: Capsule(style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

/// Centered "all caught up" style empty state.
struct ActivitySignalEmptyState: View {
    let systemImage: String
    var tint: Color = Geist.success
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        VStack(spacing: Geist.Spacing.three) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 56, height: 56)
                .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                        .stroke(Geist.border, lineWidth: 1)
                )
                .accessibilityHidden(true)
            Text(title)
                .font(Geist.heading(.title3))
                .foregroundStyle(Geist.text)
            Text(message)
                .font(Geist.body(.callout))
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Geist.Spacing.six)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Wraps content-sized action pills onto as many lines as needed.
struct ActivitySignalFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.init(width: bounds.width, height: nil))
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.init(width: maxWidth, height: nil))
            let itemWidth = min(size.width, maxWidth)
            let proposedWidth = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if !current.indices.isEmpty && proposedWidth > maxWidth {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
