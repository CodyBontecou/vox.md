import SwiftUI
import VoxboardShared

enum CaptureEditorToolbarCommand: Equatable {
    case undo
    case bold
    case italic
    case hashtag
    case heading(Int)
    case markdownLink
    case checklist
    case bulletList
    case paste
    case internalLink
    case timestamp
    case date
    case lowercase
    case uppercase
    case sentenceCase
    case capitalizeWords
    case slugify
}

/// Signal quick-actions bar: rests above the Capture footer while the keyboard
/// is down (`isResting`) and rides on the keyboard while typing.
///
/// The row shows the pins of the composer's current route
/// (`CaptureToolbarPreferences.pinnedActions(forRoute:)`, falling back to the
/// global default row). The trailing "•••" opens a panel with every action
/// grouped MARKDOWN / INSERT / EDIT, plus the separate ATTACH (media) group
/// and the keyboard-dismiss control.
struct CaptureEditorToolbar: View {
    var command: (CaptureEditorToolbarCommand) -> Void
    var showDueDate: () -> Void
    var insertLocation: () -> Void
    var showSketch: () -> Void
    var showCamera: () -> Void
    var showPhotos: () -> Void
    var showScreenshots: () -> Void
    var showLinkPrompt: () -> Void
    var showFiles: () -> Void
    var showScan: () -> Void
    var captureTextPages: () -> Void
    var chooseTextPhotos: () -> Void
    var canExtractText: Bool
    var canCaptureTextPages: Bool
    var isProcessingMedia: Bool
    var isFindingLocation: Bool
    @Bindable var preferences: CaptureToolbarPreferences
    /// Hides the keyboard. Shown inside the "•••" panel (per design the row
    /// itself ends with "•••" only).
    var dismissKeyboard: (() -> Void)? = nil
    /// The composer's current route (`CapturePreset.id`). `nil` uses the
    /// global default row.
    var routeID: String? = nil
    /// Shows the "•••" panel in place of the system keyboard (design: the
    /// panel replaces the keys while the bar stays pinned above it). Pass nil
    /// to restore the keyboard. When omitted, the panel expands inline.
    var presentAllActionsInKeyboardArea: ((AnyView?) -> Void)? = nil
    /// Regular-width editor header: the row sits inline on the page (no bar
    /// background or rule) and "•••" opens the full panel as a popover.
    var isInline = false
    /// Keyboard down (CaptureRestActions board): the row rests bare above the
    /// footer, without the bar's band or rule, and "•••" expands the panel
    /// inline instead of into the keyboard area.
    var isResting = false

    @State private var showsAllActions = false

    private var usesKeyboardAreaPanel: Bool {
        presentAllActionsInKeyboardArea != nil && !isResting
    }

    private var showsBand: Bool {
        !isInline && (!isResting || showsAllActions)
    }

