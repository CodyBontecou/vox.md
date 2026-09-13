import Foundation

public enum MarkdownDocumentEditorError: Error, Equatable, LocalizedError, Sendable {
    case headingNotFound(CaptureHeadingSelector)
    case invalidHeadingLevel(Int)
    case duplicateFrontmatterKey

    public var errorDescription: String? {
        switch self {
        case .headingNotFound(let selector):
            return "The Markdown heading \"\(selector.title)\" was not found."
        case .invalidHeadingLevel(let level):
            return "Markdown heading level \(level) is invalid."
        case .duplicateFrontmatterKey:
            return "Ordered capture frontmatter contains a duplicate key."
        }
    }
}

public struct MarkdownOrderedFrontmatterField: Equatable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct MarkdownCaptureMutation: Equatable, Sendable {
    public var requestID: UUID
    public var entry: String
    public var placement: CapturePlacement
    public var entryPrefix: String
    public var entrySuffix: String
    public var frontmatter: [String: String]
    /// Contract-order metadata used only by the bounded M2 adapter. Existing
    /// dictionary callers remain byte-compatible through `frontmatter`.
    public var orderedFrontmatter: [MarkdownOrderedFrontmatterField]?
    /// A typed location item appended to its request-ID keyed frontmatter
    /// collection. Nil preserves all legacy mutation behavior.
    public var locationMetadata: CaptureLocationRenderedMetadata?
    public var retryProtectionEnabled: Bool
    /// Applies the bounded M2/new-note trailing-LF policy at the production writer seam.
    /// Existing callers default to the established no-final-LF behavior.
    public var finalNewline: Bool
    /// Production pipeline writes include an authorized root and relative path
    /// so the writer can use descriptor-relative, no-symlink I/O.
    public var destinationRootURL: URL?
    public var relativeNotePath: String?

    public init(
        requestID: UUID,
        entry: String,
        placement: CapturePlacement,
        entryPrefix: String = "",
        entrySuffix: String = "",
        frontmatter: [String: String] = [:],
        orderedFrontmatter: [MarkdownOrderedFrontmatterField]? = nil,
        locationMetadata: CaptureLocationRenderedMetadata? = nil,
        retryProtectionEnabled: Bool = false,
        finalNewline: Bool = false,
        destinationRootURL: URL? = nil,
        relativeNotePath: String? = nil
    ) {
        self.requestID = requestID
        self.entry = entry
        self.placement = placement
        self.entryPrefix = entryPrefix
        self.entrySuffix = entrySuffix
        self.frontmatter = frontmatter
        self.orderedFrontmatter = orderedFrontmatter
        self.locationMetadata = locationMetadata
        self.retryProtectionEnabled = retryProtectionEnabled
        self.finalNewline = finalNewline
        self.destinationRootURL = destinationRootURL
        self.relativeNotePath = relativeNotePath
    }
}

/// Applies the final-newline policy used by coordinated Markdown writes.
///
/// M2 calls this production seam directly so parity covers the same bytes the writer
/// persists rather than oracle-only post-processing.
public enum CaptureMarkdownWritePolicy: Sendable {
    public static func applyingFinalNewline(_ finalNewline: Bool, to document: String) -> String {
        let withoutTrailingNewlines = document.trimmingCharacters(in: .newlines)
        return finalNewline ? withoutTrailingNewlines + "\n" : withoutTrailingNewlines
    }
}

public struct MarkdownDocumentEditor: Sendable {
    public init() {}

