import SwiftUI
import VoxboardShared

// MARK: - App navigation

enum RootDestination: Hashable {
    case capture
    case history
    case settings
    case models
    case capturePresets
    case appLanguage

    #if DEBUG
    static var localizationScreenshotStory: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--localization-screenshot"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static var localizationScreenshotDestination: RootDestination? {
        switch localizationScreenshotStory {
        case "02-history": .history
        case "03-settings", "06-privacy-local", "07-keyboard", "09-app-language-row": .settings
        case "04-models": .models
        case "05-capture-presets": .capturePresets
        case "08-app-language": .appLanguage
        default: nil
        }
    }
    #endif
}

// MARK: - RootView

/// The capture composer is the app's root.
///
/// Compact width (iPhone, the Duo cover screen, narrow Split View) keeps the
/// single stack: secondary destinations open from the composer's action bar.
/// Regular width (iPad, Duo inner screen, wide Split View) is a
/// `NavigationSplitView`: a ROUTES / VIEWS sidebar and, for Capture, the
/// composer beside the route inspector. Below `AdaptiveLayout.sidebarMinimumWidth`
/// the sidebar tucks away and composer | route split the window evenly.
///
/// Recording state lives in `PersistentRecorder`, never in these views, so a
/// size-class change mid-recording only re-hosts the live recording surface.
struct RootView: View {
    @Bindable var persistentRecorder: PersistentRecorder
    @Bindable var quickCaptureViewModel: QuickCaptureViewModel
    @Binding var rootDestination: RootDestination
    @Binding var pendingKeyboardLaunch: Bool
    @Binding var pendingWidgetRecord: Bool

    @State private var captureToolbarPreferences = CaptureToolbarPreferences.shared

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var section: AdaptiveSection = AdaptiveSection(debugName: AdaptiveLayout.debugInitialSection) ?? .capture
    @State private var settingsDestination: RootDestination = .settings
    @State private var columnVisibility: NavigationSplitViewVisibility = .detailOnly
    @State private var composerCommands = CaptureComposerCommands()
    @State private var windowWidth: CGFloat = 0
    @State private var activityCount = 0
    @State private var hingeState: AdaptiveHingeState = .unavailable

