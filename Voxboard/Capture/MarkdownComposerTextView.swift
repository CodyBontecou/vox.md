import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Imperative bridge used by the Markdown toolbar so selection-aware edits use
/// the same UITextView undo stack as keyboard typing on the iOS 17 target.
@MainActor
final class MarkdownComposerController {
    fileprivate weak var textView: UITextView?
    fileprivate var publishText: ((String) -> Void)?
    fileprivate var publishSelection: ((NSRange) -> Void)?
    fileprivate var publishFocus: ((Bool) -> Void)?

    var text: String { textView?.text ?? "" }
    var selection: NSRange { textView?.selectedRange ?? NSRange(location: 0, length: 0) }

    func dismissKeyboard() {
        textView?.resignFirstResponder()
        setInputPanel(nil)
    }

    /// Hosting controller for a SwiftUI panel shown in place of the system
    /// keyboard (the Capture Bar's "•••" panel).
    private var inputPanelHost: UIViewController?

    var showsInputPanel: Bool { inputPanelHost != nil }

    /// Replaces the system keyboard with `content` (nil restores the
    /// keyboard). The caret and first-responder state are kept, so actions in
    /// the panel insert at the selection like the pinned row does.
    func setInputPanel(_ content: AnyView?, height: CGFloat = 300) {
        guard let textView else {
            inputPanelHost = nil
            return
        }
        if let content {
            let host = UIHostingController(rootView: content)
            host.view.frame = CGRect(x: 0, y: 0, width: textView.window?.bounds.width ?? textView.bounds.width, height: height)
            host.view.autoresizingMask = [.flexibleWidth]
            host.view.backgroundColor = .clear
            inputPanelHost = host
            textView.inputView = host.view
        } else {
            guard inputPanelHost != nil || textView.inputView != nil else { return }
            inputPanelHost = nil
            textView.inputView = nil
        }
        textView.reloadInputViews()
    }

    func undo() {
        textView?.undoManager?.undo()
        restyle()
        publishCurrentState()
    }

    func replaceAll(with text: String, selection: NSRange) {
        apply(text: text, selection: selection, registeringUndo: true)
    }

    func replaceSelection(with replacement: String, selectInsertedText: Bool = false) {
        guard let textView else { return }
        let current = textView.text ?? ""
        let currentSelection = Self.clamped(textView.selectedRange, utf16Count: current.utf16.count)
        guard let range = Range(currentSelection, in: current) else { return }
        let next = current.replacingCharacters(in: range, with: replacement)
        let insertedLength = replacement.utf16.count
        let nextSelection = NSRange(
            location: currentSelection.location + (selectInsertedText ? 0 : insertedLength),
            length: selectInsertedText ? insertedLength : 0
        )
        apply(text: next, selection: nextSelection, registeringUndo: true)
    }

    /// Replaces one UTF-16 range without moving the caret more than needed.
    func replace(range: NSRange, with replacement: String) {
        guard let textView else { return }
        let current = textView.text ?? ""
        let safe = Self.clamped(range, utf16Count: current.utf16.count)
        guard let swiftRange = Range(safe, in: current) else { return }
        let next = current.replacingCharacters(in: swiftRange, with: replacement)
        var selection = textView.selectedRange
        let delta = replacement.utf16.count - safe.length
        if selection.location >= safe.location + safe.length {
            selection.location += delta
        }
        apply(text: next, selection: selection, registeringUndo: true)
    }

    private func apply(text: String, selection: NSRange, registeringUndo: Bool) {
        guard let textView else { return }
        let oldText = textView.text ?? ""
        let oldSelection = textView.selectedRange
        if registeringUndo, oldText != text || oldSelection != selection {
            textView.undoManager?.registerUndo(withTarget: self) { controller in
                controller.apply(text: oldText, selection: oldSelection, registeringUndo: true)
            }
            textView.undoManager?.setActionName(String(localized: "Edit Markdown"))
        }
        textView.text = text
        restyle()
        textView.selectedRange = Self.clamped(selection, utf16Count: text.utf16.count)
        publishCurrentState()
        textView.scrollRangeToVisible(textView.selectedRange)
    }

    fileprivate func restyle() {
        (textView as? MarkdownComposerUITextView)?.restyleMarkdown()
    }

    fileprivate func publishCurrentState() {
        guard let textView else { return }
        publishText?(textView.text ?? "")
        publishSelection?(textView.selectedRange)
        publishFocus?(textView.isFirstResponder)
    }

    fileprivate func disconnect(_ textView: UITextView) {
        guard self.textView === textView else { return }
        self.textView = nil
        publishText = nil
        publishSelection = nil
        publishFocus = nil
    }

    fileprivate static func clamped(_ range: NSRange, utf16Count: Int) -> NSRange {
        let location = min(max(0, range.location), utf16Count)
        let length = min(max(0, range.length), utf16Count - location)
        return NSRange(location: location, length: length)
    }
}

