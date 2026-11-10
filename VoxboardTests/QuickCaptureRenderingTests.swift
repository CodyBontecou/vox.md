import Observation
import SwiftUI
import VoxboardShared
import UIKit
import XCTest
@testable import Voxboard

/// These are rendering/architecture regressions, not proof of a device runtime
/// stack limit. Run test-ios-capture-launch.py on hardware for that last gate.
@MainActor
final class QuickCaptureRenderingTests: XCTestCase {
    func testCoordinatorAndSectionExposeConcreteMetadataBoundaries() {
        XCTAssertEqual(ObjectIdentifier(QuickCaptureView.Body.self), ObjectIdentifier(CaptureViewSection.self))
        XCTAssertEqual(ObjectIdentifier(CaptureViewSection.Body.self), ObjectIdentifier(AnyView.self))
    }

    func testCanvasBodyMetadataStaysSmall() {
        // Deliberately a generous engineering budget, not an OS crash threshold.
        // Nominal slots keep this constant when their internals gain features.
        let name = String(reflecting: QuickCaptureCanvas.Body.self)
        XCTAssertLessThan(name.utf8.count, 4_096, "Canvas metadata expanded: \(name)")
    }

    func testFirstNoteGuideRetainsReadingSpaceBesideTheEditor() async throws {
        let steps: [FirstNoteGuide.Step] = [.chooseFolder, .writeNote(folder: "My Notes"), .saved(file: "Note.md")]
        for size in [DynamicTypeSize.large, .accessibility5] {
            for (index, step) in steps.enumerated() {
                let guide = CaptureViewSection {
                    QuickCaptureFirstNoteGuide(step: step, action: {}, dismiss: {})
                        .background { RenderProbe(id: "first-note-viewport") }
                }
                let empty = CaptureViewSection { EmptyView() }
                let content = QuickCaptureCanvas(showsDestination: true, showsWatchStatus: false,
                    showsAttachments: false, header: empty, ocrProgress: empty, destination: guide, watchStatus: empty,
                    composer: slot("composer", expands: true), attachments: empty, controls: slot("controls"),
                    keyboardGuidance: empty, error: empty, fileExport: empty, sentToast: empty)
                    .environment(\.dynamicTypeSize, size)
                let host = UIHostingController(rootView: content)
                let window = show(host, size: CGSize(width: 320, height: 568))
                defer { window.isHidden = true }
                try await settle(window)
                let viewport = try XCTUnwrap(find("first-note-viewport", in: host.view))
                let editor = try XCTUnwrap(find("composer", in: host.view))
                XCTAssertGreaterThanOrEqual(viewport.bounds.height, 180,
                    "The editor must not squeeze first-note guidance to zero height")
                XCTAssertGreaterThan(editor.bounds.height, 80, "Leave usable space to type")
                XCTAssertLessThanOrEqual(viewport.convert(viewport.bounds, to: window).maxY,
                                         editor.convert(editor.bounds, to: window).minY + 1)
                let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                    host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "first-note-\(index)-\(size)-compact"
                attachment.lifetime = .keepAlways
                add(attachment)
                if size.isAccessibilitySize {
                    let scroll = try XCTUnwrap(findScrollView(in: host.view))
                    scroll.setContentOffset(CGPoint(x: 0, y: max(0, scroll.contentSize.height - scroll.bounds.height)), animated: false)
                    try await settle(window)
                    let bottom = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                        host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
                    }
                    let bottomAttachment = XCTAttachment(image: bottom)
                    bottomAttachment.name = "first-note-\(index)-largest-actions-compact"
                    bottomAttachment.lifetime = .keepAlways
                    add(bottomAttachment)
                }
            }
        }
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews {
            if let scroll = findScrollView(in: child) { return scroll }
        }
        return nil
    }

    func testUndoLongPasteKeepsGlyphsVisibleAfterEditorEnlarges() async throws {
        let editor = LiveTranscriptRenderingState()
        editor.text = "# A draft worth keeping\n- [ ] First task\n- [ ] Another task\n\nOriginal words remain visible."
        let original = editor.text
        let host = UIHostingController(rootView: LiveTranscriptComposerHarness(editor: editor)
            .background(Color.white).environment(\.colorScheme, .light))
        let window = show(host, size: CGSize(width: 390, height: 680))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)
        let textView = try XCTUnwrap(find("quick_capture_text", in: host.view) as? UITextView)
        let baseline = try darkGlyphPixels(in: textView)
        XCTAssertGreaterThan(baseline, 500)
        let pastes = [
            String(repeating: "\né 👩🏽‍💻 العربية 日本語 [ ]", count: 200),
            "\n```md\n- [ ] " + String(repeating: "x", count: 2_048) + "\n```\n"
                + String(repeating: "> 👨‍👩‍👧‍👦 é\n", count: 80),
        ]
        for paste in pastes {
            window.frame.size = CGSize(width: 390, height: 400)
            host.view.frame = window.bounds
            textView.becomeFirstResponder()
            try await settle(window)
            textView.selectedRange = NSRange(location: original.utf16.count, length: 0)
            textView.insertText(paste)
            try await settle(window)
            textView.undoManager?.undo()
            try await settle(window)
            XCTAssertEqual(textView.text, original)
            editor.isFocused = false
            textView.resignFirstResponder()
            for size in [CGSize(width: 390, height: 900), CGSize(width: 900, height: 390),
                         CGSize(width: 390, height: 900)] {
                window.frame.size = size
                host.view.frame = window.bounds
                try await settle(window)
                XCTAssertGreaterThan(try darkGlyphPixels(in: textView), baseline / 2,
                    "Resizing after Undo must redraw the restored paragraphs, not an empty viewport")
            }
            textView.becomeFirstResponder()
            try await settle(window)
            editor.isFocused = false
            textView.resignFirstResponder()
            try await settle(window)
            XCTAssertGreaterThan(try darkGlyphPixels(in: textView), baseline / 2)
        }
        retainScreenshot("Undo long paste after keyboard dismissal", in: host.view)
    }

    private func darkGlyphPixels(in view: UIView) throws -> Int {
        let bounds = CGRect(x: 0, y: 0, width: view.bounds.width, height: min(220, view.bounds.height))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            UIColor.white.setFill()
            context.fill(bounds)
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] < 120 && pixels[$0 + 1] < 120 && pixels[$0 + 2] < 120
        }.count
    }

    func testWorkspaceResizesWithoutReplacingEditorOrLosingSelection() async throws {
        let editor = LiveTranscriptRenderingState()
        editor.text = "A draft survives folding and unfolding."
        editor.selection = NSRange(location: 8, length: 7)
        let host = UIHostingController(rootView: ResizingCaptureWorkspaceHarness(editor: editor))
        let window = show(host, size: CGSize(width: 390, height: 680))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)
        let original = try XCTUnwrap(find("quick_capture_text", in: host.view) as? UITextView)
        let selection = original.selectedRange

        for size in [CGSize(width: 960, height: 680), CGSize(width: 960, height: 340),
                     CGSize(width: 390, height: 680)] {
            window.frame.size = size
            host.view.frame = window.bounds
            try await settle(window)
            let current = try XCTUnwrap(find("quick_capture_text", in: host.view) as? UITextView)
            XCTAssertTrue(current === original, "Resizing must retain the real text editor")
            XCTAssertEqual(current.text, editor.text)
            XCTAssertEqual(current.selectedRange, selection)
            XCTAssertEqual(find("workspace_preview_probe", in: host.view) != nil, size.width >= 760)
            XCTAssertGreaterThan(current.bounds.width, 0)
            retainScreenshot("Capture workspace \(size.width)x\(size.height)", in: host.view)
        }
    }

    func testWorkspaceKeepsAccessibleTextInASingleColumn() {
        XCTAssertFalse(AdaptiveCaptureWorkspace.supportsPreview(width: 759, dynamicTypeSize: .large))
        XCTAssertTrue(AdaptiveCaptureWorkspace.supportsPreview(width: 760, dynamicTypeSize: .large))
        XCTAssertFalse(AdaptiveCaptureWorkspace.supportsPreview(width: 960, dynamicTypeSize: .accessibility3))
    }

    func testDraftPreviewRemainsScrollableWithLongContentAndAccessibilityText() async throws {
        let content = "# A long idea worth keeping\n\n"
            + String(repeating: "- [ ] A longer task that wraps onto more than one line\n", count: 30)
            + "> Keep the original Markdown."
        let host = UIHostingController(rootView:
            CaptureDraftPreview(
                text: content,
                presetName: "Journal",
                destination: "Personal vault / Journal / A long idea worth keeping.md",
                attachmentCount: 2,
                configureDestination: {}
            )
            .environment(\.dynamicTypeSize, .accessibility3)
            .environment(\.colorScheme, .dark)
            .environment(\.layoutDirection, .rightToLeft)
        )
        let window = show(host, size: CGSize(width: 320, height: 430))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)
        let scroll = try XCTUnwrap(scrollViews(in: host.view).first)
        XCTAssertTrue(scroll.isScrollEnabled)
        XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
        XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1)
        retainScreenshot("Draft preview — large text, RTL, dark", in: host.view)
    }

    func testCanvasMountsOptionalSectionsAndRetainsComposerIdentity() async throws {
        let host = UIHostingController(rootView: canvas(optionalSections: false))
        let window = show(host)
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)

        let originalComposer = try XCTUnwrap(find("composer", in: host.view))
        XCTAssertNil(find("destination", in: host.view))
        XCTAssertNil(find("watch", in: host.view))
        XCTAssertNil(find("transcript", in: host.view))
        XCTAssertNil(find("attachments", in: host.view))

        host.rootView = canvas(optionalSections: true)
        try await settle(window)
        for id in ["destination", "watch", "attachments", "controls"] {
            XCTAssertNotNil(find(id, in: host.view), "Missing rendered section: \(id)")
        }
        XCTAssertNil(
            find("transcript", in: host.view),
            "Live transcript text belongs in the editor, not a dedicated strip"
        )
        let updatedComposer = try XCTUnwrap(find("composer", in: host.view))
        XCTAssertTrue(originalComposer === updatedComposer, "Updating sections replaced the text editor's identity")
        XCTAssertGreaterThan(updatedComposer.bounds.height, 0)
        let controls = try XCTUnwrap(find("controls", in: host.view))
        XCTAssertGreaterThanOrEqual(
            controls.convert(controls.bounds, to: window).minY,
            updatedComposer.convert(updatedComposer.bounds, to: window).maxY - 1,
            "Controls must remain below the editor in the keyboard-aware safe area"
        )

        host.rootView = canvas(optionalSections: false)
        try await settle(window)
        XCTAssertNil(find("attachments", in: host.view))
        XCTAssertNil(find("transcript", in: host.view))
        XCTAssertTrue(originalComposer === find("composer", in: host.view))
    }

    func testProgrammaticLiveTextFollowsTheEditorTailWithoutASeparateStrip() async throws {
        let editor = LiveTranscriptRenderingState()
        let host = UIHostingController(rootView: LiveTranscriptComposerHarness(editor: editor))
        let window = show(host, size: CGSize(width: 390, height: 220))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)

        let transcript = (1...40)
            .map { "Live transcript line \($0) keeps flowing inside the editor." }
            .joined(separator: "\n")
        editor.text = transcript
        editor.selection = NSRange(location: transcript.utf16.count, length: 0)
        try await settle(window)

        let textView = try XCTUnwrap(find("quick_capture_text", in: host.view) as? UITextView)
        XCTAssertEqual(textView.text, transcript)
        XCTAssertEqual(textView.selectedRange, editor.selection)
        XCTAssertGreaterThan(textView.contentSize.height, textView.bounds.height)
        XCTAssertGreaterThan(textView.contentOffset.y, 0, "Programmatic live text should keep its tail visible")
        XCTAssertNil(find("capture_live_transcription", in: host.view))
    }

    func testRealToastAndOCRBodiesRenderInBothUndoStates() async throws {
        for offersUndo in [false, true] {
            let appeared = expectation(description: "Toast rendered (undo=\(offersUndo))")
            let content = CaptureViewSection {
                VStack {
                    QuickCaptureOCRProgress()
                    QuickCaptureSentToast(offersUndo: offersUndo, undo: {})
                        .onAppear { appeared.fulfill() }
                }
            }
            let host = UIHostingController(rootView: content)
            let window = show(host)
            await fulfillment(of: [appeared], timeout: 3)
            try await settle(window)
            XCTAssertGreaterThan(host.view.bounds.width, 0)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testRecordingControlHelpAndActionHintsDescribeThreeDistinctBehaviors() {
        XCTAssertEqual(
            CaptureRecordingControlSemantics.audioHelp,
            String(localized: "Keep the new recording attached when adding it to the current draft. With Audio off, the transcript is still added when available.")
        )
        XCTAssertEqual(
            CaptureRecordingControlSemantics.importAudioHelp,
            String(localized: "Choose an existing audio or video file. Vox.md processes it and adds the transcript or result to the current Capture flow.")
        )
        XCTAssertEqual(
            CaptureRecordingControlSemantics.keyboardListeningHelp,
            String(localized: "Start or stop the persistent listening session used by the Vox.md keyboard. This is not another attachment mode.")
        )
        XCTAssertEqual(
            CaptureRecordingControlSemantics.keyboardListeningLabel(isListening: false),
            String(localized: "Start keyboard listening")
        )
        XCTAssertEqual(
            CaptureRecordingControlSemantics.keyboardListeningLabel(isListening: true),
            String(localized: "Stop keyboard listening")
        )
        XCTAssertEqual(
            CaptureRecordingControlSemantics.keyboardListeningActionHint(isListening: false),
            String(localized: "Starts the persistent listening session used by the Vox.md keyboard. This does not attach audio to the Capture.")
        )
        XCTAssertEqual(
            CaptureRecordingControlSemantics.keyboardListeningActionHint(isListening: true),
            String(localized: "Stops the persistent listening session used by the Vox.md keyboard. This does not change Capture attachments.")
        )
    }

    func testRecordingControlHelpAffordanceAndSheetMountInCompactAccessibleLayouts() async throws {
        let layouts: [(CGFloat, ColorScheme, DynamicTypeSize, LayoutDirection)] = [
            (320, .light, .large, .leftToRight),
            (320, .dark, .accessibility3, .rightToLeft),
            (390, .light, .xxxLarge, .leftToRight),
        ]
        for (width, scheme, typeSize, direction) in layouts {
            let affordanceAppeared = expectation(description: "Recording help affordance mounted")
            let affordance = CaptureRecordingControlHelp(isPresented: .constant(false))
                .padding(Geist.Spacing.three)
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.layoutDirection, direction)
                .onAppear { affordanceAppeared.fulfill() }
            let affordanceHost = UIHostingController(rootView: affordance)
            let affordanceWindow = show(affordanceHost, size: CGSize(width: width, height: 132))
            await fulfillment(of: [affordanceAppeared], timeout: 3)
            try await settle(affordanceWindow)
            XCTAssertLessThanOrEqual(
                affordanceHost.sizeThatFits(in: CGSize(width: width, height: 1_000)).height,
                132,
                "The help affordance must stay compact instead of inlining explanations"
            )
            retainScreenshot(
                "Recording control help affordance \(width) \(scheme) \(typeSize) \(direction)",
                in: affordanceHost.view
            )
            affordanceWindow.isHidden = true
            affordanceWindow.rootViewController = nil

            let sheetAppeared = expectation(description: "Recording help sheet mounted")
            let sheet = CaptureRecordingControlHelpSheet()
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.layoutDirection, direction)
                .onAppear { sheetAppeared.fulfill() }
            let sheetHost = UIHostingController(rootView: sheet)
            let sheetWindow = show(sheetHost, size: CGSize(width: width, height: 620))
            defer { sheetWindow.isHidden = true; sheetWindow.rootViewController = nil }
            await fulfillment(of: [sheetAppeared], timeout: 3)
            try await settle(sheetWindow)

            let scrollingContainers = scrollViews(in: sheetHost.view)
            XCTAssertTrue(
                scrollingContainers.contains(where: { $0.isScrollEnabled && $0.bounds.height > 0 }),
                "Recording explanations must remain vertically scrollable at large text sizes"
            )
            // Unit-hosted SwiftUI does not expose a faithful VoiceOver tree.
            // Copy tests above verify semantics; these mounts verify adaptation.
            retainScreenshot(
                "Recording control help sheet \(width) \(scheme) \(typeSize) \(direction)",
                in: sheetHost.view
            )
        }
    }

    private func retainScreenshot(_ name: String, in view: UIView) {
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        ((view as? UIScrollView).map { [$0] } ?? [])
            + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func canvas(optionalSections: Bool) -> QuickCaptureCanvas {
        QuickCaptureCanvas(
            showsDestination: optionalSections,
            showsWatchStatus: optionalSections,
            showsAttachments: optionalSections,
            header: CaptureViewSection { EmptyView() },
            ocrProgress: CaptureViewSection { EmptyView() },
            destination: slot("destination"),
            watchStatus: slot("watch"),
            composer: slot("composer", expands: true),
            attachments: slot("attachments"),
            controls: slot("controls"),
            keyboardGuidance: CaptureViewSection { EmptyView() },
            error: CaptureViewSection { EmptyView() },
            fileExport: CaptureViewSection { EmptyView() },
            sentToast: CaptureViewSection { EmptyView() }
        )
    }

    private func slot(_ id: String, expands: Bool = false) -> CaptureViewSection {
        CaptureViewSection {
            RenderProbe(id: id).frame(height: expands ? nil : 36)
        }
    }

    private func show<Content: View>(
        _ host: UIHostingController<Content>,
        size: CGSize = CGSize(width: 390, height: 844)
    ) -> UIWindow {
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.rootViewController = host
        window.isHidden = false
        host.loadViewIfNeeded()
        window.layoutIfNeeded()
        return window
    }

    private func settle(_ window: UIWindow) async throws {
        // Yield to SwiftUI's transaction/render cycle rather than just constructing
        // values (constructing a View does not exercise its runtime body metadata).
        window.rootViewController?.view.setNeedsLayout()
        window.setNeedsLayout()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.rootViewController?.view.layoutIfNeeded()
    }

    private func find(_ id: String, in view: UIView) -> UIView? {
        if view.accessibilityIdentifier == id { return view }
        for child in view.subviews {
            if let result = find(id, in: child) { return result }
        }
        return nil
    }
}

@MainActor
@Observable
private final class LiveTranscriptRenderingState {
    var text = ""
    var selection = NSRange(location: 0, length: 0)
    var isFocused = false
    let controller = MarkdownComposerController()
}

private struct LiveTranscriptComposerHarness: View {
    @Bindable var editor: LiveTranscriptRenderingState

    var body: some View {
        MarkdownComposerTextView(
            text: $editor.text,
            selection: $editor.selection,
            isFocused: $editor.isFocused,
            controller: editor.controller
        )
    }
}

private struct ResizingCaptureWorkspaceHarness: View {
    let editor: LiveTranscriptRenderingState

    var body: some View {
        GeometryReader { geometry in
            AdaptiveCaptureWorkspace(
                showsPreview: AdaptiveCaptureWorkspace.supportsPreview(
                    width: geometry.size.width, dynamicTypeSize: .large
                ),
                primary: CaptureViewSection { LiveTranscriptComposerHarness(editor: editor) },
                preview: CaptureViewSection { RenderProbe(id: "workspace_preview_probe") }
            )
        }
    }
}

private struct RenderProbe: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = id
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
