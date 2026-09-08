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
        for id in ["destination", "watch", "transcript", "attachments", "controls"] {
            XCTAssertNotNil(find(id, in: host.view), "Missing rendered section: \(id)")
        }
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

    func testMicHintOverlayRendersWithKeyboardSizedSpaceAndAccessibilityVariants() async throws {
        let variants: [(CGFloat, ColorScheme, DynamicTypeSize, LayoutDirection)] = [
            (320, .light, .large, .leftToRight),
            (390, .dark, .accessibility3, .leftToRight),
            (390, .light, .large, .rightToLeft),
            (768, .dark, .large, .leftToRight),
        ]
        for (width, scheme, typeSize, direction) in variants {
            let appeared = expectation(description: "Anchored mic hint rendered at \(width), \(direction)")
            let content = CaptureViewSection {
                RenderProbe(id: "composer")
                    .frame(maxHeight: .infinity)
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 0) {
                            RenderProbe(id: "route").frame(height: 40)
                            HStack {
                                Spacer()
                                RenderProbe(id: "mic")
                                    .overlay { Image(systemName: "mic") }
                                    .frame(width: 36, height: 36)
                                    .anchorPreference(key: CaptureMicHoldHintAnchorKey.self, value: .bounds) { $0 }
                                Spacer().frame(width: 44)
                            }
                            .padding(12)
                            RenderProbe(id: "tools").frame(height: 48)
                        }
                        .overlayPreferenceValue(CaptureMicHoldHintAnchorKey.self) { anchor in
                            if anchor != nil {
                                CaptureMicHoldHintOverlay(micAnchor: anchor, dismiss: {})
                                    .onAppear { appeared.fulfill() }
                            }
                        }
                    }
                    .environment(\.colorScheme, scheme)
                    .environment(\.dynamicTypeSize, typeSize)
                    .environment(\.layoutDirection, direction)
            }
            let host = UIHostingController(rootView: content)
            let window = show(host, size: CGSize(width: width, height: 400))
            await fulfillment(of: [appeared], timeout: 3)
            try await settle(window)
            XCTAssertNotNil(find("mic", in: host.view))
            XCTAssertNotNil(find("composer", in: host.view))
            // Unit-hosted SwiftUI does not expose the full accessibility tree.
            // Keep rendered variants for review; verify gestures/hit targets in
            // the running app as described in capture-view-regression-tests.md.
            let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Mic hint \(width) \(scheme) \(typeSize) \(direction)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testPinnedSelectionRetainsRealMarkdownUIViewCursorFocusTextAndAttachments() async throws {
        let fixture = try await QuickCapturePresetFixture.make(in: self)
        let editor = PresetRenderingState()
        let harness = PresetComposerHarness(fixture: fixture, editor: editor)
        let host = UIHostingController(rootView: harness)
        let previousKeyWindow = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let window = show(host)
        window.makeKeyAndVisible()
        defer {
            editor.controller.dismissKeyboard()
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        try await settle(window)
        let original = try XCTUnwrap(find("quick_capture_text", in: host.view) as? UITextView)
        XCTAssertTrue(original.becomeFirstResponder())
        let cursor = NSRange(location: 5, length: 12)
        editor.controller.replaceAll(with: fixture.vm.draft.text, selection: cursor)
        try await settle(window)
        XCTAssertTrue(original.isFirstResponder)
        XCTAssertTrue(editor.isFocused)
        XCTAssertEqual(original.selectedRange, cursor)
        let before = fixture.vm.draft
        retainScreenshot("Pinned presets — focused editor before switch", in: host.view)

        // This is the actual row's Button callback seam, not a direct mutation
        // or a substitute editor probe. It is not a simulated physical tap.
        XCTAssertTrue(fixture.row.activatePreset(id: "inbox"))
        try await settle(window)
        let updated = try XCTUnwrap(find("quick_capture_text", in: host.view) as? UITextView)
        XCTAssertTrue(original === updated)
        XCTAssertTrue(updated.isFirstResponder)
        XCTAssertTrue(editor.isFocused)
        XCTAssertEqual(updated.selectedRange, cursor)
        XCTAssertEqual(editor.selection, cursor)
        XCTAssertEqual(updated.text, before.text)
        XCTAssertEqual(editor.controller.text, before.text)
        XCTAssertEqual(fixture.vm.draft.additionalPayloads, before.additionalPayloads)
        XCTAssertEqual(fixture.vm.draft.id, before.id)
        XCTAssertEqual(fixture.vm.draft.voxID, "inbox")
        XCTAssertNil(fixture.vm.draft.relativeNotePathOverride)
        XCTAssertFalse(fixture.row.activatePreset(id: "inbox"))
        try await settle(window)
        XCTAssertTrue(updated.isFirstResponder)
        XCTAssertEqual(updated.selectedRange, cursor)
        retainScreenshot("Pinned presets — focused editor after switch and no-op", in: host.view)

        let staleRow = fixture.row
        let selectedDraft = fixture.vm.draft
        fixture.vm.isProcessingMedia = true
        XCTAssertFalse(fixture.row.activatePreset(id: "journal"))
        XCTAssertFalse(staleRow.activatePreset(id: "journal"))
        try await settle(window)
        XCTAssertEqual(fixture.vm.draft, selectedDraft)
        XCTAssertTrue(original === find("quick_capture_text", in: host.view))
        XCTAssertTrue(original.isFirstResponder)
        XCTAssertEqual(original.selectedRange, cursor)
        fixture.vm.isProcessingMedia = false
    }

    func testRealPinnedRowRendersOverflowInKeyboardSizedLargeTextAndRTLLayouts() async throws {
        let fixture = try await QuickCapturePresetFixture.make(in: self)
        let variants: [(CGFloat, ColorScheme, DynamicTypeSize, LayoutDirection)] = [
            (320, .light, .large, .leftToRight),
            (390, .dark, .accessibility3, .leftToRight),
            (320, .light, .accessibility3, .rightToLeft),
            (768, .dark, .xxxLarge, .leftToRight),
        ]
        for (width, scheme, typeSize, direction) in variants {
            let editor = PresetRenderingState()
            let content = PresetComposerHarness(fixture: fixture, editor: editor)
                .environment(\.colorScheme, scheme)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.layoutDirection, direction)
            let host = UIHostingController(rootView: content)
            let window = show(host, size: CGSize(width: width, height: 400))
            defer { window.isHidden = true; window.rootViewController = nil }
            try await settle(window)
            let pins = try XCTUnwrap(editor.frames["pins"])
            let composer = try XCTUnwrap(editor.frames["editor"])
            let route = try XCTUnwrap(editor.frames["route"])
            XCTAssertGreaterThanOrEqual(pins.height, 44)
            XCTAssertLessThanOrEqual(pins.width, width + 1)
            XCTAssertGreaterThan(composer.height, 0)
            XCTAssertGreaterThanOrEqual(pins.minY, composer.maxY - 1)
            XCTAssertGreaterThanOrEqual(route.minY, pins.maxY - 1)
            XCTAssertLessThanOrEqual(route.maxY, host.view.bounds.height + 1)
            if width < 768 {
                let overflow = scrollViews(in: host.view).filter {
                    !($0 is UITextView) && $0.contentSize.width > $0.bounds.width + 1
                }
                XCTAssertFalse(overflow.isEmpty, "All seven pins must overflow horizontally, never shrink or cap")
                XCTAssertTrue(overflow.allSatisfy { $0.keyboardDismissMode == .none })
            }
            retainScreenshot("Pinned presets \(width) \(scheme) \(typeSize) \(direction)", in: host.view)
        }
    }

    func testEmptyAndSinglePinUpdatesKeepActualEditorAndOmitEmptyStrip() async throws {
        let fixture = try await QuickCapturePresetFixture.make(in: self)
        let editor = PresetRenderingState()
        let host = UIHostingController(rootView: PresetComposerHarness(fixture: fixture, editor: editor))
        let window = show(host, size: CGSize(width: 320, height: 400))
        defer { window.isHidden = true; window.rootViewController = nil }
        try await settle(window)
        let original = try XCTUnwrap(find("quick_capture_text", in: host.view))
        XCTAssertTrue(fixture.preferences.setOrderedIDs([]))
        try await settle(window)
        XCTAssertLessThanOrEqual(editor.frames["pins"]?.height ?? 0, 1)
        XCTAssertTrue(original === find("quick_capture_text", in: host.view))
        retainScreenshot("Pinned presets — deliberately empty", in: host.view)
        XCTAssertTrue(fixture.preferences.setOrderedIDs(["inbox"]))
        try await settle(window)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(editor.frames["pins"]).height, 44)
        XCTAssertTrue(original === find("quick_capture_text", in: host.view))
        XCTAssertTrue(fixture.row.activatePreset(id: "inbox"))
        try await settle(window)
        XCTAssertEqual(fixture.vm.draft.voxID, "inbox")
        retainScreenshot("Pinned presets — single useful pin", in: host.view)
    }

    func testActualPresetButtonsKeep44PointTargetsAndMirrorWithDynamicType() async throws {
        for typeSize in [DynamicTypeSize.xSmall, .large, .accessibility3] {
            for direction in [LayoutDirection.leftToRight, .rightToLeft] {
                let measurements = PresetRenderingState()
                let content = HStack(spacing: 8) {
                    CapturePresetQuickAccessButton(
                        profile: CapturePresetProfile(id: "first", name: "Family", symbolName: "person", emoji: "👨‍👩‍👧‍👦"),
                        isSelected: true, action: {}
                    ).background(PresetGeometry(id: "first"))
                    CapturePresetQuickAccessButton(
                        profile: CapturePresetProfile(id: "second", name: "Inbox", symbolName: "tray"),
                        isSelected: false, action: {}
                    ).background(PresetGeometry(id: "second"))
                }
                .coordinateSpace(name: "preset-rendering")
                .onPreferenceChange(PresetFramesKey.self) { measurements.frames = $0 }
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.layoutDirection, direction)
                let host = UIHostingController(rootView: content)
                let window = show(host, size: CGSize(width: 390, height: 400))
                defer { window.isHidden = true; window.rootViewController = nil }
                try await settle(window)
                let first = try XCTUnwrap(measurements.frames["first"])
                let second = try XCTUnwrap(measurements.frames["second"])
                for frame in [first, second] {
                    XCTAssertGreaterThanOrEqual(frame.width, 44)
                    XCTAssertGreaterThanOrEqual(frame.height, 44)
                }
                if direction == .rightToLeft { XCTAssertGreaterThan(first.minX, second.minX) }
                else { XCTAssertLessThan(first.minX, second.minX) }
                retainScreenshot("Preset button targets \(typeSize) \(direction)", in: host.view)
            }
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
            showsLiveTranscript: optionalSections,
            showsAttachments: optionalSections,
            ocrProgress: CaptureViewSection { EmptyView() },
            destination: slot("destination"),
            watchStatus: slot("watch"),
            composer: slot("composer", expands: true),
            liveTranscript: slot("transcript"),
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
private final class PresetRenderingState {
    var selection = NSRange(location: 0, length: 0)
    var isFocused = false
    let controller = MarkdownComposerController()
    @ObservationIgnored var frames: [String: CGRect] = [:]
}

/// Only the ancillary destination/attachment slots are deterministic labels;
/// the row, canvas and Markdown UIViewRepresentable are production components.
private struct PresetComposerHarness: View {
    let fixture: QuickCapturePresetFixture
    @Bindable var editor: PresetRenderingState

    var body: some View {
        @Bindable var vm = fixture.vm
        QuickCaptureCanvas(
            showsDestination: false, showsWatchStatus: false, showsLiveTranscript: false,
            showsAttachments: false,
            ocrProgress: empty, destination: empty, watchStatus: empty,
            composer: CaptureViewSection {
                MarkdownComposerTextView(text: $vm.draft.text, selection: $editor.selection,
                    isFocused: $editor.isFocused, controller: editor.controller)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(PresetGeometry(id: "editor"))
            },
            liveTranscript: empty, attachments: empty,
            controls: CaptureViewSection {
                VStack(spacing: 0) {
                    fixture.row.background(PresetGeometry(id: "pins"))
                    HStack {
                        Text(vm.selectedVoxProfile?.displayName ?? "All Presets")
                        Spacer(minLength: 4)
                        Text("Vault / Note.md")
                    }
                    .font(.caption)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(PresetGeometry(id: "route"))
                }
            },
            keyboardGuidance: empty, error: empty, fileExport: empty, sentToast: empty
        )
        .coordinateSpace(name: "preset-rendering")
        .onPreferenceChange(PresetFramesKey.self) { editor.frames = $0 }
    }

    private var empty: CaptureViewSection { CaptureViewSection { EmptyView() } }
}

private struct PresetFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct PresetGeometry: View {
    let id: String
    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: PresetFramesKey.self,
                                   value: [id: proxy.frame(in: .named("preset-rendering"))])
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
