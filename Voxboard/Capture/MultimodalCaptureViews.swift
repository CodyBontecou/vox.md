import Photos
import PhotosUI
import ImageIO
import PencilKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Vision
import VisionKit
import VoxboardShared

/// Presents UIKit's native Files browser directly. SwiftUI's `fileImporter`
/// can fail to complete on physical iPhones, while the underlying document
/// picker remains reliable.
struct CaptureFilePicker: UIViewControllerRepresentable {
    var contentTypes: [UTType]
    var allowsMultipleSelection: Bool
    var onPick: ([URL]) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: contentTypes,
            asCopy: true
        )
        picker.allowsMultipleSelection = allowsMultipleSelection
        picker.shouldShowFileExtensions = true
        picker.delegate = context.coordinator
        picker.accessibilityLabel = String(localized: "Choose files to attach")
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIDocumentPickerViewController,
        context: Context
    ) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: CaptureFilePicker

        init(parent: CaptureFilePicker) {
            self.parent = parent
        }

        func documentPicker(
            _ controller: UIDocumentPickerViewController,
            didPickDocumentsAt urls: [URL]
        ) {
            parent.onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}

struct CaptureCameraPicker: UIViewControllerRepresentable {
    var onCapture: (Data) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CaptureCameraPicker
        init(parent: CaptureCameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage,
                  let data = image.jpegData(compressionQuality: 0.9) else {
                parent.onCancel()
                return
            }
            parent.onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

struct CaptureDocumentScanner: UIViewControllerRepresentable {
    var onScan: ([Data]) -> Void
    var onCancel: () -> Void
    var onError: (Error) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: CaptureDocumentScanner
        init(parent: CaptureDocumentScanner) { self.parent = parent }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFinishWith scan: VNDocumentCameraScan
        ) {
            let pages = (0..<scan.pageCount).compactMap {
                scan.imageOfPage(at: $0).jpegData(compressionQuality: 0.9)
            }
            parent.onScan(pages)
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(
            _ controller: VNDocumentCameraViewController,
            didFailWithError error: Error
        ) {
            parent.onError(error)
        }
    }
}

private struct CapturedJournalPage: Identifiable {
    let id = UUID()
    let imageData: Data
    let thumbnail: UIImage?
}

/// Captures journal pages only when the user presses the native camera shutter.
/// This intentionally avoids VisionKit's automatic document capture behavior.
struct CaptureManualJournalPages: View {
    var maxPageCount = 10
    var onCapture: ([Data]) -> Void
    var onCancel: () -> Void

    @State private var pages: [CapturedJournalPage] = []
    @State private var presentsCamera = false
    @State private var didPresentInitialCamera = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if pages.isEmpty {
                    ContentUnavailableView(
                        "No Pages Captured",
                        systemImage: "camera.viewfinder",
                        description: Text("Tap Capture Page, then press the camera shutter when the page is ready.")
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    capturedPageStrip
                    Spacer(minLength: 0)
                }

                VStack(spacing: 12) {
                    Text(pageCountLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("journal_capture_page_count")

                    Button {
                        presentsCamera = true
                    } label: {
                        Label(captureButtonTitle, systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(pages.count >= maxPageCount)
                    .accessibilityIdentifier("journal_capture_page_button")

                    if !pages.isEmpty {
                        Button("Remove Last Page", role: .destructive) {
                            pages.removeLast()
                        }
                        .accessibilityIdentifier("journal_capture_remove_last")
                    }
                }
            }
            .padding()
            .navigationTitle("Journal Pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Pages") {
                        onCapture(pages.map(\.imageData))
                    }
                    .disabled(pages.isEmpty)
                    .accessibilityIdentifier("journal_capture_use_pages")
                }
            }
            .fullScreenCover(isPresented: $presentsCamera) {
                CaptureCameraPicker(
                    onCapture: { data in
                        presentsCamera = false
                        appendPage(data)
                    },
                    onCancel: {
                        presentsCamera = false
                    }
                )
                .ignoresSafeArea()
            }
            .task {
                guard !didPresentInitialCamera else { return }
                didPresentInitialCamera = true
                await Task.yield()
                presentsCamera = true
            }
        }
    }

