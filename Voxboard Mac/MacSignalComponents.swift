import AppKit
import AVFoundation
import SwiftUI
import VoxboardShared

// Shared building blocks for the Signal Mac layouts: route catalog and
// tiles, quick-action shortcuts, the All Shortcuts sheet, Markdown preview
// blocks and styling, waveform bars, and busy-file retry wiring.

extension Notification.Name {
    static let macShowAllShortcuts = Notification.Name("VoxboardMacShowAllShortcuts")
}

// MARK: - Routes

@MainActor
enum MacRouteCatalog {
    static func enabledRoutes(in viewModel: QuickCaptureViewModel) -> [CapturePresetProfile] {
        viewModel.voxProfiles.filter(\.isEnabled)
    }

    static func displayName(_ route: CapturePresetProfile) -> String {
        route.visibleName ?? String(localized: "Icon-only route")
    }

    static func letter(_ route: CapturePresetProfile) -> String {
        if let emoji = route.emoji, !emoji.isEmpty { return emoji }
        return String((route.visibleName ?? "•").prefix(1)).uppercased()
    }

    /// "⌘1"…"⌘4" for the first four routes.
    static func shortcutLabel(forIndex index: Int) -> String? {
        index < 4 ? "⌘\(index + 1)" : nil
    }

    static func select(_ route: CapturePresetProfile, in viewModel: QuickCaptureViewModel) {
        guard viewModel.canChangeCaptureRoute else { return }
        _ = viewModel.selectVox(route.id)
    }

    /// The selected route's delivery heading as Markdown (`## Notes`).
    static func headingMarkdown(for destination: CaptureDestination?) -> String? {
        guard let destination,
              case .beneathHeading(let selector, _, _) = destination.placement else { return nil }
        return String(repeating: "#", count: max(1, min(6, selector.level ?? 2))) + " " + selector.title
    }

    /// "Vault / folder / note.md · ## Heading" for the workspace header.
    static func breadcrumb(for viewModel: QuickCaptureViewModel) -> String? {
        guard let preview = viewModel.resolvedDestinationPreview else { return nil }
        let path = preview.replacingOccurrences(of: "/", with: " / ")
            .replacingOccurrences(of: "  ", with: " ")
        if let heading = headingMarkdown(for: viewModel.selectedDestination) {
            return path + " · " + heading
        }
        return path
    }

    /// "→ Tasks.md › ## Today" for the Quick Capture footer.
    static func destinationSummary(for viewModel: QuickCaptureViewModel) -> String {
        guard let preview = viewModel.resolvedDestinationPreview else {
            return String(localized: "→ Choose a destination")
        }
        let file = (preview as NSString).lastPathComponent
        if let heading = headingMarkdown(for: viewModel.selectedDestination) {
            return "→ \(file) › \(heading)"
        }
        return "→ \(file)"
    }
}

/// Signal route tile: first route indigo, second ink, the rest neutral.
struct MacRouteTile: View {
    let letter: String
    let index: Int
    var size: CGFloat = 22

    var body: some View {
        SignalRouteTile(
            letter: letter,
            size: size,
            isPrimary: index == 0,
            isInk: index == 1
        )
    }
}

// MARK: - Quick actions

/// Mac keyboard shortcuts for the composer quick-action chips (Signal
/// MacWorkspace design).
enum MacQuickActionShortcut {
    static func shortcut(for action: CaptureToolbarAction) -> KeyboardShortcut? {
        switch action {
        case .timestamp: KeyboardShortcut("t", modifiers: [.option, .command])
        case .checklist: KeyboardShortcut("l", modifiers: [.command])
        case .internalLink: KeyboardShortcut("k", modifiers: [.command])
        case .heading: KeyboardShortcut("2", modifiers: [.command, .option])
        case .bulletList: KeyboardShortcut("8", modifiers: [.command, .shift])
        // The design's ⇧⌘3 ("#") is the system screenshot shortcut and never
        // reaches the app, and ⌃⌘3 opens Library. ⌥⌘3 keeps the "3"/"#" key
        // and sits next to Heading's ⌥⌘2.
        case .tag: KeyboardShortcut("3", modifiers: [.option, .command])
        case .bold: KeyboardShortcut("b", modifiers: [.command])
        case .italic: KeyboardShortcut("i", modifiers: [.command])
        case .currentLocation: KeyboardShortcut("l", modifiers: [.option, .command])
        case .textCase: KeyboardShortcut("c", modifiers: [.control, .command])
        case .markdownLink: KeyboardShortcut("k", modifiers: [.command, .shift])
        case .date: KeyboardShortcut("d", modifiers: [.option, .command])
        case .dueDate: KeyboardShortcut("u", modifiers: [.option, .command])
        default: nil
        }
    }