    public func applying(_ mutation: MarkdownCaptureMutation, to document: String) throws -> String {
        let normalizedDocument = normalizeNewlines(document)
        let marker = CaptureRequestMarker.text(for: mutation.requestID)
        if CaptureRequestMarker.isPresent(in: normalizedDocument, requestID: mutation.requestID) {
            return CaptureMarkdownWritePolicy.applyingFinalNewline(
                mutation.finalNewline,
                to: normalizedDocument
            )
        }

        var documentParts = splitLeadingFrontmatter(normalizedDocument)
        // Keep a compact task/frontmatter boundary compact on later appends,
        // without changing the header spacing of an existing loose list.
        let preservesCompactTaskStart = documentParts.frontmatter != nil
            && listItemMarker(in: firstLine(of: documentParts.body)) != nil
        if let location = mutation.locationMetadata,
           try validatedLocationCollectionContains(location, in: documentParts.frontmatter) {
            return normalizedDocument
        }
        let entryParts = splitLeadingFrontmatter(normalizeNewlines(mutation.entry))
        let wrappedParts = splitLeadingFrontmatter(
            normalizeNewlines(mutation.entryPrefix)
                + trimBoundaryNewlines(entryParts.body)
                + normalizeNewlines(mutation.entrySuffix)
        )
        let voxFrontmatter = try mutation.orderedFrontmatter.map(structuredFrontmatterLines)
            ?? structuredFrontmatterLines(mutation.frontmatter)
        documentParts.frontmatter = mergeFrontmatter(
            existing: mergeFrontmatter(
                existing: mergeFrontmatter(
                    existing: documentParts.frontmatter,
                    incoming: entryParts.frontmatter
                ),
                incoming: voxFrontmatter
            ),
            incoming: wrappedParts.frontmatter
        )
        if let location = mutation.locationMetadata {
            documentParts.frontmatter = try appendingLocation(
                location,
                to: documentParts.frontmatter
            )
        }

        let wrappedEntry = trimBoundaryNewlines(wrappedParts.body)
        let captureBlock = mutation.retryProtectionEnabled
            ? addingRetryMarker(marker, to: wrappedEntry)
            : wrappedEntry

        let editedBody: String
        switch mutation.placement {
        case .append:
            editedBody = joinBlocks([documentParts.body, captureBlock])
        case .prepend:
            editedBody = joinBlocks([captureBlock, documentParts.body])
        case .beneathHeading(let selector, let missingHeadingBehavior, let headingPosition):
            editedBody = try inserting(
                captureBlock,
                beneath: selector,
                missingBehavior: missingHeadingBehavior,
                position: headingPosition,
                in: documentParts.body
            )
        }

        return CaptureMarkdownWritePolicy.applyingFinalNewline(
            mutation.finalNewline,
            to: assemble(
                frontmatter: documentParts.frontmatter,
                body: editedBody,
                compactTaskStart: (mutation.placement == .prepend
                    && listItemMarker(in: firstLine(of: captureBlock)) != nil)
                    || documentParts.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || preservesCompactTaskStart
            )
        )
    }

