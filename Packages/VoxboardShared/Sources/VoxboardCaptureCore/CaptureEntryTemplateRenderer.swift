import Foundation

/// Renders metadata tokens only inside destination entry formatting. Capture
/// payload text is never interpolated, so a user's literal `{date}` stays intact.
public struct CaptureEntryTemplateRenderer: Sendable {
    /// Canonical spelling of the location entry token. Editors and capture
    /// hints share this so token detection cannot drift from rendering.
    public static let locationToken = "{location}"

    /// True when entry formatting references the `{location}` token, whose
    /// rendered value depends on the active Capture Preset's location opt-in.
    public static func referencesLocation(in template: String) -> Bool {
        template.contains(locationToken)
    }

    public var calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func render(_ template: String, for request: CaptureRequest) -> String {
        let values = CaptureDateTokenValues(date: request.createdAt, calendar: calendar)
        let id = request.id.uuidString.lowercased()
        let replacements = [
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
            "{source}": request.source.rawValue,
            "{id}": id,
            "{id8}": String(id.prefix(8)),
            Self.locationToken: locationMapLink(for: request),
        ]
        let rendered = replacements.reduce(template) { rendered, replacement in
            rendered.replacingOccurrences(of: replacement.key, with: replacement.value)
        }
        // Last, so capture text that looks like a token is never re-rendered.
        guard rendered.contains(Self.titleToken) else { return rendered }
        return rendered.replacingOccurrences(of: Self.titleToken, with: Self.title(for: request) ?? "")
    }

    /// `{title}` in entry formatting: the capture's first meaningful line,
    /// Markdown line markers stripped (e.g. `### {hour}:{minute} · {title}`).
    public static let titleToken = "{title}"

    public static func usesTitle(_ template: String) -> Bool {
        template.contains(titleToken)
    }

    /// The display title for `request`: its first non-empty text line without
    /// heading, quote, list or checkbox markers, at most 80 characters.
    public static func title(for request: CaptureRequest) -> String? {
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
                if let title = displayTitle(String(line)) { return title }
            }
        }
        return nil
    }

    static func displayTitle(_ line: String) -> String? {
        var text = line.trimmingCharacters(in: .whitespaces)
        let markerPattern = #"^(?:#{1,6}\s+|>\s*|[-*+]\s+(?:\[[ xX]\]\s+)?|\d+[.)]\s+)+"#
        if let range = text.range(of: markerPattern, options: .regularExpression) {
            text.removeSubrange(range)
        }
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if text.count > 80 {
            text = String(text.prefix(80)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return text.isEmpty ? nil : text
    }

    /// When entry formatting already carries `{title}`, a leading Markdown
    /// heading that only repeats that title is dropped from the entry body,
    /// so `# Project sync` + `### 10:42 · {title}` writes the title once.
    public static func entry(_ entry: String, droppingHeadingFor title: String?) -> String {
        guard let title else { return entry }
        var lines = entry.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("#"),
              displayTitle(lines[index]) == title else { return entry }
        lines.remove(at: index)
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            lines.remove(at: index)
        }
        return lines.joined(separator: "\n")
    }

    /// Entry body to write under `prefix` (a raw template, before rendering).
    public static func entry(_ entry: String, under prefixTemplate: String, for request: CaptureRequest) -> String {
        usesTitle(prefixTemplate) ? Self.entry(entry, droppingHeadingFor: title(for: request)) : entry
    }

    private func locationMapLink(for request: CaptureRequest) -> String {
        guard let policy = request.voxProfile?.locationPolicy,
              policy.isEnabled,
              case .available(let snapshot)? = request.locationOutcome else { return "" }
        let usesCityPrecision = policy.precision == .city || snapshot.precision == .city
        let effectivePrecision: CaptureLocationPrecision = usesCityPrecision ? .city : .exact
        guard let formatted = try? CaptureLocationFormatter().format(
            snapshot: snapshot,
            requestID: request.id,
            precision: effectivePrecision
        ), let url = formatted[.googleMapsURL] else { return "" }
        return "[Location](\(url))"
    }
}