    static func displayString(for action: CaptureToolbarAction) -> String? {
        guard let shortcut = shortcut(for: action) else { return nil }
        return displayString(shortcut)
    }

    static func displayString(_ shortcut: KeyboardShortcut) -> String {
        var result = ""
        if shortcut.modifiers.contains(.control) { result += "⌃" }
        if shortcut.modifiers.contains(.option) { result += "⌥" }
        if shortcut.modifiers.contains(.shift) { result += "⇧" }
        if shortcut.modifiers.contains(.command) { result += "⌘" }
        switch shortcut.key {
        case .return: result += "↩"
        case .space: result += "Space"
        case .escape: result += "esc"
        default: result += String(shortcut.key.character).uppercased()
        }
        return result
    }
}

// MARK: - All shortcuts

struct MacAllShortcutsSheet: View {
    let quickActions: [CaptureToolbarAction]
    let routes: [CapturePresetProfile]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("All Shortcuts")
                    .font(Geist.heading(.title2))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            GeistDivider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    group("CAPTURE", rows: [
                        (String(localized: "Quick capture (hold to talk)"), MacHotKeyStore.quickCaptureDisplayString ?? String(localized: "Off")),
                        (String(localized: "Send"), "⌘↩"),
                        (String(localized: "New capture"), "⌘N"),
                        (String(localized: "Start or stop recording"), "⇧⌘R"),
                        (String(localized: "Add files"), "⇧⌘A"),
                        (String(localized: "Close quick capture"), "esc"),
                    ])
                    group("ROUTES", rows: routes.prefix(4).enumerated().map { index, route in
                        (MacRouteCatalog.displayName(route), "⌘\(index + 1)")
                    })
                    group("QUICK ACTIONS", rows: quickActions.compactMap { action in
                        MacQuickActionShortcut.displayString(for: action).map { (action.accessibilityLabel, $0) }
                    })
                    group("NAVIGATE", rows: [
                        (String(localized: "Capture"), "⌃⌘1"),
                        (String(localized: "Activity"), "⌃⌘2"),
                        (String(localized: "Library"), "⌃⌘3"),
                        (String(localized: "Search Library"), "⌘F"),
                        (String(localized: "All shortcuts"), "⌘/"),
                        (String(localized: "Settings"), "⌘,"),
                    ])
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 560)
        .background(Geist.Palette.gray100)
    }

    private func group(_ title: LocalizedStringKey, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MacSignalSectionHeader(title)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack {
                        Text(row.0)
                            .font(Geist.body(.callout))
                            .foregroundStyle(Geist.text)
                        Spacer()
                        Text(verbatim: row.1)
                            .font(Geist.mono(size: 12, relativeTo: .caption))
                            .foregroundStyle(Geist.muted)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    if index < rows.count - 1 { GeistDivider() }
                }
            }
            .background(Geist.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Geist.border, lineWidth: 1)
            }
        }
    }
}

// MARK: - Markdown preview block

/// Dark mono block used for "WILL WRITE" (inspector) and "what was written"
/// (Library).
struct MacMarkdownBlock: View {
    var label: LocalizedStringKey?
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label)
                    .textCase(.uppercase)
                    .font(Geist.mono(size: 10.5, relativeTo: .caption2))
                    .tracking(0.63)
                    .foregroundStyle(Color(nsColor: NSColor(srgbRed: 0x9A / 255, green: 0x9A / 255, blue: 0x95 / 255, alpha: 1)))
            }
            Text(verbatim: markdown)
                .font(Geist.mono(size: 12, relativeTo: .caption))
                .lineSpacing(4)
                .foregroundStyle(Color(nsColor: NSColor(srgbRed: 0xE9 / 255, green: 0xE9 / 255, blue: 0xE4 / 255, alpha: 1)))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(
            Color(nsColor: NSColor(srgbRed: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255, alpha: 1)),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        // In dark mode the fixed #121212 block sits on a #0B0B0B–#1A1A1A
        // ground; a hairline keeps it a distinct block (invisible in light).
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Self.darkEdge, lineWidth: 1)
        }
    }

    private static let darkEdge = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(Geist.Palette.gray400)
            : .clear
    })
}

