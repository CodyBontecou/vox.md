import Foundation

public struct CapturePathPlanner: Sendable {
    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func relativePath(
        for request: CaptureRequest,
        destination: CaptureDestination,
        existingRelativePaths: Set<String> = []
    ) throws -> String {
        switch destination.noteTarget {
        case .newNote(let pathTemplate):
            let rendered = try renderedMarkdownPath(pathTemplate, request: request, rollingPeriod: nil)
            return uniquePath(rendered, avoiding: existingRelativePaths)
        case .rollingNote(let pathTemplate, let period):
            return try renderedMarkdownPath(pathTemplate, request: request, rollingPeriod: period)
        case .existingNote(let relativePath):
            try CapturePathValidation.validateRelativePath(relativePath)
            return relativePath
        }
    }

    private func renderedMarkdownPath(
        _ template: String,
        request: CaptureRequest,
        rollingPeriod: CaptureRollingPeriod?
    ) throws -> String {
        let components = calendar.dateComponents([.month], from: request.createdAt)
        let values = CaptureDateTokenValues(date: request.createdAt, calendar: calendar)
        let id = request.id.uuidString.lowercased()

        let rollingBucket: String
        switch rollingPeriod {
        case .daily: rollingBucket = values.date
        case .weekly: rollingBucket = values.weekToken
        case .monthly: rollingBucket = "\(values.year)-\(values.month)"
        case .quarterly:
            let quarter = ((components.month ?? 1) - 1) / 3 + 1
            rollingBucket = "\(values.year)-Q\(quarter)"
        case .yearly: rollingBucket = values.year
        case nil: rollingBucket = values.date
        }

        var rendered = template
        let replacements = [
            "{period}": rollingBucket,
            "{timestamp}": values.timestamp,
            "{date}": values.date,
            "{time}": values.time,
            "{year}": values.year,
            "{YR}": values.shortYear,
            "{month}": values.month,
            "{day}": values.day,
            "{week}": values.weekToken,
            "{hour}": values.hour,
            "{minute}": values.minute,
            "{second}": values.second,
            "{id}": id,
            "{id8}": String(id.prefix(8)),
        ]
        for (token, value) in replacements {
            rendered = rendered.replacingOccurrences(of: token, with: value)
        }
        // Decide the extension from the template, so a title such as
        // "Release 2.5" never reads as a file extension.
        let needsMarkdownExtension = (rendered
            .replacingOccurrences(of: Self.titleToken, with: "title")
            .trimmingCharacters(in: .whitespacesAndNewlines) as NSString)
            .pathExtension.isEmpty
        // Last, so capture text that looks like a token is never re-rendered.
        if rendered.contains(Self.titleToken) {
            rendered = rendered.replacingOccurrences(
                of: Self.titleToken,
                with: Self.titleComponent(for: request) ?? values.timestamp
            )
        }

        let trimmed = rendered.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = needsMarkdownExtension ? trimmed + ".md" : trimmed
        try CapturePathValidation.validateRelativePath(path)
        return path
    }

    /// `{title}`: the capture's first meaningful line (typed text, link title,
    /// transcript or scanned text), sanitized into one filename component.
    public static let titleToken = "{title}"

    /// Longest title kept in a path component, in characters.
    static let maximumTitleLength = 80

    /// The sanitized title for `request`, or nil when the capture has no text
    /// to name it by (callers fall back to the timestamp).
    static func titleComponent(for request: CaptureRequest) -> String? {
        for payload in request.payloads {
            let candidate: String?
            switch payload {
            case .text(let text): candidate = text
            case .url(let url, let title): candidate = title ?? url.host
            case .audio(_, let transcript): candidate = transcript
            case .scannedDocument(_, _, let extractedText): candidate = extractedText
            case .image(_, let altText, _), .sketch(_, _, let altText, _): candidate = altText
            case .retainedAudio, .file: candidate = nil
            }
            guard let candidate else { continue }
            for line in candidate.split(whereSeparator: \.isNewline) {
                if let title = sanitizedTitle(String(line)) { return title }
            }
        }
        return nil
    }

    /// Strips Markdown line markers and characters that are unsafe in file
    /// names, collapses whitespace and caps the length.
    static func sanitizedTitle(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        // Leading Markdown markers: headings, quotes, list bullets, checkboxes.
        let markerPattern = #"^(?:#{1,6}\s+|>\s*|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)+"#
        if let range = text.range(of: markerPattern, options: .regularExpression) {
            text.removeSubrange(range)
        }
        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|#^[]")
            .union(.controlCharacters)
            .union(.newlines)
        text = String(text.unicodeScalars.map { unsafe.contains($0) ? " " : Character($0) })
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while let first = text.first, first == "." || first == "~" || first.isWhitespace {
            text.removeFirst()
        }
        text = text.trimmingCharacters(in: .whitespaces)
        if text.count > maximumTitleLength {
            text = String(text.prefix(maximumTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        while text.hasSuffix(".") { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private func uniquePath(_ path: String, avoiding existingPaths: Set<String>) -> String {
        guard existingPaths.contains(path) else { return path }
        let nsPath = path as NSString
        let directory = nsPath.deletingLastPathComponent
        let ext = nsPath.pathExtension
        let base = (nsPath.lastPathComponent as NSString).deletingPathExtension

        var index = 2
        while true {
            let filename = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
            let candidate = directory.isEmpty || directory == "."
                ? filename
                : (directory as NSString).appendingPathComponent(filename)
            if !existingPaths.contains(candidate) {
                return candidate
            }
            index += 1
        }
    }

}