struct MarkdownComposerTextView: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var isFocused: Bool
    let controller: MarkdownComposerController
    /// Receives the text's laid-out height (content size), for layouts that
    /// place content directly under the text (iPad Pencil card).
    var contentHeight: Binding<CGFloat>? = nil
    /// Called with the caret's UTF-16 offset when the writer types or moves the
    /// cursor (never for programmatic text or selection updates), so live
    /// speech can follow the cursor while recording.
    var writerMovedCaret: ((Int) -> Void)? = nil
    /// Live Notes: the entry this capture just added inside a whole file,
    /// shown with a tinted card and a "JUST ADDED" label.
    var highlightedEntry: String? = nil
    /// Shows the Markdown source instead of the formatted rendering.
    var showsRawMarkdown = false
    /// Finds the file an embed (`![[clip.wav]]`) points to, for live preview.
    var resolveEmbedURL: ((String) -> URL?)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        // This editor restyles its entire text storage after edits. TextKit 2's
        // lazy rendering can lose restored glyphs after Undo and a keyboard or
        // orientation resize; TextKit 1 keeps those rendering surfaces coherent.
        let storage = NSTextStorage(string: "")
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = MarkdownComposerUITextView(frame: .zero, textContainer: container)
        textView.allowsKeyboardFocus = isEnabled
        textView.isEditable = isEnabled
        textView.delegate = context.coordinator
        textView.textDropDelegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textColor = UIColor(Geist.text)
        textView.tintColor = UIColor(Geist.accent)
        // Signal composer: 17pt Geist body on the ground, generous side gutter.
        textView.font = MarkdownComposerStyler.baseFont
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 20, bottom: 24, right: 20)
        textView.keyboardDismissMode = .interactive
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        textView.accessibilityLabel = String(localized: "Capture note")
        textView.accessibilityHint = String(localized: "Enter raw Markdown to send to the selected destination")
        textView.accessibilityIdentifier = "quick_capture_text"
        textView.text = text
        textView.highlightedEntry = highlightedEntry
        textView.showsRawMarkdown = showsRawMarkdown
        textView.resolveEmbedURL = resolveEmbedURL
        textView.restyleMarkdown()
        textView.selectedRange = MarkdownComposerController.clamped(selection, utf16Count: text.utf16.count)
        textView.toggleTask = { [weak coordinator = context.coordinator] location in
            coordinator?.toggleTask(at: location)
        }
        textView.contentHeightDidChange = { [weak coordinator = context.coordinator] height in
            guard let binding = coordinator?.parent.contentHeight else { return }
            // Never write SwiftUI state from inside a layout pass.
            DispatchQueue.main.async {
                if abs(binding.wrappedValue - height) > 0.5 { binding.wrappedValue = height }
            }
        }
        connect(textView, coordinator: context.coordinator)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        connect(textView, coordinator: context.coordinator)
        // The editor stays mounted behind recording UI. Dismissal alone is not
        // enough: UIKit taps and queued focus work must also be unable to reopen it.
        (textView as? MarkdownComposerUITextView)?.allowsKeyboardFocus = isEnabled
        (textView as? MarkdownComposerUITextView)?.highlightedEntry = highlightedEntry
        (textView as? MarkdownComposerUITextView)?.showsRawMarkdown = showsRawMarkdown
        (textView as? MarkdownComposerUITextView)?.resolveEmbedURL = resolveEmbedURL
        textView.isEditable = isEnabled

        // Programmatic edits below must not read as the writer moving the caret.
        context.coordinator.isApplyingUpdate = true
        defer { context.coordinator.isApplyingUpdate = false }
        let textChanged = textView.text != text
        if textChanged {
            textView.text = text
            (textView as? MarkdownComposerUITextView)?.restyleMarkdown()
            // The text was replaced from outside the editor (a Live Note
            // bound or reloaded, a file opened, a transcript committed).
            // Earlier undo steps no longer match it; replaying them would
            // corrupt the note, and Live Notes would autosave that.
            textView.undoManager?.removeAllActions()
        }
        let textEnd = text.utf16.count
        let desired = MarkdownComposerController.clamped(selection, utf16Count: textEnd)
        let selectionChanged = textView.selectedRange != desired
        if selectionChanged {
            textView.selectedRange = desired
        }
        // Follow programmatic edits (live speech lands at the cursor, not
        // only at the end) while the writer is not typing.
        if textChanged || selectionChanged,
           desired.location + desired.length == textEnd || !textView.isFirstResponder {
            textView.scrollRangeToVisible(desired)
        }
        if isEnabled, isFocused, !textView.isFirstResponder {
            // Focus is queued so UIKit sees an attached view. Re-check the binding
            // because navigation can dismiss the composer before this block runs.
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak textView, weak coordinator] in
                guard let textView,
                      let coordinator,
                      coordinator.parent.isEnabled,
                      coordinator.parent.isFocused,
                      textView.canBecomeFirstResponder,
                      textView.window != nil else { return }
                textView.becomeFirstResponder()
            }
        } else if !isEnabled || !isFocused, textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        if textView.isFirstResponder {
            textView.resignFirstResponder()
        }
        coordinator.parent.controller.disconnect(textView)
    }

    private func connect(_ textView: UITextView, coordinator: Coordinator) {
        controller.textView = textView
        controller.publishText = { value in
            if coordinator.parent.text != value { coordinator.parent.text = value }
        }
        controller.publishSelection = { value in
            if coordinator.parent.selection != value { coordinator.parent.selection = value }
        }
        controller.publishFocus = { value in
            if coordinator.parent.isFocused != value { coordinator.parent.isFocused = value }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate, UITextDropDelegate {
        var parent: MarkdownComposerTextView
        /// A drop from another app, captured before UIKit inserts its text.
        private var pendingExternalDrop: (location: Int, previousLength: Int, sourceURL: URL?)?
        private var droppedQuoteEnd: Int?
        private var dropGeneration = 0

        init(parent: MarkdownComposerTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            if let drop = pendingExternalDrop {
                pendingExternalDrop = nil
                convertDroppedText(in: textView, drop: drop)
                return
            }
            (textView as? MarkdownComposerUITextView)?.restyleMarkdown()
            parent.controller.publishCurrentState()
            reportWriterCaret(in: textView)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            (textView as? MarkdownComposerUITextView)?.richBlockSelectionDidChange()
            parent.controller.publishCurrentState()
            reportWriterCaret(in: textView)
        }

        /// True while `updateUIView` writes SwiftUI state into the text view.
        var isApplyingUpdate = false

        private func reportWriterCaret(in textView: UITextView) {
            guard !isApplyingUpdate,
                  textView.isFirstResponder,
                  textView.markedTextRange == nil,
                  let writerMovedCaret = parent.writerMovedCaret else { return }
            let range = textView.selectedRange
            writerMovedCaret(range.location + range.length)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            parent.controller.publishCurrentState()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            parent.controller.publishCurrentState()
        }

        /// Tapping a rendered checkbox toggles `- [ ]` and `- [x]` in place.
        func toggleTask(at bracketLocation: Int) {
            let text = parent.controller.text as NSString
            guard bracketLocation + 3 <= text.length else { return }
            let marker = text.substring(with: NSRange(location: bracketLocation, length: 3))
            let replacement: String
            switch marker {
            case "[ ]": replacement = "[x]"
            case "[x]", "[X]": replacement = "[ ]"
            default: return
            }
            UISelectionFeedbackGenerator().selectionChanged()
            parent.controller.replace(range: NSRange(location: bracketLocation, length: 3), with: replacement)
        }

        // MARK: Drops from other apps become quotes

        func textDroppableView(
            _ textDroppableView: UIView & UITextDroppable,
            willPerformDrop drop: UITextDropRequest
        ) {
            guard !drop.isSameView,
                  drop.dropSession.localDragSession == nil,
                  let textView = textDroppableView as? UITextView else { return }
            let location = textView.offset(from: textView.beginningOfDocument, to: drop.dropPosition)
            pendingExternalDrop = (location, (textView.text as NSString?)?.length ?? 0, nil)
            dropGeneration += 1
            let generation = dropGeneration
            let providers = drop.dropSession.items.map(\.itemProvider)
            Task { @MainActor [weak self, weak textView] in
                guard let url = await Self.sourceURL(from: providers),
                      let self, let textView, generation == self.dropGeneration else { return }
                self.appendSourceLink(url, in: textView)
            }
        }

        private func convertDroppedText(
            in textView: UITextView,
            drop: (location: Int, previousLength: Int, sourceURL: URL?)
        ) {
            let current = textView.text as NSString
            let insertedLength = current.length - drop.previousLength
            guard insertedLength > 0, drop.location + insertedLength <= current.length else {
                (textView as? MarkdownComposerUITextView)?.restyleMarkdown()
                parent.controller.publishCurrentState()
                return
            }
            let range = NSRange(location: drop.location, length: insertedLength)
            let dropped = current.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !dropped.isEmpty else { return }
            let quoted = dropped
                .components(separatedBy: .newlines)
                .map { "> " + $0 }
                .joined(separator: "\n")
            let needsLeadingBreak = drop.location > 0
                && current.character(at: drop.location - 1) != 0x0A
            let end = drop.location + insertedLength
            let followedByBreak = end < current.length && current.character(at: end) == 0x0A
            // A blank line ends the quote so text typed next stays outside it.
            let lead = needsLeadingBreak ? "\n" : ""
            let block = lead + quoted + (followedByBreak ? "\n" : "\n\n")
            let blockLength = (block as NSString).length
            droppedQuoteEnd = drop.location + (lead as NSString).length + (quoted as NSString).length
            parent.controller.replace(range: range, with: block)
            if let controllerTextView = parent.controller.textView {
                controllerTextView.selectedRange = NSRange(location: drop.location + blockLength, length: 0)
                parent.controller.publishCurrentState()
            }
        }

        private func appendSourceLink(_ url: URL, in textView: UITextView) {
            guard let end = droppedQuoteEnd else { return }
            droppedQuoteEnd = nil
            let current = parent.controller.text as NSString
            guard end <= current.length else { return }
            let title = url.host(percentEncoded: false) ?? url.absoluteString
            let line = "\n> — [\(title)](\(url.absoluteString))"
            parent.controller.replace(range: NSRange(location: end, length: 0), with: line)
        }

        private static func sourceURL(from providers: [NSItemProvider]) async -> URL? {
            for provider in providers where provider.canLoadObject(ofClass: URL.self) {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { value, _ in
                        continuation.resume(returning: value)
                    }
                }
                if let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    return url
                }
            }
            return nil
        }
    }
}

