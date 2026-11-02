import SwiftUI
import VoxboardShared

struct WatchRecordingQueueView: View {
    @Bindable var pipeline: WatchRecordingPipeline
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDiscard: WatchRecordingInboxItem?
    @State private var showsPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if visibleItems.isEmpty {
                    ActivitySignalEmptyState(
                        systemImage: "applewatch",
                        tint: Geist.success,
                        title: "No Watch Recordings",
                        message: "Record on Apple Watch and it will appear here automatically."
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    List(visibleItems) { item in
                        recordingRow(item)
                            .activitySignalCard(needsAttention: item.phase == .failed)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        pipeline.refresh()
                        pipeline.resume()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Geist.bg.ignoresSafeArea())
            .navigationTitle("Watch Recordings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showsPaywall) {
                PaywallView(context: .limit)
            }
            .confirmationDialog(
                "Discard this Watch recording?",
                isPresented: discardConfirmationPresented,
                titleVisibility: .visible
            ) {
                Button("Discard Recording", role: .destructive) {
                    guard let pendingDiscard else { return }
                    pipeline.discard(pendingDiscard)
                    self.pendingDiscard = nil
                }
                Button("Cancel", role: .cancel) { pendingDiscard = nil }
            } message: {
                Text("This removes the retained audio and any capture that is still queued for delivery.")
            }
        }
    }

    private var visibleItems: [WatchRecordingInboxItem] {
        pipeline.items
            .filter { item in
                item.phase != .discarded
                    && !(item.phase.isTerminal && item.acknowledgedAt != nil)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private var discardConfirmationPresented: Binding<Bool> {
        Binding(
            get: { pendingDiscard != nil },
            set: { if !$0 { pendingDiscard = nil } }
        )
    }

    private func recordingRow(_ item: WatchRecordingInboxItem) -> some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            HStack(alignment: .top, spacing: Geist.Spacing.three) {
                statusIndicator(item)
                    .padding(.top, item.phase == .delivered ? 2 : 6)

                VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                    HStack(alignment: .firstTextBaseline, spacing: Geist.Spacing.two) {
                        Text(item.watchStatusTitle)
                            .font(Geist.heading(.callout))
                            .foregroundStyle(Geist.text)
                        Spacer(minLength: Geist.Spacing.two)
                        Text(item.createdAt, style: .relative)
                            .font(Geist.mono(size: 11.5, relativeTo: .caption))
                            .foregroundStyle(Geist.muted)
                            .lineLimit(1)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: Geist.Spacing.two) {
                        Text(item.watchStatusSubtitle)
                            .font(Geist.body(.subheadline))
                            .foregroundStyle(Geist.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if item.phase == .transcribing || item.phase == .delivering {
                            Spacer(minLength: 0)
                            ProgressView()
                                .controlSize(.small)
                                .tint(Geist.accent)
                        }
                    }

                    HStack(spacing: Geist.Spacing.two) {
                        Label(item.displayPresetName, systemImage: "waveform.circle")
                        if let duration = item.duration {
                            Label(formatDuration(duration), systemImage: "timer")
                        }
                    }
                    .labelStyle(.titleOnly)
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.faint)
                }
            }

            Group {
                if item.phase == .failed {
                    HStack(spacing: Geist.Spacing.two) {
                        if item.requiresPresetSelection {
                            Menu("Choose Route") {
                                ForEach(
                                    CapturePresetStore.loadFlows().filter(\.isEnabled),
                                    id: \.id
                                ) { preset in
                                    Button(preset.accessibilityName) {
                                        pipeline.choosePreset(preset, for: item)
                                    }
                                }
                            }
                            .buttonStyle(ActivitySignalPillButtonStyle(kind: .primary))
                        } else {
                            Button {
                                usageTracker.requirePaidAccess(otherwise: { showsPaywall = true }) {
                                    pipeline.retry(item)
                                }
                            } label: {
                                PaidAccessLabel("Retry", isLocked: usageTracker.isLibraryReadOnly)
                            }
                            .buttonStyle(ActivitySignalPillButtonStyle(kind: .primary))
                            if item.flowSnapshot?.watchOutputMode == .recordingOnly {
                                Menu("Change Route") {
                                    ForEach(
                                        CapturePresetStore.loadFlows().filter {
                                            $0.isEnabled && $0.watchOutputMode == .recordingOnly
                                        },
                                        id: \.id
                                    ) { preset in
                                        Button(preset.accessibilityName) {
                                            pipeline.choosePreset(preset, for: item)
                                        }
                                    }
                                }
                                .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
                            }
                        }
                        Button("Discard", role: .destructive) { pendingDiscard = item }
                            .buttonStyle(ActivitySignalPillButtonStyle(kind: .destructive))
                    }

                    if item.canCaptureRecordingWithoutTranscript {
                        Button {
                            usageTracker.requirePaidAccess(otherwise: { showsPaywall = true }) {
                                pipeline.captureRecordingWithoutTranscript(item)
                            }
                        } label: {
                            PaidAccessLabel(
                                "Capture Recording Without Transcript",
                                systemImage: "waveform",
                                isLocked: usageTracker.isLibraryReadOnly
                            )
                        }
                        .buttonStyle(ActivitySignalPillButtonStyle(kind: .secondary))
                        .accessibilityHint("Saves the retained audio to Capture without transcription")
                    }
                } else if item.phase == .queued {
                    HStack(spacing: Geist.Spacing.two) {
                        if item.isWaitingForTranscriptionUpgrade {
                            Button("Get Unlimited") { showsPaywall = true }
                                .buttonStyle(ActivitySignalPillButtonStyle(kind: .primary))
                        }
                        Button("Discard", role: .destructive) { pendingDiscard = item }
                            .buttonStyle(ActivitySignalPillButtonStyle(kind: .destructive))
                    }
                }
            }
            .padding(.leading, 30)
        }
    }

    @ViewBuilder
    private func statusIndicator(_ item: WatchRecordingInboxItem) -> some View {
        switch item.phase {
        case .delivered:
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Geist.success)
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
        case .failed:
            ActivitySignalDot(color: Geist.warning)
        case .transcribing, .delivering:
            ActivitySignalDot(color: Geist.accent)
        case .queued:
            ActivitySignalDot(color: Geist.Palette.gray600)
        case .discarded:
            ActivitySignalDot(color: Geist.faint)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }
}

