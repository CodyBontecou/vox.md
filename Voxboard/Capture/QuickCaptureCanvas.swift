import SwiftUI
import QuickLook

/// A fixed viewport keeps the high-priority editor from collapsing guidance.
/// Larger text scrolls inside it; the composer and Send remain on screen.
struct QuickCaptureFirstNoteGuide: View {
    let step: FirstNoteGuide.Step
    let action: () -> Void
    let dismiss: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var needsMoreRoom: Bool {
        if case .saved = step { return true }
        return dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        ScrollView {
            FirstNoteGuide(step: step, action: action, dismiss: dismiss)
        }
        .frame(height: needsMoreRoom ? 240 : 180)
    }
}

struct FirstNoteDocument: Identifiable {
    let id = UUID()
    let noteURL: URL
    let rootURL: URL
}

/// Quick Look opens the actual saved file while retaining its folder access.
struct FirstNoteDocumentPreview: UIViewControllerRepresentable {
    let document: FirstNoteDocument

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        private let document: FirstNoteDocument
        private let didAccess: Bool

        init(document: FirstNoteDocument) {
            self.document = document
            didAccess = document.rootURL.startAccessingSecurityScopedResource()
        }

        deinit {
            if didAccess { document.rootURL.stopAccessingSecurityScopedResource() }
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            document.noteURL as NSURL
        }
    }
}

/// Layout only. Slots are deliberately concrete, not `Content: View` generics:
/// a new feature inside a slot cannot enlarge the canvas's metadata type.
struct QuickCaptureCanvas: View {
    let showsDestination: Bool
    let showsWatchStatus: Bool
    let showsAttachments: Bool
    let header: CaptureViewSection
    let ocrProgress: CaptureViewSection
    let destination: CaptureViewSection
    let watchStatus: CaptureViewSection
    let composer: CaptureViewSection
    let attachments: CaptureViewSection
    let controls: CaptureViewSection
    let keyboardGuidance: CaptureViewSection
    let error: CaptureViewSection
    let fileExport: CaptureViewSection
    let sentToast: CaptureViewSection
    var showsPreview = false
    var preview = CaptureViewSection { EmptyView() }

    var body: some View {
        ZStack(alignment: .top) {
            Geist.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                // Inline under the header (Signal "Capture states"): a
                // floating error used to cover the route picker, Activity
                // and Settings until it was dismissed.
                error
                ocrProgress
                if showsDestination {
                    destination
                        .padding(.horizontal, Geist.Spacing.four)
                        .padding(.bottom, Geist.Spacing.two)
                }
                if showsWatchStatus {
                    watchStatus
                        .padding(.horizontal, Geist.Spacing.four)
                        .padding(.bottom, Geist.Spacing.two)
                }
                AdaptiveCaptureWorkspace(
                    showsPreview: showsPreview,
                    primary: CaptureViewSection { composer.layoutPriority(1) },
                    preview: preview
                )
                if showsAttachments {
                    attachments
                }
            }
            // zIndex belongs to the outer siblings, not inside erased wrappers.
            keyboardGuidance.zIndex(5)
            fileExport.zIndex(4)
            sentToast.zIndex(4)
        }
        // Keep the controls in the keyboard-aware safe area; a retained first
        // responder can cover controls placed inside the flexible editor stack.
        .safeAreaInset(edge: .bottom, spacing: 0) { controls }
    }
}

struct QuickCaptureOCRProgress: View {
    var message: LocalizedStringKey = "Extracting text on this device…"

    init(_ message: LocalizedStringKey = "Extracting text on this device…") {
        self.message = message
    }

    var body: some View {
        HStack(spacing: Geist.Spacing.two) {
            ProgressView().controlSize(.small)
            Text(message)
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
            Spacer()
        }
        .padding(.horizontal, Geist.Spacing.four)
        .frame(minHeight: Geist.ControlHeight.medium)
        .background(Geist.card, in: Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous).stroke(Geist.border, lineWidth: 1))
        .padding(.horizontal, Geist.Spacing.four)
        .padding(.bottom, Geist.Spacing.two)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("capture_ocr_progress")
    }
}

/// Pure presentation: restoration and the five-second window stay owned by the
/// coordinator. A nominal View keeps the Undo branch out of the canvas's type.
struct QuickCaptureSentToast: View {
    let offersUndo: Bool
    let undo: () -> Void

