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

    static let gridActions: [CaptureAttachAction] = [
        .camera, .scan, .journal, .sketch, .file, .link, .location, .screenshot,
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

struct CaptureAttachSheet: View {
    let isProcessingMedia: Bool
    let canExtractText: Bool
    let isAvailable: (CaptureAttachAction) -> Bool
    let choose: (CaptureAttachAction) -> Void
    var recentPhotos: CaptureRecentPhotosModel?
    var pickRecentPhoto: ((PHAsset) -> Void)?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Add to note")
                    .font(.custom("Geist-SemiBold", size: 20, relativeTo: .title3))
                    .foregroundStyle(Geist.text)
                Spacer()
                Button {
                    choose(.photos)
                } label: {
                    Text("All photos")
                        .font(Geist.label(.subheadline))
                        .foregroundStyle(Geist.accentText)
                        .frame(height: 32)
                }
                .buttonStyle(.plain)
                .disabled(isProcessingMedia)
            }
            .padding(.horizontal, 4)

            if let recentPhotos, let pickRecentPhoto {
                CaptureRecentPhotosStrip(
                    model: recentPhotos,
                    isDisabled: isProcessingMedia,
                    pick: pickRecentPhoto,
                    manageLimitedAccess: presentLimitedLibraryPicker
                )
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(CaptureAttachAction.gridActions) { action in
                    Button {
                        choose(action)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: action.systemImage)
                                .font(.system(size: 20, weight: .regular))
                            Text(verbatim: action.title)
                                .font(.custom("Geist-Medium", size: 12, relativeTo: .caption))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .foregroundStyle(Geist.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 84)
                        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Geist.border, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isProcessingMedia || !isAvailable(action))
                    .opacity(isProcessingMedia || !isAvailable(action) ? 0.4 : 1)
                    .accessibilityIdentifier("capture_attach_\(action.rawValue)")
                }
            }

            Button {
                choose(.journalPhotos)
            } label: {
                Label(CaptureAttachAction.journalPhotos.title, systemImage: CaptureAttachAction.journalPhotos.systemImage)
                    .font(Geist.label(.subheadline))
                    .foregroundStyle(Geist.accentText)
            }
            .buttonStyle(.plain)
            .disabled(isProcessingMedia || !canExtractText)
            .padding(.horizontal, 4)

            Text("Scans and journal pages are read on device and saved as Markdown, with the original image alongside.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Geist.bg.ignoresSafeArea())
        .presentationDetents([.height(recentPhotos == nil ? 430 : 520), .large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}
