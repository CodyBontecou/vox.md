import AppKit
import SwiftUI
import VoxboardShared

/// Floating Quick Capture window (Signal MacQuickCapture).
///
/// The global Quick Capture shortcut (⌥Space by default) opens or closes the
/// panel on a press; holding it records push-to-talk into the current draft
/// and stops on release. The panel edits the same durable draft as the main
/// Capture workspace, so nothing typed here is lost if the main window opens.
@MainActor
final class MacQuickCapturePanelController {
    static let shared = MacQuickCapturePanelController()
    /// Holding the shortcut longer than this starts push-to-talk.
    static let holdThreshold: Duration = .milliseconds(320)

    private var panel: MacQuickCapturePanel?
    private var recorder: MacRecorder?
    private var viewModel: QuickCaptureViewModel?
    private var modelManager: ModelManager?
    private var usageTracker: UsageTracker?
    private var transcriptStore: TranscriptStore?
    private var storeManager: MacStoreManager?
    private var windowCoordinator: MacWindowCoordinator?
    private var holdTask: Task<Void, Never>?
    private var isKeyDown = false
    private var isPushToTalkActive = false
    private var previousApplication: NSRunningApplication?

    var isVisible: Bool { panel?.isVisible == true }
    var isKeyWindow: Bool { panel?.isKeyWindow == true }
    private var escapeMonitor: Any?

    func configure(
        recorder: MacRecorder,
        viewModel: QuickCaptureViewModel,
        modelManager: ModelManager,
        usageTracker: UsageTracker,
        transcriptStore: TranscriptStore,
        storeManager: MacStoreManager,
        windowCoordinator: MacWindowCoordinator
    ) {
        self.recorder = recorder
        self.viewModel = viewModel
        self.modelManager = modelManager
        self.usageTracker = usageTracker
        self.transcriptStore = transcriptStore
        self.storeManager = storeManager
        self.windowCoordinator = windowCoordinator
        let center = MacGlobalHotKeyCenter.shared
        center.quickCapturePressHandler = { [weak self] in self?.hotKeyPressed() }
        center.quickCaptureReleaseHandler = { [weak self] in self?.hotKeyReleased() }
    }

    // MARK: Hot key