    var body: some View {
        HStack(spacing: Geist.Spacing.three) {
            Label("Capture Sent", systemImage: "checkmark.circle.fill")
            if offersUndo {
                Button(action: undo) {
                    Text("Undo")
                        .fontWeight(.semibold)
                        .underline()
                        .padding(.horizontal, Geist.Spacing.two)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Undo send and restore the Capture to this draft")
                .accessibilityHint("The note already sent to your vault is kept.")
                .accessibilityIdentifier("capture_sent_toast_undo")
            }
        }
        .font(Geist.label())
        .foregroundStyle(Geist.bg)
        .padding(.horizontal, Geist.Spacing.four + 2)
        .frame(height: Geist.ControlHeight.medium)
        .background(Geist.text)
        .clipShape(Capsule(style: .continuous))
        .padding(.top, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        // Keep the Undo action individually discoverable to accessibility.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture_sent_toast")
    }
}

// MARK: - Signal capture presentation

/// The wide ink "Speak" capsule shown in the idle capture bar. Presentation
/// only: the coordinator owns the tap/long-press gesture and accessibility.
struct CaptureSpeakCapsuleLabel: View {
    let title: String
    let systemImage: String
    let modeSymbol: String?
    var isDimmed = false
    var showsProgress = false

    var body: some View {
        HStack(spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(isDimmed ? Geist.muted : Geist.bg)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 20, weight: .semibold))
            }
            Text(verbatim: title)
                .font(.custom("Geist-SemiBold", size: 17, relativeTo: .body))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let modeSymbol {
                Image(systemName: modeSymbol)
                    .font(.system(size: 12, weight: .semibold))
                    .opacity(0.7)
            }
        }
        .foregroundStyle(isDimmed ? Geist.muted : Geist.bg)
        .frame(maxWidth: .infinity)
        .frame(height: Geist.ControlHeight.hero)
        .background(isDimmed ? Geist.well : Geist.text, in: Capsule(style: .continuous))
        .contentShape(Capsule(style: .continuous))
    }
}

/// Big ring Stop control used in the live recording panel.
struct CaptureStopRingLabel: View {
    var diameter: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(Geist.text, lineWidth: 3)
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Geist.recording)
                .frame(width: diameter * 0.39, height: diameter * 0.39)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
    }
}

/// Segmented "Add to draft / Send on stop" capsule from the live recording
/// artboard, bound to the existing persisted recording result mode.
struct CaptureRecordingModeSegment: View {
    @Binding var isDraft: Bool
    let isLocked: Bool

    var body: some View {
        HStack(spacing: 4) {
            segment(String(localized: "Add to draft"), selected: isDraft) { isDraft = true }
            segment(String(localized: "Send on stop"), selected: !isDraft) { isDraft = false }
        }
        .padding(4)
        .background(Geist.Palette.gray200, in: Capsule(style: .continuous))
        .disabled(isLocked)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "When I stop"))
    }

    private func segment(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.custom(selected ? "Geist-SemiBold" : "Geist-Medium", size: 14, relativeTo: .subheadline))
                .foregroundStyle(selected ? Geist.bg : Geist.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(selected ? Geist.text : Color.clear, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Recording header: red dot, mono 44pt timer and a quiet status line.
struct CaptureLiveTimerHeader: View {
    let duration: String
    let status: String
    let isPaused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(isPaused ? Geist.muted : Geist.recording)
                .frame(width: 10, height: 10)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 6 }
            Text(verbatim: duration)
                .font(.custom("GeistMono-Medium", size: 44, relativeTo: .largeTitle))
                .monospacedDigit()
                .tracking(-0.9)
                .foregroundStyle(Geist.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(verbatim: status)
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Rounded tile for one staged attachment. Audio clips use a wider voice card.
struct CaptureAttachmentTile: View {
    let label: String
    let systemImage: String
    let isAudio: Bool
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isAudio ? Geist.bg : Geist.text)
                .frame(width: 36, height: 36)
                .background(isAudio ? Geist.text : Geist.well, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                if isAudio {
                    CaptureStaticWaveform()
                }
                Text(verbatim: label)
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: isAudio ? 200 : 150, alignment: .leading)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Geist.muted)
                    .frame(width: 28, height: 28)
                    .background(Geist.bg, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(label)")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 64)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        )
    }
}

private struct CaptureStaticWaveform: View {
    private static let heights: [CGFloat] = [6, 10, 16, 9, 20, 14, 18, 12, 8, 16, 18, 14, 10, 6, 12, 18, 14, 8, 14, 16, 12, 8]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(Self.heights.enumerated()), id: \.offset) { _, height in
                Capsule()
                    .fill(Geist.Palette.gray500)
                    .frame(width: 3, height: height)
            }
        }
        .frame(height: 20)
        .accessibilityHidden(true)
    }
}

/// Small Signal status card used for capture errors and setup prompts.
struct CaptureStatusCard: View {
    let title: String?
    let message: String
    var tint: Color = Geist.warning
    var actionTitle: String?
    var action: (() -> Void)?
    var dismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(tint)
                .frame(width: 10, height: 10)
                .padding(.top, 5)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                if let title {
                    Text(verbatim: title)
                        .font(.custom("Geist-SemiBold", size: 15, relativeTo: .subheadline))
                        .foregroundStyle(Geist.text)
                }
                Text(verbatim: message)
                    .font(Geist.caption(.subheadline))
                    .foregroundStyle(title == nil ? Geist.text : Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle, let action {
                    Button(action: action) {
                        Text(verbatim: actionTitle)
                            .font(.custom("Geist-SemiBold", size: 13.5, relativeTo: .footnote))
                            .foregroundStyle(Geist.bg)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(Geist.text, in: Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Geist.muted)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss error")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Geist.Palette.amber400, lineWidth: 1)
        )
    }
}