    var body: some View {
        Group {
            // iPhone landscape is regular width on large phones but too short
            // for side-by-side panes, so it keeps the phone layout.
            if horizontalSizeClass == .regular, verticalSizeClass != .compact {
                regularRoot
            } else {
                captureRoot
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            windowWidth = width
        }
        .background(AdaptiveHingeObserver(state: $hingeState).frame(width: 0, height: 0))
        .environment(\.adaptiveHingeState, effectiveHingeState)
        .environment(
            \.adaptiveCanExpandWindow,
            AdaptiveLayout.canExpandWindow(horizontalSizeClass: horizontalSizeClass, hinge: effectiveHingeState)
        )
        .background(Geist.bg.ignoresSafeArea())
        .onChange(of: pendingWidgetRecord) { _, isPending in
            if isPending { showCapture() }
        }
        .onChange(of: pendingKeyboardLaunch) { _, isPending in
            if isPending { showCapture() }
        }
        #if DEBUG
        .task { await AdaptiveDebugSeed.applyIfRequested(to: quickCaptureViewModel) }
        .transformEnvironment(\.defersCaptureInputFocusForReleaseNotes) { defers in
            // `-VoxAdaptiveNoAutofocus`: keep the keyboard down for screenshots.
            if AdaptiveDebugSeed.suppressesAutofocus { defers = true }
        }
        #endif
    }

    /// The live hinge, unless a DEBUG override (`-VoxAdaptiveHinge`, hosted
    /// snapshot tests) stands in for it.
    private var effectiveHingeState: AdaptiveHingeState {
        AdaptiveLayout.debugHingeOverride ?? hingeState
    }

    private func showCapture() {
        rootDestination = .capture
        section = .capture
    }

    // MARK: Compact

    private var captureRoot: some View {
        NavigationStack {
            QuickCaptureView(
                viewModel: quickCaptureViewModel,
                persistentRecorder: persistentRecorder,
                pendingKeyboardLaunch: $pendingKeyboardLaunch,
                pendingWidgetRecord: $pendingWidgetRecord,
                captureToolbarPreferences: captureToolbarPreferences,
                openSettings: { rootDestination = .settings }
            )
            .navigationDestination(isPresented: secondaryDestinationIsPresented) {
                secondaryDestination
            }
        }
    }

    @ViewBuilder
    private var secondaryDestination: some View {
        destinationView(for: rootDestination)
    }

    @ViewBuilder
    private func destinationView(for destination: RootDestination) -> some View {
        switch destination {
        case .capture:
            EmptyView()
        case .history:
            HistoryView(viewModel: quickCaptureViewModel)
        case .settings:
            MetaSettingsView(
                persistentRecorder: persistentRecorder,
                captureToolbarPreferences: captureToolbarPreferences
            )
        case .models:
            ModelTabView()
        case .capturePresets:
            CapturePresetSettingsView()
        case .appLanguage:
            AppLanguageSettingsView()
        }
    }

    private var secondaryDestinationIsPresented: Binding<Bool> {
        Binding(
            get: { rootDestination != .capture },
            set: { if !$0 { rootDestination = .capture } }
        )
    }

    // MARK: Regular

    /// Wide enough for sidebar | composer | inspector (iPad landscape).
    private var usesSidebar: Bool {
        windowWidth >= AdaptiveLayout.sidebarMinimumWidth
    }

    /// A tap-to-record session takes the whole window (tabletop layout).
    private var recordingTakesOver: Bool {
        section == .capture && persistentRecorder.isAppRecordingSegmentActive
    }

    private var composerLayout: CaptureComposerLayout {
        usesSidebar && (columnVisibility != .detailOnly || recordingTakesOver)
            ? .regularSidebar
            : .regularPane
    }

    private var desiredColumnVisibility: NavigationSplitViewVisibility {
        usesSidebar && !recordingTakesOver ? .all : .detailOnly
    }

    private var regularRoot: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            AdaptiveSidebar(
                viewModel: quickCaptureViewModel,
                section: $section,
                activityCount: activityCount,
                selectRoute: selectRoute
            )
            .navigationSplitViewColumnWidth(260)
        } detail: {
            regularDetail
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: desiredColumnVisibility, initial: true) { _, visibility in
            withAnimation(.easeInOut(duration: 0.2)) { columnVisibility = visibility }
        }
        .onChange(of: rootDestination, initial: true) { _, destination in
            routeRegularDestination(destination)
        }
        .onChange(of: usesSidebar) { _, _ in routeRegularDestination(rootDestination) }
        .task { await refreshActivityCountWhileVisible() }
    }

    @ViewBuilder
    private var regularDetail: some View {
        switch section {
        case .capture:
            captureWorkspace
        case .activity:
            ActivityFeedView(
                viewModel: quickCaptureViewModel,
                persistentRecorder: persistentRecorder,
                onNewCapture: { section = .capture },
                showsBackButton: false
            )
        case .library:
            if quickCaptureViewModel.liveNotesEnabled {
                // Live Notes: the vault tree replaces the capture Library.
                VaultFilesView(viewModel: quickCaptureViewModel) { section = .capture }
            } else {
                AdaptiveLibrarySplit(viewModel: quickCaptureViewModel) { section = .capture }
            }
        case .settings:
            NavigationStack {
                destinationView(for: settingsDestination)
            }
            .id(settingsDestination)
        }
    }

    /// Composer | route inspector. In the sidebar layout the inspector is a
    /// fixed 300pt column; in the two-pane layout the panes split evenly.
    private var captureWorkspace: some View {
        NavigationStack {
            HStack(spacing: 0) {
                QuickCaptureView(
                    viewModel: quickCaptureViewModel,
                    persistentRecorder: persistentRecorder,
                    pendingKeyboardLaunch: $pendingKeyboardLaunch,
                    pendingWidgetRecord: $pendingWidgetRecord,
                    captureToolbarPreferences: captureToolbarPreferences,
                    openSettings: openSettingsFromComposer,
                    layout: composerLayout,
                    commands: composerCommands
                )
                .frame(maxWidth: .infinity)

                if !recordingTakesOver {
                    Rectangle()
                        .fill(Geist.border)
                        .frame(width: 1)
                        .ignoresSafeArea()
                    AdaptiveRouteInspector(
                        viewModel: quickCaptureViewModel,
                        layout: composerLayout,
                        commands: composerCommands
                    )
                    .frame(width: inspectorWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: recordingTakesOver)
            .navigationDestination(isPresented: paneDestinationIsPresented) {
                if rootDestination == .history {
                    AdaptiveLibrarySplit(viewModel: quickCaptureViewModel) { rootDestination = .capture }
                        .toolbar(.hidden, for: .navigationBar)
                } else {
                    secondaryDestination
                }
            }
        }
    }

    private var inspectorWidth: CGFloat {
        if composerLayout == .regularSidebar { return 300 }
        let visibleWidth = columnVisibility == .detailOnly ? windowWidth : windowWidth - 260
        return max(300, floor((visibleWidth - 1) / 2))
    }

    /// Only the two-pane layout pushes secondary screens over the composer;
    /// the sidebar layout shows them as sections instead.
    private var paneDestinationIsPresented: Binding<Bool> {
        Binding(
            get: { !usesSidebar && rootDestination != .capture },
            set: { if !$0 { rootDestination = .capture } }
        )
    }

    private func openSettingsFromComposer() {
        if usesSidebar {
            settingsDestination = .settings
            section = .settings
        } else {
            rootDestination = .settings
        }
    }

    /// With a sidebar, app-level destinations (deep links, widgets) select a
    /// section instead of pushing over the composer.
    private func routeRegularDestination(_ destination: RootDestination) {
        guard usesSidebar, destination != .capture else { return }
        switch destination {
        case .capture:
            break
        case .history:
            section = .library
        case .settings, .models, .capturePresets, .appLanguage:
            settingsDestination = destination
            section = .settings
        }
        rootDestination = .capture
    }

    private func selectRoute(_ route: CapturePresetProfile) {
        section = .capture
        if quickCaptureViewModel.selectVox(route.id) {
            WatchRecordingController.shared.publishState()
        }
    }

    private func refreshActivityCountWhileVisible() async {
        while !Task.isCancelled {
            var count = persistentRecorder.isAppRecordingTranscribing ? 1 : 0
            if let root = AppConstants.captureDirectoryURL {
                let inbox = CaptureInbox(rootDirectoryURL: root)
                for state in [CaptureInboxState.pending, .processing, .failed] {
                    count += (try? await inbox.requestIDs(in: state).count) ?? 0
                }
            }
            if activityCount != count { activityCount = count }
            try? await Task.sleep(for: .seconds(8))
        }
    }
}
