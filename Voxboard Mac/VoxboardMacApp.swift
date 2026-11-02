import AppKit
import Carbon
import SwiftUI
import UniformTypeIdentifiers
import VoxboardShared

@main
struct VoxboardMacApp: App {
    @NSApplicationDelegateAdaptor(VoxboardMacAppDelegate.self) private var appDelegate
    @State private var modelManager = ModelManager()
    @State private var transcriptStore: TranscriptStore
    @State private var usageTracker: UsageTracker
    @State private var storeManager: MacStoreManager
    @State private var recorder: MacRecorder
    @State private var quickCaptureViewModel: QuickCaptureViewModel
    @State private var windowCoordinator: MacWindowCoordinator
    #if DEBUG
    private static let runtimeQueueValidationArgument = "--runtime-queue-validation"
    private static var localizationScreenshotWindow: NSWindow?
    #endif
    @AppStorage(MacAppVisibilityMode.storageKey, store: AppConstants.sharedDefaults)
    private var visibilityModeRaw = MacAppVisibilityMode.dockAndMenuBar.rawValue

    init() {
        RetiredAnalyticsCleanup.run()
        if let defaults = AppConstants.sharedDefaults { RetiredAnalyticsCleanup.run(defaults: defaults) }
        Geist.registerBundledFonts()
        MacFileBusyRetry.configureMonitor()
        let modelManager = ModelManager()
        let store = TranscriptStore()
        let usage = UsageTracker()
        let storeManager = MacStoreManager(usageTracker: usage)

        // Match the iOS app's on-device Apple Intelligence enrichment path on
        // macOS 26+ when Foundation Models is available for this Mac/user.
        let enricher: TranscriptEnricher?
        if #available(macOS 26, *) {
            enricher = TranscriptEnricher(backend: FoundationModelsBackend())
        } else {
            enricher = nil
        }

        let captureRequestProcessor = CapturePresetRequestProcessor(
            textProcessor: enricher.map { EnrichedCapturePresetTextProcessor(enricher: $0) },
            imageDescriber: OnDeviceImageSupport.makeDescriber()
        )
        let quickCaptureViewModel = QuickCaptureViewModel(
            defaultCaptureSource: .mac,
            requestProcessor: captureRequestProcessor
        )
        let windowCoordinator = MacWindowCoordinator()
        let recorder = MacRecorder(
            transcriptStore: store,
            usageTracker: usage,
            transcriptEnricher: enricher,
            speakerDiarizationService: SpeakerDiarizationService(),
            captureDraftEventHandler: { [weak quickCaptureViewModel] event in
                guard let quickCaptureViewModel else { return false }
                switch event {
                case .origin(let source, let locationOutcome, let profileSnapshot):
                    return await quickCaptureViewModel.journalRecordedOrigin(
                        source: source,
                        outcome: locationOutcome,
                        profileSnapshot: profileSnapshot
                    )
                case .clearOrigin(let profileID):
                    return await quickCaptureViewModel.clearRecordedOrigin(profileID: profileID)
                case .audio(let url, let draftRequestID, let deliveryID):
                    guard draftRequestID == nil || quickCaptureViewModel.draft.requestID == draftRequestID else {
                        return false
                    }
                    return await quickCaptureViewModel.stageRecordedAudio(
                        at: url,
                        deliveryID: deliveryID
                    ) != nil
                case .transcript(let text, let draftRequestID, let liveSessionID, let deliveryID):
                    guard draftRequestID == nil || quickCaptureViewModel.draft.requestID == draftRequestID else {
                        return false
                    }
                    return await quickCaptureViewModel.appendRecordedTranscript(
                        text,
                        sessionID: liveSessionID,
                        deliveryID: deliveryID
                    )
                case .liveTranscript(let sessionID, let finalizedText, let volatileText):
                    await quickCaptureViewModel.updateLiveRecordedTranscript(
                        sessionID: sessionID,
                        finalizedText: finalizedText,
                        volatileText: volatileText
                    )
                    return true
                case .cancelLiveTranscript(let sessionID):
                    await quickCaptureViewModel.cancelLiveRecordedTranscript(sessionID: sessionID)
                    return true
                }
            },
            liveTranscriptInvalidationHandler: { [weak quickCaptureViewModel] sessionID in
                quickCaptureViewModel?.invalidateLiveRecordedTranscriptSession(sessionID)
            },
            pendingCaptureRetryHandler: { [weak quickCaptureViewModel] in
                await quickCaptureViewModel?.processPendingInbox()
            }
        )

        quickCaptureViewModel.configureCaptureRouteOwnership { [weak recorder] in
            recorder?.ownsCaptureRoute == true
        }

        _modelManager = State(initialValue: modelManager)
        _transcriptStore = State(initialValue: store)
        _usageTracker = State(initialValue: usage)
        _storeManager = State(initialValue: storeManager)
        _recorder = State(initialValue: recorder)
        _quickCaptureViewModel = State(initialValue: quickCaptureViewModel)
        _windowCoordinator = State(initialValue: windowCoordinator)

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(Self.runtimeQueueValidationArgument) {
            // Allows isolated, noninteractive app-runtime validation with
            // VOXBOARD_SHARED_CONTAINER_OVERRIDE. No production launch path
            // observes either test hook.
            DispatchQueue.main.async {
                recorder.resumeRecordingQueue()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                await recorder.runRuntimeMicrophoneCaptureIfRequested(
                    modelManager: modelManager
                )
            }
        }
        if MacDebugSignalFixtures.isRequested {
            Task { @MainActor in
                await MacDebugSignalFixtures.seedIfRequested(viewModel: quickCaptureViewModel)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--localization-screenshot") {
            DispatchQueue.main.async {
                let root = MacLocalizationScreenshotRoot(
                    recorder: recorder,
                    quickCaptureViewModel: quickCaptureViewModel,
                    windowCoordinator: windowCoordinator
                )
                .environment(modelManager)
                .environment(store)
                .environment(usage)
                .environment(storeManager)
                .tint(MacBrand.orange)
                .preferredColorScheme(
                    ProcessInfo.processInfo.arguments.contains("--localization-screenshot-dark") ? .dark : .light
                )

                let controller = NSHostingController(rootView: root)
                let window = NSWindow(contentViewController: controller)
                window.identifier = NSUserInterfaceItemIdentifier(
                    "VoxboardLocalizationScreenshot"
                )
                window.title = "Vox.md"
                // Match the main window's hidden title bar.
                if !ProcessInfo.processInfo.arguments.contains("03-settings") {
                    window.styleMask.insert(.fullSizeContentView)
                    window.titlebarAppearsTransparent = true
                    window.titleVisibility = .hidden
                }
                window.setContentSize(MacLocalizationScreenshotRoot.storySize)
                window.center()
                window.isReleasedWhenClosed = false
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                Self.localizationScreenshotWindow = window
            }
        }
        #endif
    }

    private var visibilityMode: MacAppVisibilityMode {
        MacAppVisibilityMode(rawValue: visibilityModeRaw) ?? .dockAndMenuBar
    }

    private var menuBarVisibilityBinding: Binding<Bool> {
        Binding(
            get: { visibilityMode.showsMenuBar },
            set: { _ in /* read-only mirror of `visibilityMode` */ }
        )
    }