// MARK: - Live Markdown rendering

/// UITextView that renders Markdown attributes over plain Markdown text and
/// overlays tappable checkboxes on task markers. The text itself never changes
/// unless the user toggles a task.
final class MarkdownComposerUITextView: UITextView {
    var allowsKeyboardFocus = true

    override var canBecomeFirstResponder: Bool {
        allowsKeyboardFocus && super.canBecomeFirstResponder
    }

    var toggleTask: ((Int) -> Void)?
    var contentHeightDidChange: ((CGFloat) -> Void)?
    private var reportedContentHeight: CGFloat = -1
    private var taskMarkers: [(range: NSRange, isChecked: Bool)] = []
    private var checkboxButtons: [UIButton] = []

    /// Dropped-quote cards (a `>` quote ending in its source line) drawn
    /// behind the quote text; the Markdown itself is unchanged.
    private var droppedQuotes: [MarkdownComposerStyler.DroppedQuoteBlock] = []
    private var droppedQuoteCards: [MarkdownComposerDroppedQuoteCardView] = []

    /// Live Notes: the entry just added inside a whole file. Restyles when it
    /// changes so the label gets its room above the entry.
    var highlightedEntry: String? {
        didSet {
            guard oldValue != highlightedEntry else { return }
            restyleMarkdown()
        }
    }