    private func inserting(
        _ captureBlock: String,
        beneath selector: CaptureHeadingSelector,
        missingBehavior: CaptureMissingHeadingBehavior,
        position: CaptureHeadingPosition,
        in body: String
    ) throws -> String {
        if let level = selector.level, !(1...6).contains(level) {
            throw MarkdownDocumentEditorError.invalidHeadingLevel(level)
        }

        let lines = body.components(separatedBy: "\n")
        if let headingIndex = firstHeadingIndex(matching: selector, in: lines) {
            switch position {
            case .top:
                let before = lines[...headingIndex].joined(separator: "\n")
                let after = headingIndex + 1 < lines.count
                    ? lines[(headingIndex + 1)...].joined(separator: "\n")
                    : ""
                return joinBlocks([before, captureBlock, after])
            case .bottom:
                // The section owned by the heading extends to the next heading
                // of the same or higher level outside code fences (deeper
                // headings stay inside), or the end of the document.
                let matchedLevel = atxHeading(in: lines[headingIndex])?.level ?? selector.level ?? 6
                let sectionEnd = endOfSection(after: headingIndex, headingLevel: matchedLevel, in: lines)
                let before = sectionEnd > 0
                    ? lines[...(sectionEnd - 1)].joined(separator: "\n")
                    : ""
                let after = sectionEnd < lines.count
                    ? lines[sectionEnd...].joined(separator: "\n")
                    : ""
                return joinBlocks([before, captureBlock, after])
            }
        }

        switch missingBehavior {
        case .fail:
            throw MarkdownDocumentEditorError.headingNotFound(selector)
        case .create:
            let level = selector.level ?? 2
            guard (1...6).contains(level) else {
                throw MarkdownDocumentEditorError.invalidHeadingLevel(level)
            }
            return joinBlocks([body, "\(String(repeating: "#", count: level)) \(selector.title)", captureBlock])
        }
    }

    /// The index of the first line after the heading that starts a sibling or
    /// parent section: a heading of the same or higher level outside fences.
    /// Fence-aware and conservative: unclosed fences swallow the rest of the
    /// document, matching `firstHeadingIndex`'s heading matching rules.
    private func endOfSection(after headingIndex: Int, headingLevel: Int, in lines: [String]) -> Int {
        var fence: Fence?
        var index = headingIndex + 1
        while index < lines.count {
            let line = lines[index]
            if let delimiter = fenceDelimiter(in: line) {
                if let current = fence {
                    if delimiter.character == current.character && delimiter.count >= current.count {
                        fence = nil
                    }
                } else {
                    fence = delimiter
                }
                index += 1
                continue
            }
            if fence == nil, let heading = atxHeading(in: line), heading.level <= headingLevel {
                return index
            }
            index += 1
        }
        return lines.count
    }

    private func firstHeadingIndex(matching selector: CaptureHeadingSelector, in lines: [String]) -> Int? {
        var fence: Fence?
        for (index, line) in lines.enumerated() {
            if let delimiter = fenceDelimiter(in: line) {
                if let current = fence {
                    if delimiter.character == current.character && delimiter.count >= current.count {
                        fence = nil
                    }
                } else {
                    fence = delimiter
                }
                continue
            }
            guard fence == nil, let heading = atxHeading(in: line) else { continue }
            if heading.title == selector.title,
               selector.level == nil || selector.level == heading.level {
                return index
            }
        }
        return nil
    }

    private func atxHeading(in line: String) -> (level: Int, title: String)? {
        let leadingTrimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        let level = leadingTrimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level) else { return nil }
        let afterHashes = leadingTrimmed.dropFirst(level)
        guard afterHashes.first == " " || afterHashes.first == "\t" else { return nil }

        var title = afterHashes.trimmingCharacters(in: .whitespacesAndNewlines)
        while title.last == "#" {
            title.removeLast()
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return (level, title)
    }

    private struct Fence: Equatable {
        let character: Character
        let count: Int
    }

    private func fenceDelimiter(in line: String) -> Fence? {
        let leadingSpaces = line.prefix(while: { $0 == " " }).count
        guard leadingSpaces <= 3 else { return nil }
        let trimmed = line.dropFirst(leadingSpaces)
        guard let character = trimmed.first, character == "`" || character == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == character }).count
        return count >= 3 ? Fence(character: character, count: count) : nil
    }

    private struct MarkdownParts {
        var frontmatter: [String]?
        var body: String
    }

    private func splitLeadingFrontmatter(_ markdown: String) -> MarkdownParts {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first == "---",
              let closingIndex = lines.indices.dropFirst().first(where: { lines[$0] == "---" }) else {
            return MarkdownParts(frontmatter: nil, body: markdown)
        }

        let frontmatter = closingIndex > 1 ? Array(lines[1..<closingIndex]) : []
        // Vox.md treats frontmatter as a key/value mapping. Requiring at least
        // one top-level key prevents an ordinary leading horizontal-rule block
        // from being silently moved into a destination's YAML header.
        guard frontmatter.contains(where: { frontmatterEntry($0) != nil }) else {
            return MarkdownParts(frontmatter: nil, body: markdown)
        }
        let body = closingIndex + 1 < lines.count
            ? lines[(closingIndex + 1)...].joined(separator: "\n")
            : ""
        return MarkdownParts(frontmatter: frontmatter, body: body)
    }

    private func mergeFrontmatter(existing: [String]?, incoming: [String]?) -> [String]? {
        guard let incoming else { return existing }
        guard var merged = existing else { return incoming }

        var incomingIndex = 0
        while incomingIndex < incoming.count {
            guard let incomingEntry = frontmatterEntry(incoming[incomingIndex]) else {
                if !merged.contains(incoming[incomingIndex]) {
                    merged.append(incoming[incomingIndex])
                }
                incomingIndex += 1
                continue
            }

            let incomingEnd = sectionEnd(startingAt: incomingIndex, in: incoming)
            let incomingSection = Array(incoming[incomingIndex..<incomingEnd])
            guard let existingIndex = merged.indices.first(where: {
                frontmatterEntry(merged[$0])?.key == incomingEntry.key
            }) else {
                merged.append(contentsOf: incomingSection)
                incomingIndex = incomingEnd
                continue
            }

            if Self.additiveFrontmatterKeys.contains(incomingEntry.key) {
                let existingEnd = sectionEnd(startingAt: existingIndex, in: merged)
                let existingValues = frontmatterValues(
                    in: Array(merged[existingIndex..<existingEnd])
                )
                let incomingValues = frontmatterValues(in: incomingSection)
                let values = unique(existingValues + incomingValues)
                merged.replaceSubrange(
                    existingIndex..<existingEnd,
                    with: ["\(incomingEntry.key): [\(values.joined(separator: ", "))]"]
                )
            }
            // Existing non-additive values are user-owned and intentionally win.
            incomingIndex = incomingEnd
        }
        return merged
    }

