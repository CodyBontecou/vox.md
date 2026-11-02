import SwiftUI
import UIKit
import VoxboardShared

/// Activity · delivery failed. Explains why one queued capture could not be
/// written and offers ways to land it, while making clear it is safe.
struct DeliveryRecoverySheet: View {
    let problem: CaptureDeliveryProblem
    /// Called after an action queues or removes the capture; the caller
    /// drains the inbox and refreshes Activity.
    let onResolved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(StoreManager.self) private var storeManager
    @State private var showsPlans = false
    @State private var fixesRoute = true
    @State private var headings: [CaptureHeadingSelector] = []
    @State private var defaultRouteName: String?
    @State private var isWorking = false
    @State private var errorMessage: String?
    @State private var showsDiscardConfirmation = false

    private var captureRootURL: URL? { AppConstants.captureDirectoryURL }
    /// Trial or subscription ended: delivering, retrying, re-routing and
    /// fixing the route are locked and open the paywall. Copy Markdown and
    /// Discard (explicit deletion) stay available.
    private var isReadOnly: Bool { usageTracker.isLibraryReadOnly }
    private var reason: CaptureDeliveryFailureReason? { problem.failureReason }
    private var isHeadingProblem: Bool { reason?.kind == .headingNotFound && reason?.headingTitle != nil }
    private var missingHeading: CaptureHeadingSelector? {
        guard let title = reason?.headingTitle else { return nil }
        return CaptureHeadingSelector(title: title, level: reason?.headingLevel)
    }
    private var noteName: String {
        (reason?.relativeNotePath as NSString?)?.lastPathComponent ?? problem.destinationName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                captureCard
                actions
                if isHeadingProblem {
                    if isReadOnly {
                        Button { showsPlans = true } label: {
                            HStack(alignment: .center, spacing: 10) {
                                Image(systemName: "lock")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Geist.muted)
                                    .frame(width: 20)
                                fixRouteLabel
                                    .multilineTextAlignment(.leading)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(usageTracker.readOnlyHint)
                    } else {
                        Toggle(isOn: $fixesRoute) {
                            fixRouteLabel
                        }
                        .toggleStyle(SignalCheckboxToggleStyle())
                    }
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(Geist.caption(.footnote))
                        .foregroundStyle(Geist.error)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, Geist.Spacing.six)
            .padding(.bottom, Geist.Spacing.eight)
        }
        .background(Geist.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Geist.bg)
        .disabled(isWorking)
        .task { await load() }
        .sheet(isPresented: $showsPlans) {
            PaywallView(context: .captureLimit)
                .environment(usageTracker)
                .environment(storeManager)
        }
        .confirmationDialog("Discard this capture?", isPresented: $showsDiscardConfirmation, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { perform { try await discard() } }
        } message: {
            Text("It will be removed from this iPhone and won’t be delivered.")
        }
    }

    // MARK: Sections