// MARK: - Composer Markdown styling

extension NSAttributedString.Key {
    /// Marks the `[ ]` / `[x]` of a Markdown task so the composer can draw a
    /// real checkbox over it. Value: `NSNumber(bool:)`, true when checked.
    static let macTaskCheckbox = NSAttributedString.Key("VoxboardMacTaskCheckbox")
}

/// Live Markdown styling for the AppKit editors. The string stays plain
/// Markdown; only display attributes change.
@MainActor
enum MacMarkdownSyntaxStyler {
    /// Per-surface sizes and task rendering.
    struct Style: Equatable {
        var bodySize: CGFloat
        /// H1…H6 point sizes.
        var headingSizes: [CGFloat]
        var lineHeightMultiple: CGFloat
        /// The composer hides `- [ ]` and draws a clickable checkbox instead.
        var rendersTaskCheckboxes: Bool
        /// Muted color for `- [ ]` markers when they stay visible.
        var taskMarkerColor: NSColor?

        /// Signal MacWorkspace document: 40pt H1, 18pt body, real checkboxes.
        static let document = Style(
            bodySize: 18,
            headingSizes: [40, 28, 22, 20, 19, 18],
            lineHeightMultiple: 1.35,
            rendersTaskCheckboxes: true,
            taskMarkerColor: nil
        )

        /// Signal MacQuickCapture panel: 20pt with muted `- [ ]` markers.
        static let quickCapture = Style(
            bodySize: 20,
            headingSizes: [28, 24, 22, 21, 20, 20],
            lineHeightMultiple: 1.3,
            rendersTaskCheckboxes: false,
            taskMarkerColor: NSColor(srgbRed: 0x8A / 255, green: 0x8A / 255, blue: 0x85 / 255, alpha: 1)
        )
    }

    /// Checkbox side length and the width reserved for `[ ]` in the composer.
    static let checkboxSize: CGFloat = 18
    static let checkboxSlotWidth: CGFloat = 24