    private var highlightRange: NSRange?
    private var highlightCardIsCreated = false
    private lazy var highlightCard: UIView = {
        highlightCardIsCreated = true
        let card = UIView()
        card.backgroundColor = UIColor(Geist.Palette.blue100)
        card.layer.cornerRadius = 12
        card.layer.cornerCurve = .continuous
        card.isUserInteractionEnabled = false
        card.isHidden = true
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: String(localized: "JUST ADDED"),
            attributes: [
                .font: UIFont(name: "Geist-SemiBold", size: 10.5) ?? .systemFont(ofSize: 10.5, weight: .semibold),
                .kern: 0.8,
                .foregroundColor: UIColor(Geist.accentText),
            ]
        )
        label.tag = 1
        label.isAccessibilityElement = false
        card.addSubview(label)
        insertSubview(card, at: 0)
        return card
    }()

    private static let highlightLabelSpace: CGFloat = 22

    /// The "JUST ADDED" card's frame while it is shown (tests, accessibility).
    var entryHighlightFrame: CGRect? {
        highlightRange == nil || highlightCard.isHidden ? nil : highlightCard.frame
    }

    /// The character range the card covers, if the entry was found.
    var entryHighlightRange: NSRange? { highlightRange }

    /// Finds the entry and gives its first paragraph room for the label.
    private func applyEntryHighlight() {
        highlightRange = nil
        let needle = highlightedEntry?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !needle.isEmpty else { return }
        let string = textStorage.string as NSString
        let found = string.range(of: needle, options: .backwards)
        guard found.location != NSNotFound, found.length < string.length else { return }
        highlightRange = found
        let paragraph = string.paragraphRange(for: NSRange(location: found.location, length: 0))
        let existing = (textStorage.attribute(.paragraphStyle, at: found.location, effectiveRange: nil)
            as? NSParagraphStyle) ?? NSParagraphStyle.default
        let style = (existing.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
        style.paragraphSpacingBefore = max(style.paragraphSpacingBefore, Self.highlightLabelSpace + 6)
        textStorage.addAttribute(.paragraphStyle, value: style, range: paragraph)
    }

    private func layoutEntryHighlight() {
        guard let range = highlightRange,
              NSMaxRange(range) <= ((text as NSString?)?.length ?? 0),
              let top = caretRect(at: range.location),
              let end = caretRect(at: NSMaxRange(range)) else {
            if highlightRange == nil, highlightedEntry == nil, highlightCardIsCreated == false { return }
            highlightCard.isHidden = true
            return
        }
        let inset = textContainerInset
        let minY = top.minY - Self.highlightLabelSpace - 4
        let frame = CGRect(
            x: inset.left - 8,
            y: minY,
            width: max(0, bounds.width - inset.left - inset.right + 16),
            height: end.maxY + 8 - minY
        )
        highlightCard.isHidden = false
        highlightCard.frame = frame
        if let label = highlightCard.viewWithTag(1) {
            label.sizeToFit()
            label.frame.origin = CGPoint(x: 8, y: 7)
        }
    }

    /// Raw/formatted toggle: raw shows the file's Markdown source as-is.
    var showsRawMarkdown = false {
        didSet {
            guard oldValue != showsRawMarkdown else { return }
            restyleMarkdown()
        }
    }

    // MARK: Live preview blocks (properties, audio, images, video)

    var resolveEmbedURL: ((String) -> URL?)?
    private var frontmatterBlock: MarkdownRichBlocks.Frontmatter?
    private var embedBlocks: [MarkdownRichBlocks.Embed] = []
    private var propertiesView: MarkdownPropertiesView?
    private var embedViews: [String: MarkdownRichCardView] = [:]
    private var imageAspectRatios: [String: CGFloat] = [:]
    private var revealedBlockLocations: Set<Int> = []

    /// Height of the widget drawn over a block.
    private func richHeight(for embed: MarkdownRichBlocks.Embed) -> CGFloat {
        switch embed.kind {
        case .audio: return MarkdownAudioEmbedView.height
        case .video: return MarkdownVideoEmbedView.height
        case .image:
            let width = max(0, bounds.width - textContainerInset.left - textContainerInset.right)
            guard let ratio = imageAspectRatios[embed.target], width > 0 else { return 200 }
            return min(MarkdownImageEmbedView.maximumHeight, max(80, width * ratio))
        }
    }

    private func blockIsRevealed(_ range: NSRange) -> Bool {
        isFirstResponder && MarkdownRichBlocks.isRevealed(range, by: selectedRange)
    }

    /// Hides each unrevealed block's Markdown and gives its first line the
    /// widget's height; the widgets themselves are laid out as subviews.
    private func applyRichBlocks() {
        let string = textStorage.string as NSString
        frontmatterBlock = nil
        embedBlocks = []
        revealedBlockLocations = []
        guard string.length > 0, string.length <= 60_000 else { return }
        if let frontmatter = MarkdownRichBlocks.frontmatter(in: string) {
            if blockIsRevealed(frontmatter.range) {
                revealedBlockLocations.insert(frontmatter.range.location)
            } else {
                frontmatterBlock = frontmatter
                hideBlock(frontmatter.range, reserving: MarkdownPropertiesView.height(for: frontmatter.properties))
            }
        }
        for embed in MarkdownRichBlocks.embeds(in: string) {
            if let frontmatter = MarkdownRichBlocks.frontmatter(in: string),
               NSIntersectionRange(frontmatter.range, embed.range).length > 0 { continue }
            if blockIsRevealed(embed.range) {
                revealedBlockLocations.insert(embed.range.location)
                continue
            }
            embedBlocks.append(embed)
            hideBlock(embed.range, reserving: richHeight(for: embed))
        }
    }

    private func hideBlock(_ range: NSRange, reserving height: CGFloat) {
        let string = textStorage.string as NSString
        let paragraphs = string.paragraphRange(for: range)
        textStorage.addAttributes([
            .font: UIFont.systemFont(ofSize: 0.5),
            .foregroundColor: UIColor.clear,
        ], range: range)
        // Link/code styling paints backgrounds; the hidden source must not.
        textStorage.removeAttribute(.backgroundColor, range: range)
        textStorage.removeAttribute(.underlineStyle, range: range)
        var location = paragraphs.location
        var isFirst = true
        while location < NSMaxRange(paragraphs) {
            let paragraph = string.paragraphRange(for: NSRange(location: location, length: 0))
            let style = NSMutableParagraphStyle()
            let lineHeight: CGFloat = isFirst ? height + 12 : 0.5
            style.minimumLineHeight = lineHeight
            style.maximumLineHeight = lineHeight
            style.paragraphSpacing = 0
            style.paragraphSpacingBefore = 0
            textStorage.addAttribute(.paragraphStyle, value: style, range: paragraph)
            isFirst = false
            location = NSMaxRange(paragraph)
        }
    }

    /// The caret moved: re-render when it entered or left a block.
    func richBlockSelectionDidChange() {
        guard !showsRawMarkdown, markedTextRange == nil else { return }
        let string = textStorage.string as NSString
        var blocks: [NSRange] = []
        if let frontmatter = MarkdownRichBlocks.frontmatter(in: string) { blocks.append(frontmatter.range) }
        blocks += MarkdownRichBlocks.embeds(in: string).map(\.range)
        let revealed = Set(blocks.filter(blockIsRevealed).map(\.location))
        if revealed != revealedBlockLocations { restyleMarkdown() }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { DispatchQueue.main.async { [weak self] in self?.richBlockSelectionDidChange() } }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned, !revealedBlockLocations.isEmpty {
            DispatchQueue.main.async { [weak self] in self?.restyleMarkdown() }
        }
        return resigned
    }

    private func layoutRichBlocks() {
        let inset = textContainerInset
        let width = max(0, bounds.width - inset.left - inset.right)
        func top(of location: Int) -> CGFloat? {
            guard location < textStorage.length else { return nil }
            let glyph = layoutManager.glyphIndexForCharacter(at: location)
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            return rect.minY + inset.top + 4
        }

        if let frontmatter = frontmatterBlock, let y = top(of: frontmatter.range.location) {
            let view = propertiesView ?? {
                let view = MarkdownPropertiesView()
                view.onTap = { [weak self] in self?.revealBlock(at: frontmatter.closingLineRange.location) }
                addSubview(view)
                propertiesView = view
                return view
            }()
            view.configure(frontmatter.properties)
            view.isHidden = false
            view.frame = CGRect(x: inset.left, y: y, width: width, height: MarkdownPropertiesView.height(for: frontmatter.properties))
        } else {
            propertiesView?.isHidden = true
        }

        var used = Set<String>()
        for (index, embed) in embedBlocks.enumerated() {
            let key = "\(index):\(embed.target)"
            used.insert(key)
            guard let y = top(of: embed.range.location) else { continue }
            let url = resolveEmbedURL?(embed.target)
            let view: MarkdownRichCardView
            if let existing = embedViews[key] {
                view = existing
            } else {
                switch embed.kind {
                case .audio: view = MarkdownAudioEmbedView()
                case .video: view = MarkdownVideoEmbedView()
                case .image:
                    let image = MarkdownImageEmbedView()
                    let target = embed.target
                    image.onAspectRatioChange = { [weak self] ratio in
                        self?.imageAspectRatios[target] = ratio
                        self?.restyleMarkdown()
                    }
                    view = image
                }
                addSubview(view)
                embedViews[key] = view
            }
            switch view {
            case let audio as MarkdownAudioEmbedView: audio.configure(target: embed.target, url: url)
            case let video as MarkdownVideoEmbedView: video.configure(target: embed.target, url: url)
            case let image as MarkdownImageEmbedView: image.configure(target: embed.target, url: url)
            default: break
            }
            view.isHidden = false
            view.frame = CGRect(x: inset.left, y: y, width: width, height: richHeight(for: embed))
        }
        for (key, view) in embedViews where !used.contains(key) {
            view.removeFromSuperview()
            embedViews[key] = nil
        }
    }

    /// Tapping Properties shows the YAML under the caret, ready to edit.
    private func revealBlock(at location: Int) {
        _ = becomeFirstResponder()
        selectedRange = NSRange(location: min(location, textStorage.length), length: 0)
        restyleMarkdown()
    }

    func restyleMarkdown() {
        guard markedTextRange == nil else { return }
        let selection = selectedRange
        if showsRawMarkdown {
            frontmatterBlock = nil
            embedBlocks = []
            droppedQuotes = []
            updateLeadingDroppedQuoteInset()
            taskMarkers = []
            let full = NSRange(location: 0, length: textStorage.length)
            textStorage.beginEditing()
            if full.length > 0 { textStorage.setAttributes(MarkdownComposerStyler.rawAttributes, range: full) }
            applyEntryHighlight()
            textStorage.endEditing()
            typingAttributes = MarkdownComposerStyler.rawAttributes
            if selectedRange != selection { selectedRange = selection }
            setNeedsLayout()
            return
        }
        droppedQuotes = MarkdownComposerStyler.droppedQuoteBlocks(in: textStorage.string as NSString)
        updateLeadingDroppedQuoteInset()
        taskMarkers = MarkdownComposerStyler.apply(to: textStorage)
        applyRichBlocks()
        applyEntryHighlight()
        typingAttributes = MarkdownComposerStyler.baseAttributes
        if selectedRange != selection { selectedRange = selection }
        setNeedsLayout()
    }

    /// Text layout drops `paragraphSpacingBefore` on the first paragraph, so a
    /// dropped quote at the very top of the draft (DuoSplitView) would push
    /// its card and "DROPPED QUOTE" label above the text container, where the
    /// text view clips them. Make that room with the top inset instead.
    private var leadingDroppedQuoteInset: CGFloat = 0

    private func updateLeadingDroppedQuoteInset() {
        let needed = droppedQuotes.first?.range.location == 0
            ? MarkdownComposerStyler.droppedQuoteLabelSpace
            : 0
        guard needed != leadingDroppedQuoteInset else { return }
        var inset = textContainerInset
        inset.top += needed - leadingDroppedQuoteInset
        leadingDroppedQuoteInset = needed
        textContainerInset = inset
    }

    private var observesTraitChanges = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !observesTraitChanges else { return }
        observesTraitChanges = true
        // Rendered fonts are fixed per pass; restyle when Dynamic Type or
        // light/dark appearance changes.
        registerForTraitChanges(
            [UITraitPreferredContentSizeCategory.self, UITraitUserInterfaceStyle.self]
        ) { (textView: MarkdownComposerUITextView, _: UITraitCollection) in
            textView.restyleMarkdown()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCheckboxes()
        layoutDroppedQuoteCards()
        layoutEntryHighlight()
        layoutRichBlocks()
        if contentHeightDidChange != nil, abs(contentSize.height - reportedContentHeight) > 0.5 {
            reportedContentHeight = contentSize.height
            contentHeightDidChange?(contentSize.height)
        }
    }

    private func layoutDroppedQuoteCards() {
        while droppedQuoteCards.count < droppedQuotes.count {
            let card = MarkdownComposerDroppedQuoteCardView()
            // Behind the text so the quote stays selectable and editable.
            insertSubview(card, at: 0)
            droppedQuoteCards.append(card)
        }
        let length = (text as NSString?)?.length ?? 0
        for (index, card) in droppedQuoteCards.enumerated() {
            guard index < droppedQuotes.count else {
                card.isHidden = true
                continue
            }
            let block = droppedQuotes[index]
            guard NSMaxRange(block.range) <= length,
                  let quoteTop = caretRect(at: block.quoteRange.location),
                  let sourceTop = caretRect(at: block.sourceLineRange.location),
                  let sourceEnd = caretRect(at: NSMaxRange(block.sourceLineRange)) else {
                card.isHidden = true
                continue
            }
            let inset = textContainerInset
            let minX = inset.left
            let width = max(0, bounds.width - inset.left - inset.right)
            let top = quoteTop.minY - MarkdownComposerStyler.droppedQuoteLabelSpace + 4
            let bottom = max(sourceTop.maxY, sourceEnd.maxY) + 10
            card.isHidden = false
            card.frame = CGRect(x: minX, y: top, width: width, height: bottom - top)
            card.sourceLabelOriginY = sourceTop.minY - top
            card.setNeedsLayout()
        }
    }

    private func caretRect(at offset: Int) -> CGRect? {
        guard let position = position(from: beginningOfDocument, offset: offset) else { return nil }
        let rect = caretRect(for: position)
        guard !rect.isNull, !rect.isInfinite, rect.height > 0 else { return nil }
        return rect
    }

    private func layoutCheckboxes() {
        while checkboxButtons.count < taskMarkers.count {
            let button = UIButton(type: .custom)
            button.addTarget(self, action: #selector(checkboxTapped(_:)), for: .touchUpInside)
            addSubview(button)
            checkboxButtons.append(button)
        }
        for (index, button) in checkboxButtons.enumerated() {
            guard index < taskMarkers.count else {
                button.isHidden = true
                continue
            }
            let marker = taskMarkers[index]
            guard let start = position(from: beginningOfDocument, offset: marker.range.location),
                  let end = position(from: start, offset: marker.range.length),
                  let textRange = textRange(from: start, to: end) else {
                button.isHidden = true
                continue
            }
            let rect = firstRect(for: textRange)
            guard !rect.isNull, !rect.isInfinite, rect.height > 0 else {
                button.isHidden = true
                continue
            }
            let side: CGFloat = 20
            button.isHidden = false
            button.tag = marker.range.location
            button.frame = CGRect(x: rect.minX - 2, y: rect.midY - 22, width: 44, height: 44)
            let configuration = UIImage.SymbolConfiguration(pointSize: side, weight: .regular)
            let image = UIImage(
                systemName: marker.isChecked ? "checkmark.square.fill" : "square",
                withConfiguration: configuration
            )
            button.setImage(image, for: .normal)
            button.tintColor = marker.isChecked ? UIColor(Geist.accent) : UIColor(Geist.Palette.gray600)
            button.contentHorizontalAlignment = .left
            button.accessibilityLabel = marker.isChecked
                ? String(localized: "Completed task")
                : String(localized: "Open task")
            button.accessibilityHint = String(localized: "Double-tap to toggle this task.")
            button.accessibilityTraits = marker.isChecked ? [.button, .selected] : .button
        }
    }

    @objc private func checkboxTapped(_ sender: UIButton) {
        // The marker range starts at "-"; the brackets follow "- ".
        guard let marker = taskMarkers.first(where: { $0.range.location == sender.tag }) else { return }
        let text = (self.text ?? "") as NSString
        let bracket = text.range(of: "[", options: [], range: marker.range).location
        guard bracket != NSNotFound else { return }
        toggleTask?(bracket)
    }
}

enum MarkdownComposerStyler {
    static var baseFont: UIFont {
        scaled(UIFont(name: "Geist-Regular", size: 17) ?? .systemFont(ofSize: 17), style: .body)
    }

    /// Raw mode: the Markdown exactly as it is in the file, in mono, with no
    /// rendered headings, checkboxes or quote cards.
    static var rawAttributes: [NSAttributedString.Key: Any] {
        [
            .font: scaled(UIFont(name: "GeistMono-Regular", size: 15) ?? .monospacedSystemFont(ofSize: 15, weight: .regular), style: .body),
            .foregroundColor: UIColor(Geist.text),
            .paragraphStyle: paragraph(spacing: 2),
        ]
    }

    static var baseAttributes: [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: UIColor(Geist.text),
            .paragraphStyle: paragraph(spacing: 4),
        ]
    }

    private static func scaled(_ font: UIFont, style: UIFont.TextStyle) -> UIFont {
        UIFontMetrics(forTextStyle: style).scaledFont(for: font)
    }

    private static func font(_ name: String, _ size: CGFloat, _ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
        scaled(UIFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight), style: style)
    }

    private static func paragraph(spacing: CGFloat, before: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = spacing
        style.paragraphSpacingBefore = before
        return style
    }

    private static let heading = try! NSRegularExpression(pattern: "^(#{1,6})([ \\t]+)(.*)$", options: .anchorsMatchLines)
    private static let task = try! NSRegularExpression(pattern: "^([ \\t]*)([-*+] \\[( |x|X)\\])(?=[ \\t]|$)(.*)$", options: .anchorsMatchLines)
    private static let bullet = try! NSRegularExpression(pattern: "^[ \\t]*([-*+])(?= (?!\\[[ xX]\\]))", options: .anchorsMatchLines)
    private static let quote = try! NSRegularExpression(pattern: "^(>[ \\t]?)(.*)$", options: .anchorsMatchLines)
    private static let wikilink = try! NSRegularExpression(pattern: "!?\\[\\[[^\\]\\n]+\\]\\]")
    private static let link = try! NSRegularExpression(pattern: "(?<!!)\\[([^\\]\\n]+)\\]\\(([^)\\s]+)\\)")
    private static let bold = try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)([^\\n]+?)(?<=\\S)\\1")
    private static let italic = try! NSRegularExpression(pattern: "(?<![*_\\w])([*_])(?=\\S)([^*_\\n]+?)(?<=\\S)\\1(?![*_\\w])")
    private static let code = try! NSRegularExpression(pattern: "`[^`\\n]+`")
    private static let tag = try! NSRegularExpression(pattern: "(?<![\\w#&/])#[\\p{L}\\p{N}_/-]*[\\p{L}_][\\p{L}\\p{N}_/-]*")

    /// Applies Markdown styling attributes and returns task marker ranges
    /// (from the list dash through the closing bracket).
    @discardableResult
    static func apply(to storage: NSTextStorage) -> [(range: NSRange, isChecked: Bool)] {
        let string = storage.string as NSString
        let full = NSRange(location: 0, length: string.length)
        var markers: [(range: NSRange, isChecked: Bool)] = []
        guard full.length > 0, full.length <= 60_000 else {
            if full.length > 0 { storage.setAttributes(baseAttributes, range: full) }
            return markers
        }
        let text = storage.string
        let muted = UIColor(Geist.muted)
        let faint = UIColor(Geist.Palette.gray600)
        let accent = UIColor(Geist.accentText)
        let mono = font("GeistMono-Regular", 15, .body, weight: .regular)

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: full)

        // Inside fenced code, `# comment`, `- [ ]`, `#tag` and `[[link]]` are code,
        // not Markdown: skip every inline pass there and show the block as code.
        let codeBlocks = fencedCodeBlocks(in: string)
        func isCode(_ range: NSRange) -> Bool {
            codeBlocks.contains { NSIntersectionRange($0, range).length > 0 }
        }

        for match in heading.matches(in: text, range: full) where !isCode(match.range) {
            let level = match.range(at: 1).length
            let size: CGFloat = [30, 24, 20, 18, 17, 17][min(level, 6) - 1]
            let style: UIFont.TextStyle = level == 1 ? .title1 : (level == 2 ? .title2 : .title3)
            storage.addAttributes([
                .font: font("Geist-SemiBold", size, style, weight: .semibold),
                .kern: level <= 2 ? -0.4 : 0,
                .paragraphStyle: paragraph(spacing: 2, before: 6),
            ], range: match.range)
            let marker = NSUnionRange(match.range(at: 1), match.range(at: 2))
            storage.addAttributes([
                .font: font("GeistMono-Regular", 16, .body, weight: .regular),
                .foregroundColor: faint,
            ], range: marker)
        }

        for match in task.matches(in: text, range: full) where !isCode(match.range) {
            let markerRange = match.range(at: 2)
            let checked = string.substring(with: match.range(at: 3)).lowercased() == "x"
            markers.append((markerRange, checked))
            // The checkbox overlay replaces the visible marker glyphs.
            storage.addAttributes([.foregroundColor: UIColor.clear], range: markerRange)
            if checked, match.range(at: 4).length > 0 {
                storage.addAttributes([
                    .foregroundColor: muted,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: muted,
                ], range: match.range(at: 4))
            }
        }

        for match in bullet.matches(in: text, range: full) where !isCode(match.range) {
            storage.addAttributes([.foregroundColor: faint], range: match.range(at: 1))
        }

        for match in quote.matches(in: text, range: full) where !isCode(match.range) {
            storage.addAttributes([.foregroundColor: faint], range: match.range(at: 1))
            storage.addAttributes([.foregroundColor: UIColor(Geist.Palette.gray800)], range: match.range(at: 2))
        }

        for match in bold.matches(in: text, range: full) where !isCode(match.range) {
            storage.addAttributes([.font: font("Geist-SemiBold", 17, .body, weight: .semibold)], range: match.range(at: 2))
            for marker in [match.range(at: 1), NSRange(location: match.range.upperBound - match.range(at: 1).length, length: match.range(at: 1).length)] {
                storage.addAttributes([.foregroundColor: faint], range: marker)
            }
        }

        for match in italic.matches(in: text, range: full) where !isCode(match.range) {
            storage.addAttributes([.obliqueness: 0.14], range: match.range(at: 2))
        }

        for match in code.matches(in: text, range: full) where !isCode(match.range) {
            storage.addAttributes([
                .font: mono,
                .backgroundColor: UIColor(Geist.Palette.gray200),
            ], range: match.range)
        }

        for match in tag.matches(in: text, range: full)
            where !isInsideHeadingMarker(match.range, in: string) && !isCode(match.range) {
            storage.addAttributes([.foregroundColor: accent], range: match.range)
        }

        for match in link.matches(in: text, range: full) where !isCode(match.range) {
            storage.addAttributes([.foregroundColor: accent], range: match.range(at: 1))
            storage.addAttributes([.foregroundColor: faint, .font: font("GeistMono-Regular", 13, .footnote, weight: .regular)], range: match.range(at: 2))
        }

        for match in wikilink.matches(in: text, range: full) where !isCode(match.range) {
            storage.addAttributes([
                .font: mono,
                .foregroundColor: accent,
                .backgroundColor: UIColor(Geist.accentSoft),
            ], range: match.range)
        }

        for block in droppedQuoteBlocks(in: string) where !isCode(block.range) {
            styleDroppedQuote(block, in: storage, string: string)
        }

        for block in codeBlocks {
            storage.addAttributes([.font: mono], range: block)
        }

        storage.endEditing()
        return markers
    }

    // MARK: Fenced code

    private static let fenceLine = try! NSRegularExpression(pattern: "^ {0,3}(`{3,}|~{3,})(.*)$")

    /// Ranges of fenced code blocks, fences included. As in CommonMark, a fence
    /// closes on a run of the same character at least as long with nothing
    /// after it, and an unclosed fence runs to the end of the text.
    static func fencedCodeBlocks(in string: NSString) -> [NSRange] {
        guard string.length > 0, string.length <= 60_000 else { return [] }
        var blocks: [NSRange] = []
        var open: (start: Int, fence: String)?
        var location = 0
        while location < string.length {
            var lineEnd = 0
            var contentsEnd = 0
            string.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let line = string.substring(with: NSRange(location: location, length: contentsEnd - location))
            let nsLine = line as NSString
            if let match = fenceLine.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) {
                let fence = nsLine.substring(with: match.range(at: 1))
                let rest = nsLine.substring(with: match.range(at: 2))
                if let current = open {
                    if fence.first == current.fence.first,
                       fence.count >= current.fence.count,
                       rest.trimmingCharacters(in: .whitespaces).isEmpty {
                        blocks.append(NSRange(location: current.start, length: lineEnd - current.start))
                        open = nil
                    }
                } else if !(fence.first == "`" && rest.contains("`")) {
                    open = (location, fence)
                }
            }
            location = max(lineEnd, location + 1)
        }
        if let current = open {
            blocks.append(NSRange(location: current.start, length: string.length - current.start))
        }
        return blocks
    }

    // MARK: Dropped quotes

    /// A blockquote dropped from another app: its `>` quote lines followed by
    /// the `> — [title](url)` source line the composer appends.
    struct DroppedQuoteBlock: Equatable {
        let range: NSRange
        let quoteRange: NSRange
        let sourceLineRange: NSRange
    }

    /// Room above the first quote line for the "DROPPED QUOTE" label.
    static let droppedQuoteLabelSpace: CGFloat = 30
    private static let cardInset: CGFloat = 14
    private static let sourceLine = try! NSRegularExpression(pattern: "^> — \\[[^\\]\\n]+\\]\\([^)\\s]+\\)[ \\t]*$")

    static func droppedQuoteBlocks(in string: NSString) -> [DroppedQuoteBlock] {
        guard string.length > 0, string.length <= 60_000 else { return [] }
        var blocks: [DroppedQuoteBlock] = []
        var lines: [NSRange] = []
        func flush() {
            defer { lines.removeAll() }
            guard lines.count >= 2, let last = lines.last else { return }
            let lastText = string.substring(with: last)
            guard sourceLine.firstMatch(
                in: lastText,
                range: NSRange(location: 0, length: (lastText as NSString).length)
            ) != nil else { return }
            let first = lines[0]
            let quoteEnd = lines[lines.count - 2]
            blocks.append(DroppedQuoteBlock(
                range: NSUnionRange(first, last),
                quoteRange: NSUnionRange(first, quoteEnd),
                sourceLineRange: last
            ))
        }
        var location = 0
        while location < string.length {
            var lineEnd = 0
            var contentsEnd = 0
            string.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            let content = NSRange(location: location, length: contentsEnd - location)
            if content.length > 0, string.character(at: location) == 0x3E /* > */ {
                lines.append(content)
            } else {
                flush()
            }
            location = max(lineEnd, location + 1)
        }
        flush()
        return blocks
    }

    /// Indents a dropped quote inside its card and hides the source line's
    /// glyphs under the card's "source link kept" label.
    private static func styleDroppedQuote(_ block: DroppedQuoteBlock, in storage: NSTextStorage, string: NSString) {
        var location = block.range.location
        var isFirst = true
        while location < NSMaxRange(block.range) {
            let line = string.lineRange(for: NSRange(location: location, length: 0))
            let isSource = line.location == block.sourceLineRange.location
            let style = NSMutableParagraphStyle()
            style.lineSpacing = 3
            style.firstLineHeadIndent = cardInset
            style.headIndent = cardInset
            style.tailIndent = -cardInset
            if isFirst { style.paragraphSpacingBefore = droppedQuoteLabelSpace }
            if isSource { style.paragraphSpacing = 16 }
            storage.addAttributes([.paragraphStyle: style], range: line)
            isFirst = false
            location = NSMaxRange(line)
        }
        storage.addAttributes([
            .font: font("GeistMono-Regular", 11, .caption2, weight: .regular),
            .foregroundColor: UIColor.clear,
        ], range: block.sourceLineRange)
    }

    private static func isInsideHeadingMarker(_ range: NSRange, in string: NSString) -> Bool {
        // `# Heading` markers are handled by the heading pass.
        let lineStart = string.lineRange(for: NSRange(location: range.location, length: 0)).location
        return range.location == lineStart && range.length == 1
    }
}