extension WatchRecordingInboxItem {
    var isWaitingForTranscriptionUpgrade: Bool {
        phase == .queued
            && statusMessage == WatchRecordingStatusMessage.transcriptionLimitReached
    }

    var watchStatusTitle: String {
        switch phase {
        case .queued:
            return String(localized: "Received from Apple Watch")
        case .transcribing:
            return String(localized: "Transcribing Watch recording")
        case .delivering:
            return isRecordingOnlyWatchOutput
                ? String(localized: "Saving recording to Files")
                : String(localized: "Saving to Capture")
        case .delivered:
            return isRecordingOnlyWatchOutput
                ? String(localized: "Watch recording saved to Files")
                : String(localized: "Watch recording saved")
        case .failed:
            return String(localized: "Watch recording needs attention")
        case .discarded:
            return String(localized: "Watch recording discarded")
        }
    }

    var watchStatusSubtitle: String {
        if let statusMessage, !statusMessage.isEmpty {
            return statusMessage
        }
        switch phase {
        case .queued:
            return String(localized: "Queued on iPhone with \(displayPresetName)")
        case .transcribing:
            return String(localized: "On-device transcription is running")
        case .delivering:
            return isRecordingOnlyWatchOutput
                ? String(localized: "Copying the retained M4A to the selected Files folder")
                : String(localized: "Writing through the Capture pipeline")
        case .delivered:
            return isRecordingOnlyWatchOutput
                ? String(localized: "Saved as a user-visible M4A file")
                : String(localized: "Delivered with \(displayPresetName)")
        case .failed:
            return isRecordingOnlyWatchOutput
                ? String(localized: "The M4A is retained safely for Files retry")
                : String(localized: "The audio and transcript are retained for retry")
        case .discarded:
            return String(localized: "Removed")
        }
    }

    var canCaptureRecordingWithoutTranscript: Bool {
        phase == .failed
            && failureStage == .transcription
            && !isRecordingOnlyWatchOutput
            && hasAudio
    }

    private var isRecordingOnlyWatchOutput: Bool {
        flowSnapshot?.watchOutputMode == .recordingOnly
    }

    var watchStatusSymbol: String {
        switch phase {
        case .queued:
            return "applewatch.radiowaves.left.and.right"
        case .transcribing:
            return "waveform.badge.magnifyingglass"
        case .delivering:
            return isRecordingOnlyWatchOutput ? "folder.badge.plus" : "arrow.up.doc"
        case .delivered:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .discarded:
            return "trash"
        }
    }
}
