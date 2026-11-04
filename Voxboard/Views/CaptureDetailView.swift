import AVFoundation
import SwiftUI
import UIKit
import VoxboardShared

/// Library · capture detail: what was captured, where it went, and how the
/// route handled it, with playback, re-delivery and Obsidian hand-off.
struct CaptureDetailView: View {
    enum Tab: Hashable { case written, transcript, routeLog }

    let item: LibraryItem
    @Bindable var viewModel: QuickCaptureViewModel
    var isReadOnly = false
    var isPrimaryRoute = false
    /// False in a list | detail Library, where the list stays beside it.
    var showsBackButton = true
    /// Called after Delete, so a split Library can clear its selection.
    var onDeleted: (() -> Void)?

    @Environment(TranscriptStore.self) private var store
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(StoreManager.self) private var storeManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var tab: Tab = .written
    @State private var player = CaptureAudioPlayer()
    @State private var sharePayload: TranscriptSharePayload?
    @State private var showsDeleteConfirmation = false
    @State private var statusMessage: String?
    @State private var errorMessage: String?
    @State private var isSending = false
    @State private var showsPlans = false

    /// Read-only when presented that way, or once a trial or subscription
    /// has ended. Copy, export, Open in Obsidian and delete stay available;
    /// "Send to another route" is a new Capture delivery and is locked.
    private var requiresPlanToSend: Bool {
        isReadOnly || usageTracker.isLibraryReadOnly
    }

    private var record: CaptureHistoryRecord? { item.record }
    private var content: CaptureLibraryContent? { item.content }

    private var destination: CaptureDestination? {
        guard let id = record?.destinationID else { return nil }
        return viewModel.destinations.first { $0.id == id }
    }

    var body: some View {
        ZStack {
            Geist.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                        titleSection
                            .padding(.horizontal, 4)
                            .padding(.bottom, 4)
                        if content?.audioRelativePath != nil {
                            audioCard
                        }
                        ActivitySignalSegmentedControl(
                            selection: $tab,
                            segments: [
                                (.written, String(localized: "As written")),
                                (.transcript, String(localized: "Transcript")),
                                (.routeLog, String(localized: "Route log")),
                            ]
                        )
                        .accessibilityLabel("View")
                        pane
                        if let statusMessage {
                            Label(statusMessage, systemImage: "checkmark")
                                .font(Geist.caption(.footnote))
                                .foregroundStyle(Geist.success)
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, Geist.Spacing.four)
                    .padding(.top, Geist.Spacing.two)
                    .padding(.bottom, Geist.Spacing.four)
                }
                footer
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if viewModel.destinations.isEmpty { await viewModel.refreshLibrary() }
            loadAudio()
        }
        .onDisappear { player.stop() }
        .sheet(isPresented: $showsPlans) {
            PaywallView(context: .captureLimit)
                .environment(usageTracker)
                .environment(storeManager)
        }
        .sheet(item: $sharePayload) { payload in
            TranscriptActivityView(activityItems: [payload.url])
                .ignoresSafeArea()
        }
        .confirmationDialog(
            "Delete this capture from the Library?",
            isPresented: $showsDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
        } message: {
            Text("The note in your vault is not changed.")
        }
        .alert("Capture", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            if showsBackButton {
                Button { dismiss() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(SignalCircleButtonStyle())
                    .accessibilityLabel("Back to library")
            }
            Spacer()
            Menu {
                if let markdown = item.copyableMarkdown {
                    Button("Copy Markdown", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = markdown
                        flash(String(localized: "Copied Markdown"))
                    }
                }
                if let text = item.bodyText, text != item.copyableMarkdown {
                    Button("Copy text", systemImage: "text.quote") {
                        UIPasteboard.general.string = text
                        flash(String(localized: "Copied text"))
                    }
                }
                Button("Export", systemImage: "square.and.arrow.up") { export() }
                Divider()
                Button("Delete", systemImage: "trash", role: .destructive) {
                    showsDeleteConfirmation = true
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Geist.text)
                    .frame(width: Geist.ControlHeight.medium, height: Geist.ControlHeight.medium)
                    .background(Geist.card, in: Circle())
                    .overlay(Circle().stroke(Geist.border, lineWidth: 1))
                    .contentShape(Circle())
            }
            .accessibilityLabel("More actions")
        }
        .padding(.horizontal, Geist.Spacing.four + 4)
        .padding(.vertical, Geist.Spacing.two)
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.two) {
            HStack(spacing: Geist.Spacing.two) {
                LibraryRouteTileView(name: item.routeName, size: 22)
                Text(verbatim: item.routeName ?? String(localized: "Capture"))
                    .font(Geist.label(.subheadline))
                    .foregroundStyle(Geist.text)
                Text(verbatim: "· \(LibraryFormatting.dayLabel(item.date)) \(item.date.formatted(.dateTime.hour().minute()))")
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
            }
            .accessibilityElement(children: .combine)

            Text(verbatim: item.title)
                .font(Geist.display(30))
                .foregroundStyle(Geist.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            deliveryLine
        }
    }