    private static let additiveFrontmatterKeys: Set<String> = ["tags", "tag", "audio"]

    private func validatedLocationCollectionContains(
        _ location: CaptureLocationRenderedMetadata,
        in frontmatter: [String]?
    ) throws -> Bool {
        guard let frontmatter,
              let start = frontmatter.indices.first(where: {
                  guard let key = frontmatterEntry(frontmatter[$0])?.key else { return false }
                  return unquotedYAMLKey(key) == location.collectionKey
              }) else { return false }
        let end = sectionEnd(startingAt: start, in: frontmatter)
        guard let entry = frontmatterEntry(frontmatter[start]) else {
            throw CaptureLocationMetadataError.frontmatterCollision(location.collectionKey)
        }
        let value = entry.value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value == "[]" {
            let hasContent = frontmatter[(start + 1)..<end].contains {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            }
            guard !hasContent else {
                throw CaptureLocationMetadataError.frontmatterCollision(location.collectionKey)
            }
            return false
        }
        guard value.isEmpty else {
            throw CaptureLocationMetadataError.frontmatterCollision(location.collectionKey)
        }

        let continuation = frontmatter[(start + 1)..<end].compactMap { raw -> String? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { return nil }
            return raw
        }
        if continuation.isEmpty { return false }
        guard continuation.allSatisfy({ line in
            !line.contains("\t") && line.prefix(while: { $0 == " " }).count >= 2
        }) else {
            throw CaptureLocationMetadataError.frontmatterCollision(location.collectionKey)
        }
        let source = continuation.map { String($0.dropFirst(2)) }.joined(separator: "\n")
        let parsed: CaptureLocationYAMLValue
        do {
            var parser = try CaptureLocationConstrainedYAMLParser(source: source, maximumDepth: 32)
            parsed = try parser.parse()
        } catch {
            throw CaptureLocationMetadataError.frontmatterCollision(location.collectionKey)
        }
        guard case .sequence(let items) = parsed else {
            throw CaptureLocationMetadataError.frontmatterCollision(location.collectionKey)
        }

        var ids = Set<UUID>()
        for item in items {
            guard case .mapping(let pairs) = item,
                  let idPair = pairs.first(where: { $0.key == "id" }),
                  case .string(let rawID) = idPair.value,
                  let id = UUID(uuidString: rawID),
                  ids.insert(id).inserted else {
                throw CaptureLocationMetadataError.frontmatterCollision(location.collectionKey)
            }
        }
        return ids.contains(location.requestID)
    }

    private func appendingLocation(
        _ location: CaptureLocationRenderedMetadata,
        to frontmatter: [String]?
    ) throws -> [String] {
        var lines = frontmatter ?? []
        let item = location.itemLines.enumerated().map { index, line in
            index == 0 ? "  - \(line)" : "    \(line)"
        }
        guard let start = lines.indices.first(where: {
            guard let key = frontmatterEntry(lines[$0])?.key else { return false }
            return unquotedYAMLKey(key) == location.collectionKey
        }) else {
            lines.append("\(location.collectionKey):")
            lines.append(contentsOf: item)
            return lines
        }

        if try validatedLocationCollectionContains(location, in: lines) {
            return lines
        }
        let entry = frontmatterEntry(lines[start])
        if entry?.value == "[]" {
            lines[start] = "\(location.collectionKey):"
        }
        let end = sectionEnd(startingAt: start, in: lines)
        lines.insert(contentsOf: item, at: end)
        return lines
    }