    private static let headingRegex = try! NSRegularExpression(pattern: "^(#{1,6})[ \\t]+.*$", options: [.anchorsMatchLines])
    private static let taskRegex = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+] )(\\[([ xX])\\])(.*)$", options: [.anchorsMatchLines])
    private static let bulletRegex = try! NSRegularExpression(pattern: "^([ \\t]*[-*+])[ \\t](?!\\[[ xX]\\])", options: [.anchorsMatchLines])
    private static let boldRegex = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    private static let italicRegex = try! NSRegularExpression(pattern: "(?<![*_\\w])([*_])(?=\\S)([^*_\\n]+?)(?<=\\S)\\1(?![*_\\w])")
    private static let wikiLinkRegex = try! NSRegularExpression(pattern: "!?\\[\\[[^\\]\\n]+\\]\\]")
    private static let linkRegex = try! NSRegularExpression(pattern: "\\[[^\\]\\n]+\\]\\([^)\\n]+\\)")
    private static let tagRegex = try! NSRegularExpression(pattern: "(?<![\\w#&/])#[\\p{L}\\p{N}_/-]*\\p{L}[\\p{L}\\p{N}_/-]*")
    private static let codeRegex = try! NSRegularExpression(pattern: "`[^`\\n]+`")
    private static let quoteRegex = try! NSRegularExpression(pattern: "^>.*$", options: [.anchorsMatchLines])

    static func apply(to textView: NSTextView) {
        let composer = textView as? MacComposerTextView
        apply(to: textView, style: composer?.markdownStyle ?? .document)
        composer?.markdownDidRestyle()
    }

    static func apply(to textView: NSTextView, style: Style) {
        guard let storage = textView.textStorage else { return }
        let text = storage.string as NSString
        let fullRange = NSRange(location: 0, length: text.length)
        let base = font(size: style.bodySize, weight: "Regular")
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = style.lineHeightMultiple
        let muted = NSColor.secondaryLabelColor
        let accent = MacBrand.appKitOrange

        storage.beginEditing()
        storage.setAttributes([
            .font: base,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph,
        ], range: fullRange)

        for match in headingRegex.matches(in: storage.string, range: fullRange) {
            let level = match.range(at: 1).length
            let size = style.headingSizes[min(level, style.headingSizes.count) - 1]
            storage.addAttribute(.font, value: font(size: size, weight: "SemiBold"), range: match.range)
            storage.addAttribute(.kern, value: level == 1 ? -size * 0.025 : -0.2, range: match.range)
            storage.addAttribute(.foregroundColor, value: NSColor.tertiaryLabelColor, range: match.range(at: 1))
            if level == 1 {
                let headingParagraph = NSMutableParagraphStyle()
                headingParagraph.lineHeightMultiple = 1.1
                headingParagraph.paragraphSpacing = style.bodySize * 0.5
                storage.addAttribute(.paragraphStyle, value: headingParagraph, range: match.range)
            }
        }
        for match in taskRegex.matches(in: storage.string, range: fullRange) {
            let dashRange = match.range(at: 2)
            let boxRange = match.range(at: 3)
            let checked = text.substring(with: match.range(at: 4)).lowercased() == "x"
            if style.rendersTaskCheckboxes {
                // Keep "- [ ]" in the string but draw a checkbox in its place.
                storage.addAttributes([
                    .font: font(size: 1, weight: "Regular"),
                    .foregroundColor: NSColor.clear,
                ], range: dashRange)
                let boxFont = font(size: style.bodySize, weight: "Regular")
                let natural = NSAttributedString(string: "[ ]", attributes: [.font: boxFont]).size().width
                storage.addAttributes([
                    .font: boxFont,
                    .foregroundColor: NSColor.clear,
                    .kern: (checkboxSlotWidth - natural) / 3,
                    .macTaskCheckbox: NSNumber(value: checked),
                ], range: boxRange)
            } else {
                let markerRange = NSRange(location: dashRange.location, length: NSMaxRange(boxRange) - dashRange.location)
                storage.addAttribute(.foregroundColor, value: style.taskMarkerColor ?? accent, range: markerRange)
            }
            if checked {
                var labelRange = match.range(at: 5)
                while labelRange.length > 0,
                      text.character(at: labelRange.location) == 0x20 || text.character(at: labelRange.location) == 0x09 {
                    labelRange.location += 1
                    labelRange.length -= 1
                }
                storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: labelRange)
                storage.addAttribute(.foregroundColor, value: muted, range: labelRange)
            }
        }
        for match in bulletRegex.matches(in: storage.string, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: muted, range: match.range(at: 1))
        }
        for match in boldRegex.matches(in: storage.string, range: fullRange) {
            let current = (storage.attribute(.font, at: match.range.location, effectiveRange: nil) as? NSFont) ?? base
            storage.addAttribute(.font, value: font(size: current.pointSize, weight: "SemiBold"), range: match.range)
            storage.addAttribute(.foregroundColor, value: muted, range: match.range(at: 1))
            storage.addAttribute(.foregroundColor, value: muted, range: NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length))
        }
        for match in italicRegex.matches(in: storage.string, range: fullRange) {
            let current = (storage.attribute(.font, at: match.range.location, effectiveRange: nil) as? NSFont) ?? base
            let italic = NSFontManager.shared.convert(current, toHaveTrait: .italicFontMask)
            storage.addAttribute(.font, value: italic, range: match.range)
            storage.addAttribute(.obliqueness, value: 0.18, range: match.range)
        }
        for regex in [wikiLinkRegex, linkRegex, tagRegex] {
            for match in regex.matches(in: storage.string, range: fullRange) {
                storage.addAttribute(.foregroundColor, value: accent, range: match.range)
            }
        }
        for match in codeRegex.matches(in: storage.string, range: fullRange) {
            storage.addAttribute(.font, value: mono(size: style.bodySize - 2), range: match.range)
            storage.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor, range: match.range)
        }
        for match in quoteRegex.matches(in: storage.string, range: fullRange) {
            storage.addAttribute(.foregroundColor, value: muted, range: match.range)
        }
        if let composer = textView as? MacComposerTextView {
            composer.styleInlineAudioAnchors(in: storage)
        }
        storage.endEditing()
        textView.typingAttributes = [
            .font: base,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraph,
        ]
    }

    static func font(size: CGFloat, weight: String) -> NSFont {
        NSFont(name: "Geist-\(weight)", size: size)
            ?? .systemFont(ofSize: size, weight: weight == "Regular" ? .regular : .semibold)
    }

    private static func mono(size: CGFloat) -> NSFont {
        NSFont(name: "GeistMono-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: .regular)
    }
}

// MARK: - Waveform