    var body: some Scene {
        WindowGroup("Vox.md", id: "main") {
            Group {
                if usageTracker.hasUnlocked {
                    MacRootView(
                        recorder: recorder,
                        quickCaptureViewModel: quickCaptureViewModel,
                        windowCoordinator: windowCoordinator
                    )
                } else {
                    MacPaywallView(context: .onboarding, isAccessGate: true, historyViewModel: quickCaptureViewModel)
                }
            }
                .tint(MacBrand.orange)
                .task {
                    // Busy notes (open with unsaved changes or locked in
                    // another app) are retried every minute while Vox.md runs.
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(CaptureFileBusyMonitor.retryInterval)) } catch { return }
                        await MacFileBusyRetry.retryDue(
                            viewModel: quickCaptureViewModel,
                            recorder: recorder,
                            modelManager: modelManager
                        )
                    }
                }
                .task {
                    // Drain the shared capture inbox on a cadence while the Mac
                    // app runs, so queued captures retry without waiting for the
                    // next foreground activation (#11).
                    while !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(30)) } catch { return }
                        await storeManager.syncCurrentEntitlements()
                        await quickCaptureViewModel.processPendingInbox()
                    }
                }
                .environment(modelManager)
                .environment(transcriptStore)
                .environment(usageTracker)
                .environment(storeManager)
                .onAppear {
                    appDelegate.configureURLHandler(handleURL)
                    appDelegate.configureLifecycleHandlers(
                        didBecomeActive: { [weak quickCaptureViewModel, weak recorder, weak windowCoordinator, weak storeManager] in
                            await storeManager?.syncCurrentEntitlements()
                            if let quickCaptureViewModel, let windowCoordinator {
                                Self.consumePendingQuickCaptureOpenIfNeeded(
                                    quickCaptureViewModel: quickCaptureViewModel,
                                    windowCoordinator: windowCoordinator
                                )
                            }
                            recorder?.resumeRecordingQueue()
                            await quickCaptureViewModel?.retryFailedInbox()
                        },
                        flushDraft: { [weak quickCaptureViewModel, weak recorder, weak windowCoordinator] in
                            if recorder?.isRecording == true
                                || recorder?.isExporting == true {
                                recorder?.lastError = String(localized: "Wait for the current recording or Capture export to finish before quitting.")
                                windowCoordinator?.showMain(.navigate(.capture))
                                return false
                            }
                            return await quickCaptureViewModel?.flushDraftForTermination() ?? false
                        },
                        reopen: { [weak windowCoordinator] in
                            windowCoordinator?.showMain(.navigate(.capture))
                        }
                    )
                    storeManager.start()
                    transcriptStore.reload()
                    usageTracker.reload()
                    MacQuickCapturePanelController.shared.configure(
                        recorder: recorder,
                        viewModel: quickCaptureViewModel,
                        modelManager: modelManager,
                        usageTracker: usageTracker,
                        transcriptStore: transcriptStore,
                        storeManager: storeManager,
                        windowCoordinator: windowCoordinator
                    )
                    configureGlobalHotKeys()
                    #if DEBUG
                    MacGlobalHotKeyCenter.shared.debugSimulateQuickCaptureIfRequested()
                    #endif
                    recorder.resumeRecordingQueue()
                    Self.consumePendingQuickCaptureOpenIfNeeded(
                        quickCaptureViewModel: quickCaptureViewModel,
                        windowCoordinator: windowCoordinator
                    )
                    Task {
                        await storeManager.syncCurrentEntitlements()
                        usageTracker.reload()
                        await quickCaptureViewModel.processPendingInbox()
                    }
                }
                .onChange(of: visibilityModeRaw) { _, _ in
                    visibilityMode.apply()
                }
                .onChange(of: usageTracker.hasUnlocked) { _, hasUnlocked in
                    guard hasUnlocked else { return }
                    Task { await quickCaptureViewModel.processPendingInbox() }
                }
        }
        .handlesExternalEvents(matching: ["capture", "capture-request", "listen"])
        // The Signal boards are drawn at 1440×900; open roomy enough that the
        // breadcrumb, Speak and Send fit beside the route inspector.
        .defaultSize(width: 1_280, height: 820)
        // Signal chrome: no title bar or toolbar; the traffic lights sit at
        // the top of the sidebar as on the boards. Commands are in the menu bar.
        .windowStyle(.hiddenTitleBar)
        .commands {
            SidebarCommands()
            InspectorCommands()
            MacCaptureFormatCommands()
            CommandGroup(after: .sidebar) {
                MacListMenuItems()
            }

            CommandGroup(replacing: .newItem) {
                Button("New Capture") {
                    windowCoordinator.showMain(.newCapture)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Navigate") {
                // ⌘1–⌘4 pick routes (Signal); views move to ⌃⌘1–⌃⌘3.
                Button("Capture") {
                    windowCoordinator.showMain(.navigate(.capture))
                }
                .keyboardShortcut("1", modifiers: [.command, .control])

                Button("Activity") {
                    windowCoordinator.showMain(.navigate(.activity))
                }
                .keyboardShortcut("2", modifiers: [.command, .control])

                Button("Library") {
                    windowCoordinator.showMain(.navigate(.library))
                }
                .keyboardShortcut("3", modifiers: [.command, .control])

                Divider()

                Button("All Shortcuts") {
                    NotificationCenter.default.post(name: .macShowAllShortcuts, object: nil)
                }
                .keyboardShortcut("/", modifiers: .command)
            }

            CommandMenu("Route") {
                // Every enabled route (the old toolbar route menu); ⌘1–⌘4 for
                // the first four, as in the sidebar.
                ForEach(Array(MacRouteCatalog.enabledRoutes(in: quickCaptureViewModel).enumerated()), id: \.element.id) { index, route in
                    let button = Button {
                        MacRouteCatalog.select(route, in: quickCaptureViewModel)
                        if !MacQuickCapturePanelController.shared.isKeyWindow {
                            windowCoordinator.showMain(.navigate(.capture))
                        }
                    } label: {
                        if route.id == quickCaptureViewModel.selectedVoxProfile?.id {
                            Label(MacRouteCatalog.displayName(route), systemImage: "checkmark")
                        } else {
                            Text(MacRouteCatalog.displayName(route))
                        }
                    }
                    .disabled(!quickCaptureViewModel.canChangeCaptureRoute)
                    if index < 4 {
                        button.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    } else {
                        button
                    }
                }

                Divider()

                Button("Quick Capture") {
                    MacQuickCapturePanelController.shared.toggle()
                }
            }

            CommandMenu("Capture") {
                Button("Show Capture") {
                    windowCoordinator.showMain(.navigate(.capture))
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])

                Button("Show Activity") {
                    windowCoordinator.showMain(.navigate(.activity))
                }

                Button("Show Library") {
                    windowCoordinator.showMain(.navigate(.library))
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button(recorder.isRecording
                       ? String(localized: "Stop + Transcribe")
                       : String(localized: "Start Recording")) {
                    Self.handleGlobalHotKey(
                        recorder: recorder,
                        quickCaptureViewModel: quickCaptureViewModel,
                        modelManager: modelManager,
                        usageTracker: usageTracker,
                        windowCoordinator: windowCoordinator
                    )
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Button("Add Files to Capture…") {
                    windowCoordinator.showMain(.chooseFiles)
                }
                .keyboardShortcut("a", modifiers: [.command, .shift])

                Button("Clear Capture Draft") {
                    windowCoordinator.showMain(.newCapture)
                }
                .disabled(!quickCaptureViewModel.draft.hasCaptureContent)

                Divider()

                // Formerly the Capture window's toolbar menus.
                MacCaptureMenuItems()
            }

            CommandMenu("Vox.md") {
                Button("Reveal Data Folder") {
                    if let url = AppConstants.sharedContainerURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }

                Divider()

                Menu("Visibility") {
                    ForEach(MacAppVisibilityMode.allCases) { mode in
                        Button {
                            visibilityModeRaw = mode.rawValue
                            mode.apply()
                        } label: {
                            if visibilityMode == mode {
                                Label(mode.title, systemImage: "checkmark")
                            } else {
                                Text(mode.title)
                            }
                        }
                    }
                }
            }
        }

        Settings {
            MacSettingsView(recorder: recorder)
            .environment(modelManager)
            .environment(transcriptStore)
            .environment(usageTracker)
            .environment(storeManager)
            .tint(MacBrand.orange)
            .frame(minWidth: 760, minHeight: 640)
        }

        MenuBarExtra(isInserted: menuBarVisibilityBinding) {
            MacMenuBarMenu(
                recorder: recorder,
                quickCaptureViewModel: quickCaptureViewModel,
                windowCoordinator: windowCoordinator
            )
                .environment(modelManager)
                .environment(transcriptStore)
                .environment(usageTracker)
                .environment(storeManager)
                .tint(MacBrand.orange)
        } label: {
            Image(systemName: menuBarSymbolName)
                .help(menuBarStatusText)
        }
        .menuBarExtraStyle(.menu)
    }

    private var menuBarSymbolName: String {
        if recorder.isRecording { return "record.circle.fill" }
        if recorder.isTranscribing || recorder.isExporting { return "waveform.circle.fill" }
        return "mic.circle"
    }

    private var menuBarStatusText: String {
        if recorder.isRecording { return String(localized: "Vox.md is recording") }
        if recorder.isTranscribing { return String(localized: "Vox.md is transcribing") }
        if recorder.isExporting { return String(localized: "Vox.md is finishing the Capture export") }
        return "Vox.md"
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == AppConstants.urlScheme else { return }
        switch url.host {
        case "capture", "capture-request":
            do {
                let action = try CaptureDeepLinkParser().parse(url)
                Task { @MainActor in
                    // Finish the serialized load/mutation/persist path before
                    // the selected Capture window is allowed to consume the
                    // requested input from the shared view model.
                    await quickCaptureViewModel.handleDeepLink(action)
                    windowCoordinator.showMain(.navigate(.capture))
                }
            } catch {
                quickCaptureViewModel.errorMessage = error.localizedDescription
                windowCoordinator.showMain(.navigate(.capture))
            }
        case "listen":
            windowCoordinator.showMain(.navigate(.capture))
        default:
            break
        }
    }

    @MainActor
    private static func consumePendingQuickCaptureOpenIfNeeded(
        quickCaptureViewModel: QuickCaptureViewModel,
        windowCoordinator: MacWindowCoordinator
    ) {
        guard AppConstants.sharedDefaults?.bool(
            forKey: AppConstants.pendingQuickCaptureOpenKey
        ) == true else { return }

        AppConstants.sharedDefaults?.set(false, forKey: AppConstants.pendingQuickCaptureOpenKey)
        let defaults = AppConstants.sharedDefaults
        let incoming = CaptureDeepLinkDraft(
            voxID: defaults?.string(forKey: AppConstants.pendingQuickCaptureVoxIdKey),
            requestedInput: defaults?.string(forKey: AppConstants.pendingQuickCaptureInputKey)
                .flatMap(CaptureRequestedInput.init(rawValue:)),
            source: defaults?.string(forKey: AppConstants.pendingQuickCaptureSourceKey)
                .flatMap(CaptureSource.init(rawValue:))
        )
        defaults?.removeObject(forKey: AppConstants.pendingQuickCaptureSourceKey)
        defaults?.removeObject(forKey: AppConstants.pendingQuickCaptureVoxIdKey)
        defaults?.removeObject(forKey: AppConstants.pendingQuickCaptureInputKey)
        Task { @MainActor in
            await quickCaptureViewModel.handleDeepLink(.openComposer(incoming))
            windowCoordinator.showMain(.navigate(.capture))
        }
    }

    private func configureGlobalHotKeys() {
        let recorder = recorder
        let modelManager = modelManager
        let usageTracker = usageTracker
        let windowCoordinator = windowCoordinator
        MacGlobalHotKeyCenter.shared.configure { target in
            let flowID: String?
            let completionMode: MacRecordingCompletionMode?
            switch target {
            case .quickCapture:
                // Routed through MacQuickCapturePanelController (press/hold).
                return
            case .transcriptionOnly:
                flowID = nil
                completionMode = .transcriptionOnly
            case .selectedPreset:
                flowID = nil
                completionMode = nil
            case .preset(let presetID):
                guard CapturePresetStore.loadFlows().contains(where: {
                    $0.id == presetID && $0.isEnabled
                }) else {
                    NSSound.beep()
                    return
                }
                flowID = presetID
                completionMode = nil
            }
            Self.handleGlobalHotKey(
                recorder: recorder,
                quickCaptureViewModel: quickCaptureViewModel,
                modelManager: modelManager,
                usageTracker: usageTracker,
                windowCoordinator: windowCoordinator,
                flowID: flowID,
                completionMode: completionMode
            )
        }
    }

    @MainActor
    private static func handleGlobalHotKey(
        recorder: MacRecorder,
        quickCaptureViewModel: QuickCaptureViewModel,
        modelManager: ModelManager,
        usageTracker: UsageTracker,
        windowCoordinator: MacWindowCoordinator,
        flowID requestedFlowID: String? = nil,
        completionMode: MacRecordingCompletionMode? = nil
    ) {
        let flowId = requestedFlowID ?? CapturePresetStore.selectedFlowId()
        if recorder.isRecording {
            recorder.stopAndTranscribe(modelManager: modelManager, flowId: flowId)
            return
        }

        guard !usageTracker.isAtLimit else {
            recorder.needsUnlock = true
            windowCoordinator.showMain(.navigate(.capture))
            return
        }

        Task { @MainActor in
            await quickCaptureViewModel.load()
            guard let operation = quickCaptureViewModel.beginCaptureRouteOperation() else {
                windowCoordinator.showMain(.navigate(.capture))
                return
            }
            defer { quickCaptureViewModel.endCaptureRouteOperation(operation) }
            let granted = await AudioRecorder.requestMicrophonePermission()
            guard !Task.isCancelled, !recorder.ownsCaptureRoute,
                  CapturePresetStore.loadFlows().contains(where: { $0.id == flowId && $0.isEnabled }) else { return }
            guard granted else {
                recorder.lastError = String(localized: "Could not access the microphone. Check macOS Privacy & Security settings.")
                windowCoordinator.showMain(.navigate(.capture))
                return
            }

            recorder.startRecording(
                modelManager: modelManager,
                flowId: flowId,
                completionMode: completionMode
            )
            if !recorder.isRecording, recorder.lastError != nil {
                windowCoordinator.showMain(.navigate(.capture))
            }
        }
    }
}