    private var capturedPageStrip: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    ZStack(alignment: .topTrailing) {
                        Group {
                            if let thumbnail = page.thumbnail {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Rectangle()
                                    .fill(.quaternary)
                                    .overlay {
                                        Image(systemName: "doc")
                                            .foregroundStyle(.secondary)
                                    }
                            }
                        }
                        .frame(width: 132, height: 176)
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Text("\(index + 1)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(7)
                            .background(.black.opacity(0.72), in: Circle())
                            .padding(7)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Journal page \(index + 1)")
                }
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private var pageCountLabel: String {
        if pages.count >= maxPageCount {
            return String(localized: "\(maxPageCount)-page limit reached")
        }
        return String(localized: "\(pages.count) of \(maxPageCount) pages captured")
    }

    private var captureButtonTitle: String {
        pages.isEmpty ? String(localized: "Capture Page") : String(localized: "Capture Next Page")
    }

    private func appendPage(_ data: Data) {
        guard pages.count < maxPageCount else { return }
        let thumbnail = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 264, height: 352))
        pages.append(CapturedJournalPage(imageData: data, thumbnail: thumbnail))
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Page \(pages.count) captured")
        )
    }
}

struct ProcessedDocumentScan: Sendable {
    var pageImages: [Data]
    var pdfData: Data
    var extractedText: String?
}

enum JournalImageOCRProcessorError: Error, Equatable, LocalizedError, Sendable {
    case noImages
    case unreadableImage(page: Int)
    case noTextRecognized

    var errorDescription: String? {
        switch self {
        case .noImages:
            return String(localized: "Choose at least one journal image.")
        case .unreadableImage(let page):
            return String(localized: "Journal page \(page) could not be read as an image.")
        case .noTextRecognized:
            return String(localized: "No text was found in those journal images. Try brighter, straighter photos with the writing filling the frame.")
        }
    }
}

enum JournalImageOCRProcessor {
    static func process(pageImages: [Data]) async throws -> String {
        guard !pageImages.isEmpty else { throw JournalImageOCRProcessorError.noImages }
        let pageTexts = try await VisionPageTextRecognizer.recognizePageTexts(
            in: pageImages,
            unreadableImagePolicy: .fail,
            automaticallyDetectsLanguage: true
        )
        let markdown = CaptureOCRMarkdownFormatter().render(pageTexts: pageTexts)
        guard !markdown.isEmpty else { throw JournalImageOCRProcessorError.noTextRecognized }
        return markdown
    }
}

enum DocumentScanProcessor {
    static func process(pageImages: [Data]) async throws -> ProcessedDocumentScan {
        // Preserve the attachment scanner's established best-effort OCR behavior:
        // unreadable pages still belong in its PDF and must not abort staging.
        let pageTexts = try await VisionPageTextRecognizer.recognizePageTexts(
            in: pageImages,
            unreadableImagePolicy: .skip,
            automaticallyDetectsLanguage: false
        )
        let text = CaptureOCRMarkdownFormatter().render(pageTexts: pageTexts)
        let pdf = try makePDF(from: pageImages)
        return ProcessedDocumentScan(
            pageImages: pageImages,
            pdfData: pdf,
            extractedText: text.isEmpty ? nil : text
        )
    }

    @MainActor
    private static func makePDF(from pages: [Data]) throws -> Data {
        let images = pages.compactMap(UIImage.init(data:))
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        return renderer.pdfData { context in
            for image in images {
                context.beginPage()
                let inset = pageRect.insetBy(dx: 24, dy: 24)
                let scale = min(inset.width / image.size.width, inset.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let origin = CGPoint(x: inset.midX - size.width / 2, y: inset.midY - size.height / 2)
                image.draw(in: CGRect(origin: origin, size: size))
            }
        }
    }
}

private enum VisionPageTextRecognizer {
    enum UnreadableImagePolicy: Sendable {
        case skip
        case fail
    }