/// Live microphone bars (Signal Quick Capture): ~40 bars, newest on the
/// right, the most recent few in recording red.
struct MacWaveformBars: View {
    let levels: [Float]
    var isLive = true
    var height: CGFloat = 20

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 1)
                    .fill(isLive && index >= levels.count - 6
                          ? MacBrand.recording
                          : Color(nsColor: NSColor(srgbRed: 0x4A / 255, green: 0x4A / 255, blue: 0x47 / 255, alpha: 1)))
                    .frame(maxWidth: .infinity)
                    .frame(height: 3 + CGFloat(level) * (height - 4))
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.1), value: levels)
        .accessibilityHidden(true)
    }
}

// MARK: - Library helpers

enum MacCaptureSourceLabel {
    /// Friendly origin for Library "FROM": iPhone, Watch, Keyboard, Mac…
    static func label(for source: CaptureSource) -> String {
        switch source {
        case .app, .widget, .shortcut, .deepLink, .voice: String(localized: "iPhone")
        case .keyboard: String(localized: "Keyboard")
        case .shareExtension: String(localized: "Share sheet")
        case .watch: String(localized: "Watch")
        case .mac: String(localized: "Mac")
        case .fileImport: String(localized: "File import")
        }
    }

    /// Record-level origin: "Mac · ⌥Space" for Quick Capture panel sends.
    static func label(for record: CaptureHistoryRecord) -> String {
        if record.source == .mac,
           record.sourceDetail == CaptureHistoryRecord.macQuickCaptureSourceDetail {
            let shortcut = MacHotKeyStore.quickCaptureDisplayString ?? "⌥Space"
            return String(localized: "Mac · \(shortcut)")
        }
        return label(for: record.source)
    }
}

enum MacObsidianLink {
    /// `obsidian://open?vault=<vault>&file=<path without .md>`
    static func url(vaultName: String, relativePath: String) -> URL? {
        var file = relativePath
        if file.lowercased().hasSuffix(".md") { file = String(file.dropLast(3)) }
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [
            URLQueryItem(name: "vault", value: vaultName),
            URLQueryItem(name: "file", value: file),
        ]
        return components.url
    }

    static var isInstalled: Bool {
        guard let url = URL(string: "obsidian://open") else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
    }
}

// MARK: - Busy-file retry

@MainActor
enum MacFileBusyRetry {
    static func configureMonitor() {
        let monitor = CaptureFileBusyMonitor.shared
        monitor.isDetectionEnabled = true
        monitor.policy = storedPolicy
    }

    static var storedPolicy: CaptureFileBusyPolicy {
        (AppConstants.sharedDefaults ?? .standard)
            .string(forKey: CaptureFileBusyPolicy.storageKey)
            .flatMap(CaptureFileBusyPolicy.init(rawValue:)) ?? .waitAndRetry
    }

    static func setPolicy(_ policy: CaptureFileBusyPolicy) {
        (AppConstants.sharedDefaults ?? .standard).set(policy.rawValue, forKey: CaptureFileBusyPolicy.storageKey)
        CaptureFileBusyMonitor.shared.policy = policy
    }

    /// Retries every busy capture whose minute has elapsed.
    static func retryDue(
        viewModel: QuickCaptureViewModel,
        recorder: MacRecorder,
        modelManager: ModelManager,
        now: Date = Date(),
        force: Bool = false
    ) async {
        let due = CaptureFileBusyMonitor.shared.entries.filter { force || $0.nextRetryAt <= now }
        guard !due.isEmpty else { return }
        await retry(due.map(\.requestID), viewModel: viewModel, recorder: recorder, modelManager: modelManager)
    }

    static func retry(
        _ requestIDs: [UUID],
        viewModel: QuickCaptureViewModel,
        recorder: MacRecorder,
        modelManager: ModelManager
    ) async {
        let ids = Set(requestIDs)
        if ids.contains(viewModel.draft.requestID), !viewModel.isSubmitting, viewModel.canSubmit {
            await viewModel.submit()
        }
        for job in recorder.recordingQueue.actionableJobs where ids.contains(job.id) && job.phase == .failed {
            await recorder.recordingQueue.retry(
                job,
                modelID: modelManager.selectedModelId,
                fallbackModelID: modelManager.preferredFallbackModelID,
                replaceFallbackModelID: true,
                language: modelManager.selectedLanguage,
                delivery: nil
            )
        }
        if viewModel.failedInboxCount > 0 {
            await viewModel.retryFailedInbox()
        }
    }
}