enum MacMainWindowRequest: Equatable {
    case navigate(MacDestination)
    case chooseFiles
    case newCapture
}

enum MacSceneWindowKind {
    case main(token: String)
}

/// Routes commands to the intended main SwiftUI window instead of guessing from
/// `NSApplication.windows`, where Settings and sheets can become key windows.
@MainActor
final class MacWindowCoordinator {
    private final class WeakWindow {
        weak var value: NSWindow?
        init(_ value: NSWindow) { self.value = value }
    }

    private var openWindowAction: OpenWindowAction?
    private var mainWindows: [String: WeakWindow] = [:]
    private var pendingUnassignedMainRequest: MacMainWindowRequest?
    private var pendingMainRequests: [String: MacMainWindowRequest] = [:]
    private var readyMainTokens = Set<String>()
    private var readyCaptureTokens = Set<String>()

    func configure(openWindow: OpenWindowAction) {
        openWindowAction = openWindow
    }

    func register(window: NSWindow, kind: MacSceneWindowKind) {
        switch kind {
        case .main(let token):
            mainWindows[token] = WeakWindow(window)
            if let request = pendingUnassignedMainRequest {
                pendingUnassignedMainRequest = nil
                pendingMainRequests[token] = request
                focus(window)
                if readyMainTokens.contains(token) {
                    route(request, to: token)
                }
            }
        }
    }