    static func recognizePageTexts(
        in pages: [Data],
        unreadableImagePolicy: UnreadableImagePolicy,
        automaticallyDetectsLanguage: Bool
    ) async throws -> [String] {
        try await Task.detached(priority: .userInitiated) {
            var pageTexts: [String] = []
            pageTexts.reserveCapacity(pages.count)

            for (index, data) in pages.enumerated() {
                guard let image = UIImage(data: data), let cgImage = image.cgImage else {
                    switch unreadableImagePolicy {
                    case .skip:
                        continue
                    case .fail:
                        throw JournalImageOCRProcessorError.unreadableImage(page: index + 1)
                    }
                }

                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = automaticallyDetectsLanguage

                let handler = VNImageRequestHandler(
                    cgImage: cgImage,
                    orientation: CGImagePropertyOrientation(image.imageOrientation),
                    options: [:]
                )
                try handler.perform([request])

                let lines = (request.results ?? []).compactMap {
                    $0.topCandidates(1).first?.string
                }
                pageTexts.append(lines.joined(separator: "\n"))
            }

            return pageTexts
        }.value
    }
}

private extension CGImagePropertyOrientation {
    nonisolated init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

struct CaptureSketchEditor: View {
    var onSave: (Data, Data) -> Void
    var onCancel: () -> Void
    @State private var drawing = PKDrawing()

    /// PencilKit data plus a 2x PNG preview of the drawn area, as staged by
    /// `QuickCaptureViewModel.stageSketch`. Shared with the inline iPad canvas.
    static func sketchPayload(for drawing: PKDrawing) -> (drawing: Data, preview: Data)? {
        let bounds = drawing.bounds.isEmpty
            ? CGRect(x: 0, y: 0, width: 1024, height: 768)
            : drawing.bounds.insetBy(dx: -24, dy: -24)
        let preview = drawing.image(from: bounds, scale: 2)
        guard let png = preview.pngData() else { return nil }
        return (drawing.dataRepresentation(), png)
    }

    var body: some View {
        NavigationStack {
            PencilCanvas(drawing: $drawing)
                .background(Color.white)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Sketch")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            guard let payload = Self.sketchPayload(for: drawing) else { return }
                            onSave(payload.drawing, payload.preview)
                        }
                        .disabled(drawing.strokes.isEmpty)
                    }
                }
        }
    }
}

private struct PencilCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator { Coordinator(drawing: $drawing) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawing = drawing
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .white
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        DispatchQueue.main.async {
            let picker = PKToolPicker()
            picker.setVisible(true, forFirstResponder: canvas)
            picker.addObserver(canvas)
            canvas.becomeFirstResponder()
            context.coordinator.toolPicker = picker
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing { canvas.drawing = drawing }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        var toolPicker: PKToolPicker?
        init(drawing: Binding<PKDrawing>) { _drawing = drawing }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { drawing = canvasView.drawing }
    }
}

// MARK: - Attach sheet (Signal)

/// One attach tool. The coordinator runs it after the sheet has dismissed so the
/// follow-up picker/camera sheet never races this one.
enum CaptureAttachAction: String, CaseIterable, Identifiable {
    case camera, scan, journal, sketch, file, link, location, screenshot, photos, journalPhotos

    var id: String { rawValue }

    /// Revised Attach sheet, ATTACH grid (3 × 2). Scan and Journal page sit in
    /// their own READ INTO MARKDOWN row.
    static let gridActions: [CaptureAttachAction] = [
        .camera, .file, .sketch, .link, .location, .screenshot,
    ]

    var title: String {
        switch self {
        case .camera: return String(localized: "Camera")
        case .scan: return String(localized: "Scan")
        case .journal: return String(localized: "Journal")
        case .sketch: return String(localized: "Sketch")
        case .file: return String(localized: "File")
        case .link: return String(localized: "Link")
        case .location: return String(localized: "Location")
        case .screenshot: return String(localized: "Screenshot")
        case .photos: return String(localized: "Photo")
        case .journalPhotos: return String(localized: "Choose Journal Photos")
        }
    }

    var systemImage: String {
        switch self {
        case .camera: return "camera"
        case .scan: return "doc.viewfinder"
        case .journal: return "book.closed"
        case .sketch: return "pencil.tip"
        case .file: return "doc"
        case .link: return "link"
        case .location: return "location"
        case .screenshot: return "rectangle.inset.filled.and.person.filled"
        case .photos: return "photo"
        case .journalPhotos: return "photo.on.rectangle"
        }
    }
}

