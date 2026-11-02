import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoxboardShared

private enum MacCaptureInputMode: String, CaseIterable, Identifiable {
    case microphone
    case meeting
    var id: Self { self }
}

private enum MacCaptureRecordingMode: String, CaseIterable, Identifiable {
    case draft
    case preset

    var id: Self { self }
}

private enum MacCaptureInspectorTool: String, Identifiable {
    case route
    case webLink
    case internalLink
    case camera
    case sketch
    case dueDate

    var id: Self { self }
}

/// Capture-first Mac companion surface. It uses the same durable draft and
/// delivery model as iOS while adapting input, editing, and window behavior to
/// AppKit.
struct MacCaptureWorkspaceView: View {
    @Bindable var viewModel: QuickCaptureViewModel
    @Bindable var recorder: MacRecorder
    let windowToken: String
    let windowCoordinator: MacWindowCoordinator
    let openHistory: () -> Void
    let openSettings: () -> Void
    let openModels: () -> Void

    /// Fallback label while the capture coordinator has not resolved the
    /// picked application's display name.
    private var selectedMeetingApplicationFallback: String {
        String(localized: "selected application")
    }

    @Environment(ModelManager.self) private var modelManager
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(MacStoreManager.self) private var storeManager
    @Environment(TranscriptStore.self) private var transcriptStore
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    @State private var flows = CapturePresetStore.loadFlows()
    @State private var selectedInspectorTool: MacCaptureInspectorTool? = .route
    @State private var inputMode: MacCaptureInputMode = .microphone
    @State private var recordingMode: MacCaptureRecordingMode = .preset
    @State private var attachRecordingAudio = false
    @State private var showsPaywall = false
    @State private var showsInboxDiscardConfirmation = false
    @State private var showsClearDraftConfirmation = false
    @State private var linkText = ""
    @State private var internalLinkText = ""
    @State private var composerSelection = NSRange(location: 0, length: 0)
    @State private var composerIsFocused = false
    @State private var composerController = MacMarkdownComposerController()
    private var isProcessingAttachments: Bool {
        get { viewModel.isProcessingMedia }
        nonmutating set { viewModel.isProcessingMedia = newValue }
    }
    @State private var isDropTargeted = false
    @State private var showsSentToast = false
    @State private var lastRevealedReceiptURL: URL?
    @State private var showsAllShortcuts = false
    @State private var isFindingLocation = false
    @State private var locationService = CaptureLocationService()
    @State private var toolbarPreferences = CaptureToolbarPreferences.shared
    @State private var inspirationQuote = InspirationQuote.fallback
    @State private var hasLoadedInspirationQuote = false
    @State private var hasLoadedFirstNoteState = false
    @State private var firstNoteReceipt: CaptureReceipt?
    @AppStorage(CapturePreferenceKeys.firstNoteSaved, store: AppConstants.sharedDefaults)
    private var hasSavedFirstNote = false

    var body: some View {
        ZStack(alignment: .top) {
            Geist.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                if viewModel.locationDecision != nil {
                    locationDecisionBanner
                } else if viewModel.inboxLocationDecision != nil {
                    inboxLocationDecisionBanner
                }

                documentWorkspace
                    .layoutPriority(1)
            }
            .macUnderTitleBar()

            if let message = displayedError {
                errorBanner(message)
                    .padding(.horizontal, 24)
                    .padding(.top, 18)
                    .frame(maxWidth: 680)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
            }

            if showsSentToast {
                Label("Capture Sent", systemImage: "checkmark.circle.fill")
                    .font(Geist.label())
                    .foregroundStyle(Geist.Palette.background100)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .background(Geist.text)
                    .clipShape(Capsule(style: .continuous))
                    .padding(.top, 18)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .navigationTitle("Capture")
        // No window toolbar (MacWorkspace): its commands live in the menu bar.
        .focusedSceneValue(\.macCaptureMenuActions, menuActions)
        .task {
            await viewModel.load()
            guard !Task.isCancelled else { return }
            if viewModel.historyRecords.contains(where: { $0.outcome == .delivered }) {
                hasSavedFirstNote = true
            }
            hasLoadedFirstNoteState = true

            // `load()` owns the only destructive draft restoration. Do not let
            // coordinator-targeted actions consume or mutate that draft until
            // this window has finished the cold-load barrier.
            reloadFlows()
            transcriptStore.reload()
            if viewModel.needsCaptureUnlock {
                viewModel.needsCaptureUnlock = false
                showsPaywall = !usageTracker.hasUnlocked
            }
            windowCoordinator.captureWorkspaceReady(token: windowToken)
            if selectedInspectorTool == nil || selectedInspectorTool == .route {
                DispatchQueue.main.async { composerController.focus() }
            }

            await loadInspirationQuoteIfNeeded()
        }
        .onAppear {
            reloadFlows()
        }
        .onChange(of: viewModel.draft.text) { _, _ in
            if !viewModel.hasLiveRecordedTranscriptPreview {
                viewModel.scheduleDraftSave()
            }
        }
        .onChange(of: viewModel.lastReceipt) { _, receipt in
            guard let receipt else { return }
            if !MacQuickCapturePanelController.shared.isVisible {
                MacSoundEffects.play(.captureSent)
            }
            if !hasSavedFirstNote {
                firstNoteReceipt = receipt
                hasSavedFirstNote = true
            }
            usageTracker.reload()
            lastRevealedReceiptURL = receipt.noteURL
            Task { await presentSentToast() }
        }
        .onChange(of: viewModel.needsCaptureUnlock) { _, needsUnlock in
            guard needsUnlock else { return }
            viewModel.needsCaptureUnlock = false
            usageTracker.reload()
            showsPaywall = !usageTracker.hasUnlocked
        }
        .onChange(of: recorder.needsUnlock) { _, needsUnlock in
            guard needsUnlock else { return }
            recorder.needsUnlock = false
            showsPaywall = true
        }
        .inspector(isPresented: inspectorPresentationBinding) {
            captureInspector
                .macUnderTitleBar()
                // MacWorkspace: the route inspector is a 300–340pt column.
                .inspectorColumnWidth(min: 300, ideal: 340, max: 480)
        }
        .sheet(isPresented: $showsPaywall) {
            MacPaywallView(context: .captureLimit)
                .environment(usageTracker)
                .environment(storeManager)
        }
        .confirmationDialog(
            "Discard queued Capture?",
            isPresented: $showsInboxDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Capture", role: .destructive) {
                Task { await viewModel.discardInboxLocationRequest() }
            }
            Button("Keep Capture", role: .cancel) {}
        } message: {
            Text("This permanently removes the queued Capture that could not resolve its required location.")
        }
        .confirmationDialog(
            "Start a New Capture?",
            isPresented: $showsClearDraftConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Draft and Start New", role: .destructive) {
                clearCaptureDraft()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your unsent text and attachments will be removed from this Mac.")
        }
        .alert(
            "Switch Route?",
            isPresented: Binding(
                get: { viewModel.pendingPresetSwitch != nil },
                set: { _ in }
            ),
            presenting: viewModel.pendingPresetSwitch
        ) { pending in
            Button("Switch Route") {
                Task { await confirmPresetSwitch(id: pending.id) }
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelPresetSwitch(id: pending.id)
            }
        } message: { pending in
            Text("Use \(pending.presetName) for this draft? Your text and attachments will be kept; one-off routing will reset.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .macShowCapture)) { notification in
            guard let targetToken = notification.object as? String,
                  targetToken == windowToken else { return }
            consumeRequestedInput()
            if selectedInspectorTool == nil || selectedInspectorTool == .route {
                DispatchQueue.main.async { composerController.focus() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .macChooseCaptureFiles)) { notification in
            guard let targetToken = notification.object as? String,
                  targetToken == windowToken else { return }
            chooseFiles()
        }
        .onReceive(NotificationCenter.default.publisher(for: .macClearCaptureDraft)) { notification in
            guard let targetToken = notification.object as? String,
                  targetToken == windowToken else { return }
            requestNewCapture()
        }
        .onDisappear {
            windowCoordinator.captureWorkspaceNotReady(token: windowToken)
            Task { await viewModel.saveDraftNow() }
        }
    }

    private var documentWorkspace: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 0) {
                signalHeader
                quickActionRow

                if !isLocalizationScreenshot && hasLoadedFirstNoteState
                    && (!hasSavedFirstNote || firstNoteReceipt != nil) {
                    FirstNoteGuide(step: firstNoteStep, action: advanceFirstNote, dismiss: {
                        firstNoteReceipt = nil
                    })
                    .padding(.horizontal, 30)
                } else if viewModel.selectedDestination == nil && !isLocalizationScreenshot {
                    destinationSetupNotice
                }

                if recorder.isRecording || recorder.isTranscribing || recorder.isExporting {
                    recordingStatusBar
                    Divider()
                }

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    composer.frame(maxWidth: 720)
                    Spacer(minLength: 0)
                }
                .background(isDropTargeted ? MacBrand.subtleOrange : Geist.bg)
                .layoutPriority(1)

                if !stripPayloads.isEmpty {
                    Divider()
                    attachmentStrip
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Geist.bg)
        .onReceive(NotificationCenter.default.publisher(for: .macShowAllShortcuts)) { _ in
            showsAllShortcuts = true
        }
    }