    func showMain(_ request: MacMainWindowRequest) {
        MacAppVisibilityMode.current.apply()
        pruneClosedWindows()
        if let (token, window) = preferredMainWindow() {
            focus(window)
            route(request, to: token)
        } else {
            pendingUnassignedMainRequest = request
            openWindowAction?(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func mainRootReady(token: String) {
        readyMainTokens.insert(token)
        if let request = pendingMainRequests[token] {
            route(request, to: token)
        }
    }

    func mainRootNotReady(token: String) {
        readyMainTokens.remove(token)
        readyCaptureTokens.remove(token)
    }

    func captureWorkspaceReady(token: String) {
        readyCaptureTokens.insert(token)
        deliverPendingCaptureRequestIfReady(to: token)
    }

    func captureWorkspaceNotReady(token: String) {
        readyCaptureTokens.remove(token)
    }

    private func preferredMainWindow() -> (String, NSWindow)? {
        if let keyWindow = NSApplication.shared.keyWindow,
           let entry = mainWindows.first(where: { $0.value.value === keyWindow }) {
            return (entry.key, keyWindow)
        }
        for window in NSApplication.shared.orderedWindows {
            if let entry = mainWindows.first(where: { $0.value.value === window }),
               window.isVisible || window.isMiniaturized {
                return (entry.key, window)
            }
        }
        for (token, reference) in mainWindows {
            if let window = reference.value,
               window.isVisible || window.isMiniaturized {
                return (token, window)
            }
        }
        return nil
    }

    private func pruneClosedWindows() {
        mainWindows = mainWindows.filter { _, reference in
            guard let window = reference.value else { return false }
            return window.isVisible || window.isMiniaturized
        }
        let liveTokens = Set(mainWindows.keys)
        readyMainTokens.formIntersection(liveTokens)
        readyCaptureTokens.formIntersection(liveTokens)
        pendingMainRequests = pendingMainRequests.filter { liveTokens.contains($0.key) }
    }

    private func focus(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func route(_ request: MacMainWindowRequest, to token: String) {
        pendingMainRequests[token] = request
        guard readyMainTokens.contains(token) else { return }

        switch request {
        case .navigate(let destination):
            NotificationCenter.default.post(
                name: .macNavigate,
                object: MacNavigationRequest(windowToken: token, destination: destination)
            )
            if destination == .capture {
                // Keep the request pending across a cold mount. The tokened
                // focus/input event is delivered only after `load()` has crossed
                // the Capture workspace's destructive-restoration barrier.
                deliverPendingCaptureRequestIfReady(to: token)
            } else {
                pendingMainRequests[token] = nil
            }
        case .chooseFiles:
            NotificationCenter.default.post(
                name: .macNavigate,
                object: MacNavigationRequest(windowToken: token, destination: .capture)
            )
            deliverPendingCaptureRequestIfReady(to: token)
        case .newCapture:
            NotificationCenter.default.post(
                name: .macNavigate,
                object: MacNavigationRequest(windowToken: token, destination: .capture)
            )
            deliverPendingCaptureRequestIfReady(to: token)
        }
    }

    private func deliverPendingCaptureRequestIfReady(to token: String) {
        guard readyMainTokens.contains(token),
              readyCaptureTokens.contains(token),
              let request = pendingMainRequests[token] else { return }

        switch request {
        case .navigate(.capture), .chooseFiles, .newCapture:
            pendingMainRequests[token] = nil
            NotificationCenter.default.post(name: .macShowCapture, object: token)
            if request == .chooseFiles {
                NotificationCenter.default.post(name: .macChooseCaptureFiles, object: token)
            } else if request == .newCapture {
                NotificationCenter.default.post(name: .macClearCaptureDraft, object: token)
            }
        case .navigate:
            break
        }
    }
}

struct MacSceneWindowRegistrar: NSViewRepresentable {
    let kind: MacSceneWindowKind
    let coordinator: MacWindowCoordinator

    func makeNSView(context: Context) -> WindowProbeView {
        WindowProbeView { window in
            coordinator.register(window: window, kind: kind)
        }
    }

    func updateNSView(_ nsView: WindowProbeView, context: Context) {
        nsView.onWindow = { window in
            coordinator.register(window: window, kind: kind)
        }
        if let window = nsView.window {
            coordinator.register(window: window, kind: kind)
        }
    }

    final class WindowProbeView: NSView {
        var onWindow: (NSWindow) -> Void

        init(onWindow: @escaping (NSWindow) -> Void) {
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { onWindow(window) }
        }
    }
}

enum MacAppVisibilityMode: String, CaseIterable, Identifiable {
    case dockAndMenuBar
    case menuBarOnly
    case dockOnly
    case hidden

    var id: String { rawValue }

    static let storageKey = "macAppVisibilityMode"

    var title: String {
        switch self {
        case .dockAndMenuBar: return String(localized: "Dock + Menu Bar")
        case .menuBarOnly: return String(localized: "Menu Bar Only")
        case .dockOnly: return String(localized: "Dock Only")
        case .hidden: return String(localized: "Hidden")
        }
    }

    var summary: String {
        switch self {
        case .dockAndMenuBar: return String(localized: "Dock icon, Cmd-Tab, and menu bar")
        case .menuBarOnly: return String(localized: "Menu bar only — hidden from Dock and Cmd-Tab")
        case .dockOnly: return String(localized: "Dock icon and Cmd-Tab — no menu bar")
        case .hidden: return String(localized: "Invisible — reopen from Spotlight or Finder")
        }
    }

    var systemImage: String {
        switch self {
        case .dockAndMenuBar: return "macwindow.on.rectangle"
        case .menuBarOnly: return "menubar.rectangle"
        case .dockOnly: return "dock.rectangle"
        case .hidden: return "eye.slash"
        }
    }

    var showsMenuBar: Bool {
        switch self {
        case .dockAndMenuBar, .menuBarOnly: return true
        case .dockOnly, .hidden: return false
        }
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        switch self {
        case .dockAndMenuBar, .dockOnly: return .regular
        case .menuBarOnly, .hidden: return .accessory
        }
    }

    static var current: MacAppVisibilityMode {
        let raw = (AppConstants.sharedDefaults ?? .standard).string(forKey: storageKey) ?? ""
        return MacAppVisibilityMode(rawValue: raw) ?? .dockAndMenuBar
    }

    func apply() {
        let target = activationPolicy
        DispatchQueue.main.async {
            if NSApp.activationPolicy() != target {
                NSApp.setActivationPolicy(target)
            }
        }
    }

    func applyImmediately() {
        if NSApp.activationPolicy() != activationPolicy {
            NSApp.setActivationPolicy(activationPolicy)
        }
    }
}

final class VoxboardMacAppDelegate: NSObject, NSApplicationDelegate {
    private var openURLHandler: ((URL) -> Void)?
    private var pendingOpenURLs: [URL] = []
    private var didBecomeActiveHandler: (@MainActor () async -> Void)?
    private var flushDraftHandler: (@MainActor () async -> Bool)?
    private var reopenHandler: (@MainActor () -> Void)?
    private var isAwaitingTerminationReply = false

    @MainActor
    func configureURLHandler(_ handler: @escaping (URL) -> Void) {
        openURLHandler = handler
        let pending = pendingOpenURLs
        pendingOpenURLs.removeAll()
        for url in pending { handler(url) }
    }

    @MainActor
    func configureLifecycleHandlers(
        didBecomeActive: @escaping @MainActor () async -> Void,
        flushDraft: @escaping @MainActor () async -> Bool,
        reopen: @escaping @MainActor () -> Void
    ) {
        didBecomeActiveHandler = didBecomeActive
        flushDraftHandler = flushDraft
        reopenHandler = reopen
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        // `--debug-appearance=light|dark` pins the appearance for visual QA.
        if let raw = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--debug-appearance=") })?
            .dropFirst("--debug-appearance=".count) {
            NSApp.appearance = NSAppearance(named: raw == "dark" ? .darkAqua : .aqua)
        }
        if ProcessInfo.processInfo.arguments.contains("--localization-screenshot") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            scheduleLocalizationScreenshotIfRequested()
            return
        }
        #endif
        MacAppVisibilityMode.current.applyImmediately()
        MacKeyboardHintCenter.shared.start()
    }

    #if DEBUG
    private func scheduleLocalizationScreenshotIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--localization-screenshot-output"),
              arguments.indices.contains(index + 1) else { return }
        let destination = URL(fileURLWithPath: arguments[index + 1])

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let candidates = NSApp.windows.filter { $0.contentView != nil }
            let screenshotWindow = candidates.first {
                $0.identifier?.rawValue == "VoxboardLocalizationScreenshot"
            }
            guard let window = screenshotWindow ?? candidates.max(by: {
                $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
            }),
                  let contentView = window.contentView else { return }

            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            let view = contentView
            view.layoutSubtreeIfNeeded()

            guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.cacheDisplay(in: view.bounds, to: image)
            guard let data = image.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: destination, options: .atomic)
        }
    }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        MacKeyboardHintCenter.shared.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard let didBecomeActiveHandler else { return }
        Task { await didBecomeActiveHandler() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let openURLHandler else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        for url in urls { openURLHandler(url) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            reopenHandler?()
        }
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let flushDraftHandler else { return .terminateNow }
        guard !isAwaitingTerminationReply else { return .terminateLater }
        isAwaitingTerminationReply = true
        Task {
            let saved = await flushDraftHandler()
            isAwaitingTerminationReply = false
            sender.reply(toApplicationShouldTerminate: saved)
        }
        return .terminateLater
    }
}