/// Lets a limited-access Photos user extend the selection Vox.md can read.
@MainActor
private func presentLimitedLibraryPicker() {
    guard let scene = UIApplication.shared.connectedScenes
        .compactMap({ $0 as? UIWindowScene })
        .first(where: { $0.activationState == .foregroundActive }),
          var presenter = scene.keyWindow?.rootViewController else { return }
    while let presented = presenter.presentedViewController { presenter = presented }
    PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
}

/// What the clipboard holds, read without triggering the paste prompt:
/// `hasURLs` / `hasImages` only report presence, and pattern detection says
/// whether copied text looks like a web link. The content itself is read
/// through `PasteButton`, which needs no prompt.
enum CaptureClipboardKind: Equatable {
    case link, image

    static func detect() async -> CaptureClipboardKind? {
        let pasteboard = UIPasteboard.general
        if pasteboard.hasURLs { return .link }
        if pasteboard.hasImages { return .image }
        guard pasteboard.hasStrings,
              let patterns = try? await pasteboard.detectedPatterns(for: [\.probableWebURL]),
              patterns.contains(\.probableWebURL) else { return nil }
        return .link
    }

    var contentTypes: [UTType] {
        switch self {
        case .link: [.url, .plainText]
        case .image: [.image]
        }
    }
}

/// Attach sheet (Signal "Attach sheet · revised"): where the note lands, a
/// clipboard shortcut, multi-select recent photos, the two tools that read
/// text into Markdown, then the remaining attachments.
struct CaptureAttachSheet: View {
    let isProcessingMedia: Bool
    let canExtractText: Bool
    let isAvailable: (CaptureAttachAction) -> Bool
    let choose: (CaptureAttachAction) -> Void
    /// "Meeting Notes", shown with `destinationPath` under the title.
    var routeName: String? = nil
    var destinationPath: String? = nil
    var recentPhotos: CaptureRecentPhotosModel?
    var pickRecentPhotos: (([PHAsset]) -> Void)?
    var paste: (([NSItemProvider]) -> Void)?

