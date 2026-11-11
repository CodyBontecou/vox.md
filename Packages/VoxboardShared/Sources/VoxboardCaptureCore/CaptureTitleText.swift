import Foundation

/// The "first meaningful line" of a capture, shared by the `{title}` token in
/// note paths and entry formatting and by the Lock Screen Route Today lines,
/// so all three name a capture the same way.
enum CaptureTitleText {
    /// Leading Markdown line markers: headings, quotes, list bullets,
    /// checkboxes and numbered items.
    static let lineMarkerPattern = #"^(?:#{1,6}\s+|>\s*|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)+"#

    /// The first line of `request` for which `transform` returns a value,
    /// searching typed text, link titles, transcripts, scanned text and alt
    /// text in payload order.
    static func firstLine(
        in request: CaptureRequest,
        _ transform: (String) -> String?
    ) -> String? {
        for payload in request.payloads {
            guard let text = text(of: payload) else { continue }
            if let line = firstLine(of: text, transform) { return line }
        }
        return nil
    }

    /// A fenced code block delimiter: ```` ``` ```` or `~~~`, optionally with
    /// an info string such as `swift`. Never a meaningful title.
    static let codeFencePattern = #"^\s{0,3}(?:`{3,}|~{3,})"#

    /// The first line of `text` for which `transform` returns a value,
    /// skipping code fence delimiters.
    static func firstLine(of text: String, _ transform: (String) -> String?) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            if line.range(of: codeFencePattern, options: .regularExpression) != nil { continue }
            if let result = transform(String(line)) { return result }
        }
        return nil
    }

    /// `line` trimmed, without leading Markdown markers and with runs of
    /// whitespace collapsed to one space.
    static func strippingLineMarkers(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespaces)
        if let range = text.range(of: lineMarkerPattern, options: .regularExpression) {
            text.removeSubrange(range)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func text(of payload: CapturePayload) -> String? {
        switch payload {
        case .text(let text): text
        case .url(let url, let title): title ?? url.host
        case .audio(_, let transcript): transcript
        case .scannedDocument(_, _, let extractedText): extractedText
        case .image(_, let altText, _), .sketch(_, _, let altText, _): altText
        case .retainedAudio, .file: nil
        }
    }
}
