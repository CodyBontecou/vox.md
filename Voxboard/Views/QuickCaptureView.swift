import AVFoundation
import Combine
import Photos
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit
import VoxboardShared

private enum KeyboardLaunchPhase: Equatable {
    case starting
    case ready
    case error
}

private struct KeyboardReturnGuidance: Equatable, Identifiable {
    let id = UUID()
    var phase: KeyboardLaunchPhase
}

private struct InitialComposerFocusTaskID: Equatable {
    let isPending: Bool
    let hasCompletedInitialLoad: Bool
    let defersForReleaseNotes: Bool
}

enum CaptureRecordingMode: String, CaseIterable, Identifiable {
    case draft
    case preset

    var id: Self { self }

    /// Resolves the persisted recording result mode. A missing or invalid
    /// stored value maps to `.draft` ("Add to Draft") — the default for new
    /// installs and the migration default for existing users upgrading to
    /// 2.8, where the recording result previously reset every launch.
    init(persistedRawValue: String?) {
        self = Self(rawValue: persistedRawValue ?? "") ?? .draft
    }
}

/// Rolling live-recording waveform: the newest levels read in the recording
/// red, older history fades to grey (Signal live recording artboard).
private struct CaptureRecordingWaveform: View {
    let levels: [Float]
    var isPaused = false

    private let minFraction: CGFloat = 0.08
    private let maxHeight: CGFloat = 56
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 3

    var body: some View {
        HStack(spacing: barSpacing) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(color(for: index))
                    .frame(
                        width: barWidth,
                        height: maxHeight * max(minFraction, CGFloat(level))
                    )
                    .animation(.easeInOut(duration: 0.08), value: level)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: maxHeight)
        .accessibilityHidden(true)
    }

    private func color(for index: Int) -> Color {
        guard !isPaused else { return Geist.Palette.gray500 }
        return index >= levels.count - 14 ? Geist.recording : Geist.Palette.gray500
    }
}

struct QuickCaptureView: View {
    @Bindable var viewModel: QuickCaptureViewModel
    @Bindable var persistentRecorder: PersistentRecorder
    @Binding var pendingKeyboardLaunch: Bool
    @Binding var pendingWidgetRecord: Bool
    let captureToolbarPreferences: CaptureToolbarPreferences
    let openSettings: () -> Void
    /// Regular-width arrangement (iPad, Duo inner, wide Split View). See
    /// `CaptureComposerLayout`; `.compact` is the phone layout.
    let layout: CaptureComposerLayout
    /// Lets a route pane beside the composer trigger Send.
    let commands: CaptureComposerCommands?

    @Environment(TranscriptStore.self) private var transcriptStore
    @Environment(UsageTracker.self) private var usageTracker
    @Environment(StoreManager.self) private var storeManager
    @Environment(WatchRecordingPipeline.self) private var watchRecordingPipeline
    @Environment(\.defersCaptureInputFocusForReleaseNotes) private var defersCaptureInputFocusForReleaseNotes
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone
    @Environment(\.adaptiveCanExpandWindow) private var canExpandWindow
    @Environment(\.adaptiveHingeState) private var hingeState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var workspaceWidth: CGFloat = 0
    @State private var previewIsEnabled = false

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedScreenshots: [PhotosPickerItem] = []
    @State private var selectedOCRPhotos: [PhotosPickerItem] = []
    @State private var showsPhotoPicker = false
    @State private var showsScreenshotPicker = false
    @State private var showsOCRPhotoPicker = false
    @State private var showsCamera = false
    @State private var showsFileImporter = false
    @State private var showsScanner = false
    @State private var showsJournalPageCapture = false
    @State private var showsSketch = false
    @State private var showsLinkPrompt = false
    @State private var showsCaptureHistory = false
    @State private var showsVaultFiles = false
    @State private var showsRoutePicker = false
    @State private var showsDueDate = false
    @State private var showsInternalLinks = false
    @State private var showsPaywall = false
    @State private var paywallContext: PaywallContext = .limit
    @State private var showsAudioImporter = false
    @State private var showsVoiceCaptureDetails = false
    @State private var showsRecordingControlHelp = false
    @State private var showsWatchRecordingQueue = false
    /// Durable recording result mode ("Add to Draft" vs "Send Immediately").
    /// `recordingMode` seeds from this persisted value at first render and
    /// writes back through the details-bar picker binding, so the choice
    /// survives relaunches instead of resetting to "Send Immediately".
    @AppStorage(CapturePreferenceKeys.defaultRecordingResultMode)
    private var persistedRecordingResultMode = CaptureRecordingMode.draft.rawValue
    @State private var recordingMode: CaptureRecordingMode = .init(
        persistedRawValue: UserDefaults.standard.string(
            forKey: CapturePreferenceKeys.defaultRecordingResultMode
        )
    )
    @State private var attachRecordingAudio = false
    @State private var lastStartedRecordingMode: CaptureRecordingMode = .preset
    @State private var microphonePermissionTask: Task<Void, Never>?
    @State private var showsMicrophoneSettings = false
    @State private var showsFirstNoteFolderPicker = false
    @State private var isSavingFirstNoteFolder = false
    @State private var firstNoteReceipt: CaptureReceipt?
    @State private var firstNoteDocument: FirstNoteDocument?
    @AppStorage(CapturePreferenceKeys.firstNoteSaved, store: AppConstants.sharedDefaults)
    private var hasSavedFirstNote = false
    @State private var setupChoseFolder = false
    @State private var keyboardLaunchPhase: KeyboardLaunchPhase?
    @State private var keyboardReturnGuidance: KeyboardReturnGuidance?
    @State private var fileExportToast: FileExportToast?
    @State private var flows: [CapturePreset] = CapturePresetStore.loadFlows()
    @State private var selectedFlowId: String = CapturePresetStore.selectedFlowId()
    @State private var observedPresetData: Data?
    @State private var linkText = ""
    private var isProcessingMedia: Bool {
        get { viewModel.isProcessingMedia }
        nonmutating set { viewModel.isProcessingMedia = newValue }
    }
    @State private var isExtractingText = false
    @State private var isFindingLocation = false
    @State private var locationRequestTask: Task<Void, Never>?
    @State private var showsSentToast = false
    @State private var sentUndoSnapshot: SentCaptureUndoSnapshot?
    @State private var sentToastPresentationID: UUID?
    @State private var showsPresetSendConfirmation = false
    @AppStorage(CapturePreferenceKeys.confirmPresetSend) private var confirmsPresetSend = false
    @State private var composerSelection = NSRange(location: 0, length: 0)
    @State private var composerIsFocused = false
    /// The editor's text height, so the iPad Pencil card can sit right under it.
    @State private var composerContentHeight: CGFloat = 0
    /// The editor's on-screen height, so the quote can step aside when the
    /// keyboard and attachments leave no room beside the Route prompt.
    @State private var composerViewportHeight: CGFloat = .infinity
    /// True while an on-screen keyboard (or the ••• panel in its place) is up.
    /// A hardware keyboard only shows the accessory bar, which stays false.
    @State private var hasPerformedInitialLoad = false
    @State private var hasCompletedInitialLoad = false
    @State private var initialComposerFocusIsPending = false
    @State private var composerController = MarkdownComposerController()
    @State private var locationService = CaptureLocationService()
    @State private var inspirationQuote = InspirationQuote.fallback
    @State private var hasLoadedInspirationQuote = false
    @State private var recordingAudioLevels: [Float] = Array(repeating: 0, count: Self.recordingWaveformBarCount)
    @State private var showsAttachSheet = false
    @State private var pendingAttachAction: CaptureAttachAction?
    /// Push-to-talk: the Speak capsule records while held and stops on release.
    @State private var speakLongPressTask: Task<Void, Never>?
    @State private var speakLongPressFired = false
    @State private var isSpeakPressed = false
    @State private var vaultIsReachable = true
    @State private var showsVaultRegrantPicker = false
    @State private var pendingCaptureCount = 0
    @State private var recentPhotos = CaptureRecentPhotosModel()
    @State private var showsWhiteboardScanner = false
    @State private var showsWhiteboardCamera = false

    private static let recordingWaveformBarCount = 44

    init(
        viewModel: QuickCaptureViewModel,
        persistentRecorder: PersistentRecorder,
        pendingKeyboardLaunch: Binding<Bool>,
        pendingWidgetRecord: Binding<Bool>,
        captureToolbarPreferences: CaptureToolbarPreferences,
        openSettings: @escaping () -> Void,
        layout: CaptureComposerLayout = .compact,
        commands: CaptureComposerCommands? = nil
    ) {
        self.viewModel = viewModel
        self.persistentRecorder = persistentRecorder
        _pendingKeyboardLaunch = pendingKeyboardLaunch
        _pendingWidgetRecord = pendingWidgetRecord
        self.captureToolbarPreferences = captureToolbarPreferences
        self.openSettings = openSettings
        self.layout = layout
        self.commands = commands
        #if DEBUG
        let screenshotStory = RootDestination.localizationScreenshotStory
        _showsVoiceCaptureDetails = State(
            initialValue: screenshotStory == "02-live-recording"
                || screenshotStory == "05-live-recording"
        )
        #endif
    }

    // State and effects live here; presentation crosses concrete section
    // boundaries. See docs/capture-view-regression-tests.md before adding UI.
    var body: CaptureViewSection { presentedContent }

