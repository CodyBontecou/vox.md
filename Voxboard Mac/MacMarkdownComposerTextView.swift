import AppKit
import SwiftUI

/// AppKit-backed Markdown editor used by the Mac Capture workspace.
///
/// Keeping the `NSTextView` alive gives Capture native undo, find, spelling,
/// Services, keyboard selection, and drag behavior while toolbar edits continue
/// to use the shared `CaptureComposerTextEditor` semantics.
@MainActor
final class MacMarkdownComposerController {
    fileprivate weak var textView: NSTextView?
    fileprivate var publishText: ((String) -> Void)?
    fileprivate var publishSelection: ((NSRange) -> Void)?
    fileprivate var publishFocus: ((Bool) -> Void)?

    var text: String { textView?.string ?? "" }
    var selection: NSRange { textView?.selectedRange() ?? NSRange(location: 0, length: 0) }
    var isFocused: Bool { textView?.window?.firstResponder === textView }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
        publishCurrentState()
    }

    func dismissFocus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(nil)
        publishCurrentState()
    }

    func undo() {
        textView?.undoManager?.undo()
        publishCurrentState()
    }

    func redo() {
        textView?.undoManager?.redo()
        publishCurrentState()
    }

    func replaceAll(with text: String, selection: NSRange) {
        apply(text: text, selection: selection, registeringUndo: true)
    }

    func replaceSelection(with replacement: String, selectInsertedText: Bool = false) {
        guard let textView else { return }
        let current = textView.string
        let currentSelection = Self.clamped(textView.selectedRange(), utf16Count: current.utf16.count)
        guard let range = Range(currentSelection, in: current) else { return }
        let next = current.replacingCharacters(in: range, with: replacement)
        let insertedLength = replacement.utf16.count
        let nextSelection = NSRange(
            location: currentSelection.location + (selectInsertedText ? 0 : insertedLength),
            length: selectInsertedText ? insertedLength : 0
        )
        apply(text: next, selection: nextSelection, registeringUndo: true)
    }

    private func apply(text: String, selection: NSRange, registeringUndo: Bool) {
        guard let textView else { return }
        let oldText = textView.string
        let oldSelection = textView.selectedRange()
        if registeringUndo, oldText != text || oldSelection != selection {
            textView.undoManager?.registerUndo(withTarget: self) { controller in
                controller.apply(text: oldText, selection: oldSelection, registeringUndo: true)
            }
            textView.undoManager?.setActionName(String(localized: "Edit Markdown"))
        }

        textView.string = text
        MacMarkdownSyntaxStyler.apply(to: textView)
        textView.setSelectedRange(Self.clamped(selection, utf16Count: text.utf16.count))
        textView.scrollRangeToVisible(textView.selectedRange())
        publishCurrentState()
    }

    fileprivate func publishCurrentState() {
        guard let textView else { return }
        publishText?(textView.string)
        publishSelection?(textView.selectedRange())
        publishFocus?(textView.window?.firstResponder === textView)
    }

    fileprivate func disconnect(_ textView: NSTextView) {
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

/// An audio attachment shown as a playable chip inside the composer's
/// document flow (Signal MacWorkspace). It sits on its `![[file]]` line when
/// the text embeds it, otherwise after the text, where delivery appends it.
struct MacComposerInlineAudio: Identifiable, Equatable {
    /// Stable identity (the staged relative path).
    let id: String
    let url: URL
    let filename: String
    let speakerCount: Int
}

struct MacMarkdownComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    @Binding var isFocused: Bool
    let controller: MacMarkdownComposerController
    var style: MacMarkdownSyntaxStyler.Style = .document
    var textInset = NSSize(width: 28, height: 48)
    var inlineAudio: [MacComposerInlineAudio] = []
    var onRemoveInlineAudio: ((String) -> Void)?
    var accessibilityLabel: String = String(localized: "Capture note")
    var accessibilityIdentifier = "mac_quick_capture_text"

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // An explicit TextKit 1 stack: checkbox drawing and inline chips use
        // NSLayoutManager geometry.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(
            containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        layoutManager.addTextContainer(container)
        let textView = MacComposerTextView(frame: .zero, textContainer: container)
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        let scrollView = NSScrollView()
        scrollView.documentView = textView

        textView.markdownStyle = style
        textView.baseInset = textInset
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindPanel = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isContinuousSpellCheckingEnabled = true
        textView.drawsBackground = false
        textView.textColor = .textColor
        textView.insertionPointColor = MacBrand.appKitOrange
        textView.font = MacMarkdownSyntaxStyler.font(size: style.bodySize, weight: "Regular")
        textView.textContainerInset = textInset
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = style.lineHeightMultiple
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes[.paragraphStyle] = paragraph
        textView.onRemoveInlineAudio = onRemoveInlineAudio
        textView.inlineAudio = inlineAudio
        textView.string = text
        MacMarkdownSyntaxStyler.apply(to: textView)
        textView.setSelectedRange(Self.clamped(selection, utf16Count: text.utf16.count))
        textView.setAccessibilityLabel(accessibilityLabel)
        textView.setAccessibilityIdentifier(accessibilityIdentifier)

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        connect(textView, coordinator: context.coordinator)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.parent = self
        connect(textView, coordinator: context.coordinator)

        if let composer = textView as? MacComposerTextView {
            composer.onRemoveInlineAudio = onRemoveInlineAudio
            if composer.inlineAudio != inlineAudio {
                composer.inlineAudio = inlineAudio
                MacMarkdownSyntaxStyler.apply(to: composer)
            }
        }
        if textView.string != text {
            textView.string = text
            MacMarkdownSyntaxStyler.apply(to: textView)
        }
        let desired = Self.clamped(selection, utf16Count: text.utf16.count)
        if textView.selectedRange() != desired {
            textView.setSelectedRange(desired)
        }

        if isFocused, textView.window?.firstResponder !== textView {
            let coordinator = context.coordinator
            DispatchQueue.main.async { [weak textView, weak coordinator] in
                guard let textView, let coordinator, coordinator.parent.isFocused else { return }
                textView.window?.makeFirstResponder(textView)
            }
        } else if !isFocused, textView.window?.firstResponder === textView {
            textView.window?.makeFirstResponder(nil)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        coordinator.parent.controller.disconnect(textView)
    }

    private func connect(_ textView: NSTextView, coordinator: Coordinator) {
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

    private static func clamped(_ range: NSRange, utf16Count: Int) -> NSRange {
        MacMarkdownComposerController.clamped(range, utf16Count: utf16Count)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MacMarkdownComposerTextView

        init(parent: MacMarkdownComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            if let textView = notification.object as? NSTextView, !textView.hasMarkedText() {
                MacMarkdownSyntaxStyler.apply(to: textView)
            }
            parent.controller.publishCurrentState()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            parent.controller.publishCurrentState()
        }

        func textDidBeginEditing(_ notification: Notification) {
            parent.controller.publishCurrentState()
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.controller.publishCurrentState()
        }
    }
}

/// Composer text view: draws clickable checkboxes over Markdown task markers
/// and hosts inline audio chips, without changing the plain-Markdown string.
final class MacComposerTextView: NSTextView {
    var markdownStyle: MacMarkdownSyntaxStyler.Style = .document
    /// Visual top/side inset; the bottom grows to make room for trailing chips.
    var baseInset = NSSize(width: 28, height: 48) {
        didSet { updateInsetForTrailingChips() }
    }
    var inlineAudio: [MacComposerInlineAudio] = [] {
        didSet { if inlineAudio != oldValue { scheduleInlineLayout() } }
    }
    var onRemoveInlineAudio: ((String) -> Void)?

    private var chipViews: [String: NSHostingView<MacAudioAttachmentChip>] = [:]
    private var trailingChipsHeight: CGFloat = 0
    private var isInlineLayoutScheduled = false
    private static let chipLineHeight: CGFloat = 64
    private static let chipSpacing: CGFloat = 10

    override var textContainerOrigin: NSPoint {
        NSPoint(x: baseInset.width, y: baseInset.height)
    }

    // MARK: Checkboxes

    /// Checkbox frames (view coordinates) with the range of their `[ ]`.
    private func checkboxFrames() -> [(rect: NSRect, range: NSRange, checked: Bool)] {
        guard markdownStyle.rendersTaskCheckboxes,
              let storage = textStorage,
              let layoutManager,
              let textContainer else { return [] }
        var result: [(NSRect, NSRange, Bool)] = []
        let origin = textContainerOrigin
        storage.enumerateAttribute(
            .macTaskCheckbox,
            in: NSRange(location: 0, length: storage.length)
        ) { value, range, _ in
            guard let checked = (value as? NSNumber)?.boolValue else { return }
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphs.length > 0 else { return }
            let line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            let glyphRect = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
            let size = MacMarkdownSyntaxStyler.checkboxSize
            // Center on the line's first baseline area (lines are 1.35× tall).
            let font = (storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
            let lineHeight = font.map { layoutManager.defaultLineHeight(for: $0) } ?? line.height
            let rect = NSRect(
                x: origin.x + glyphRect.minX,
                // lineHeightMultiple adds its extra space above the glyphs, so
                // center on the glyph box at the bottom of the fragment.
                y: origin.y + line.maxY - min(line.height, lineHeight) + (min(line.height, lineHeight) - size) / 2,
                width: size,
                height: size
            )
            result.append((rect, range, checked))
        }
        return result
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        for box in checkboxFrames() where box.rect.intersects(dirtyRect) {
            drawCheckbox(in: box.rect, checked: box.checked)
        }
    }

    private func drawCheckbox(in rect: NSRect, checked: Bool) {
        let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
        if checked {
            MacBrand.appKitOrange.setFill()
            path.fill()
            let check = NSBezierPath()
            check.move(to: NSPoint(x: rect.minX + rect.width * 0.26, y: rect.minY + rect.height * 0.52))
            check.line(to: NSPoint(x: rect.minX + rect.width * 0.43, y: rect.minY + rect.height * 0.70))
            check.line(to: NSPoint(x: rect.minX + rect.width * 0.75, y: rect.minY + rect.height * 0.32))
            check.lineWidth = 2
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            NSColor.white.setStroke()
            check.stroke()
        } else {
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor.tertiaryLabelColor.setStroke()
            path.lineWidth = 1.2
            path.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1,
           !event.modifierFlags.contains(.shift),
           let box = checkboxFrames().first(where: { $0.rect.insetBy(dx: -4, dy: -4).contains(point) }) {
            toggleTask(at: box.range, checked: box.checked)
            return
        }
        super.mouseDown(with: event)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        for box in checkboxFrames() {
            addCursorRect(box.rect.insetBy(dx: -4, dy: -4), cursor: .pointingHand)
        }
    }

    /// Flips `[ ]` ↔ `[x]` in the Markdown source with undo support.
    private func toggleTask(at boxRange: NSRange, checked: Bool) {
        let stateRange = NSRange(location: boxRange.location + 1, length: 1)
        let replacement = checked ? " " : "x"
        guard shouldChangeText(in: stateRange, replacementString: replacement) else { return }
        textStorage?.replaceCharacters(in: stateRange, with: replacement)
        didChangeText()
        undoManager?.setActionName(String(localized: "Toggle Task"))
    }

    // MARK: Inline audio

    /// Filenames that have a staged audio attachment, matched against
    /// `![[filename]]` lines.
    private var anchoredAudio: [(audio: MacComposerInlineAudio, lineRange: NSRange)] {
        let text = string as NSString
        var used = Set<Int>()
        return inlineAudio.compactMap { audio in
            let candidates = Set([audio.filename, (audio.id as NSString).lastPathComponent])
            for name in candidates where !name.isEmpty {
                let embed = "![[\(name)]]"
                var search = NSRange(location: 0, length: text.length)
                while true {
                    let found = text.range(of: embed, options: [], range: search)
                    guard found.location != NSNotFound else { break }
                    let line = text.lineRange(for: found)
                    let trimmed = text.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed == embed, used.insert(line.location).inserted {
                        return (audio, line)
                    }
                    search = NSRange(location: NSMaxRange(found), length: text.length - NSMaxRange(found))
                }
            }
            return nil
        }
    }

    /// Hides each anchored `![[file.m4a]]` line and gives it room for its chip.
    func styleInlineAudioAnchors(in storage: NSTextStorage) {
        guard markdownStyle.rendersTaskCheckboxes else { return }
        for anchor in anchoredAudio {
            var contentRange = anchor.lineRange
            let text = storage.string as NSString
            if NSMaxRange(contentRange) > 0,
               NSMaxRange(contentRange) <= text.length,
               contentRange.length > 0,
               text.character(at: NSMaxRange(contentRange) - 1) == 0x0A {
                contentRange.length -= 1
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = Self.chipLineHeight
            paragraph.maximumLineHeight = Self.chipLineHeight
            storage.addAttribute(.paragraphStyle, value: paragraph, range: anchor.lineRange)
            storage.addAttribute(.foregroundColor, value: NSColor.clear, range: contentRange)
        }
    }

    func markdownDidRestyle() {
        scheduleInlineLayout()
        window?.invalidateCursorRects(for: self)
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        scheduleInlineLayout()
    }

    override func didChangeText() {
        super.didChangeText()
        scheduleInlineLayout()
    }

    private func scheduleInlineLayout() {
        guard !isInlineLayoutScheduled else { return }
        isInlineLayoutScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isInlineLayoutScheduled = false
            self.layoutInlineAudio()
        }
    }

    private func layoutInlineAudio() {
        guard let layoutManager, let textContainer else { return }
        let liveIDs = Set(inlineAudio.map(\.id))
        for (id, view) in chipViews where !liveIDs.contains(id) {
            view.removeFromSuperview()
            chipViews[id] = nil
        }
        guard !inlineAudio.isEmpty else {
            if trailingChipsHeight != 0 {
                trailingChipsHeight = 0
                updateInsetForTrailingChips()
            }
            return
        }
        layoutManager.ensureLayout(for: textContainer)
        let origin = textContainerOrigin
        let x = origin.x + textContainer.lineFragmentPadding
        let maxWidth = max(120, min(420, bounds.width - x - baseInset.width))
        let anchors = anchoredAudio
        let anchoredIDs = Set(anchors.map(\.audio.id))

        for anchor in anchors {
            let view = chipView(for: anchor.audio)
            let size = chipSize(view, maxWidth: maxWidth)
            let glyphs = layoutManager.glyphRange(forCharacterRange: anchor.lineRange, actualCharacterRange: nil)
            guard glyphs.length > 0 else { continue }
            let line = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
            view.frame = NSRect(
                x: x,
                y: origin.y + line.minY + max(0, (line.height - size.height) / 2),
                width: size.width,
                height: size.height
            )
        }

        // Unanchored audio follows the text, where delivery appends it.
        var y = origin.y + layoutManager.usedRect(for: textContainer).maxY + 16
        var trailing: CGFloat = 0
        for audio in inlineAudio where !anchoredIDs.contains(audio.id) {
            let view = chipView(for: audio)
            let size = chipSize(view, maxWidth: maxWidth)
            view.frame = NSRect(x: x, y: y, width: size.width, height: size.height)
            y += size.height + Self.chipSpacing
            trailing += size.height + Self.chipSpacing
        }
        let neededTrailing = trailing > 0 ? trailing + 16 : 0
        if abs(neededTrailing - trailingChipsHeight) > 0.5 {
            trailingChipsHeight = neededTrailing
            updateInsetForTrailingChips()
        }
    }

    private func chipView(for audio: MacComposerInlineAudio) -> NSHostingView<MacAudioAttachmentChip> {
        let remove = onRemoveInlineAudio
        let chip = MacAudioAttachmentChip(
            url: audio.url,
            filename: audio.filename,
            speakerCount: audio.speakerCount,
            onRemove: remove.map { handler in { handler(audio.id) } }
        )
        if let existing = chipViews[audio.id] {
            existing.rootView = chip
            return existing
        }
        let view = NSHostingView(rootView: chip)
        addSubview(view)
        chipViews[audio.id] = view
        return view
    }

    private func chipSize(_ view: NSView, maxWidth: CGFloat) -> NSSize {
        let fitting = view.fittingSize
        return NSSize(width: min(maxWidth, max(fitting.width, 200)), height: max(fitting.height, 50))
    }

    /// `textContainerInset` is symmetric; the overridden origin keeps the top
    /// at `baseInset.height`, so a larger inset only adds bottom room.
    private func updateInsetForTrailingChips() {
        let inset = NSSize(width: baseInset.width, height: baseInset.height + trailingChipsHeight / 2)
        if textContainerInset != inset {
            textContainerInset = inset
            invalidateTextContainerOrigin()
        }
    }
}