enum MacHotKeyTarget: Hashable, Identifiable {
    /// Press opens the floating Quick Capture panel; hold to talk.
    case quickCapture
    case transcriptionOnly
    case selectedPreset
    case preset(String)

    var id: String {
        switch self {
        case .quickCapture: "quick-capture"
        case .transcriptionOnly: "transcription-only"
        case .selectedPreset: "selected-preset"
        case .preset(let presetID): "preset:\(presetID)"
        }
    }
}

struct MacHotKeyShortcut: Codable, Equatable {
    static let allowedModifierFlags: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
    private static let requiredModifierFlags: NSEvent.ModifierFlags = [.command, .option, .control]

    let keyCode: UInt32
    let modifierFlagsRawValue: UInt
    let keyEquivalent: String

    init(keyCode: UInt32, modifierFlags: NSEvent.ModifierFlags, keyEquivalent: String) {
        self.keyCode = keyCode
        self.modifierFlagsRawValue = modifierFlags.intersection(Self.allowedModifierFlags).rawValue
        self.keyEquivalent = keyEquivalent
    }

    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(Self.allowedModifierFlags)
        guard !modifiers.intersection(Self.requiredModifierFlags).isEmpty else { return nil }

        let keyName = Self.keyName(
            keyCode: event.keyCode,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers
        )
        guard !keyName.isEmpty else { return nil }

        self.keyCode = UInt32(event.keyCode)
        self.modifierFlagsRawValue = modifiers.rawValue
        self.keyEquivalent = keyName
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierFlagsRawValue).intersection(Self.allowedModifierFlags)
    }

    var carbonModifiers: UInt32 {
        var carbonModifiers: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        return carbonModifiers
    }

    var displayString: String {
        var pieces: [String] = []
        let flags = modifierFlags
        if flags.contains(.control) { pieces.append("⌃") }
        if flags.contains(.option) { pieces.append("⌥") }
        if flags.contains(.shift) { pieces.append("⇧") }
        if flags.contains(.command) { pieces.append("⌘") }
        pieces.append(keyEquivalent)
        return pieces.joined()
    }

    func conflicts(with other: MacHotKeyShortcut) -> Bool {
        keyCode == other.keyCode && modifierFlags == other.modifierFlags
    }

    private static func keyName(keyCode: UInt16, charactersIgnoringModifiers: String?) -> String {
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 71: return "Clear"
        case 76: return "Enter"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 99: return "F3"
        case 100: return "F8"
        case 101: return "F9"
        case 103: return "F11"
        case 105: return "F13"
        case 106: return "F16"
        case 107: return "F14"
        case 109: return "F10"
        case 111: return "F12"
        case 113: return "F15"
        case 118: return "F4"
        case 120: return "F2"
        case 122: return "F1"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            let trimmed = (charactersIgnoringModifiers ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "" }
            return trimmed.uppercased()
        }
    }
}

enum MacHotKeyStore {
    /// Retained for compatibility with existing installations that configured
    /// the original single start/stop shortcut.
    static let storageKey = "macGlobalHotKeyShortcut"
    static let transcriptionOnlyStorageKey = "macTranscriptionOnlyHotKeyShortcut"
    static let presetStorageKey = "macCapturePresetHotKeyShortcuts"
    static let quickCaptureStorageKey = "macQuickCaptureHotKeyShortcut"
    /// Stored when the person turns the Quick Capture shortcut off, so the
    /// ⌥Space default is not re-applied.
    private static let disabledSentinel = "off"
    /// ⌥Space: the Signal default for Quick Capture.
    static let defaultQuickCaptureShortcut = MacHotKeyShortcut(
        keyCode: 49,
        modifierFlags: [.option],
        keyEquivalent: "Space"
    )

    /// Display string for the Quick Capture shortcut ("⌥Space"), or nil when
    /// it is turned off.
    static var quickCaptureDisplayString: String? {
        load(for: .quickCapture)?.displayString
    }

    static func load(for target: MacHotKeyTarget = .selectedPreset) -> MacHotKeyShortcut? {
        switch target {
        case .quickCapture:
            let encoded = AppConstants.sharedDefaults?.string(forKey: quickCaptureStorageKey)
            if encoded == disabledSentinel { return nil }
            if let encoded, let shortcut = decode(encoded) { return shortcut }
            // Default ⌥Space unless an older recording keybind already uses it.
            let defaultShortcut = defaultQuickCaptureShortcut
            let others = [load(for: .transcriptionOnly), load(for: .selectedPreset)]
                + loadPresetShortcuts().values.map(Optional.some)
            guard !others.contains(where: { $0?.conflicts(with: defaultShortcut) == true }) else {
                return nil
            }
            return defaultShortcut
        case .transcriptionOnly:
            guard let encoded = AppConstants.sharedDefaults?.string(forKey: transcriptionOnlyStorageKey) else { return nil }
            return decode(encoded)
        case .selectedPreset:
            guard let encoded = AppConstants.sharedDefaults?.string(forKey: storageKey) else { return nil }
            return decode(encoded)
        case .preset(let presetID):
            return loadPresetShortcuts()[presetID]
        }
    }

    static func save(_ shortcut: MacHotKeyShortcut, for target: MacHotKeyTarget = .selectedPreset) {
        switch target {
        case .quickCapture:
            guard let encoded = encode(shortcut) else { return }
            AppConstants.sharedDefaults?.set(encoded, forKey: quickCaptureStorageKey)
        case .transcriptionOnly:
            guard let encoded = encode(shortcut) else { return }
            AppConstants.sharedDefaults?.set(encoded, forKey: transcriptionOnlyStorageKey)
        case .selectedPreset:
            guard let encoded = encode(shortcut) else { return }
            AppConstants.sharedDefaults?.set(encoded, forKey: storageKey)
        case .preset(let presetID):
            var shortcuts = loadPresetShortcuts()
            shortcuts[presetID] = shortcut
            savePresetShortcuts(shortcuts)
        }
    }