    private var fixRouteLabel: some View {
        Text("Fix the \(problem.displayRouteName) route too, so this doesn’t happen again")
            .font(Geist.body(.subheadline))
            .foregroundStyle(Geist.Palette.gray800)
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: Geist.Spacing.three) {
            Image(systemName: isVaultProblem ? "folder.badge.questionmark" : "exclamationmark.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Geist.Palette.amber900)
                .frame(width: 40, height: 40)
                .background(Geist.Palette.amber100, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Geist.heading(.title3))
                    .foregroundStyle(Geist.text)
                    .accessibilityAddTraits(.isHeader)
                message
                    .font(Geist.body(.callout))
                    .foregroundStyle(Geist.Palette.gray800)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var isVaultProblem: Bool {
        reason?.kind == .vaultUnreachable || reason?.kind == .permissionDenied
            || problem.failureCategory == .destinationUnavailable
            || problem.failureCategory == .permissionDenied
    }

    private var title: String {
        if isHeadingProblem { return String(localized: "Heading not found") }
        if isVaultProblem { return String(localized: "Can’t reach your vault") }
        return String(localized: "Couldn’t deliver this capture")
    }

    private var message: Text {
        if isHeadingProblem, let heading = reason?.headingMarkdown {
            return Text("\(noteName) no longer has a ")
                + Text(verbatim: heading).font(Geist.mono(size: 13.5, relativeTo: .callout))
                + Text(" section. Your capture is safe on this iPhone.")
        }
        if isVaultProblem {
            return Text("\(problem.destinationName) can’t be opened right now. Your capture is safe on this iPhone. Re-grant folder access from Activity to deliver.")
        }
        let detail = problem.failureCategory?.displayName ?? String(localized: "Delivery failed")
        return Text("\(detail). Your capture is safe on this iPhone.")
    }

    private var captureCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: "\(problem.displayRouteName.uppercased()) · \(problem.createdAt.formatted(.dateTime.hour().minute()))")
                Spacer()
                Text(problem.itemCount == 1 ? "1 ITEM" : "\(problem.itemCount) ITEMS")
            }
            .font(Geist.mono(size: 11, relativeTo: .caption))
            .foregroundStyle(Geist.muted)
            Text(verbatim: problem.preview)
                .font(Geist.mono(size: 12.5, relativeTo: .footnote))
                .lineSpacing(3)
                .foregroundStyle(Geist.text)
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, Geist.Spacing.three)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Geist.border, lineWidth: 1))
    }

    private var actions: some View {
        VStack(spacing: Geist.Spacing.two) {
            if isHeadingProblem, let heading = reason?.headingMarkdown, let missingHeading {
                Button {
                    performPaid { try await deliver(beneath: missingHeading, create: true) }
                } label: {
                    PaidAccessLabel("Add “\(heading)” and deliver", isLocked: isReadOnly)
                }
                .buttonStyle(GeistButtonStyle(variant: isReadOnly ? .secondary : .primary))
            } else {
                Button {
                    performPaid { try await retry() }
                } label: {
                    PaidAccessLabel("Retry delivery", isLocked: isReadOnly)
                }
                .buttonStyle(GeistButtonStyle(variant: isReadOnly ? .secondary : .primary))
            }

            HStack(spacing: Geist.Spacing.two) {
                if isHeadingProblem, isReadOnly {
                    Button { showsPlans = true } label: {
                        secondaryLabel(String(localized: "Pick a heading"), isLocked: true)
                    }
                    .buttonStyle(.plain)
                } else if isHeadingProblem {
                    Menu {
                        if headings.isEmpty {
                            Text("No headings in \(noteName)")
                        } else {
                            ForEach(Array(headings.enumerated()), id: \.offset) { _, heading in
                                Button(String(repeating: "#", count: heading.level ?? 2) + " " + heading.title) {
                                    performPaid { try await deliver(beneath: heading, create: false) }
                                }
                            }
                        }
                    } label: {
                        secondaryLabel(String(localized: "Pick a heading"))
                    }
                }
                Button {
                    performPaid { try await sendToDefault() }
                } label: {
                    secondaryLabel(
                        String(localized: "Send to \(defaultRouteName ?? String(localized: "Inbox"))"),
                        isLocked: isReadOnly
                    )
                }
                .buttonStyle(.plain)
                .disabled(problem.destinationName == defaultRouteName)
            }

            HStack(spacing: 20) {
                Button("Copy Markdown") {
                    UIPasteboard.general.string = problem.preview
                }
                .foregroundStyle(Geist.accentText)
                Button("Discard", role: .destructive) {
                    showsDiscardConfirmation = true
                }
                .foregroundStyle(Geist.error)
            }
            .font(Geist.body(.subheadline).weight(.medium))
            .buttonStyle(.plain)
            .frame(minHeight: 40)
            .padding(.top, 4)
        }
    }

    private func secondaryLabel(_ title: String, isLocked: Bool = false) -> some View {
        HStack(spacing: 6) {
            if isLocked {
                Image(systemName: "lock")
                    .accessibilityHidden(true)
            }
            Text(title)
        }
            .font(Geist.label(.subheadline))
            .foregroundStyle(Geist.text)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Geist.card, in: Capsule())
            .overlay(Capsule().stroke(Geist.border, lineWidth: 1))
            .contentShape(Capsule())
            .accessibilityElement(children: .combine)
            .accessibilityHint(isLocked ? usageTracker.readOnlyHint : Text(verbatim: ""))
    }

    // MARK: Actions

    private func load() async {
        guard let captureRootURL else { return }
        defaultRouteName = await CaptureInboxRecovery.defaultDestination(captureRootURL: captureRootURL)?.name
        if isHeadingProblem, let path = reason?.relativeNotePath {
            headings = await CaptureInboxRecovery.headings(
                relativeNotePath: path,
                destinationID: problem.destinationID,
                captureRootURL: captureRootURL
            )
        }
    }

    /// Delivery, retry and route changes require paid access; read-only
    /// users get the paywall instead.
    private func performPaid(_ action: @escaping () async throws -> Void) {
        usageTracker.requirePaidAccess(otherwise: { showsPlans = true }) {
            perform(action)
        }
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            defer { isWorking = false }
            do {
                try await action()
                await onResolved()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deliver(beneath heading: CaptureHeadingSelector, create: Bool) async throws {
        guard let captureRootURL else { return }
        try await CaptureInboxRecovery.deliver(
            requestID: problem.requestID,
            beneath: heading,
            createIfMissing: create,
            captureRootURL: captureRootURL
        )
        if fixesRoute {
            try await CaptureInboxRecovery.fixRoute(
                destinationID: problem.destinationID,
                presetID: problem.routeID,
                heading: heading,
                createIfMissing: true,
                captureRootURL: captureRootURL
            )
        }
    }

    private func retry() async throws {
        guard let captureRootURL else { return }
        try await CaptureInboxRecovery.retry(requestID: problem.requestID, captureRootURL: captureRootURL)
    }

    private func sendToDefault() async throws {
        guard let captureRootURL else { return }
        try await CaptureInboxRecovery.sendToDefaultRoute(requestID: problem.requestID, captureRootURL: captureRootURL)
    }

    private func discard() async throws {
        guard let captureRootURL else { return }
        try await CaptureInboxRecovery.discard(requestID: problem.requestID, captureRootURL: captureRootURL)
    }
}

/// Square accent checkbox matching the Signal recovery sheet.
struct SignalCheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20))
                    .foregroundStyle(configuration.isOn ? Geist.accent : Geist.borderHi)
                configuration.label
                    .multilineTextAlignment(.leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}
