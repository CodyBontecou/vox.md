import Observation
import SwiftUI
import UIKit

// MARK: - Composer layout

/// How the capture composer is arranged for the current width.
///
/// - `compact`: the phone layout (also the iPhone Duo cover screen and narrow
///   Split View). Unchanged from the single-stack app.
/// - `regularPane`: two even panes, composer | route (Duo inner screen, iPad
///   portrait, wide Split View). The route pill stays in the composer header
///   and the quick actions sit inline under it.
/// - `regularSidebar`: three columns, sidebar | composer | route inspector
///   (iPad landscape). Routes are chosen in the sidebar, so the composer header
///   is the destination path plus the inline quick actions.
enum CaptureComposerLayout: Equatable {
    case compact
    case regularPane
    case regularSidebar

    var isRegular: Bool { self != .compact }
}

/// Commands the composer exposes to its container, so a route pane can drive
/// Send without the container reaching into the composer's private state.
@MainActor
@Observable
final class CaptureComposerCommands {
    var send: (() -> Void)?
    var canSend = false
}

// MARK: - Hinge

/// The fold state of the device, from `UIHingeInteraction` (iOS 27.1+).
/// `.unavailable` on devices without a hinge and on earlier systems.
enum AdaptiveHingeState: Equatable {
    case unavailable
    case closed
    case partiallyOpen
    case open
}

private struct AdaptiveHingeStateKey: EnvironmentKey {
    static let defaultValue = AdaptiveHingeState.unavailable
}

extension EnvironmentValues {
    var adaptiveHingeState: AdaptiveHingeState {
        get { self[AdaptiveHingeStateKey.self] }
        set { self[AdaptiveHingeStateKey.self] = newValue }
    }
}

/// Zero-size view that installs a `UIHingeInteraction` and reports the hinge.
struct AdaptiveHingeObserver: UIViewRepresentable {
    @Binding var state: AdaptiveHingeState

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        if #available(iOS 27.1, *) {
            let binding = $state
            let interaction = UIHingeInteraction { _, update in
                let next: AdaptiveHingeState
                switch update.hinge?.status {
                case .closed?: next = .closed
                case .partiallyOpen?: next = .partiallyOpen
                case .fullyOpen?: next = .open
                default: next = .unavailable
                }
                if binding.wrappedValue != next { binding.wrappedValue = next }
            }
            view.addInteraction(interaction)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Window growth

private struct AdaptiveCanExpandWindowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while a compact layout could become wider: a closed foldable
    /// (`UIHingeInteraction`, iOS 27.1+) on its cover screen, an iPad window in
    /// Split View, Slide Over or Stage Manager, or (DEBUG) a simulated cover
    /// screen. Drives the "Open to see route steps" cover hints.
    var adaptiveCanExpandWindow: Bool {
        get { self[AdaptiveCanExpandWindowKey.self] }
        set { self[AdaptiveCanExpandWindowKey.self] = newValue }
    }
}

enum AdaptiveLayout {
    /// Below this width a regular-width window shows two even panes instead of
    /// sidebar | composer | inspector.
    static let sidebarMinimumWidth: CGFloat = 1000

    /// The live recording surface switches to the propped "tabletop" layout
    /// (transcript top half, controls bottom half) once both halves have room.
    static let tabletopMinimumSide: CGFloat = 560

    static func usesTabletopRecording(
        size: CGSize,
        horizontalSizeClass: UserInterfaceSizeClass?,
        hinge: AdaptiveHingeState = .unavailable
    ) -> Bool {
        if debugForcesTabletop { return true }
        // A half-open foldable is propped like a laptop: tabletop whenever
        // the window is big enough to split.
        if hinge == .partiallyOpen, min(size.width, size.height) >= 360 { return true }
        guard horizontalSizeClass == .regular else { return false }
        return min(size.width, size.height) >= tabletopMinimumSide
    }

    @MainActor
    static func canExpandWindow(
        horizontalSizeClass: UserInterfaceSizeClass?,
        hinge: AdaptiveHingeState = .unavailable
    ) -> Bool {
        if debugSimulatesFoldable { return horizontalSizeClass == .compact }
        // A closed foldable shows the cover screen; opening it gives the
        // regular-width layout.
        if hinge == .closed, horizontalSizeClass == .compact { return true }
        // An iPad window narrower than regular width can always be widened
        // (Split View divider, Stage Manager resize, leaving Slide Over).
        return UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .compact
    }