    private var captureContent: CaptureViewSection {
        CaptureViewSection {
            QuickCaptureCanvas(
                showsDestination: !isLocalizationScreenshot
                    && (showsFirstNoteGuide || viewModel.selectedDestination == nil || !vaultIsReachable),
                showsWatchStatus: watchRecordingPipeline.hasVisibleItems,
                showsAttachments: !viewModel.draft.additionalPayloads.isEmpty,
                header: captureHeader,
                ocrProgress: captureOCRProgressBanner,
                destination: destinationGuidance,
                watchStatus: watchRecordingStatusCard,
                composer: composerWithInlineTools,
                attachments: attachmentStrip,
                controls: captureControls,
                keyboardGuidance: keyboardGuidanceOverlay,
                error: captureErrorOverlay,
                fileExport: fileExportOverlay,
                sentToast: sentToastOverlay,
                showsPreview: showsInlinePreview,
                preview: draftPreview
            )
            .overlay { liveRecordingScreen }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { workspaceWidth = $0 }
            // The Signal header (route pill, Activity, Settings) replaces the
            // empty navigation bar on the capture root.
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: registerComposerCommands)
            .onChange(of: viewModel.canSubmit && !captureSubmissionIsBlocked, initial: true) { _, canSend in
                commands?.canSend = canSend
            }
        }
    }

    // MARK: Regular-width layout

    /// Exposes Send to a route pane beside the composer (`CaptureComposerCommands`).
    private func registerComposerCommands() {
        commands?.send = {
            if captureSubmissionRequiresUnlock {
                presentPaywall(context: .captureLimit)
            } else {
                sendComposerCapture()
            }
        }
    }

    private var showsInlinePencil: Bool {
        layout.isRegular && UIDevice.current.userInterfaceIdiom == .pad
    }

    /// iPad keeps an inline "Draw with Pencil" canvas directly under the text
    /// (iPad board): the editor is as tall as its text, up to the room left
    /// above the card, and scrolls past that.
    private var composerWithInlineTools: CaptureViewSection {
        CaptureViewSection {
            if showsInlinePencil {
                VStack(alignment: .leading, spacing: 0) {
                    composer
                        .frame(minHeight: 96, maxHeight: max(96, composerContentHeight))
                        .layoutPriority(1)
                    AdaptivePencilSketchArea(viewModel: viewModel)
                        .padding(.horizontal, layout == .regularSidebar ? 28 : 20)
                        .padding(.bottom, Geist.Spacing.two)
                    // Empty room under the card still means "write here".
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture { composerIsFocused = true }
                        .accessibilityHidden(true)
                }
            } else {
                composer
            }
        }
    }

    private var captureHeader: CaptureViewSection {
        CaptureViewSection {
            switch layout {
            case .compact:
                compactCaptureHeader
            case .regularPane:
                VStack(alignment: .leading, spacing: 14) {
                    compactCaptureHeader
                    quickActionsToolbar(isInline: true)
                        .padding(.horizontal, 20)
                        .padding(.bottom, Geist.Spacing.two)
                }
            case .regularSidebar:
                // Routes live in the sidebar: the path line and the inline
                // quick actions share one 64pt editor header.
                HStack(spacing: Geist.Spacing.three) {
                    routeDestinationLine
                        .frame(minWidth: 120, alignment: .leading)
                        .layoutPriority(1)
                    Spacer(minLength: Geist.Spacing.two)
                    quickActionsToolbar(isInline: true)
                        .frame(minWidth: 200, maxWidth: 400)
                }
                .padding(.horizontal, 24)
                .frame(height: 64)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Geist.border).frame(height: 1)
                }
                .padding(.bottom, Geist.Spacing.three)
            }
        }
    }

    private var compactCaptureHeader: CaptureViewSection {
        CaptureViewSection {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top, spacing: Geist.Spacing.three) {
                    // One route bar everywhere (resting, typing, cover
                    // screen): no dropdown menu to open first.
                    routePillsRow
                    Spacer(minLength: 0)
                    captureHeaderActions
                }
                // Full width under the actions row, so the vault/folder
                // prefix is kept wherever it fits (Main board).
                routeDestinationLine
                liveNoteBannerSection
            }
            .padding(.horizontal, 20)
            .padding(.top, Geist.Spacing.two)
            .padding(.bottom, Geist.Spacing.three)
        }
    }

    private var captureHeaderActions: CaptureViewSection {
        CaptureViewSection {
            HStack(spacing: Geist.Spacing.two) {
                if isKeyboardListeningActive {
                    Button(action: togglePersistentListening) {
                        Image(systemName: "headphones")
                    }
                    .buttonStyle(SignalCircleButtonStyle(foreground: Geist.accentText))
                    .accessibilityLabel(
                        CaptureRecordingControlSemantics.keyboardListeningLabel(isListening: true)
                    )
                    .accessibilityHint(
                        CaptureRecordingControlSemantics.keyboardListeningActionHint(isListening: true)
                    )
                    .help(CaptureRecordingControlSemantics.keyboardListeningHelp)
                    .accessibilityIdentifier("capture_keyboard_listening_status")
                }

                if showsTypingDoneButton {
                    // While typing, Activity and Settings give way to Done
                    // (CaptureKeyboard / CaptureRestActions boards).
                    Button(action: dismissComposer) {
                        Text("Done")
                            .font(Geist.body(.subheadline).weight(.semibold))
                            .foregroundStyle(Geist.accentText)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("capture_done_typing")
                } else {
                    if viewModel.liveNotesEnabled {
                        filesButton
                    }
                    activityButton

                    Button {
                        dismissComposer()
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                            .accessibilityLabel("Settings")
                    }
                    .buttonStyle(SignalCircleButtonStyle())
                    .accessibilityIdentifier("capture_settings")
                }
            }
        }
    }

    /// Phone only: the cover screen and the iPad panes keep their actions.
    private var showsTypingDoneButton: Bool {
        layout == .compact && composerIsFocused && !isCoverScreen
    }

    /// Files: the vault tree (Live Notes).
    private var filesButton: CaptureViewSection {
        CaptureViewSection {
            Button {
                dismissComposer()
                showsVaultFiles = true
            } label: {
                Image(systemName: "folder")
                    .accessibilityLabel("Files")
            }
            .buttonStyle(SignalCircleButtonStyle())
            .accessibilityIdentifier("capture_files")
        }
    }

    /// Live Notes problems with the open file, under the path line.
    private var liveNoteBannerSection: CaptureViewSection {
        CaptureViewSection {
            let status = viewModel.liveNoteStatus
            if viewModel.liveNotesEnabled, status.needsAttention,
               status != .unreachable || vaultIsReachable {
                LiveNoteBanner(
                    status: status,
                    fileName: viewModel.liveNote?.binding.fileName,
                    resolve: { choice in Task { await viewModel.liveNote?.resolveConflict(choice) } },
                    reconnect: {
                        dismissComposer()
                        showsVaultRegrantPicker = true
                    },
                    recreate: { Task { await viewModel.liveNote?.recreateMissingFile() } }
                )
                .padding(.top, Geist.Spacing.two)
            }
        }
    }

    /// Activity (recent captures) with an orange dot while queued captures
    /// have failed and need attention.
    private var activityButton: CaptureViewSection {
        CaptureViewSection {
            Button {
                dismissComposer()
                showsCaptureHistory = true
            } label: {
                Image(systemName: "clock")
                    .accessibilityLabel(activityAccessibilityLabel)
            }
            .buttonStyle(SignalCircleButtonStyle())
            .overlay(alignment: .topTrailing) {
                if activityPendingCount > 0 {
                    Group {
                        if activityPendingCount > 1 {
                            Text(verbatim: activityPendingCount > 99 ? "99+" : "\(activityPendingCount)")
                                .font(.custom("Geist-SemiBold", fixedSize: 10))
                                .foregroundStyle(Color.white)
                                .padding(.horizontal, 4)
                                .frame(minWidth: 16, minHeight: 16)
                                .background(Geist.warning, in: Capsule())
                                .overlay(Capsule().stroke(Geist.card, lineWidth: 2))
                                .offset(x: 2, y: -2)
                        } else {
                            Circle()
                                .fill(Geist.warning)
                                .frame(width: 9, height: 9)
                                .overlay(Circle().stroke(Geist.card, lineWidth: 2))
                                .offset(x: -6, y: 6)
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .accessibilityIdentifier("capture_activity")
        }
    }

    /// Mono destination path under the route pill. Tapping opens the one-off
    /// route picker, as the former route button did.
    private var routeDestinationLine: CaptureViewSection {
        CaptureViewSection {
            HStack(spacing: 6) {
                Button {
                    dismissComposer()
                    showsRoutePicker = true
                } label: {
                    HStack(spacing: 5) {
                        if viewModel.hasAnyRouteOverride {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        // Keep the note's filename and heading; shorten the
                        // vault/folder prefix first ("…/ 2026-11-01.md · ## Notes").
                        let candidates = Self.pathLineCandidates(routeDestinationPath)
                        ViewThatFits(in: .horizontal) {
                            ForEach(Array(candidates.dropLast().enumerated()), id: \.offset) { _, candidate in
                                routePathText(candidate).fixedSize(horizontal: true, vertical: false)
                            }
                            routePathText(candidates.last ?? routeDestinationPath)
                                .truncationMode(.head)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(verbatim: routeDestinationPath))
                        if viewModel.hasAnyRouteOverride {
                            SignalBadge(text: "Override")
                        }
                    }
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
                    .padding(.leading, 4)
                    .frame(minHeight: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Capture route \(routeLabel), \(viewModel.effectivePlacementLabel)")
                .disabled(!viewModel.canChangeCaptureRoute)

                if viewModel.hasAnyRouteOverride, viewModel.liveNote == nil {
                    Button {
                        viewModel.useVoxRouteDefaults()
                    } label: {
                        Image(systemName: "arrow.uturn.backward.circle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Geist.muted)
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Use Route destination defaults")
                    .disabled(!viewModel.canChangeCaptureRoute)
                }
                if viewModel.liveNotesEnabled {
                    Spacer(minLength: 4)
                    LiveNoteStatusPill(status: viewModel.liveNoteStatus)
                }
            }
        }
    }

    private func routePathText(_ text: String) -> CaptureViewSection {
        CaptureViewSection {
            Text(verbatim: text)
                .strikethrough(!vaultIsReachable && viewModel.selectedDestination != nil)
                .lineLimit(1)
        }
    }

    /// Progressively shorter forms of `Vault / Folder / note.md · ## Heading`:
    /// leading path components are replaced by "…" one at a time, so the
    /// filename and heading are the last to go.
    static func pathLineCandidates(_ line: String) -> [String] {
        let components = line.components(separatedBy: " / ")
        guard components.count > 1 else { return [line] }
        var candidates = [line]
        for dropped in 1..<components.count {
            candidates.append("…/ " + components[dropped...].joined(separator: " / "))
        }
        return candidates
    }

    private var routeDestinationPath: String {
        // Live Notes: the file the composer is editing, wherever it lives.
        if let relativePath = viewModel.liveNoteRelativePath {
            let vault = viewModel.liveNote.flatMap { session in
                viewModel.destinations.first(where: { $0.id == session.binding.destinationID })?.rootName
            }
            let parts = ([vault].compactMap { $0 }) + relativePath.split(separator: "/").map(String.init)
            return parts.joined(separator: " / ")
        }
        // The iPad sidebar editor header shows only the note path, as in
        // `Meetings / 2026-11-01.md`; the phone shows vault, path and heading.
        if layout == .regularSidebar,
           let preview = viewModel.resolvedDestinationPreview,
           let separator = preview.range(of: " / ") {
            return preview[separator.upperBound...]
                .split(separator: "/", omittingEmptySubsequences: true)
                .joined(separator: " / ")
        }
        return viewModel.resolvedDestinationDisplayLine
            ?? viewModel.resolvedDestinationPreview
            ?? routeLabel
    }

    private var captureOCRProgressBanner: CaptureViewSection {
        CaptureViewSection {
            // Capture states C: route progress sits under the header, above
            // the note, as on the board.
            if let progress = persistentRecorder.lastRouteProgress,
               !persistentRecorder.isAppRecordingSegmentActive {
                CaptureRouteProgressCard(
                    progress: progress,
                    keepTranscriptOnly: { persistentRecorder.dismissRouteProgress(keepTranscriptOnly: true) },
                    retrySummary: { Task { await persistentRecorder.retryRouteProcessing() } }
                )
                .overlay(alignment: .topTrailing) {
                    Button {
                        persistentRecorder.dismissRouteProgress(keepTranscriptOnly: false)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Geist.muted)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss route progress")
                }
                .padding(.horizontal, Geist.Spacing.four)
                .padding(.bottom, Geist.Spacing.two)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            if isExtractingText {
                QuickCaptureOCRProgress()
            } else if viewModel.isDescribingImages {
                QuickCaptureOCRProgress("Describing images on this device…")
            }
        }
    }

    private var keyboardGuidanceOverlay: CaptureViewSection {
        CaptureViewSection {
            if let guidance = keyboardReturnGuidance {
                keyboardReturnGuidanceBanner(guidance.phase)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: guidance.id) {
                        await dismissKeyboardReturnGuidance(after: .seconds(6), id: guidance.id)
                    }
            }
        }
    }

    private var captureErrorOverlay: CaptureViewSection {
        CaptureViewSection {
            if let message = captureErrorMessage {
                errorBanner(message)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
                    .padding(.bottom, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var fileExportOverlay: CaptureViewSection {
        CaptureViewSection {
            if let toast = fileExportToast {
                FileExportToastView(fileName: toast.url.lastPathComponent) {
                    openExportedFileInFiles(toast.url)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    private var sentToastOverlay: CaptureViewSection {
        CaptureViewSection {
            if showsSentToast {
                QuickCaptureSentToast(
                    offersUndo: sentUndoSnapshot?.offersUndo == true,
                    undo: restoreSentCaptureAsDraft
                )
            }
        }
    }

    private var draftLifecycleContent: CaptureViewSection {
        CaptureViewSection {
            captureContent
                .task {
                    await loadAndPresentRequestedInput()
                    handleCaptureNeedsUnlock(viewModel.needsCaptureUnlock)
                }
                .task(
                    id: InitialComposerFocusTaskID(
                        isPending: initialComposerFocusIsPending,
                        hasCompletedInitialLoad: hasCompletedInitialLoad,
                        defersForReleaseNotes: defersCaptureInputFocusForReleaseNotes
                    )
                ) {
                    await fulfillInitialComposerFocusIfReady()
                }
                .onChange(of: defersCaptureInputFocusForReleaseNotes) { _, isDeferring in
                    if isDeferring { dismissComposer() }
                }
                .onChange(of: viewModel.draft.text) { _, _ in
                    if !viewModel.hasLiveRecordedTranscriptPreview {
                        viewModel.scheduleDraftSave()
                    }
                }
                .onChange(of: viewModel.recordedTranscriptCaretOffset) { previous, caret in
                    followRecordedTranscriptCaret(from: previous, to: caret)
                }
                .onChange(of: viewModel.draft.voxID) { _, id in
                    viewModel.scheduleDraftSave()
                    if let id { selectedFlowId = id }
                }
                .onChange(of: viewModel.draft.destinationID) { _, _ in viewModel.scheduleDraftSave() }
                .onChange(of: viewModel.draft.destinationSelectionMode) { _, _ in viewModel.scheduleDraftSave() }
                .onChange(of: viewModel.draft.entryTemplateID) { _, _ in viewModel.scheduleDraftSave() }
                .onChange(of: viewModel.draft.placementOverride) { _, _ in viewModel.scheduleDraftSave() }
                .onChange(of: viewModel.draft.relativeNotePathOverride) { _, _ in viewModel.scheduleDraftSave() }
                .onChange(of: viewModel.errorMessage) { _, message in
                    guard let message else { return }
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
                .onChange(of: viewModel.needsCaptureUnlock) { _, needsUnlock in
                    handleCaptureNeedsUnlock(needsUnlock)
                }
                .onChange(of: viewModel.lastReceipt) { _, receipt in
                    guard receipt != nil else { return }
                    if !hasSavedFirstNote {
                        hasSavedFirstNote = true
                        if !setupChoseFolder {
                            firstNoteReceipt = receipt
                            dismissComposer()
                        }
                    }
                    usageTracker.reload()
                    ReviewPromptManager.shared.recordSuccessfulCapture(
                        totalCaptureCount: usageTracker.successfulCapturesUsed
                    )
                    Task { await presentSentToast(for: receipt) }
                }
                .onChange(of: selectedPhotos) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await importPhotos(items, prefix: "photo") }
                }
                .onChange(of: selectedScreenshots) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await importScreenshots(items) }
                }
                .onChange(of: selectedOCRPhotos) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await importOCRPhotos(items) }
                }
                .onChange(of: viewModel.requestedInput) { _, input in
                    handleRequestedInputChange(input)
                }
        }
    }

    private var recordingLifecycleContent: CaptureViewSection {
        CaptureViewSection {
            draftLifecycleContent
                .onAppear(perform: prepareRecordingFeatures)
                .onChange(of: pendingKeyboardLaunch) { _, isPending in
                    if isPending { consumePendingKeyboardLaunchIfNeeded() }
                }
                .onChange(of: pendingWidgetRecord) { _, isPending in
                    if isPending { consumePendingWidgetRecordIfNeeded() }
                }
                .onChange(of: persistentRecorder.needsUnlock) { _, needs in
                    handleRecorderNeedsUnlock(needs)
                }
                .onChange(of: persistentRecorder.lastFileExportEvent) { _, event in
                    handleFileExportEvent(event)
                }
                .onChange(of: persistentRecorder.lastURLDeliveryEvent) { _, event in
                    handleURLDeliveryEvent(event)
                }
                .onChange(of: URLDeliveryRuntime.coordinator.lastError) { _, message in
                    if let message, persistentRecorder.lastError == nil {
                        persistentRecorder.lastError = String(localized: "URL delivery needs attention. Open URL Deliveries in Settings. \(message)")
                    }
                }
                .onChange(of: persistentRecorder.lastSentAudioUndoSnapshot) { _, observedSnapshot in
                    guard let observedSnapshot,
                          let snapshot = persistentRecorder.consumeSentAudioUndoSnapshot(
                            id: observedSnapshot.id
                          ) else { return }
                    Task { await presentSentToast(replacingWith: snapshot) }
                }
                .onChange(of: persistentRecorder.lastError) { _, message in
                    guard let message else { return }
                    UIAccessibility.post(notification: .announcement, argument: message)
                }
                .onChange(of: persistentRecorder.isTranscribing) { _, isTranscribing in
                    handleTranscribingChange(isTranscribing)
                }
                .onChange(of: persistentRecorder.isSegmentActive) { _, isActive in
                    if !isActive { watchRecordingPipeline.resume() }
                }
                .onChange(of: watchRecordingPipeline.lastDeliveredRecordingID) { _, recordingID in
                    guard recordingID != nil else { return }
                    usageTracker.reload()
                    Task { await viewModel.refreshHistory() }
                    Task { await presentSentToast() }
                }
        }
    }

    private var lifecycleContent: CaptureViewSection {
        CaptureViewSection {
            recordingLifecycleContent
                .sheet(item: $firstNoteDocument) { document in
                    FirstNoteDocumentPreview(document: document)
                }
                .sheet(isPresented: $showsFirstNoteFolderPicker) {
                    CaptureFolderPicker(initialDirectoryURL: nil, onPick: { url in
                        showsFirstNoteFolderPicker = false
                        Task { await saveFirstNoteFolder(url) }
                    }, onCancel: { showsFirstNoteFolderPicker = false })
                }
                .alert("Microphone access is off", isPresented: $showsMicrophoneSettings) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Allow microphone access in Settings to record. You can still type and save notes.")
                }
                .task(id: fileExportToast?.id) { await dismissExportToastAfterDelay() }
                .onChange(of: scenePhase) { _, phase in handleScenePhaseChange(phase) }
                .onChange(of: persistentRecorder.isAppRecordingSegmentActive) { _, isActive in
                    handleAppRecordingActiveChange(isActive)
                }
                .task(id: viewModel.selectedDestination?.rootBookmark) { refreshVaultReachability() }
                .task { await refreshPendingCaptureCountWhileVisible() }
                .onChange(of: viewModel.voxProfiles) { _, _ in reloadPresetsIfDefaultsChanged() }
                .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
                    .receive(on: RunLoop.main)) { _ in
                    reloadPresetsIfDefaultsChanged()
                }
                .onReceive(NotificationCenter.default.publisher(for: .captureInboxDecisionRequired)) { _ in
                    Task { await viewModel.processPendingInbox() }
                }
                .onDisappear(perform: handleCaptureDisappear)
        }
    }

    private var mediaPickerContent: CaptureViewSection {
        CaptureViewSection {
            lifecycleContent
                .photosPicker(
                    isPresented: $showsPhotoPicker,
                    selection: $selectedPhotos,
                    maxSelectionCount: 10,
                    matching: .images
                )
                .photosPicker(
                    isPresented: $showsScreenshotPicker,
                    selection: $selectedScreenshots,
                    maxSelectionCount: 10,
                    matching: .screenshots
                )
                .photosPicker(
                    isPresented: $showsOCRPhotoPicker,
                    selection: $selectedOCRPhotos,
                    maxSelectionCount: 10,
                    selectionBehavior: .ordered,
                    matching: .images
                )
                .sheet(isPresented: $showsFileImporter) {
                    CaptureFilePicker(
                        contentTypes: [.data],
                        allowsMultipleSelection: true,
                        onPick: { urls in
                            showsFileImporter = false
                            importFiles(urls)
                        },
                        onCancel: {
                            showsFileImporter = false
                            focusComposer()
                        }
                    )
                    .ignoresSafeArea()
                }
        }
    }

    private var locationDecisionContent: CaptureViewSection {
        CaptureViewSection {
            mediaPickerContent
                .confirmationDialog(
                    "Location",
                    isPresented: Binding(
                        get: { viewModel.locationDecision != nil },
                        set: { if !$0 { Task { await viewModel.cancelUnavailableLocation() } } }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Retry") { Task { await viewModel.retryUnavailableLocation() } }
                    Button("Send Without Location") {
                        Task { await viewModel.sendWithoutUnavailableLocation(alwaysForPreset: false) }
                    }
                    Button("Always Send Without Location for This Route") {
                        Task { await viewModel.sendWithoutUnavailableLocation(alwaysForPreset: true) }
                    }
                    Button("Cancel", role: .cancel) {
                        discardSentUndoSnapshot()
                        Task { await viewModel.cancelUnavailableLocation() }
                    }
                } message: {
                    Text("Vox.md could not get an origin-time location. Your draft is preserved.")
                }
                .confirmationDialog(
                    inboxLocationDecisionTitle,
                    isPresented: Binding(
                        get: { viewModel.inboxLocationDecision != nil },
                        set: { _ in }
                    ),
                    titleVisibility: .visible
                ) {
                    Button("Send Without Location") {
                        Task { await viewModel.sendInboxRequestWithoutLocation() }
                    }
                    Button("Always Send Without Location for This Route") {
                        Task { await viewModel.sendInboxRequestWithoutLocation(alwaysForPreset: true) }
                    }
                    Button("Cancel and Discard Capture", role: .destructive) {
                        Task { await viewModel.discardInboxLocationRequest() }
                    }
                } message: {
                    Text(inboxLocationDecisionMessage)
                }
        }
    }

    private var presetSwitchDecisionContent: CaptureViewSection {
        CaptureViewSection {
            locationDecisionContent
                .alert(
                    "Switch Route?",
                    isPresented: Binding(
                        get: { viewModel.pendingPresetSwitch != nil },
                        set: { _ in }
                    ),
                    presenting: viewModel.pendingPresetSwitch
                ) { pending in
                    Button("Switch Route") {
                        Task { await viewModel.confirmPresetSwitch(id: pending.id) }
                    }
                    Button("Cancel", role: .cancel) {
                        viewModel.cancelPresetSwitch(id: pending.id)
                    }
                } message: { pending in
                    Text("Use \(pending.presetName) for this draft? Your text and attachments will be kept; one-off routing will reset.")
                }
        }
    }

    private var navigationSheetContent: CaptureViewSection {
        CaptureViewSection {
            presetSwitchDecisionContent
                .sheet(isPresented: $showsCaptureHistory) {
                    ActivityFeedView(
                        viewModel: viewModel,
                        persistentRecorder: persistentRecorder,
                        onNewCapture: {
                            showsCaptureHistory = false
                            focusComposer()
                        }
                    )
                    .environment(transcriptStore)
                    .environment(watchRecordingPipeline)
                }
                .sheet(isPresented: $showsVaultFiles) {
                    VaultFilesView(viewModel: viewModel) {
                        showsVaultFiles = false
                    }
                }
                .sheet(isPresented: $showsWatchRecordingQueue) {
                    WatchRecordingQueueView(pipeline: watchRecordingPipeline)
                }
                .sheet(isPresented: $showsRoutePicker, onDismiss: reloadFlows) {
                    CaptureRoutePickerView(viewModel: viewModel)
                }
                .sheet(isPresented: $showsDueDate) {
                    CaptureDueDateSheet { date, includesTime in
                        let token = insertionFormatter.dueDateToken(for: date, includeTime: includesTime)
                        applyComposerCommand(.replaceSelection(with: token))
                        focusComposer()
                    }
                }
                .sheet(isPresented: $showsInternalLinks) {
                    CaptureInternalLinkPicker(rootURL: viewModel.selectedRootURL()) { markdown in
                        applyComposerCommand(.replaceSelection(with: markdown))
                        focusComposer()
                    }
                }
                .sheet(isPresented: $showsPaywall) {
                    PaywallView(context: paywallContext)
                        .environment(usageTracker)
                        .environment(storeManager)
                }
                .fileImporter(
                    isPresented: $showsAudioImporter,
                    allowedContentTypes: [.audio, .movie],
                    allowsMultipleSelection: false,
                    onCompletion: handleAudioImport
                )
        }
    }

    private var cameraSheetContent: CaptureViewSection {
        CaptureViewSection {
            navigationSheetContent
                .sheet(isPresented: $showsCamera) {
                    CaptureCameraPicker(
                        onCapture: { data in
                            showsCamera = false
                            Task {
                                guard viewModel.requireCaptureRouteAvailable() else { return }
                                isProcessingMedia = true
                                await viewModel.stageImage(
                                    data: data,
                                    filename: "camera-\(captureTimestamp()).jpg",
                                    contentTypeIdentifier: UTType.jpeg.identifier
                                )
                                isProcessingMedia = false
                                focusComposer()
                            }
                        },
                        onCancel: {
                            showsCamera = false
                            focusComposer()
                        }
                    )
                    .ignoresSafeArea()
                }
                .sheet(isPresented: $showsScanner) {
                    CaptureDocumentScanner(
                        onScan: { pages in
                            showsScanner = false
                            Task {
                                await processScan(pages)
                                focusComposer()
                            }
                        },
                        onCancel: {
                            showsScanner = false
                            focusComposer()
                        },
                        onError: { error in
                            showsScanner = false
                            viewModel.errorMessage = error.localizedDescription
                        }
                    )
                    .ignoresSafeArea()
                }
        }
    }

    private var drawingSheetContent: CaptureViewSection {
        CaptureViewSection {
            cameraSheetContent
                .sheet(isPresented: $showsJournalPageCapture) {
                    CaptureManualJournalPages(
                        maxPageCount: 10,
                        onCapture: { pages in
                            showsJournalPageCapture = false
                            Task { await processOCRScan(pages) }
                        },
                        onCancel: {
                            showsJournalPageCapture = false
                            focusComposer()
                        }
                    )
                }
                .sheet(isPresented: $showsSketch) {
                    CaptureSketchEditor(
                        onSave: { drawing, preview in
                            showsSketch = false
                            Task {
                                guard viewModel.requireCaptureRouteAvailable() else { return }
                                isProcessingMedia = true
                                await viewModel.stageSketch(drawingData: drawing, previewData: preview)
                                isProcessingMedia = false
                                focusComposer()
                            }
                        },
                        onCancel: {
                            showsSketch = false
                            focusComposer()
                        }
                    )
                }
        }
    }

    private var attachSheetContent: CaptureViewSection {
        CaptureViewSection {
            drawingSheetContent
                .sheet(isPresented: $showsAttachSheet, onDismiss: runPendingAttachAction) {
                    CaptureAttachSheet(
                        isProcessingMedia: isProcessingMedia,
                        canExtractText: canExtractJournalText,
                        isAvailable: isAttachActionAvailable,
                        choose: { action in
                            pendingAttachAction = action
                            showsAttachSheet = false
                        },
                        routeName: selectedFlow.visibleName ?? selectedFlow.accessibilityName,
                        destinationPath: routeDestinationPath,
                        recentPhotos: recentPhotos,
                        pickRecentPhotos: { assets in
                            showsAttachSheet = false
                            Task { await attachRecentPhotos(assets) }
                        },
                        paste: { providers in
                            showsAttachSheet = false
                            Task { await attachPastedItems(providers) }
                        }
                    )
                }
                .sheet(isPresented: $showsVaultRegrantPicker) {
                    CaptureFolderPicker(
                        initialDirectoryURL: nil,
                        onPick: { url in
                            showsVaultRegrantPicker = false
                            regrantVaultAccess(folderURL: url)
                        },
                        onCancel: { showsVaultRegrantPicker = false }
                    )
                    .ignoresSafeArea()
                }
                .sheet(isPresented: $showsWhiteboardScanner) {
                    CaptureDocumentScanner(
                        onScan: { pages in
                            showsWhiteboardScanner = false
                            Task { await stageWhiteboardImages(pages) }
                        },
                        onCancel: { showsWhiteboardScanner = false },
                        onError: { error in
                            showsWhiteboardScanner = false
                            viewModel.errorMessage = error.localizedDescription
                        }
                    )
                    .ignoresSafeArea()
                }
                .sheet(isPresented: $showsWhiteboardCamera) {
                    CaptureCameraPicker(
                        onCapture: { data in
                            showsWhiteboardCamera = false
                            Task { await stageWhiteboardImages([data]) }
                        },
                        onCancel: { showsWhiteboardCamera = false }
                    )
                    .ignoresSafeArea()
                }
        }
    }

    private var presentedContent: CaptureViewSection {
        CaptureViewSection {
            attachSheetContent
                .alert("Capture Link", isPresented: $showsLinkPrompt) {
                    TextField("https://example.com", text: $linkText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("Cancel", role: .cancel) { linkText = "" }
                    Button("Add") {
                        let value = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
                        linkText = ""
                        if let url = URL(string: value) {
                            Task { await viewModel.addURL(url) }
                        } else {
                            viewModel.errorMessage = String(localized: "Enter a valid link.")
                        }
                    }
                } message: {
                    Text("The link stays in your durable draft until the note is captured.")
                }
        }
    }

    /// One-tap pause/resume without opening the detail sheet.
    private var voiceCapturePauseToggle: CaptureViewSection {
        CaptureViewSection {
            Group {
                if persistentRecorder.isAppRecordingSegmentActive {
                    Button {
                        persistentRecorder.toggleInAppSegmentPause()
                    } label: {
                        Image(systemName: persistentRecorder.isSegmentPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(SignalCircleButtonStyle(
                        diameter: 56,
                        filled: persistentRecorder.isSegmentPaused ? Geist.accent : Geist.Palette.gray200
                    ))
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(
                        persistentRecorder.isSegmentPaused
                            ? String(localized: "Resume recording")
                            : String(localized: "Pause recording")
                    )
                    .accessibilityIdentifier("capture_recording_pause_compact")
                }
            }
            .animation(.easeInOut(duration: 0.18), value: persistentRecorder.isSegmentPaused)
        }
    }

    private var voiceCaptureButton: CaptureViewSection {
        CaptureViewSection {
            // One container keeps the press gesture alive while the label swaps
            // between idle, push-to-talk and recording presentations.
            ZStack {
                if persistentRecorder.isAppRecordingSegmentActive {
                    activeVoiceCaptureButtonLabel
                } else {
                    idleVoiceCaptureButtonLabel
                }
            }
            .frame(minWidth: 36, minHeight: 36)
            .contentShape(Capsule(style: .continuous))
            .gesture(voiceCaptureGesture)
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(recordingStatusTitle)
            .accessibilityHint("Tap to start or stop. Long-press for detailed recording controls.")
            .accessibilityAction { handleVoiceCaptureTap() }
            .accessibilityAction(named: "Show detailed recording controls") {
                presentVoiceCaptureDetails()
            }
            .accessibilityAction(
                named: persistentRecorder.isSegmentPaused ? String(localized: "Resume") : String(localized: "Pause")
            ) {
                persistentRecorder.toggleInAppSegmentPause()
            }
            .accessibilityIdentifier("capture_voice_recording")
            .opacity(isProcessingMedia ? 0.35 : 1)
        }
    }

    private var activeVoiceCaptureButtonLabel: CaptureViewSection {
        CaptureViewSection {
            CaptureStopRingLabel()
        }
    }

    private var idleVoiceCaptureButtonLabel: CaptureViewSection {
        CaptureViewSection {
            CaptureSpeakCapsuleLabel(
                title: persistentRecorder.isAppRecordingTranscribing
                    ? String(localized: "Transcribing")
                    : String(localized: "Speak"),
                systemImage: isCaptureReadOnly ? "lock.fill" : "mic",
                modeSymbol: persistentRecorder.isAppRecordingTranscribing || isCaptureReadOnly
                    ? nil : recordingResultModeSymbol,
                isDimmed: (isMicrophoneDenied || isCaptureReadOnly) && !isLocalizationScreenshot,
                showsProgress: persistentRecorder.isAppRecordingTranscribing
            )
            .scaleEffect(isSpeakPressed && !reduceMotion ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: isSpeakPressed)
            .accessibilityHidden(true)
        }
    }

    /// Trial ended (no paid access): capture stays readable but recording and
    /// sending need a plan. The Speak bar is shown disabled; tapping it opens
    /// the plans sheet.
    private var isCaptureReadOnly: Bool {
        usageTracker.isAtLimit && !isLocalizationScreenshot
    }

    private var isMicrophoneDenied: Bool {
        AVAudioApplication.shared.recordPermission == .denied
    }

    /// Compact indicator pinned to the mic control showing the persisted
    /// recording result mode — `text.badge.plus` when stopping adds the
    /// transcript to the Capture draft, `paperplane.fill` when it runs the
    /// selected preset and sends immediately — so users can see what stop
    /// will do before pressing it.
    private var recordingResultModeSymbol: String {
        recordingMode == .draft ? "text.badge.plus" : "paperplane.fill"
    }

    /// Tap starts or stops recording; a long press opens the detailed
    /// recording controls. There is no hold-to-talk.
    private var voiceCaptureGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { _ in beginSpeakPress() }
            .onEnded { _ in endSpeakPress() }
    }

    private func beginSpeakPress() {
        guard !isSpeakPressed else { return }
        isSpeakPressed = true
        speakLongPressFired = false
        speakLongPressTask?.cancel()
        speakLongPressTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, isSpeakPressed else { return }
            speakLongPressFired = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            presentVoiceCaptureDetails()
        }
    }

    private func endSpeakPress() {
        isSpeakPressed = false
        speakLongPressTask?.cancel()
        speakLongPressTask = nil
        guard !speakLongPressFired else {
            speakLongPressFired = false
            return
        }
        handleVoiceCaptureTap()
    }

    private func handleAppRecordingActiveChange(_ isActive: Bool) {
        if isActive {
            dismissComposer()
        } else {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }

    private func presentVoiceCaptureDetails() {
        guard !isProcessingMedia else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
            showsVoiceCaptureDetails = true
        }
    }

    private var voiceCaptureDetailsBar: CaptureViewSection {
        CaptureViewSection {
            VStack(spacing: 0) {
                recordingDetailsHeader
                GeistDivider()
                recordingDetailsOptions
            }
            .background(Geist.card, in: RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
            .padding(.horizontal, Geist.Spacing.four)
            .padding(.top, Geist.Spacing.two)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityIdentifier("capture_recording_details")
        }
    }

    private var recordingDetailsHeader: CaptureViewSection {
        CaptureViewSection {
            HStack(spacing: Geist.Spacing.three) {
                Image(systemName: recordingDetailsIcon)
                    .foregroundStyle(recordingDetailsColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recordingDetailsTitle)
                        .font(Geist.label())
                        .foregroundStyle(Geist.text)
                    Text(recordingDetailsSubtitle)
                        .font(Geist.caption(.caption2))
                        .foregroundStyle(Geist.muted)
                        .lineLimit(1)
                }

                Spacer(minLength: Geist.Spacing.two)
                voiceCapturePauseButton
                recordingPrimaryButton

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsVoiceCaptureDetails = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hide detailed recording controls")
            }
            .padding(.horizontal, Geist.Spacing.three)
            .padding(.vertical, Geist.Spacing.two)
        }
    }

    private var recordingDetailsOptions: CaptureViewSection {
        CaptureViewSection {
            VStack(alignment: .leading, spacing: Geist.Spacing.three) {
                Picker("Recording result", selection: recordingModeSelection) {
                    Text("Add to Draft").tag(CaptureRecordingMode.draft)
                    Text("Send Immediately").tag(CaptureRecordingMode.preset)
                }
                .pickerStyle(.segmented)
                .disabled(recordingOptionsAreLocked)
                .accessibilityIdentifier("capture_recording_mode")

                recordingDestinationOptions
                CaptureRecordingControlHelp(isPresented: $showsRecordingControlHelp)
                recordingDetailsStatus
            }
            .padding(Geist.Spacing.three)
        }
    }

    private var recordingDestinationOptions: CaptureViewSection {
        CaptureViewSection {
            HStack(spacing: Geist.Spacing.three) {
                Menu {
                    ForEach(enabledFlows) { flow in
                        presetMenuButton(flow)
                    }
                } label: {
                    HStack(spacing: 6) {
                        CapturePresetIconView(symbolName: selectedFlow.symbolName, emoji: selectedFlow.emoji)
                        if let name = selectedFlow.visibleName {
                            Text(name)
                                .lineLimit(1)
                        }
                    }
                    .font(Geist.label())
                    .padding(.horizontal, Geist.Spacing.three)
                    .frame(height: Geist.ControlHeight.medium)
                    .background(Geist.bg, in: Capsule(style: .continuous))
                }
                .disabled(!viewModel.canSelectCapturePreset)
                .accessibilityLabel("Route \(selectedFlow.accessibilityName)")

                if recordingMode == .draft {
                    Toggle(isOn: $attachRecordingAudio) {
                        Label("Audio", systemImage: "paperclip")
                            .font(Geist.caption())
                    }
                    .toggleStyle(.switch)
                    .tint(Geist.Palette.blue700)
                    .disabled(recordingOptionsAreLocked)
                    .accessibilityLabel("Attach audio to Capture")
                    .accessibilityHint(CaptureRecordingControlSemantics.audioHelp)
                    .help(CaptureRecordingControlSemantics.audioHelp)
                }

                Spacer(minLength: 0)

                Button {
                    showsAudioImporter = true
                } label: {
                    Image(systemName: "waveform.badge.plus")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(recordingOptionsAreLocked)
                .accessibilityLabel("Import audio or video")
                .accessibilityHint(CaptureRecordingControlSemantics.importAudioHelp)
                .help(CaptureRecordingControlSemantics.importAudioHelp)
                .accessibilityIdentifier("capture_audio_import")

                Button(action: togglePersistentListening) {
                    Image(systemName: persistentRecorder.isListening ? "headphones.circle.fill" : "headphones.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(persistentRecorder.isListening ? Geist.Palette.blue700 : Geist.text)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .disabled(recordingOptionsAreLocked)
                .accessibilityLabel(
                    CaptureRecordingControlSemantics.keyboardListeningLabel(
                        isListening: persistentRecorder.isListening
                    )
                )
                .accessibilityHint(
                    CaptureRecordingControlSemantics.keyboardListeningActionHint(
                        isListening: persistentRecorder.isListening
                    )
                )
                .help(CaptureRecordingControlSemantics.keyboardListeningHelp)
                .accessibilityIdentifier("capture_keyboard_listening")
            }

        }
    }

    private var recordingDetailsStatus: CaptureViewSection {
        CaptureViewSection {
            if !usageTracker.hasUnlocked {
                recordingUsageMeter
            }

            if let phase = keyboardLaunchPhase {
                keyboardListeningStatusRow(phase)
            }

            if let result = persistentRecorder.lastTranscriptionResult {
                HStack(spacing: Geist.Spacing.two) {
                    Image(systemName: lastStartedRecordingMode == .draft ? "text.badge.plus" : "checkmark.circle.fill")
                    Text(
                        lastStartedRecordingMode == .draft
                            ? String(localized: "Transcript added to Capture")
                            : String(localized: "Sent with Route")
                    )
                    .font(Geist.caption())
                    Spacer()
                    Button("Copy") { UIPasteboard.general.string = result }
                        .font(Geist.caption())
                }
                .foregroundStyle(Geist.muted)

                if let reason = persistentRecorder.lastSpeakerDiarizationSkipReason {
                    Label(reason.displayText, systemImage: "exclamationmark.triangle")
                        .font(Geist.caption(.caption2))
                        .foregroundStyle(Geist.error)
                        .accessibilityIdentifier("speaker_diarization_skip_reason")
                }
            }
        }
    }

    private var voiceCapturePauseButton: CaptureViewSection {
        CaptureViewSection {
            if persistentRecorder.isAppRecordingSegmentActive {
                Button {
                    persistentRecorder.toggleInAppSegmentPause()
                } label: {
                    Label(
                        persistentRecorder.isSegmentPaused
                            ? String(localized: "Resume")
                            : String(localized: "Pause"),
                        systemImage: persistentRecorder.isSegmentPaused ? "play.fill" : "pause.fill"
                    )
                }
                .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
                .accessibilityIdentifier("capture_recording_pause")
            }
        }
    }

    private var recordingPrimaryButton: CaptureViewSection {
        CaptureViewSection {
            if persistentRecorder.isAppRecordingSegmentActive {
                Button(action: { persistentRecorder.stopInAppSegment() }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(GeistButtonStyle(variant: .destructive, size: .small))
                .accessibilityIdentifier("capture_recording_stop")
            } else {
                Button(action: startInlineRecording) {
                    Label(
                        usageTracker.isAtLimit ? String(localized: "Unlock") : String(localized: "Record"),
                        systemImage: usageTracker.isAtLimit ? "lock.fill" : "mic.fill"
                    )
                }
                .buttonStyle(GeistButtonStyle(variant: usageTracker.isAtLimit ? .destructive : .primary, size: .small))
                .accessibilityIdentifier("capture_recording_start")
            }
        }
    }

    private var recordingUsageMeter: CaptureViewSection {
        CaptureViewSection {
            Button(action: { presentPaywall(context: .usageMeter) }) {
                HStack(spacing: Geist.Spacing.two) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Geist.Palette.gray200).frame(height: 2)
                            Rectangle()
                                .fill(usageTracker.isAtLimit ? Geist.error : Geist.text)
                                .frame(width: geometry.size.width * usageTracker.fractionUsed, height: 2)
                        }
                    }
                    .frame(height: 2)
                    Text(recordingUsageLabel)
                        .font(Geist.mono())
                        .foregroundStyle(usageTracker.isAtLimit ? Geist.error : Geist.muted)
                        .fixedSize()
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func keyboardListeningStatusRow(_ phase: KeyboardLaunchPhase) -> CaptureViewSection {
        CaptureViewSection {
            HStack(spacing: Geist.Spacing.two) {
                switch phase {
                case .starting:
                    ProgressView().controlSize(.small)
                    Text("Preparing keyboard listening…")
                case .ready:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Geist.Palette.blue700)
                    Text("Keyboard listening is ready")
                case .error:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Geist.error)
                    Text("Keyboard listening could not start")
                }
                Spacer()
            }
            .font(Geist.caption())
        }
    }

    private func keyboardReturnGuidanceBanner(_ phase: KeyboardLaunchPhase) -> CaptureViewSection {
        CaptureViewSection {
            HStack(alignment: .top, spacing: Geist.Spacing.three) {
                Group {
                    switch phase {
                    case .starting:
                        ProgressView()
                            .controlSize(.small)
                    case .ready:
                        Image(systemName: "keyboard.fill")
                            .foregroundStyle(Geist.Palette.blue700)
                    case .error:
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Geist.error)
                    }
                }
                .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: Geist.Spacing.one) {
                    Text(keyboardReturnGuidanceTitle(for: phase))
                        .font(Geist.label())
                        .foregroundStyle(Geist.text)
                    Text(keyboardReturnGuidanceMessage(for: phase))
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Geist.Spacing.two)

                Button {
                    withAnimation(.easeIn(duration: 0.18)) {
                        keyboardReturnGuidance = nil
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss keyboard listening message")
            }
            .padding(Geist.Spacing.three)
            .background(phase == .error ? Geist.Palette.red100 : Geist.Palette.blue100)
            .overlay {
                RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous)
                    .stroke(
                        phase == .error ? Geist.Palette.red400 : Geist.Palette.blue400,
                        lineWidth: 1
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous))
            .accessibilityIdentifier("keyboard_return_guidance")
        }
    }

    private func keyboardReturnGuidanceTitle(for phase: KeyboardLaunchPhase) -> String {
        switch phase {
        case .starting:
            return String(localized: "Turning on keyboard listening")
        case .ready:
            return String(localized: "Keyboard listening is on")
        case .error:
            return String(localized: "Keyboard listening couldn't start")
        }
    }

    private func keyboardReturnGuidanceMessage(for phase: KeyboardLaunchPhase) -> String {
        switch phase {
        case .starting:
            return String(localized: "Vox.md opened to enable voice input. When it’s ready, return to your keyboard to use it.")
        case .ready:
            return String(localized: "Return to your keyboard to start using voice input.")
        case .error:
            return String(localized: "Check microphone access, then try again from your keyboard.")
        }
    }

    private func handleVoiceCaptureTap() {
        if persistentRecorder.isAppRecordingSegmentActive {
            // Never block stopping an app-owned recording because unrelated media
            // work happens to be finishing in the draft.
            persistentRecorder.stopInAppSegment()
        } else if !persistentRecorder.isSegmentActive,
                  !isProcessingMedia {
            startInlineRecording()
        }
    }

    private var canExtractJournalText: Bool {
        !persistentRecorder.isSegmentActive
            && !persistentRecorder.isTranscribing
            && !watchRecordingPipeline.isProcessing
            && !viewModel.hasLiveRecordedTranscriptPreview
    }

    private func requireIdleVoiceCaptureForOCR() -> Bool {
        guard canExtractJournalText else {
            viewModel.errorMessage = String(
                localized: "Finish the current voice capture before extracting journal text."
            )
            return false
        }
        return true
    }

    private var recordingOptionsAreLocked: Bool {
        !viewModel.canChangeCaptureRoute
    }

    private var recordingUsageLabel: String {
        usageTracker.isAtLimit
            ? String(localized: "Limit reached · Unlock")
            : String(localized: "Choose a plan")
    }

    private var captureControls: CaptureViewSection {
        CaptureViewSection {
            VStack(spacing: 0) {
                if showsVoiceCaptureDetails, !usesInlineRecordingDock {
                    voiceCaptureDetailsBar
                }
                if isFindingLocation || viewModel.isResolvingLocation || persistentRecorder.isResolvingLocation {
                    locationProgressBar
                }
                entryLocationTokenHintSection
                if layout == .compact, canExpandWindow, !composerIsFocused,
                   !persistentRecorder.isAppRecordingSegmentActive {
                    AdaptiveExpandHint(kind: .capture)
                        .padding(.horizontal, Geist.Spacing.four)
                        .padding(.top, Geist.Spacing.three)
                }
                if isMicrophoneDenied, !composerIsFocused, !isLocalizationScreenshot,
                   !persistentRecorder.isAppRecordingSegmentActive {
                    CaptureMicrophoneOffCard(openSettings: openAppSettings)
                        .padding(.horizontal, Geist.Spacing.four)
                        .padding(.top, Geist.Spacing.three)
                }
                // CaptureRestActions board: the route's quick-action row is
                // always there, resting bare above Attach / Speak / Send.
                // While typing it sits on the keyboard as a band with a
                // keyboard-down button; Attach / Speak / Send stay below it.
                if usesInlineRecordingDock {
                    // Speak transforms the footer into the recording dock;
                    // the words stream into the editor at the cursor.
                    liveRecordingDock
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    if layout == .compact {
                        captureQuickActionsBar
                    }
                    captureActionBar
                }
            }
            .animation(
                reduceMotion ? nil : .easeInOut(duration: 0.22),
                value: usesInlineRecordingDock
            )
            .background(Geist.bg)
            // Sampled here, not on the Speak button: the phone dock replaces
            // that button while recording and its waveform needs the levels.
            .task(id: persistentRecorder.isAppRecordingSegmentActive) {
                await updateRecordingAudioLevels()
            }
        }
    }

    /// The route's quick actions: resting above the footer, or on the keyboard
    /// while typing.
    private var captureQuickActionsBar: CaptureViewSection {
        quickActionsToolbar(isInline: false, isResting: !composerIsFocused)
    }

    /// `isInline` places the row in the regular-width editor header instead of
    /// above the keyboard; its "•••" panel then opens as a popover.
    private func quickActionsToolbar(isInline: Bool, isResting: Bool = false) -> CaptureViewSection {
        CaptureViewSection {
            CaptureEditorToolbar(
                command: handleToolbarCommand,
                showDueDate: { showsDueDate = true },
                insertLocation: insertCurrentLocation,
                showSketch: { showsSketch = true },
                showCamera: { showsCamera = true },
                showPhotos: { showsPhotoPicker = true },
                showScreenshots: { showsScreenshotPicker = true },
                showLinkPrompt: { showsLinkPrompt = true },
                showFiles: presentFileImporter,
                showScan: { showsScanner = VNDocumentCameraViewController.isSupported },
                captureTextPages: {
                    showsJournalPageCapture = UIImagePickerController.isSourceTypeAvailable(.camera)
                },
                chooseTextPhotos: { showsOCRPhotoPicker = true },
                canExtractText: canExtractJournalText,
                canCaptureTextPages: UIImagePickerController.isSourceTypeAvailable(.camera),
                isProcessingMedia: isProcessingMedia,
                isFindingLocation: isFindingLocation,
                preferences: captureToolbarPreferences,
                dismissKeyboard: toggleKeyboard,
                routeID: selectedFlow.id,
                presentAllActionsInKeyboardArea: isInline ? nil : { panel in
                    composerController.setInputPanel(panel)
                },
                isInline: isInline,
                isResting: isResting
            )
        }
    }

    /// Phones record in place: the footer becomes `liveRecordingDock`.
    private var usesInlineRecordingDock: Bool {
        layout == .compact && persistentRecorder.isAppRecordingSegmentActive
    }

    private var liveRecordingDock: CaptureViewSection {
        CaptureViewSection {
            CaptureLiveRecordingDock(
                engineLabel: persistentRecorder.segmentEngineLabel,
                errorMessage: captureErrorMessage,
                duration: formatRecordingDuration(persistentRecorder.segmentDuration, padded: true),
                isPaused: persistentRecorder.isSegmentPaused,
                levels: recordingAudioLevels,
                isDraftMode: Binding(
                    get: { recordingMode == .draft },
                    set: { switchActiveRecordingMode(to: $0 ? .draft : .preset) }
                ),
                canSnapWhiteboard: UIImagePickerController.isSourceTypeAvailable(.camera)
                    || VNDocumentCameraViewController.isSupported,
                discard: discardActiveRecording,
                stop: { persistentRecorder.stopInAppSegment() },
                togglePause: { persistentRecorder.toggleInAppSegmentPause() },
                markMoment: markRecordingMoment,
                addTask: { viewModel.insertRecordingActionLine("- [ ] ") },
                snapWhiteboard: snapWhiteboardDuringRecording,
                isKeyboardVisible: composerIsFocused,
                dismissKeyboard: dismissComposer,
                liveNoteLine: viewModel.liveNoteRecordingLine?.text,
                liveNoteLineIsLive: viewModel.liveNoteRecordingLine?.isLive ?? false
            )
        }
    }

    /// Full-screen dark live recording surface for tap-to-record sessions on
    /// larger windows (iPad, a propped Duo); phones use `liveRecordingDock`.
    private var liveRecordingScreen: CaptureViewSection {
        CaptureViewSection {
            if persistentRecorder.isAppRecordingSegmentActive, layout != .compact {
                CaptureLiveRecordingScreen(
                    routeName: selectedFlow.visibleName ?? selectedFlow.accessibilityName,
                    routeSymbolName: selectedFlow.symbolName,
                    routeEmoji: selectedFlow.emoji,
                    routeTone: SignalRouteTileTone.forRoute(id: selectedFlow.id),
                    engineLabel: persistentRecorder.segmentEngineLabel,
                    errorMessage: captureErrorMessage,
                    speakerCount: persistentRecorder.liveSpeakerCount,
                    duration: formatRecordingDuration(persistentRecorder.segmentDuration, padded: true),
                    isPaused: persistentRecorder.isSegmentPaused,
                    levels: recordingAudioLevels,
                    lines: persistentRecorder.liveTranscriptLines,
                    volatileText: persistentRecorder.liveTranscriptVolatileText,
                    showsSpeakerLabels: persistentRecorder.segmentIdentifiesSpeakers,
                    isDraftMode: Binding(
                        get: { recordingMode == .draft },
                        set: { switchActiveRecordingMode(to: $0 ? .draft : .preset) }
                    ),
                    // Live recording board: the toggle stays active while
                    // recording and only changes what Stop does.
                    isModeLocked: false,
                    liveNoteLine: viewModel.liveNoteRecordingLine?.text,
                    liveNoteLineIsLive: viewModel.liveNoteRecordingLine?.isLive ?? false,
                    canSnapWhiteboard: UIImagePickerController.isSourceTypeAvailable(.camera)
                        || VNDocumentCameraViewController.isSupported,
                    discard: discardActiveRecording,
                    stop: { persistentRecorder.stopInAppSegment() },
                    togglePause: { persistentRecorder.toggleInAppSegmentPause() },
                    markMoment: markRecordingMoment,
                    addTask: { viewModel.insertRecordingActionLine("- [ ] ") },
                    snapWhiteboard: snapWhiteboardDuringRecording
                )
                // Full-screen: keep VoiceOver off the Capture chrome
                // (Activity, Settings) underneath while recording.
                .accessibilityAddTraits(.isModal)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
                .zIndex(10)
            }
        }
    }

    private var composer: CaptureViewSection {
        CaptureViewSection {
            MarkdownComposerTextView(
                text: $viewModel.draft.text,
                selection: $composerSelection,
                isFocused: $composerIsFocused,
                controller: composerController,
                contentHeight: showsInlinePencil ? $composerContentHeight : nil,
                writerMovedCaret: { offset in
                    // Type while recording: speech follows the cursor.
                    guard persistentRecorder.isAppRecordingSegmentActive else { return }
                    viewModel.moveRecordedTranscriptInsertion(toUTF16Offset: offset)
                },
                highlightedEntry: viewModel.liveNoteHighlightedEntry
            )
            // Phones keep the editor live under the recording dock so the
            // writer can type while speaking; larger windows cover it.
            .disabled(persistentRecorder.isAppRecordingSegmentActive && !usesInlineRecordingDock)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Geist.bg)
            .overlay(alignment: .topLeading) {
                // An explicit leading ZStack: the overlay's implicit stack
                // centers its children, which drew the idle caret in the
                // middle of the Route prompt instead of before it.
                ZStack(alignment: .topLeading) {
                if viewModel.draft.text.isEmpty, let prompt = composerPlaceholderPrompt {
                    // The Route's own empty prompt, above the centered quote.
                    Text(verbatim: prompt)
                        .font(Geist.body())
                        .foregroundStyle(Geist.faint)
                        .lineSpacing(4)
                        .padding(.leading, composerIsFocused ? 27 : 31)
                        .padding(.trailing, 25)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                if viewModel.draft.text.isEmpty && !composerIsFocused {
                    BlinkingCaptureCaret()
                        .padding(.leading, 25)
                        .padding(.top, 12)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { composerViewportHeight = $0 }
            .overlay(alignment: .center) {
                // The quote sits mid-editor on empty drafts, as before the
                // redesign; the Route prompt keeps its own line at the top.
                if InspirationQuotePresentation.shouldShow(
                    forDraftText: viewModel.draft.text,
                    hasPrompt: composerPlaceholderPrompt != nil,
                    editorHeight: composerViewportHeight
                ) {
                    inspirationPlaceholder
                        .task { await loadInspirationQuote() }
                }
            }
        }
    }

    /// Placeholder copy for an empty composer: only microphone-off guidance.
    /// Otherwise the empty composer is just the blinking caret.
    private var composerPlaceholderPrompt: String? {
        if isMicrophoneDenied, !isLocalizationScreenshot {
            return String(localized: "Type, paste or attach — or turn on the microphone to speak.")
        }
        return nil
    }

    private var inspirationPlaceholder: CaptureViewSection {
        CaptureViewSection {
            VStack(spacing: Geist.Spacing.three) {
                VStack(spacing: Geist.Spacing.two) {
                    Text(verbatim: "“\(inspirationQuote.text)”")
                        .font(Geist.body(.title3))
                        .foregroundStyle(Geist.faint)
                        .multilineTextAlignment(.center)
                        .lineLimit(5)

                    Text(verbatim: "— \(inspirationQuote.author)")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.faint)
                }
                .accessibilityElement(children: .combine)

                Link(
                    "ZenQuotes ↗",
                    destination: URL(string: "https://zenquotes.io/")!
                )
                .font(Geist.caption(.caption2))
                .foregroundStyle(Geist.faint)
                .accessibilityLabel("Inspirational quotes provided by ZenQuotes API")
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 28)
        }
    }

    private var hasDraftContent: Bool {
        !viewModel.draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !viewModel.draft.additionalPayloads.isEmpty
    }

    private var supportsInlinePreview: Bool {
        AdaptiveCaptureWorkspace.supportsPreview(width: workspaceWidth, dynamicTypeSize: dynamicTypeSize)
    }

    private var showsInlinePreview: Bool {
        supportsInlinePreview && previewIsEnabled && hasDraftContent
    }

    private var draftPreview: CaptureViewSection {
        CaptureViewSection {
            CaptureDraftPreview(
                text: viewModel.draft.text,
                presetName: selectedFlow.accessibilityName,
                destination: viewModel.resolvedDestinationPreview,
                attachmentCount: viewModel.draft.additionalPayloads.count,
                configureDestination: {
                    dismissComposer()
                    showsRoutePicker = true
                }
            )
        }
    }

    private var watchRecordingStatusCard: CaptureViewSection {
        CaptureViewSection {
            if let item = watchRecordingPipeline.currentItem {
                VStack(alignment: .leading, spacing: Geist.Spacing.two) {
                    HStack(spacing: Geist.Spacing.three) {
                        Button {
                            dismissComposer()
                            showsWatchRecordingQueue = true
                        } label: {
                            HStack(spacing: Geist.Spacing.three) {
                                Image(systemName: item.watchStatusSymbol)
                                    .foregroundStyle(item.phase == .failed ? Geist.error : Geist.text)
                                    .frame(width: 28, height: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.watchStatusTitle)
                                        .font(Geist.label())
                                    Text(item.watchStatusSubtitle)
                                        .font(Geist.caption(.caption2))
                                        .foregroundStyle(item.phase == .failed ? Geist.error : Geist.muted)
                                        .lineLimit(3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: Geist.Spacing.two)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if item.phase == .transcribing || item.phase == .delivering {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Button {
                            dismissComposer()
                            showsWatchRecordingQueue = true
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(Geist.caption(.caption2))
                                .foregroundStyle(Geist.faint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Show Watch recording queue")
                    }

                    if item.isWaitingForTranscriptionUpgrade {
                        Button("Get Vox.md Unlimited") { presentPaywall(context: .limit) }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(GeistButtonStyle(variant: .primary, size: .small))
                    } else if item.phase == .failed {
                        Button("Retry") { watchRecordingPipeline.retry(item) }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .foregroundStyle(Geist.text)
                .geistCard(padding: 0)
                .accessibilityIdentifier("watch_recording_status")
            }
        }
    }

    private var emptyDestinationBanner: CaptureViewSection {
        CaptureViewSection {
            if viewModel.selectedDestination != nil, !vaultIsReachable {
                CaptureVaultUnreachableBanner {
                    dismissComposer()
                    showsVaultRegrantPicker = true
                }
            } else {
                unconfiguredDestinationBanner
            }
        }
    }

    private var unconfiguredDestinationBanner: CaptureViewSection {
        CaptureViewSection {
            Button {
                dismissComposer()
                showsRoutePicker = true
            } label: {
                HStack(spacing: Geist.Spacing.three) {
                    Circle()
                        .fill(Geist.warning)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Destination Not Configured")
                            .font(.custom("Geist-SemiBold", size: 15, relativeTo: .subheadline))
                        Text("Set up where this Route writes Markdown")
                            .font(Geist.caption())
                            .foregroundStyle(Geist.muted)
                    }
                    Spacer(minLength: Geist.Spacing.two)
                    Text("Set Up")
                        .font(.custom("Geist-SemiBold", size: 13.5, relativeTo: .footnote))
                        .foregroundStyle(Geist.bg)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(Geist.text, in: Capsule(style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .foregroundStyle(Geist.text)
                .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Geist.Palette.amber400, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("capture_destination_banner")
        }
    }

    /// Onboarding Setup already chose a folder and starter routes, so the
    /// first-note walkthrough (folder → write → saved) is only for people who
    /// skipped it.
    private var showsFirstNoteGuide: Bool {
        hasCompletedInitialLoad && !setupChoseFolder
            && (!hasSavedFirstNote || firstNoteReceipt != nil)
    }

    private var firstNoteStep: FirstNoteGuide.Step {
        if let receipt = firstNoteReceipt { return .saved(file: receipt.noteURL.lastPathComponent) }
        if let destination = viewModel.selectedDestination { return .writeNote(folder: destination.rootName) }
        return .chooseFolder
    }

    private var destinationGuidance: CaptureViewSection {
        CaptureViewSection {
            if showsFirstNoteGuide {
                QuickCaptureFirstNoteGuide(step: firstNoteStep, action: advanceFirstNote, dismiss: {
                    firstNoteReceipt = nil
                })
                .disabled(isSavingFirstNoteFolder || !viewModel.canChangeCaptureRoute)
            } else {
                emptyDestinationBanner
            }
        }
    }

    private func advanceFirstNote() {
        if let receipt = firstNoteReceipt {
            do {
                guard let destination = viewModel.destinations.first(where: { $0.id == receipt.destinationID }) else { return }
                let root = try CaptureBookmarkResolver.resolve(destination.rootBookmark)
                guard !root.isStale else { throw QuickCaptureViewModelError.staleDestination(destination.rootName) }
                firstNoteDocument = FirstNoteDocument(noteURL: receipt.noteURL, rootURL: root.url)
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        } else if viewModel.selectedDestination == nil {
            dismissComposer()
            showsFirstNoteFolderPicker = true
        } else {
            focusComposer()
        }
    }

    private func saveFirstNoteFolder(_ url: URL) async {
        guard usageTracker.hasUnlocked, viewModel.selectedDestination == nil,
              !isSavingFirstNoteFolder else { return }
        isSavingFirstNoteFolder = true
        defer { isSavingFirstNoteFolder = false }
        do {
            try await viewModel.setUpFirstNoteFolder(url)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private var locationProgressBar: CaptureViewSection {
        CaptureViewSection {
            HStack(spacing: Geist.Spacing.two) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding Location…")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.text)
                Spacer()
            }
            .padding(.horizontal, 20)
            .frame(minHeight: Geist.ControlHeight.small)
            .background(Geist.bg)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(String(localized: "Finding Location…"))
            .accessibilityIdentifier("capture_finding_preset_location")
        }
    }

    private var entryLocationTokenHintSection: CaptureViewSection {
        CaptureViewSection {
            if let hint = viewModel.entryLocationTokenHint {
                entryLocationTokenHintBar(hint)
            }
        }
    }

    /// Non-blocking hint shown when the resolved entry formatting uses the
    /// `{location}` token but the delivering Capture Preset has location off.
    /// One tap enables the preset's location capture instead of sending a
    /// capture whose token silently renders empty.
    private func entryLocationTokenHintBar(
        _ hint: QuickCaptureViewModel.EntryLocationTokenHint
    ) -> CaptureViewSection {
        CaptureViewSection {
            HStack(spacing: Geist.Spacing.two) {
                Label(
                    String(localized: "{location} needs Current Location for this Preset"),
                    systemImage: "location.slash"
                )
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
                .lineLimit(2)
                Spacer(minLength: 4)
                Button(String(localized: "Use Current Location")) {
                    Task { await viewModel.enableEntryLocationTokenForPreset() }
                }
                .font(Geist.caption())
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    String(localized: "Use Current Location for \(hint.presetDisplayName)")
                )
            }
            .padding(.horizontal, 20)
            .frame(minHeight: Geist.ControlHeight.small)
            .background(Geist.bg)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("capture_entry_location_token_hint")
        }
    }

    private func presetMenuButton(_ flow: CapturePreset) -> CaptureViewSection {
        CaptureViewSection {
            Button {
                selectFlow(flow)
            } label: {
                // Native menu actions have a title + UIImage, not a SwiftUI
                // Text icon slot (UIKit UIAction.h). Keep emoji in the title;
                // symbol-only entries retain the native system-image fallback.
                if let emoji = CapturePresetEmoji.normalized(flow.emoji) {
                    if let name = flow.visibleName {
                        Text(verbatim: "\(emoji) \(name)")
                    } else {
                        Text(verbatim: emoji)
                    }
                } else {
                    Label(flow.visibleName ?? "", systemImage: flow.symbolName)
                }
            }
            .accessibilityLabel(Text(verbatim: flow.accessibilityName))
            .accessibilityAddTraits(viewModel.draft.voxID == flow.id ? .isSelected : [])
        }
    }

    private var selectedPresetActionName: String {
        selectedFlow.visibleName ?? String(localized: "this icon-only preset")
    }

    private var presetSendConfirmationTitle: String {
        if let name = selectedFlow.visibleName {
            return String(localized: "Send this Capture with \(name)?")
        }
        return String(localized: "Send this Capture with this icon-only route?")
    }

    private var sendRouteAccessibilityLabel: String {
        if viewModel.isSubmitting {
            return viewModel.isDescribingImages
                ? String(localized: "Describing images…")
                : String(localized: "Sending capture")
        }
        if captureSubmissionRequiresUnlock {
            return String(localized: "Unlock unlimited captures")
        }
        return String(localized: "Send to \(selectedFlow.visibleName ?? selectedFlow.accessibilityName)")
    }

    private func triggerSendRoute() {
        if captureSubmissionRequiresUnlock {
            presentPaywall(context: .captureLimit)
        } else {
            sendComposerCapture()
        }
    }

    /// Accent Send arrow on the phone; on the iPad sidebar layout a
    /// "Send ⌘↩" text pill, as on the iPad capture board.
    private var sendRouteControl: CaptureViewSection {
        CaptureViewSection {
            Group {
                if layout == .regularSidebar {
                    Button(action: triggerSendRoute) {
                        HStack(spacing: 6) {
                            if captureSubmissionRequiresUnlock {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            Text("Send")
                                .font(.custom("Geist-SemiBold", size: 16, relativeTo: .body))
                            Text(verbatim: "⌘↩")
                                .font(Geist.mono(size: 11, relativeTo: .caption2))
                                .foregroundStyle(Geist.onAccent.opacity(0.75))
                        }
                        .lineLimit(1)
                        .foregroundStyle(Geist.onAccent)
                        .padding(.horizontal, 22)
                        .frame(height: 56)
                        .background(Geist.accent, in: Capsule(style: .continuous))
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sendRouteAccessibilityLabel)
                    .accessibilityHint(Text("Command Return"))
                } else {
                    Button(action: triggerSendRoute) {
                        Image(systemName: captureSubmissionRequiresUnlock ? "lock.fill" : "arrow.up")
                            .accessibilityLabel(sendRouteAccessibilityLabel)
                    }
                    .buttonStyle(SignalCircleButtonStyle(diameter: Geist.ControlHeight.large, filled: Geist.accent))
                }
            }
            .disabled(!viewModel.canSubmit || captureSubmissionIsBlocked)
            .opacity(viewModel.canSubmit && !captureSubmissionIsBlocked ? 1 : 0.35)
            .accessibilityIdentifier("quick_capture_submit")
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    /// Live Notes: the accent circle closes the open file and starts a blank
    /// note. Before the first save it saves first, so nothing is lost.
    private var newNoteControl: CaptureViewSection {
        CaptureViewSection {
            Button {
                Task {
                    await viewModel.startNewNote()
                    if viewModel.needsCaptureUnlock {
                        presentPaywall(context: .captureLimit)
                    }
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .accessibilityLabel("New note")
            }
            .buttonStyle(SignalCircleButtonStyle(diameter: Geist.ControlHeight.large, filled: Geist.accent))
            .disabled(!canStartNewNote)
            .opacity(canStartNewNote ? 1 : 0.35)
            .accessibilityHint(Text("Closes this file and starts a blank note"))
            .accessibilityIdentifier("capture_new_note")
            .keyboardShortcut("n", modifiers: .command)
        }
    }

    private var canStartNewNote: Bool {
        (viewModel.liveNote != nil || viewModel.draft.hasCaptureContent)
            && !viewModel.isSubmitting
            && !viewModel.hasLiveRecordedTranscriptPreview
    }

    /// Vault unreachable (Signal "Capture states" A): the footer is Speak plus
    /// an outlined Save that queues the capture until access is back.
    private var captureFooterIsVaultUnreachable: Bool {
        viewModel.selectedDestination != nil && !vaultIsReachable && footerShowsSend
    }

    private var queueSaveControl: CaptureViewSection {
        CaptureViewSection {
            Button(action: triggerSendRoute) {
                HStack(spacing: 6) {
                    if captureSubmissionRequiresUnlock {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("Save")
                        .font(.custom("Geist-SemiBold", size: 15, relativeTo: .subheadline))
                }
                .lineLimit(1)
                .foregroundStyle(Geist.text)
                .padding(.horizontal, 18)
                .frame(height: 52)
                .background(Geist.card, in: Capsule(style: .continuous))
                .overlay(Capsule(style: .continuous).stroke(Geist.border, lineWidth: 1))
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canSubmit || captureSubmissionIsBlocked)
            .opacity(viewModel.canSubmit && !captureSubmissionIsBlocked ? 1 : 0.35)
            .accessibilityLabel(captureSubmissionRequiresUnlock
                ? String(localized: "Unlock unlimited captures")
                : String(localized: "Save"))
            .accessibilityHint(Text("Keeps this capture waiting on this device until vault access is back."))
            .accessibilityIdentifier("quick_capture_submit")
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    /// The footer shows Send except in the two-pane layout (Duo inner
    /// screen, iPad portrait), where "Send to <route>" lives in the route pane.
    private var footerShowsSend: Bool {
        layout != .regularPane || commands == nil
    }

    /// Bottom bar: Attach (+) | wide ink Speak capsule | accent Send arrow.
    private var captureActionBar: CaptureViewSection {
        CaptureViewSection {
            VStack(spacing: Geist.Spacing.three) {
                if let closed = viewModel.lastClosedNote {
                    LiveNoteClosedToast(note: closed) {
                        Task {
                            await viewModel.reopenClosedNote()
                            focusComposer()
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: closed.id) {
                        try? await Task.sleep(for: .seconds(6))
                        if viewModel.lastClosedNote == closed {
                            withAnimation { viewModel.lastClosedNote = nil }
                        }
                    }
                }
                if !composerIsFocused, captureHintRowHasContent {
                    captureHintRow
                }
                HStack(spacing: Geist.Spacing.three) {
                    if !captureFooterIsVaultUnreachable, viewModel.liveNote == nil {
                        Button {
                            dismissComposer()
                            showsAttachSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .accessibilityLabel("Attach")
                        }
                        .buttonStyle(SignalCircleButtonStyle(diameter: Geist.ControlHeight.large))
                        .disabled(isProcessingMedia)
                        .accessibilityIdentifier("capture_attach")
                    }

                    voiceCaptureButton

                    if viewModel.liveNotesEnabled {
                        if footerShowsSend { newNoteControl }
                    } else if captureFooterIsVaultUnreachable {
                        queueSaveControl
                    } else if footerShowsSend {
                        sendRouteControl
                    }
                }
            }
            .padding(.horizontal, Geist.Spacing.four)
            .padding(.top, Geist.Spacing.three)
            .padding(.bottom, Geist.Spacing.two)
            // Strictly opt-in confirmation (default off) for Preset sends.
            // Attached to the bar so it also works when Send lives in the
            // route pane.
            .confirmationDialog(
                presetSendConfirmationTitle,
                isPresented: $showsPresetSendConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "Send")) { submitComposerCapture() }
                Button(String(localized: "Cancel"), role: .cancel) {}
            } message: {
                Text("Optional confirmation for Route sends. Turn it off in Settings › Capture Bar.")
            }
        }
    }

    private var showsPendingCaptureHint: Bool {
        viewModel.selectedDestination != nil && !vaultIsReachable && pendingCaptureCount > 0
    }

    private var showsUnlockHint: Bool {
        !usageTracker.hasUnlocked && usageTracker.successfulCapturesUsed >= 7
    }

    /// The hint row only takes space when it has something to say; the
    /// idle "Tap to record" line is gone (long-press Speak for details).
    private var captureHintRowHasContent: Bool {
        showsPendingCaptureHint || isCaptureReadOnly || supportsInlinePreview || showsUnlockHint
    }

    private var captureHintRow: CaptureViewSection {
        CaptureViewSection {
            HStack(spacing: Geist.Spacing.two) {
                // "0 captures waiting" reads like an error; with nothing held
                // yet the regular hint stays.
                if showsPendingCaptureHint {
                    Text(pendingCaptureCount == 1
                        ? String(localized: "1 capture waiting · nothing is lost")
                        : String(localized: "\(pendingCaptureCount) captures waiting · nothing is lost"))
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                } else if isCaptureReadOnly {
                    Text("Read-only · choose a plan to capture")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                }

                if supportsInlinePreview {
                    Button {
                        previewIsEnabled.toggle()
                    } label: {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(previewIsEnabled ? Geist.accentText : Geist.muted)
                            .frame(width: 28, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!hasDraftContent)
                    .accessibilityLabel(previewIsEnabled ? "Hide draft preview" : "Show draft preview")
                    .accessibilityIdentifier("capture_toggle_preview")
                }

                if showsUnlockHint {
                    Button {
                        presentPaywall(context: .usageMeter)
                    } label: {
                        Text(
                            usageTracker.isCaptureAtLimit
                                ? String(localized: "Unlock")
                                : String(localized: "Unlock Capture")
                        )
                        .font(Geist.mono(.caption2, medium: true))
                        .foregroundStyle(usageTracker.isCaptureAtLimit ? Geist.error : Geist.accentText)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unlock Capture")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Staged attachments rendered inline under the composer: voice clips as
    /// playable chips, images and sketches as thumbnails, everything else as
    /// compact tiles. The Markdown text itself is unchanged.
    private var attachmentStrip: CaptureViewSection {
        CaptureViewSection {
            let indexed = Array(viewModel.draft.additionalPayloads.enumerated())
            let audio = indexed.filter { Self.isAudioPayload($0.element) }
            let visual = indexed.filter { Self.isVisualPayload($0.element) }
            let other = indexed.filter { !Self.isAudioPayload($0.element) && !Self.isVisualPayload($0.element) }
            VStack(alignment: .leading, spacing: 10) {
                ForEach(audio, id: \.offset) { index, payload in
                    CaptureInlineAudioChip(
                        url: stagedAssetURL(for: payload),
                        label: payloadLabel(payload),
                        hasTranscript: audioHasTranscript(payload),
                        remove: { Task { await viewModel.removePayload(at: index) } }
                    )
                }
                if !visual.isEmpty {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(visual, id: \.offset) { index, payload in
                            CaptureInlineImageTile(
                                url: stagedAssetURL(for: payload),
                                label: payloadLabel(payload),
                                isSketch: { if case .sketch = payload { return true } else { return false } }(),
                                remove: { Task { await viewModel.removePayload(at: index) } }
                            )
                        }
                    }
                }
                if !other.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(other, id: \.offset) { index, payload in
                                CaptureAttachmentTile(
                                    label: payloadLabel(payload),
                                    systemImage: payloadIcon(payload),
                                    isAudio: false
                                ) {
                                    Task { await viewModel.removePayload(at: index) }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, Geist.Spacing.two)
            .background(Geist.bg)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Capture attachments")
        }
    }

    private static func isAudioPayload(_ payload: CapturePayload) -> Bool {
        switch payload {
        case .audio, .retainedAudio: return true
        default: return false
        }
    }

    private static func isVisualPayload(_ payload: CapturePayload) -> Bool {
        switch payload {
        case .image, .sketch: return true
        default: return false
        }
    }

    private func audioHasTranscript(_ payload: CapturePayload) -> Bool {
        if case .audio(_, let transcript) = payload {
            return transcript?.isEmpty == false
        }
        return false
    }

    private func stagedAssetURL(for payload: CapturePayload) -> URL? {
        let asset: CaptureAssetReference
        switch payload {
        case .audio(let reference, _), .retainedAudio(let reference, _), .image(let reference, _, _):
            asset = reference
        case .sketch(_, let preview, _, _):
            asset = preview
        default:
            return nil
        }
        return viewModel.sentCaptureUndoSourceDirectoryURL?.appendingPathComponent(asset.relativePath)
    }

    private var captureErrorMessage: String? {
        if isLocalizationScreenshot { return nil }
        return viewModel.errorMessage ?? persistentRecorder.lastError
    }

    private var isLocalizationScreenshot: Bool {
        #if DEBUG
        return RootDestination.localizationScreenshotStory != nil
        #else
        return false
        #endif
    }

    private func dismissCaptureError() {
        if viewModel.errorMessage != nil {
            viewModel.errorMessage = nil
        } else {
            persistentRecorder.lastError = nil
        }
    }

    private func errorBanner(_ message: String) -> CaptureViewSection {
        CaptureViewSection {
            CaptureStatusCard(
                title: nil,
                message: message,
                tint: Geist.recording,
                actionTitle: viewModel.errorMessage != nil && viewModel.failedInboxCount > 0
                    ? String(localized: "Retry queued captures")
                    : nil,
                action: { Task { await viewModel.retryFailedInbox() } },
                dismiss: dismissCaptureError
            )
        }
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

    /// Every Send is a new Capture delivery, so it needs paid access for any
    /// draft — including a voice transcript recorded before access ended,
    /// which the delivery quota alone would let through. Locked, Send shows
    /// a lock and opens the paywall (`triggerSendRoute`).
    private var captureSubmissionRequiresUnlock: Bool {
        usageTracker.isCaptureAtLimit
    }

    private var captureSubmissionIsBlocked: Bool {
        !viewModel.canChangeCaptureRoute
    }

    private var isKeyboardListeningActive: Bool {
        persistentRecorder.isListening
            && AppConstants.sharedDefaults?.bool(forKey: AppConstants.autoListenEnabledKey) == true
    }

    private var insertionFormatter: CaptureInsertionFormatter {
        CaptureInsertionFormatter(calendar: calendar, locale: locale, timeZone: timeZone)
    }

    private func handleToolbarCommand(_ command: CaptureEditorToolbarCommand) {
        switch command {
        case .undo:
            composerController.undo()
        case .bold:
            applyComposerCommand(.toggleBold)
        case .italic:
            applyComposerCommand(.toggleItalic)
        case .hashtag:
            applyComposerCommand(.insertHashtag)
        case .heading(let level):
            applyComposerCommand(.heading(level: level))
        case .markdownLink:
            applyComposerCommand(.markdownLink())
        case .checklist:
            applyComposerCommand(.taskCheckbox)
        case .bulletList:
            applyComposerCommand(.bullet)
        case .paste:
            if let value = UIPasteboard.general.string {
                applyComposerCommand(.replaceSelection(with: value))
            }
        case .internalLink:
            dismissComposer()
            showsInternalLinks = true
        case .timestamp:
            applyComposerCommand(.replaceSelection(with: Self.timestampInsertion(
                formatter: insertionFormatter,
                preferences: captureToolbarPreferences
            )))
        case .date:
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            applyComposerCommand(.replaceSelection(with: formatter.string(from: Date())))
        case .lowercase:
            applyComposerCommand(.lowercase)
        case .uppercase:
            applyComposerCommand(.uppercase)
        case .sentenceCase:
            applyComposerCommand(.sentenceCase)
        case .capitalizeWords:
            applyComposerCommand(.capitalizeWords)
        case .slugify:
            applyComposerCommand(.slugify)
        }
    }

    /// Injectable seam for the real composer timestamp command. Tests provide a
    /// fixed instant while production keeps the caller's calendar/locale/zone.
    static func timestampInsertion(
        at date: Date = Date(),
        formatter: CaptureInsertionFormatter,
        preferences: CaptureToolbarPreferences
    ) -> String {
        formatter.currentTimestamp(at: date, format: preferences.timestampFormat)
    }

    private func applyComposerCommand(_ command: CaptureComposerCommand) {
        let result = CaptureComposerTextEditor().applying(
            command,
            to: composerController.text,
            selection: composerController.selection
        )
        composerController.replaceAll(with: result.text, selection: result.selection.nsRange)
        focusComposer()
    }

    private func handleRequestedInputChange(_ input: CaptureRequestedInput?) {
        guard let input, viewModel.requireCaptureRouteAvailable() else { return }
        presentRequestedInput(input)
        viewModel.requestedInput = nil
    }

    private func presentFileImporter() {
        dismissComposer()
        showsFileImporter = true
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            reloadFlows()
            // Returning from Settings may have changed folder access.
            refreshVaultReachability()
            Task { await refreshPendingCaptureCount() }
            Task { await viewModel.liveNoteSceneDidBecomeActive() }
        }
        // Permission prompts make the scene temporarily inactive. Keep explicit
        // one-shot requests alive until the app actually backgrounds.
        guard phase == .background else { return }
        microphonePermissionTask?.cancel()
        locationRequestTask?.cancel()
        let backgroundTask = UIApplication.shared.beginBackgroundTask(
            withName: "Save Capture draft"
        )
        Task {
            defer {
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
            }
            await viewModel.saveDraftNow()
            await viewModel.liveNoteSceneDidEnterBackground()
        }
    }

    private func handleCaptureDisappear() {
        microphonePermissionTask?.cancel()
        locationRequestTask?.cancel()
        initialComposerFocusIsPending = false
        sentToastPresentationID = nil
        showsSentToast = false
        discardSentUndoSnapshot()
        dismissComposer()
    }

    private func insertCurrentLocation() {
        guard locationRequestTask == nil else { return }
        isFindingLocation = true
        locationRequestTask = Task { @MainActor in
            defer {
                isFindingLocation = false
                locationRequestTask = nil
            }
            do {
                let location = try await locationService.requestCurrentLocation()
                try Task.checkCancellation()
                let markdown = try insertionFormatter.googleMapsLink(
                    latitude: location.latitude,
                    longitude: location.longitude,
                    label: location.label
                )
                applyComposerCommand(.replaceSelection(with: markdown))
            } catch is CancellationError {
                // Leaving Capture cancels the explicit one-shot request.
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func isAttachActionAvailable(_ action: CaptureAttachAction) -> Bool {
        switch action {
        case .camera:
            return UIImagePickerController.isSourceTypeAvailable(.camera)
        case .scan:
            return VNDocumentCameraViewController.isSupported
        case .journal:
            return canExtractJournalText && UIImagePickerController.isSourceTypeAvailable(.camera)
        case .journalPhotos:
            return canExtractJournalText
        case .location:
            return !isFindingLocation
        case .sketch, .file, .link, .screenshot, .photos:
            return true
        }
    }

    /// Runs the tool picked in the Attach sheet once that sheet is gone, so the
    /// follow-up picker, camera or alert can present cleanly.
    private func runPendingAttachAction() {
        guard let action = pendingAttachAction else { return }
        pendingAttachAction = nil
        switch action {
        case .camera: showsCamera = true
        case .scan: showsScanner = VNDocumentCameraViewController.isSupported
        case .journal:
            showsJournalPageCapture = UIImagePickerController.isSourceTypeAvailable(.camera)
        case .journalPhotos: showsOCRPhotoPicker = true
        case .sketch: showsSketch = true
        case .file: presentFileImporter()
        case .link: showsLinkPrompt = true
        case .location: insertCurrentLocation()
        case .screenshot: showsScreenshotPicker = true
        case .photos: showsPhotoPicker = true
        }
    }

    private func toggleKeyboard() {
        if composerIsFocused {
            dismissComposer()
        } else {
            focusComposer()
        }
    }

    private func dismissComposer() {
        composerIsFocused = false
        composerController.dismissKeyboard()
    }

    /// Keeps the caret just after spoken words as they stream in at the
    /// cursor. While typing it follows only when the caret sat where the
    /// words land, so speech and typing interleave in order without
    /// stealing a cursor the writer placed elsewhere.
    private func followRecordedTranscriptCaret(from previous: Int?, to caret: Int?) {
        guard let caret else { return }
        if composerIsFocused {
            guard composerSelection.length == 0,
                  composerSelection.location == previous else { return }
        }
        composerSelection = NSRange(location: caret, length: 0)
    }

    /// The UTF-16 offset a new recording's words go to: the composer cursor,
    /// or the end when the cursor was never placed in an existing draft.
    private var recordingInsertionOffset: Int? {
        let end = composerSelection.location + composerSelection.length
        if end == 0, !composerIsFocused, !viewModel.draft.text.isEmpty { return nil }
        return end
    }

    private func loadInspirationQuote() async {
        guard !hasLoadedInspirationQuote else { return }
        let quote = await InspirationQuoteService.shared.nextQuote()
        guard !Task.isCancelled else { return }
        inspirationQuote = quote
        hasLoadedInspirationQuote = true
    }

    private func focusComposer() {
        composerIsFocused = true
    }

    private var isPresentingCaptureModal: Bool {
        showsPhotoPicker
            || showsScreenshotPicker
            || showsOCRPhotoPicker
            || showsCamera
            || showsFileImporter
            || showsScanner
            || showsJournalPageCapture
            || showsSketch
            || showsLinkPrompt
            || showsCaptureHistory
            || showsRoutePicker
            || showsFirstNoteFolderPicker
            || firstNoteDocument != nil
            || showsMicrophoneSettings
            || showsDueDate
            || showsInternalLinks
            || showsPaywall
            || showsAudioImporter
            || showsVoiceCaptureDetails
            || showsWatchRecordingQueue
            || viewModel.pendingPresetSwitch != nil
    }

    private func fulfillInitialComposerFocusIfReady() async {
        guard initialComposerFocusIsPending,
              hasCompletedInitialLoad,
              !defersCaptureInputFocusForReleaseNotes else { return }

        guard !isPresentingCaptureModal else {
            initialComposerFocusIsPending = false
            return
        }

        try? await Task.sleep(for: .milliseconds(180))
        guard !Task.isCancelled,
              initialComposerFocusIsPending,
              hasCompletedInitialLoad,
              !defersCaptureInputFocusForReleaseNotes else { return }

        guard !isPresentingCaptureModal else {
            initialComposerFocusIsPending = false
            return
        }

        initialComposerFocusIsPending = false
        focusComposer()
    }

    private func loadAndPresentRequestedInput() async {
        // Navigation restarts this task when Capture reappears. Auto-focusing on
        // every restart races the pop transition and can put the keyboard over
        // controls before SwiftUI has restored the keyboard safe area.
        let shouldAutoFocus = !hasPerformedInitialLoad
        hasPerformedInitialLoad = true
        if shouldAutoFocus {
            initialComposerFocusIsPending = true
        }

        await viewModel.load()
        guard !Task.isCancelled else { return }
        if viewModel.historyRecords.contains(where: { $0.outcome == .delivered }) {
            hasSavedFirstNote = true
        }
        setupChoseFolder = VoxVaultStore.stored() != nil
        if !hasSavedFirstNote, !setupChoseFolder { initialComposerFocusIsPending = false }
        reloadFlows()
        handleRequestedInputChange(viewModel.requestedInput)
        if shouldAutoFocus {
            hasCompletedInitialLoad = true
        }
    }

    private func presentRequestedInput(_ input: CaptureRequestedInput) {
        guard viewModel.requireCaptureRouteAvailable() else { return }
        initialComposerFocusIsPending = false
        dismissComposer()
        switch input {
        case .photos: showsPhotoPicker = true
        case .screenshots: showsScreenshotPicker = true
        case .camera: showsCamera = true
        case .files: presentFileImporter()
        case .scan: showsScanner = VNDocumentCameraViewController.isSupported
        case .sketch: showsSketch = true
        case .link: showsLinkPrompt = true
        case .voice:
            // External voice requests (Shortcuts "Record a Capture", deep
            // links) honor the persisted result mode instead of forcing the
            // draft flow, matching the in-app behavior the user configured.
            recordingMode = Self.externallyRequestedVoiceRecordingMode()
            startInlineRecording()
        }
    }

    private func presentSentToast(
        for receipt: CaptureReceipt? = nil,
        replacingWith suppliedSnapshot: SentCaptureUndoSnapshot? = nil
    ) async {
        if let suppliedSnapshot {
            replaceSentUndoSnapshot(with: suppliedSnapshot)
        } else if let receipt {
            // Undo is only offered when the receipt belongs to the composer
            // send that created the snapshot. Inbox receipts key different
            // request IDs and watch deliveries have no local snapshot.
            if sentUndoSnapshot?.requestID != receipt.requestID {
                discardSentUndoSnapshot()
            }
        } else {
            discardSentUndoSnapshot()
        }

        // Live Notes: the first save isn't a "send"; the Saved pill says it.
        if viewModel.liveNotesEnabled {
            discardSentUndoSnapshot()
            return
        }
        let presentationID = UUID()
        sentToastPresentationID = presentationID
        withAnimation(.easeOut(duration: 0.18)) { showsSentToast = true }
        let undoAvailable = sentUndoSnapshot?.offersUndo == true
        UIAccessibility.post(
            notification: .announcement,
            argument: undoAvailable
                ? String(localized: "Capture sent. Undo available for five seconds.")
                : String(localized: "Capture sent")
        )
        try? await Task.sleep(for: SentCaptureUndo.toastWindow)
        guard sentToastPresentationID == presentationID else { return }
        sentToastPresentationID = nil
        withAnimation(.easeIn(duration: 0.18)) { showsSentToast = false }
        discardSentUndoSnapshot()
        focusComposer()
    }

    private func replaceSentUndoSnapshot(with snapshot: SentCaptureUndoSnapshot) {
        guard sentUndoSnapshot?.id != snapshot.id else { return }
        sentUndoSnapshot?.discardCachedAudio()
        sentUndoSnapshot = snapshot
    }

    private func discardSentUndoSnapshot(matching snapshotID: UUID? = nil) {
        guard snapshotID == nil || sentUndoSnapshot?.id == snapshotID else { return }
        sentUndoSnapshot?.discardCachedAudio()
        sentUndoSnapshot = nil
    }

    /// Sends the composer Capture. When the opt-in preference is enabled, a
    /// preset send is confirmed before dispatch; draft content in the
    /// composer is otherwise never confirmed.
    private func sendComposerCapture() {
        guard viewModel.requireCaptureRouteAvailable() else { return }
        guard confirmsPresetSend else {
            submitComposerCapture()
            return
        }
        showsPresetSendConfirmation = true
    }

    private func submitComposerCapture() {
        guard viewModel.requireCaptureRouteAvailable() else { return }
        // Snapshot before submit(): successful delivery moves staged audio and
        // replaces the live draft, so this is the only safe preservation point.
        let snapshot = SentCaptureUndo.snapshot(
            draft: viewModel.draft,
            presetDisplayName: selectedFlow.accessibilityName,
            stagingDirectoryURL: viewModel.sentCaptureUndoSourceDirectoryURL,
            audioCacheRootURL: viewModel.sentCaptureUndoCacheRootURL
        )
        replaceSentUndoSnapshot(with: snapshot)
        Task {
            await viewModel.submit()
            if viewModel.lastHeldForVaultRequestID == snapshot.requestID {
                // Held in the inbox for an unreachable vault: update
                // "N captures waiting" right away.
                await refreshPendingCaptureCount()
                UIAccessibility.post(
                    notification: .announcement,
                    argument: String(localized: "Saved on this iPhone. It delivers when vault access is back.")
                )
            }
            if viewModel.lastReceipt?.requestID != snapshot.requestID,
               viewModel.locationDecision == nil {
                discardSentUndoSnapshot(matching: snapshot.id)
            }
        }
    }

    /// Restores the just-sent Capture into the composer as an editable draft.
    /// The note already written to the user's vault is intentionally kept.
    private func restoreSentCaptureAsDraft() {
        guard let snapshot = sentUndoSnapshot else { return }
        sentUndoSnapshot = nil
        sentToastPresentationID = nil
        withAnimation(.easeIn(duration: 0.18)) { showsSentToast = false }
        let sentVia = viewModel.historyRecords
            .first { $0.requestID == snapshot.requestID && $0.outcome == .delivered }?
            .destinationName
            ?? snapshot.presetDisplayName
        Task {
            let didRestore = await SentCaptureUndo.apply(snapshot, to: viewModel)
            focusComposer()
            guard didRestore else { return }
            UIAccessibility.post(
                notification: .announcement,
                argument: String(
                    localized: "Capture restored to this draft. The sent note remains in \(sentVia)."
                )
            )
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem], prefix: String) async {
        guard viewModel.requireCaptureRouteAvailable() else { selectedPhotos = []; return }
        isProcessingMedia = true
        defer {
            selectedPhotos = []
            isProcessingMedia = false
            focusComposer()
        }
        let firstNewPayloadIndex = viewModel.draft.additionalPayloads.count
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first ?? .jpeg
                let ext = type.preferredFilenameExtension ?? "jpg"
                await viewModel.stageImage(
                    data: data,
                    filename: "\(prefix)-\(UUID().uuidString.lowercased()).\(ext)",
                    contentTypeIdentifier: type.identifier,
                    describeImmediately: false
                )
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
        await viewModel.describeStagedImagesIfNeeded(from: firstNewPayloadIndex)
    }

    private func importOCRPhotos(_ items: [PhotosPickerItem]) async {
        guard viewModel.requireCaptureRouteAvailable(), requireIdleVoiceCaptureForOCR() else {
            selectedOCRPhotos = []
            focusComposer()
            return
        }
        isProcessingMedia = true
        isExtractingText = true
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Extracting text on this device")
        )
        defer {
            selectedOCRPhotos = []
            isExtractingText = false
            isProcessingMedia = false
            focusComposer()
        }

        do {
            var pages: [Data] = []
            pages.reserveCapacity(items.count)
            for (index, item) in items.enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw JournalImageOCRProcessorError.unreadableImage(page: index + 1)
                }
                pages.append(data)
            }
            try await extractJournalText(from: pages)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func importScreenshots(_ items: [PhotosPickerItem]) async {
        guard viewModel.requireCaptureRouteAvailable() else { selectedScreenshots = []; return }
        isProcessingMedia = true
        defer {
            selectedScreenshots = []
            isProcessingMedia = false
            focusComposer()
        }
        let firstNewPayloadIndex = viewModel.draft.additionalPayloads.count
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let type = item.supportedContentTypes.first ?? .png
                let ext = type.preferredFilenameExtension ?? "png"
                await viewModel.stageImage(
                    data: data,
                    filename: "screenshot-\(UUID().uuidString.lowercased()).\(ext)",
                    contentTypeIdentifier: type.identifier,
                    altText: String(localized: "Screenshot"), altTextOrigin: .placeholder,
                    describeImmediately: false
                )
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
        await viewModel.describeStagedImagesIfNeeded(from: firstNewPayloadIndex)
    }

    private func importFiles(_ urls: [URL]) {
        Task {
            guard viewModel.requireCaptureRouteAvailable() else { return }
            isProcessingMedia = true
            defer {
                isProcessingMedia = false
                focusComposer()
            }
            do {
                var budget = CaptureInputBudget()
                try budget.reserveSharedItems(urls.count)
                let firstNewPayloadIndex = viewModel.draft.additionalPayloads.count
                for url in urls {
                    let values = try url.resourceValues(forKeys: [.contentTypeKey])
                    let type = values.contentType ?? .data
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
    }

    private func processScan(_ pages: [Data]) async {
        guard viewModel.requireCaptureRouteAvailable() else { return }
        isProcessingMedia = true
        defer { isProcessingMedia = false }
        do {
            let scan = try await DocumentScanProcessor.process(pageImages: pages)
            await viewModel.stageScan(
                pageImages: scan.pageImages,
                pdfData: scan.pdfData,
                extractedText: scan.extractedText
            )
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func processOCRScan(_ pages: [Data]) async {
        guard viewModel.requireCaptureRouteAvailable(), requireIdleVoiceCaptureForOCR() else {
            focusComposer()
            return
        }
        isProcessingMedia = true
        isExtractingText = true
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Extracting text on this device")
        )
        defer {
            isExtractingText = false
            isProcessingMedia = false
            focusComposer()
        }

        do {
            try await extractJournalText(from: pages)
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private func extractJournalText(from pages: [Data]) async throws {
        let markdown = try await JournalImageOCRProcessor.process(pageImages: pages)
        // Watch delivery can begin while a picker or Vision request is active.
        // Never merge two asynchronous transcript sources into the same draft.
        guard requireIdleVoiceCaptureForOCR() else { return }
        guard await viewModel.appendRecognizedText(markdown) else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: String(localized: "Extracted text added to Capture")
        )
    }

    // MARK: - Capture states, activity and recording actions

    /// A foldable's closed cover screen (DuoCoverCapture), as opposed to the
    /// phone layout (Main).
    private var isCoverScreen: Bool {
        layout == .compact
            && AdaptiveLayout.isCoverScreen(horizontalSizeClass: horizontalSizeClass, hinge: hingeState)
    }

    private var routePillsRow: CaptureViewSection {
        CaptureViewSection {
            CaptureRoutePillsRow(
                profiles: enabledFlows.map(\.captureProfile),
                selectedID: viewModel.draft.voxID ?? selectedFlow.id,
                isEnabled: viewModel.canSelectCapturePreset,
                pillHeight: isCoverScreen ? 44 : 40,
                select: { id in
                    guard let flow = flows.first(where: { $0.id == id }) else { return }
                    selectFlow(flow)
                }
            )
        }
    }

    /// Captures still on the way to the vault: queued inbox requests (pending,
    /// processing or failed) plus an in-flight recording transcription.
    private var activityPendingCount: Int {
        pendingCaptureCount + (persistentRecorder.isAppRecordingTranscribing ? 1 : 0)
    }

    private var activityAccessibilityLabel: String {
        if viewModel.failedInboxCount > 0 {
            return String(localized: "Activity, \(activityPendingCount) pending, \(viewModel.failedInboxCount) need attention")
        }
        if activityPendingCount > 0 {
            return String(localized: "Activity, \(activityPendingCount) pending")
        }
        return String(localized: "Activity")
    }

    private func refreshPendingCaptureCount() async {
        guard let root = AppConstants.captureDirectoryURL else { return }
        let inbox = CaptureInbox(rootDirectoryURL: root)
        var count = 0
        for state in [CaptureInboxState.pending, .processing, .failed] {
            count += (try? await inbox.requestIDs(in: state).count) ?? 0
        }
        if pendingCaptureCount != count { pendingCaptureCount = count }
    }

    private func refreshPendingCaptureCountWhileVisible() async {
        while !Task.isCancelled {
            await refreshPendingCaptureCount()
            try? await Task.sleep(for: .seconds(8))
        }
    }

    private func refreshVaultReachability() {
        guard let destination = viewModel.selectedDestination else {
            vaultIsReachable = true
            return
        }
        let reachable = CaptureVaultReachability.isReachable(destination)
        if vaultIsReachable != reachable {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { vaultIsReachable = reachable }
        }
    }

    private func regrantVaultAccess(folderURL: URL) {
        guard let destination = viewModel.selectedDestination else { return }
        Task {
            do {
                try await CaptureVaultReachability.regrant(destination: destination, folderURL: folderURL)
                await viewModel.refreshLibrary()
                refreshVaultReachability()
                await viewModel.liveNoteSceneDidBecomeActive()
                if vaultIsReachable {
                    await viewModel.retryFailedInbox()
                    await viewModel.processPendingInbox()
                    await refreshPendingCaptureCount()
                    UIAccessibility.post(
                        notification: .announcement,
                        argument: String(localized: "Vault access restored. Waiting captures are delivering.")
                    )
                }
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Switches what Stop does for the recording in progress and keeps it as
    /// the default for the next recording, like the details-bar picker.
    private func switchActiveRecordingMode(to mode: CaptureRecordingMode) {
        guard mode != recordingMode else { return }
        recordingMode = mode
        persistedRecordingResultMode = mode.rawValue
        persistentRecorder.setActiveSegmentCompletionMode(selectedRecordingCompletionMode)
    }

    private func discardActiveRecording() {
        persistentRecorder.cancelSegment()
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Recording discarded"))
    }

    /// Inserts a `⏱ 01:59` marker line for the current recording offset.
    private func markRecordingMoment() {
        let stamp = formatRecordingDuration(persistentRecorder.segmentDuration, padded: true)
        viewModel.insertRecordingActionLine("⏱ \(stamp) ")
    }

    private func snapWhiteboardDuringRecording() {
        if VNDocumentCameraViewController.isSupported {
            showsWhiteboardScanner = true
        } else if UIImagePickerController.isSourceTypeAvailable(.camera) {
            showsWhiteboardCamera = true
        }
    }

    /// Recording keeps running while the whiteboard is captured; the photo is
    /// staged beside the note with a moment marker for when it was taken.
    private func stageWhiteboardImages(_ pages: [Data]) async {
        guard !pages.isEmpty else { return }
        if persistentRecorder.isAppRecordingSegmentActive {
            let stamp = formatRecordingDuration(persistentRecorder.segmentDuration, padded: true)
            viewModel.insertRecordingActionLine("⏱ \(stamp) Whiteboard")
        }
        for (index, data) in pages.enumerated() {
            await viewModel.stageImage(
                data: data,
                filename: "whiteboard-\(captureTimestamp())\(pages.count > 1 ? "-\(index + 1)" : "").jpg",
                contentTypeIdentifier: UTType.jpeg.identifier,
                altText: String(localized: "Whiteboard"),
                altTextOrigin: .placeholder,
                describeImmediately: false
            )
        }
    }

    /// Stages the photos picked in the Attach sheet's recent strip, in pick
    /// order, then describes them together.
    private func attachRecentPhotos(_ assets: [PHAsset]) async {
        guard !assets.isEmpty, viewModel.requireCaptureRouteAvailable() else { return }
        isProcessingMedia = true
        defer {
            isProcessingMedia = false
            focusComposer()
        }
        let firstNewPayloadIndex = viewModel.draft.additionalPayloads.count
        var failedCount = 0
        for asset in assets {
            guard let (data, identifier) = await CaptureRecentPhotosModel.imageData(for: asset) else {
                failedCount += 1
                continue
            }
            await stagePhoto(data: data, typeIdentifier: identifier)
        }
        if failedCount > 0 {
            viewModel.errorMessage = assets.count == 1
                ? String(localized: "That photo could not be loaded.")
                : failedCount == 1
                    ? String(localized: "One photo could not be loaded.")
                    : String(localized: "\(failedCount) photos could not be loaded.")
        }
        await viewModel.describeStagedImagesIfNeeded(from: firstNewPayloadIndex)
    }

    /// The Attach sheet's clipboard card: a copied link joins the draft like
    /// the Link prompt; a copied image is staged like a photo.
    private func attachPastedItems(_ providers: [NSItemProvider]) async {
        guard viewModel.requireCaptureRouteAvailable() else { return }
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self), let url = await Self.loadURL(from: provider) {
                await viewModel.addURL(url)
                return
            }
            // A link copied as plain text (many apps copy it this way).
            if provider.canLoadObject(ofClass: String.self),
               let text = await Self.loadString(from: provider),
               let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
               let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                await viewModel.addURL(url)
                return
            }
            if let imageType = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) }),
               let data = await Self.loadData(from: provider, type: imageType) {
                isProcessingMedia = true
                defer {
                    isProcessingMedia = false
                    focusComposer()
                }
                let firstNewPayloadIndex = viewModel.draft.additionalPayloads.count
                await stagePhoto(data: data, typeIdentifier: imageType.identifier)
                await viewModel.describeStagedImagesIfNeeded(from: firstNewPayloadIndex)
                return
            }
        }
        viewModel.errorMessage = String(localized: "Nothing on the clipboard could be added.")
    }

    private func stagePhoto(data: Data, typeIdentifier: String) async {
        let type = UTType(typeIdentifier) ?? .jpeg
        await viewModel.stageImage(
            data: data,
            filename: "photo-\(UUID().uuidString.lowercased()).\(type.preferredFilenameExtension ?? "jpg")",
            contentTypeIdentifier: type.identifier,
            describeImmediately: false
        )
    }

    private static func loadURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                continuation.resume(returning: url)
            }
        }
    }

    private static func loadString(from provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in
                continuation.resume(returning: text)
            }
        }
    }

    private static func loadData(from provider: NSItemProvider, type: UTType) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    // MARK: - Inline recording

    private var enabledFlows: [CapturePreset] {
        let enabled = flows.filter(\.isEnabled)
        return enabled.isEmpty ? CapturePresetStore.defaultFlows : enabled
    }

    private var selectedFlow: CapturePreset {
        enabledFlows.first(where: { $0.id == selectedFlowId }) ?? enabledFlows[0]
    }

    private var selectedRecordingCompletionMode: RecordingCompletionMode {
        Self.completionMode(
            for: recordingMode,
            attachAudio: attachRecordingAudio,
            flowID: selectedFlow.id
        )
    }

    /// Segmented-picker binding that keeps `recordingMode` and the persisted
    /// default (`capture.voice.defaultResult.v1`) in lockstep, so a change
    /// made in the details bar survives relaunches.
    private var recordingModeSelection: Binding<CaptureRecordingMode> {
        Binding(
            get: { recordingMode },
            set: { mode in
                guard viewModel.requireCaptureRouteAvailable() else { return }
                recordingMode = mode
                persistedRecordingResultMode = mode.rawValue
            }
        )
    }

    /// Maps the selected recording result mode onto the pipeline completion
    /// mode. Internal (and static) so unit tests can verify that the persisted
    /// default flows through to the actual capture behavior.
    static nonisolated func completionMode(
        for mode: CaptureRecordingMode,
        attachAudio: Bool,
        flowID: String
    ) -> RecordingCompletionMode {
        switch mode {
        case .draft:
            return .captureDraft(attachAudio: attachAudio)
        case .preset:
            return .runVox(flowID: flowID)
        }
    }

    /// Resolves the recording result mode for an externally triggered voice
    /// capture (Shortcuts intent, deep link): the persisted preference —
    /// defaulting to `.draft` ("Add to Draft") when unset — rather than a
    /// forced draft flow.
    static nonisolated func externallyRequestedVoiceRecordingMode(
        defaults: UserDefaults = .standard
    ) -> CaptureRecordingMode {
        CaptureRecordingMode(
            persistedRawValue: defaults.string(
                forKey: CapturePreferenceKeys.defaultRecordingResultMode
            )
        )
    }

    private var recordingDetailsTitle: String {
        if persistentRecorder.isAppRecordingSegmentActive {
            return persistentRecorder.isSegmentPaused
                ? String(localized: "Paused \(formatRecordingDuration(persistentRecorder.segmentDuration))")
                : String(localized: "Recording \(formatRecordingDuration(persistentRecorder.segmentDuration))")
        }
        if persistentRecorder.isAppRecordingTranscribing {
            if let percent = persistentRecorder.transcriptionProgress?.formattedWholePercentCompleted {
                return String(localized: "Transcribing \(percent)")
            }
            return String(localized: "Transcribing")
        }
        if persistentRecorder.isListening { return String(localized: "Keyboard Listening On") }
        return String(localized: "Voice Capture")
    }

    private var recordingDetailsSubtitle: String {
        if persistentRecorder.isAppRecordingSegmentActive {
            return persistentRecorder.isSegmentPaused
                ? String(localized: "Paused audio is excluded — resume to keep recording this note")
                : String(localized: "Composer remains available while you record")
        }
        if persistentRecorder.isTranscribing,
           let origin = persistentRecorder.appRecordingOriginDisplay {
            return origin.transcribingSubtitle
        }
        if persistentRecorder.isAppRecordingTranscribing {
            // Missing origin is not permission to label another draft's preset.
            return String(localized: "Transcribing")
        }
        if persistentRecorder.isListening {
            return String(localized: "Ready for the Vox.md keyboard in any app")
        }
        return recordingMode == .draft
            ? String(localized: "Transcript will be added to the editor")
            : String(localized: "Record and export with \(selectedPresetActionName)")
    }

    private var recordingDetailsIcon: String {
        if persistentRecorder.isAppRecordingSegmentActive {
            return persistentRecorder.isSegmentPaused ? "pause.circle.fill" : "record.circle.fill"
        }
        if persistentRecorder.isAppRecordingTranscribing { return "waveform.badge.magnifyingglass" }
        if persistentRecorder.isListening { return "headphones.circle.fill" }
        return "waveform.circle"
    }

    private var recordingDetailsColor: Color {
        if persistentRecorder.isAppRecordingSegmentActive {
            return persistentRecorder.isSegmentPaused ? Geist.Palette.blue700 : Geist.error
        }
        if persistentRecorder.isAppRecordingTranscribing || persistentRecorder.isListening {
            return Geist.Palette.blue700
        }
        return Geist.text
    }

    private var recordingStatusTitle: String {
        if persistentRecorder.isAppRecordingSegmentActive {
            return persistentRecorder.isSegmentPaused
                ? String(localized: "Paused, \(formatRecordingDuration(persistentRecorder.segmentDuration)) recorded. Tap to stop, or use Resume to continue.")
                : String(localized: "Stop voice recording, \(formatRecordingDuration(persistentRecorder.segmentDuration))")
        }
        if persistentRecorder.isAppRecordingTranscribing {
            if let percent = persistentRecorder.transcriptionProgress?.formattedWholePercentCompleted {
                return String(localized: "Transcribing voice capture, \(percent) complete")
            }
            return String(localized: "Transcribing voice capture")
        }
        if usageTracker.isAtLimit { return String(localized: "Unlock voice capture") }
        return recordingMode == .draft
            ? String(localized: "Start voice capture and add transcript to Capture")
            : String(localized: "Start voice capture and run \(selectedPresetActionName)")
    }

    private func prepareRecordingFeatures() {
        reloadFlows()
        consumePendingKeyboardLaunchIfNeeded()
        consumePendingWidgetRecordIfNeeded()
        watchRecordingPipeline.resume()
    }

    private func reloadPresetsIfDefaultsChanged() {
        let defaults = AppConstants.sharedDefaults
        // Ignore unrelated defaults (including draft autosaves). Compare before
        // calling store APIs so seeding/migrations cannot form an observer loop.
        guard defaults?.data(forKey: CapturePresetProfileStore.profilesKey) != observedPresetData else { return }
        reloadFlows()
    }

    private func reloadFlows() {
        flows = CapturePresetStore.loadFlows()
        observedPresetData = AppConstants.sharedDefaults?.data(forKey: CapturePresetProfileStore.profilesKey)
        viewModel.refreshVoxProfiles()
        let draftVoxID = viewModel.draft.voxID
        selectedFlowId = flows.contains(where: { $0.id == draftVoxID && $0.isEnabled })
            ? (draftVoxID ?? CapturePresetStore.generalId)
            : (viewModel.selectedVoxProfile?.id ?? CapturePresetStore.selectedFlowId())
    }

    @discardableResult
    private func selectFlow(_ flow: CapturePreset) -> Bool {
        guard viewModel.selectVox(flow.id) else { return false }
        selectedFlowId = flow.id
        WatchRecordingController.shared.publishState()
        return true
    }

    private func startInlineRecording() {
        guard microphonePermissionTask == nil else { return }
        // Live Notes: speech always goes into the open note.
        if viewModel.liveNotesEnabled { recordingMode = .draft }
        guard viewModel.requireCaptureRouteAvailable(),
              selectedFlow.id == viewModel.draft.voxID,
              CapturePresetStore.loadFlows().contains(where: { $0.id == selectedFlow.id && $0.isEnabled }) else { return }
        if usageTracker.isAtLimit {
            presentPaywall(context: .recording)
            return
        }
        let permission = AVAudioApplication.shared.recordPermission
        if permission == .undetermined {
            let flowID = selectedFlow.id
            let requestID = viewModel.draft.requestID
            microphonePermissionTask = Task {
                defer { microphonePermissionTask = nil }
                let granted = await AudioRecorder.requestMicrophonePermission()
                guard !Task.isCancelled, scenePhase != .background,
                      selectedFlow.id == flowID, viewModel.draft.requestID == requestID else { return }
                if granted {
                    // Re-enter through all route and paid-access guards after
                    // the system prompt; state may have changed while suspended.
                    microphonePermissionTask = nil
                    startInlineRecording()
                } else {
                    showsMicrophoneSettings = true
                }
            }
            return
        }
        guard permission == .granted else {
            showsMicrophoneSettings = true
            return
        }
        guard !persistentRecorder.ownsCaptureRoute else { return }

        lastStartedRecordingMode = recordingMode
        persistentRecorder.lastTranscriptionResult = nil
        viewModel.beginRecordedTranscriptInsertion(atUTF16Offset: recordingInsertionOffset)
        // Preserve the insertion point above, then release UIKit focus before
        // recording starts rather than waiting for the recording-state observer.
        dismissComposer()
        _ = persistentRecorder.startOneShotInAppSegment(
            flowId: selectedFlow.id,
            completionMode: selectedRecordingCompletionMode,
            draftRequestID: recordingMode == .draft ? viewModel.draft.requestID : nil
        )
    }

    private func togglePersistentListening() {
        if persistentRecorder.isListening {
            persistentRecorder.stopListening()
            AppConstants.sharedDefaults?.set(false, forKey: AppConstants.autoListenEnabledKey)
            keyboardLaunchPhase = nil
            withAnimation(.easeIn(duration: 0.18)) {
                keyboardReturnGuidance = nil
            }
        } else {
            handleKeyboardLaunch()
        }
    }

    private func handleAudioImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, viewModel.requireCaptureRouteAvailable(),
                  selectedFlow.id == viewModel.draft.voxID,
                  CapturePresetStore.loadFlows().contains(where: { $0.id == selectedFlow.id && $0.isEnabled }) else { return }
            if usageTracker.isAtLimit {
                presentPaywall(context: .recording)
                return
            }
            lastStartedRecordingMode = recordingMode
            persistentRecorder.lastTranscriptionResult = nil
            _ = persistentRecorder.importAudioFile(
                from: url,
                flowId: selectedFlow.id,
                completionMode: selectedRecordingCompletionMode,
                draftRequestID: recordingMode == .draft ? viewModel.draft.requestID : nil
            )
        case .failure(let error):
            persistentRecorder.lastError = error.localizedDescription
        }
    }

    private func presentPaywall(context: PaywallContext) {
        paywallContext = context
        showsPaywall = true
    }

    private func handleCaptureNeedsUnlock(_ needsUnlock: Bool) {
        guard needsUnlock else { return }
        viewModel.needsCaptureUnlock = false
        usageTracker.reload()
        guard !usageTracker.hasUnlocked else {
            Task { await viewModel.processPendingInbox() }
            return
        }
        presentPaywall(context: .captureLimit)
    }

    private func consumePendingKeyboardLaunchIfNeeded() {
        guard pendingKeyboardLaunch else { return }
        pendingKeyboardLaunch = false

        let guidance = KeyboardReturnGuidance(phase: .starting)
        withAnimation(.easeOut(duration: 0.18)) {
            keyboardReturnGuidance = guidance
        }
        handleKeyboardLaunch(guidanceID: guidance.id)
    }

    private func handleKeyboardLaunch(guidanceID: UUID? = nil) {
        keyboardLaunchPhase = .starting
        updateKeyboardReturnGuidance(.starting, id: guidanceID)
        Task { @MainActor in
            if !persistentRecorder.isListening {
                persistentRecorder.startListening()
            }
            let backendReady = await persistentRecorder.prepareTranscriptionBackend()
            let isReady = persistentRecorder.isListening && backendReady
            let completedPhase: KeyboardLaunchPhase = isReady ? .ready : .error
            keyboardLaunchPhase = completedPhase
            updateKeyboardReturnGuidance(completedPhase, id: guidanceID)
            UIAccessibility.post(
                notification: .announcement,
                argument: isReady
                    ? String(localized: "Keyboard listening is ready. Return to your keyboard to use it.")
                    : String(localized: "Keyboard listening could not start")
            )
            if isReady {
            }
            try? await Task.sleep(for: .seconds(2.5))
            if keyboardLaunchPhase == completedPhase { keyboardLaunchPhase = nil }
        }
    }

    private func updateKeyboardReturnGuidance(_ phase: KeyboardLaunchPhase, id: UUID?) {
        guard let id, var guidance = keyboardReturnGuidance, guidance.id == id else { return }
        guidance.phase = phase
        withAnimation(.easeInOut(duration: 0.18)) {
            keyboardReturnGuidance = guidance
        }
    }

    private func dismissKeyboardReturnGuidance(after delay: Duration, id: UUID) async {
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled, keyboardReturnGuidance?.id == id else { return }
        withAnimation(.easeIn(duration: 0.18)) {
            keyboardReturnGuidance = nil
        }
    }

    private func consumePendingWidgetRecordIfNeeded() {
        guard pendingWidgetRecord else { return }
        pendingWidgetRecord = false
        let request = PendingQuickRecordingRequest.consume()
        guard AppConstants.lockScreenQuickRecordEnabled else { return }

        switch request.recordingAction.command(isRecording: persistentRecorder.isSegmentActive) {
        case .none:
            return
        case .stop:
            // Stop preserves the active segment's preset and completion mode,
            // and does not require loading or changing the composer's route.
            persistentRecorder.stopInAppSegment()
            return
        case .start:
            break
        }
        Task { @MainActor in
            await viewModel.load()
            guard viewModel.requireCaptureRouteAvailable(), !persistentRecorder.isSegmentActive else { return }
            let selection = WidgetRecordingFlowSelection.resolve(requestedFlowID: request.requestedFlowID)
            // Draft delivery preserves the composer's route; the requested
            // preset supplies only the frozen voice-processing policy.
            lastStartedRecordingMode = request.draftAttachAudio == nil ? .preset : .draft
            persistentRecorder.lastTranscriptionResult = nil
            _ = persistentRecorder.startOneShotInAppSegment(
                flowId: selection.flowID,
                completionMode: request.completionMode(flowID: selection.flowID),
                origin: .quickRecord,
                draftRequestID: request.draftRequestID(in: viewModel.draft)
            )
        }
    }

    private func handleRecorderNeedsUnlock(_ needsUnlock: Bool) {
        guard needsUnlock else { return }
        persistentRecorder.needsUnlock = false
        usageTracker.reload()
        if usageTracker.isAtLimit { presentPaywall(context: .limit) }
    }

    private func dismissExportToastAfterDelay() async {
        guard fileExportToast != nil else { return }
        try? await Task.sleep(for: .seconds(3.5))
        guard !Task.isCancelled else { return }
        fileExportToast = nil
    }

    private func handleFileExportEvent(_ event: FileExportEvent?) {
        guard let event else { return }
        switch event.result {
        case .success(let url):
            fileExportToast = FileExportToast(url: url)
        case .failure(let message):
            fileExportToast = nil
            persistentRecorder.lastError = String(localized: "Your transcript was saved locally, but file export failed. \(message)")
        }
    }

    private func handleURLDeliveryEvent(_ event: URLDeliveryEvent?) {
        guard let event else { return }
        switch event.result {
        case .delivered, .disabled, .queued, .retained:
            break
        case .failed(let message, _):
            if persistentRecorder.lastError == nil {
                persistentRecorder.lastError = String(localized: "Your transcript was saved locally, but URL delivery failed. \(message)")
            }
        }
    }

    private func handleTranscribingChange(_ isTranscribing: Bool) {
        guard !isTranscribing else { return }
        if lastStartedRecordingMode == .draft, persistentRecorder.lastTranscriptionResult != nil {
            UIAccessibility.post(notification: .announcement, argument: String(localized: "Transcript added to Capture"))
        }
        watchRecordingPipeline.resume()
    }

    private func openExportedFileInFiles(_ url: URL) {
        fileExportToast = nil
        let didScopeFile = url.startAccessingSecurityScopedResource()
        UIApplication.shared.open(url, options: [:]) { success in
            if didScopeFile { url.stopAccessingSecurityScopedResource() }
            guard !success else { return }
            let folderURL = url.deletingLastPathComponent()
            let didScopeFolder = folderURL.startAccessingSecurityScopedResource()
            UIApplication.shared.open(folderURL, options: [:]) { _ in
                if didScopeFolder { folderURL.stopAccessingSecurityScopedResource() }
            }
        }
    }

    private func updateRecordingAudioLevels() async {
        recordingAudioLevels = Array(repeating: 0, count: Self.recordingWaveformBarCount)
        guard persistentRecorder.isAppRecordingSegmentActive else { return }

        while !Task.isCancelled, persistentRecorder.isAppRecordingSegmentActive {
            if let level = TranscriptionIPC.readAudioLevel() {
                recordingAudioLevels.removeFirst()
                recordingAudioLevels.append(level)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        recordingAudioLevels = Array(repeating: 0, count: Self.recordingWaveformBarCount)
    }

    private func formatRecordingDuration(_ duration: TimeInterval, padded: Bool = false) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: padded ? "%02d:%02d" : "%d:%02d", minutes, seconds)
    }

    private func captureTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private func payloadIcon(_ payload: CapturePayload) -> String {
        switch payload {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .audio, .retainedAudio: return "waveform"
        case .image: return "photo"
        case .file: return "doc"
        case .scannedDocument: return "doc.viewfinder"
        case .sketch: return "pencil.tip"
        }
    }

    private func payloadLabel(_ payload: CapturePayload) -> String {
        switch payload {
        case .text(let value): return value
        case .url(let url, let title): return title ?? url.absoluteString
        case .audio(let asset, _), .retainedAudio(let asset, _), .file(let asset):
            return asset.originalFilename
        case .image(let asset, let altText, let origin):
            return generatedAltTextLabel(altText, origin: origin) ?? asset.originalFilename
        case .scannedDocument(let pages, _, _):
            return String(localized: "Scan · \(pages.count) page(s)")
        case .sketch(_, _, let altText, let origin):
            return generatedAltTextLabel(altText, origin: origin) ?? String(localized: "Sketch")
        }
    }

    private func generatedAltTextLabel(_ altText: String?, origin: CaptureAltTextOrigin?) -> String? {
        guard origin == .generated else { return nil }
        return CaptureImageDescription.validated(altText)
    }
}

private struct BlinkingCaptureCaret: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @ScaledMetric(relativeTo: .body) private var height: CGFloat = 21
    @State private var isVisible = true

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(colorScheme == .dark ? Color.white : Color.black)
            .frame(width: 2, height: height)
            .opacity(accessibilityReduceMotion || isVisible ? 1 : 0)
            .task(id: accessibilityReduceMotion) {
                isVisible = true
                guard !accessibilityReduceMotion else { return }

                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(530))
                    guard !Task.isCancelled else { return }
                    isVisible.toggle()
                }
            }
    }
}

private struct FileExportToast: Equatable {
    let id = UUID()
    let url: URL
}

private struct FileExportToastView: View {
    let fileName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Geist.Spacing.two) {
                Image(systemName: "checkmark.circle.fill")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export Ready")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                    Text(fileName)
                        .font(Geist.body())
                        .foregroundStyle(Geist.text)
                        .lineLimit(1)
                }
                Spacer()
                Text("Open File")
                    .font(Geist.label())
            }
            .padding(.vertical, Geist.Spacing.three)
            .padding(.horizontal, 14)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
