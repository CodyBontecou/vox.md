import Foundation

/// Reconciles a replaceable live-transcription span with an editable Capture draft.
///
/// Speech lands where the writer's cursor was when recording started (or at the
/// end of the draft), joined to the surrounding text with a space rather than a
/// new paragraph. Apple Speech volatile results may revise earlier words, so the
/// span is replaced in place as recognition progresses. Finalization swaps that
/// same span for the committed transcript instead of inserting a duplicate.
///
/// Offsets are UTF-16, matching `UITextView.selectedRange`.
public struct LiveTranscriptDraftPreview: Equatable, Sendable {
    /// Where the transcript goes in the draft *without* the rendered span.
    /// `nil` means the end of the draft.
    private var anchor: Int?
    /// The text currently rendered into the draft, separators included.
    private var renderedBlock = ""
    /// UTF-16 location of `renderedBlock` in the draft it was rendered into.
    private var renderedLocation = 0
    private var transcript = ""
    /// Leading words of the session transcript already left in the draft as
    /// plain text because the writer typed or moved the cursor mid-recording.
    /// Later renders and the final commit place only the words after them.
    private var frozenWordCount = 0
    /// UTF-16 offset just past the transcript (before any trailing separator)
    /// in the most recently returned draft; a natural place for the caret.
    public private(set) var caretOffset: Int?

    public init(insertionOffset: Int? = nil) {
        anchor = insertionOffset.map { max(0, $0) }
    }

    public var isRendering: Bool { !renderedBlock.isEmpty }

    /// Where the next transcript text goes in the draft without the live span.
    public var insertionOffset: Int? { anchor }

    public mutating func render(
        finalizedText: String,
        volatileText: String?,
        in currentDraft: String
    ) -> String {
        let base = removingRenderedBlock(from: currentDraft)
        transcript = Self.droppingWords(
            frozenWordCount,
            from: Self.merged(finalizedText: finalizedText, volatileText: volatileText)
        )
        return place(in: base)
    }

