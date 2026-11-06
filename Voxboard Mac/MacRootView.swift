import AppKit
import ServiceManagement
import StoreKit
import SwiftUI
import UniformTypeIdentifiers
import VoxboardShared

extension Notification.Name {
    static let macNavigate = Notification.Name("VoxboardMacNavigate")
    static let macShowCapture = Notification.Name("VoxboardMacShowCapture")
    static let macChooseCaptureFiles = Notification.Name("VoxboardMacChooseCaptureFiles")
    static let macClearCaptureDraft = Notification.Name("VoxboardMacClearCaptureDraft")
    static let macSelectSettingsPane = Notification.Name("VoxboardMacSelectSettingsPane")
}

enum MacDestination: String, CaseIterable, Identifiable, Hashable, Sendable {
    case capture = "Capture"
    case activity = "Activity"
    case library = "Library"

    static let workDestinations: [MacDestination] = [.capture, .activity, .library]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: String(localized: "Capture")
        case .activity: String(localized: "Activity")
        case .library: String(localized: "Library")
        }
    }

    var symbol: String {
        switch self {
        case .capture: return "mic"
        case .activity: return "clock"
        case .library: return "books.vertical"
        }
    }
}

struct MacNavigationRequest: Sendable {
    let windowToken: String
    let destination: MacDestination
}

@MainActor
@Observable
final class MacNavigationState {
    var selectedDestination: MacDestination?
    /// Library "FILTER BY ROUTE": route IDs the person unchecked.
    var hiddenLibraryRouteIDs: Set<String> = []

    init(selectedDestination: MacDestination = .capture) {
        self.selectedDestination = selectedDestination
    }

    var destination: MacDestination {
        selectedDestination ?? .capture
    }

    func select(_ destination: MacDestination) {
        selectedDestination = destination
    }
}

struct MacRootView: View {
    private static let firstRunSetupCompletionKey = MacFirstRunSetupView.didFinishStorageKey

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(ModelManager.self) private var modelManager
    @Bindable var recorder: MacRecorder
    @Bindable var quickCaptureViewModel: QuickCaptureViewModel
    let windowCoordinator: MacWindowCoordinator
    @State private var navigationState: MacNavigationState
    @State private var windowToken = UUID().uuidString
    @State private var showsFirstRunSetup: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @AppStorage(firstRunSetupCompletionKey, store: AppConstants.sharedDefaults)
    private var hasCompletedFirstRunSetup = false

    #if DEBUG
    private static var localizationScreenshotStory: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--localization-screenshot"),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    #endif

    init(
        recorder: MacRecorder,
        quickCaptureViewModel: QuickCaptureViewModel,
        windowCoordinator: MacWindowCoordinator
    ) {
        self.recorder = recorder
        self.quickCaptureViewModel = quickCaptureViewModel
        self.windowCoordinator = windowCoordinator
        #if DEBUG
        let initialDestination: MacDestination = switch Self.localizationScreenshotStory {
        case "02-history": .library
        case "06-recording-queue": .activity
        default: .capture
        }
        #else
        let initialDestination: MacDestination = .capture
        #endif
        _navigationState = State(
            initialValue: MacNavigationState(selectedDestination: initialDestination)
        )
        let hasConfiguredDestination = CapturePresetStore.loadFlows()
            .contains { $0.isEnabled && $0.captureDestinationID != nil }
        let completedSetup = AppConstants.sharedDefaults?.bool(
            forKey: Self.firstRunSetupCompletionKey
        ) == true
        _showsFirstRunSetup = State(
            initialValue: !completedSetup && !hasConfiguredDestination
        )
    }

    var body: some View {
        @Bindable var navigation = navigationState

        NavigationSplitView(columnVisibility: $columnVisibility) {
            MacSidebar(
                navigationState: navigation,
                viewModel: quickCaptureViewModel,
                recorder: recorder
            )
            .navigationTitle("Vox.md")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            // Signal chrome: no sidebar toggle button (View › Hide Sidebar, ⌃⌘S).
            .toolbar(removing: .sidebarToggle)
        } detail: {
            #if DEBUG
            if Self.localizationScreenshotStory == "03-settings" {
                MacSettingsView(
                    recorder: recorder,
                    usesLocalizationScreenshotLayout: true
                )
            } else {
                selectedDetail
                    .environment(\.macContentUnderTitleBar, columnVisibility != .detailOnly)
            }
            #else
            selectedDetail
                .environment(\.macContentUnderTitleBar, columnVisibility != .detailOnly)
            #endif
        }
        // Hidden title bar: detail headers start at the window's top edge,
        // as on the boards; only the sidebar keeps the traffic-light inset.
        .navigationSplitViewStyle(.balanced)
        .tint(MacBrand.tint)
        .frame(minWidth: 960, minHeight: 640)
        .background(
            MacSceneWindowRegistrar(
                kind: .main(token: windowToken),
                coordinator: windowCoordinator
            )
        )
        .onAppear {
            windowCoordinator.configure(openWindow: openWindow)
            windowCoordinator.mainRootReady(token: windowToken)
            #if DEBUG
            // `--debug-navigate=activity|library`: visual QA of the main
            // window's other screens, selected once the window is up. (A bare
            // value argument would be opened as a document and suppress the
            // main window, so the value is joined with `=`.)
            if let raw = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("--debug-navigate=") })?
                .dropFirst("--debug-navigate=".count).lowercased(),
               let destination = MacDestination.allCases.first(where: { $0.rawValue.lowercased() == raw }) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { navigationState.select(destination) }
            }
            #endif
        }
        .onDisappear {
            windowCoordinator.mainRootNotReady(token: windowToken)
        }
        .onReceive(NotificationCenter.default.publisher(for: .macNavigate)) { notification in
            guard let request = notification.object as? MacNavigationRequest,
                  request.windowToken == windowToken else { return }
            navigationState.select(request.destination)
        }
        .sheet(isPresented: $showsFirstRunSetup) {
            MacFirstRunSetupView(
                viewModel: quickCaptureViewModel,
                onComplete: completeFirstRunSetup,
                onSkip: completeFirstRunSetup
            )
            .environment(modelManager)
        }
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch navigationState.destination {
        case .capture:
            MacCaptureWorkspaceView(
                viewModel: quickCaptureViewModel,
                recorder: recorder,
                windowToken: windowToken,
                windowCoordinator: windowCoordinator,
                openHistory: { navigationState.select(.library) },
                openSettings: { openSettings() },
                openModels: { openSettingsPane(.transcription) }
            )
        case .activity:
            MacActivityView(
                queue: recorder.recordingQueue,
                viewModel: quickCaptureViewModel,
                retryOverride: { job, delivery in
                    await recorder.recordingQueue.retry(
                        job,
                        modelID: modelManager.selectedModelId,
                        fallbackModelID: modelManager.preferredFallbackModelID,
                        replaceFallbackModelID: true,
                        language: modelManager.selectedLanguage,
                        delivery: delivery
                    )
                },
                openCapture: { navigationState.select(.capture) }
            )
        case .library:
            MacHistoryView(
                viewModel: quickCaptureViewModel,
                hiddenRouteIDs: navigationState.hiddenLibraryRouteIDs
            )
        }
    }

    private func completeFirstRunSetup() {
        hasCompletedFirstRunSetup = true
        showsFirstRunSetup = false
    }

    private func openSettingsPane(_ destination: MacSettingsDestination) {
        AppConstants.sharedDefaults?.set(
            destination.rawValue,
            forKey: MacSettingsDestination.storageKey
        )
        openSettings()
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .macSelectSettingsPane,
                object: destination.rawValue
            )
        }
    }
}

/// Signal sidebar. In Capture it shows ROUTES and ACTIVITY (MacWorkspace);
/// in Activity and Library it shows the Capture / Activity / Library list
/// (MacActivity, MacLibrary), plus FILTER BY ROUTE in Library.
struct MacSidebar: View {
    @Bindable var navigationState: MacNavigationState
    @Bindable var viewModel: QuickCaptureViewModel
    @Bindable var recorder: MacRecorder

    var body: some View {
        List {
            // The Signal boards (MacWorkspace, MacActivity, MacLibrary) have
            // no app-icon brand row: the sidebar starts with its first section.
            if navigationState.destination == .capture {
                routesSection
                activitySection
            } else {
                destinationsSection
                if navigationState.destination == .library {
                    libraryRouteFilterSection
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Geist.Palette.gray200)
    }

    private var sidebarRoutes: [CapturePresetProfile] {
        MacRouteCatalog.enabledRoutes(in: viewModel)
    }

    private var needsYouCount: Int {
        MacActivityCounts.needsYou(queue: recorder.recordingQueue, viewModel: viewModel)
    }

    /// ROUTES: letter tiles with ⌘1–⌘4. Choosing one sets the draft's route.
    private var routesSection: some View {
        Section {
            ForEach(Array(sidebarRoutes.enumerated()), id: \.element.id) { index, route in
                let isSelected = route.id == viewModel.selectedVoxProfile?.id
                Button {
                    MacRouteCatalog.select(route, in: viewModel)
                    navigationState.select(.capture)
                } label: {
                    HStack(spacing: 10) {
                        MacRouteTile(letter: MacRouteCatalog.letter(route), index: index)
                        Text(MacRouteCatalog.displayName(route))
                            .font(isSelected ? Geist.label(.callout) : Geist.body(.callout))
                            .foregroundStyle(Geist.text)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        if let key = MacRouteCatalog.shortcutLabel(forIndex: index) {
                            Text(verbatim: key)
                                .font(Geist.mono(size: 11, relativeTo: .caption))
                                .foregroundStyle(Geist.muted)
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 38)
                    .background { selectionBackground(isSelected) }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canChangeCaptureRoute)
                .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
                .accessibilityLabel(route.accessibilityName)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        } header: {
            sidebarHeader("ROUTES")
        }
    }

    /// ACTIVITY: Needs you / Delivered today open Activity (MacWorkspace has
    /// no Library row; Library is ⌃⌘3, the Navigate menu and Activity's
    /// sidebar).
    private var activitySection: some View {
        Section {
            activityShortcutRow(
                title: String(localized: "Needs you"),
                count: needsYouCount,
                color: MacBrand.attentionIndicator
            ) { navigationState.select(.activity) }
            activityShortcutRow(
                title: String(localized: "Delivered today"),
                count: MacActivityCounts.deliveredToday(viewModel.historyRecords).count,
                color: MacBrand.deliveredIndicator
            ) { navigationState.select(.activity) }
        } header: {
            sidebarHeader("ACTIVITY")
                .padding(.top, 12)
        }
    }

    private func activityShortcutRow(
        title: String,
        count: Int,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 8, height: 8).padding(.horizontal, 7)
                Text(title).font(Geist.body(.callout)).foregroundStyle(Geist.text)
                Spacer(minLength: 4)
                Text(count, format: .number)
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
        .accessibilityLabel("\(title), \(count)")
    }

    /// Capture ⌘N / Activity / Library, as in MacActivity and MacLibrary.
    private var destinationsSection: some View {
        Section {
            ForEach(MacDestination.workDestinations) { destination in
                destinationRow(destination)
            }
        }
    }

    private func destinationRow(_ destination: MacDestination) -> some View {
        let isSelected = navigationState.destination == destination
        return Button {
            navigationState.select(destination)
        } label: {
            HStack(spacing: 8) {
                Text(destination.title)
                    .font(isSelected ? Geist.label(.callout) : Geist.body(.callout))
                    .foregroundStyle(Geist.text)
                    .lineLimit(1)
                Spacer(minLength: 4)
                switch destination {
                case .capture:
                    Text(verbatim: "⌘N")
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundStyle(Geist.muted)
                case .activity:
                    // A count while Activity is open; an orange dot elsewhere.
                    if isSelected {
                        if needsYouCount > 0 {
                            Text(needsYouCount, format: .number)
                                .font(Geist.mono(size: 11, relativeTo: .caption))
                                .foregroundStyle(Geist.muted)
                        }
                    } else if needsYouCount > 0 {
                        Circle()
                            .fill(MacBrand.attentionIndicator)
                            .frame(width: 8, height: 8)
                            .accessibilityLabel("Needs you")
                    }
                case .library:
                    EmptyView()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background { selectionBackground(isSelected) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Library FILTER BY ROUTE checkboxes.
    private var libraryRouteFilterSection: some View {
        Section {
            ForEach(Array(viewModel.voxProfiles.enumerated()), id: \.element.id) { index, route in
                Toggle(isOn: Binding(
                    get: { !navigationState.hiddenLibraryRouteIDs.contains(route.id) },
                    set: { isOn in
                        if isOn {
                            navigationState.hiddenLibraryRouteIDs.remove(route.id)
                        } else {
                            navigationState.hiddenLibraryRouteIDs.insert(route.id)
                        }
                    }
                )) {
                    HStack(spacing: 10) {
                        MacRouteTile(letter: MacRouteCatalog.letter(route), index: index, size: 18)
                        Text(MacRouteCatalog.displayName(route))
                            .font(Geist.body(.callout))
                            .lineLimit(1)
                    }
                }
                .toggleStyle(.checkbox)
                // White check on the indigo fill; the lavender control tint
                // would leave the check unreadable in dark mode.
                .tint(MacBrand.accent)
                .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 4))
            }
        } header: {
            sidebarHeader("FILTER BY ROUTE")
                .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func selectionBackground(_ isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Geist.card)
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Geist.border, lineWidth: 1)
                }
        }
    }

    private func sidebarHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Geist.mono(size: 11, relativeTo: .caption))
            .tracking(0.66)
            .foregroundStyle(Geist.muted)
    }
}

#if DEBUG
/// Composer document rendering with sample Markdown (not the real draft).
private struct MacComposerScreenshotStory: View {
    @State private var text = "# Project sync\n- [ ] Review final designs\n- [x] Loop in design before Friday\n\nDecision: ship routing first and keep the composer as calm as it is now. The keyboard and Watch get the same route picker.\n![[2026-11-01-1042.m4a]]\n"
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var isFocused = false
    @State private var controller = MacMarkdownComposerController()

    var body: some View {
        MacMarkdownComposerTextView(
            text: $text,
            selection: $selection,
            isFocused: $isFocused,
            controller: controller,
            inlineAudio: [
                MacComposerInlineAudio(
                    id: "2026-11-01-1042.m4a",
                    url: URL(fileURLWithPath: "/dev/null/2026-11-01-1042.m4a"),
                    filename: "2026-11-01-1042.m4a",
                    speakerCount: 2
                ),
            ]
        )
    }
}

/// Hosts deterministic Mac feature surfaces for localization and visual QA.
struct MacLocalizationScreenshotRoot: View {
    @Bindable var recorder: MacRecorder
    @Bindable var quickCaptureViewModel: QuickCaptureViewModel
    let windowCoordinator: MacWindowCoordinator
    @State private var windowToken = UUID().uuidString

    private var story: String {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--localization-screenshot"),
              arguments.indices.contains(index + 1) else { return "01-capture" }
        return arguments[index + 1]
    }

    @ViewBuilder
    var body: some View {
        switch story {
        case "02-history":
            localizationWorkspace(selection: .library) {
                MacHistoryView(
                    viewModel: quickCaptureViewModel,
                    screenshotFixture: .localization
                )
            }
        case "03-settings":
            MacSettingsView(
                recorder: recorder,
                usesLocalizationScreenshotLayout: true
            )
        case "04-models":
            NavigationStack { MacModelView() }
        case "05-presets":
            NavigationStack { MacCapturePresetSettingsView() }
        case "06-recording-queue":
            localizationWorkspace(selection: .activity) {
                MacActivityView(
                    queue: recorder.recordingQueue,
                    viewModel: quickCaptureViewModel,
                    openCapture: {}
                )
            }
            .frame(minWidth: 1_180, minHeight: 760)
        case "07-capture-route-inspector":
            HStack(spacing: 0) {
                MacCaptureWorkspaceView(
                    viewModel: quickCaptureViewModel,
                    recorder: recorder,
                    windowToken: windowToken,
                    windowCoordinator: windowCoordinator,
                    openHistory: {},
                    openSettings: {},
                    openModels: {}
                )
                GeistDivider().frame(width: 1)
                MacCaptureRouteInspector(viewModel: quickCaptureViewModel)
                    .frame(width: 440)
            }
        case "09-composer-document":
            MacComposerScreenshotStory()
                .frame(width: 900, height: 760)
                .background(Geist.bg)
        case "10-quick-capture":
            MacQuickCaptureView(
                viewModel: quickCaptureViewModel,
                recorder: recorder,
                onClose: {},
                onToggleRecording: {},
                onOpenMain: {}
            )
            .padding(24)
            .background(Color(nsColor: NSColor(srgbRed: 0xCF / 255, green: 0xCF / 255, blue: 0xC8 / 255, alpha: 1)))
        case "08-first-run-setup":
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                MacFirstRunSetupView(
                    viewModel: quickCaptureViewModel,
                    onComplete: {},
                    onSkip: {}
                )
            }
        default:
            localizationWorkspace(selection: .capture) {
                MacCaptureWorkspaceView(
                    viewModel: quickCaptureViewModel,
                    recorder: recorder,
                    windowToken: windowToken,
                    windowCoordinator: windowCoordinator,
                    openHistory: {},
                    openSettings: {},
                    openModels: {}
                )
            }
        }
    }

    private func localizationWorkspace<Detail: View>(
        selection: MacDestination,
        @ViewBuilder detail: () -> Detail
    ) -> some View {
        NavigationSplitView {
            MacSidebar(
                navigationState: MacNavigationState(selectedDestination: selection),
                viewModel: quickCaptureViewModel,
                recorder: recorder
            )
            .navigationTitle("Vox.md")
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            // Signal chrome: no sidebar toggle button (View › Hide Sidebar, ⌃⌘S).
            .toolbar(removing: .sidebarToggle)
        } detail: {
            detail().environment(\.macContentUnderTitleBar, true)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(MacBrand.tint)
        .frame(minWidth: Self.storySize.width, minHeight: Self.storySize.height)
    }

    /// `--localization-screenshot-size 1280x820`; 1180×760 by default.
    static var storySize: CGSize {
        let arguments = ProcessInfo.processInfo.arguments
        let parts = arguments.firstIndex(of: "--localization-screenshot-size")
            .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }?
            .split(separator: "x").compactMap { Double($0) } ?? []
        return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : CGSize(width: 1_180, height: 760)
    }
}
#endif

// MARK: - Model

private struct MacModelView: View {
    @Environment(ModelManager.self) private var modelManager

    private var whisperModels: [WhisperModelInfo] {
        WhisperModelInfo.availableModels.filter { !$0.engine.isParakeet }
    }

    private var parakeetModels: [WhisperModelInfo] {
        WhisperModelInfo.availableModels.filter { $0.engine.isParakeet }
    }