    static func clear(_ target: MacHotKeyTarget = .selectedPreset) {
        switch target {
        case .quickCapture:
            AppConstants.sharedDefaults?.set(disabledSentinel, forKey: quickCaptureStorageKey)
        case .transcriptionOnly:
            AppConstants.sharedDefaults?.removeObject(forKey: transcriptionOnlyStorageKey)
        case .selectedPreset:
            AppConstants.sharedDefaults?.removeObject(forKey: storageKey)
        case .preset(let presetID):
            var shortcuts = loadPresetShortcuts()
            shortcuts.removeValue(forKey: presetID)
            savePresetShortcuts(shortcuts)
        }
    }

    static func configuredBindings() -> [(target: MacHotKeyTarget, shortcut: MacHotKeyShortcut)] {
        var bindings: [(MacHotKeyTarget, MacHotKeyShortcut)] = []
        if let shortcut = load(for: .quickCapture) {
            bindings.append((.quickCapture, shortcut))
        }
        if let shortcut = load(for: .transcriptionOnly) {
            bindings.append((.transcriptionOnly, shortcut))
        }
        if let shortcut = load() {
            bindings.append((.selectedPreset, shortcut))
        }
        bindings.append(contentsOf: loadPresetShortcuts()
            .sorted(by: { $0.key < $1.key })
            .map { (.preset($0.key), $0.value) })
        return bindings
    }

    static func conflictingTarget(
        for shortcut: MacHotKeyShortcut,
        excluding excludedTarget: MacHotKeyTarget,
        activePresetIDs: Set<String>
    ) -> MacHotKeyTarget? {
        configuredBindings().first(where: { binding in
            guard binding.target != excludedTarget,
                  binding.shortcut.conflicts(with: shortcut) else { return false }
            switch binding.target {
            case .quickCapture, .transcriptionOnly, .selectedPreset:
                return true
            case .preset(let presetID):
                return activePresetIDs.contains(presetID)
            }
        })?.target
    }

    static func decode(_ encoded: String) -> MacHotKeyShortcut? {
        guard let data = encoded.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MacHotKeyShortcut.self, from: data)
    }

    static func encode(_ shortcut: MacHotKeyShortcut) -> String? {
        guard let data = try? JSONEncoder().encode(shortcut) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func loadPresetShortcuts() -> [String: MacHotKeyShortcut] {
        guard let encoded = AppConstants.sharedDefaults?.string(forKey: presetStorageKey),
              let data = encoded.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: MacHotKeyShortcut].self, from: data)) ?? [:]
    }

    private static func savePresetShortcuts(_ shortcuts: [String: MacHotKeyShortcut]) {
        guard !shortcuts.isEmpty else {
            AppConstants.sharedDefaults?.removeObject(forKey: presetStorageKey)
            return
        }
        guard let data = try? JSONEncoder().encode(shortcuts),
              let encoded = String(data: data, encoding: .utf8) else { return }
        AppConstants.sharedDefaults?.set(encoded, forKey: presetStorageKey)
    }
}

private let macHotKeySignature: OSType = 0x564F5848 // VOXH

nonisolated private func macHotKeyHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ eventRef: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        eventRef,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr,
          hotKeyID.signature == 0x564F5848 else {
        return noErr
    }

    let pressedHotKeyID = hotKeyID.id
    let isRelease = eventRef.map { GetEventKind($0) == UInt32(kEventHotKeyReleased) } ?? false
    Task { @MainActor in
        if isRelease {
            MacGlobalHotKeyCenter.shared.handleHotKeyReleased(id: pressedHotKeyID)
        } else {
            MacGlobalHotKeyCenter.shared.handleHotKeyPressed(id: pressedHotKeyID)
        }
    }
    return noErr
}

@MainActor
final class MacGlobalHotKeyCenter {
    static let shared = MacGlobalHotKeyCenter()

    private var action: ((MacHotKeyTarget) -> Void)?
    /// Quick Capture distinguishes press (open) from hold (push-to-talk), so
    /// it receives both key-down and key-up.
    var quickCapturePressHandler: (() -> Void)?
    var quickCaptureReleaseHandler: (() -> Void)?
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var targetsByHotKeyID: [UInt32: MacHotKeyTarget] = [:]

    private(set) var lastRegistrationError: String?

    func configure(action: @escaping (MacHotKeyTarget) -> Void) {
        self.action = action
        installEventHandlerIfNeeded()
        reloadRegistration()
    }

    func reloadRegistration() {
        unregisterHotKeys()
        lastRegistrationError = nil

        let enabledPresetIDs = Set(
            CapturePresetStore.loadFlows()
                .filter(\.isEnabled)
                .map(\.id)
        )
        let bindings = MacHotKeyStore.configuredBindings().filter { binding in
            switch binding.target {
            case .quickCapture, .transcriptionOnly, .selectedPreset:
                true
            case .preset(let presetID):
                enabledPresetIDs.contains(presetID)
            }
        }
        var errors: [String] = []

        for (index, binding) in bindings.enumerated() {
            let modifiers = binding.shortcut.carbonModifiers
            guard modifiers != 0 else { continue }

            let id = UInt32(index + 1)
            let hotKeyID = EventHotKeyID(signature: macHotKeySignature, id: id)
            var newHotKeyRef: EventHotKeyRef?
            let status = RegisterEventHotKey(
                binding.shortcut.keyCode,
                modifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &newHotKeyRef
            )

            if status == noErr, let newHotKeyRef {
                hotKeyRefs.append(newHotKeyRef)
                targetsByHotKeyID[id] = binding.target
                KeyboardDebugLog.shared.log(
                    "[MacHotKey] Registered \(binding.target.id): \(binding.shortcut.displayString)"
                )
            } else {
                errors.append(String(localized: "Could not register \(binding.shortcut.displayString). Try a different shortcut. (OSStatus \(status))"))
                KeyboardDebugLog.shared.log(
                    "[MacHotKey] ❌ RegisterEventHotKey failed for \(binding.target.id): \(status)"
                )
            }
        }
        lastRegistrationError = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    #if DEBUG
    static let debugOpenQuickCaptureArgument = "--debug-open-quick-capture"

    /// `--debug-open-quick-capture`: drives the registered ⌥Space Carbon
    /// hotkey's own press/release handlers (the path a real key event takes
    /// after `macHotKeyHandler`) once the main scene is ready, and records
    /// whether RegisterEventHotKey succeeded in keyboard_debug.log.
    func debugSimulateQuickCaptureIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains(Self.debugOpenQuickCaptureArgument) else { return }
        let id = targetsByHotKeyID.first { $0.value == .quickCapture }?.key
        KeyboardDebugLog.shared.log(
            "[MacHotKey] debug: quickCapture registered=\(id != nil) id=\(id.map(String.init) ?? "nil") error=\(lastRegistrationError ?? "none")"
        )
        guard let id else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            handleHotKeyPressed(id: id)
            try? await Task.sleep(for: .milliseconds(60))
            handleHotKeyReleased(id: id)
            KeyboardDebugLog.shared.log(
                "[MacHotKey] debug: released; panel visible=\(MacQuickCapturePanelController.shared.isVisible)"
            )
            guard ProcessInfo.processInfo.arguments.contains("--debug-quick-capture-esc") else { return }
            // Queue a real esc key-down through the app's event loop so the
            // panel's local key monitor handles it as it would a keypress.
            try? await Task.sleep(for: .seconds(3))
            if let panel = NSApp.keyWindow,
               let esc = NSEvent.keyEvent(
                   with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                   windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
                   charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53
               ) {
                NSApp.postEvent(esc, atStart: false)
            }
            try? await Task.sleep(for: .milliseconds(500))
            KeyboardDebugLog.shared.log(
                "[MacHotKey] debug: after esc; panel visible=\(MacQuickCapturePanelController.shared.isVisible)"
            )
        }
    }
    #endif

    func handleHotKeyPressed(id: UInt32) {
        guard let target = targetsByHotKeyID[id] else { return }
        KeyboardDebugLog.shared.log("[MacHotKey] Hotkey pressed for \(target.id)")
        if target == .quickCapture {
            quickCapturePressHandler?()
            return
        }
        action?(target)
    }

    func handleHotKeyReleased(id: UInt32) {
        guard targetsByHotKeyID[id] == .quickCapture else { return }
        quickCaptureReleaseHandler?()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let handler: EventHandlerUPP = macHotKeyHandler
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            eventTypes.count,
            &eventTypes,
            nil,
            &eventHandlerRef
        )
        if status != noErr {
            lastRegistrationError = String(localized: "Could not install Vox.md hotkey listener. (OSStatus \(status))")
            KeyboardDebugLog.shared.log("[MacHotKey] ❌ InstallEventHandler failed: \(status)")
        }
    }

    private func unregisterHotKeys() {
        for hotKeyRef in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        targetsByHotKeyID.removeAll()
    }
}