    public mutating func commit(_ transcript: String, in currentDraft: String) -> String {
        let base = removingRenderedBlock(from: currentDraft)
        self.transcript = Self.droppingWords(
            frozenWordCount,
            from: transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let result = place(in: base)
        renderedBlock = ""
        return result
    }

    public mutating func cancel(in currentDraft: String) -> String {
        let base = removingRenderedBlock(from: currentDraft)
        renderedBlock = ""
        caretOffset = nil
        return base
    }

    /// The writer typed or moved the cursor while recording: the words already
    /// shown stay in the draft as ordinary text, and the next words go to
    /// `offset` (UTF-16, in `currentDraft`). The draft text is unchanged.
    public mutating func moveInsertion(toUTF16Offset offset: Int, in currentDraft: String) {
        if !renderedBlock.isEmpty {
            frozenWordCount += Self.wordCount(transcript)
            renderedBlock = ""
            transcript = ""
        }
        anchor = Self.clampedOffset(max(0, offset), in: currentDraft)
        caretOffset = anchor
    }

    /// Inserts a whole line (timestamp marker, empty task) just ahead of the
    /// live span, so the span keeps rendering after it.
    public mutating func insertLine(_ line: String, in currentDraft: String) -> String {
        let base = removingRenderedBlock(from: currentDraft)
        let at = Self.clampedOffset(anchor, in: base)
        let insertion = line.hasSuffix("\n") ? line : line + "\n"
        let before = Self.character(before: at, in: base)
        let prefix = before == nil || before == "\n" ? "" : "\n"
        let joined = prefix + insertion
        let ns = base as NSString
        let updated = ns.replacingCharacters(in: NSRange(location: at, length: 0), with: joined)
        anchor = at + (joined as NSString).length
        return place(in: updated)
    }

    /// One-shot insertion for a transcript that never had a live span (batch
    /// transcription). Returns the new text and the caret offset after it.
    public static func inserting(
        _ transcript: String,
        into text: String,
        atUTF16Offset offset: Int?
    ) -> (text: String, caretOffset: Int) {
        var preview = LiveTranscriptDraftPreview(insertionOffset: offset)
        let result = preview.commit(transcript, in: text)
        return (result, preview.caretOffset ?? (result as NSString).length)
    }

    // MARK: Placement

    private mutating func place(in base: String) -> String {
        guard !transcript.isEmpty else {
            renderedBlock = ""
            caretOffset = nil
            return base
        }
        let at = Self.clampedOffset(anchor, in: base)
        let before = Self.character(before: at, in: base)
        let after = Self.character(at: at, in: base)
        let leading = Self.needsLeadingSpace(before: before) ? " " : ""
        let trailing = Self.needsTrailingSpace(after: after) ? " " : ""
        let block = leading + transcript + trailing
        let ns = base as NSString
        let result = ns.replacingCharacters(in: NSRange(location: at, length: 0), with: block)
        renderedBlock = block
        renderedLocation = at
        caretOffset = at + (leading + transcript as NSString).length
        return result
    }

    private mutating func removingRenderedBlock(from draft: String) -> String {
        guard !renderedBlock.isEmpty else { return draft }
        let ns = draft as NSString
        let blockLength = (renderedBlock as NSString).length
        // Fast path: nothing moved the span since it was rendered.
        if renderedLocation + blockLength <= ns.length,
           ns.substring(with: NSRange(location: renderedLocation, length: blockLength)) == renderedBlock {
            if anchor != nil { anchor = renderedLocation }
            return ns.replacingCharacters(
                in: NSRange(location: renderedLocation, length: blockLength),
                with: ""
            )
        }
        // Typing before the span shifted it: find the occurrence nearest to
        // where it was rendered.
        var best: NSRange?
        var searchRange = NSRange(location: 0, length: ns.length)
        while true {
            let found = ns.range(of: renderedBlock, options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            if best == nil || abs(found.location - renderedLocation) < abs(best!.location - renderedLocation) {
                best = found
            }
            let next = found.location + 1
            guard next < ns.length else { break }
            searchRange = NSRange(location: next, length: ns.length - next)
        }
        guard let best else {
            // Preserve user edits if the preview itself was manually changed.
            return draft
        }
        if anchor != nil { anchor = best.location }
        return ns.replacingCharacters(in: best, with: "")
    }

    // MARK: Helpers

    private static func merged(finalizedText: String, volatileText: String?) -> String {
        let finalized = finalizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let volatile = (volatileText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        switch (finalized.isEmpty, volatile.isEmpty) {
        case (true, true): return ""
        case (false, true): return finalized
        case (true, false): return volatile
        case (false, false): return finalized + " " + volatile
        }
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    private static func droppingWords(_ count: Int, from text: String) -> String {
        guard count > 0 else { return text }
        return text.split(whereSeparator: \.isWhitespace).dropFirst(count).joined(separator: " ")
    }

    /// Clamps to the text and snaps back to a composed-character boundary so
    /// an insertion never splits an emoji or combining sequence.
    private static func clampedOffset(_ offset: Int?, in text: String) -> Int {
        let ns = text as NSString
        guard let offset, offset < ns.length else { return ns.length }
        guard offset > 0 else { return 0 }
        return ns.rangeOfComposedCharacterSequence(at: offset).location
    }

    private static func character(before offset: Int, in text: String) -> Character? {
        guard offset > 0 else { return nil }
        let ns = text as NSString
        let range = ns.rangeOfComposedCharacterSequence(at: offset - 1)
        return Character(ns.substring(with: range))
    }

    private static func character(at offset: Int, in text: String) -> Character? {
        let ns = text as NSString
        guard offset < ns.length else { return nil }
        let range = ns.rangeOfComposedCharacterSequence(at: offset)
        return Character(ns.substring(with: range))
    }

    private static func needsLeadingSpace(before: Character?) -> Bool {
        guard let before else { return false }
        return !before.isWhitespace && !"([{\"'“‘".contains(before)
    }

    private static func needsTrailingSpace(after: Character?) -> Bool {
        guard let after else { return false }
        return !after.isWhitespace && !".,;:!?)]}\"'”’…".contains(after)
    }
}