    private func hotKeyPressed() {
        guard !isKeyDown else { return }
        isKeyDown = true
        holdTask?.cancel()
        holdTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.holdThreshold)
            guard let self, !Task.isCancelled, self.isKeyDown else { return }
            self.beginPushToTalk()
        }
    }

    private func hotKeyReleased() {
        isKeyDown = false
        holdTask?.cancel()
        holdTask = nil
        if isPushToTalkActive {
            endPushToTalk()
        } else {
            toggle()
        }
    }

    // MARK: Panel

    func toggle() {
        if isVisible { close() } else { show() }
    }

    func show() {
        #if DEBUG
        KeyboardDebugLog.shared.log("[MacQuickCapture] show requested configured=\(viewModel != nil && recorder != nil)")
        #endif
        guard let viewModel, let recorder else { return }
        if panel == nil { panel = makePanel(viewModel: viewModel, recorder: recorder) }
        guard let panel else { return }
        if !NSApp.isActive {
            previousApplication = NSWorkspace.shared.frontmostApplication
        }
        position(panel)
        Task { await viewModel.load() }
        installEscapeMonitorIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .macQuickCaptureFocus, object: nil)
        #if DEBUG
        KeyboardDebugLog.shared.log("[MacQuickCapture] shown visible=\(panel.isVisible) key=\(panel.isKeyWindow) frame=\(panel.frame)")
        #endif
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        #if DEBUG
        KeyboardDebugLog.shared.log("[MacQuickCapture] closed")
        #endif
        Task { await viewModel?.saveDraftNow() }
        panel.orderOut(nil)
        if let previousApplication, previousApplication != NSRunningApplication.current {
            previousApplication.activate()
        }
        previousApplication = nil
    }

    /// NSTextView maps esc to completion, so close the panel before the text
    /// view sees it.
    private func installEscapeMonitorIfNeeded() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53,
                  let self,
                  let panel = self.panel,
                  panel.isKeyWindow,
                  panel.attachedSheet == nil else { return event }
            self.close()
            return nil
        }
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { panel.center(); return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + frame.height * 0.62 - size.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func makePanel(viewModel: QuickCaptureViewModel, recorder: MacRecorder) -> MacQuickCapturePanel {
        let panel = MacQuickCapturePanel(
            contentRect: NSRect(x: 0, y: 0, width: 472, height: 512),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        // .canJoinAllSpaces and .moveToActiveSpace are mutually exclusive:
        // together NSWindow throws NSInternalInconsistencyException and the
        // panel never appears. Joining all Spaces already shows it on the
        // active one.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.onCancel = { [weak self] in self?.close() }

        var root = AnyView(
            MacQuickCaptureView(
                viewModel: viewModel,
                recorder: recorder,
                onClose: { [weak self] in self?.close() },
                onToggleRecording: { [weak self] in self?.toggleRecordingFromPanel() },
                onOpenMain: { [weak self] in
                    self?.close()
                    self?.windowCoordinator?.showMain(.navigate(.capture))
                }
            )
            .tint(MacBrand.tint)
        )
        if let modelManager { root = AnyView(root.environment(modelManager)) }
        if let usageTracker { root = AnyView(root.environment(usageTracker)) }
        if let transcriptStore { root = AnyView(root.environment(transcriptStore)) }
        if let storeManager { root = AnyView(root.environment(storeManager)) }
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(x: 0, y: 0, width: 472, height: 512)
        panel.contentView = hosting
        return panel
    }

    // MARK: Recording

    private func beginPushToTalk() {
        show()
        guard let recorder, !recorder.isRecording else { return }
        isPushToTalkActive = true
        startDraftRecording(pushToTalk: true)
    }

    private func endPushToTalk() {
        isPushToTalkActive = false
        stopRecording()
    }

    private func toggleRecordingFromPanel() {
        guard let recorder else { return }
        if recorder.isRecording { stopRecording() } else { startDraftRecording(pushToTalk: false) }
    }

    private func stopRecording() {
        guard let recorder, let modelManager, recorder.isRecording else { return }
        let flowID = viewModel?.draft.voxID ?? CapturePresetStore.selectedFlowId()
        recorder.stopAndTranscribe(modelManager: modelManager, flowId: flowID)
    }

    /// Records into the current draft: the transcript is appended where the
    /// person is typing and stays editable before Send.
    private func startDraftRecording(pushToTalk: Bool) {
        guard let recorder, let viewModel, let modelManager, let usageTracker else { return }
        guard !usageTracker.isAtLimit else {
            recorder.needsUnlock = true
            windowCoordinator?.showMain(.navigate(.capture))
            return
        }
        Task { @MainActor in
            await viewModel.load()
            guard viewModel.requireCaptureRouteAvailable(),
                  let operation = viewModel.beginCaptureRouteOperation() else { return }
            defer { viewModel.endCaptureRouteOperation(operation) }
            let granted = await AudioRecorder.requestMicrophonePermission()
            guard !Task.isCancelled, !recorder.ownsCaptureRoute else { return }
            guard granted else {
                recorder.lastError = String(localized: "Enable microphone access in System Settings to record audio.")
                return
            }
            // A release that landed while permission was pending ends the take.
            if pushToTalk, !isPushToTalkActive { return }
            let flowID = viewModel.draft.voxID ?? CapturePresetStore.selectedFlowId()
            recorder.startRecording(
                modelManager: modelManager,
                flowId: flowID,
                completionMode: .captureDraft(attachAudio: false),
                draftRequestID: viewModel.draft.requestID
            )
        }
    }
}

extension Notification.Name {
    static let macQuickCaptureFocus = Notification.Name("VoxboardMacQuickCaptureFocus")
}

/// Borderless panel that can still become key so the person can type.
final class MacQuickCapturePanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

// MARK: - View

struct MacQuickCaptureView: View {
    @Bindable var viewModel: QuickCaptureViewModel
    @Bindable var recorder: MacRecorder
    let onClose: () -> Void
    let onToggleRecording: () -> Void
    let onOpenMain: () -> Void

    @Environment(UsageTracker.self) private var usageTracker
    @State private var editorSelection = NSRange(location: 0, length: 0)
    @State private var isTextFocused = false
    @State private var editorController = MacMarkdownComposerController()

    /// Signal MacQuickCapture panel surface: #FBFBF9 in light mode, the
    /// Signal gray-100 surface in dark mode.
    private static let panelBackground = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(Geist.Palette.gray100)
        }
        return NSColor(srgbRed: 0xFB / 255, green: 0xFB / 255, blue: 0xF9 / 255, alpha: 1)
    })

    /// Text on the selected (ink) chip: white in light; the dark ground in
    /// dark, where the ink pill turns light.
    private static let onInk = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x0B / 255, green: 0x0B / 255, blue: 0x0B / 255, alpha: 1)
            : .white
    })

    private var routes: [CapturePresetProfile] { MacRouteCatalog.enabledRoutes(in: viewModel) }

    var body: some View {
        VStack(spacing: 0) {
            routeTabs
            VStack(alignment: .leading, spacing: 12) {
                editor
                recordingBar
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 18)
            footer
        }
        .background(
            Self.panelBackground,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(width: 472, height: 512)
        .onAppear { focusEditor() }
        .onReceive(NotificationCenter.default.publisher(for: .macQuickCaptureFocus)) { _ in
            focusEditor()
        }
        .onChange(of: viewModel.draft.text) { _, _ in
            if !viewModel.hasLiveRecordedTranscriptPreview { viewModel.scheduleDraftSave() }
        }
        .onChange(of: viewModel.lastReceipt) { _, receipt in
            guard receipt != nil else { return }
            MacSoundEffects.play(.captureSent)
            onClose()
        }
        .alert(
            "Switch Route?",
            isPresented: Binding(get: { viewModel.pendingPresetSwitch != nil }, set: { _ in }),
            presenting: viewModel.pendingPresetSwitch
        ) { pending in
            Button("Switch Route") { Task { _ = await viewModel.confirmPresetSwitch(id: pending.id) } }
            Button("Cancel", role: .cancel) { viewModel.cancelPresetSwitch(id: pending.id) }
        } message: { pending in
            Text("Use \(pending.presetName) for this draft? Your text and attachments will be kept; one-off routing will reset.")
        }
        // esc closes; ⌘↩ sends (the Send button owns that shortcut).
        .background {
            Button("Close", action: onClose)
                .keyboardShortcut(.cancelAction)
                .hidden()
        }
    }

    private var routeTabs: some View {
        // MacQuickCapture: chips keep their full names and wrap (flex-wrap)
        // instead of truncating the selected, semibold chip.
        ActivitySignalFlowLayout(spacing: 6) {
            ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                let isSelected = route.id == viewModel.selectedVoxProfile?.id
                Button {
                    MacRouteCatalog.select(route, in: viewModel)
                } label: {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(isSelected ? Self.onInk : dotColor(index))
                            .frame(width: 8, height: 8)
                        Text(MacRouteCatalog.displayName(route))
                            .font(isSelected ? Geist.label(.footnote) : Geist.body(.footnote))
                            .lineLimit(1)
                        if let key = MacRouteCatalog.shortcutLabel(forIndex: index) {
                            Text(verbatim: key)
                                .font(Geist.mono(size: 10.5, relativeTo: .caption2))
                                .opacity(0.7)
                        }
                    }
                    // Selected chip is an ink pill: white on #121212 in light,
                    // near-black on the light ink pill in dark.
                    .foregroundStyle(isSelected ? Self.onInk : Geist.text)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(isSelected ? Geist.text : Geist.card, in: Capsule())
                    .overlay { Capsule().stroke(isSelected ? Geist.text : Geist.border, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .modifier(MacRouteKeyModifier(index: index))
                .disabled(!viewModel.canChangeCaptureRoute)
                .fixedSize()
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                .accessibilityLabel(route.accessibilityName)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Route")
    }

    private func dotColor(_ index: Int) -> Color {
        switch index {
        case 0: MacBrand.accent
        case 1: Geist.text
        default: Geist.Palette.gray600
        }
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if viewModel.draft.text.isEmpty {
                Text("Type, or hold \(MacHotKeyStore.quickCaptureDisplayString ?? "⌥Space") to talk…")
                    .font(.custom("Geist-Regular", size: 20))
                    .foregroundStyle(Geist.faint)
                    .padding(.leading, 5)
                    .allowsHitTesting(false)
            }
            // Same live Markdown styling as the workspace, with the panel's
            // muted "- [ ]" markers.
            MacMarkdownComposerTextView(
                text: $viewModel.draft.text,
                selection: $editorSelection,
                isFocused: $isTextFocused,
                controller: editorController,
                style: .quickCapture,
                textInset: NSSize(width: 0, height: 0),
                accessibilityLabel: String(localized: "Quick capture text"),
                accessibilityIdentifier: "mac_quick_capture_panel_text"
            )
        }
        .frame(maxHeight: .infinity)
    }

    private func focusEditor() {
        isTextFocused = true
        DispatchQueue.main.async { editorController.focus() }
    }

    private var recordingBar: some View {
        Button(action: onToggleRecording) {
            HStack(spacing: 10) {
                Circle()
                    .fill(recorder.isRecording ? MacBrand.recording : Geist.Palette.gray700)
                    .frame(width: 8, height: 8)
                Text(verbatim: formatTimer(recorder.isRecording ? recorder.recordingDuration : 0))
                    .font(Geist.mono(size: 12, relativeTo: .caption))
                    .monospacedDigit()
                MacWaveformBars(levels: recorder.inputLevels, isLive: recorder.isRecording)
                    .frame(maxWidth: .infinity)
                Text(recorder.isTranscribing
                     ? String(localized: "transcribing…")
                     : recorder.isRecording
                        ? String(localized: "release to stop")
                        : String(localized: "hold \(MacHotKeyStore.quickCaptureDisplayString ?? "⌥Space")"))
                    .font(Geist.caption(.caption))
                    .foregroundStyle(Color(nsColor: NSColor(srgbRed: 0x9A / 255, green: 0x9A / 255, blue: 0x95 / 255, alpha: 1)))
            }
            .foregroundStyle(Color(nsColor: NSColor(srgbRed: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF1 / 255, alpha: 1)))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(nsColor: NSColor(srgbRed: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: 1)),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(recorder.isTranscribing || recorder.isExporting)
        .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: onOpenMain) {
                Text(verbatim: MacRouteCatalog.destinationSummary(for: viewModel))
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .help("Open in the Capture workspace")
            if let error = viewModel.errorMessage ?? recorder.lastError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(MacBrand.attention)
                    .help(error)
            }
            Text("esc to close")
                .font(Geist.caption(.caption))
                .foregroundStyle(Geist.muted)
            Button {
                send()
            } label: {
                Text(viewModel.isSubmitting ? String(localized: "Sending…") : String(localized: "Send ⌘↩"))
                    .font(Geist.label(.footnote))
                    .foregroundStyle(MacBrand.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .background(MacBrand.accent, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!viewModel.canSubmit || recorder.isRecording || recorder.isTranscribing || viewModel.isSubmitting)
            .opacity(viewModel.canSubmit ? 1 : 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .top) {
            Rectangle().fill(Geist.Palette.gray300).frame(height: 1)
        }
    }

    private func send() {
        guard viewModel.requireCaptureRouteAvailable() else { return }
        if viewModel.draft.deliveryKind == .standard && usageTracker.isCaptureAtLimit {
            onOpenMain()
            viewModel.needsCaptureUnlock = true
            return
        }
        // Library "FROM" shows "Mac · ⌥Space" for panel sends.
        viewModel.historySourceDetails[viewModel.draft.requestID] = CaptureHistoryRecord.macQuickCaptureSourceDetail
        Task { await viewModel.submit() }
    }

    private func formatTimer(_ duration: TimeInterval) -> String {
        String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60)
    }
}

/// ⌘1…⌘4 for the first four route chips.
struct MacRouteKeyModifier: ViewModifier {
    let index: Int

    func body(content: Content) -> some View {
        if index < 4 {
            content.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        } else {
            content
        }
    }
}