    var body: some View {
        ZStack {
            Geist.surface.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    pageHeader("Use a compatible model already stored on this Mac, or download a model into Vox.md. Whisper models run through whisper.cpp + Metal.")
                    if let error = modelManager.modelOperationError {
                        modelErrorBanner(error)
                    }
                    languageSection
                    modelSection("02", "Whisper Models", models: whisperModels)
                    modelSection("03", "Parakeet Models", models: parakeetModels)
                }
            }
        }
        .navigationTitle("Transcription Models")
    }

    private func pageHeader(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Geist.caption())
            .foregroundColor(Geist.muted)
            .lineSpacing(3)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Geist.bg)
    }

    private func modelErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(MacBrand.attention)
            VStack(alignment: .leading, spacing: 3) {
                Text("Model Operation Failed")
                    .font(Geist.label())
                    .foregroundStyle(Geist.text)
                Text(message)
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .textSelection(.enabled)
            }
            Spacer()
            Button("Dismiss") {
                modelManager.modelOperationError = nil
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(MacBrand.attentionSoft)
        .overlay(alignment: .bottom) { GeistDivider() }
    }

    private func modelSection(_ number: String, _ title: LocalizedStringKey, models: [WhisperModelInfo]) -> some View {
        VStack(spacing: 0) {
            sectionHeader(number, title)
            GeistDivider()
            ForEach(models) { model in
                modelRow(model)
                GeistDivider()
            }
        }
    }

    private var languageSection: some View {
        VStack(spacing: 0) {
            sectionHeader("01", "Language")
            GeistDivider()
            HStack {
                Text("Transcription Language")
                    .font(Geist.label())
                    .foregroundColor(Geist.text)
                Spacer()
                Picker("Language", selection: Binding(
                    get: { modelManager.selectedLanguage },
                    set: { modelManager.selectedLanguage = $0 }
                )) {
                    ForEach(modelManager.availableLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }
                .frame(width: 220)
            }
            .padding(20)
            .background(Geist.bg)
        }
    }

    private func modelRow(_ model: WhisperModelInfo) -> some View {
        let installationSource = modelManager.installationSource(for: model)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.name)
                        .font(Geist.label())
                        .foregroundColor(Geist.text)
                    if model.isBundled {
                        Text("Bundled")
                            .font(Geist.caption())
                            .foregroundColor(Geist.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Geist.borderHi, lineWidth: 1))
                    }
                    if model.engine.isParakeet {
                        Text("Core ML")
                            .font(Geist.caption())
                            .foregroundColor(Geist.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Geist.border, lineWidth: 1))
                    }
                    if installationSource == .external {
                        Text("Existing Install")
                            .font(Geist.caption())
                            .foregroundColor(Geist.muted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Geist.border, lineWidth: 1))
                    }
                }
                Text(model.sizeLabel)
                    .font(Geist.caption())
                    .foregroundColor(Geist.muted)
                if let description = model.localizedModelDescription {
                    Text(description)
                        .font(Geist.caption())
                        .foregroundColor(Geist.muted)
                }
            }
            Spacer()
            modelAction(model, installationSource: installationSource)
        }
        .padding(20)
        .background(Geist.bg)
    }

    @ViewBuilder
    private func modelAction(
        _ model: WhisperModelInfo,
        installationSource: ModelInstallationSource?
    ) -> some View {
        if modelManager.isModelDownloaded(model) {
            HStack(spacing: 12) {
                if modelManager.selectedModelId == model.id {
                    Text("Selected")
                        .font(Geist.caption())
                        .foregroundColor(Geist.text)
                } else {
                    Button("Select") { modelManager.selectModel(model) }
                        .font(Geist.caption())
                        .foregroundColor(Geist.text)
                        .buttonStyle(.plain)
                }
                if installationSource == .external {
                    Button("Stop Using") { modelManager.forgetExternalModel(model) }
                        .font(Geist.caption())
                        .foregroundColor(MacBrand.attention)
                        .buttonStyle(.plain)
                        .help("Stops using this model without deleting it from your Mac.")
                } else {
                    Button("Remove") { modelManager.deleteModel(model) }
                        .font(Geist.caption())
                        .foregroundColor(MacBrand.attention)
                        .buttonStyle(.plain)
                }
            }
        } else if let state = modelManager.downloadState(for: model.id) {
            HStack(spacing: 8) {
                VStack(alignment: .trailing, spacing: 4) {
                    Group {
                        if let progress = state.fractionCompleted {
                            ProgressView(value: progress)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: 110)
                    .tint(Geist.text)

                    Text(downloadStatusText(state))
                        .font(Geist.caption())
                        .foregroundColor(Geist.muted)
                    Text("Keep Vox.md open")
                        .font(Geist.caption(.caption))
                        .foregroundColor(Geist.faint)
                }
                Button("Cancel") { modelManager.cancelDownload(model) }
                    .font(Geist.caption())
                    .foregroundColor(MacBrand.attention)
                    .buttonStyle(.plain)
                    .disabled(state.isCancelling)
            }
        } else {
            HStack(spacing: 8) {
                Button {
                    chooseExistingModel(model)
                } label: {
                    Text("Use Existing…")
                        .font(Geist.caption())
                        .foregroundColor(Geist.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Geist.borderHi, lineWidth: 1))
                }
                .buttonStyle(.plain)

                Button {
                    modelManager.startDownload(model)
                } label: {
                    Text("Download")
                        .font(Geist.caption())
                        .foregroundColor(Geist.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Geist.borderHi, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chooseExistingModel(_ model: WhisperModelInfo) {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Use Existing \(model.name) Model")
        panel.prompt = String(localized: "Use Model")
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true

        if model.engine.isParakeet {
            panel.message = String(localized: "Choose the folder containing Preprocessor.mlmodelc, Encoder.mlmodelc, Decoder.mlmodelc, JointDecision.mlmodelc, and parakeet_vocab.json.")
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
        } else {
            panel.message = String(localized: "Choose the existing GGML .bin file for \(model.name). Vox.md will use it in place without copying it.")
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [UTType(filenameExtension: "bin") ?? .data]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        modelManager.useExistingModel(model, at: url)
    }

    private func downloadStatusText(_ state: ModelDownloadState) -> String {
        switch state.phase {
        case .preparing:
            return String(localized: "Preparing…")
        case .listingFiles:
            return String(localized: "Finding files…")
        case .verifying:
            return String(localized: "Verifying…")
        case .cancelling:
            return String(localized: "Cancelling…")
        case .transferring:
            if let fileProgressDescription = state.fileProgressDescription {
                return fileProgressDescription
            }
            if let progress = state.fractionCompleted {
                return progress.formatted(.percent.precision(.fractionLength(0)))
            }
            return String(localized: "Downloading…")
        }
    }
}

// MARK: - Capture Presets

private struct MacCapturePresetSettingsView: View {
    @State private var flows: [CapturePreset] = CapturePresetStore.loadFlows()
    @State private var selectedFlowId: String = CapturePresetStore.selectedFlowId()
    @State private var deletionError: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("CAPTURE PRESETS")
                        .font(Geist.label())
                        .foregroundColor(Geist.text)
                    Spacer()
                    Button { addFlow() } label: { Image(systemName: "plus") }
                        .buttonStyle(.plain)
                }
                .padding(16)
                GeistDivider()
                List(selection: $selectedFlowId) {
                    ForEach(flows) { flow in
                        Label {
                            Text(flow.visibleName ?? String(localized: "Icon-only route"))
                                .foregroundStyle(flow.visibleName == nil ? .secondary : .primary)
                        } icon: {
                            CapturePresetIconView(symbolName: flow.symbolName, emoji: flow.emoji)
                        }
                        .accessibilityLabel(flow.accessibilityName)
                        .tag(flow.id)
                    }
                }
                .listStyle(.sidebar)
            }
            .background(Geist.surface)
            .frame(width: 260)
            GeistDivider().frame(width: 1)

            if let index = flows.firstIndex(where: { $0.id == selectedFlowId }) {
                MacCapturePresetEditor(preset: $flows[index], onDelete: { delete(flows[index]) })
                    .id(flows[index].id)
            } else {
                Text("Select a Route")
                    .font(Geist.body())
                    .foregroundColor(Geist.muted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Geist.surface)
        .navigationTitle("Routes")
        .onAppear { reload() }
        .onChange(of: flows) { _, newValue in CapturePresetStore.saveFlows(newValue) }
        .alert("Route Could Not Be Deleted", isPresented: Binding(
            get: { deletionError != nil }, set: { if !$0 { deletionError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(deletionError ?? "") }
        .onChange(of: selectedFlowId) { _, id in CapturePresetStore.selectFlow(id: id) }
    }

    private func reload() {
        flows = CapturePresetStore.loadFlows()
        selectedFlowId = CapturePresetStore.selectedFlowId()
    }

    private func addFlow() {
        let flow = CapturePresetStore.makeCustomFlow()
        flows.append(flow)
        selectedFlowId = flow.id
    }

    private func delete(_ flow: CapturePreset) {
        guard !flow.isBuiltIn else { return }
        do {
            try URLDeliveryKeychain.deleteCredentials(for: flow.exportSettings.urlDelivery)
        } catch {
            deletionError = String(localized: "Saved URL credentials could not be removed. Try again after the Keychain is available. The route has not been deleted.")
            return
        }
        let selectedCapturePresetID = CapturePresetProfileStore.selectedProfileID(
            defaults: AppConstants.sharedDefaults
        )
        CapturePresetStore.retirePreset(
            id: flow.id,
            ownedRouteID: flow.captureDestinationID
        )
        flows.removeAll { $0.id == flow.id }
        let fallbackID = flows.first?.id ?? CapturePresetStore.generalId
        selectedFlowId = fallbackID
        CapturePresetStore.selectFlow(id: fallbackID)
        if selectedCapturePresetID == flow.id {
            CapturePresetProfileStore.selectCaptureProfile(
                id: fallbackID,
                defaults: AppConstants.sharedDefaults
            )
        }
    }
}

struct MacAudioFilenameTemplateSetting: View {
    @Binding var template: String
    let isAudioSavingEnabled: Bool
    let presetName: String

    @ViewBuilder
    var body: some View {
        if isAudioSavingEnabled {
            VStack(alignment: .leading, spacing: 6) {
                Text("Audio Filename Template")
                TextField(
                    "Audio Filename Template",
                    text: $template,
                    prompt: Text("Automatic")
                )
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Audio Filename Template")
                .accessibilityHint("Leave blank to retain the existing automatic name. Typed extensions are replaced by the real audio extension, and unsafe path characters are sanitized.")
                .accessibilityIdentifier("mac_preset_audio_filename_template")

                Group {
                    if let previewFilename {
                        Text("Example: \(previewFilename)")
                    } else {
                        Text("Example: Existing automatic name")
                    }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("mac_preset_audio_filename_preview")

                Text("Tokens: {timestamp}, {date}, {time}, {YR}, {id}, {id8}, {preset}, {original}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Leave blank to retain the existing automatic name. A typed extension is ignored and replaced by the real encoded or copied audio extension. Unsafe and path characters are sanitized.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("mac_preset_audio_filename_setting")
        }
    }

    var previewFilename: String? {
        CapturePresetAudioFilename.preferredFilename(
            template: template,
            context: CapturePresetAudioFilenameContext(
                identifier: "12345678-90AB-CDEF-1234-567890ABCDEF",
                createdAt: Date(timeIntervalSince1970: 1_704_164_645),
                presetName: presetName,
                originalFilename: "recording.wav",
                timeZone: TimeZone(secondsFromGMT: 0)!
            ),
            sourceExtension: "m4a"
        )
    }
}

private struct MacCapturePresetEditor: View {
    @Binding var flow: CapturePreset
    let onDelete: () -> Void
    @State private var frontmatterText: String
    @State private var isIconPickerPresented = false
    @State private var captureDestinations: [CaptureDestination] = []
    @State private var captureEntryTemplates: [CaptureEntryTemplate] = []
    @State private var captureDestinationLoadError: String?
    @State private var isEditingDestination = false
    @State private var isCaptureProcessingInfoPresented = false
    @AppStorage(
        CapturePresetProfileStore.selectedCaptureProfileIDKey,
        store: AppConstants.sharedDefaults
    ) private var selectedCaptureVoxID = ""

    init(preset: Binding<CapturePreset>, onDelete: @escaping () -> Void) {
        self._flow = preset
        self.onDelete = onDelete
        self._frontmatterText = State(initialValue: Self.renderFrontmatter(preset.wrappedValue.staticFrontmatter))
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField(
                    "Name (optional)",
                    text: Binding(
                        get: { flow.name },
                        set: { flow.name = $0 }
                    )
                )
                Button {
                    isIconPickerPresented = true
                } label: {
                    HStack(spacing: 10) {
                        Text("Icon")
                        Spacer()
                        CapturePresetIconView(symbolName: flow.symbolName, emoji: flow.emoji)
                            .frame(width: 24)
                            .foregroundStyle(.secondary)
                        Text(CapturePresetEmoji.normalized(flow.emoji) != nil
                             ? String(localized: "Emoji")
                             : MacFlowIconPickerView.title(for: flow.symbolName))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Icon for \(flow.accessibilityName)")
                .accessibilityValue(CapturePresetEmoji.normalized(flow.emoji)
                                    ?? MacFlowIconPickerView.title(for: flow.symbolName))
                .accessibilityIdentifier("mac_preset_icon_picker")
                Toggle("Enabled", isOn: $flow.isEnabled)
                if selectedCaptureVoxID == flow.id {
                    Label("Default for Capture", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                } else {
                    Button("Use as Capture Default") {
                        CapturePresetProfileStore.selectCaptureProfile(
                            id: flow.id,
                            defaults: AppConstants.sharedDefaults
                        )
                        selectedCaptureVoxID = flow.id
                    }
                    .disabled(!flow.isEnabled)
                }
            }

            Section("Capture Processing") {
                HStack(spacing: 10) {
                    Toggle("Use Apple Intelligence", isOn: $flow.captureProcessingEnabled)
                    Button {
                        isCaptureProcessingInfoPresented = true
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("About Apple Intelligence Processing")
                    .accessibilityLabel("About Apple Intelligence Processing")
                }
                ImageAltTextSettings(
                    generateImageAltText: $flow.generateImageAltText,
                    processingEnabled: flow.captureProcessingEnabled
                )

                Picker("Mode", selection: $flow.postProcessingMode) {
                    ForEach(CapturePresetProcessingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if flow.captureProcessingEnabled {
                    Picker("Apply To", selection: $flow.captureProcessingScope) {
                        ForEach(CapturePresetProcessingScope.allCases) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                }
                if flow.postProcessingMode == .custom {
                    TextEditor(text: $flow.customPostProcessingInstruction)
                        .frame(minHeight: 90)
                }
                TextField(
                    "Empty Capture Prompt",
                    text: Binding(
                        get: { flow.displayCapturePrompt },
                        set: { flow.capturePrompt = $0 }
                    )
                )
                if flow.postProcessingMode != .none {
                    if flow.captureProcessingEnabled {
                        switch flow.captureProcessingScope {
                        case .both:
                            Label("Voice transcriptions and typed Capture text are processed on device using this mode.", systemImage: "waveform")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .voiceOnly:
                            Label("Only voice transcriptions are processed; typed Capture text stays exactly as captured.", systemImage: "waveform")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .textOnly:
                            Label("Only typed Capture text is processed; voice transcriptions stay exactly as captured.", systemImage: "waveform")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Label("Apple Intelligence is off — turn it on above to apply this mode to voice transcriptions and Capture text.", systemImage: "waveform")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(flow.postProcessingMode.helpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Destination") {
                if let destination = ownedDestination {
                    LabeledContent("Vault / Folder", value: destination.rootName)
                    Text(captureDestinationSummary(destination))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Button("Edit Destination…") {
                        isEditingDestination = true
                    }
                } else {
                    Text("Choose a vault or folder and define where this route writes Markdown.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Set Up Destination…") {
                        isEditingDestination = true
                    }
                }
                if let captureDestinationLoadError {
                    Text(captureDestinationLoadError)
                        .font(.caption)
                        .foregroundStyle(MacBrand.attention)
                }
                Text("This destination belongs to this route, including its note target, placement, formatting, attachments, and retry behavior.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if flow.captureDestinationID == nil {
                Section("Legacy Voice File Export") {
                Toggle("Save Notes to Files", isOn: $flow.exportSettings.exportEnabled)
                    .onChange(of: flow.exportSettings.exportEnabled) { _, _ in markPerFlow() }
                if flow.exportSettings.exportEnabled {
                    Button { chooseFolder(.exportFolder) } label: {
                        settingRow("Export Directory", value: flow.exportSettings.folderName, image: "folder")
                    }
                    Picker("Format", selection: $flow.exportSettings.format) {
                        ForEach(ExportFileFormat.allCases, id: \.self) { format in
                            Text(format.rawValue.uppercased()).tag(format)
                        }
                    }
                    Picker("Mode", selection: $flow.exportSettings.mode) {
                        Text("New File").tag(ExportFileMode.newFile)
                        Text("Append").tag(ExportFileMode.append)
                    }
                    if flow.exportSettings.mode == .newFile {
                        TextField("Filename Template", text: $flow.exportSettings.newFileNameTemplate)
                        Text("Tokens: {timestamp}, {date}, {time}, {YR} (2-digit year), {id8}, {id}, {model}, {language}")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        TextField("Append Filename", text: $flow.exportSettings.appendFileName)
                    }
                    Toggle("Obsidian Bases", isOn: $flow.exportSettings.mdObsidianEnabled)
                    Toggle("Use Markdown Template", isOn: $flow.exportSettings.markdownTemplateEnabled)
                    if flow.exportSettings.markdownTemplateEnabled {
                        Button { chooseFolder(.markdownTemplate) } label: {
                            settingRow("Markdown Template", value: flow.exportSettings.markdownTemplateName, image: "doc.text")
                        }
                    }
                }
                }
            }

            URLDeliverySettingsSection(settings: $flow.exportSettings.urlDelivery)

            Section("Metadata") {
                TextField("Transcript Property", text: $flow.transcriptPropertyName, prompt: Text("note"))
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("preset_transcript_property")
                if !flow.transcriptPropertyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if TranscriptPropertyMapping.normalizedKey(flow.transcriptPropertyName) != nil {
                        Toggle("Also Include Transcript in Body", isOn: $flow.includeTranscriptInBody)
                            .accessibilityIdentifier("preset_transcript_include_body")
                        Text("Voice transcripts fill this note property. Later captures to the same note replace its value.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Use letters, numbers, underscores, or hyphens for the property name.")
                            .font(.caption)
                            .foregroundStyle(MacBrand.orangeText)
                    }
                } else {
                    Text("Leave empty to keep voice transcripts in the note body.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Scope", selection: $flow.metadataScope) {
                    ForEach(CapturePresetMetadataScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                Text(flow.metadataScope == .document
                     ? "Use note frontmatter for one-note-per-capture routes."
                     : "Use inline key:: value fields to keep rolling-note entries separate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $frontmatterText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 110)
                    .onChange(of: frontmatterText) { _, text in flow.staticFrontmatter = Self.parseFrontmatter(text) }
            }

            Section("Location") {
                Toggle("Use Current Location", isOn: $flow.locationPolicy.isEnabled)
                    .accessibilityIdentifier("mac_preset_location_enabled")

                if flow.locationPolicy.isEnabled {
                    Text("Entry formatting can use {location} without writing additional metadata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Precision", selection: $flow.locationPolicy.precision) {
                        Text("Exact").tag(CaptureLocationPrecision.exact)
                        Text("City").tag(CaptureLocationPrecision.city)
                    }
                    .accessibilityIdentifier("mac_preset_location_precision")
                    Picker("When Location Is Unavailable", selection: $flow.locationPolicy.unavailableBehavior) {
                        Text("Ask").tag(CaptureLocationUnavailableBehavior.ask)
                        Text("Send Without Location").tag(CaptureLocationUnavailableBehavior.sendWithoutLocation)
                        Text("Cancel Capture").tag(CaptureLocationUnavailableBehavior.cancel)
                    }
                    .accessibilityIdentifier("mac_preset_location_unavailable_behavior")
                    Toggle("Write Location Metadata", isOn: $flow.locationPolicy.metadataOutputEnabled)
                        .accessibilityIdentifier("mac_preset_location_metadata_output_enabled")

                    if flow.locationPolicy.metadataOutputEnabled {
                        Picker("Configuration", selection: $flow.locationPolicy.outputMode) {
                            Text("Structured Fields").tag(CaptureLocationOutputMode.structured)
                            Text("Advanced YAML Template")
                                .tag(CaptureLocationOutputMode.advancedTemplate)
                                .disabled(flow.metadataScope == .entry)
                        }
                        .accessibilityIdentifier("mac_preset_location_output_mode")

                        if flow.locationPolicy.outputMode == .advancedTemplate,
                           flow.metadataScope == .entry {
                            Label(
                                String(localized: "Advanced YAML Template") + " · " + String(localized: "Use Note Frontmatter Scope"),
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.caption)
                            .foregroundStyle(MacBrand.attention)
                            .accessibilityIdentifier("mac_preset_location_scope_error")
                            Button("Use Note Frontmatter Scope") {
                                flow.metadataScope = .document
                            }
                        }

                        if flow.metadataScope == .document {
                            TextField("Name", text: $flow.locationPolicy.collectionKey)
                                .font(.system(.body, design: .monospaced))
                                .accessibilityIdentifier("mac_preset_location_collection_key")
                            Text("Each Capture is appended to this collection by Capture ID, so a note can retain multiple locations without replacing earlier ones.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Inline Entry Fields writes the selected `key:: value` fields beside each captured entry. No frontmatter collection is written.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if flow.locationPolicy.outputMode == .structured {
                            ForEach(CaptureLocationField.allCases, id: \.self) { field in
                                Toggle(field.configurationDisplayName, isOn: locationFieldSelection(field))
                                if flow.locationPolicy.structuredFields.contains(where: { $0.field == field }) {
                                    TextField("Output", text: locationOutputKey(field))
                                        .font(.system(.body, design: .monospaced))
                                        .accessibilityLabel(
                                            String(localized: "Output") + " · " + field.configurationDisplayName
                                        )
                                        .accessibilityIdentifier("mac_preset_location_key_\(field.rawValue)")
                                }
                            }
                        } else {
                            TextEditor(text: $flow.locationPolicy.advancedTemplate)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 160)
                                .accessibilityLabel("Advanced YAML Template")
                                .accessibilityIdentifier("mac_preset_location_advanced_template")
                            Text("Nested mappings and list items are supported. Use placeholders such as `{{coordinates}}`, `{{city}}`, `{{timestamp}}`, and `{{id}}`.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        locationPolicyPreview

                        Text("Place, city, region, and country use Apple's system reverse geocoder only when selected and may make a network request.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No frontmatter collection or inline location fields will be written. The {location} template token still works.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("Provider links disclose the privacy-adjusted coordinates to Apple, Google, or OpenStreetMap only when you open a link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Reset Location Unavailable Choice") {
                    flow.locationPolicy.unavailableBehavior = .ask
                }
                .disabled(flow.locationPolicy.unavailableBehavior == .ask)
                .accessibilityIdentifier("mac_preset_location_reset_unavailable")

                Button("Reset Location Configuration", role: .destructive) {
                    flow.locationPolicy = CapturePresetLocationPolicy()
                }
                .accessibilityIdentifier("mac_preset_location_reset_configuration")
                Text("Location is requested once at Capture send or recording stop. Exact keeps the origin fix; City rounds coordinates and omits a point-of-interest label. Vox.md does not track location in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice Processing") {
                Toggle("Identify Speakers", isOn: $flow.speakerDiarizationEnabled)
                    .accessibilityIdentifier("mac_preset_identify_speakers")
                if flow.speakerDiarizationEnabled {
                    Label("Speaker labels are added after transcription.", systemImage: "person.2.wave.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("Detects and labels multiple voices entirely on device. The speaker model downloads the first time this route uses it. Identification is best-effort; if it cannot run, Vox.md keeps the normal transcript and shows why in Library.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Voice Audio") {
                Picker("Save Audio", selection: $flow.audioSaveMode) {
                    ForEach(CapturePresetAudioSaveMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                if flow.audioSaveMode == .attachmentsFolder {
                    if flow.captureDestinationID != nil {
                        TextField("Attachments Folder", text: $flow.attachmentsFolderName)
                        Text("Relative to the unified Markdown destination. Leave blank to use its default attachment folder.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Button { chooseFolder(.audioFolder) } label: {
                            settingRow("Audio Export Directory", value: flow.exportSettings.audioFolderName, image: "folder")
                        }
                        TextField("Attachments Folder", text: $flow.attachmentsFolderName)
                    }
                }
                MacAudioFilenameTemplateSetting(
                    template: $flow.audioFilenameTemplate,
                    isAudioSavingEnabled: flow.audioSaveMode != .off,
                    presetName: flow.visibleName ?? ""
                )
                if flow.audioSaveMode != .off {
                    Toggle("Embed Audio in Markdown", isOn: $flow.exportSettings.embedAudioInMarkdown)
                        .disabled(!markdownAudioEmbedAvailable)
                        .onChange(of: flow.exportSettings.embedAudioInMarkdown) { _, _ in markPerFlow() }
                    if flow.exportSettings.embedAudioInMarkdown && markdownAudioEmbedAvailable {
                        Picker("Embed Position", selection: $flow.exportSettings.audioEmbedPlacement) {
                            ForEach(CapturePresetAudioEmbedPlacement.allCases) { placement in
                                Text(placement.displayName).tag(placement)
                            }
                        }
                        .onChange(of: flow.exportSettings.audioEmbedPlacement) { _, _ in markPerFlow() }
                    }
                    Text(markdownAudioEmbedHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !flow.isBuiltIn {
                Section {
                    Button("Delete Route", role: .destructive, action: onDelete)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 18)
        .navigationTitle(flow.visibleName ?? String(localized: "Route"))
        .sheet(isPresented: $isIconPickerPresented) {
            MacFlowIconPickerView(
                presetName: flow.accessibilityName,
                symbolName: flow.symbolName,
                emoji: flow.emoji
            ) { symbolName, emoji in
                // Commit the pair together through the existing settings save
                // boundary. Typing, mode changes and Cancel never edit `flow`.
                var updated = flow
                updated.symbolName = symbolName
                updated.emoji = emoji
                flow = updated
            }
        }
        .sheet(isPresented: $isEditingDestination) {
            MacCaptureDestinationEditor(
                existing: ownedDestination,
                templates: captureEntryTemplates,
                fixedName: flow.visibleName ?? String(localized: "Icon-only route")
            ) { destination in
                try await saveOwnedDestination(destination)
            }
        }
        .sheet(isPresented: $isCaptureProcessingInfoPresented) {
            MacCaptureTextProcessingInfoView()
        }
        .task { await loadCaptureDestinations() }
        .onAppear { flow.exportSettings.usesCustomExportSettings = true }
        .onDisappear { flow.staticFrontmatter = Self.parseFrontmatter(frontmatterText) }
    }

    private func locationFieldSelection(_ field: CaptureLocationField) -> Binding<Bool> {
        Binding(
            get: { flow.locationPolicy.structuredFields.contains(where: { $0.field == field }) },
            set: { isSelected in
                flow.locationPolicy.structuredFields.removeAll { $0.field == field }
                if isSelected {
                    flow.locationPolicy.structuredFields.append(
                        CaptureLocationStructuredField(field: field)
                    )
                }
            }
        )
    }

    private func locationOutputKey(_ field: CaptureLocationField) -> Binding<String> {
        Binding(
            get: {
                flow.locationPolicy.structuredFields.first(where: { $0.field == field })?.outputKey
                    ?? field.rawValue
            },
            set: { value in
                guard let index = flow.locationPolicy.structuredFields.firstIndex(where: {
                    $0.field == field
                }) else { return }
                flow.locationPolicy.structuredFields[index].outputKey = value
            }
        )
    }

    @ViewBuilder
    private var locationPolicyPreview: some View {
        switch CaptureLocationConfigurationPreview.result(
            profile: flow.captureProfile,
            source: .mac
        ) {
        case .success(let preview):
            VStack(alignment: .leading, spacing: 6) {
                Label("Delivery Preview", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(MacBrand.success)
                Text(preview)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("mac_preset_location_preview")
        case .failure(let error):
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(MacBrand.attention)
                .accessibilityIdentifier("mac_preset_location_validation_error")
        }
    }

    private enum BookmarkKind {
        case exportFolder, audioFolder, markdownTemplate
    }

    private var ownedDestination: CaptureDestination? {
        guard let id = flow.captureDestinationID else { return nil }
        return captureDestinations.first(where: { $0.id == id })
    }

    private func saveOwnedDestination(_ submittedDestination: CaptureDestination) async throws {
        guard let url = AppConstants.captureLibraryURL else {
            throw MacCapturePresetDestinationError.storageUnavailable
        }
        let destination = CapturePresetStore.migratingLegacyMarkdownTemplate(
            into: submittedDestination,
            from: flow.exportSettings
        )
        let library = try await CaptureLibraryStore(fileURL: url).update { library in
            if let index = library.destinations.firstIndex(where: { $0.id == destination.id }) {
                library.destinations[index] = destination
            } else {
                library.destinations.append(destination)
            }
            if library.defaultDestinationID == nil {
                library.defaultDestinationID = destination.id
            }
        }
        flow.captureDestinationID = destination.id
        flow.captureEntryTemplateID = nil
        flow.capturePlacementOverride = nil
        if destination.markdownTemplatePath != nil {
            flow.exportSettings.markdownTemplateEnabled = false
            flow.exportSettings.markdownTemplateBookmark = nil
            flow.exportSettings.markdownTemplateName = ""
        }
        captureDestinations = library.destinations
        captureEntryTemplates = library.entryTemplates
        captureDestinationLoadError = nil
    }

    private func loadCaptureDestinations() async {
        guard let url = AppConstants.captureLibraryURL else {
            captureDestinationLoadError = String(localized: "Shared capture storage is unavailable.")
            return
        }
        do {
            let store = CaptureLibraryStore(fileURL: url)
            let library = try await CapturePresetRouteLibrary.load(from: store)
            captureDestinations = library.destinations
            captureEntryTemplates = library.entryTemplates
            if let refreshed = CapturePresetStore.flow(id: flow.id) {
                // Route migration owns only these fields. Keep any edits made
                // while the asynchronous load was in flight.
                flow.captureDestinationID = refreshed.captureDestinationID
                flow.captureEntryTemplateID = refreshed.captureEntryTemplateID
                flow.capturePlacementOverride = refreshed.capturePlacementOverride
                if let routeID = refreshed.captureDestinationID,
                   library.destinations.first(where: { $0.id == routeID })?.markdownTemplatePath != nil {
                    flow.exportSettings.markdownTemplateEnabled = false
                    flow.exportSettings.markdownTemplateBookmark = nil
                    flow.exportSettings.markdownTemplateName = ""
                }
            }
            captureDestinationLoadError = nil
        } catch {
            captureDestinationLoadError = error.localizedDescription
        }
    }

    private func captureDestinationSummary(_ destination: CaptureDestination) -> String {
        let target: String
        switch destination.noteTarget {
        case .newNote(let path): target = path
        case .rollingNote(let path, let period):
            target = String(localized: "\(period.rawValue.capitalized): \(path)")
        case .existingNote(let path): target = path
        }
        let placement: String
        switch destination.placement {
        case .append: placement = String(localized: "append")
        case .prepend: placement = String(localized: "prepend")
        case .beneathHeading(let heading, _, let position):
            placement = position == .bottom
                ? String(localized: "end of \(heading.title)")
                : String(localized: "under \(heading.title)")
        }
        return "\(target) · \(placement)"
    }

    private func settingRow(_ title: LocalizedStringKey, value: String, image: String) -> some View {
        HStack {
            Label(title, systemImage: image)
            Spacer()
            Text(value.isEmpty ? String(localized: "Not set") : value)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }

    private var markdownAudioEmbedAvailable: Bool {
        if flow.captureDestinationID != nil { return true }
        guard flow.exportSettings.exportEnabled else { return false }
        if flow.exportSettings.markdownTemplateEnabled { return true }
        if flow.exportSettings.format == .md { return true }
        return flow.exportSettings.format == .yaml && flow.exportSettings.yamlUsesMarkdownExtension
    }

    private var markdownAudioEmbedHelpText: String {
        if flow.captureDestinationID != nil {
            return String(localized: "Adds an Obsidian-style audio link to the unified Markdown note at the selected position.")
        }
        guard markdownAudioEmbedAvailable else {
            return String(localized: "Audio embeds require a Markdown note export. Switch this route to MD, a Markdown template, or YAML with the .md extension.")
        }
        return String(localized: "Adds an Obsidian-style `![[recording.m4a]]` link to the note so you can replay the recording while reviewing the transcript.")
    }

    private func markPerFlow() {
        flow.exportSettings.usesCustomExportSettings = true
    }

    private func chooseFolder(_ kind: BookmarkKind) {
        markPerFlow()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = kind != .markdownTemplate
        panel.canChooseFiles = kind == .markdownTemplate
        panel.allowedContentTypes = kind == .markdownTemplate ? [.plainText, .text, UTType(filenameExtension: "md") ?? .plainText] : []
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let didScope = url.startAccessingSecurityScopedResource()
        defer { if didScope { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        switch kind {
        case .exportFolder:
            flow.exportSettings.folderBookmark = bookmark
            flow.exportSettings.folderName = url.lastPathComponent
        case .audioFolder:
            flow.exportSettings.audioFolderBookmark = bookmark
            flow.exportSettings.audioFolderName = url.lastPathComponent
        case .markdownTemplate:
            flow.exportSettings.markdownTemplateBookmark = bookmark
            flow.exportSettings.markdownTemplateName = url.lastPathComponent
        }
    }

    private static func renderFrontmatter(_ frontmatter: [String: String]) -> String {
        frontmatter.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }.joined(separator: "\n")
    }

    private static func parseFrontmatter(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty { result[key] = value }
        }
        return result
    }
}

private struct MacCaptureTextProcessingInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 30, weight: .medium))
                    .accessibilityHidden(true)
                Text("Apple Intelligence Processing")
                    .font(.title2.weight(.semibold))
                Spacer()
            }

            Text("When this setting is on, Vox.md uses on-device Apple Intelligence to edit captured text using the selected mode and the “Apply To” scope you choose — voice transcriptions, typed Capture text, or both — before updating your Markdown file.")

            VStack(alignment: .leading, spacing: 14) {
                infoRow(
                    icon: "slider.horizontal.3",
                    title: "Applies where you choose",
                    detail: "Process voice transcriptions, typed Capture text, or both via “Apply To.”"
                )
                infoRow(
                    icon: "checkmark.circle",
                    title: "Follows the selected mode",
                    detail: "Clean prose, create a todo checklist, format meeting notes, or follow your custom instruction."
                )
                infoRow(
                    icon: "lock.shield",
                    title: "Runs on device",
                    detail: "Your captured text is processed locally and is not sent to a cloud AI service."
                )
                infoRow(
                    icon: "doc.text",
                    title: "Keeps capture reliable",
                    detail: "If Apple Intelligence is unavailable, Vox.md uses a local fallback when possible or keeps the original text."
                )
            }

            Text("Keep Original and Apply To control text only. Image descriptions are optional.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private func infoRow(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private enum MacCapturePresetDestinationError: Error, LocalizedError {
    case storageUnavailable

    var errorDescription: String? {
        "Shared capture storage is unavailable."
    }
}

/// Sheet-local input only; saved identity is changed once, by Apply. In
/// particular, unrecognized persisted emoji stays intact if the user cancels.
private struct MacPresetIconDraft {
    enum Mode: Hashable {
        case symbols, emoji
    }

    var mode: Mode
    var symbolName: String
    var emojiInput: String

    init(symbolName: String, emoji: String?) {
        self.symbolName = symbolName
        emojiInput = emoji ?? ""
        mode = emoji == nil ? .symbols : .emoji
    }

    var normalizedEmoji: String? { CapturePresetEmoji.normalized(emojiInput) }
    var previewEmoji: String? { mode == .emoji ? normalizedEmoji : nil }

    var hasInvalidEmoji: Bool {
        mode == .emoji
            && !emojiInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && normalizedEmoji == nil
    }

    var selection: (symbolName: String, emoji: String?)? {
        switch mode {
        case .symbols:
            return (symbolName, nil)
        case .emoji:
            guard let normalizedEmoji else { return nil }
            return (symbolName, normalizedEmoji)
        }
    }

    mutating func selectSymbol(_ name: String) {
        symbolName = name
        mode = .symbols
        emojiInput = ""
    }
}

private struct MacPresetIconPreview: View {
    let presetName: String
    let symbolName: String
    let emoji: String?

    var body: some View {
        HStack(spacing: 12) {
            CapturePresetIconView(symbolName: symbolName, emoji: emoji)
                .font(.title2)
                .foregroundColor(Geist.text)
                .frame(width: 48, height: 48)
                .background(Geist.well)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Geist.borderHi, lineWidth: 1))
            VStack(alignment: .leading, spacing: 3) {
                Text("Preview")
                    .font(Geist.caption())
                    .foregroundColor(Geist.muted)
                Text(presetName)
                    .font(Geist.label())
                    .foregroundColor(Geist.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Geist.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Geist.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Icon preview for \(presetName)")
        .accessibilityValue(CapturePresetEmoji.normalized(emoji)
                            ?? MacFlowIconPickerView.title(for: symbolName))
        .accessibilityIdentifier("mac_preset_icon_preview")
    }
}

private struct MacFlowIconPickerView: View {
    let presetName: String
    let onApply: (String, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MacPresetIconDraft
    @State private var searchText = ""
    @FocusState private var focusedInput: MacPresetIconDraft.Mode?

    private let columns = [GridItem(.adaptive(minimum: 88), spacing: 12)]

    init(
        presetName: String,
        symbolName: String,
        emoji: String?,
        onApply: @escaping (String, String?) -> Void
    ) {
        self.presetName = presetName
        self.onApply = onApply
        _draft = State(initialValue: MacPresetIconDraft(symbolName: symbolName, emoji: emoji))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            GeistDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MacPresetIconPreview(
                        presetName: presetName,
                        symbolName: draft.symbolName,
                        emoji: draft.previewEmoji
                    )
                    if draft.mode == .emoji {
                        emojiEditor
                    } else {
                        symbolLibrary
                    }
                }
                .padding(20)
            }
            GeistDivider()
            footer
        }
        .background(Geist.bg)
        .frame(minWidth: 540, idealWidth: 600, minHeight: 620)
        .onAppear { focusedInput = draft.mode }
        .onChange(of: draft.mode) { _, mode in focusedInput = mode }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose Icon")
                .font(Geist.label(.title3))
                .foregroundColor(Geist.text)
            Text(presetName)
                .font(Geist.body())
                .foregroundColor(Geist.muted)
                .lineLimit(2)
                .help(presetName)
            Picker("Icon Type", selection: $draft.mode) {
                Text("Symbols").tag(MacPresetIconDraft.Mode.symbols)
                Text("Emoji").tag(MacPresetIconDraft.Mode.emoji)
            }
            .pickerStyle(.segmented)
            .tint(MacBrand.accent) // white glyph on indigo, legible in dark
            .accessibilityIdentifier("mac_preset_icon_mode")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Geist.surface)
    }

    private var emojiEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Emoji", text: $draft.emojiInput)
                .textFieldStyle(.roundedBorder)
                .font(.title2)
                .focused($focusedInput, equals: .emoji)
                .onSubmit(applySelection)
                .accessibilityLabel("Route emoji")
                .accessibilityHint("Enter one complete emoji. Use Control–Command–Space to open Character Viewer.")
                .accessibilityIdentifier("mac_preset_emoji_input")

            Text("Press Control–Command–Space while editing to open Character Viewer. Flags, skin tones, and joined emoji are supported.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)

            if draft.hasInvalidEmoji {
                Label("Enter one complete emoji, not multiple emoji or other text.", systemImage: "exclamationmark.triangle.fill")
                    .font(Geist.caption())
                    .foregroundStyle(MacBrand.attention)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mac_preset_emoji_error")
            } else if draft.normalizedEmoji == nil {
                Text("Enter an emoji to apply, or choose Symbols to use an SF Symbol.")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
            }

            Text("Your current icon is kept until you choose Apply. The SF Symbol is retained as a fallback for surfaces that cannot show emoji.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var symbolLibrary: some View {
        VStack(alignment: .leading, spacing: 20) {
            TextField("Search icons", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(Geist.body(.callout))
                .focused($focusedInput, equals: .symbols)
                .accessibilityIdentifier("mac_preset_symbol_search")

            Text("Applying Symbols replaces the emoji with the selected SF Symbol.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)

            if filteredCategories.isEmpty {
                Text("No matching icons")
                    .font(Geist.body())
                    .foregroundColor(Geist.muted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 24)
            } else {
                ForEach(filteredCategories) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(category.title)
                            .font(Geist.caption())
                            .foregroundColor(Geist.muted)
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(category.options) { option in
                                iconButton(option)
                            }
                        }
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("mac_preset_icon_cancel")
            Spacer()
            Button("Apply", action: applySelection)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.selection == nil)
                .accessibilityIdentifier("mac_preset_icon_apply")
        }
        .padding(20)
        .background(Geist.surface)
    }

    private func applySelection() {
        guard let selection = draft.selection else { return }
        onApply(selection.symbolName, selection.emoji)
        dismiss()
    }

    private var filteredCategories: [MacFlowIconCategory] {
        Self.filteredCategories(matching: searchText)
    }

    private func iconButton(_ option: MacFlowIconOption) -> some View {
        let selected = option.symbolName == Self.iconName(for: draft.symbolName)
        return Button {
            draft.selectSymbol(option.symbolName)
        } label: {
            VStack(spacing: 8) {
                CapturePresetIconView(symbolName: option.symbolName)
                    .font(.title2)
                Text(option.title)
                    .font(Geist.caption())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(selected ? Geist.text : Geist.muted)
            .frame(maxWidth: .infinity, minHeight: 82)
            .padding(.vertical, 8)
            .background(selected ? Geist.surface2 : Geist.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? MacBrand.accent : Geist.border, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .focusable()
        .accessibilityLabel(option.title)
        .accessibilityValue(option.symbolName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("mac_preset_symbol_\(option.symbolName)")
    }

    static func iconName(for symbolName: String) -> String {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "waveform" : trimmed
    }

    static func title(for symbolName: String) -> String {
        let iconName = iconName(for: symbolName)
        let title = allOptions.first(where: { $0.symbolName == iconName })?.title ?? iconName
        return title == "Waveform"
            ? String(localized: "Waveform", bundle: .main)
            : title
    }

    private static func filteredCategories(matching query: String) -> [MacFlowIconCategory] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return iconCategories }

        return iconCategories.compactMap { category in
            let matches = category.options.filter { $0.matches(trimmed) }
            guard !matches.isEmpty else { return nil }
            return MacFlowIconCategory(title: category.title, options: matches)
        }
    }

    private static let allOptions = iconCategories.flatMap(\.options)

    private static let iconCategories: [MacFlowIconCategory] = [
        MacFlowIconCategory(
            title: "Writing",
            options: [
                MacFlowIconOption("text.alignleft", "Text"),
                MacFlowIconOption("note.text", "Note"),
                MacFlowIconOption("doc.text", "Document"),
                MacFlowIconOption("doc.text.magnifyingglass", "Research"),
                MacFlowIconOption("list.bullet", "List"),
                MacFlowIconOption("quote.bubble", "Quote"),
                MacFlowIconOption("books.vertical", "Books"),
                MacFlowIconOption("bookmark", "Bookmark"),
                MacFlowIconOption("newspaper", "Article"),
                MacFlowIconOption("pencil", "Draft"),
            ]
        ),
        MacFlowIconCategory(
            title: "Voice",
            options: [
                MacFlowIconOption("mic", "Mic"),
                MacFlowIconOption("waveform", "Waveform"),
                MacFlowIconOption("wave.3.right", "Audio"),
                MacFlowIconOption("record.circle", "Record"),
                MacFlowIconOption("headphones", "Listen"),
                MacFlowIconOption("speaker.wave.2", "Speaker"),
                MacFlowIconOption("message", "Message"),
                MacFlowIconOption("bubble.left.and.text.bubble.right", "Chat"),
                MacFlowIconOption("phone", "Call"),
                MacFlowIconOption("video", "Video"),
            ]
        ),
        MacFlowIconCategory(
            title: "Tasks",
            options: [
                MacFlowIconOption("checkmark.circle", "Done"),
                MacFlowIconOption("checklist", "Checklist"),
                MacFlowIconOption("calendar", "Calendar"),
                MacFlowIconOption("bell", "Reminder"),
                MacFlowIconOption("flag", "Flag"),
                MacFlowIconOption("target", "Goal"),
                MacFlowIconOption("tray.and.arrow.down", "Inbox"),
                MacFlowIconOption("paperplane", "Send"),
                MacFlowIconOption("wand.and.stars", "Magic"),
                MacFlowIconOption("timer", "Timer"),
            ]
        ),
        MacFlowIconCategory(
            title: "Personal",
            options: [
                MacFlowIconOption("person", "Person"),
                MacFlowIconOption("person.crop.circle", "Profile"),
                MacFlowIconOption("brain.head.profile", "Thought"),
                MacFlowIconOption("heart", "Heart"),
                MacFlowIconOption("moon.stars", "Dream"),
                MacFlowIconOption("lightbulb", "Idea"),
                MacFlowIconOption("sparkles", "Sparkles"),
                MacFlowIconOption("house", "Home"),
                MacFlowIconOption("leaf", "Nature"),
                MacFlowIconOption("figure.walk", "Walk"),
            ]
        ),
        MacFlowIconCategory(
            title: "Work",
            options: [
                MacFlowIconOption("briefcase", "Work"),
                MacFlowIconOption("person.2", "People"),
                MacFlowIconOption("person.2.wave.2", "Meeting"),
                MacFlowIconOption("building.2", "Company"),
                MacFlowIconOption("chart.bar", "Stats"),
                MacFlowIconOption("rectangle.on.rectangle.angled", "Slides"),
                MacFlowIconOption("folder", "Folder"),
                MacFlowIconOption("archivebox", "Archive"),
                MacFlowIconOption("hammer", "Build"),
                MacFlowIconOption("gearshape", "Settings"),
            ]
        ),
    ]
}

private struct MacFlowIconCategory: Identifiable {
    let title: String
    let options: [MacFlowIconOption]

    var id: String { title }
}

private struct MacFlowIconOption: Identifiable {
    let symbolName: String
    let title: String
    let keywords: [String]

    var id: String { symbolName }

    init(_ symbolName: String, _ title: String, keywords: [String] = []) {
        self.symbolName = symbolName
        self.title = title
        self.keywords = keywords
    }

    func matches(_ query: String) -> Bool {
        let haystack = ([symbolName, title] + keywords).joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }
}

// MARK: - Library

struct MacHistoryView: View {
    @Bindable var viewModel: QuickCaptureViewModel
    private let isReadOnly: Bool
    @Environment(TranscriptStore.self) private var store
    #if DEBUG
    private let screenshotFixture: MacHistoryScreenshotFixture?
    #endif
    @State private var searchText = ""
    @State private var showsClearConfirmation = false
    @State private var isClearingHistory = false
    @State private var selectedItemID: UUID?
    @State private var tableSelection = Set<UUID>()
    @State private var libraryContent: [UUID: CaptureLibraryContent] = [:]
    @State private var libraryError: String?
    @FocusState private var isSearchFocused: Bool

    private let hiddenRouteIDs: Set<String>

    #if DEBUG
    fileprivate init(
        viewModel: QuickCaptureViewModel,
        screenshotFixture: MacHistoryScreenshotFixture? = nil,
        isReadOnly: Bool = false,
        hiddenRouteIDs: Set<String> = []
    ) {
        self.viewModel = viewModel
        self.screenshotFixture = screenshotFixture
        self.isReadOnly = isReadOnly
        self.hiddenRouteIDs = hiddenRouteIDs
    }
    #else
    init(viewModel: QuickCaptureViewModel, isReadOnly: Bool = false, hiddenRouteIDs: Set<String> = []) {
        self.viewModel = viewModel
        self.isReadOnly = isReadOnly
        self.hiddenRouteIDs = hiddenRouteIDs
    }
    #endif

    private var historyTranscripts: [Transcript] {
        #if DEBUG
        if let screenshotFixture { return screenshotFixture.transcripts }
        #endif
        return store.transcripts
    }

    private var historyRecords: [CaptureHistoryRecord] {
        #if DEBUG
        if let screenshotFixture { return screenshotFixture.records }
        #endif
        return viewModel.historyRecords
    }

    private var usesScreenshotFixture: Bool {
        #if DEBUG
        screenshotFixture != nil
        #else
        false
        #endif
    }

    private var unifiedItems: [MacUnifiedHistoryItem] {
        var captureByID: [UUID: CaptureHistoryRecord] = [:]
        for record in historyRecords { captureByID[record.requestID] = record }
        let transcriptIDs = Set(historyTranscripts.map(\.id))
        let transcripts = historyTranscripts.map {
            MacUnifiedHistoryItem.transcript($0, delivery: captureByID[$0.id])
        }
        let captures = historyRecords
            .filter { !transcriptIDs.contains($0.requestID) }
            .map(MacUnifiedHistoryItem.capture)
        return (transcripts + captures).sorted { $0.date > $1.date }
    }

    private var filteredItems: [MacUnifiedHistoryItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let routed = hiddenRouteIDs.isEmpty ? unifiedItems : unifiedItems.filter { item in
            let voxID: String? = switch item {
            case .transcript(_, let delivery): delivery?.voxID
            case .capture(let record): record.voxID
            }
            return voxID.map { !hiddenRouteIDs.contains($0) } ?? true
        }
        return query.isEmpty ? routed : routed.filter { item in
            item.matches(query)
                || (libraryContent[item.id]?.text?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var selectedItem: MacUnifiedHistoryItem? {
        guard let selectedItemID else { return nil }
        return unifiedItems.first(where: { $0.id == selectedItemID })
    }

    var body: some View {
        HSplitView {
            libraryTablePane
                .frame(minWidth: 440, idealWidth: 620, maxWidth: .infinity, maxHeight: .infinity)
            libraryPreviewPane
                .frame(minWidth: 320, idealWidth: 400, maxWidth: 480, maxHeight: .infinity)
        }
        .macUnderTitleBar()
        .background(Geist.bg)
        .groupBoxStyle(MacSignalGroupBoxStyle())
        .navigationTitle("Library")
        // No window toolbar (MacLibrary): Reload and Clear are in the View menu.
        .focusedSceneValue(\.macLibraryMenuActions, MacLibraryMenuActions(
            reload: { reloadHistory() },
            clearAll: unifiedItems.isEmpty ? nil : { showsClearConfirmation = true }
        ))
        .confirmationDialog(
            "Clear the Library?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                isClearingHistory = true
                selectedItemID = nil
                tableSelection = []
                store.clear()
                Task {
                    await viewModel.clearHistory()
                    isClearingHistory = false
                    reconcileSelection()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears transcript content and Capture delivery metadata. Exported Markdown notes and attachments are not deleted.")
        }
        .onAppear {
            guard !usesScreenshotFixture else {
                reconcileSelection()
                return
            }
            store.reload()
            reconcileSelection()
        }
        .task {
            guard !usesScreenshotFixture else {
                reconcileSelection()
                return
            }
            await viewModel.refreshHistory()
            await reloadLibraryContent()
            reconcileSelection()
        }
        .onChange(of: searchText) { _, _ in
            reconcileSelection(requiringVisibleItem: true)
        }
        .onChange(of: unifiedItems.map(\.id)) { _, _ in
            reconcileSelection(requiringVisibleItem: true)
            Task { await reloadLibraryContent() }
        }
        .onChange(of: hiddenRouteIDs) { _, _ in
            reconcileSelection(requiringVisibleItem: true)
        }
        .onChange(of: tableSelection) { _, selection in
            guard let first = filteredItems.first(where: { selection.contains($0.id) }) else { return }
            if selectedItemID != first.id { selectedItemID = first.id }
        }
        .onChange(of: selectedItemID) { _, id in
            guard let id, !tableSelection.contains(id) else { return }
            tableSelection = [id]
        }
        .alert("Library Error", isPresented: Binding(
            get: { libraryError != nil },
            set: { if !$0 { libraryError = nil } }
        )) {
            Button("OK") { libraryError = nil }
        } message: {
            Text(libraryError ?? "")
        }
    }

    // MARK: Signal table

    private var libraryTablePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Geist.muted)
                    TextField("Search  ⌘F", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(Geist.body(.callout))
                        .focused($isSearchFocused)
                        .accessibilityLabel("Search library")
                }
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Geist.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Geist.border, lineWidth: 1)
                }
                .background {
                    Button("Search") { isSearchFocused = true }
                        .keyboardShortcut("f", modifiers: .command)
                        .hidden()
                }

                Button("Export…") { exportSelection() }
                    .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
                    .fixedSize()
                    .disabled(filteredItems.isEmpty)
                    .help("Export the selected captures (or all shown) as Markdown files")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            GeistDivider()

            if !isReadOnly && viewModel.failedInboxCount > 0 {
                Button {
                    Task { await viewModel.retryFailedInbox() }
                } label: {
                    Label(
                        viewModel.failedInboxCount == 1
                            ? String(localized: "Retry 1 queued capture")
                            : String(localized: "Retry \(viewModel.failedInboxCount) queued captures"),
                        systemImage: "arrow.clockwise.circle"
                    )
                    .font(Geist.label(.footnote))
                    .foregroundStyle(MacBrand.attention)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .frame(height: 34)
                    .background(MacBrand.attentionSoft)
                }
                .buttonStyle(.plain)
                GeistDivider()
            }

            if unifiedItems.isEmpty {
                ContentUnavailableView(
                    "Library is Empty",
                    systemImage: "books.vertical",
                    description: Text("Completed captures and transcripts will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                libraryTable
            }
        }
        .background(Geist.bg)
    }

    // MARK: Signal rows

    /// Selected rows use Signal soft indigo (#E6E6FC), which a native Table
    /// selection cannot draw, so the table is drawn here.
    private static let selectedRowFill = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(srgbRed: 0x2F / 255, green: 0x3B / 255, blue: 0xE8 / 255, alpha: 0.28)
        }
        return NSColor(srgbRed: 0xE6 / 255, green: 0xE6 / 255, blue: 0xFC / 255, alpha: 1)
    })
    private static let rowDivider = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.separatorColor
            : NSColor(srgbRed: 0xE6 / 255, green: 0xE6 / 255, blue: 0xE0 / 255, alpha: 1)
    })

    private var libraryTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                libraryHeaderCell("CAPTURE").frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
                libraryHeaderCell("ROUTE").frame(width: 130, alignment: .leading).padding(.leading, 8)
                libraryHeaderCell("FROM").frame(width: 110, alignment: .leading).padding(.leading, 8)
                libraryHeaderCell("WHEN").frame(width: 90, alignment: .trailing)
                    .padding(.leading, 8).padding(.trailing, 20)
            }
            .padding(.vertical, 10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredItems) { item in
                            libraryRow(item)
                                .id(item.id)
                        }
                    }
                }
                .onChange(of: selectedItemID) { _, id in
                    guard let id else { return }
                    proxy.scrollTo(id)
                }
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onCommand(#selector(NSResponder.selectAll(_:))) {
            tableSelection = Set(filteredItems.map(\.id))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Captures")
    }

    private func libraryHeaderCell(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Geist.mono(size: 10.5, relativeTo: .caption2))
            .tracking(0.63)
            .foregroundStyle(Geist.muted)
            .lineLimit(1)
    }

    private func libraryRow(_ item: MacUnifiedHistoryItem) -> some View {
        let isSelected = tableSelection.contains(item.id)
        return HStack(spacing: 0) {
            Text(libraryTitle(item))
                .font(Geist.label(.callout))
                .foregroundStyle(Geist.text)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 20)
            Text(routeName(item))
                .font(Geist.body(.callout))
                .foregroundStyle(Geist.Palette.gray800)
                .lineLimit(1)
                .frame(width: 130, alignment: .leading)
                .padding(.leading, 8)
            Text(sourceLabel(item))
                .font(Geist.body(.callout))
                .foregroundStyle(Geist.muted)
                .lineLimit(1)
                .frame(width: 110, alignment: .leading)
                .padding(.leading, 8)
            HStack(spacing: 6) {
                Spacer(minLength: 0)
                if deliveryRecord(item)?.outcome == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MacBrand.attention)
                        .help("Delivery failed")
                }
                Text(whenLabel(item.date))
                    .font(Geist.mono(size: 12, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
            }
            .frame(width: 90, alignment: .trailing)
            .padding(.leading, 8)
            .padding(.trailing, 20)
        }
        .padding(.vertical, 11)
        .background(isSelected ? Self.selectedRowFill : Color.clear)
        .overlay(alignment: .top) { Rectangle().fill(Self.rowDivider).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { selectRow(item.id, modifiers: NSEvent.modifierFlags) }
        .contextMenu {
            let ids = tableSelection.contains(item.id) ? tableSelection : [item.id]
            Button("Copy Markdown") { copyToPasteboard(markdown(for: item)) }
            if let record = deliveryRecord(item), record.outcome == .delivered, record.relativeNotePath != nil {
                Button("Reveal in Finder") { reveal(record) }
            }
            Divider()
            Button("Export…") { exportItems(unifiedItems.filter { ids.contains($0.id) }) }
            Divider()
            Button("Delete", role: .destructive) { delete(item) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    /// Click selects; ⌘-click toggles; ⇧-click extends.
    private func selectRow(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if tableSelection.contains(id) { tableSelection.remove(id) } else { tableSelection.insert(id) }
        } else if modifiers.contains(.shift),
                  let anchor = selectedItemID,
                  let from = filteredItems.firstIndex(where: { $0.id == anchor }),
                  let to = filteredItems.firstIndex(where: { $0.id == id }) {
            tableSelection = Set(filteredItems[min(from, to)...max(from, to)].map(\.id))
            return
        } else {
            tableSelection = [id]
        }
        if tableSelection.contains(id) { selectedItemID = id }
    }

    private func moveSelection(by offset: Int) -> KeyPress.Result {
        guard !filteredItems.isEmpty else { return .ignored }
        let current = selectedItemID.flatMap { id in filteredItems.firstIndex { $0.id == id } } ?? (offset > 0 ? -1 : filteredItems.count)
        let next = min(max(current + offset, 0), filteredItems.count - 1)
        let id = filteredItems[next].id
        tableSelection = [id]
        selectedItemID = id
        return .handled
    }

    // MARK: Signal preview

    @ViewBuilder
    private var libraryPreviewPane: some View {
        if let selectedItem {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        MacRouteTile(letter: routeLetter(selectedItem), index: routeIndex(selectedItem), size: 20)
                        Text(verbatim: [routeName(selectedItem), previewTime(selectedItem.date), sourceLabel(selectedItem)]
                            .joined(separator: " · "))
                            .font(Geist.body(.footnote))
                            .foregroundStyle(Geist.muted)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        previewMoreMenu(selectedItem)
                    }

                    Text(libraryTitle(selectedItem))
                        .font(Geist.display(26))
                        .tracking(-0.5)
                        .foregroundStyle(Geist.text)
                        .textSelection(.enabled)

                    if let record = deliveryRecord(selectedItem) {
                        if record.outcome == .delivered {
                            Text(verbatim: "✓ " + String(localized: "Delivered to \(record.relativeNotePath ?? record.destinationName)"))
                                .font(Geist.label(.footnote))
                                .foregroundStyle(MacBrand.success)
                        } else {
                            Label(record.failureCategory?.displayName ?? String(localized: "Delivery failed"), systemImage: "exclamationmark.triangle.fill")
                                .font(Geist.label(.footnote))
                                .foregroundStyle(MacBrand.attention)
                        }
                    }

                    MacMarkdownBlock(markdown: markdown(for: selectedItem))

                    previewActions(selectedItem)

                    if case .transcript(let transcript, _) = selectedItem {
                        VStack(alignment: .leading, spacing: 8) {
                            MacSignalSectionHeader("Transcript")
                            Text(transcript.cleanedText ?? transcript.text)
                                .font(Geist.body(.callout))
                                .lineSpacing(3)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .macSignalCard(padding: 14)
                            HStack(spacing: 12) {
                                Label(formatDurationShort(transcript.duration), systemImage: "clock")
                                Label(transcript.modelUsed, systemImage: "waveform")
                                if transcript.speakerCount > 0 {
                                    Label("\(transcript.speakerCount) speakers", systemImage: "person.2.wave.2")
                                }
                            }
                            .font(Geist.caption(.caption))
                            .foregroundStyle(Geist.muted)
                        }
                    }

                    if let record = deliveryRecord(selectedItem) {
                        MacCaptureDeliveryMetadataView(record: record) { reveal($0) }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Geist.Palette.gray100)
        } else {
            ContentUnavailableView(
                unifiedItems.isEmpty ? "Library is Empty" : "Select a Capture",
                systemImage: unifiedItems.isEmpty ? "books.vertical" : "sidebar.left",
                description: Text(
                    unifiedItems.isEmpty
                        ? "Completed captures and transcripts will appear here."
                        : "Choose a capture to see what was written."
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Geist.Palette.gray100)
        }
    }

    private func previewActions(_ item: MacUnifiedHistoryItem) -> some View {
        let record = deliveryRecord(item)
        let isDelivered = record?.outcome == .delivered && record?.relativeNotePath != nil
        return HStack(spacing: 8) {
            Button("Open in Obsidian") {
                if let record { openInObsidian(record) }
            }
            .buttonStyle(GeistButtonStyle(variant: .primary, size: .small))
            .fixedSize()
            .disabled(!isDelivered)
            Button("Reveal in Finder") {
                if let record { reveal(record) }
            }
            .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
            .fixedSize()
            .disabled(!isDelivered)
            MacSharingPickerButton(title: String(localized: "Send to…")) {
                [markdown(for: item) as NSString]
            }
            .fixedSize()
        }
    }

    private func previewMoreMenu(_ item: MacUnifiedHistoryItem) -> some View {
        Menu {
            Button("Copy Markdown", systemImage: "doc.on.doc") { copyToPasteboard(markdown(for: item)) }
            if case .transcript(let transcript, _) = item {
                Button("Copy Transcript", systemImage: "text.quote") {
                    copyToPasteboard(transcript.cleanedText ?? transcript.text)
                }
                if transcript.cleanedText != nil, transcript.cleanedText != transcript.text {
                    Button("Copy Raw Transcript") { copyToPasteboard(transcript.text) }
                }
            }
            Button("Export…", systemImage: "square.and.arrow.up") { exportItems([item]) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("More actions")
    }

    // MARK: Row data

    private func deliveryRecord(_ item: MacUnifiedHistoryItem) -> CaptureHistoryRecord? {
        switch item {
        case .transcript(_, let delivery): delivery
        case .capture(let record): record
        }
    }

    private func routeProfile(_ item: MacUnifiedHistoryItem) -> CapturePresetProfile? {
        guard let voxID = deliveryRecord(item)?.voxID else { return nil }
        return viewModel.voxProfiles.first { $0.id == voxID }
    }

    private func routeName(_ item: MacUnifiedHistoryItem) -> String {
        if let profile = routeProfile(item) { return MacRouteCatalog.displayName(profile) }
        return deliveryRecord(item)?.voxName ?? deliveryRecord(item)?.destinationName ?? String(localized: "Transcript")
    }

    private func routeIndex(_ item: MacUnifiedHistoryItem) -> Int {
        guard let profile = routeProfile(item) else { return 2 }
        return MacRouteCatalog.enabledRoutes(in: viewModel).firstIndex(where: { $0.id == profile.id }) ?? 2
    }

    private func routeLetter(_ item: MacUnifiedHistoryItem) -> String {
        routeProfile(item).map(MacRouteCatalog.letter) ?? String(routeName(item).prefix(1)).uppercased()
    }

    private func sourceLabel(_ item: MacUnifiedHistoryItem) -> String {
        if let record = deliveryRecord(item) { return MacCaptureSourceLabel.label(for: record) }
        return String(localized: "Mac")
    }

    private func libraryTitle(_ item: MacUnifiedHistoryItem) -> String {
        switch item {
        case .transcript(let transcript, _):
            if let title = transcript.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
            return firstLine(transcript.cleanedText ?? transcript.text) ?? String(localized: "Transcript")
        case .capture(let record):
            if let text = libraryContent[record.requestID]?.text, let line = firstLine(text) {
                return line
            }
            if let markdown = libraryContent[record.requestID]?.renderedMarkdown, let line = firstLine(markdown) {
                return line
            }
            return record.voxName ?? record.destinationName
        }
    }

    private func firstLine(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("<!--") }
        guard var line else { return nil }
        while line.hasPrefix("#") { line.removeFirst() }
        line = line.replacingOccurrences(of: "- [ ] ", with: "").trimmingCharacters(in: .whitespaces)
        return line.isEmpty ? nil : String(line.prefix(80))
    }

    /// The Markdown that was (or would be) written for this capture.
    private func markdown(for item: MacUnifiedHistoryItem) -> String {
        if let rendered = libraryContent[item.id]?.renderedMarkdown, !rendered.isEmpty {
            return rendered
        }
        switch item {
        case .transcript(let transcript, _):
            var lines: [String] = []
            if let title = transcript.title, !title.isEmpty { lines.append("### \(title)") }
            lines.append(transcript.cleanedText ?? transcript.text)
            return lines.joined(separator: "\n")
        case .capture(let record):
            if let text = libraryContent[record.requestID]?.text { return text }
            return String(localized: "Vox.md did not keep a copy of this entry. Open the note to see what was written.")
        }
    }

    private func whenLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday") }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private func previewTime(_ date: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return String(localized: "Today \(time)") }
        if calendar.isDateInYesterday(date) { return String(localized: "Yesterday \(time)") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Actions

    private func reloadLibraryContent() async {
        guard !usesScreenshotFixture, let url = AppConstants.captureHistoryURL else { return }
        libraryContent = await CaptureHistoryStore(fileURL: url).allContent()
    }

    private func delete(_ item: MacUnifiedHistoryItem) {
        switch item {
        case .transcript(let transcript, _): deleteTranscript(transcript)
        case .capture(let record): deleteCapture(record)
        }
    }

    private func exportSelection() {
        let selected = filteredItems.filter { tableSelection.contains($0.id) }
        exportItems(selected.isEmpty ? filteredItems : selected)
    }

    /// Bulk Export…: one Markdown file per capture in a chosen folder.
    private func exportItems(_ items: [MacUnifiedHistoryItem]) {
        guard !items.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Export Captures")
        panel.prompt = String(localized: "Export")
        panel.message = items.count == 1
            ? String(localized: "Choose a folder for the Markdown file.")
            : String(localized: "Choose a folder for \(items.count) Markdown files.")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HHmm"
        var usedNames = Set<String>()
        do {
            for item in items {
                let safeTitle = libraryTitle(item)
                    .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>\n"))
                    .joined(separator: "-")
                    .trimmingCharacters(in: .whitespaces)
                var name = "\(formatter.string(from: item.date)) \(safeTitle.prefix(60))"
                var suffix = 2
                while usedNames.contains(name) || FileManager.default.fileExists(
                    atPath: folder.appendingPathComponent(name + ".md").path
                ) {
                    name = "\(formatter.string(from: item.date)) \(safeTitle.prefix(60)) \(suffix)"
                    suffix += 1
                }
                usedNames.insert(name)
                try Data(markdown(for: item).utf8).write(
                    to: folder.appendingPathComponent(name + ".md"),
                    options: .atomic
                )
            }
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } catch {
            libraryError = error.localizedDescription
        }
    }

    private func openInObsidian(_ record: CaptureHistoryRecord) {
        Task { @MainActor in
            do {
                let (rootURL, noteURL) = try await resolveNote(record)
                let didAccess = rootURL.startAccessingSecurityScopedResource()
                defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
                // The Obsidian vault is the nearest folder holding `.obsidian`;
                // fall back to the destination folder.
                var vaultURL = rootURL
                var candidate = noteURL.deletingLastPathComponent()
                while candidate.path.count > 1 {
                    if FileManager.default.fileExists(atPath: candidate.appendingPathComponent(".obsidian").path) {
                        vaultURL = candidate
                        break
                    }
                    candidate = candidate.deletingLastPathComponent()
                }
                let vaultPath = vaultURL.standardizedFileURL.path
                let notePath = noteURL.standardizedFileURL.path
                let relative = notePath.hasPrefix(vaultPath + "/")
                    ? String(notePath.dropFirst(vaultPath.count + 1))
                    : (record.relativeNotePath ?? noteURL.lastPathComponent)
                guard let url = MacObsidianLink.url(vaultName: vaultURL.lastPathComponent, relativePath: relative) else { return }
                if !NSWorkspace.shared.open(url) {
                    libraryError = String(localized: "Obsidian is not installed. Use Reveal in Finder instead.")
                }
            } catch {
                libraryError = error.localizedDescription
            }
        }
    }

    private func resolveNote(_ record: CaptureHistoryRecord) async throws -> (URL, URL) {
        guard let libraryURL = AppConstants.captureLibraryURL,
              let relativePath = record.relativeNotePath else {
            throw MacHistoryRevealError.destinationMissing
        }
        let library = try await CaptureLibraryStore(fileURL: libraryURL).load()
        guard let destination = library.destinations.first(where: { $0.id == record.destinationID }) else {
            throw MacHistoryRevealError.destinationMissing
        }
        let resolution = try CaptureBookmarkResolver.resolve(destination.rootBookmark)
        guard !resolution.isStale else { throw MacHistoryRevealError.permissionExpired }
        let noteURL = try CapturePathValidation.containedFileURL(relativePath: relativePath, rootURL: resolution.url)
        return (resolution.url, noteURL)
    }

    @ViewBuilder
    private func historyRow(_ item: MacUnifiedHistoryItem) -> some View {
        switch item {
        case .transcript(let transcript, let delivery):
            HStack(alignment: .top, spacing: Geist.Spacing.three) {
                Image(systemName: "waveform")
                    .foregroundStyle(historyRowSecondaryColor(for: item))
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: Geist.Spacing.one) {
                    Text(transcript.title ?? relativeDate(transcript.date))
                        .font(Geist.label())
                        .lineLimit(1)
                    Text("\(relativeDate(transcript.date)) · \(formatDurationShort(transcript.duration))")
                        .font(Geist.caption())
                        .foregroundStyle(historyRowSecondaryColor(for: item))
                        .lineLimit(1)
                    Text(transcript.cleanedText ?? transcript.text)
                        .font(Geist.caption())
                        .foregroundStyle(historyRowTertiaryColor(for: item))
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                if let delivery {
                    Image(systemName: delivery.outcome == .delivered
                          ? "checkmark.circle.fill"
                          : "exclamationmark.triangle.fill")
                        .foregroundStyle(
                            selectedItemID == item.id
                                ? Color.white.opacity(0.9)
                                : (delivery.outcome == .delivered ? Geist.muted : MacBrand.attention)
                        )
                        .help(delivery.outcome == .delivered ? "Delivered" : "Failed")
                }
            }
            .padding(.vertical, Geist.Spacing.two)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)

        case .capture(let record):
            HStack(alignment: .top, spacing: Geist.Spacing.three) {
                Image(systemName: record.outcome == .delivered
                      ? "checkmark.circle.fill"
                      : "exclamationmark.triangle.fill")
                    .foregroundStyle(
                        selectedItemID == item.id
                            ? Color.white.opacity(0.9)
                            : (record.outcome == .delivered ? Geist.muted : MacBrand.attention)
                    )
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: Geist.Spacing.one) {
                    Text(record.destinationName)
                        .font(Geist.label())
                        .lineLimit(1)
                    Text(record.deliveredAt ?? record.createdAt, style: .relative)
                        .font(Geist.caption())
                        .foregroundStyle(historyRowSecondaryColor(for: item))
                    Text(record.relativeNotePath
                         ?? record.failureCategory?.displayName
                         ?? String(localized: "Capture delivery"))
                        .font(Geist.caption())
                        .foregroundStyle(
                            selectedItemID == item.id
                                ? Color.white.opacity(0.82)
                                : (record.failureCategory == nil ? Geist.faint : MacBrand.attention)
                        )
                        .lineLimit(2)
                }
            }
            .padding(.vertical, Geist.Spacing.two)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
    }

    private func historyRowSecondaryColor(for item: MacUnifiedHistoryItem) -> Color {
        selectedItemID == item.id ? Color.white.opacity(0.9) : Geist.muted
    }

    private func historyRowTertiaryColor(for item: MacUnifiedHistoryItem) -> Color {
        selectedItemID == item.id ? Color.white.opacity(0.78) : Geist.faint
    }

    private func reloadHistory() {
        store.reload()
        reconcileSelection(requiringVisibleItem: true)
        Task {
            await viewModel.refreshHistory()
            reconcileSelection(requiringVisibleItem: true)
        }
    }

    private func deleteTranscript(_ transcript: Transcript) {
        selectFallback(removing: transcript.id)
        store.delete(ids: [transcript.id])
        Task {
            await viewModel.deleteHistory(requestID: transcript.id)
            reconcileSelection(requiringVisibleItem: true)
        }
    }

    private func deleteCapture(_ record: CaptureHistoryRecord) {
        selectFallback(removing: record.requestID)
        Task {
            await viewModel.deleteHistory(requestID: record.requestID)
            reconcileSelection(requiringVisibleItem: true)
        }
    }

    private func selectFallback(removing itemID: UUID) {
        let candidates = filteredItems
        guard let index = candidates.firstIndex(where: { $0.id == itemID }) else {
            selectedItemID = candidates.first(where: { $0.id != itemID })?.id
            return
        }
        let remaining = candidates.filter { $0.id != itemID }
        guard !remaining.isEmpty else {
            selectedItemID = nil
            return
        }
        selectedItemID = remaining[min(index, remaining.count - 1)].id
    }

    private func reconcileSelection(requiringVisibleItem: Bool = false) {
        guard !isClearingHistory else {
            selectedItemID = nil
            return
        }
        let candidates = requiringVisibleItem ? filteredItems : unifiedItems
        guard !candidates.isEmpty else {
            selectedItemID = nil
            return
        }
        if let selectedItemID,
           candidates.contains(where: { $0.id == selectedItemID }) {
            return
        }
        self.selectedItemID = candidates.first?.id
    }

    private func reveal(_ record: CaptureHistoryRecord) {
        Task { @MainActor in
            do {
                guard let libraryURL = AppConstants.captureLibraryURL,
                      let relativePath = record.relativeNotePath else { return }
                let library = try await CaptureLibraryStore(fileURL: libraryURL).load()
                guard let destination = library.destinations.first(where: { $0.id == record.destinationID }) else {
                    throw MacHistoryRevealError.destinationMissing
                }
                let rootResolution = try CaptureBookmarkResolver.resolve(destination.rootBookmark)
                let rootURL = rootResolution.url
                guard !rootResolution.isStale else { throw MacHistoryRevealError.permissionExpired }
                let didAccess = rootURL.startAccessingSecurityScopedResource()
                defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
                let noteURL = try CapturePathValidation.containedFileURL(
                    relativePath: relativePath,
                    rootURL: rootURL
                )
                NSWorkspace.shared.activateFileViewerSelecting([noteURL])
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct MacTranscriptDetailView: View {
    @State private var exportError: String?
    let transcript: Transcript
    let delivery: CaptureHistoryRecord?
    let onReveal: (CaptureHistoryRecord) -> Void
    let onDelete: () -> Void

    private var cleanedText: String? {
        guard let cleanedText = transcript.cleanedText,
              !cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return cleanedText
    }

    private var displayTitle: String {
        guard let title = transcript.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return String(localized: "Transcript")
        }
        return title
    }

    private var primaryText: String {
        cleanedText ?? transcript.text
    }

    private var showsRawTranscript: Bool {
        guard let cleanedText else { return false }
        return cleanedText != transcript.text
    }

    var body: some View {
        ZStack {
            Geist.Palette.gray100.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Geist.Spacing.six) {
                    header
                    if let delivery {
                        MacCaptureDeliveryMetadataView(record: delivery, onReveal: onReveal)
                    }
                    transcriptSection(
                        cleanedText == nil
                            ? String(localized: "Transcript")
                            : String(localized: "Cleaned Transcript"),
                        text: primaryText
                    )
                    if showsRawTranscript {
                        transcriptSection(String(localized: "Raw Transcript"), text: transcript.text)
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(Geist.Spacing.six)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Capture Detail")
        .alert("Export Error", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: {
            Text(exportError ?? "")
        }
    }

    private func exportExistingTranscript() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "transcript-\(transcript.id.uuidString.prefix(8)).md"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("VoxboardHistoryExports", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let source = try TranscriptFileExporter.export(transcript, format: .md, mode: .newFile,
                    folderURL: folder, newFileNameTemplateOverride: "transcript-{date}-{id8}")
                try Data(contentsOf: source).write(to: destination, options: .atomic)
            } catch {
                exportError = error.localizedDescription
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            HStack(spacing: Geist.Spacing.four) {
                Spacer()
                copyControl
                Button("Export", systemImage: "square.and.arrow.up", action: exportExistingTranscript)
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
            }

            Text(displayTitle)
                .font(Geist.display(26))
                .foregroundStyle(Geist.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(transcript.date.formatted(date: .long, time: .shortened))
                .font(Geist.mono())
                .foregroundStyle(Geist.muted)

            HStack(spacing: Geist.Spacing.four) {
                Label(formatDurationShort(transcript.duration), systemImage: "clock")
                Label(transcript.modelUsed, systemImage: "waveform")
                Label(transcript.language.uppercased(), systemImage: "globe")
                if let category = transcript.category, !category.isEmpty {
                    Label(category, systemImage: "folder")
                }
                if transcript.speakerCount > 0 {
                    Label("\(transcript.speakerCount) speakers", systemImage: "person.2.wave.2")
                }
            }
            .font(Geist.caption())
            .foregroundStyle(Geist.muted)

            if let reason = transcript.speakerDiarizationSkipReason {
                Label(reason.displayText, systemImage: "exclamationmark.triangle")
                    .font(Geist.caption())
                    .foregroundStyle(MacBrand.attention)
            }

            if let tags = transcript.tags, !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Geist.Spacing.two) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(Geist.caption())
                                .foregroundStyle(Geist.muted)
                                .padding(.horizontal, Geist.Spacing.three)
                                .frame(height: 28)
                                .background(Geist.well)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func transcriptSection(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            Text(verbatim: title.uppercased())
                .font(Geist.mono(size: 11, relativeTo: .caption))
                .tracking(0.66)
                .foregroundStyle(Geist.muted)
            Text(text)
                .font(Geist.body())
                .foregroundStyle(Geist.text)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .macSignalCard(padding: 20)
        }
    }

    @ViewBuilder
    private var copyControl: some View {
        if showsRawTranscript {
            Menu("Copy", systemImage: "doc.on.doc") {
                Button("Copy Cleaned") { copyToPasteboard(primaryText) }
                Button("Copy Raw") { copyToPasteboard(transcript.text) }
            }
        } else {
            Button("Copy", systemImage: "doc.on.doc") {
                copyToPasteboard(primaryText)
            }
        }
    }
}

private struct MacCaptureHistoryDetailView: View {
    let record: CaptureHistoryRecord
    let onReveal: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ZStack {
            Geist.Palette.gray100.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Geist.Spacing.six) {
                    HStack(alignment: .top, spacing: Geist.Spacing.four) {
                        VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                            Text(record.destinationName)
                                .font(Geist.display(26))
                                .foregroundStyle(Geist.text)
                                .textSelection(.enabled)
                            Label(
                                record.outcome == .delivered
                                    ? String(localized: "Delivered")
                                    : String(localized: "Failed"),
                                systemImage: record.outcome == .delivered
                                    ? "checkmark.circle.fill"
                                    : "exclamationmark.triangle.fill"
                            )
                            .font(Geist.label())
                            .foregroundStyle(
                                record.outcome == .delivered
                                    ? MacBrand.success
                                    : MacBrand.attention
                            )
                        }
                        Spacer()
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    }
                    MacCaptureDeliveryMetadataView(record: record) { _ in onReveal() }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(Geist.Spacing.six)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Capture Delivery")
    }
}

private struct MacCaptureDeliveryMetadataView: View {
    let record: CaptureHistoryRecord
    let onReveal: (CaptureHistoryRecord) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            HStack {
                Text("DELIVERY")
                    .font(Geist.mono(.caption, medium: true))
                    .foregroundStyle(Geist.faint)
                Spacer()
                if record.outcome == .delivered, record.relativeNotePath != nil {
                    Button("Reveal in Finder", systemImage: "folder") {
                        onReveal(record)
                    }
                    .buttonStyle(.plain)
                }
            }
            LabeledContent("Status") {
                Label(
                    record.outcome == .delivered
                        ? String(localized: "Delivered")
                        : String(localized: "Failed"),
                    systemImage: record.outcome == .delivered
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(
                    record.outcome == .delivered
                        ? MacBrand.success
                        : MacBrand.attention
                )
            }
            LabeledContent("Destination", value: record.destinationName)
            LabeledContent("Created", value: record.createdAt.formatted(date: .long, time: .shortened))
            if let deliveredAt = record.deliveredAt {
                LabeledContent("Delivered", value: deliveredAt.formatted(date: .long, time: .shortened))
            }
            LabeledContent("Source", value: record.source.rawValue.capitalized)
            if let preset = record.voxName {
                LabeledContent("Route", value: preset)
            }
            if let path = record.relativeNotePath {
                LabeledContent("Note Path") {
                    Text(path)
                        .font(Geist.mono())
                        .textSelection(.enabled)
                }
            }
            LabeledContent("Attachments", value: record.attachmentCount.formatted())
            if let failure = record.failureCategory {
                LabeledContent("Failure") {
                    Text(failure.displayName)
                        .foregroundStyle(MacBrand.attention)
                }
            }
        }
        .font(Geist.body())
        .macSignalCard(padding: 20)
    }
}

#if DEBUG
private struct MacHistoryScreenshotFixture {
    let transcripts: [Transcript]
    let records: [CaptureHistoryRecord]

    static let localization: MacHistoryScreenshotFixture = {
        let transcriptID = UUID(uuidString: "2D94C0A1-1E73-4D82-A669-92D872E3AE25")!
        let captureOnlyID = UUID(uuidString: "C0296E2C-52DE-4025-B7AA-382236D4224C")!
        let destinationID = UUID(uuidString: "7E3E8CC2-405C-4399-B45B-674BE10F59E5")!
        let transcriptDate = Date().addingTimeInterval(-18 * 60)
        let transcript = Transcript(
            id: transcriptID,
            text: "so we need to ship the mac navigation update this week and then verify the screenshots",
            date: transcriptDate,
            duration: 94,
            modelUsed: "Parakeet v2",
            language: "en",
            speakerTurns: [
                TranscriptSpeakerTurn(
                    speaker: 0,
                    text: "We need to ship the Mac navigation update this week.",
                    startTime: 0,
                    endTime: 4.2
                ),
                TranscriptSpeakerTurn(
                    speaker: 1,
                    text: "Then verify the screenshots.",
                    startTime: 4.4,
                    endTime: 6.8
                ),
            ],
            title: "Mac navigation review",
            tags: ["macos", "release"],
            category: "Work",
            cleanedText: "We need to ship the Mac navigation update this week, then verify the screenshots."
        )
        let delivered = try! CaptureHistoryRecord(
            requestID: transcriptID,
            createdAt: transcriptDate,
            deliveredAt: transcriptDate.addingTimeInterval(98),
            source: .voice,
            outcome: .delivered,
            destinationID: destinationID,
            destinationName: "Product Notes",
            voxID: "meeting-notes",
            voxName: "Meeting Notes",
            relativeNotePath: "Meetings/2026-08-31.md",
            attachmentCount: 1
        )
        let failed = try! CaptureHistoryRecord(
            requestID: captureOnlyID,
            createdAt: Date().addingTimeInterval(-52 * 60),
            deliveredAt: nil,
            source: .mac,
            outcome: .failed,
            destinationID: destinationID,
            destinationName: "Daily Notes",
            voxID: "quick-note",
            voxName: "Quick Note",
            relativeNotePath: nil,
            attachmentCount: 2,
            failureCategory: .permissionDenied
        )
        let quickCapture = try! CaptureHistoryRecord(
            requestID: UUID(uuidString: "5B0B7E3F-8C47-4C5A-9F38-0D6C2F5E9A11")!,
            createdAt: Date().addingTimeInterval(-26 * 60 * 60),
            deliveredAt: Date().addingTimeInterval(-26 * 60 * 60 + 2),
            source: .mac,
            outcome: .delivered,
            destinationID: destinationID,
            destinationName: "Tasks",
            voxID: "tasks",
            voxName: "Tasks",
            relativeNotePath: "Tasks.md",
            attachmentCount: 0,
            sourceDetail: CaptureHistoryRecord.macQuickCaptureSourceDetail
        )
        return MacHistoryScreenshotFixture(
            transcripts: [transcript],
            records: [delivered, failed, quickCapture]
        )
    }()
}
#endif

private enum MacUnifiedHistoryItem: Identifiable {
    case transcript(Transcript, delivery: CaptureHistoryRecord?)
    case capture(CaptureHistoryRecord)

    /// Transcript and delivery records share the same request UUID, so
    /// selection survives a reload that promotes a capture-only row into a
    /// full transcript without changing identity.
    var id: UUID {
        switch self {
        case .transcript(let transcript, _): transcript.id
        case .capture(let record): record.requestID
        }
    }

    var date: Date {
        switch self {
        case .transcript(let transcript, _): transcript.date
        case .capture(let record): record.deliveredAt ?? record.createdAt
        }
    }

    func matches(_ query: String) -> Bool {
        switch self {
        case .transcript(let transcript, let delivery):
            if TranscriptSearch.matches(transcript, query: query) { return true }
            return delivery.map { Self.captureHaystack($0).localizedCaseInsensitiveContains(query) } ?? false
        case .capture(let record):
            return Self.captureHaystack(record).localizedCaseInsensitiveContains(query)
        }
    }

    private static func captureHaystack(_ record: CaptureHistoryRecord) -> String {
        [
            record.destinationName,
            record.voxName,
            record.relativeNotePath,
            record.source.rawValue,
            record.outcome.rawValue,
            record.failureCategory?.displayName,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
    }
}

private enum MacHistoryRevealError: Error, LocalizedError {
    case destinationMissing
    case permissionExpired

    var errorDescription: String? {
        switch self {
        case .destinationMissing: String(localized: "The Capture destination no longer exists.")
        case .permissionExpired: String(localized: "Folder permission expired. Reauthorize the destination in Routes.")
        }
    }
}

// MARK: - Settings / Paywall

enum MacSettingsDestination: String, CaseIterable, Identifiable {
    static let storageKey = "macSettingsSelectedPane"

    case general
    case recording
    case transcription
    case vault
    case presets
    case templates
    case shortcuts
    case access
    case diagnostics
    case about
    case visibility

    var id: Self { self }

    /// The Signal settings tab (General, Vault, Transcription, Shortcuts,
    /// Account) that hosts this pane.
    var tab: MacSettingsTab {
        switch self {
        case .general, .recording, .diagnostics, .about, .visibility: .general
        case .vault, .presets, .templates: .vault
        case .transcription: .transcription
        case .shortcuts: .shortcuts
        case .access: .account
        }
    }

    var title: String {
        switch self {
        case .access: String(localized: "Access")
        case .general: String(localized: "General")
        case .recording: String(localized: "Recording")
        case .transcription: String(localized: "Transcription")
        case .vault: String(localized: "Vault")
        case .presets: String(localized: "Routes & Destinations")
        case .templates: String(localized: "Templates")
        case .shortcuts: String(localized: "Shortcuts")
        case .diagnostics: String(localized: "Diagnostics")
        case .about: String(localized: "About")
        case .visibility: String(localized: "Dock & Menu Bar")
        }
    }

    var symbol: String {
        switch self {
        case .access: "person.badge.key"
        case .general: "gearshape"
        case .recording: "waveform"
        case .transcription: "cpu"
        case .vault: "externaldrive"
        case .presets: "slider.horizontal.3"
        case .templates: "doc.text"
        case .shortcuts: "keyboard"
        case .diagnostics: "stethoscope"
        case .about: "info.circle"
        case .visibility: "dock.rectangle"
        }
    }
}

enum MacSettingsTab: String, CaseIterable, Identifiable {
    case general, vault, transcription, shortcuts, account

    var id: Self { self }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .vault: String(localized: "Vault")
        case .transcription: String(localized: "Transcription")
        case .shortcuts: String(localized: "Shortcuts")
        case .account: String(localized: "Account")
        }
    }

    /// Panes folded into this tab, first is the default.
    var panes: [MacSettingsDestination] {
        switch self {
        case .general: [.general, .visibility, .recording, .diagnostics, .about]
        case .vault: [.vault, .presets, .templates]
        case .transcription: [.transcription]
        case .shortcuts: [.shortcuts]
        case .account: [.access]
        }
    }
}

private enum MacTranscriptionEngineChoice: String, CaseIterable, Identifiable {
    case automatic, parakeet, whisper
    var id: Self { self }
    var title: String {
        switch self {
        case .automatic: String(localized: "Automatic")
        case .parakeet: "Parakeet"
        case .whisper: "Whisper"
        }
    }
}

private enum MacAttachmentsFolderChoice: String, Hashable {
    case besideNote, attachmentsFolder, perRoute
}

/// Keeps the hosting window's title in sync after SwiftUI's own updates.
private struct MacWindowTitleSetter: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let title = title
        DispatchQueue.main.async {
            if nsView.window?.title != title { nsView.window?.title = title }
        }
    }
}

struct MacSettingsView: View {
    let recorder: MacRecorder
    #if DEBUG
    private let usesLocalizationScreenshotLayout: Bool
    #endif
    @Environment(MacStoreManager.self) private var storeManager
    @Environment(ModelManager.self) private var modelManager
    @Environment(UsageTracker.self) private var usageTracker
    @AppStorage(MacAppVisibilityMode.storageKey, store: AppConstants.sharedDefaults)
    private var visibilityModeRaw = MacAppVisibilityMode.dockAndMenuBar.rawValue
    @AppStorage(MacSoundEffects.storageKey, store: AppConstants.sharedDefaults)
    private var soundsEnabled = true
    @State private var selectedDestination: MacSettingsDestination = .general
    @State private var launchesAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var vaultDestinations: [CaptureDestination] = []
    @State private var defaultVaultDestinationID: UUID?
    @State private var vaultPath: String?
    @State private var vaultStatus: (text: String, isHealthy: Bool)?
    @State private var vaultError: String?
    @State private var busyPolicy = MacFileBusyRetry.storedPolicy
    @State private var defaultRouteID = CapturePresetStore.selectedFlowId()
    @State private var accountPlanName: String?
    @State private var accountRenewal: Date?
    @State private var accountWillRenew = false
    @State private var accountIsFamilyShared = false
    @State private var hotKeyFlows = CapturePresetStore.loadFlows()
    @State private var hotKeyDestinations: [CaptureDestination] = []
    @State private var hotKeyBindings: [MacHotKeyTarget: MacHotKeyShortcut] = [:]
    @State private var editingHotKeyTarget: MacHotKeyTarget?
    @State private var hotKeyStatusMessage: String?

    #if DEBUG
    init(
        recorder: MacRecorder,
        usesLocalizationScreenshotLayout: Bool = false
    ) {
        self.recorder = recorder
        self.usesLocalizationScreenshotLayout = usesLocalizationScreenshotLayout
    }
    #else
    init(recorder: MacRecorder) {
        self.recorder = recorder
    }
    #endif

    @ViewBuilder
    var body: some View {
        #if DEBUG
        settingsNavigation
        #else
        settingsNavigation
        #endif
    }

    /// Signal settings: five tabs at 760×640, each showing the design's
    /// content. Older panes are folded into their tab and opened from link
    /// rows on its first page, with a back bar to return.
    private var settingsNavigation: some View {
        VStack(spacing: 0) {
            settingsTabBar
            if selectedDestination != selectedDestination.tab.panes[0] {
                settingsBackBar
                GeistDivider()
            }
            NavigationStack {
                selectedSettingsDetail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Geist.Palette.gray100)
        // MacSettings: the window title is always the selected tab's name.
        // Pane navigationTitles ("Transcription Models", …) and the initial
        // "General" otherwise left the title at "Vox.md".
        .background(MacWindowTitleSetter(title: selectedDestination.tab.title))
        .tint(MacBrand.tint)
        .frame(minWidth: 760, idealWidth: 760, minHeight: 640, idealHeight: 640)
        .onChange(of: selectedDestination) { _, destination in
            AppConstants.sharedDefaults?.set(
                destination.rawValue,
                forKey: MacSettingsDestination.storageKey
            )
            if destination != .shortcuts {
                editingHotKeyTarget = nil
            }
        }
        .onAppear(perform: restoreSelectedSettingsDestination)
        .onReceive(NotificationCenter.default.publisher(for: .macSelectSettingsPane)) { notification in
            guard let rawValue = notification.object as? String,
                  let destination = MacSettingsDestination(rawValue: rawValue) else { return }
            selectedDestination = destination
        }
        .task { await reloadHotKeyConfiguration() }
        .task { await reloadVaultSettings() }
        .task { await reloadAccountSummary() }
        // Settings may open before the app-level StoreKit task completes.
        // Refresh here so existing owners always see the Family upgrade.
        .task { await storeManager.prepareForPurchases() }
    }

    private var settingsTabBar: some View {
        HStack(spacing: 4) {
            ForEach(MacSettingsTab.allCases) { tab in
                let isSelected = selectedDestination.tab == tab
                Button {
                    selectedDestination = tab.panes[0]
                } label: {
                    Text(tab.title)
                        .font(isSelected ? Geist.label(.footnote) : Geist.body(.footnote))
                        .foregroundStyle(isSelected ? Geist.text : Geist.Palette.gray800)
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(
                            isSelected ? Geist.Palette.gray100 : Color.clear,
                            in: UnevenRoundedRectangle(topLeadingRadius: 8, topTrailingRadius: 8)
                        )
                        .overlay(alignment: .bottom) {
                            if isSelected { Rectangle().fill(MacBrand.tint).frame(height: 2) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity)
        .background(Geist.Palette.gray200)
        .overlay(alignment: .bottom) { Rectangle().fill(Geist.border).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings")
    }

    /// "‹ General   Recording" above a pane opened from a tab's link rows.
    private var settingsBackBar: some View {
        let tab = selectedDestination.tab
        return HStack(spacing: 10) {
            Button {
                selectedDestination = tab.panes[0]
            } label: {
                Label(tab.title, systemImage: "chevron.left")
                    .font(Geist.label(.footnote))
            }
            .buttonStyle(.plain)
            .foregroundStyle(MacBrand.accentText)
            .keyboardShortcut("[", modifiers: .command)
            Text(verbatim: selectedDestination.title)
                .font(Geist.label(.footnote))
                .foregroundStyle(Geist.muted)
            Spacer()
        }
        .padding(.horizontal, 20)
        .frame(height: 36)
        .background(Geist.Palette.gray100)
    }

    /// Link rows to a tab's other panes (content beyond the design grid).
    private func settingsLinkRows(_ panes: [MacSettingsDestination]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(panes.enumerated()), id: \.element) { index, pane in
                Button {
                    selectedDestination = pane
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: pane.symbol)
                            .foregroundStyle(Geist.muted)
                            .frame(width: 18)
                        Text(verbatim: pane.title)
                            .font(Geist.body(.callout))
                            .foregroundStyle(Geist.text)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Geist.faint)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("mac_settings_link_\(pane.rawValue)")
                if index < panes.count - 1 { GeistDivider() }
            }
        }
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Geist.border, lineWidth: 1)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }

    /// Design grid row: right-aligned 180pt label, control column.
    private func formRow<Content: View>(
        _ label: LocalizedStringKey,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 20) {
            Text(label)
                .font(Geist.body(.callout))
                .foregroundStyle(Geist.muted)
                .frame(width: 180, alignment: .trailing)
            content()
                .font(Geist.body(.callout))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Vault tab

    private var vaultSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                formRow("Vault") {
                    HStack(spacing: 10) {
                        Text(verbatim: vaultPath ?? String(localized: "Not set up"))
                            .font(Geist.mono(size: 12.5, relativeTo: .caption))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Button("Change…", action: changeVaultFolder)
                            .controlSize(.small)
                    }
                }
                formRow("Status") {
                    if let vaultStatus {
                        Text(verbatim: (vaultStatus.isHealthy ? "✓ " : "⚠︎ ") + vaultStatus.text)
                            .font(Geist.label(.callout))
                            .foregroundStyle(vaultStatus.isHealthy ? MacBrand.success : MacBrand.attention)
                    } else {
                        Text("Checking…").foregroundStyle(Geist.muted)
                    }
                }
                formRow("Attachments") {
                    Picker("Attachment folder", selection: attachmentsChoiceBinding) {
                        Text("Beside the note").tag(MacAttachmentsFolderChoice.besideNote)
                        Text(verbatim: "Attachments/").tag(MacAttachmentsFolderChoice.attachmentsFolder)
                        if attachmentsChoice == .perRoute {
                            Text("Per route").tag(MacAttachmentsFolderChoice.perRoute)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(maxWidth: 280, alignment: .leading)
                    .disabled(vaultDestinations.isEmpty)
                }
                formRow("Default route") {
                    Picker("Default route", selection: Binding(
                        get: { defaultRouteID },
                        set: { id in
                            defaultRouteID = id
                            CapturePresetStore.selectFlow(id: id)
                        }
                    )) {
                        ForEach(hotKeyFlows.filter(\.isEnabled)) { flow in
                            Text(flow.visibleName ?? String(localized: "Icon-only route")).tag(flow.id)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .frame(maxWidth: 280, alignment: .leading)
                }
                formRow("When a file is busy", alignment: .top) {
                    Picker("When a file is busy", selection: Binding(
                        get: { busyPolicy },
                        set: { policy in
                            busyPolicy = policy
                            MacFileBusyRetry.setPolicy(policy)
                        }
                    )) {
                        Text("Wait and retry").tag(CaptureFileBusyPolicy.waitAndRetry)
                        Text("Write a new note instead").tag(CaptureFileBusyPolicy.writeNewNote)
                    }
                    .pickerStyle(.radioGroup)
                    .tint(MacBrand.accent) // white glyph on indigo, legible in dark
                    .labelsHidden()
                }
                formRow("") {
                    Text("A note is busy when it is open with unsaved changes or locked in another app. Waiting captures retry automatically every minute and appear in Activity.")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let vaultError {
                    formRow("") {
                        Text(vaultError).font(Geist.caption()).foregroundStyle(MacBrand.attention)
                    }
                }
                formRow("") {
                    settingsLinkRows(Array(MacSettingsTab.vault.panes.dropFirst()))
                }
                .padding(.top, 6)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
        }
        .navigationTitle("Vault")
    }

    private var defaultVaultDestination: CaptureDestination? {
        vaultDestinations.first { $0.id == defaultVaultDestinationID } ?? vaultDestinations.first
    }

    private var attachmentsChoice: MacAttachmentsFolderChoice {
        let folders = Set(vaultDestinations.map(\.attachmentsFolderName))
        if folders == [CaptureDestination.besideNoteAttachmentsFolder] { return .besideNote }
        if !folders.isEmpty, folders.allSatisfy({ $0.lowercased() == "attachments" }) { return .attachmentsFolder }
        return vaultDestinations.isEmpty ? .attachmentsFolder : .perRoute
    }

    private var attachmentsChoiceBinding: Binding<MacAttachmentsFolderChoice> {
        Binding(
            get: { attachmentsChoice },
            set: { choice in
                guard choice != .perRoute else { return }
                Task { await setAttachmentsFolder(choice) }
            }
        )
    }

    private func setAttachmentsFolder(_ choice: MacAttachmentsFolderChoice) async {
        guard let url = AppConstants.captureLibraryURL else { return }
        do {
            let library = try await CaptureLibraryStore(fileURL: url).update { library in
                for index in library.destinations.indices {
                    switch choice {
                    case .besideNote:
                        library.destinations[index].attachmentsFolderName = CaptureDestination.besideNoteAttachmentsFolder
                    case .attachmentsFolder:
                        if library.destinations[index].attachmentsFolderName.lowercased() != "attachments" {
                            library.destinations[index].attachmentsFolderName = "Attachments"
                        }
                    case .perRoute:
                        break
                    }
                }
            }
            vaultDestinations = library.destinations
        } catch {
            vaultError = error.localizedDescription
        }
    }

    private func reloadVaultSettings() async {
        busyPolicy = MacFileBusyRetry.storedPolicy
        defaultRouteID = CapturePresetStore.selectedFlowId()
        guard let url = AppConstants.captureLibraryURL,
              let library = try? await CaptureLibraryStore(fileURL: url).load() else {
            vaultStatus = (String(localized: "No vault folder yet. Set up a route destination."), false)
            return
        }
        vaultDestinations = library.destinations
        defaultVaultDestinationID = library.defaultDestinationID
        guard let destination = defaultVaultDestination else {
            vaultPath = nil
            vaultStatus = (String(localized: "No vault folder yet. Set up a route destination."), false)
            return
        }
        let inspection = Self.inspectVault(destination)
        vaultPath = inspection.path ?? destination.rootName
        vaultStatus = (inspection.status, inspection.isHealthy)
    }

    /// Real readability/writability and iCloud checks on the vault folder.
    private static func inspectVault(_ destination: CaptureDestination) -> (path: String?, status: String, isHealthy: Bool) {
        guard let resolution = try? CaptureBookmarkResolver.resolve(destination.rootBookmark) else {
            return (nil, String(localized: "Folder not found. Choose it again."), false)
        }
        let url = resolution.url
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        let fileManager = FileManager.default
        var home = NSHomeDirectory()
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            home = String(cString: dir)
        }
        var path = url.path
        if path.hasPrefix(home) { path = "~" + path.dropFirst(home.count) }
        if path.contains("/Library/Mobile Documents/iCloud~md~obsidian/Documents/") {
            path = path.replacingOccurrences(of: "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/", with: "iCloud › Obsidian › ")
        }
        guard !resolution.isStale else {
            return (path, String(localized: "Permission expired. Choose the folder again."), false)
        }
        let readable = (try? fileManager.contentsOfDirectory(atPath: url.path)) != nil
        let writable = fileManager.isWritableFile(atPath: url.path)
        let isICloud = (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true
            || url.path.contains("/Library/Mobile Documents/")
        let sync = isICloud ? String(localized: "iCloud synced") : String(localized: "On this Mac")
        switch (readable, writable) {
        case (true, true):
            return (path, String(localized: "Readable and writable") + " · " + sync, true)
        case (true, false):
            return (path, String(localized: "Read-only — Vox.md cannot write here") + " · " + sync, false)
        default:
            return (path, String(localized: "Not readable — choose the folder again"), false)
        }
    }

    /// Change…: points every destination that used the old vault folder at
    /// the newly chosen one.
    private func changeVaultFolder() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Vault Folder")
        panel.prompt = String(localized: "Choose")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let didAccess = folder.startAccessingSecurityScopedResource()
        defer { if didAccess { folder.stopAccessingSecurityScopedResource() } }
        do {
            let bookmark = try folder.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            let oldPath = defaultVaultDestination
                .flatMap { try? CaptureBookmarkResolver.resolve($0.rootBookmark) }?.url.standardizedFileURL.path
            let oldName = defaultVaultDestination?.rootName
            Task {
                guard let url = AppConstants.captureLibraryURL else { return }
                do {
                    _ = try await CaptureLibraryStore(fileURL: url).update { library in
                        for index in library.destinations.indices {
                            let destination = library.destinations[index]
                            let path = (try? CaptureBookmarkResolver.resolve(destination.rootBookmark))?.url.standardizedFileURL.path
                            let matches = (oldPath != nil && path == oldPath)
                                || (path == nil && destination.rootName == oldName)
                                || library.destinations.count == 1
                            guard matches else { continue }
                            library.destinations[index].rootBookmark = bookmark
                            library.destinations[index].rootName = folder.lastPathComponent
                            library.destinations[index].markdownTemplatePath = nil
                        }
                    }
                    vaultError = nil
                    await reloadVaultSettings()
                } catch {
                    vaultError = error.localizedDescription
                }
            }
        } catch {
            vaultError = error.localizedDescription
        }
    }

    // MARK: Transcription tab

    private var transcriptionSettings: some View {
        VStack(spacing: 0) {
            formRow("Engine") {
                Picker("Engine", selection: Binding(
                    get: { transcriptionChoice },
                    set: { selectTranscription($0) }
                )) {
                    ForEach(MacTranscriptionEngineChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .tint(MacBrand.accent) // white glyph on indigo, legible in dark
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
            Text("Same model list as iPhone. Downloads are per device; Automatic uses Apple speech recognition and falls back to your installed model.")
                .font(Geist.caption())
                .foregroundStyle(Geist.faint)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 240)
                .padding(.trailing, 40)
                .padding(.vertical, 10)
            GeistDivider()
            MacModelView()
        }
    }

    private var transcriptionChoice: MacTranscriptionEngineChoice {
        if modelManager.isAutomaticSelection { return .automatic }
        return modelManager.selectedModel?.engine.isParakeet == true ? .parakeet : .whisper
    }

    private func selectTranscription(_ choice: MacTranscriptionEngineChoice) {
        switch choice {
        case .automatic:
            modelManager.selectAutomatic()
        case .parakeet, .whisper:
            let candidates = WhisperModelInfo.availableModels.filter {
                $0.engine.isParakeet == (choice == .parakeet)
            }
            let model = candidates.first(where: modelManager.isModelDownloaded) ?? candidates.first
            if let model { modelManager.selectModel(model) }
        }
    }

    // MARK: Account tab

    private var accountSettings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                formRow("Plan") {
                    Text(accountPlanName ?? planFallbackName)
                        .font(Geist.label(.callout))
                }
                formRow("Renewal") {
                    if let accountRenewal {
                        Text(accountWillRenew
                             ? String(localized: "Renews \(accountRenewal.formatted(date: .long, time: .omitted))")
                             : String(localized: "Ends \(accountRenewal.formatted(date: .long, time: .omitted))"))
                    } else {
                        Text(usageTracker.hasUnlocked ? String(localized: "One-time purchase — no renewal") : String(localized: "—"))
                            .foregroundStyle(Geist.muted)
                    }
                }
                formRow("Family Sharing") {
                    Text(familySharingSummary)
                }
                formRow("") {
                    HStack(spacing: 8) {
                        Button(storeManager.isRestoring ? String(localized: "Restoring…") : String(localized: "Restore Purchases")) {
                            Task {
                                await storeManager.restore()
                                await reloadAccountSummary()
                            }
                        }
                        .disabled(storeManager.isRestoring)
                        Button("Manage Subscription…") {
                            // AppStore.showManageSubscriptions is iOS-only; the
                            // Mac App Store opens the same management page.
                            if let url = URL(string: "macappstores://apps.apple.com/account/subscriptions") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                }
                if let message = storeManager.errorMessage {
                    formRow("") {
                        Text(message).font(Geist.caption()).foregroundStyle(MacBrand.attention)
                    }
                }
                GeistDivider().padding(.vertical, 8)
                MacPaywallView(context: .settings, embeddedInSettings: true)
                    .frame(maxWidth: 680)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
        }
        .navigationTitle("Account")
    }

    private var planFallbackName: String {
        switch usageTracker.accessLevel {
        case .free: String(localized: "Free")
        case .individual: String(localized: "Vox.md Individual")
        case .family: String(localized: "Vox.md Family")
        }
    }

    private var familySharingSummary: String {
        if accountIsFamilyShared { return String(localized: "Shared with you through Family Sharing") }
        if usageTracker.accessLevel == .family { return String(localized: "On — shared with your family group") }
        return String(localized: "Off — upgrade to Family to share")
    }

    private func reloadAccountSummary() async {
        var best: (product: VoxboardPurchaseProduct, transaction: StoreKit.Transaction)?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.revocationDate == nil,
                  let product = VoxboardPurchaseProduct(rawValue: transaction.productID) else { continue }
            if best == nil || product.grantedAccessLevel == .family {
                best = (product, transaction)
            }
        }
        guard let best else {
            accountPlanName = nil
            accountRenewal = nil
            accountIsFamilyShared = false
            return
        }
        accountPlanName = storeManager.product(for: best.product)?.displayName ?? planFallbackName
        accountRenewal = best.transaction.expirationDate
        accountIsFamilyShared = best.transaction.ownershipType == .familyShared
        if let status = try? await storeManager.product(for: best.product)?.subscription?.status.first,
           case .verified(let info) = status.renewalInfo {
            accountWillRenew = info.willAutoRenew
        } else {
            accountWillRenew = best.transaction.expirationDate != nil
        }
    }


    @ViewBuilder
    private var selectedSettingsDetail: some View {
        switch selectedDestination {
        case .access:
            accountSettings
        case .vault:
            vaultSettings
        case .general:
            generalSettings
        case .recording:
            MacRecordingSettingsView()
        case .transcription:
            transcriptionSettings
        case .presets:
            MacCapturePresetSettingsView()
        case .templates:
            MacEntryTemplateLibraryView()
        case .shortcuts:
            shortcutsSettings
        case .diagnostics:
            MacDebugLogView()
                .navigationTitle("Diagnostics")
        case .about:
            aboutSettings
        case .visibility:
            visibilityPaneSettings
        }
    }

    private var accessSettings: some View {
        ScrollView {
            MacPaywallView(context: .settings, embeddedInSettings: true)
                .frame(maxWidth: 760)
                .padding(.vertical, Geist.Spacing.four)
                .frame(maxWidth: .infinity)
        }
        .background(Geist.Palette.background100)
        .navigationTitle("Access")
    }

    private var generalSettings: some View {
        ScrollView {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    formRow("Launch at login") {
                        Toggle("Open Vox.md when you log in", isOn: Binding(
                            get: { launchesAtLogin },
                            set: { setLaunchAtLogin($0) }
                        ))
                        .toggleStyle(.checkbox)
                        .tint(MacBrand.accent) // white glyph on indigo, legible in dark
                    }
                    formRow("Menu bar icon") {
                        Toggle("Show Vox.md in the menu bar", isOn: Binding(
                            get: { visibilityMode.showsMenuBar },
                            set: { setMenuBarIcon($0) }
                        ))
                        .toggleStyle(.checkbox)
                        .tint(MacBrand.accent) // white glyph on indigo, legible in dark
                    }
                    formRow("Sounds") {
                        Toggle("Play sounds when recording starts, stops and sends", isOn: $soundsEnabled)
                            .toggleStyle(.checkbox)
                            .tint(MacBrand.accent) // white glyph on indigo, legible in dark
                    }
                    if let launchAtLoginError {
                        formRow("") {
                            Text(launchAtLoginError).font(Geist.caption()).foregroundStyle(MacBrand.attention)
                        }
                    }
                    formRow("") {
                        settingsLinkRows(Array(MacSettingsTab.general.panes.dropFirst()))
                    }
                    .padding(.top, 6)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(Geist.Palette.gray100)
        .navigationTitle("General")
    }

    /// Dock and menu bar presence (opened from General).
    private var visibilityPaneSettings: some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader("01", "Visibility")
                visibilitySettings
            }
        }
        .background(Geist.surface)
        .navigationTitle("Dock & Menu Bar")
    }

    /// What runs on this Mac versus iOS (shown in About).
    @ViewBuilder
    private var macCompanionRows: some View {
        sectionHeader("02", "Mac Companion")
        settingsRow(
            title: String(localized: "ON-DEVICE TRANSCRIPTION"),
            detail: String(localized: "Whisper and Parakeet models run locally with Metal/Core ML acceleration."),
            trailing: String(localized: "LOCAL")
        )
        settingsRow(
            title: String(localized: "APPLE INTELLIGENCE"),
            detail: appleIntelligenceDetail,
            trailing: appleIntelligenceStatus
        )
        settingsRow(
            title: String(localized: "FILE EXPORT"),
            detail: String(localized: "Routes, templates, Markdown exports, and attachments use local app storage. Folder permissions stay on this Mac."),
            trailing: String(localized: "ENABLED")
        )
        settingsRow(
            title: String(localized: "KEYBOARD + LOCK SCREEN"),
            detail: String(localized: "Custom keyboard, widgets, Dynamic Island, and Live Activities remain iOS-specific."),
            trailing: String(localized: "IOS")
        )
    }

    @ViewBuilder
    private var shortcutsSettings: some View {
        if let target = editingHotKeyTarget {
            MacHotKeyRecorderView(
                title: hotKeyTitle(for: target),
                detail: hotKeyDetail(for: target),
                currentShortcut: hotKeyBindings[target],
                conflictingBindingName: { shortcut in
                    conflictingBindingName(for: shortcut, excluding: target)
                },
                onCancel: { editingHotKeyTarget = nil },
                onSave: { shortcut in saveHotKey(shortcut, for: target) },
                onClear: { clearHotKey(for: target) }
            )
            .id(target.id)
            .navigationTitle("Shortcuts")
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 14) {
                        formRow("Quick capture") {
                            HStack(spacing: 10) {
                                Text(verbatim: hotKeyBindings[.quickCapture]?.displayString
                                     .replacingOccurrences(of: "Space", with: " Space") ?? String(localized: "Off"))
                                    .font(Geist.mono(size: 12.5, relativeTo: .caption))
                                    .padding(.horizontal, 10)
                                    .frame(height: 28)
                                    .background(Geist.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(hotKeyBindings[.quickCapture] == nil ? Geist.border : MacBrand.accent, lineWidth: 2)
                                    }
                                Button(String(localized: "Change…")) { editingHotKeyTarget = .quickCapture }
                                    .controlSize(.small)
                                if hotKeyBindings[.quickCapture] == nil {
                                    Button(String(localized: "Use ⌥Space")) {
                                        saveHotKey(MacHotKeyStore.defaultQuickCaptureShortcut, for: .quickCapture)
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                        formRow("") {
                            Text("Press to open Quick Capture. Hold to talk; release to stop.")
                                .font(Geist.caption())
                                .foregroundStyle(Geist.faint)
                        }
                        formRow("Route 1–4") {
                            Text(verbatim: "⌘1 … ⌘4").font(Geist.mono(size: 12.5, relativeTo: .caption))
                        }
                        formRow("Send") {
                            Text(verbatim: "⌘↩").font(Geist.mono(size: 12.5, relativeTo: .caption))
                        }
                        formRow("All shortcuts") {
                            Text(verbatim: "⌘/").font(Geist.mono(size: 12.5, relativeTo: .caption))
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Geist.Palette.gray100)
                    sectionHeader("01", "Recording keybinds")
                    hotKeySettings
                }
            }
            .background(Geist.surface)
            .navigationTitle("Shortcuts")
        }
    }

    private var aboutSettings: some View {
        ScrollView {
            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    MacAppIconView(size: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                        Text("Vox.md")
                            .font(Geist.heading(.title))
                            .foregroundStyle(Geist.text)
                        Text("Private capture and on-device transcription for Markdown workflows.")
                            .font(Geist.body())
                            .foregroundStyle(Geist.muted)
                    }
                    Spacer()
                }
                .padding(Geist.Spacing.four)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Geist.bg)
                sectionHeader("01", "About")
                settingsRow(title: String(localized: "VERSION"), detail: appVersionString, trailing: "")
                settingsRow(
                    title: String(localized: "PROCESSING"),
                    detail: String(localized: "Voice and text stay on-device."),
                    trailing: String(localized: "PRIVATE")
                )
                settingsRow(
                    title: String(localized: "STORAGE"),
                    detail: String(localized: "Capture drafts, Library, routes, templates, and diagnostics remain in local app storage."),
                    trailing: String(localized: "LOCAL")
                )
                macCompanionRows
            }
        }
        .background(Geist.surface)
        .navigationTitle("About")
    }

    private func settingsPageHeader(
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.two) {
            Text(title)
                .font(Geist.heading(.title))
                .foregroundStyle(Geist.text)
            Text(detail)
                .font(Geist.body())
                .foregroundStyle(Geist.muted)
        }
        .padding(Geist.Spacing.four)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Geist.bg)
    }

    private var visibilityMode: MacAppVisibilityMode {
        MacAppVisibilityMode(rawValue: visibilityModeRaw) ?? .dockAndMenuBar
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            launchAtLoginError = String(localized: "Allow Vox.md in System Settings › General › Login Items.")
        }
    }

    private func setMenuBarIcon(_ shows: Bool) {
        let next: MacAppVisibilityMode = switch (visibilityMode, shows) {
        case (.dockOnly, true): .dockAndMenuBar
        case (.hidden, true): .menuBarOnly
        case (.dockAndMenuBar, false): .dockOnly
        case (.menuBarOnly, false): .hidden
        default: visibilityMode
        }
        visibilityModeRaw = next.rawValue
        next.apply()
    }

    private var visibilityFootnote: String {
        switch visibilityMode {
        case .dockAndMenuBar:
            return String(localized: "Default. Click “Show Vox.md” from the menu bar or use Cmd-Tab.")
        case .menuBarOnly:
            return String(localized: "No Dock icon or Cmd-Tab entry. Click the menu bar item to reveal Vox.md.")
        case .dockOnly:
            return String(localized: "Use the Dock icon or Cmd-Tab to bring Vox.md forward.")
        case .hidden:
            return String(localized: "Fully hidden. Reopen Vox.md from Spotlight, Finder, or Launchpad to access it again.")
        }
    }

    private var appleIntelligenceStatus: String {
        if #available(macOS 26, *) {
            return FoundationModelsBackend.isAvailable
                ? String(localized: "READY")
                : String(localized: "UNAVAILABLE")
        }
        return String(localized: "MACOS 26+")
    }

    private var appleIntelligenceDetail: String {
        if #available(macOS 26, *) {
            return String(localized: "Foundation Models cleans transcripts, adds titles/tags/categories, and powers smart folder routing on-device.")
        }
        return String(localized: "Requires macOS 26+ on an Apple Intelligence-capable Mac.")
    }

    private var visibilitySettings: some View {
        VStack(spacing: 0) {
            GeistDivider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Choose where Vox.md appears. macOS controls the Dock icon and Cmd-Tab entry together.")
                    .font(Geist.caption())
                    .foregroundColor(Geist.muted)

                VStack(spacing: 8) {
                    ForEach(MacAppVisibilityMode.allCases) { mode in
                        visibilityModeRow(mode)
                    }
                }

                Text(visibilityFootnote)
                    .font(Geist.caption())
                    .foregroundColor(Geist.faint)
            }
            .padding(20)
            .background(Geist.bg)
        }
    }

    private func visibilityModeRow(_ mode: MacAppVisibilityMode) -> some View {
        let isSelected = visibilityMode == mode
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                visibilityModeRaw = mode.rawValue
            }
            mode.apply()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isSelected ? MacBrand.accentText : Geist.faint)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(Geist.label())
                        .foregroundColor(Geist.text)
                    Text(mode.summary)
                        .font(Geist.caption())
                        .foregroundColor(Geist.muted)
                }

                Spacer()

                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(isSelected ? MacBrand.accent : Geist.borderHi)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? MacBrand.accent : Geist.border, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var hotKeySettings: some View {
        VStack(spacing: 0) {
            GeistDivider()
            VStack(alignment: .leading, spacing: 14) {
                Text("Start or stop a recording from anywhere on macOS while Vox.md is running. Use the transcription-only keybind for temporary dictation, or assign route keybinds to write to specific destinations.")
                    .font(Geist.caption())
                    .foregroundColor(Geist.muted)

                hotKeyRow(
                    target: .transcriptionOnly,
                    title: String(localized: "Transcribe to Clipboard"),
                    detail: String(localized: "Copy immediately when processed now. Deferred results wait in Activity so they never overwrite your clipboard later.")
                )

                hotKeyRow(
                    target: .selectedPreset,
                    title: String(localized: "Selected Route"),
                    detail: String(localized: "Use whichever route is currently selected in Capture.")
                )

                if !enabledHotKeyFlows.isEmpty {
                    Text("CAPTURE PRESETS")
                        .font(Geist.caption())
                        .foregroundColor(Geist.faint)
                        .padding(.top, 4)

                    ForEach(enabledHotKeyFlows) { flow in
                        hotKeyRow(
                            target: .preset(flow.id),
                            title: flow.visibleName ?? String(localized: "Icon-only route"),
                            detail: hotKeyRouteSummary(for: flow)
                        )
                    }
                }

                Text("For a fast reading workflow, configure one route to create a New Note and another to use an Existing Note, then assign a keybind to each. Press any recording keybind again to stop the active recording.")
                    .font(Geist.caption())
                    .foregroundColor(Geist.faint)

                if let hotKeyStatusMessage {
                    Text(hotKeyStatusMessage)
                        .font(Geist.caption())
                        .foregroundColor(MacBrand.attention)
                }
            }
            .padding(20)
            .background(Geist.bg)
        }
    }

    private var enabledHotKeyFlows: [CapturePreset] {
        hotKeyFlows.filter(\.isEnabled)
    }

    private func hotKeyRow(
        target: MacHotKeyTarget,
        title: String,
        detail: String
    ) -> some View {
        let shortcut = hotKeyBindings[target]
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Geist.label())
                    .foregroundColor(Geist.text)
                Text(detail)
                    .font(Geist.caption())
                    .foregroundColor(Geist.muted)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            Text(shortcut?.displayString ?? String(localized: "OFF"))
                .font(Geist.mono(size: 12.5, relativeTo: .caption, medium: true))
                .foregroundColor(shortcut == nil ? Geist.faint : Geist.text)
                .padding(.horizontal, 10)
                .frame(minWidth: 72, minHeight: 28)
                .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.small, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Geist.Radius.small, style: .continuous)
                        .stroke(shortcut == nil ? Geist.border : MacBrand.accent, lineWidth: shortcut == nil ? 1 : 2)
                }

            Button(shortcut == nil ? String(localized: "Set") : String(localized: "Change")) {
                editingHotKeyTarget = target
            }
            .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
            // GeistButtonStyle fills its width; keep Set/Change compact so the
            // OFF chip and button line up at the card's trailing edge.
            .fixedSize()

            if shortcut != nil {
                Button {
                    clearHotKey(for: target)
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundColor(MacBrand.attention)
                .accessibilityLabel("Clear \(title) keybind")
            }
        }
        .macSignalCard(padding: 14)
    }

    private func hotKeyTitle(for target: MacHotKeyTarget) -> String {
        switch target {
        case .quickCapture:
            return String(localized: "Quick Capture")
        case .transcriptionOnly:
            return String(localized: "Transcribe to Clipboard")
        case .selectedPreset:
            return String(localized: "Selected Route")
        case .preset(let presetID):
            return hotKeyFlows.first(where: { $0.id == presetID }).map { $0.visibleName ?? String(localized: "Icon-only route") }
                ?? String(localized: "Route")
        }
    }

    private func hotKeyDetail(for target: MacHotKeyTarget) -> String {
        switch target {
        case .quickCapture:
            return String(localized: "Press to open the floating Quick Capture window. Hold to talk; release to stop.")
        case .transcriptionOnly:
            return String(localized: "Start or stop a temporary transcription. Immediate results are copied; deferred results wait for an explicit Copy action in Activity.")
        case .selectedPreset:
            return String(localized: "Start or stop recording with whichever Route is currently selected.")
        case .preset(let presetID):
            guard let flow = hotKeyFlows.first(where: { $0.id == presetID }) else {
                return String(localized: "Start or stop recording with this Route.")
            }
            return hotKeyRouteSummary(for: flow)
        }
    }

    private func hotKeyRouteSummary(for flow: CapturePreset) -> String {
        guard let destinationID = flow.captureDestinationID,
              let destination = hotKeyDestinations.first(where: { $0.id == destinationID }) else {
            return String(localized: "Destination not configured.")
        }

        switch destination.noteTarget {
        case .newNote(let pathTemplate):
            return String(localized: "Create a new note at \(pathTemplate) in \(destination.rootName).")
        case .rollingNote(let pathTemplate, let period):
            return String(localized: "Write to the \(period.rawValue) rolling note at \(pathTemplate).")
        case .existingNote(let relativePath):
            let verb: String
            switch destination.placement {
            case .append: verb = String(localized: "Append to")
            case .prepend: verb = String(localized: "Prepend to")
            case .beneathHeading: verb = String(localized: "Insert into")
            }
            return String(localized: "\(verb) \(relativePath) in \(destination.rootName).")
        }
    }

    private func conflictingBindingName(
        for shortcut: MacHotKeyShortcut,
        excluding target: MacHotKeyTarget
    ) -> String? {
        guard let conflict = MacHotKeyStore.conflictingTarget(
            for: shortcut,
            excluding: target,
            activePresetIDs: Set(enabledHotKeyFlows.map(\.id))
        ) else { return nil }
        return hotKeyTitle(for: conflict)
    }

    private func saveHotKey(_ shortcut: MacHotKeyShortcut, for target: MacHotKeyTarget) {
        MacHotKeyStore.save(shortcut, for: target)
        reloadHotKeyBindings()
        MacGlobalHotKeyCenter.shared.reloadRegistration()
        hotKeyStatusMessage = MacGlobalHotKeyCenter.shared.lastRegistrationError
        editingHotKeyTarget = nil
    }

    private func clearHotKey(for target: MacHotKeyTarget) {
        MacHotKeyStore.clear(target)
        reloadHotKeyBindings()
        MacGlobalHotKeyCenter.shared.reloadRegistration()
        hotKeyStatusMessage = MacGlobalHotKeyCenter.shared.lastRegistrationError
        editingHotKeyTarget = nil
    }

    private func reloadHotKeyBindings() {
        hotKeyBindings = Dictionary(
            uniqueKeysWithValues: MacHotKeyStore.configuredBindings().map {
                ($0.target, $0.shortcut)
            }
        )
    }

    private func reloadHotKeyConfiguration() async {
        hotKeyFlows = CapturePresetStore.loadFlows()
        reloadHotKeyBindings()
        guard let captureLibraryURL = AppConstants.captureLibraryURL else {
            hotKeyDestinations = []
            return
        }
        do {
            let library = try await CapturePresetRouteLibrary.load(
                from: CaptureLibraryStore(fileURL: captureLibraryURL)
            )
            // Loading the route library may complete legacy destination
            // ownership migration, so refresh the matching preset IDs too.
            hotKeyFlows = CapturePresetStore.loadFlows()
            hotKeyDestinations = library.destinations
        } catch {
            hotKeyDestinations = []
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func restoreSelectedSettingsDestination() {
        #if DEBUG
        if usesLocalizationScreenshotLayout {
            // `--localization-screenshot-settings-pane <pane>` picks the tab
            // for visual QA; Vault stays the default story.
            let arguments = ProcessInfo.processInfo.arguments
            let pane = arguments.firstIndex(of: "--localization-screenshot-settings-pane")
                .flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
                .flatMap(MacSettingsDestination.init(rawValue:))
            selectedDestination = pane ?? .vault
            return
        }
        #endif
        guard let rawValue = AppConstants.sharedDefaults?.string(
            forKey: MacSettingsDestination.storageKey
        ), let destination = MacSettingsDestination(rawValue: rawValue) else { return }
        selectedDestination = destination
    }
}

private struct MacRecordingSettingsView: View {
    @State private var retentionMode: SourceAudioRetentionMode
    @State private var timedRetentionDays: Int
    @State private var processingPolicy: RecordingJobProcessingPolicy

    init() {
        let configuration = RecordingQueuePreferences.load()
        _retentionMode = State(initialValue: configuration.sourceAudioRetention.mode)
        let interval = configuration.sourceAudioRetention.retentionInterval
            ?? SourceAudioRetentionPolicy.defaultTimedRetention
        _timedRetentionDays = State(
            initialValue: max(1, Int((interval / 86_400).rounded()))
        )
        _processingPolicy = State(initialValue: configuration.processingPolicy)
    }

    var body: some View {
        Form {
            Section("Activity") {
                Picker("After recording", selection: $processingPolicy) {
                    Text("Immediately").tag(RecordingJobProcessingPolicy.immediate)
                    Text("When Idle").tag(RecordingJobProcessingPolicy.whenIdle)
                    Text("Manually").tag(RecordingJobProcessingPolicy.manual)
                }

                Text(processingDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Original Audio") {
                Picker("Keep audio", selection: $retentionMode) {
                    Text("Until Processing Finishes").tag(SourceAudioRetentionMode.deleteAfterSuccess)
                    Text("For a Period").tag(SourceAudioRetentionMode.timed)
                    Text("Permanently").tag(SourceAudioRetentionMode.permanent)
                }

                if retentionMode == .timed {
                    Stepper(
                        "Keep for \(timedRetentionDays) days",
                        value: $timedRetentionDays,
                        in: 1...365
                    )
                }

                Text("Failed recordings remain available until you retry or delete them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Recording")
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: retentionMode) { _, _ in save() }
        .onChange(of: timedRetentionDays) { _, _ in save() }
        .onChange(of: processingPolicy) { _, _ in save() }
    }

    private var processingDetail: String {
        switch processingPolicy {
        case .immediate:
            return String(localized: "Start processing as soon as the microphone is free.")
        case .whenIdle:
            return String(localized: "Process while Vox.md is open and no recording is active.")
        case .manual:
            return String(localized: "Wait until you choose Process Now in Activity.")
        }
    }

    private func save() {
        let retention: SourceAudioRetentionPolicy = switch retentionMode {
        case .deleteAfterSuccess:
            .deleteAfterSuccess
        case .timed:
            .timed(TimeInterval(timedRetentionDays) * 86_400)
        case .permanent:
            .permanent
        }
        RecordingQueuePreferences.save(
            RecordingQueueConfiguration(
                sourceAudioRetention: retention,
                processingPolicy: processingPolicy
            )
        )
    }
}

private struct MacHotKeyRecorderView: View {
    let title: String
    let detail: String
    let currentShortcut: MacHotKeyShortcut?
    let conflictingBindingName: (MacHotKeyShortcut) -> String?
    let onCancel: () -> Void
    let onSave: (MacHotKeyShortcut) -> Void
    let onClear: () -> Void

    @State private var capturedShortcut: MacHotKeyShortcut?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                HStack {
                    Button("Back", systemImage: "chevron.left", action: onCancel)
                    Spacer()
                }
                VStack(spacing: 8) {
                    Text("Set \(title) Keybind")
                        .font(Geist.heading(.title2))
                        .foregroundColor(Geist.text)
                    Text(detail)
                        .font(Geist.body())
                        .foregroundColor(Geist.muted)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Text(capturedShortcut?.displayString ?? String(localized: "PRESS A KEYBIND"))
                        .font(Geist.display(42))
                        .foregroundColor(Geist.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .background(Geist.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MacBrand.accent, lineWidth: 2))

                    Text("Use a letter, number, Space, arrow, or function key with ⌃ Control, ⌥ Option, or ⌘ Command. ⇧ Shift can be combined. Press Esc to cancel.")
                        .font(Geist.caption())
                        .foregroundColor(Geist.muted)
                        .multilineTextAlignment(.center)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Geist.caption())
                        .foregroundColor(MacBrand.attention)
                }

                HStack(spacing: 12) {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(GeistButtonStyle(variant: .secondary))

                    Button("Clear", action: onClear)
                        .buttonStyle(.plain)
                        .foregroundColor(MacBrand.attention)
                        .disabled(currentShortcut == nil && capturedShortcut == nil)

                    Spacer()

                    Button("Save Keybind") {
                        guard let capturedShortcut else { return }
                        if let conflict = conflictingBindingName(capturedShortcut) {
                            errorMessage = String(localized: "\(capturedShortcut.displayString) is already assigned to \(conflict).")
                            return
                        }
                        onSave(capturedShortcut)
                    }
                    .buttonStyle(GeistButtonStyle(variant: .primary))
                    .disabled(capturedShortcut == nil)
                }
            }
            .padding(30)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .background(Geist.bg)
        .background(
            MacHotKeyCaptureView(
                onKeyDown: handleKeyDown,
                onFlagsChanged: handleFlagsChanged
            )
            .frame(width: 0, height: 0)
        )
        .onAppear {
            capturedShortcut = currentShortcut
        }
    }

    private func handleKeyDown(_ event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }

        guard let shortcut = MacHotKeyShortcut(event: event) else {
            errorMessage = String(localized: "Press one non-modifier key with Control, Option, or Command.")
            return
        }
        if let conflict = conflictingBindingName(shortcut) {
            capturedShortcut = nil
            errorMessage = String(localized: "\(shortcut.displayString) is already assigned to \(conflict).")
            return
        }

        capturedShortcut = shortcut
        errorMessage = nil
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(MacHotKeyShortcut.allowedModifierFlags)
        guard !modifiers.isEmpty else { return }

        if modifiers.intersection([.command, .option, .control]).isEmpty {
            errorMessage = String(localized: "Shift alone cannot be used. Add Control, Option, or Command plus one non-modifier key.")
        } else {
            errorMessage = String(localized: "Now press a letter, number, Space, arrow, or function key to finish the shortcut.")
        }
    }
}

private struct MacHotKeyCaptureView: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Void
    let onFlagsChanged: (NSEvent) -> Void

    func makeNSView(context: Context) -> MacHotKeyCaptureNSView {
        let view = MacHotKeyCaptureNSView()
        view.onKeyDown = onKeyDown
        view.onFlagsChanged = onFlagsChanged
        return view
    }

    func updateNSView(_ nsView: MacHotKeyCaptureNSView, context: Context) {
        nsView.onKeyDown = onKeyDown
        nsView.onFlagsChanged = onFlagsChanged
        nsView.focusIfPossible()
    }
}

private final class MacHotKeyCaptureNSView: NSView, MacKeyboardHintSuppressingResponder {
    var onKeyDown: ((NSEvent) -> Void)?
    var onFlagsChanged: ((NSEvent) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        focusIfPossible()
    }

    func focusIfPossible() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        onKeyDown?(event)
    }

    override func flagsChanged(with event: NSEvent) {
        onFlagsChanged?(event)
    }
}

private enum MacPaywallPresentation {
    case modal
    case embeddedSettings
}

struct MacPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(MacStoreManager.self) private var storeManager

    @AppStorage(Thoughtful.introductionKey) private var introductionCompleted = false
    @State private var family = false
    @State private var selectedPlanIndex = 1
    @State private var showsHistory = false
    private var historyViewModel: QuickCaptureViewModel?
    let context: PaywallContext
    var isAccessGate = false
    fileprivate let presentation: MacPaywallPresentation

    init(context: PaywallContext = .settings, isAccessGate: Bool = false,
         historyViewModel: QuickCaptureViewModel? = nil) {
        self.context = context
        self.isAccessGate = isAccessGate
        self.historyViewModel = historyViewModel
        self.presentation = .modal
    }

    fileprivate init(
        context: PaywallContext,
        embeddedInSettings: Bool
    ) {
        self.context = context
        self.presentation = embeddedInSettings ? .embeddedSettings : .modal
    }

    @ViewBuilder
    var body: some View {
        if isAccessGate && !introductionCompleted && !usageTracker.hasUnlocked {
            ThoughtfulOnboarding(onFinish: { introductionCompleted = true },
                                 onHistory: historyViewModel == nil ? nil : { showsHistory = true })
                .frame(minWidth: 560, idealWidth: 620, maxWidth: 760, minHeight: 560, idealHeight: 760)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Thoughtful.background)
                .sheet(isPresented: $showsHistory) { existingHistory }
                .task { await storeManager.prepareForPurchases() }
        } else if presentation == .modal {
            ScrollView { paywallContent }
                .frame(width: 620)
                .background(Thoughtful.background)
                .task { await storeManager.prepareForPurchases() }
        } else {
            paywallContent
                .frame(maxWidth: 760)
                .background(Thoughtful.background)
                .task { await storeManager.prepareForPurchases() }
        }
    }

    private var paywallContent: some View {
        VStack(spacing: 22) {
            if isAccessGate && historyViewModel != nil {
                Button("View and Export Your Library", systemImage: "clock") { showsHistory = true }
                    .accessibilityIdentifier("paywall.existingHistory")
                    .sheet(isPresented: $showsHistory) {
                        if let historyViewModel {
                            NavigationStack {
                                MacHistoryView(viewModel: historyViewModel, isReadOnly: true)
                                    .toolbar { Button("Close") { showsHistory = false } }
                            }
                            .frame(minWidth: 900, minHeight: 600)
                        }
                    }
            }
            ThoughtfulNoteIllustration(compact: true)
            Text(paywallTitle)
                .font(Thoughtful.title)
                .foregroundColor(Geist.text)
            Text(paywallDetail)
                .font(Geist.body())
                .foregroundColor(Geist.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)

            purchaseOptions

            Text("Subscriptions renew automatically unless canceled at least 24 hours before the period ends. Eligible subscriptions include a 7-day free trial, then renew at the displayed price. Lifetime is a one-time purchase without a trial. Deleting the app or buying Lifetime does not cancel an existing subscription.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
            HStack {
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy Policy", destination: URL(string: "https://vox.isolated.tech/privacy.html")!)
                Link("Manage Subscriptions", destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
            }
            .font(Geist.caption())

            Button(storeManager.isRestoring
                   ? String(localized: "Restoring…")
                   : String(localized: "Restore Purchases")) {
                Task { await storeManager.restore() }
            }
            .buttonStyle(GeistButtonStyle(variant: .secondary))
            .frame(maxWidth: 440)
            .disabled(storeManager.isRestoring || storeManager.isPurchasing)

            if let error = storeManager.errorMessage {
                Text(error)
                    .font(Geist.caption())
                    .foregroundColor(MacBrand.attention)
                Button("Retry Loading Purchases") {
                    Task { await storeManager.prepareForPurchases() }
                }
                .disabled(storeManager.isPurchasing || storeManager.isRestoring)
            }
            if presentation == .modal && !isAccessGate {
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(Geist.muted)
            }
        }
        .padding(36)
    }

    @ViewBuilder
    private var purchaseOptions: some View {
        if !storeManager.isEntitlementStateReady {
            HStack(spacing: 10) {
                ProgressView()
                Text("CHECKING PURCHASES…")
                    .font(Geist.caption())
                    .foregroundColor(Geist.muted)
            }
            .frame(maxWidth: 440)
        } else {
            availablePurchaseOptions
        }
    }

    private var offers: [VoxboardPurchaseProduct] {
        if usageTracker.isEligibleForFamilyUpgrade { return [.familyUpgrade] }
        return family ? [.familyWeekly, .familyYearly, .family] : [.individualWeekly, .individualYearly, .individual]
    }

    private var selectedProduct: VoxboardPurchaseProduct {
        offers[min(selectedPlanIndex, offers.count - 1)]
    }

    @ViewBuilder
    private var existingHistory: some View {
        if let historyViewModel {
            NavigationStack {
                MacHistoryView(viewModel: historyViewModel, isReadOnly: true)
                    .toolbar { Button("Close") { showsHistory = false } }
            }
            .frame(minWidth: 900, minHeight: 600)
        }
    }

    @ViewBuilder
    private var availablePurchaseOptions: some View {
        if usageTracker.hasFamilyAccess {
            Label("Family Unlimited Unlocked", systemImage: "person.3.fill")
                .font(Geist.body())
        } else {
            if !usageTracker.isEligibleForFamilyUpgrade {
                Picker("Access", selection: $family) {
                    Text("Individual").tag(false)
                    Text("Family").tag(true)
                }
                .pickerStyle(.segmented)
                .tint(MacBrand.accent) // white glyph on indigo, legible in dark
                .disabled(storeManager.isPurchasing || storeManager.isRestoring)
                Text(family ? String(localized: "For your Apple Family Sharing group. Each person keeps their own notes.") : String(localized: "For you, across your Apple devices."))
                    .font(Geist.caption())
                    .foregroundStyle(Thoughtful.secondary)
            }
            VStack(spacing: 0) {
                ForEach(offers, id: \.rawValue) { product in
                    macOffer(product: product, title: LocalizedStringKey(planTitle(product)),
                             detail: LocalizedStringKey(product.isSubscription ? product.billingLabel : String(localized: "One-time purchase. No trial.")))
                    if product != offers.last { Divider().padding(.horizontal, 16) }
                }
            }
            .background(Thoughtful.paper, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Thoughtful.rule, lineWidth: 1))
            .frame(maxWidth: 480)
            if let price = storeManager.displayPrice(for: selectedProduct) {
                Text(storeManager.offersFreeTrial(selectedProduct)
                     ? String(localized: "7 days free, then \(price) \(selectedProduct.billingLabel). Auto-renews.")
                     : selectedProduct.isSubscription ? String(localized: "\(price) \(selectedProduct.billingLabel). Auto-renews until canceled.")
                     : String(localized: "\(price), once. No subscription."))
                    .font(Geist.caption())
                    .foregroundStyle(Thoughtful.secondary)
            }
            Button(purchaseButtonTitle(for: selectedProduct)) {
                let product = selectedProduct
                Task { await storeManager.purchase(product, context: context) }
            }
            .buttonStyle(GeistButtonStyle(variant: .primary))
            .frame(maxWidth: 480)
            .disabled(storeManager.isPurchasing || storeManager.isRestoring || storeManager.product(for: selectedProduct) == nil)
        }
    }

    private func planTitle(_ product: VoxboardPurchaseProduct) -> String {
        switch product {
        case .individualWeekly, .familyWeekly: String(localized: "Weekly")
        case .individualYearly, .familyYearly: String(localized: "Yearly")
        case .familyUpgrade: String(localized: "Upgrade to Family Lifetime")
        default: String(localized: "Lifetime")
        }
    }

    private func macOffer(
        product: VoxboardPurchaseProduct,
        title: LocalizedStringKey,
        detail: LocalizedStringKey
    ) -> some View {
        Button {
            selectedPlanIndex = offers.firstIndex(of: product) ?? 0
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selectedProduct == product ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Geist.label(.body))
                    Text(detail).font(Geist.caption()).foregroundStyle(Thoughtful.secondary)
                }
                Spacer()
                Text(storeManager.displayPrice(for: product) ?? String(localized: "Price unavailable"))
                    .font(Geist.label(.body))
                    .monospacedDigit()
            }
            .foregroundStyle(Thoughtful.ink)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 76)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(storeManager.isPurchasing || storeManager.isRestoring)
        .accessibilityAddTraits(selectedProduct == product ? .isSelected : [])
    }

    private func purchaseButtonTitle(for product: VoxboardPurchaseProduct) -> String {
        if storeManager.purchasingProductID == product.rawValue {
            return String(localized: "Purchasing…")
        }
        if storeManager.offersFreeTrial(product) { return String(localized: "Start 7-Day Free Trial") }
        return switch product {
        case .individualWeekly, .individualYearly, .familyWeekly, .familyYearly: String(localized: "Subscribe")
        case .individual, .family: String(localized: "Buy Lifetime")
        case .familyUpgrade: String(localized: "Upgrade to Family")
        }
    }

    private var paywallTitle: String {
        switch usageTracker.accessLevel {
        case .free: String(localized: "A home for every thought.")
        case .individual: String(localized: "A little more room.")
        case .family: String(localized: "Vox.md Family Unlimited")
        }
    }

    private var paywallDetail: String {
        switch usageTracker.accessLevel {
        case .free:
            String(localized: "Unlimited Capture. Private, on-device transcription. Your words, in your own Markdown files.")
        case .individual:
            String(localized: "Your Unlimited access is active. Lifetime owners can upgrade to Family Sharing.")
        case .family:
            String(localized: "Your Unlimited access supports Apple Family Sharing.")
        }
    }
}

private struct MacDebugLogView: View {
    @State private var logText = KeyboardDebugLog.shared.read()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Diagnostics")
                        .font(Geist.heading(.title2))
                    Text("Review local hotkey, recording, export, and purchase restore diagnostics.")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                }
                Spacer()
                Button("Clear") {
                    KeyboardDebugLog.shared.clear()
                    logText = "(cleared)"
                }
                .foregroundColor(MacBrand.attention)
                Button("Refresh", systemImage: "arrow.clockwise") {
                    refresh()
                }
                Button("Copy", systemImage: "doc.on.doc") {
                    copyToPasteboard(logText)
                }
                if AppConstants.sharedContainerURL != nil {
                    Button("Reveal Data Folder", systemImage: "folder") {
                        revealDataFolder()
                    }
                }
            }
            .padding(Geist.Spacing.four)
            GeistDivider()
            ScrollView {
                Text(logText.isEmpty ? String(localized: "(empty)") : logText)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundColor(Geist.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Geist.Spacing.four)
            }
        }
        .background(Geist.Palette.background100)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        logText = KeyboardDebugLog.shared.read()
    }

    private func revealDataFolder() {
        guard let url = AppConstants.sharedContainerURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

private extension CapturePresetProcessingMode {
    var helpText: String {
        switch self {
        case .none:
            return String(localized: "Keeps typed Markdown, OCR, and voice text exactly as captured.")
        case .clean:
            return String(localized: "Improves casing and punctuation on device while preserving meaning and Markdown structure.")
        case .todoList:
            return String(localized: "Turns captured tasks into `- [ ]` Markdown checklist items without inventing new tasks.")
        case .meetingNotes:
            return String(localized: "Builds grounded Markdown meeting notes from typed text, OCR, or voice.")
        case .custom:
            return String(localized: "Follows your instruction on device for any Capture text when enabled.")
        }
    }
}

// MARK: - Shared helpers

private func sectionHeader(_ number: String, _ title: LocalizedStringKey) -> some View {
    HStack {
        GeistSectionLabel(number: number, title: title)
        Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.top, 28)
    .padding(.bottom, 12)
    .background(Geist.Palette.gray100)
}

private func settingsRow(title: String, detail: String, trailing: String) -> some View {
    VStack(spacing: 0) {
        GeistDivider()
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Geist.label())
                    .foregroundColor(Geist.text)
                Text(detail)
                    .font(Geist.caption())
                    .foregroundColor(Geist.muted)
            }
            Spacer()
            if !trailing.isEmpty {
                Text(trailing)
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .tracking(0.66)
                    .foregroundColor(Geist.muted)
            }
        }
        .padding(20)
        .background(Geist.Palette.gray100)
    }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

private func formatDurationShort(_ d: TimeInterval) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.allowedUnits = d < 60 ? [.second] : [.minute, .second]
    formatter.maximumUnitCount = 2
    return formatter.string(from: max(0, d)) ?? String(localized: "0 sec")
}

private func relativeDate(_ date: Date) -> String {
    let now = Date()
    if now.timeIntervalSince(date) < 86_400 {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }
    let f = DateFormatter()
    f.dateStyle = .short
    f.timeStyle = .none
    return f.string(from: date)
}