    @State private var selectedPhotoIDs: [String] = []
    @State private var clipboard: CaptureClipboardKind?
    @State private var contentHeight: CGFloat = 560

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let clipboard, paste != nil {
                    clipboardCard(clipboard)
                }
                if let recentPhotos, pickRecentPhotos != nil {
                    recentSection(recentPhotos)
                }
                readIntoMarkdownSection
                attachSection
                if !selectedPhotoIDs.isEmpty {
                    addSelectedPhotosButton
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Geist.bg.ignoresSafeArea())
        .presentationDetents([.height(contentHeight), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
        .task { clipboard = await CaptureClipboardKind.detect() }
        .onReceive(NotificationCenter.default.publisher(for: UIPasteboard.changedNotification)) { _ in
            Task { clipboard = await CaptureClipboardKind.detect() }
        }
    }

    // MARK: Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add to note")
                .font(.custom("Geist-SemiBold", size: 20, relativeTo: .title3))
                .foregroundStyle(Geist.text)
            if let line = destinationLine {
                Text(verbatim: line)
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var destinationLine: String? {
        switch (routeName, destinationPath) {
        case let (name?, path?) where name != path: "→ \(name) · \(path)"
        case let (name?, _): "→ \(name)"
        case let (nil, path?): "→ \(path)"
        default: nil
        }
    }

    private func clipboardCard(_ kind: CaptureClipboardKind) -> some View {
        HStack(spacing: 12) {
            Image(systemName: kind == .link ? "link" : "photo")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Geist.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind == .link ? "Paste copied link" : "Paste copied image")
                    .font(.custom("Geist-SemiBold", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Geist.text)
                Text("From your clipboard")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            PasteButton(supportedContentTypes: kind.contentTypes) { providers in
                paste?(providers)
            }
            .labelStyle(.titleOnly)
            .buttonBorderShape(.capsule)
            .tint(Geist.accent)
            .disabled(isProcessingMedia)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Geist.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Geist.accent.opacity(0.25), lineWidth: 1)
        )
        .accessibilityIdentifier("capture_attach_clipboard")
    }

    private func recentSection(_ model: CaptureRecentPhotosModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel("RECENT")
                Spacer()
                Text(selectedPhotoIDs.isEmpty
                     ? String(localized: "Tap to pick one or more")
                     : String(localized: "\(selectedPhotoIDs.count) selected"))
                    .font(Geist.caption(.caption2))
                    .foregroundStyle(Geist.muted)
                    .padding(.trailing, 4)
            }
            CaptureRecentPhotosStrip(
                model: model,
                isDisabled: isProcessingMedia,
                selection: selectedPhotoIDs,
                toggle: { asset in
                    if let index = selectedPhotoIDs.firstIndex(of: asset.localIdentifier) {
                        selectedPhotoIDs.remove(at: index)
                    } else {
                        selectedPhotoIDs.append(asset.localIdentifier)
                    }
                },
                showAllPhotos: { choose(.photos) },
                manageLimitedAccess: presentLimitedLibraryPicker
            )
        }
    }

    private var readIntoMarkdownSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("READ INTO MARKDOWN")
            HStack(spacing: 8) {
                Button { choose(.scan) } label: {
                    readTile(title: String(localized: "Scan"),
                             subtitle: String(localized: "Documents, whiteboards"),
                             systemImage: CaptureAttachAction.scan.systemImage)
                }
                .buttonStyle(.plain)
                .attachAvailability(isAvailable(.scan), processing: isProcessingMedia)
                .accessibilityIdentifier("capture_attach_scan")

                Menu {
                    Button { choose(.journal) } label: {
                        Label("Capture Journal Pages", systemImage: "camera.viewfinder")
                    }
                    .disabled(!isAvailable(.journal))
                    Button { choose(.journalPhotos) } label: {
                        Label(CaptureAttachAction.journalPhotos.title,
                              systemImage: CaptureAttachAction.journalPhotos.systemImage)
                    }
                    .disabled(!isAvailable(.journalPhotos))
                } label: {
                    readTile(title: String(localized: "Journal page"),
                             subtitle: String(localized: "Camera or photos"),
                             systemImage: CaptureAttachAction.journal.systemImage)
                }
                .attachAvailability(canExtractText, processing: isProcessingMedia)
                .accessibilityIdentifier("capture_attach_journal")
            }
            Text("Read on this device. The original image is kept alongside.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    private var attachSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("ATTACH")
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CaptureAttachAction.gridActions) { action in
                    Button {
                        choose(action)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 16, weight: .regular))
                                .frame(width: 20)
                            Text(verbatim: action.title)
                                .font(.custom("Geist-Medium", size: 13, relativeTo: .footnote))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(Geist.text)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Geist.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Geist.border, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .attachAvailability(isAvailable(action), processing: isProcessingMedia)
                    .accessibilityIdentifier("capture_attach_\(action.rawValue)")
                }
            }
        }
    }

    private var addSelectedPhotosButton: some View {
        Button {
            guard let recentPhotos else { return }
            let byID = Dictionary(
                recentPhotos.assets.map { ($0.localIdentifier, $0) },
                uniquingKeysWith: { first, _ in first }
            )
            let assets = selectedPhotoIDs.compactMap { byID[$0] }
            selectedPhotoIDs = []
            pickRecentPhotos?(assets)
        } label: {
            Text(selectedPhotoIDs.count == 1
                 ? String(localized: "Add 1 photo")
                 : String(localized: "Add \(selectedPhotoIDs.count) photos"))
                .font(.custom("Geist-SemiBold", size: 16, relativeTo: .body))
                .foregroundStyle(Geist.bg)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Geist.text, in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isProcessingMedia)
        .accessibilityIdentifier("capture_attach_add_photos")
    }

    // MARK: Pieces

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Geist.mono(size: 10.5, relativeTo: .caption2))
            .tracking(0.6)
            .foregroundStyle(Geist.muted)
            .padding(.horizontal, 4)
    }

    private func readTile(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .regular))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title)
                    .font(.custom("Geist-SemiBold", size: 14, relativeTo: .subheadline))
                    .foregroundStyle(Geist.text)
                Text(verbatim: subtitle)
                    .font(Geist.caption(.caption2))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Geist.text)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    /// Dims and disables an Attach tool that is unavailable or busy.
    func attachAvailability(_ isAvailable: Bool, processing: Bool) -> some View {
        disabled(processing || !isAvailable)
            .opacity(processing || !isAvailable ? 0.4 : 1)
    }
}
