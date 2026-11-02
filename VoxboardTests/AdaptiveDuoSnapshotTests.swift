import SwiftUI
import UIKit
import VoxboardShared
import XCTest
@testable import Voxboard

/// Renders the app's real `RootView` at the iPhone Duo inner-screen sizes
/// (DuoInnerCapture, DuoInnerLibrary, DuoTabletop, DuoSplitView boards) and
/// attaches each render. The cover screen can't be unfolded without
/// Simulator.app, so a window with the inner frame and a regular-width trait
/// override stands in for it; the DEBUG hinge override stands in for
/// `UIHingeInteraction`.
///
/// Opt-in: set `VOX_DUO_SNAPSHOTS=1` in the test environment (it writes the
/// DEBUG seed routes and captures into the host app's container).
@MainActor
final class AdaptiveDuoSnapshotTests: XCTestCase {
    private struct AppGraph {
        let modelManager: ModelManager
        let transcriptStore: TranscriptStore
        let usageTracker: UsageTracker
        let storeManager: StoreManager
        let viewModel: QuickCaptureViewModel
        let recorder: PersistentRecorder
        let watchPipeline: WatchRecordingPipeline
    }

    private static let innerSize = CGSize(width: 890, height: 626)
    private static let tabletopSize = CGSize(width: 626, height: 890)
    /// The app's half of DuoSplitView (890pt inner screen, 442pt pane).
    private static let splitPaneSize = CGSize(width: 442, height: 626)

    private static let projectSync = """
    # Project sync
    - [ ] Review final designs
    - [ ] Loop in design before Friday

    Decision: ship routing first and keep the composer calm
    """

    private var window: UIWindow?
    private var contentRect: CGRect = .zero