    // MARK: Signal header and quick actions

    /// "Vault / folder / note.md · ## Heading" with Speak and Send.
    private var signalHeader: some View {
        HStack(spacing: 12) {
            Text(verbatim: MacRouteCatalog.breadcrumb(for: viewModel) ?? String(localized: "Choose a destination"))
                .font(Geist.mono(size: 12, relativeTo: .caption))
                .foregroundStyle(Geist.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(viewModel.resolvedDestinationPreview ?? "")
            Spacer(minLength: 8)
            // The breadcrumb truncates first; Speak and Send never do.
            headerAttachButton
            recordToolbarButton.fixedSize()
            sendToolbarButton.fixedSize()
        }
        .padding(.horizontal, 28)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Geist.border).frame(height: 1) }
    }

    private var quickActions: [CaptureToolbarAction] {
        toolbarPreferences.pinnedActions(
            forRoute: selectedFlow.id,
            surfaceDefault: CaptureToolbarAction.macWorkspaceDefault
        ).filter { !$0.isMedia }
    }

    private var quickActionRow: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(quickActions) { action in
                        quickActionChip(action)
                    }
                }
            }
            Button {
                showsAllShortcuts = true
            } label: {
                Text(verbatim: "All shortcuts ⌘/")
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            // A transient popover, not a sheet: the StoreKit paywall stays the
            // only modal surface over a Capture draft.
            .popover(isPresented: $showsAllShortcuts, arrowEdge: .bottom) {
                MacAllShortcutsSheet(
                    quickActions: quickActions,
                    routes: MacRouteCatalog.enabledRoutes(in: viewModel)
                )
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Geist.border).frame(height: 1) }
        .onReceive(NotificationCenter.default.publisher(for: CaptureQuickActionPins.didChangeNotification)) { _ in
            toolbarPreferences.reloadSharedPins()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick actions")
    }

    @ViewBuilder
    private func quickActionChip(_ action: CaptureToolbarAction) -> some View {
        let shortcut = MacQuickActionShortcut.shortcut(for: action)
        let help = [action.accessibilityLabel, MacQuickActionShortcut.displayString(for: action)]
            .compactMap { $0 }
            .joined(separator: " ")
        switch action {
        case .textCase:
            Menu {
                Button("Lowercase") { applyComposerCommand(.lowercase) }
                Button("Uppercase") { applyComposerCommand(.uppercase) }
                Button("Sentence case") { applyComposerCommand(.sentenceCase) }
                Button("Capitalize Words") { applyComposerCommand(.capitalizeWords) }
                Button("Slugify") { applyComposerCommand(.slugify) }
            } label: {
                chipLabel(action)
            } primaryAction: {
                applyComposerCommand(.sentenceCase)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .modifier(MacOptionalShortcut(shortcut: shortcut))
            .help(help)
            .accessibilityLabel(action.accessibilityLabel)
        case .formatMarkdown:
            Menu {
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { applyComposerCommand(.heading(level: level)) }
                }
                Button("Bold") { applyComposerCommand(.toggleBold) }
                Button("Italic") { applyComposerCommand(.toggleItalic) }
                Button("Checklist") { applyComposerCommand(.taskCheckbox) }
                Button("Bullet list") { applyComposerCommand(.bullet) }
            } label: {
                chipLabel(action)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .help(help)
            .accessibilityLabel(action.accessibilityLabel)
        default:
            Button {
                performQuickAction(action)
            } label: {
                chipLabel(action)
            }
            .buttonStyle(.plain)
            .modifier(MacOptionalShortcut(shortcut: shortcut))
            .disabled(action == .currentLocation && isFindingLocation)
            .help(help)
            .accessibilityLabel(action.accessibilityLabel)
        }
    }

    private func chipLabel(_ action: CaptureToolbarAction) -> some View {
        Text(verbatim: chipGlyph(action))
            .font(Geist.mono(size: 12.5, relativeTo: .caption))
            .foregroundStyle(Geist.text)
            .padding(.horizontal, 9)
            .frame(minWidth: 30, minHeight: 30)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Geist.border, lineWidth: 1)
            }
            .contentShape(Rectangle())
    }

    private func chipGlyph(_ action: CaptureToolbarAction) -> String {
        switch action {
        case .timestamp:
            return Self.chipTimeString(locale: locale, timeZone: timeZone)
        case .date:
            return captureDateString()
        default:
            return action.glyph
        }
    }

    /// "10:42" without a day period: HH:mm for 24-hour locales, else h:mm.
    static func chipTimeString(locale: Locale, timeZone: TimeZone, date: Date = Date()) -> String {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        let uses12Hour = template.contains("a") || template.contains("h") || template.contains("K")
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = uses12Hour ? "h:mm" : "HH:mm"
        return formatter.string(from: date)
    }

    private func performQuickAction(_ action: CaptureToolbarAction) {
        switch action {
        case .timestamp:
            applyComposerCommand(.replaceSelection(with: insertionFormatter.currentTimestamp()))
        case .date:
            applyComposerCommand(.replaceSelection(with: captureDateString()))
        case .checklist: applyComposerCommand(.taskCheckbox)
        case .bulletList: applyComposerCommand(.bullet)
        case .heading: applyComposerCommand(.heading(level: 2))
        case .bold: applyComposerCommand(.toggleBold)
        case .italic: applyComposerCommand(.toggleItalic)
        case .tag: applyComposerCommand(.insertHashtag)
        case .markdownLink: applyComposerCommand(.markdownLink())
        case .internalLink: selectInspectorTool(.internalLink)
        case .dueDate: selectInspectorTool(.dueDate)
        case .currentLocation: insertCurrentLocation()
        case .paste: pasteIntoCapture()
        case .undo: composerController.undo()
        case .textCase: applyComposerCommand(.sentenceCase)
        case .formatMarkdown: applyComposerCommand(.heading(level: 2))
        case .addMedia: chooseImages()
        case .addFiles: chooseFiles()
        case .scanDocument, .extractText: chooseScan()
        case .sketch: selectInspectorTool(.sketch)
        }
    }

    private func insertCurrentLocation() {
        guard !isFindingLocation else { return }
        isFindingLocation = true
        Task { @MainActor in
            defer { isFindingLocation = false }
            do {
                let location = try await locationService.requestCurrentLocation()
                let markdown = try insertionFormatter.googleMapsLink(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    label: location.label
                )
                applyComposerCommand(.replaceSelection(with: markdown))
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private var isCaptureActivityVisible: Bool {
        recorder.isRecording || recorder.isTranscribing || recorder.isExporting
            || viewModel.isSubmitting || viewModel.isResolvingLocation
            || recorder.isResolvingLocation || isProcessingAttachments
    }

    private var captureActivityLabel: String {
        if recorder.isRecording {
            return recorder.isRecordingPaused
                ? String(localized: "Paused \(formatDuration(recorder.recordingDuration))")
                : String(localized: "Recording \(formatDuration(recorder.recordingDuration))")
        }
        if recorder.isTranscribing { return String(localized: "Transcribing…") }
        if recorder.isExporting { return String(localized: "Finishing Export…") }
        if viewModel.isResolvingLocation || recorder.isResolvingLocation {
            return String(localized: "Finding Location…")
        }
        if viewModel.isDescribingImages { return String(localized: "Describing Images…") }
        if viewModel.isSubmitting { return String(localized: "Sending…") }
        return String(localized: "Adding Attachments…")
    }

    /// Signal header paperclip: the same items as the menu bar's Capture › Add.
    private var headerAttachButton: some View {
        Menu {
            attachmentMenuItems
        } label: {
            Image(systemName: isProcessingAttachments ? "hourglass" : "paperclip")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Geist.text)
                .frame(width: 36, height: 36)
                .background(Geist.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Geist.border, lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(isProcessingAttachments)
        .help("Add an attachment or link")
        .accessibilityLabel("Add an attachment or link")
        .accessibilityIdentifier("mac_capture_header_attach")
    }

    @ViewBuilder
    private var attachmentMenuItems: some View {
        Button("Images or Screenshots…", systemImage: "photo") { chooseImages() }
            Button("Take Photo…", systemImage: "camera") { selectInspectorTool(.camera) }
            Button("Import Scan or PDF…", systemImage: "doc.viewfinder") { chooseScan() }
            Button("Sketch…", systemImage: "pencil.tip") { selectInspectorTool(.sketch) }
            Button("Files…", systemImage: "paperclip") { chooseFiles() }
            Button("Audio Attachment…", systemImage: "waveform") { chooseAudio() }
            Button("Transcribe Audio or Video…", systemImage: "waveform.badge.plus") {
                importAudioForTranscription()
            }
            Divider()
            Button("Web Link…", systemImage: "link") { selectInspectorTool(.webLink) }
            Button("Paste", systemImage: "clipboard") { pasteIntoCapture() }
    }

    /// Menu-bar commands (Capture › Add to Capture, Format, …) for this
    /// window; they replace the old toolbar menus one for one.
    private var menuActions: MacCaptureMenuActions {
        MacCaptureMenuActions(
            attach: { item in
                switch item {
                case .images: chooseImages()
                case .photo: selectInspectorTool(.camera)
                case .scan: chooseScan()
                case .sketch: selectInspectorTool(.sketch)
                case .files: chooseFiles()
                case .audio: chooseAudio()
                case .transcribe: importAudioForTranscription()
                case .webLink: selectInspectorTool(.webLink)
                case .paste: pasteIntoCapture()
                }
            },
            canAttach: !isProcessingAttachments,
            format: { item in
                switch item {
                case .undo: composerController.undo()
                case .redo: composerController.redo()
                case .bold: applyComposerCommand(.toggleBold)
                case .italic: applyComposerCommand(.toggleItalic)
                case .hashtag: applyComposerCommand(.insertHashtag)
                case .heading(let level): applyComposerCommand(.heading(level: level))
                case .markdownLink: applyComposerCommand(.markdownLink())
                case .internalLink: selectInspectorTool(.internalLink)
                case .dueDate: selectInspectorTool(.dueDate)
                case .checklist: applyComposerCommand(.taskCheckbox)
                case .bullet: applyComposerCommand(.bullet)
                case .timestamp: applyComposerCommand(.replaceSelection(with: insertionFormatter.currentTimestamp()))
                case .date: applyComposerCommand(.replaceSelection(with: captureDateString()))
                case .lowercase: applyComposerCommand(.lowercase)
                case .uppercase: applyComposerCommand(.uppercase)
                case .sentenceCase: applyComposerCommand(.sentenceCase)
                case .capitalizeWords: applyComposerCommand(.capitalizeWords)
                case .slugify: applyComposerCommand(.slugify)
                }
            },
            isMeetingAudio: Binding(
                get: { inputMode == .meeting },
                set: { inputMode = $0 ? .meeting : .microphone }
            ),
            sendsAfterRecording: Binding(
                get: { recordingMode == .preset },
                set: { recordingMode = $0 ? .preset : .draft }
            ),
            attachesRecordingAudio: $attachRecordingAudio,
            isRecording: recorder.isRecording,
            revealLastCapture: lastRevealedReceiptURL.map { url in { revealInFinder(url) } },
            unlock: usageTracker.hasUnlocked ? nil : { showsPaywall = true },
            unlockTitle: usageTracker.isCaptureAtLimit
                ? String(localized: "Unlock Capture")
                : String(localized: "\(usageTracker.capturesRemaining) captures · \(String(format: "%.1f", usageTracker.minutesRemaining)) min"),
            toggleDetails: {
                if selectedInspectorTool == .route {
                    dismissInspectorTool()
                } else {
                    selectInspectorTool(.route)
                }
            },
            isShowingDetails: selectedInspectorTool == .route
        )
    }

    private var recordToolbarButton: some View {
        Button {
            if recorder.isRecording {
                recorder.stopAndTranscribe(modelManager: modelManager, flowId: selectedFlow.id)
            } else {
                startRecording()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: recorder.isRecording
                      ? "stop.fill"
                      : (inputMode == .meeting ? "person.2.wave.2" : "mic"))
                Text(recorder.isRecording ? String(localized: "Stop") : String(localized: "Speak"))
                if !recorder.isRecording, let shortcut = MacHotKeyStore.quickCaptureDisplayString {
                    Text(verbatim: shortcut)
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .foregroundStyle(Geist.Palette.gray600)
                }
            }
            .font(Geist.label(.footnote))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        // Signal: Speak is an ink pill; it turns red while recording.
        .tint(recorder.isRecording ? MacBrand.recording : Geist.text)
        .foregroundStyle(recorder.isRecording ? Color.white : Geist.Palette.background100)
        .accessibilityIdentifier("mac_capture_record")
    }

    private var sendToolbarButton: some View {
        Button {
            sendCapture()
        } label: {
            HStack(spacing: 6) {
                if captureAllowanceBlocked { Image(systemName: "lock.fill") }
                Text(
                    captureAllowanceBlocked
                        ? String(localized: "Unlock")
                        : (viewModel.isSubmitting
                           ? (viewModel.isDescribingImages
                              ? String(localized: "Describing images…")
                              : String(localized: "Sending…"))
                           : String(localized: "Send"))
                )
                .font(Geist.label(.footnote))
                Text(verbatim: "⌘↩")
                    .font(Geist.mono(size: 11, relativeTo: .caption))
                    .opacity(0.75)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(MacBrand.accent)
        .foregroundStyle(MacBrand.onAccent)
        .disabled(!viewModel.canSubmit || isProcessingAttachments || recorder.isRecording || recorder.isTranscribing)
        .keyboardShortcut(.return, modifiers: [.command])
        .accessibilityIdentifier("mac_quick_capture_submit")
    }

    private var destinationSetupNotice: some View {
        Button {
            selectInspectorTool(.route)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .foregroundStyle(.secondary)
                Text("Choose a destination to enable Send")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Choose…")
                    .foregroundStyle(.tint)
            }
            .font(Geist.label())
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Destination Not Configured. Choose where this Capture writes Markdown.")
        .accessibilityIdentifier("mac_capture_destination_banner")
    }

    private var firstNoteStep: FirstNoteGuide.Step {
        if let receipt = firstNoteReceipt { return .saved(file: receipt.noteURL.lastPathComponent) }
        if let destination = viewModel.selectedDestination { return .writeNote(folder: destination.rootName) }
        return .chooseFolder
    }

    private func advanceFirstNote() {
        if let receipt = firstNoteReceipt {
            NSWorkspace.shared.activateFileViewerSelecting([receipt.noteURL])
            firstNoteReceipt = nil
        } else if viewModel.selectedDestination == nil {
            selectInspectorTool(.route)
        } else {
            composerController.focus()
        }
    }

    private var locationDecisionBanner: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            Label("Location Unavailable", systemImage: "location.slash.fill")
                .font(Geist.label())
            Text("Vox.md could not get an origin-time location. Your Capture draft is preserved and remains editable.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Geist.Spacing.two) { locationDecisionActions }
                VStack(alignment: .leading, spacing: Geist.Spacing.two) { locationDecisionActions }
            }
        }
        .padding(.horizontal, Geist.Spacing.four)
        .padding(.vertical, Geist.Spacing.three)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacBrand.attentionSoft)
        .overlay(alignment: .bottom) { Rectangle().fill(Geist.border).frame(height: 1) }
        .accessibilityIdentifier("mac_capture_location_decision")
    }

    @ViewBuilder
    private var locationDecisionActions: some View {
        Button("Retry") {
            Task { await viewModel.retryUnavailableLocation() }
        }
        Button("Send Without Location") {
            Task { await viewModel.sendWithoutUnavailableLocation(alwaysForPreset: false) }
        }
        Button("Always Send Without for Route") {
            Task { await viewModel.sendWithoutUnavailableLocation(alwaysForPreset: true) }
        }
        Button("Cancel") {
            Task { await viewModel.cancelUnavailableLocation() }
        }
    }

    private var inboxLocationDecisionBanner: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.three) {
            Label(inboxLocationDecisionTitle, systemImage: "tray.full.fill")
                .font(Geist.label())
            Text(inboxLocationDecisionMessage)
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Geist.Spacing.two) { inboxLocationDecisionActions }
                VStack(alignment: .leading, spacing: Geist.Spacing.two) { inboxLocationDecisionActions }
            }
        }
        .padding(.horizontal, Geist.Spacing.four)
        .padding(.vertical, Geist.Spacing.three)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MacBrand.attentionSoft)
        .overlay(alignment: .bottom) { Rectangle().fill(Geist.border).frame(height: 1) }
        .accessibilityIdentifier("mac_capture_inbox_location_decision")
    }

    @ViewBuilder
    private var inboxLocationDecisionActions: some View {
        Button("Send Without Location") {
            Task { await viewModel.sendInboxRequestWithoutLocation() }
        }
        Button("Always Send Without for Route") {
            Task { await viewModel.sendInboxRequestWithoutLocation(alwaysForPreset: true) }
        }
        Button("Discard Capture", role: .destructive) {
            showsInboxDiscardConfirmation = true
        }
    }

    private var composer: some View {
        MacMarkdownComposerTextView(
            text: $viewModel.draft.text,
            selection: $composerSelection,
            isFocused: $composerIsFocused,
            controller: composerController,
            inlineAudio: inlineAudioAttachments,
            onRemoveInlineAudio: { id in removeInlineAudio(id: id) }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            isDropTargeted
                ? MacBrand.subtleOrange
                : Geist.bg
        )
        .overlay(alignment: .center) {
            if InspirationQuotePresentation.shouldShow(forDraftText: viewModel.draft.text),
               inlineAudioAttachments.isEmpty {
                emptyComposerPrompt
                    .allowsHitTesting(false)
            }
        }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous)
                    .stroke(MacBrand.accent, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                    .padding(8)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard !urls.isEmpty else { return false }
            Task { await stageURLs(urls) }
            return true
        } isTargeted: { isDropTargeted = $0 }
    }

    /// Staged audio shown as chips inside the document (Signal MacWorkspace).
    private var inlineAudioAttachments: [MacComposerInlineAudio] {
        guard let stagingURL = viewModel.sentCaptureUndoSourceDirectoryURL else { return [] }
        return viewModel.draft.additionalPayloads.compactMap { payload in
            guard case .audio(let asset, let transcript) = payload else { return nil }
            return MacComposerInlineAudio(
                id: asset.relativePath,
                url: stagingURL.appendingPathComponent(asset.relativePath),
                filename: asset.originalFilename,
                speakerCount: MacAudioAttachmentChip.speakerCount(in: transcript)
            )
        }
    }

    private var stripPayloads: [(offset: Int, element: CapturePayload)] {
        let inlineIDs = Set(inlineAudioAttachments.map(\.id))
        return viewModel.draft.additionalPayloads.enumerated().filter { _, payload in
            if case .audio(let asset, _) = payload { return !inlineIDs.contains(asset.relativePath) }
            return true
        }.map { ($0.offset, $0.element) }
    }

    private func removeInlineAudio(id: String) {
        guard let index = viewModel.draft.additionalPayloads.firstIndex(where: { payload in
            if case .audio(let asset, _) = payload { return asset.relativePath == id }
            return false
        }) else { return }
        Task { await viewModel.removePayload(at: index) }
    }

    private var emptyComposerPrompt: some View {
        VStack(spacing: 10) {
            Text(verbatim: "“\(inspirationQuote.text)”")
                .font(Geist.heading(.title2))
            Text(verbatim: "— \(inspirationQuote.author)")
                .font(Geist.mono(size: 12, relativeTo: .caption))
                .foregroundStyle(Geist.muted)
            Text("Type Markdown, dictate, paste, or drop files anywhere in this window.")
                .font(Geist.caption())
                .foregroundStyle(Geist.faint)
        }
        .foregroundStyle(Geist.muted)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 560)
        .padding(32)
    }

    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Geist.Spacing.two) {
                ForEach(stripPayloads, id: \.offset) { index, payload in
                    HStack(spacing: Geist.Spacing.two) {
                        Image(systemName: payloadIcon(payload))
                        Text(payloadLabel(payload))
                            .lineLimit(1)
                        Button {
                            Task { await viewModel.removePayload(at: index) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(payloadLabel(payload))")
                    }
                    .font(Geist.mono(size: 12, relativeTo: .caption))
                    .foregroundStyle(Geist.text)
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Geist.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Geist.border, lineWidth: 1)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 10)
        }
        .background(Geist.bg)
        .accessibilityLabel("Capture attachments")
    }

    private var recordingStatusBar: some View {
        HStack(spacing: Geist.Spacing.three) {
            Image(systemName: recorder.isRecording
                  ? (recorder.isRecordingPaused ? "pause.circle.fill" : "record.circle.fill")
                  : "waveform.badge.magnifyingglass")
                .foregroundStyle(recorder.isRecording ? MacBrand.recording : MacBrand.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(
                    recorder.isRecording
                        ? recorder.isRecordingPaused
                            ? "Paused \(formatDuration(recorder.recordingDuration))"
                            : "Recording \(formatDuration(recorder.recordingDuration))"
                        : recorder.isTranscribing
                            ? "Transcribing on this Mac"
                            : "Finishing the Capture export"
                )
                    .font(Geist.label())
                Text(recorder.isMeetingRecording
                     ? String(localized: "Capturing \(recorder.meetingCapture.selectedApplicationName ?? selectedMeetingApplicationFallback) with separate System and Mic audio.")
                     : recorder.isExporting
                     ? "The transcript is saved locally while its note and requested audio finish exporting."
                     : recordingMode == .draft
                         ? "The on-device transcript will be added to this durable draft."
                         : "The recording will be processed and sent with \(selectedFlow.accessibilityName).")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
            }
            Spacer()
            if recorder.isMeetingRecording {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 5) {
                        Text(String(localized: "System · \(recorder.meetingCapture.systemStatus)")).font(Geist.caption())
                        ProgressView(value: Double(recorder.meetingCapture.systemLevel)).frame(width: 70)
                    }
                    HStack(spacing: 5) {
                        Text(String(localized: "Mic · \(recorder.meetingCapture.microphoneStatus)")).font(Geist.caption())
                        ProgressView(value: Double(recorder.meetingCapture.microphoneLevel)).frame(width: 70)
                    }
                    if let warning = recorder.meetingCapture.warnings.last {
                        Text(warning)
                            .font(Geist.caption())
                            .foregroundStyle(MacBrand.attention)
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("System and microphone recording levels")
            }
            if recorder.isRecording {
                if !recorder.isMeetingRecording {
                    Button {
                        recorder.toggleRecordingPause()
                    } label: {
                        Label(
                            recorder.isRecordingPaused
                                ? String(localized: "Resume")
                                : String(localized: "Pause"),
                            systemImage: recorder.isRecordingPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
                    .fixedSize()
                    .accessibilityIdentifier("mac_capture_recording_pause")
                }
                Button {
                    recorder.stopAndTranscribe(modelManager: modelManager, flowId: selectedFlow.id)
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(GeistButtonStyle(variant: .destructive, size: .small))
                .fixedSize()
            } else if recorder.isTranscribing,
                      let progress = recorder.transcriptionProgress,
                      let fraction = progress.exactFractionCompleted,
                      let percent = progress.formattedWholePercentCompleted {
                VStack(alignment: .trailing, spacing: 3) {
                    ProgressView(value: fraction)
                        .frame(width: 110)
                    Text("\(percent) complete")
                        .font(Geist.mono(.caption2))
                        .foregroundStyle(Geist.muted)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Transcription \(percent) complete")
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.horizontal, Geist.Spacing.four)
        .padding(.vertical, Geist.Spacing.three)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, Geist.Spacing.three)
    }

    private var inspectorPresentationBinding: Binding<Bool> {
        Binding(
            get: { selectedInspectorTool != nil },
            set: { isPresented in
                if isPresented, selectedInspectorTool == nil {
                    selectInspectorTool(.route)
                } else if !isPresented {
                    dismissInspectorTool()
                }
            }
        )
    }

    @ViewBuilder
    private var captureInspector: some View {
        switch selectedInspectorTool {
        case .route:
            MacCaptureRouteInspector(
                viewModel: viewModel,
                onClose: { dismissInspectorTool() },
                onAddFiles: { chooseFiles() },
                onOpenModels: {
                    dismissInspectorTool(refocus: false)
                    openModels()
                }
            )
        case .webLink:
            MacCaptureTextInspectorView(
                title: "Capture Link",
                detail: "The link remains in the durable Capture draft until it is sent.",
                prompt: "https://example.com",
                actionTitle: "Add to Capture",
                text: $linkText,
                onClose: {
                    linkText = ""
                    dismissInspectorTool()
                },
                onSubmit: addLink
            )
        case .internalLink:
            MacCaptureTextInspectorView(
                title: "Internal Link",
                detail: "Enter a note name or vault-relative path. Vox.md inserts an Obsidian wiki link.",
                prompt: "Projects/Vox",
                actionTitle: "Insert Link",
                text: $internalLinkText,
                onClose: {
                    internalLinkText = ""
                    dismissInspectorTool()
                },
                onSubmit: insertInternalLink
            )
        case .camera:
            MacCameraCaptureView(
                onClose: { dismissInspectorTool() },
                onCapture: { imageData in
                    dismissInspectorTool(refocus: false)
                    stageCameraImage(imageData)
                }
            )
        case .sketch:
            MacSketchEditor(
                onClose: { dismissInspectorTool() },
                onSave: { drawingData, previewData in
                    dismissInspectorTool(refocus: false)
                    stageSketch(drawingData, previewData)
                }
            )
        case .dueDate:
            MacCaptureDueDateInspectorView(
                onClose: { dismissInspectorTool() },
                onInsert: { date, includesTime in
                    insertDueDate(date, includesTime)
                    dismissInspectorTool()
                }
            )
        case nil:
            EmptyView()
        }
    }

    private func selectInspectorTool(_ tool: MacCaptureInspectorTool) {
        if selectedInspectorTool == .route, tool != .route {
            Task { await viewModel.saveDraftNow() }
            reloadFlows()
        }
        composerController.dismissFocus()
        selectedInspectorTool = tool
    }

    private func dismissInspectorTool(refocus: Bool = true) {
        guard let dismissedTool = selectedInspectorTool else { return }
        selectedInspectorTool = nil
        if dismissedTool == .route {
            Task { await viewModel.saveDraftNow() }
            reloadFlows()
        }
        if refocus {
            DispatchQueue.main.async { composerController.focus() }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.one) {
            HStack(alignment: .top, spacing: Geist.Spacing.three) {
                if shouldOpenModelsFromError {
                    Button {
                        recorder.lastError = nil
                        openModels()
                    } label: {
                        HStack(alignment: .top, spacing: Geist.Spacing.three) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(MacBrand.attention)
                            Text(message)
                                .font(Geist.caption())
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(Geist.caption())
                                .foregroundStyle(Geist.muted)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help("Open Transcription Models")
                    .accessibilityHint("Opens Transcription Models to download the selected model or choose an existing copy.")
                    .accessibilityIdentifier("mac_error_open_models")
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(MacBrand.attention)
                    Text(message)
                        .font(Geist.caption())
                    Spacer()
                }
                Button {
                    if viewModel.errorMessage != nil {
                        viewModel.errorMessage = nil
                    } else {
                        recorder.lastError = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            if viewModel.failedInboxCount > 0 {
                Button("Retry queued captures") {
                    Task { await viewModel.retryFailedInbox() }
                }
                .font(Geist.caption())
                .padding(.leading, 28)
            }
            if viewModel.errorMessage == nil,
               let recoveryURL = recorder.lastRecoveryAudioURL {
                Button("Reveal preserved recording") {
                    NSWorkspace.shared.activateFileViewerSelecting([recoveryURL])
                }
                .font(Geist.caption())
                .padding(.leading, 28)
            }
        }
        .padding(Geist.Spacing.three)
        .foregroundStyle(Geist.text)
        .background(Geist.card)
        .overlay {
            RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous)
                .stroke(MacBrand.attentionBorder, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 12, y: 4)
    }

    private var shouldOpenModelsFromError: Bool {
        guard viewModel.errorMessage == nil,
              let message = recorder.lastError,
              !modelManager.isAutomaticSelection else { return false }
        guard let model = modelManager.selectedModel else {
            return message == String(localized: "Select or download a transcription model first.")
        }
        return !modelManager.isModelDownloaded(model)
            && message == String(localized: "Download \(model.name) or choose an existing copy before recording.")
    }

    private func revealInFinder(_ url: URL) {
        let rootURL = viewModel.selectedRootURL()
        let didAccess = rootURL?.startAccessingSecurityScopedResource() ?? false
        NSWorkspace.shared.activateFileViewerSelecting([url])
        if didAccess { rootURL?.stopAccessingSecurityScopedResource() }
    }

    private func stageCameraImage(_ imageData: Data) {
        Task {
            guard viewModel.requireCaptureRouteAvailable() else { return }
            isProcessingAttachments = true
            await viewModel.stageImage(
                data: imageData,
                filename: "camera-photo.jpg",
                contentTypeIdentifier: UTType.jpeg.identifier,
                altText: String(localized: "Camera photo"), altTextOrigin: .placeholder
            )
            isProcessingAttachments = false
            composerController.focus()
        }
    }

    private func stageSketch(_ drawingData: Data, _ previewData: Data) {
        Task {
            guard viewModel.requireCaptureRouteAvailable() else { return }
            isProcessingAttachments = true
            await viewModel.stageSketch(
                drawingData: drawingData,
                previewData: previewData,
                altText: String(localized: "Sketch created on Mac"), altTextOrigin: .placeholder,
                drawingFilename: "sketch.voxsketch",
                drawingContentTypeIdentifier: "application/vnd.voxmd.sketch+json"
            )
            isProcessingAttachments = false
            composerController.focus()
        }
    }

    private func insertDueDate(_ date: Date, _ includesTime: Bool) {
        let token = insertionFormatter.dueDateToken(for: date, includeTime: includesTime)
        applyComposerCommand(.replaceSelection(with: token))
    }

    private var displayedError: String? {
        if isLocalizationScreenshot { return nil }
        if let message = viewModel.errorMessage { return message }
        return recorder.lastError
    }

    private var isLocalizationScreenshot: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--localization-screenshot")
        #else
        return false
        #endif
    }

    private var enabledFlows: [CapturePreset] {
        let enabled = flows.filter(\.isEnabled)
        return enabled.isEmpty ? CapturePresetStore.defaultFlows : enabled
    }

    private var selectedFlow: CapturePreset {
        if let id = viewModel.draft.voxID,
           let match = enabledFlows.first(where: { $0.id == id }) {
            return match
        }
        return enabledFlows.first(where: { $0.id == CapturePresetStore.selectedFlowId() })
            ?? enabledFlows[0]
    }

    private var inboxLocationDecisionTitle: String {
        guard let decision = viewModel.inboxLocationDecision else {
            return String(localized: "Send Capture Without Location?")
        }
        let preset = decision.presetName ?? String(localized: "Unknown Route")
        return String(localized: "Location Needed for \(preset)")
    }

    private var inboxLocationDecisionMessage: String {
        guard let decision = viewModel.inboxLocationDecision else { return "" }
        let preset = decision.presetName ?? String(localized: "Unknown Route")
        return String(localized: "Send Capture Without Location?")
            + " " + preset + ". "
            + String(localized: "Location is unavailable. Open Vox.md to send this exact Capture without location or discard it.")
    }

    private var routeLabel: String {
        if let override = viewModel.draft.relativeNotePathOverride {
            return URL(fileURLWithPath: override).deletingPathExtension().lastPathComponent
        }
        return viewModel.selectedDestination?.rootName ?? String(localized: "Set up destination")
    }

    private var insertionFormatter: CaptureInsertionFormatter {
        CaptureInsertionFormatter(calendar: calendar, locale: locale, timeZone: timeZone)
    }

    private func reloadFlows() {
        flows = CapturePresetStore.loadFlows()
        viewModel.refreshVoxProfiles()
        Task { await viewModel.refreshLibrary() }
    }

    private func consumeRequestedInput() {
        guard let requestedInput = viewModel.requestedInput,
              viewModel.requireCaptureRouteAvailable() else { return }
        viewModel.requestedInput = nil
        switch requestedInput {
        case .photos, .screenshots: chooseImages()
        case .camera: selectInspectorTool(.camera)
        case .files: chooseFiles()
        case .scan: chooseScan()
        case .sketch: selectInspectorTool(.sketch)
        case .link: selectInspectorTool(.webLink)
        case .voice: startRecording()
        }
    }

    private func selectFlow(_ flow: CapturePreset) {
        // Draft selection never changes the keyboard/global recording preset.
        guard viewModel.selectVox(flow.id) else { return }
    }

    private func requestNewCapture() {
        if viewModel.draft.hasCaptureContent {
            showsClearDraftConfirmation = true
        } else {
            clearCaptureDraft()
        }
    }

    private func clearCaptureDraft() {
        Task {
            await viewModel.clearDraft()
            composerController.focus()
        }
    }

    private func confirmPresetSwitch(id: UUID) async {
        if await viewModel.confirmPresetSwitch(id: id) {
            consumeRequestedInput()
        }
    }

    private var captureAllowanceBlocked: Bool {
        viewModel.draft.deliveryKind == .standard && usageTracker.isCaptureAtLimit
    }

    private func sendCapture() {
        guard viewModel.requireCaptureRouteAvailable() else { return }
        if captureAllowanceBlocked {
            showsPaywall = true
            return
        }
        Task { await viewModel.submit() }
    }

    private func startRecording() {
        guard viewModel.requireCaptureRouteAvailable() else { return }
        guard !usageTracker.isAtLimit else {
            showsPaywall = true
            return
        }
        Task { @MainActor in
            guard let operation = viewModel.beginCaptureRouteOperation() else { return }
            defer { viewModel.endCaptureRouteOperation(operation) }
            let draftID = viewModel.draft.id
            let requestID = viewModel.draft.requestID
            let presetID = viewModel.draft.voxID
            let granted = await AudioRecorder.requestMicrophonePermission()
            guard !Task.isCancelled, !recorder.ownsCaptureRoute,
                  viewModel.draft.id == draftID, viewModel.draft.requestID == requestID,
                  viewModel.draft.voxID == presetID,
                  CapturePresetStore.loadFlows().contains(where: { $0.id == presetID && $0.isEnabled }) else { return }
            guard granted else {
                recorder.lastError = String(localized: "Enable microphone access in System Settings to record audio.")
                return
            }
            if inputMode == .meeting {
                await recorder.startMeetingRecording(
                    modelManager: modelManager,
                    flowId: selectedFlow.id,
                    completionMode: selectedRecordingCompletionMode,
                    draftRequestID: recordingMode == .draft ? viewModel.draft.requestID : nil
                )
            } else {
                recorder.startRecording(
                    modelManager: modelManager,
                    flowId: selectedFlow.id,
                    completionMode: selectedRecordingCompletionMode,
                    draftRequestID: recordingMode == .draft ? viewModel.draft.requestID : nil
                )
            }
        }
    }

    private var selectedRecordingCompletionMode: MacRecordingCompletionMode {
        switch recordingMode {
        case .draft:
            return .captureDraft(attachAudio: attachRecordingAudio)
        case .preset:
            return .runPreset(flow: selectedFlow)
        }
    }

    private func applyComposerCommand(_ command: CaptureComposerCommand) {
        let result = CaptureComposerTextEditor().applying(
            command,
            to: composerController.text,
            selection: CaptureTextSelection(
                location: composerController.selection.location,
                length: composerController.selection.length
            )
        )
        composerController.replaceAll(
            with: result.text,
            selection: NSRange(location: result.selection.location, length: result.selection.length)
        )
        composerIsFocused = true
        composerController.focus()
    }

    private func chooseImages() {
        chooseURLs(
            title: String(localized: "Add Images to Capture"),
            contentTypes: [.image],
            allowsMultipleSelection: true
        )
    }

    private func chooseScan() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Scan or PDF")
        panel.prompt = String(localized: "Add Scan")
        panel.allowedContentTypes = [.image, .pdf]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }

        Task {
            guard viewModel.requireCaptureRouteAvailable() else { return }
            isProcessingAttachments = true
            defer {
                isProcessingAttachments = false
                composerController.focus()
            }
            do {
                var budget = CaptureInputBudget()
                try budget.reserveSharedItems(panel.urls.count)
                var imageURLs: [URL] = []
                var otherURLs: [URL] = []
                for url in panel.urls {
                    let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                        ?? UTType(filenameExtension: url.pathExtension)
                        ?? .data
                    if type.conforms(to: .image) {
                        imageURLs.append(url)
                    } else {
                        otherURLs.append(url)
                    }
                }
                if !imageURLs.isEmpty {
                    let scan = try await MacDocumentScanProcessor.process(imageURLs: imageURLs)
                    await viewModel.stageScan(
                        pageImages: scan.pageImages,
                        pdfData: scan.pdfData,
                        extractedText: scan.extractedText
                    )
                }
                if !otherURLs.isEmpty {
                    await stageURLs(otherURLs, alreadyOwnsRoute: true)
                }
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func chooseFiles() {
        chooseURLs(
            title: String(localized: "Add Files to Capture"),
            contentTypes: [.data],
            allowsMultipleSelection: true
        )
    }

    private func chooseAudio() {
        chooseURLs(
            title: String(localized: "Add Audio to Capture"),
            contentTypes: [.audio],
            allowsMultipleSelection: true
        )
    }

    private func importAudioForTranscription() {
        guard viewModel.requireCaptureRouteAvailable() else { return }
        guard !usageTracker.isAtLimit else {
            showsPaywall = true
            return
        }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Transcribe Audio or Video")
        panel.prompt = String(localized: "Transcribe")
        panel.allowedContentTypes = [.audio, .movie]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url,
              viewModel.requireCaptureRouteAvailable(),
              CapturePresetStore.loadFlows().contains(where: { $0.id == viewModel.draft.voxID && $0.isEnabled }) else { return }
        recorder.importAudioFile(
            from: url,
            modelManager: modelManager,
            flowId: selectedFlow.id,
            completionMode: selectedRecordingCompletionMode,
            draftRequestID: recordingMode == .draft ? viewModel.draft.requestID : nil
        )
    }

    private func chooseURLs(
        title: String,
        contentTypes: [UTType],
        allowsMultipleSelection: Bool
    ) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.prompt = String(localized: "Add")
        panel.allowedContentTypes = contentTypes
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK else { return }
        Task { await stageURLs(panel.urls) }
    }

    private func stageURLs(_ urls: [URL], alreadyOwnsRoute: Bool = false) async {
        guard !urls.isEmpty,
              alreadyOwnsRoute || viewModel.requireCaptureRouteAvailable() else { return }
        isProcessingAttachments = true
        defer {
            isProcessingAttachments = false
            composerController.focus()
        }
        do {
            var budget = CaptureInputBudget()
            try budget.reserveSharedItems(urls.count)
            let firstNewPayloadIndex = viewModel.draft.additionalPayloads.count
            for url in urls {
                let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)
                    ?? UTType(filenameExtension: url.pathExtension)
                    ?? .data
                await viewModel.stageFile(
                    at: url,
                    filename: url.lastPathComponent,
                    contentTypeIdentifier: type.identifier,
                    embedAsImage: type.conforms(to: .image),
                    embedAsAudio: type.conforms(to: .audio),
                    describeImageImmediately: false
                )
            }
            await viewModel.describeStagedImagesIfNeeded(from: firstNewPayloadIndex)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func pasteIntoCapture() {
        let pasteboard = NSPasteboard.general
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            Task { await stageURLs(urls) }
            return
        }

        if let data = pasteboard.data(forType: .png) {
            Task {
                guard viewModel.requireCaptureRouteAvailable() else { return }
                isProcessingAttachments = true
                await viewModel.stageImage(
                    data: data,
                    filename: "pasted-image-\(UUID().uuidString.lowercased()).png",
                    contentTypeIdentifier: UTType.png.identifier,
                    altText: String(localized: "Pasted image"), altTextOrigin: .placeholder
                )
                isProcessingAttachments = false
            }
            return
        }

        if let tiff = pasteboard.data(forType: .tiff),
           let image = NSImage(data: tiff),
           let png = pngData(from: image) {
            Task {
                guard viewModel.requireCaptureRouteAvailable() else { return }
                isProcessingAttachments = true
                await viewModel.stageImage(
                    data: png,
                    filename: "pasted-image-\(UUID().uuidString.lowercased()).png",
                    contentTypeIdentifier: UTType.png.identifier,
                    altText: String(localized: "Pasted image"), altTextOrigin: .placeholder
                )
                isProcessingAttachments = false
            }
            return
        }

        guard let string = pasteboard.string(forType: .string), !string.isEmpty else { return }
        if let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            Task { await viewModel.addURL(url) }
        } else {
            composerController.replaceSelection(with: string)
        }
    }

    private func pngData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }

    private func addLink() {
        let value = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            viewModel.errorMessage = String(localized: "Enter a complete http:// or https:// link.")
            return
        }
        linkText = ""
        dismissInspectorTool(refocus: false)
        Task {
            await viewModel.addURL(url)
            composerController.focus()
        }
    }

    private func insertInternalLink() {
        let value = internalLinkText
        do {
            let link = try insertionFormatter.wikiLink(for: value)
            internalLinkText = ""
            dismissInspectorTool(refocus: false)
            applyComposerCommand(.replaceSelection(with: link))
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func captureDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func loadInspirationQuoteIfNeeded() async {
        guard !hasLoadedInspirationQuote else { return }
        inspirationQuote = await InspirationQuoteService.shared.nextQuote()
        hasLoadedInspirationQuote = true
    }

    private func presentSentToast() async {
        withAnimation(.easeOut(duration: 0.18)) { showsSentToast = true }
        try? await Task.sleep(for: .seconds(2))
        withAnimation(.easeIn(duration: 0.18)) { showsSentToast = false }
        composerController.focus()
    }

    private func payloadIcon(_ payload: CapturePayload) -> String {
        switch payload {
        case .text: "text.alignleft"
        case .url: "link"
        case .audio, .retainedAudio: "waveform"
        case .image: "photo"
        case .file: "doc"
        case .scannedDocument: "doc.viewfinder"
        case .sketch: "pencil.tip"
        }
    }

    private func payloadLabel(_ payload: CapturePayload) -> String {
        switch payload {
        case .text(let value): value
        case .url(let url, let title): title ?? url.absoluteString
        case .audio(let asset, _), .retainedAudio(let asset, _), .file(let asset):
            asset.originalFilename
        case .image(let asset, let altText, let origin):
            generatedAltTextLabel(altText, origin: origin) ?? asset.originalFilename
        case .scannedDocument(let pages, _, _): "Scan · \(pages.count) page(s)"
        case .sketch(_, _, let altText, let origin):
            generatedAltTextLabel(altText, origin: origin) ?? "Sketch"
        }
    }

    private func generatedAltTextLabel(_ altText: String?, origin: CaptureAltTextOrigin?) -> String? {
        guard origin == .generated else { return nil }
        return CaptureImageDescription.validated(altText)
    }
}

struct MacCaptureRouteInspector: View {
    @Bindable var viewModel: QuickCaptureViewModel
    @Environment(ModelManager.self) private var modelManager
    var onClose: (() -> Void)?
    var onAddFiles: (() -> Void)?
    var onOpenModels: (() -> Void)?
    @State private var isEditingDestination = false

    init(
        viewModel: QuickCaptureViewModel,
        onClose: (() -> Void)? = nil,
        onAddFiles: (() -> Void)? = nil,
        onOpenModels: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onClose = onClose
        self.onAddFiles = onAddFiles
        self.onOpenModels = onOpenModels
    }

    var body: some View {
        NavigationStack {
            // Signal inspector: header, four step cards and WILL WRITE sit
            // directly on the panel; the editable details follow as cards.
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    routeHeader
                    routeStepsSection
                    willWriteSection

                    destinationSection

                    if viewModel.selectedDestination != nil {
                        captureOverridesSection
                    }

                    processingSection
                    attachmentsSection
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .groupBoxStyle(MacSignalGroupBoxStyle())
            .disabled(!viewModel.canChangeCaptureRoute)
            .background(Geist.Palette.gray100)
            .navigationTitle("Capture Details")
            .navigationDestination(isPresented: $isEditingDestination) {
                MacCaptureDestinationEditor(
                    existing: viewModel.selectedPresetDestination,
                    templates: viewModel.entryTemplates,
                    fixedName: viewModel.selectedVoxProfile.map { $0.visibleName ?? String(localized: "Icon-only route") },
                    embeddedInNavigation: true,
                    onClose: { isEditingDestination = false }
                ) { destination in
                    try await viewModel.saveSelectedPresetDestination(destination)
                }
            }
        }
    }

    /// Signal route header: indigo letter tile + route name.
    @ViewBuilder
    private var routeHeader: some View {
        if let preset = viewModel.selectedVoxProfile {
            HStack(spacing: 10) {
                // Same tile as the sidebar: color by route position, emoji
                // or first letter.
                MacRouteTile(
                    letter: MacRouteCatalog.letter(preset),
                    index: MacRouteCatalog.enabledRoutes(in: viewModel)
                        .firstIndex { $0.id == preset.id } ?? Int.max,
                    size: 32
                )
                Text(preset.visibleName ?? String(localized: "Icon-only route"))
                    .font(Geist.heading(.headline))
                    .foregroundStyle(Geist.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .listRowBackground(Color.clear)
            .accessibilityElement(children: .combine)
        }
    }

    /// CAPTURE / PROCESS / SHAPE / DELIVER for the selected route.
    @ViewBuilder
    private var routeStepsSection: some View {
        if viewModel.selectedVoxProfile != nil {
            // Four separate cards, as in the Signal MacWorkspace inspector.
            Section {
                VStack(spacing: 8) {
                    ForEach(MacCapturePreview.steps(for: viewModel)) { step in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: step.kind)
                                .font(Geist.mono(size: 10.5, relativeTo: .caption2))
                                .tracking(0.63)
                                .foregroundStyle(Geist.muted)
                            Text(step.title)
                                .font(Geist.label(.callout))
                                .foregroundStyle(Geist.text)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Geist.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Geist.border, lineWidth: 1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    /// "WILL WRITE": the Markdown this draft will append, rendered with the
    /// pipeline's CaptureMarkdownRenderer.
    @ViewBuilder
    private var willWriteSection: some View {
        if let markdown = MacCapturePreview.willWrite(for: viewModel) {
            Section {
                MacMarkdownBlock(label: "Will write", markdown: markdown)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
        }
    }

    @ViewBuilder
    private var destinationSection: some View {
        inspectorGroup("Destination") {
            if let preset = viewModel.selectedVoxProfile {
                LabeledContent("Route") {
                    Label {
                        Text(preset.visibleName ?? String(localized: "Icon-only route"))
                            .foregroundStyle(preset.visibleName == nil ? .secondary : .primary)
                    } icon: {
                        CapturePresetIconView(symbolName: preset.symbolName, emoji: preset.emoji)
                    }
                    .accessibilityLabel(preset.accessibilityName)
                }

                if let destination = viewModel.selectedPresetDestination {
                    LabeledContent("Folder", value: destination.rootName)
                    if let preview = viewModel.resolvedDestinationPreview {
                        LabeledContent("Note") {
                            Text(preview)
                                .font(Geist.mono(size: 12, relativeTo: .caption))
                                .foregroundStyle(Geist.muted)
                                .lineLimit(2)
                                .textSelection(.enabled)
                        }
                    }
                    Button("Edit Destination…") {
                        isEditingDestination = true
                    }
                } else {
                    Text("Choose a notes folder before sending this Capture.")
                        .foregroundStyle(.secondary)
                    Button("Set Up Destination…") {
                        isEditingDestination = true
                    }
                    .accessibilityIdentifier("mac_capture_destination_setup")
                }
            } else {
                Label("No Route Selected", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var captureOverridesSection: some View {
        inspectorGroup("This Capture") {
            Picker("Placement", selection: placementBinding) {
                Text("Route Default").tag(PlacementChoice.default)
                Text("Top").tag(PlacementChoice.top)
                Text("Bottom").tag(PlacementChoice.bottom)
            }

            Picker("Entry Template", selection: Binding(
                get: { viewModel.draft.entryTemplateID },
                set: { viewModel.setEntryTemplateOverride($0) }
            )) {
                Text("Route Default").tag(UUID?.none)
                ForEach(viewModel.entryTemplates) { template in
                    Text(template.name).tag(Optional(template.id))
                }
            }

            Button {
                chooseOneOffNote()
            } label: {
                Label(
                    viewModel.draft.relativeNotePathOverride ?? String(localized: "Choose another Markdown note"),
                    systemImage: "doc.text.magnifyingglass"
                )
            }

            if viewModel.hasAnyRouteOverride {
                Button("Use Route Defaults", systemImage: "arrow.uturn.backward") {
                    viewModel.useVoxRouteDefaults()
                }
            }
        }
    }

    @ViewBuilder
    private var processingSection: some View {
        inspectorGroup("Processing") {
            LabeledContent("Transcription", value: transcriptionModelLabel)

            if let preset = viewModel.selectedVoxProfile {
                LabeledContent(
                    "Text",
                    value: preset.captureProcessingEnabled
                        ? preset.postProcessingMode.displayName
                        : String(localized: "Off")
                )

                if preset.captureProcessingEnabled && preset.postProcessingMode != .none {
                    LabeledContent("Apply To", value: preset.captureProcessingScope.displayName)
                }

                LabeledContent(
                    "Image Alt Text",
                    value: preset.captureProcessingEnabled && preset.generateImageAltText
                        ? String(localized: "On")
                        : String(localized: "Off")
                )

                Text("Processing follows the selected Route and runs on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let onOpenModels {
                Button("Manage Transcription Models…", systemImage: "cpu", action: onOpenModels)
            }
        }
    }

    @ViewBuilder
    private var attachmentsSection: some View {
        inspectorGroup("Attachments") {
            if viewModel.draft.additionalPayloads.isEmpty {
                Label("No Attachments", systemImage: "paperclip")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(viewModel.draft.additionalPayloads.enumerated()), id: \.offset) { index, payload in
                    HStack(spacing: 8) {
                        Label(payloadLabel(payload), systemImage: payloadIcon(payload))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button {
                            Task { await viewModel.removePayload(at: index) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(payloadLabel(payload))")
                    }
                }
            }

            if let onAddFiles {
                Button("Add Files…", systemImage: "plus", action: onAddFiles)
            }

            Text("You can also drag files anywhere onto the Capture document.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func inspectorGroup<Content: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .buttonStyle(.link)
            .labeledContentStyle(MacInspectorLabeledContentStyle())
        }
    }

    private var transcriptionModelLabel: String {
        if modelManager.isAutomaticSelection {
            return String(localized: "Automatic")
        }
        return modelManager.selectedModel?.name ?? String(localized: "Not Selected")
    }

    private var placementBinding: Binding<PlacementChoice> {
        Binding(
            get: {
                switch viewModel.draft.placementOverride {
                case nil: .default
                case .prepend: .top
                case .append: .bottom
                case .beneathHeading: .default
                }
            },
            set: { choice in
                switch choice {
                case .default: viewModel.setPlacementOverride(nil)
                case .top: viewModel.setPlacementOverride(.prepend)
                case .bottom: viewModel.setPlacementOverride(.append)
                }
            }
        )
    }

    private func chooseOneOffNote() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose Markdown Note")
        panel.prompt = String(localized: "Use Note")
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.directoryURL = viewModel.selectedRootURL()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.setOneOffNote(url: url) }
    }

    private func payloadIcon(_ payload: CapturePayload) -> String {
        switch payload {
        case .text: "text.alignleft"
        case .url: "link"
        case .audio, .retainedAudio: "waveform"
        case .image: "photo"
        case .file: "doc"
        case .scannedDocument: "doc.viewfinder"
        case .sketch: "pencil.tip"
        }
    }

    private func payloadLabel(_ payload: CapturePayload) -> String {
        switch payload {
        case .text(let value): value
        case .url(let url, let title): title ?? url.absoluteString
        case .audio(let asset, _), .retainedAudio(let asset, _), .file(let asset):
            asset.originalFilename
        case .image(let asset, let altText, let origin):
            generatedAltTextLabel(altText, origin: origin) ?? asset.originalFilename
        case .scannedDocument(let pages, _, _): "Scan · \(pages.count) page(s)"
        case .sketch(_, _, let altText, let origin):
            generatedAltTextLabel(altText, origin: origin) ?? "Sketch"
        }
    }

    private func generatedAltTextLabel(_ altText: String?, origin: CaptureAltTextOrigin?) -> String? {
        guard origin == .generated else { return nil }
        return CaptureImageDescription.validated(altText)
    }

    private enum PlacementChoice: String, Hashable {
        case `default`, top, bottom
    }
}

/// Label leading, value trailing in the inspector cards (as in a Form).
private struct MacInspectorLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            configuration.content
                .foregroundStyle(Geist.muted)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct MacCaptureTextInspectorView: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let prompt: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    @Binding var text: String
    let onClose: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.four) {
            HStack {
                Text(title)
                    .font(Geist.heading(.title2))
                Spacer()
                Button("Close", action: onClose)
            }
            Text(detail)
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
            TextField(prompt, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit(onSubmit)
            Button(actionTitle, action: onSubmit)
                .buttonStyle(.borderedProminent)
                .tint(MacBrand.accent)
                .foregroundStyle(MacBrand.onAccent)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Spacer()
        }
        .padding(Geist.Spacing.four)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Geist.Palette.gray100)
    }
}

private struct MacCaptureDueDateInspectorView: View {
    @State private var date = Date()
    @State private var includesTime = false
    let onClose: () -> Void
    let onInsert: (Date, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Geist.Spacing.four) {
            HStack {
                Text("Set Due Date")
                    .font(Geist.heading(.title2))
                Spacer()
                Button("Close", action: onClose)
            }
            DatePicker(
                "Due date",
                selection: $date,
                displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date]
            )
            Toggle("Include time", isOn: $includesTime)
            Button("Insert Due Date") {
                onInsert(date, includesTime)
            }
            .buttonStyle(.borderedProminent)
            .tint(MacBrand.accent)
            .foregroundStyle(MacBrand.onAccent)
            Spacer()
        }
        .padding(Geist.Spacing.four)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Geist.Palette.gray100)
    }
}

private func formatDuration(_ duration: TimeInterval) -> String {
    let minutes = Int(duration) / 60
    let seconds = Int(duration) % 60
    return String(format: "%d:%02d", minutes, seconds)
}

/// Applies a keyboard shortcut only when one is defined.
private struct MacOptionalShortcut: ViewModifier {
    let shortcut: KeyboardShortcut?

    func body(content: Content) -> some View {
        if let shortcut {
            content.keyboardShortcut(shortcut)
        } else {
            content
        }
    }
}

// MARK: - Menu bar (formerly the Capture window toolbar)

/// The Capture window's Add, recording-option and Capture Details commands
/// (the window has no toolbar), shown at the end of the menu bar's Capture
/// menu. They act on the focused Capture window through `MacCaptureMenuActions`.
struct MacCaptureMenuItems: View {
    @FocusedValue(\.macCaptureMenuActions) private var actions

    var body: some View {
        Menu("Add") {
            Button("Images or Screenshots…") { actions?.attach(.images) }
            Button("Take Photo…") { actions?.attach(.photo) }
            Button("Import Scan or PDF…") { actions?.attach(.scan) }
            Button("Sketch…") { actions?.attach(.sketch) }
            Button("Files…") { actions?.attach(.files) }
            Button("Audio Attachment…") { actions?.attach(.audio) }
            Divider()
            Button("Web Link…") { actions?.attach(.webLink) }
            Button("Paste") { actions?.attach(.paste) }
        }
        .disabled(actions?.canAttach != true)

        Button("Transcribe Audio or Video…") { actions?.attach(.transcribe) }
            .disabled(actions == nil || actions?.isRecording == true)

        Toggle("Capture Details", isOn: Binding(
            get: { actions?.isShowingDetails == true },
            set: { _ in actions?.toggleDetails() }
        ))
        .keyboardShortcut("i", modifiers: [.command, .option])
        .disabled(actions == nil)

        Divider()

        Menu("Audio Source") {
            Toggle("Microphone", isOn: radio(\.isMeetingAudio, on: false))
            Toggle("Meeting", isOn: radio(\.isMeetingAudio, on: true))
        }
        .disabled(actions == nil || actions?.isRecording == true)
        Menu("After Recording") {
            Toggle("Add to Draft", isOn: radio(\.sendsAfterRecording, on: false))
            Toggle("Send Immediately", isOn: radio(\.sendsAfterRecording, on: true))
        }
        .disabled(actions == nil || actions?.isRecording == true)
        if actions?.sendsAfterRecording.wrappedValue == false {
            Toggle("Attach Audio to Draft", isOn: radio(\.attachesRecordingAudio, on: true))
                .disabled(actions?.isRecording == true)
        }

        if let reveal = actions?.revealLastCapture {
            Divider()
            Button("Reveal Last Capture", action: reveal)
        }
        if let unlock = actions?.unlock, let title = actions?.unlockTitle {
            Divider()
            Button(title, action: unlock)
        }
    }

    /// A checkmark item that is on when the Bool equals `on`; choosing it sets that value.
    private func radio(_ keyPath: KeyPath<MacCaptureMenuActions, Binding<Bool>>, on: Bool) -> Binding<Bool> {
        Binding(
            get: { actions?[keyPath: keyPath].wrappedValue == on },
            set: { isOn in
                guard let actions else { return }
                if isOn {
                    actions[keyPath: keyPath].wrappedValue = on
                } else if keyPath == \.attachesRecordingAudio {
                    actions[keyPath: keyPath].wrappedValue = false
                }
            }
        )
    }
}

/// The menu bar's "Format" menu for the Capture composer. Undo and Redo stay in
/// the system Edit menu, which reaches the composer through the responder chain.
struct MacCaptureFormatCommands: Commands {
    var body: some Commands {
        CommandMenu("Format") {
            MacCaptureFormatMenuItems()
        }
    }
}

private struct MacCaptureFormatMenuItems: View {
    @FocusedValue(\.macCaptureMenuActions) private var actions

    var body: some View {
        Group {
            Button("Bold") { actions?.format(.bold) }
            Button("Italic") { actions?.format(.italic) }
            Button("Hashtag") { actions?.format(.hashtag) }
            Menu("Heading") {
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { actions?.format(.heading(level)) }
                }
            }
            Divider()
            Button("Markdown link") { actions?.format(.markdownLink) }
            // Same action and ⌘K as the "[[ ]]" (Link note) quick-action chip.
            Button("Internal link") { actions?.format(.internalLink) }
                .keyboardShortcut("k", modifiers: .command)
            Button("Due date") { actions?.format(.dueDate) }
            Button("Checklist") { actions?.format(.checklist) }
            Button("Bullet list") { actions?.format(.bullet) }
            Button("Timestamp") { actions?.format(.timestamp) }
            Button("Date") { actions?.format(.date) }
            Menu("Change Case") {
                Button("Lowercase") { actions?.format(.lowercase) }
                Button("Uppercase") { actions?.format(.uppercase) }
                Button("Sentence case") { actions?.format(.sentenceCase) }
                Button("Capitalize Words") { actions?.format(.capitalizeWords) }
                Button("Slugify") { actions?.format(.slugify) }
            }
        }
        .disabled(actions == nil)
    }
}