/// Observable mirror of `CaptureFileBusyMonitor.shared` for SwiftUI.
@MainActor
@Observable
final class MacFileBusyStore {
    static let shared = MacFileBusyStore()

    private(set) var entries: [CaptureFileBusyEntry] = CaptureFileBusyMonitor.shared.entries
    @ObservationIgnored private var observer: NSObjectProtocol?

    private init() {
        observer = NotificationCenter.default.addObserver(
            forName: CaptureFileBusyMonitor.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func reload() {
        entries = CaptureFileBusyMonitor.shared.entries
    }

    func entry(for requestID: UUID) -> CaptureFileBusyEntry? {
        entries.first { $0.requestID == requestID }
    }
}

// MARK: - Activity counts

@MainActor
enum MacActivityCounts {
    static func needsYou(queue: RecordingJobQueue, viewModel: QuickCaptureViewModel) -> Int {
        let failedJobs = queue.actionableJobs.filter { $0.phase == .failed }
        let jobIDs = Set(failedJobs.map(\.id))
        // Every busy note is a Needs you card in Activity (MacActivity:
        // "Tasks.md is open with unsaved changes" counts as 1), not only the
        // open draft's. Failed jobs that are also busy count once.
        let busyCount = MacFileBusyStore.shared.entries.filter { !jobIDs.contains($0.requestID) }.count
        return failedJobs.count + viewModel.failedInboxCount + busyCount
    }

    static func deliveredToday(_ records: [CaptureHistoryRecord], calendar: Calendar = .current) -> [CaptureHistoryRecord] {
        records.filter { record in
            record.outcome == .delivered
                && calendar.isDateInToday(record.deliveredAt ?? record.createdAt)
        }
    }
}

// MARK: - Send to…

/// "Send to…" button that presents `NSSharingServicePicker` anchored to
/// itself.
struct MacSharingPickerButton: View {
    let title: String
    let items: () -> [Any]
    @State private var anchor = MacSharingAnchor.Box()

    var body: some View {
        // A Signal secondary button (white, hairline border) like its
        // neighbours; the picker anchors to the button's own bounds.
        Button(title) {
            guard let view = anchor.view else { return }
            NSSharingServicePicker(items: items())
                .show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        .buttonStyle(GeistButtonStyle(variant: .secondary, size: .small))
        .background(MacSharingAnchor(box: anchor))
    }
}

/// Captures the NSView behind a SwiftUI control so AppKit pickers can anchor to it.
struct MacSharingAnchor: NSViewRepresentable {
    final class Box { weak var view: NSView? }
    let box: Box

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        box.view = view
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        box.view = nsView
    }
}

// MARK: - Route steps and WILL WRITE preview

@MainActor
enum MacCapturePreview {
    struct Step: Identifiable {
        let kind: String
        let title: String
        var id: String { kind }
    }

    /// CAPTURE / PROCESS / SHAPE / DELIVER for the selected route.
    static func steps(for viewModel: QuickCaptureViewModel) -> [Step] {
        let profile = viewModel.selectedVoxProfile
        let destination = viewModel.selectedDestination
        let process: String
        if let profile, profile.captureProcessingEnabled, profile.postProcessingMode != .none {
            process = "\(profile.postProcessingMode.displayName) · " + String(localized: "on device")
        } else {
            process = String(localized: "As typed · no processing")
        }
        let shape: String
        if let template = entryTemplate(for: viewModel) {
            shape = template.name
        } else if let destination, !(destination.entryPrefix + destination.entrySuffix).isEmpty {
            shape = destination.entryPrefix.contains("{time")
                ? String(localized: "Timestamped entry")
                : String(localized: "Route template")
        } else {
            shape = String(localized: "Plain entry")
        }
        return [
            Step(kind: "CAPTURE", title: String(localized: "Voice, text, photos, scans")),
            Step(kind: "PROCESS", title: process),
            Step(kind: "SHAPE", title: shape),
            Step(kind: "DELIVER", title: deliverSummary(for: viewModel)),
        ]
    }

    static func deliverSummary(for viewModel: QuickCaptureViewModel) -> String {
        guard let destination = viewModel.selectedDestination else {
            return String(localized: "Choose a destination")
        }
        let note: String
        switch destination.noteTarget {
        case .rollingNote(_, let period):
            note = period == .daily ? String(localized: "Daily note") : String(localized: "\(period.rawValue.capitalized) note")
        case .newNote:
            note = String(localized: "New note")
        case .existingNote(let path):
            note = (path as NSString).lastPathComponent
        }
        if let override = viewModel.draft.relativeNotePathOverride {
            return (override as NSString).lastPathComponent + " · " + String(localized: "append")
        }
        let placement = viewModel.draft.placementOverride ?? destination.placement
        switch placement {
        case .append:
            return note + " · " + String(localized: "append")
        case .prepend:
            return note + " · " + String(localized: "prepend")
        case .beneathHeading:
            let heading = MacRouteCatalog.headingMarkdown(for: destination) ?? ""
            return note + " › " + heading + " · " + String(localized: "append")
        }
    }

    static func entryTemplate(for viewModel: QuickCaptureViewModel) -> CaptureEntryTemplate? {
        let id = viewModel.draft.entryTemplateID ?? viewModel.selectedDestination?.entryTemplateID
        guard let id else { return nil }
        return viewModel.entryTemplates.first { $0.id == id }
    }

    /// The Markdown this draft will write (prefix + rendered entry + suffix),
    /// rendered with the same `CaptureMarkdownRenderer` the pipeline uses.
    static func willWrite(for viewModel: QuickCaptureViewModel, now: Date = Date()) -> String? {
        guard let destination = viewModel.selectedDestination,
              let destinationID = viewModel.effectiveDestinationID,
              viewModel.draft.hasCaptureContent,
              let request = try? viewModel.draft.makeRequest(
                source: .mac,
                resolvedDestinationID: destinationID,
                voxProfile: viewModel.selectedVoxProfile
              ),
              let entry = try? CaptureMarkdownRenderer().render(request, for: destination) else {
            return nil
        }
        let template = entryTemplate(for: viewModel)
        let renderer = CaptureEntryTemplateRenderer()
        let prefix = renderer.render(template?.entryPrefix ?? destination.entryPrefix, for: request)
        let suffix = renderer.render(template?.entrySuffix ?? destination.entrySuffix, for: request)
        let rendered = (prefix + entry + suffix).trimmingCharacters(in: .newlines)
        let maxLength = 900
        return rendered.count > maxLength ? String(rendered.prefix(maxLength)) + "…" : rendered
    }
}

// MARK: - Inline audio chip

/// "2026-11-01-1042.m4a · 1:59 · 2 speakers" with play/pause.
struct MacAudioAttachmentChip: View {
    let url: URL
    let filename: String
    var speakerCount: Int = 0
    var onRemove: (() -> Void)?

    @State private var player: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var duration: TimeInterval?
    @State private var progressTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Geist.Palette.background100)
                    .frame(width: 34, height: 34)
                    .background(Geist.text, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause \(filename)" : "Play \(filename)")

            Text(verbatim: summary)
                .font(Geist.mono(size: 12, relativeTo: .caption))
                .foregroundStyle(Geist.muted)
                .lineLimit(1)

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Geist.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(filename)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: 420, alignment: .leading)
        .background(Geist.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Geist.border, lineWidth: 1)
        }
        .task(id: url) {
            let asset = AVURLAsset(url: url)
            if let time = try? await asset.load(.duration), time.seconds.isFinite {
                duration = time.seconds
            }
        }
        .onDisappear {
            player?.stop()
            progressTask?.cancel()
        }
    }

    private var summary: String {
        var parts = [filename]
        if let duration {
            parts.append(String(format: "%d:%02d", Int(duration) / 60, Int(duration) % 60))
        }
        if speakerCount > 1 { parts.append(String(localized: "\(speakerCount) speakers")) }
        return parts.joined(separator: " · ")
    }

    private func togglePlayback() {
        if isPlaying {
            player?.pause()
            isPlaying = false
            return
        }
        if player == nil { player = try? AVAudioPlayer(contentsOf: url) }
        guard let player else { return }
        player.play()
        isPlaying = true
        progressTask?.cancel()
        progressTask = Task { @MainActor in
            while !Task.isCancelled, player.isPlaying {
                try? await Task.sleep(for: .milliseconds(250))
            }
            isPlaying = false
        }
    }

    /// Distinct "Speaker N" labels in a diarized transcript.
    static func speakerCount(in transcript: String?) -> Int {
        guard let transcript,
              let regex = try? NSRegularExpression(pattern: "Speaker\\s+(\\d+)", options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(transcript.startIndex..., in: transcript)
        let labels = Set(regex.matches(in: transcript, range: range).compactMap { match -> String? in
            Range(match.range(at: 1), in: transcript).map { String(transcript[$0]) }
        })
        return labels.count
    }
}