    /// A foldable's closed cover screen (DuoCoverCapture / DuoCoverRecording):
    /// compact width with the hinge closed. Phones and compact iPad windows
    /// keep the plain phone layout.
    @MainActor
    static func isCoverScreen(
        horizontalSizeClass: UserInterfaceSizeClass?,
        hinge: AdaptiveHingeState
    ) -> Bool {
        guard horizontalSizeClass == .compact else { return false }
        if debugSimulatesFoldable { return true }
        return hinge == .closed && UIDevice.current.userInterfaceIdiom == .phone
    }

    // MARK: DEBUG launch arguments

    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments
    /// `-VoxAdaptiveSimulateFoldable`: treat a compact iPhone window as a
    /// foldable cover screen so the "open to see more" hints show.
    static let debugSimulatesFoldable = arguments.contains("-VoxAdaptiveSimulateFoldable")
    /// `-VoxAdaptiveForceTabletop`: always use the tabletop recording layout.
    static let debugForcesTabletop = arguments.contains("-VoxAdaptiveForceTabletop")
    /// `-VoxAdaptiveSection <capture|activity|library|settings>`: initial
    /// sidebar section at regular width (screenshots).
    static var debugInitialSection: String? {
        if let debugSectionOverride { return debugSectionOverride }
        guard let index = arguments.firstIndex(of: "-VoxAdaptiveSection"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    /// Test hook (hosted snapshot tests): wins over `-VoxAdaptiveSection`.
    nonisolated(unsafe) static var debugSectionOverride: String?

    /// `-VoxAdaptiveHinge <closed|partiallyOpen|open>`, or set from a hosted
    /// test: replaces the `UIHingeInteraction` state RootView publishes, so
    /// the Duo inner / tabletop paths render without unfolding the device.
    nonisolated(unsafe) static var debugHingeOverride: AdaptiveHingeState? = {
        guard let index = arguments.firstIndex(of: "-VoxAdaptiveHinge"),
              arguments.indices.contains(index + 1) else { return nil }
        switch arguments[index + 1] {
        case "closed": return .closed
        case "partiallyOpen": return .partiallyOpen
        case "open": return .open
        default: return nil
        }
    }()

    /// `-VoxForceLandscape`: once the first window scene connects, ask it to
    /// rotate to landscape right (iPad landscape screenshots without
    /// Simulator.app's rotate command).
    static let debugForcesLandscape = arguments.contains("-VoxForceLandscape")
    @MainActor private static var didRequestDebugLandscape = false

    @MainActor
    static func requestDebugLandscapeIfNeeded() {
        guard debugForcesLandscape, !didRequestDebugLandscape else { return }
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first else { return }
        didRequestDebugLandscape = true
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { error in
            print("[VoxForceLandscape] requestGeometryUpdate failed: \(error)")
        }
        print("[VoxForceLandscape] requested landscapeRight for \(scene.session.persistentIdentifier)")
    }
    #else
    static let debugSimulatesFoldable = false
    static let debugForcesTabletop = false
    static let debugInitialSection: String? = nil
    static let debugHingeOverride: AdaptiveHingeState? = nil
    #endif
}

// MARK: - Cover hint

/// Accent hint shown on a compact cover-sized window that can grow, pointing
/// at what the wide layout adds (DuoCoverCapture / DuoCoverRecording).
struct AdaptiveExpandHint: View {
    enum Kind { case capture, recording }
    let kind: Kind

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.split.2x1")
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            Text(message)
                .font(Geist.caption(.footnote))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(kind == .capture ? Geist.Palette.blue800 : Color(captureHex: 0x9A9A95))
        .padding(.horizontal, kind == .capture ? 12 : 0)
        .padding(.vertical, kind == .capture ? 8 : 0)
        .frame(maxWidth: .infinity, alignment: kind == .capture ? .leading : .center)
        .background {
            if kind == .capture {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Geist.accentSoft)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("adaptive_expand_hint")
    }

    private var message: LocalizedStringKey {
        switch kind {
        case .capture: "Open to see route steps and the “will write” preview"
        case .recording: "Open, or prop it up, to keep recording on the big screen"
        }
    }
}
