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
            Geist.Palette.background100.ignoresSafeArea()
            VStack(spacing: 0) {
                ocrProgress
                if showsDestination {
                    destination
                    GeistDivider()
                }
                if showsWatchStatus {
                    watchStatus
                    GeistDivider()
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
            error.zIndex(3)
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
        .padding(.horizontal, Geist.Spacing.three)
        .frame(minHeight: Geist.ControlHeight.medium)
        .background(Geist.Palette.background200)
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
        .foregroundStyle(Geist.Palette.background100)
        .padding(.horizontal, Geist.Spacing.four)
        .frame(height: Geist.ControlHeight.medium)
        .background(Geist.Palette.gray1000)
        .clipShape(Capsule())
        .padding(.top, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        // Keep the Undo action individually discoverable to accessibility.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("capture_sent_toast")
    }
}