    @ViewBuilder
    private var deliveryLine: some View {
        if let record {
            switch record.outcome {
            case .delivered:
                Label {
                    Text(record.relativeNotePath.map { String(localized: "Delivered to \($0)") }
                         ?? String(localized: "Delivered to \(record.destinationName)"))
                } icon: {
                    Image(systemName: "checkmark")
                }
                .font(Geist.label(.footnote))
                .foregroundStyle(Geist.success)
            case .failed:
                Label {
                    Text(record.failureReason?.kind == .headingNotFound
                         ? String(localized: "Not delivered · heading not found")
                         : String(localized: "Not delivered · \(record.failureCategory?.displayName ?? "Delivery failed")"))
                } icon: {
                    Image(systemName: "exclamationmark.circle")
                }
                .font(Geist.label(.footnote))
                .foregroundStyle(Geist.Palette.amber900)
            }
        } else {
            Label("Saved on this iPhone", systemImage: "iphone")
                .font(Geist.label(.footnote))
                .foregroundStyle(Geist.muted)
        }
    }

    // MARK: Audio

    private var audioCard: some View {
        HStack(spacing: Geist.Spacing.three) {
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Geist.Palette.background100)
                    .frame(width: 40, height: 40)
                    .background(Geist.text, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!player.isReady)
            .opacity(player.isReady ? 1 : 0.5)
            .accessibilityLabel(player.isPlaying ? "Pause recording" : "Play recording")

            VStack(alignment: .leading, spacing: 4) {
                CapturePlaybackScrubber(
                    progress: player.progress,
                    isEnabled: player.isReady,
                    onSeek: { player.seek(toFraction: $0) }
                )
                .accessibilityLabel("Playback position")
                .accessibilityValue(LibraryFormatting.clock(player.currentTime))

                Text(verbatim: audioMetadata)
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Geist.Spacing.three)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Geist.border, lineWidth: 1))
    }

    private var audioMetadata: String {
        var parts: [String] = []
        if let name = content?.audioFilename { parts.append(name) }
        let duration = player.duration > 0 ? player.duration : (item.transcript?.duration ?? content?.audioDuration ?? 0)
        if duration > 0 { parts.append(LibraryFormatting.clock(duration)) }
        if let speakers = item.transcript?.speakerCount, speakers > 0 {
            parts.append(speakers == 1
                ? String(localized: "1 speaker")
                : String(localized: "\(speakers) speakers"))
        }
        if let failure = player.loadError { parts.append(failure) }
        return parts.joined(separator: " · ")
    }

    private func loadAudio() {
        guard let path = content?.audioRelativePath, let destination else { return }
        player.load(rootBookmark: destination.rootBookmark, relativePath: path)
    }

    // MARK: Panes

    @ViewBuilder
    private var pane: some View {
        switch tab {
        case .written:
            codeBlock(content?.renderedMarkdown
                      ?? item.bodyText
                      ?? String(localized: "This capture was delivered before Vox.md kept a copy of the written Markdown."))
        case .transcript:
            transcriptPane
        case .routeLog:
            routeLogPane
        }
    }

    private func codeBlock(_ text: String) -> some View {
        Text(verbatim: text)
            .font(Geist.mono(size: 12.5, relativeTo: .footnote))
            .lineSpacing(4)
            .foregroundStyle(Color(red: 0.914, green: 0.914, blue: 0.894))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Geist.Spacing.four)
            .background(
                Color(red: 0.071, green: 0.071, blue: 0.071),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
    }

    @ViewBuilder
    private var transcriptPane: some View {
        if let turns = item.transcript?.speakerTurns, !turns.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(turns.enumerated()), id: \.element.id) { index, turn in
                    if index > 0 { GeistDivider() }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: turn.speakerLabel)
                                .font(Geist.label(.footnote))
                                .foregroundStyle(Geist.text)
                            Spacer()
                            Button(LibraryFormatting.clock(turn.startTime)) {
                                player.seek(toTime: turn.startTime)
                            }
                            .font(Geist.mono(size: 11, relativeTo: .caption))
                            .foregroundStyle(Geist.muted)
                            .buttonStyle(.plain)
                            .disabled(!player.isReady)
                            .accessibilityLabel("Play from \(LibraryFormatting.clock(turn.startTime))")
                        }
                        Text(verbatim: turn.text)
                            .font(Geist.body(.callout))
                            .foregroundStyle(Geist.text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, Geist.Spacing.three)
                }
            }
            .padding(.horizontal, 14)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Geist.border, lineWidth: 1))
        } else {
            let text = item.transcript.map { $0.cleanedText ?? $0.text } ?? item.bodyText
            Text(verbatim: text ?? String(localized: "No transcript for this capture."))
                .font(Geist.body(.callout))
                .foregroundStyle(text == nil ? Geist.muted : Geist.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Geist.Spacing.four)
                .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Geist.border, lineWidth: 1))
        }
    }

    private var routeSteps: [CaptureRouteLogStep] {
        if let log = record?.routeLog, !log.isEmpty { return log }
        guard let record else {
            return [CaptureRouteLogStep(kind: .capture, outcome: .succeeded, at: item.date)]
        }
        return [
            CaptureRouteLogStep(kind: .capture, outcome: .succeeded, at: record.createdAt, detail: record.source.rawValue),
            CaptureRouteLogStep(
                kind: .deliver,
                outcome: record.outcome == .delivered ? .succeeded : .failed,
                at: record.deliveredAt,
                detail: record.outcome == .delivered ? record.relativeNotePath : record.failureCategory?.displayName
            ),
        ]
    }

    private var routeLogPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(routeSteps.enumerated()), id: \.offset) { index, step in
                if index > 0 { GeistDivider() }
                HStack(alignment: .top, spacing: Geist.Spacing.three) {
                    Image(systemName: icon(for: step.outcome))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(color(for: step.outcome))
                        .frame(width: 18, height: 18)
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(for: step))
                            .font(Geist.label(.subheadline))
                            .foregroundStyle(Geist.text)
                        if let detail = stepDetail(step) {
                            Text(verbatim: detail)
                                .font(Geist.mono(size: 11.5, relativeTo: .caption))
                                .foregroundStyle(step.outcome == .failed ? Geist.Palette.amber900 : Geist.muted)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: Geist.Spacing.two)
                    if let at = step.at {
                        Text(at, format: .dateTime.hour().minute().second())
                            .font(Geist.mono(size: 11.5, relativeTo: .caption))
                            .foregroundStyle(Geist.muted)
                    }
                }
                .padding(.vertical, Geist.Spacing.three)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Geist.border, lineWidth: 1))
    }

    private func title(for step: CaptureRouteLogStep) -> String {
        switch (step.kind, step.outcome) {
        case (.capture, _): return String(localized: "Captured")
        case (.process, .skipped): return String(localized: "Processing skipped")
        case (.process, .failed): return String(localized: "Processing failed")
        case (.process, _): return String(localized: "Processed on device")
        case (.shape, .failed): return String(localized: "Couldn’t shape the entry")
        case (.shape, _): return String(localized: "Shaped with the route template")
        case (.deliver, .failed): return String(localized: "Delivery failed")
        case (.deliver, _): return String(localized: "Delivered")
        }
    }

    private func stepDetail(_ step: CaptureRouteLogStep) -> String? {
        if step.kind == .capture, let raw = step.detail, let source = CaptureSource(rawValue: raw) {
            return String(localized: "From \(LibrarySourceLabel.text(for: source))")
        }
        if step.kind == .deliver, step.outcome == .succeeded, let path = step.detail {
            if let heading = record?.placementHeading { return "\(path) · \(heading)" }
            return path
        }
        return step.detail
    }

    private func icon(for outcome: CaptureRouteLogStep.Outcome) -> String {
        switch outcome {
        case .succeeded: return "checkmark"
        case .failed: return "exclamationmark"
        case .skipped: return "minus"
        }
    }

    private func color(for outcome: CaptureRouteLogStep.Outcome) -> Color {
        switch outcome {
        case .succeeded: return Geist.success
        case .failed: return Geist.Palette.amber900
        case .skipped: return Geist.faint
        }
    }

    // MARK: Footer

    private var otherRoutes: [CapturePresetProfile] {
        viewModel.voxProfiles.filter { $0.isEnabled && $0.id != record?.voxID }
    }

    private var footer: some View {
        HStack(spacing: Geist.Spacing.two) {
            if requiresPlanToSend {
                // Locked, not hidden: tapping opens the paywall.
                Button { showsPlans = true } label: {
                    sendToAnotherRouteLabel(isLocked: true)
                }
                .buttonStyle(.plain)
                .disabled(item.copyableMarkdown == nil)
            } else {
                Menu {
                    if otherRoutes.isEmpty {
                        Text("No other routes")
                    } else {
                        ForEach(otherRoutes) { profile in
                            Button(profile.name) { send(to: profile) }
                        }
                    }
                } label: {
                    sendToAnotherRouteLabel(isLocked: false)
                }
                .disabled(isSending || item.copyableMarkdown == nil)
            }

            Button {
                openInObsidian()
            } label: {
                Text("Open in Obsidian")
                    .font(Geist.label(.subheadline))
                    .foregroundStyle(Geist.Palette.background100)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Geist.text, in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(record?.relativeNotePath == nil)
            .opacity(record?.relativeNotePath == nil ? 0.5 : 1)
        }
        .padding(.horizontal, Geist.Spacing.four)
        .padding(.top, 14)
        .padding(.bottom, Geist.Spacing.two)
        .background(Geist.bg)
    }

    private func sendToAnotherRouteLabel(isLocked: Bool) -> some View {
        HStack(spacing: 6) {
            if isLocked {
                Image(systemName: "lock")
                    .accessibilityHidden(true)
            }
            Text(isSending ? "Sending…" : "Send to another route")
        }
        .font(Geist.label(.subheadline))
        .foregroundStyle(Geist.text)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(Geist.card, in: Capsule())
        .overlay(Capsule().stroke(Geist.border, lineWidth: 1))
        .contentShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityHint(isLocked ? usageTracker.readOnlyHint : Text(verbatim: ""))
    }

    // MARK: Actions

    private func flash(_ message: String) {
        withAnimation { statusMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { if statusMessage == message { statusMessage = nil } }
        }
    }

    private func export() {
        do {
            sharePayload = TranscriptSharePayload(url: try LibraryExporter.exportOne(item))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete() {
        player.stop()
        if item.transcript != nil { store.delete(ids: [item.id]) }
        Task {
            await viewModel.deleteHistory(requestID: item.id)
            dismiss()
            onDeleted?()
        }
    }

    private func send(to profile: CapturePresetProfile) {
        guard !requiresPlanToSend else {
            showsPlans = true
            return
        }
        guard let text = item.bodyText ?? item.copyableMarkdown,
              let captureRootURL = AppConstants.captureDirectoryURL else { return }
        isSending = true
        Task {
            defer { isSending = false }
            do {
                try await CaptureInboxRecovery.redeliver(
                    text: text,
                    to: profile,
                    captureRootURL: captureRootURL
                )
                await viewModel.processPendingInbox()
                await viewModel.refreshHistory()
                flash(String(localized: "Sent to \(profile.name)"))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openInObsidian() {
        guard let path = record?.relativeNotePath else { return }
        let vault = destination?.rootName ?? ""
        guard !vault.isEmpty, let url = CaptureInboxRecovery.obsidianOpenURL(vaultName: vault, relativePath: path) else {
            openFileFallback(path)
            return
        }
        openURL(url) { accepted in
            if !accepted { openFileFallback(path) }
        }
    }

    /// Without Obsidian, hand the delivered note to the share sheet so it can
    /// open in Files or another Markdown editor.
    private func openFileFallback(_ path: String) {
        guard let destination,
              let resolution = try? CaptureBookmarkResolver.resolve(destination.rootBookmark) else {
            errorMessage = String(localized: "Vox.md can’t reach this vault folder right now.")
            return
        }
        let root = resolution.url
        let didAccess = root.startAccessingSecurityScopedResource()
        defer { if didAccess { root.stopAccessingSecurityScopedResource() } }
        let source = root.appendingPathComponent(path)
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoxboardOpenNote-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let copy = folder.appendingPathComponent(source.lastPathComponent)
            try FileManager.default.copyItem(at: source, to: copy)
            sharePayload = TranscriptSharePayload(url: copy)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Thin 4pt playback track from the capture detail board. Tap or drag
/// anywhere on the (taller) hit area to seek; VoiceOver adjusts in 5% steps.
private struct CapturePlaybackScrubber: View {
    let progress: Double
    let isEnabled: Bool
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Geist.well)
                Capsule()
                    .fill(Geist.accent)
                    .frame(width: width * min(max(progress, 0), 1))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        onSeek(min(max(value.location.x / width, 0), 1))
                    }
            )
        }
        .frame(height: 16)
        .opacity(isEnabled ? 1 : 0.6)
        .accessibilityElement()
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            switch direction {
            case .increment: onSeek(min(progress + 0.05, 1))
            case .decrement: onSeek(max(progress - 0.05, 0))
            @unknown default: break
            }
        }
    }
}

enum LibrarySourceLabel {
    static func text(for source: CaptureSource) -> String {
        switch source {
        case .app: return String(localized: "the app")
        case .keyboard: return String(localized: "the keyboard")
        case .widget: return String(localized: "a widget")
        case .shortcut: return String(localized: "Shortcuts")
        case .shareExtension: return String(localized: "the share sheet")
        case .watch: return String(localized: "Apple Watch")
        case .mac: return String(localized: "Mac")
        case .deepLink: return String(localized: "a link")
        case .fileImport: return String(localized: "a file import")
        case .voice: return String(localized: "voice")
        }
    }
}

/// Plays a delivered recording from inside the vault folder, holding the
/// folder's security scope only while the player is loaded.
@MainActor
@Observable
final class CaptureAudioPlayer {
    private(set) var isReady = false
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var currentTime: TimeInterval = 0
    private(set) var loadError: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var scopedRoot: URL?
    @ObservationIgnored private var timer: Timer?

    var progress: Double {
        duration > 0 ? currentTime / duration : 0
    }

    func load(rootBookmark: Data, relativePath: String) {
        stop()
        guard (try? CapturePathValidation.validateRelativePath(relativePath)) != nil,
              let resolution = try? CaptureBookmarkResolver.resolve(rootBookmark) else {
            loadError = String(localized: "vault unavailable")
            return
        }
        let root = resolution.url
        if root.startAccessingSecurityScopedResource() { scopedRoot = root }
        let url = root.appendingPathComponent(relativePath)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            isReady = true
            loadError = nil
        } catch {
            loadError = String(localized: "audio unavailable")
            releaseScope()
        }
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            player.pause()
            isPlaying = false
            timer?.invalidate()
        } else {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func seek(toFraction fraction: Double) {
        seek(toTime: duration * min(max(fraction, 0), 1))
    }

    func seek(toTime time: TimeInterval) {
        guard let player else { return }
        player.currentTime = min(max(time, 0), duration)
        currentTime = player.currentTime
        if !player.isPlaying {
            player.play()
            isPlaying = true
            startTimer()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        isPlaying = false
        isReady = false
        currentTime = 0
        releaseScope()
    }

    private func releaseScope() {
        scopedRoot?.stopAccessingSecurityScopedResource()
        scopedRoot = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            // Scheduled on the main run loop.
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func tick() {
        guard let player else { return }
        currentTime = player.currentTime
        if !player.isPlaying {
            isPlaying = false
            timer?.invalidate()
            if currentTime <= 0.01 || currentTime >= duration - 0.05 { currentTime = 0 }
        }
    }
}