// MARK: - Menu bar commands for the chrome-less Signal window

/// The Signal boards draw no window toolbar, so the Capture, Activity and
/// Library commands that used to live there are published to the menu bar
/// through focused scene values.
enum MacCaptureAttachItem: CaseIterable {
    case images, photo, scan, sketch, files, audio, transcribe, webLink, paste
}

enum MacCaptureFormatItem: Hashable {
    case undo, redo, bold, italic, hashtag, heading(Int)
    case markdownLink, internalLink, dueDate, checklist, bullet, timestamp, date
    case lowercase, uppercase, sentenceCase, capitalizeWords, slugify
}

struct MacCaptureMenuActions {
    var attach: (MacCaptureAttachItem) -> Void
    var canAttach: Bool
    var format: (MacCaptureFormatItem) -> Void
    var isMeetingAudio: Binding<Bool>
    var sendsAfterRecording: Binding<Bool>
    var attachesRecordingAudio: Binding<Bool>
    var isRecording: Bool
    var revealLastCapture: (() -> Void)?
    var unlock: (() -> Void)?
    var unlockTitle: String
    /// The former toolbar's "Capture Details" (sidebar.trailing) button.
    var toggleDetails: () -> Void
    var isShowingDetails: Bool
}

struct MacActivityMenuActions {
    var refresh: () -> Void
    var isRefreshing: Bool
    var retryAll: (() -> Void)?
}