private struct MacMenuBarMenu: View {
    @Environment(ModelManager.self) private var modelManager
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(TranscriptStore.self) private var transcriptStore

    @Bindable var recorder: MacRecorder
    @Bindable var quickCaptureViewModel: QuickCaptureViewModel
    let windowCoordinator: MacWindowCoordinator
    @AppStorage(CapturePresetStore.selectedFlowIdKey, store: AppConstants.sharedDefaults)
    private var selectedFlowId = CapturePresetStore.generalId

    var body: some View {
        Text(statusTitle)
            .onAppear {
                usageTracker.reload()
                transcriptStore.reload()
            }

        if recorder.isRecording {
            Text("Recording: \(formatMenuDuration(recorder.recordingDuration))")
        } else if let error = recorder.lastError, !error.isEmpty {
            Text("Error: \(error)")
        } else if let modelName = modelManager.selectedModel?.name {
            Text("Model: \(modelName)")
        } else {
            Text("No model selected")
        }

        Divider()

        if recorder.isRecording {
            Button {
                recorder.stopAndTranscribe(modelManager: modelManager, flowId: selectedFlowId)
            } label: {
                Label("Stop + Transcribe", systemImage: "stop.fill")
            }
        } else {
            Button {
                beginRecording()
            } label: {
                Label(recordButtonTitle, systemImage: usageTracker.isAtLimit ? "lock.fill" : "mic.fill")
            }
        }

        Button {
            chooseImport()
        } label: {
            Label("Import Audio…", systemImage: "waveform")
        }
        .disabled(recorder.isRecording || usageTracker.isAtLimit)

        if let result = recorder.lastTranscriptionResult, !result.isEmpty {
            Button {
                copyToPasteboard(result)
            } label: {
                Label("Copy Last Transcript", systemImage: "doc.on.doc")
            }
        }
        if let reason = recorder.lastSpeakerDiarizationSkipReason {
            Label(reason.displayText, systemImage: "exclamationmark.triangle")
                .foregroundStyle(MacBrand.attention)
        }

        if let exportURL = recorder.lastExportURL {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([exportURL])
            } label: {
                Label("Reveal Last Export", systemImage: "folder")
            }
        }

        Divider()

        Picker("Route", selection: $selectedFlowId) {
            ForEach(enabledFlows) { flow in
                Label(flow.visibleName ?? String(localized: "Icon-only route"), systemImage: iconName(for: flow.symbolName))
                    .tag(flow.id)
                    .accessibilityLabel(flow.accessibilityName)
            }
        }
        .disabled(recorder.isRecording)

        Button {
            MacQuickCapturePanelController.shared.show()
        } label: {
            Label(
                MacHotKeyStore.quickCaptureDisplayString.map { String(localized: "Quick Capture (\($0))") }
                    ?? String(localized: "Quick Capture"),
                systemImage: "bolt.fill"
            )
        }

        Button {
            windowCoordinator.showMain(.navigate(.capture))
        } label: {
            Label("Show Capture", systemImage: "square.and.pencil")
        }
        .keyboardShortcut("0")

        Button {
            windowCoordinator.showMain(.navigate(.library))
        } label: {
            Label("Show Library", systemImage: "books.vertical")
        }

        Button {
            if let url = AppConstants.sharedContainerURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        } label: {
            Label("Reveal Data Folder", systemImage: "externaldrive")
        }

        Divider()

        Button("Quit Vox.md") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var enabledFlows: [CapturePreset] {
        let enabled = CapturePresetStore.loadFlows().filter(\.isEnabled)
        return enabled.isEmpty ? CapturePresetStore.defaultFlows : enabled
    }

    private var statusTitle: String {
        if recorder.isRecording { return String(localized: "Vox.md — Recording") }
        if recorder.isTranscribing { return String(localized: "Vox.md — Transcribing") }
        if recorder.isExporting { return String(localized: "Vox.md — Finishing Export") }
        return String(localized: "Vox.md — Ready")
    }

    private var recordButtonTitle: String {
        if usageTracker.isAtLimit { return String(localized: "Unlock to Record") }
        return String(localized: "Start Recording")
    }

    private func beginRecording() {
        guard !usageTracker.isAtLimit else {
            recorder.needsUnlock = true
            windowCoordinator.showMain(.navigate(.capture))
            return
        }

        Task { @MainActor in
            await quickCaptureViewModel.load()
            guard let operation = quickCaptureViewModel.beginCaptureRouteOperation() else {
                windowCoordinator.showMain(.navigate(.capture))
                return
            }
            defer { quickCaptureViewModel.endCaptureRouteOperation(operation) }
            let flowID = selectedFlowId
            let granted = await AudioRecorder.requestMicrophonePermission()
            guard !Task.isCancelled, !recorder.ownsCaptureRoute,
                  CapturePresetStore.loadFlows().contains(where: { $0.id == flowID && $0.isEnabled }) else { return }
            guard granted else {
                recorder.lastError = String(localized: "Could not access the microphone. Check macOS Privacy & Security settings.")
                windowCoordinator.showMain(.navigate(.capture))
                return
            }
            recorder.startRecording(modelManager: modelManager, flowId: flowID)
        }
    }