    override func setUp() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["VOX_DUO_SNAPSHOTS"] == "1",
            "Set VOX_DUO_SNAPSHOTS=1 to render the Duo inner-screen boards."
        )
    }

    override func tearDown() async throws {
        window?.isHidden = true
        window?.rootViewController = nil
        window = nil
        AdaptiveLayout.debugHingeOverride = nil
        AdaptiveLayout.debugSectionOverride = nil
    }

    // MARK: Boards

    func testDuoInnerCapture() async throws {
        let graph = makeGraph()
        AdaptiveLayout.debugHingeOverride = .open
        AdaptiveLayout.debugSectionOverride = "capture"
        let window = host(graph, size: Self.innerSize, sizeClass: .regular)
        try await seed(graph, in: window)
        graph.viewModel.draft.text = Self.projectSync
        try await settle(window, seconds: 2)
        attach(window, name: "DuoInnerCapture")
    }

    func testDuoInnerLibrary() async throws {
        let graph = makeGraph()
        AdaptiveLayout.debugHingeOverride = .open
        AdaptiveLayout.debugSectionOverride = "library"
        let window = host(graph, size: Self.innerSize, sizeClass: .regular)
        try await seed(graph, in: window)
        await AdaptiveDebugSeed.seedLibrary(viewModel: graph.viewModel)
        try await settle(window, seconds: 3)
        attach(window, name: "DuoInnerLibrary")
    }

    func testDuoTabletopRecording() async throws {
        let graph = makeGraph()
        AdaptiveLayout.debugHingeOverride = .partiallyOpen
        AdaptiveLayout.debugSectionOverride = "capture"
        let window = host(graph, size: Self.tabletopSize, sizeClass: .regular)
        try await seed(graph, in: window)
        graph.viewModel.draft.text = ""
        graph.recorder.configureLocalizationScreenshot(story: "02-live-recording")
        try await settle(window, seconds: 3)
        attach(window, name: "DuoTabletop")
    }

    func testDuoSplitViewDropCard() async throws {
        let graph = makeGraph()
        AdaptiveLayout.debugHingeOverride = .open
        let window = host(graph, size: Self.splitPaneSize, sizeClass: .compact)
        try await seed(graph, in: window)
        if let inbox = graph.viewModel.voxProfiles.first(where: { $0.name == "Inbox" }) {
            _ = graph.viewModel.selectVox(inbox.id)
        }
        // What a text drop from another app leaves in the composer: a quote
        // ending in its source line, then the person's own note.
        graph.viewModel.draft.text = """
        > Local-first software keeps the primary copy of your data on your own device.
        > — [inkandswitch.com](https://www.inkandswitch.com/local-first/)

        Good framing for the vault-first pitch
        """
        try await settle(window, seconds: 3)
        attach(window, name: "DuoSplitView")
    }

    // MARK: Hosting

    /// The `-VoxAdaptiveSeedDemo` seed, applied once the composer has
    /// restored its saved draft (as the app's 2s seed delay does).
    private func seed(_ graph: AppGraph, in window: UIWindow) async throws {
        try await settle(window, seconds: 2)
        await AdaptiveDebugSeed.apply(to: graph.viewModel, settleDelay: .zero)
    }

    /// Mirrors `VoxboardApp.init` for the pieces RootView reads.
    private func makeGraph() -> AppGraph {
        let store = TranscriptStore()
        let usage = UsageTracker()
        let storeManager = StoreManager(usageTracker: usage)
        let viewModel = QuickCaptureViewModel(requestProcessor: CapturePresetRequestProcessor())
        let recorder = PersistentRecorder(
            transcriptStore: store,
            usageTracker: usage,
            transcriptionService: AppTranscriptionServices.shared,
            captureDraftEventHandler: { [weak viewModel] event in
                guard let viewModel else { return false }
                return await CaptureDraftRecordingEventDelivery.deliver(event, to: viewModel)
            }
        )
        let watchPipeline = WatchRecordingPipeline(
            transcriptStore: store,
            usageTracker: usage,
            transcriptionService: AppTranscriptionServices.shared,
            transcriptEnricher: nil
        )
        return AppGraph(
            modelManager: ModelManager(),
            transcriptStore: store,
            usageTracker: usage,
            storeManager: storeManager,
            viewModel: viewModel,
            recorder: recorder,
            watchPipeline: watchPipeline
        )
    }

    private func host(_ graph: AppGraph, size: CGSize, sizeClass: UIUserInterfaceSizeClass) -> UIWindow {
        let root = RootView(
            persistentRecorder: graph.recorder,
            quickCaptureViewModel: graph.viewModel,
            rootDestination: .constant(.capture),
            pendingKeyboardLaunch: .constant(false),
            pendingWidgetRecord: .constant(false)
        )
        // Same modifiers as the app's WindowGroup root.
        .tint(Geist.tint)
        .environment(graph.modelManager)
        .environment(graph.transcriptStore)
        .environment(graph.usageTracker)
        .environment(graph.storeManager)
        .environment(graph.watchPipeline)
        .environment(\.defersCaptureInputFocusForReleaseNotes, true)

        let controller = UIHostingController(rootView: root)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        window.traitOverrides.horizontalSizeClass = sizeClass
        window.traitOverrides.verticalSizeClass = .regular
        window.overrideUserInterfaceStyle = .light
        window.rootViewController = controller
        window.windowLevel = .alert + 1
        window.isHidden = false
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        window.layoutIfNeeded()
        // The window is larger than the folded cover screen it lives on, and
        // that screen's insets (right sensor edge, home indicator) still
        // reach the navigation containers inside RootView. Grow the window by
        // those insets so its safe region is exactly the inner-screen size,
        // and render only that region (`contentRect`).
        var insets = window.safeAreaInsets
        for _ in 0..<4 {
            // The insets depend on how far the window reaches past the
            // screen, so settle them over a few passes.
            window.frame = CGRect(
                x: 0, y: 0,
                width: size.width + insets.left + insets.right,
                height: size.height + insets.top + insets.bottom
            )
            controller.view.frame = window.bounds
            window.layoutIfNeeded()
            if window.safeAreaInsets == insets { break }
            insets = window.safeAreaInsets
        }
        contentRect = CGRect(origin: CGPoint(x: insets.left, y: insets.top), size: size)
        self.window = window
        return window
    }

    private func settle(_ window: UIWindow, seconds: Double) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            window.setNeedsLayout()
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
        }
    }

    private func dumpFrames(_ view: UIView, depth: Int = 0, into lines: inout [String]) {
        guard depth < 9, lines.count < 80 else { return }
        let f = view.convert(view.bounds, to: nil)
        lines.append(String(repeating: " ", count: depth) + "\(type(of: view)) x=\(Int(f.minX)) w=\(Int(f.width)) h=\(Int(f.height)) sa=\(view.safeAreaInsets.right)/\(view.layoutMargins.right)")
        for sub in view.subviews { dumpFrames(sub, depth: depth + 1, into: &lines) }
    }

    private func attach(_ window: UIWindow, name: String) {
        if ProcessInfo.processInfo.environment["VOX_DUO_DUMP"] == "1" {
            var lines: [String] = []
            dumpFrames(window, into: &lines)
            print("[DuoFrames] \(name)\n" + lines.joined(separator: "\n"))
        }
        let format = UIGraphicsImageRendererFormat(for: window.traitCollection)
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: contentRect, format: format).image { _ in
            _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "\(name) \(Int(contentRect.width))x\(Int(contentRect.height)) \(UIDevice.current.name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("[DuoSnapshot] \(name) rendered=\(contentRect) window=\(window.bounds.size) screen=\(window.screen.bounds.size) "
            + "windowSafeArea=\(window.safeAreaInsets) rootSafeArea=\(window.rootViewController?.view.safeAreaInsets ?? .zero) "
            + "hSize=\(window.traitCollection.horizontalSizeClass.rawValue) idiom=\(UIDevice.current.userInterfaceIdiom.rawValue)")
    }
}