    private var pinnedActions: [CaptureToolbarAction] {
        preferences.pinnedActions(forRoute: routeID)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(pinnedActions) { action in
                            actionControl(action, style: .chip)
                        }
                    }
                    .padding(.leading, 4)
                }
                .accessibilityLabel("Quick actions")

                Rectangle()
                    .fill(Geist.Palette.gray500)
                    .frame(width: 1, height: 24)
                    .accessibilityHidden(true)

                Button {
                    if usesKeyboardAreaPanel, let presentAllActionsInKeyboardArea {
                        showsAllActions.toggle()
                        presentAllActionsInKeyboardArea(
                            showsAllActions ? AnyView(keyboardAreaPanel) : nil
                        )
                    } else {
                        withAnimation(.snappy(duration: 0.2)) { showsAllActions.toggle() }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(showsAllActions ? Geist.bg : Geist.text)
                        .frame(width: 44, height: 40)
                        .background(
                            showsAllActions ? Geist.text : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("All quick actions")
                .accessibilityValue(showsAllActions ? Text("Expanded") : Text("Collapsed"))
                .accessibilityIdentifier("capture_quick_actions_more")
                .popover(isPresented: inlinePanelIsPresented, arrowEdge: .top) {
                    allActionsPanelContent
                        .frame(width: 380)
                        .frame(maxHeight: 420)
                        .background(Geist.Palette.gray100)
                        .presentationCompactAdaptation(.popover)
                        .accessibilityLabel("All quick actions")
                }
            }
            .frame(height: 40)
            .padding(.leading, isInline ? 0 : 8)
            .padding(.trailing, isInline ? 0 : 8)
            .padding(.vertical, isInline ? 0 : 8)
            .background(showsBand ? Geist.Palette.gray200 : Color.clear)

            if showsAllActions, !usesKeyboardAreaPanel, !isInline {
                allActionsPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if showsBand {
                Rectangle().fill(Geist.border).frame(height: 1)
            }
        }
        .onChange(of: isResting) {
            // The keyboard came up or went down: close whichever panel was
            // open so it never lingers inline over the keys, or stays
            // installed as the text view's input view after it resigns.
            guard showsAllActions else { return }
            showsAllActions = false
            presentAllActionsInKeyboardArea?(nil)
        }
        .onDisappear {
            // Recording or a layout change can remove the bar; never leave the
            // panel installed as the text view's input view.
            if showsAllActions { presentAllActionsInKeyboardArea?(nil) }
        }
    }

    private var inlinePanelIsPresented: Binding<Bool> {
        Binding(
            get: { isInline && showsAllActions },
            set: { if !$0 { showsAllActions = false } }
        )
    }

    /// The panel as hosted in the keyboard area (fills the keyboard frame).
    private var keyboardAreaPanel: some View {
        allActionsPanelContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Geist.Palette.gray100.ignoresSafeArea())
            .accessibilityLabel("All quick actions")
    }

    // MARK: All-actions panel

    private var allActionsPanel: some View {
        allActionsPanelContent
            .frame(maxHeight: 236)
            .background(Geist.Palette.gray100)
            .accessibilityLabel("All quick actions")
    }

    private var allActionsPanelContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(CaptureQuickActionGroup.allCases) { group in
                    HStack {
                        Text(group.title)
                            .font(Geist.mono(size: 10.5, relativeTo: .caption2))
                            .tracking(0.6)
                            .foregroundStyle(Geist.muted)
                        Spacer()
                        if group == .markdown, !isResting, let dismissKeyboard {
                            Button(action: dismissKeyboard) {
                                Label("Hide keyboard", systemImage: "keyboard.chevron.compact.down")
                                    .labelStyle(.iconOnly)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Geist.text)
                                    .frame(width: 44, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Dismiss keyboard")
                        }
                    }
                    .padding(.horizontal, 4)

                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                        spacing: 6
                    ) {
                        ForEach(group.actions) { action in
                            actionControl(action, style: .tile)
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    // MARK: Actions

    private enum ControlStyle { case chip, tile }

    @ViewBuilder
    private func actionControl(_ action: CaptureToolbarAction, style: ControlStyle) -> some View {
        switch action {
        case .addMedia:
            Menu {
                Button(action: showSketch) {
                    Label("Sketch", systemImage: "pencil.tip")
                }
                Button(action: showCamera) {
                    Label("Camera", systemImage: "camera")
                }
                Button(action: showPhotos) {
                    Label("Photo", systemImage: "photo")
                }
                Button(action: showScreenshots) {
                    Label("Screenshot", systemImage: "rectangle.inset.filled.and.person.filled")
                }
                Divider()
                Button(action: showLinkPrompt) {
                    Label("Web Link", systemImage: "link")
                }
            } label: {
                actionLabel(action, style: style)
            }
            .disabled(isProcessingMedia)

        case .addFiles:
            actionButton(action, style: style, perform: showFiles)
                .disabled(isProcessingMedia)

        case .scanDocument:
            actionButton(action, style: style, perform: showScan)
                .disabled(isProcessingMedia)

        case .extractText:
            Menu {
                Button(action: captureTextPages) {
                    Label("Capture Journal Pages", systemImage: "camera.viewfinder")
                }
                .disabled(!canCaptureTextPages)
                Button(action: chooseTextPhotos) {
                    Label("Choose Journal Photos", systemImage: "photo.on.rectangle")
                }
            } label: {
                actionLabel(action, style: style)
            }
            .disabled(isProcessingMedia || !canExtractText)

        case .sketch:
            actionButton(action, style: style, perform: showSketch)

        case .undo:
            actionButton(action, style: style) { command(.undo) }

        case .formatMarkdown:
            Menu {
                Button("Bold") { command(.bold) }
                Button("Italic") { command(.italic) }
                Button("Hashtag") { command(.hashtag) }
                Divider()
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { command(.heading(level)) }
                }
            } label: {
                actionLabel(action, style: style)
            }

        case .heading:
            Menu {
                ForEach(1...6, id: \.self) { level in
                    Button("Heading \(level)") { command(.heading(level)) }
                }
            } label: {
                actionLabel(action, style: style)
            } primaryAction: {
                command(.heading(2))
            }

        case .bold:
            actionButton(action, style: style) { command(.bold) }

        case .italic:
            actionButton(action, style: style) { command(.italic) }

        case .tag:
            actionButton(action, style: style) { command(.hashtag) }

        case .markdownLink:
            actionButton(action, style: style) { command(.markdownLink) }

        case .dueDate:
            actionButton(action, style: style, perform: showDueDate)

        case .checklist:
            actionButton(action, style: style) { command(.checklist) }

        case .bulletList:
            actionButton(action, style: style) { command(.bulletList) }

        case .paste:
            actionButton(action, style: style) { command(.paste) }

        case .internalLink:
            actionButton(action, style: style) { command(.internalLink) }

        case .currentLocation:
            actionButton(action, style: style, perform: insertLocation)
                .disabled(isFindingLocation)
                .opacity(isFindingLocation ? 0.5 : 1)

        case .timestamp:
            actionButton(action, style: style) { command(.timestamp) }

        case .date:
            actionButton(action, style: style) { command(.date) }

        case .textCase:
            Menu {
                Button("Lowercase") { command(.lowercase) }
                Button("Uppercase") { command(.uppercase) }
                Button("Sentence case") { command(.sentenceCase) }
                Button("Capitalize case") { command(.capitalizeWords) }
                Button("Slugify case") { command(.slugify) }
            } label: {
                actionLabel(action, style: style)
            }
        }
    }

    private func actionButton(
        _ action: CaptureToolbarAction,
        style: ControlStyle,
        perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            actionLabel(action, style: style)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func actionLabel(_ action: CaptureToolbarAction, style: ControlStyle) -> some View {
        switch style {
        case .chip:
            glyphView(action, size: 13)
                .padding(.horizontal, action.isMedia ? 0 : 10)
                .foregroundStyle(Geist.text)
                .frame(minWidth: 40, minHeight: 40)
                .background(Geist.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Geist.border, lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel(action.accessibilityLabel)
        case .tile:
            VStack(spacing: 1) {
                glyphView(action, size: 13)
                    .foregroundStyle(Geist.text)
                Text(action.shortTitle)
                    .font(Geist.caption(.caption2))
                    .foregroundStyle(Geist.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Geist.border, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(action.accessibilityLabel)
        }
    }

    @ViewBuilder
    private func glyphView(_ action: CaptureToolbarAction, size: CGFloat) -> some View {
        if let text = CaptureQuickActionGlyph.text(for: action, timestampFormat: preferences.timestampFormat) {
            Text(verbatim: text)
                .font(Geist.mono(size: size, relativeTo: .footnote, medium: true))
                .lineLimit(1)
                .fixedSize()
        } else if let systemImage = action.systemImage {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
        }
    }
}

/// Design text glyphs, with live values for Time ("10:42") and Date ("11-01").
enum CaptureQuickActionGlyph {
    static func text(
        for action: CaptureToolbarAction,
        timestampFormat: CaptureTimestampFormat,
        now: Date = .now
    ) -> String? {
        switch action {
        case .timestamp:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = timestampFormat == .twentyFourHour ? "HH:mm" : "h:mm"
            return formatter.string(from: now)
        case .date:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MM-dd"
            return formatter.string(from: now)
        default:
            return action.textIcon
        }
    }
}
