import SwiftUI
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

    private func show<Content: View>(_ host: UIHostingController<Content>) -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
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

private struct RenderProbe: UIViewRepresentable {
    let id: String

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.accessibilityIdentifier = id
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