    private func unquotedYAMLKey(_ key: String) -> String {
        guard key.count >= 2 else { return key }
        if (key.hasPrefix("\"") && key.hasSuffix("\""))
            || (key.hasPrefix("'") && key.hasSuffix("'")) {
            return String(key.dropFirst().dropLast())
        }
        return key
    }

    private func structuredFrontmatterLines(_ values: [String: String]) throws -> [String]? {
        guard !values.isEmpty else { return nil }
        return try structuredFrontmatterLines(values.keys.sorted().map {
            MarkdownOrderedFrontmatterField(name: $0, value: values[$0] ?? "")
        })
    }

    private func structuredFrontmatterLines(
        _ values: [MarkdownOrderedFrontmatterField]
    ) throws -> [String]? {
        guard !values.isEmpty else { return nil }
        var names = Set<String>()
        return try values.map { field in
            guard names.insert(field.name).inserted else {
                throw MarkdownDocumentEditorError.duplicateFrontmatterKey
            }
            return "\(yamlKey(field.name)): \(yamlScalar(field.value))"
        }
    }

    private func yamlKey(_ key: String) -> String {
        let isPlain = !key.isEmpty && key.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-"
        }
        return isPlain ? key : yamlScalar(key)
    }

    private func yamlScalar(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
            || (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
            || ["true", "false", "null", "~"].contains(trimmed.lowercased())
            || Double(trimmed) != nil {
            return trimmed
        }
        return "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            + "\""
    }

    private func frontmatterEntry(_ line: String) -> (key: String, value: String)? {
        guard line.first != " ", line.first != "\t", !line.hasPrefix("#"),
              let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return (key, value)
    }

    private func frontmatterValues(in section: [String]) -> [String] {
        guard let first = section.first, let entry = frontmatterEntry(first) else { return [] }
        var rawValues = frontmatterValues(entry.value)
        for continuation in section.dropFirst() {
            let trimmed = continuation.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("-") else { continue }
            rawValues.append(
                String(trimmed.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            )
        }
        return rawValues.filter { !$0.isEmpty }
    }

    private func frontmatterValues(_ raw: String) -> [String] {
        let unwrapped = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return unwrapped
            .split(separator: ",", omittingEmptySubsequences: true)
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
            .filter { !$0.isEmpty }
    }

    private func sectionEnd(startingAt index: Int, in lines: [String]) -> Int {
        var cursor = index + 1
        while cursor < lines.count, frontmatterEntry(lines[cursor]) == nil {
            cursor += 1
        }
        return cursor
    }

    private func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    private func assemble(frontmatter: [String]?, body: String, compactTaskStart: Bool) -> String {
        let trimmedBody = trimBoundaryNewlines(body)
        guard let frontmatter else { return trimmedBody }
        let block = "---\n" + frontmatter.joined(separator: "\n") + "\n---"
        let separator = compactTaskStart && listItemMarker(in: firstLine(of: trimmedBody)) != nil
            ? "\n" : "\n\n"
        return trimmedBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? block
            : block + separator + trimmedBody
    }

    private func joinBlocks(_ blocks: [String]) -> String {
        let nonEmpty = blocks
            .map(trimBoundaryNewlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let first = nonEmpty.first else { return "" }
        var joined = first
        for (before, after) in zip(nonEmpty, nonEmpty.dropFirst()) {
            joined += blockSeparator(between: before, and: after) + after
        }
        return joined
    }

    /// A paragraph separator makes a tight list loose. Only change the
    /// insertion seam; blank lines inside either user-owned block stay intact.
    /// Checkbox and plain list items are both list items: adjacent items with
    /// an identical marker (bullet, indentation, checkbox presence) join with
    /// one newline, and a heading keeps any list item tight beneath it. Mixed
    /// or reordered markers keep paragraph spacing.
    private func blockSeparator(between before: String, and after: String) -> String {
        guard let nextMarker = listItemMarker(in: firstLine(of: after)),
              let previousLine = lastMarkdownLine(in: before) else { return "\n\n" }
        let headingIndent = previousLine.prefix { $0 == " " }.count
        let isHeading = headingIndent <= 3 && previousLine.dropFirst(headingIndent).first == "#"
            && atxHeading(in: previousLine) != nil
        if listItemMarker(in: previousLine) == nextMarker || isHeading {
            return "\n"
        }
        return "\n\n"
    }

    private func addingRetryMarker(_ marker: String, to entry: String) -> String {
        guard !entry.isEmpty else { return marker }
        guard let lastLine = lastMarkdownLine(in: entry), listItemMarker(in: lastLine) != nil else {
            return entry + "\n\n" + marker
        }
        // A standalone HTML block splits a Markdown list even without blank
        // lines. An inline comment keeps the list tight and the exact marker
        // remains detectable by all existing retry readers. Preserve hard breaks.
        let trailingSpaceCount = entry.reversed().prefix { $0 == " " || $0 == "\t" }.count
        return String(entry.dropLast(trailingSpaceCount)) + " " + marker
            + String(entry.suffix(trailingSpaceCount))
    }

    private struct ListItemMarker: Equatable {
        var indentation: Int
        var bullet: Character
        /// Checkbox status is deliberately not part of the identity: unchecked
        /// and checked tasks belong to the same list. A plain bullet is a
        /// different list shape than a checkbox item, so it stays separate.
        var hasCheckbox: Bool
    }

    private func listItemMarker(in line: String) -> ListItemMarker? {
        let indentation = line.prefix { $0 == " " }.count
        guard indentation <= 3 else { return nil } // Four spaces is indented code.
        let unindented = line.dropFirst(indentation)
        guard let bullet = unindented.first, "-*+".contains(bullet) else { return nil }
        let afterBullet = unindented.dropFirst()
        guard afterBullet.first == " " || afterBullet.first == "\t" else { return nil }
        let padding = afterBullet.prefix { $0 == " " || $0 == "\t" }
        var contentColumn = indentation + 1
        for character in padding {
            contentColumn += character == "\t" ? 4 - contentColumn % 4 : 1
        }
        // Five or more columns after a bullet starts an indented code block,
        // not a list item. Tabs advance to Markdown's four-column tab stops.
        guard contentColumn - indentation - 1 <= 4 else { return nil }
        let content = afterBullet.dropFirst(padding.count)
        guard !content.isEmpty else { return nil } // A bare bullet is not a text-bearing item.
        if ["[ ]", "[x]", "[X]"].contains(String(content.prefix(3))) {
            let afterCheckbox = content.dropFirst(3)
            guard afterCheckbox.isEmpty || afterCheckbox.first == " " || afterCheckbox.first == "\t" else {
                // Not a checkbox task (e.g. "- [x](link)"); an ordinary bullet.
                return ListItemMarker(indentation: indentation, bullet: bullet, hasCheckbox: false)
            }
            return ListItemMarker(indentation: indentation, bullet: bullet, hasCheckbox: true)
        }
        return ListItemMarker(indentation: indentation, bullet: bullet, hasCheckbox: false)
    }

    private func firstLine(of markdown: String) -> String {
        String(markdown.prefix { $0 != "\n" })
    }

    /// Be conservative about task-looking examples: never compact a seam in
    /// an open code fence or HTML comment, or attempt to parse raw HTML blocks.
    private func lastMarkdownLine(in markdown: String) -> String? {
        var fence: Fence?
        var inComment = false
        var lastLine: String?
        for line in markdown.components(separatedBy: "\n") {
            if let current = fence {
                if let delimiter = fenceDelimiter(in: line),
                   delimiter.character == current.character, delimiter.count >= current.count,
                   line.trimmingCharacters(in: .whitespaces).dropFirst(delimiter.count)
                    .trimmingCharacters(in: .whitespaces).isEmpty {
                    fence = nil
                }
                lastLine = nil
                continue
            }
            if !inComment, let delimiter = fenceDelimiter(in: line) {
                fence = delimiter
                lastLine = nil
                continue
            }
            if !inComment {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("<"), !trimmed.hasPrefix("<!--") { return nil }
            }
            var cursor = line.startIndex
            while let delimiter = line.range(of: inComment ? "-->" : "<!--", range: cursor..<line.endIndex) {
                inComment.toggle()
                cursor = delimiter.upperBound
            }
            lastLine = inComment ? nil : line
        }
        return lastLine
    }

    private func trimBoundaryNewlines(_ value: String) -> String {
        value.trimmingCharacters(in: .newlines)
    }

    private func normalizeNewlines(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