    private func chooseImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            let flowID = selectedFlowId
            Task { @MainActor in
                await quickCaptureViewModel.load()
                guard quickCaptureViewModel.requireCaptureRouteAvailable(),
                      CapturePresetStore.loadFlows().contains(where: { $0.id == flowID && $0.isEnabled }) else {
                    windowCoordinator.showMain(.navigate(.capture))
                    return
                }
                recorder.importAudioFile(from: url, modelManager: modelManager, flowId: flowID)
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func iconName(for symbolName: String) -> String {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "questionmark.square" : trimmed
    }

    private func formatMenuDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

#if DEBUG
/// `--debug-seed-signal-fixtures`: DEBUG-only visual-QA data for the Signal
/// boards. It writes four routes (Meeting Notes, Inbox, Journal, Tasks) whose
/// destinations live in this app's own sandbox container (no folder picker
/// needed), three delivered Library records, and one busy-file entry so the
/// Activity "Needs you" card renders. Run it only against an isolated debug
/// container (for example an ad-hoc build with a separate bundle ID).
@MainActor
enum MacDebugSignalFixtures {
    static let argument = "--debug-seed-signal-fixtures"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(argument)
    }

    /// Appends to `<sandbox tmp>/signal-fixtures.log` so a QA run can check
    /// the seed without Console.
    private static func trace(_ message: String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("signal-fixtures.log")
        let line = Data("\(Date()) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile(); handle.write(line); try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }

    private static let busyRequestID = UUID(uuidString: "00000000-0000-4000-8000-0000000000B5")!

    static func seedIfRequested(viewModel: QuickCaptureViewModel) async {
        trace("start")
        guard isRequested, let defaults = AppConstants.sharedDefaults else { return }
        await viewModel.load()
        trace("loaded profiles=\(viewModel.voxProfiles.count)")

        let routes: [(id: String, name: String, path: String, heading: String?)] = [
            ("debug-meeting-notes", "Meeting Notes", "Meetings/{date}.md", "Notes"),
            ("debug-inbox", "Inbox", "Inbox/Inbox.md", nil),
            ("debug-journal", "Journal", "Journal/{period}.md", nil),
            ("debug-tasks", "Tasks", "Tasks.md", "Today"),
        ]
        let existing = CapturePresetStore.loadFlows(defaults: defaults)
        if !existing.contains(where: { $0.id == routes[0].id }) {
            let presets = routes.map { route -> CapturePreset in
                var preset = CapturePresetStore.makeCustomFlow()
                preset.id = route.id
                preset.name = route.name
                return preset
            }
            // Keep the built-in Default route but hide it, so the sidebar
            // shows exactly the four board routes.
            let builtIns = existing.map { flow -> CapturePreset in
                var flow = flow
                flow.isEnabled = false
                return flow
            }
            CapturePresetStore.saveFlows(presets + builtIns, defaults: defaults)
            viewModel.refreshVoxProfiles()

            let vault = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Vox Notes", isDirectory: true)
            try? FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
            let bookmark = (try? vault.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
                ?? (try? vault.bookmarkData()) ?? Data()

            for route in routes {
                // The main window's own cold load briefly holds the route; wait for it.
                for _ in 0..<50 where !viewModel.canChangeCaptureRoute {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                guard viewModel.selectVox(route.id) || viewModel.selectedVoxProfile?.id == route.id else {
                    trace("could not select \(route.name)")
                    continue
                }
                let target: CaptureNoteTarget = route.path.contains("{period}")
                    ? .rollingNote(pathTemplate: route.path, period: .weekly)
                    : route.path.contains("{date}")
                        ? .newNote(pathTemplate: route.path)
                        : .existingNote(relativePath: route.path)
                let placement: CapturePlacement = route.heading.map {
                    .beneathHeading(
                        CaptureHeadingSelector(title: $0, level: 2),
                        missingHeadingBehavior: .create,
                        headingPosition: .bottom
                    )
                } ?? .append
                let destination = CaptureDestination(
                    name: route.name,
                    rootBookmark: bookmark,
                    rootName: "Vox Notes",
                    noteTarget: target,
                    placement: placement,
                    attachmentsFolderName: "attachments"
                )
                do {
                    try await viewModel.saveSelectedPresetDestination(destination)
                } catch {
                    trace("route \(route.name) failed: \(error)")
                }
            }
            trace("seeded \(viewModel.voxProfiles.count) routes")
            _ = viewModel.selectVox(routes[0].id)
            viewModel.errorMessage = nil
        }
        if viewModel.draft.text.isEmpty {
            viewModel.draft.text = "# Project sync\n- [ ] Review final designs\n- [ ] Loop in design before Friday\n\nDecision: ship routing first and keep the composer as calm as it is now. The keyboard and Watch get the same route picker.\n"
            viewModel.scheduleDraftSave()
        }

        if let historyURL = AppConstants.captureDirectoryURL?
            .appendingPathComponent(AppConstants.captureHistoryFilename) {
            let store = CaptureHistoryStore(fileURL: historyURL)
            let destinationsByName = Dictionary(
                viewModel.destinations.map { ($0.name, $0.id) },
                uniquingKeysWith: { first, _ in first }
            )
            let now = Date()
            let seeds: [(String, String, String, CaptureSource, TimeInterval)] = [
                ("debug-meeting-notes", "Meeting Notes", "Meetings/2026-11-01.md", .app, 40 * 60),
                ("debug-inbox", "Inbox", "Inbox/Book recs from Sam.md", .keyboard, 2 * 3_600),
                ("debug-journal", "Journal", "Journal/2026-W44.md", .watch, 4 * 3_600),
            ]
            for (index, seed) in seeds.enumerated() {
                let id = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index + 1))!
                if let record = try? CaptureHistoryRecord(
                    requestID: id,
                    createdAt: now.addingTimeInterval(-seed.4),
                    deliveredAt: now.addingTimeInterval(-seed.4 + 4),
                    source: seed.3,
                    outcome: .delivered,
                    destinationID: destinationsByName[seed.1] ?? UUID(),
                    destinationName: seed.1,
                    voxID: seed.0,
                    voxName: seed.1,
                    relativeNotePath: seed.2,
                    attachmentCount: 0
                ) {
                    _ = try? await store.upsert(record)
                }
            }
            if let busy = try? CaptureHistoryRecord(
                requestID: busyRequestID,
                createdAt: now.addingTimeInterval(-15 * 60),
                deliveredAt: nil,
                source: .mac,
                outcome: .failed,
                destinationID: destinationsByName["Tasks"] ?? UUID(),
                destinationName: "Tasks",
                voxID: "debug-tasks",
                voxName: "Tasks",
                relativeNotePath: "Tasks.md",
                attachmentCount: 0,
                failureCategory: .fileWrite
            ) {
                _ = try? await store.upsert(busy)
            }
            await viewModel.refreshHistory()
        }

        if ProcessInfo.processInfo.arguments.contains("--debug-dump-menus") {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(10))
                @MainActor func dump(_ menu: NSMenu, _ depth: Int) {
                    // Let SwiftUI refresh the items as if the menu were opening.
                    menu.delegate?.menuNeedsUpdate?(menu)
                    menu.update()
                    for item in menu.items where !item.isSeparatorItem {
                        let key = item.keyEquivalent.isEmpty ? "" : " [\(item.keyEquivalentModifierMask.rawValue >> 16):\(item.keyEquivalent)]"
                        trace(String(repeating: "  ", count: depth) + (item.state == .on ? "✓ " : "") + item.title + key + (item.isEnabled ? "" : " (disabled)"))
                        if let submenu = item.submenu { dump(submenu, depth + 1) }
                    }
                }
                if let menu = NSApp.mainMenu { dump(menu, 0) }
            }
        }
        // `--debug-perform-menu=Format>Internal link`: invokes a menu bar
        // item by title path, as a click would, for menu-command QA.
        if let path = ProcessInfo.processInfo.arguments
            .first(where: { $0.hasPrefix("--debug-perform-menu=") })?
            .dropFirst("--debug-perform-menu=".count) {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(8))
                var menu = NSApp.mainMenu
                let titles = path.split(separator: ">").map(String.init)
                for (depth, title) in titles.enumerated() {
                    guard let current = menu else { break }
                    current.delegate?.menuNeedsUpdate?(current)
                    current.update()
                    guard let index = current.items.firstIndex(where: { $0.title == title }) else {
                        trace("menu item not found: \(title)"); break
                    }
                    if depth == titles.count - 1 {
                        trace("perform \(path) enabled=\(current.items[index].isEnabled)")
                        current.performActionForItem(at: index)
                    } else {
                        menu = current.items[index].submenu
                    }
                }
            }
        }

        CaptureFileBusyMonitor.shared.record(CaptureFileBusyEntry(
            requestID: busyRequestID,
            fileName: "Tasks.md",
            relativeNotePath: "Tasks.md",
            reason: .unsavedChanges,
            markdown: "- [ ] Pricing page monthly toggle\n- [ ] Email Dana\n- [ ] Book design crit"
        ))
    }
}
#endif