/// Card behind a dropped quote (Signal "Duo split view"): a dashed accent
/// outline, the "DROPPED QUOTE" label and "source link kept" over the
/// quote's hidden source line.
final class MarkdownComposerDroppedQuoteCardView: UIView {
    var sourceLabelOriginY: CGFloat = 0

    private let border = CAShapeLayer()
    private let titleLabel = UILabel()
    private let sourceLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        layer.cornerRadius = 16
        layer.cornerCurve = .continuous
        border.fillColor = UIColor.clear.cgColor
        border.lineWidth = 2
        border.lineDashPattern = [6, 4]
        layer.addSublayer(border)
        titleLabel.text = String(localized: "DROPPED QUOTE")
        titleLabel.adjustsFontForContentSizeCategory = true
        sourceLabel.text = String(localized: "source link kept")
        sourceLabel.adjustsFontForContentSizeCategory = true
        addSubview(titleLabel)
        addSubview(sourceLabel)
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: MarkdownComposerDroppedQuoteCardView, _: UITraitCollection) in
            view.applyColors()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyColors() {
        backgroundColor = UIColor(Geist.card)
        border.strokeColor = UIColor(Geist.accent).cgColor
        titleLabel.textColor = UIColor(Geist.accentText)
        sourceLabel.textColor = UIColor(Geist.muted)
        let mono = UIFont(name: "GeistMono-Regular", size: 10.5) ?? .monospacedSystemFont(ofSize: 10.5, weight: .regular)
        titleLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: mono)
        let attributes: [NSAttributedString.Key: Any] = [.kern: 0.6]
        titleLabel.attributedText = NSAttributedString(string: String(localized: "DROPPED QUOTE"), attributes: attributes)
        let sourceFont = UIFont(name: "GeistMono-Regular", size: 11) ?? .monospacedSystemFont(ofSize: 11, weight: .regular)
        sourceLabel.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(for: sourceFont)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        border.frame = bounds
        border.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerRadius: 15
        ).cgPath
        let inset: CGFloat = 14
        let width = max(0, bounds.width - inset * 2)
        let titleHeight = titleLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        titleLabel.frame = CGRect(x: inset, y: 12, width: width, height: titleHeight)
        let sourceHeight = sourceLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        sourceLabel.frame = CGRect(x: inset, y: sourceLabelOriginY, width: width, height: sourceHeight)
    }
}