struct MacLibraryMenuActions {
    var reload: () -> Void
    var clearAll: (() -> Void)?
}

private struct MacCaptureMenuActionsKey: FocusedValueKey { typealias Value = MacCaptureMenuActions }
private struct MacActivityMenuActionsKey: FocusedValueKey { typealias Value = MacActivityMenuActions }
private struct MacLibraryMenuActionsKey: FocusedValueKey { typealias Value = MacLibraryMenuActions }

extension FocusedValues {
    var macCaptureMenuActions: MacCaptureMenuActions? {
        get { self[MacCaptureMenuActionsKey.self] }
        set { self[MacCaptureMenuActionsKey.self] = newValue }
    }
    var macActivityMenuActions: MacActivityMenuActions? {
        get { self[MacActivityMenuActionsKey.self] }
        set { self[MacActivityMenuActionsKey.self] = newValue }
    }
    var macLibraryMenuActions: MacLibraryMenuActions? {
        get { self[MacLibraryMenuActionsKey.self] }
        set { self[MacLibraryMenuActionsKey.self] = newValue }
    }
}

/// Activity's former toolbar (Refresh, Retry All) and Library's (Reload,
/// Clear All), shown in the View menu for whichever screen is focused.
struct MacListMenuItems: View {
    @FocusedValue(\.macActivityMenuActions) private var activity
    @FocusedValue(\.macLibraryMenuActions) private var library

    var body: some View {
        if let activity {
            Button("Refresh", action: activity.refresh)
                .keyboardShortcut("r", modifiers: .command)
                .disabled(activity.isRefreshing)
            if let retryAll = activity.retryAll {
                Button("Retry All", action: retryAll)
            }
        }
        if let library {
            Button("Reload", action: library.reload)
                .keyboardShortcut("r", modifiers: .command)
            Button("Clear All") { library.clearAll?() }
                .disabled(library.clearAll == nil)
        }
    }
}

// MARK: - Title-bar inset

/// True when a screen's header should run under the hidden title bar (the
/// MacWorkspace/MacActivity/MacLibrary boards start their header row at the
/// window's top edge). The root clears it while the sidebar is collapsed so
/// the traffic lights never sit over the breadcrumb or search field.
private struct MacUnderTitleBarKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var macContentUnderTitleBar: Bool {
        get { self[MacUnderTitleBarKey.self] }
        set { self[MacUnderTitleBarKey.self] = newValue }
    }
}

extension View {
    /// Ignores the hidden title bar's top inset when `macContentUnderTitleBar` is set.
    func macUnderTitleBar() -> some View { modifier(MacUnderTitleBarModifier()) }
}

private struct MacUnderTitleBarModifier: ViewModifier {
    @Environment(\.macContentUnderTitleBar) private var isUnderTitleBar
    func body(content: Content) -> some View {
        content.ignoresSafeArea(.container, edges: isUnderTitleBar ? .top : [])
    }
}
