import XCTest
@testable import VoxboardCaptureCore

final class MarkdownTaskSpacingTests: XCTestCase {
    private let requestID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!

    func test_prependAndAppendJoinAdjacentTasksWithOneNewline() throws {
        XCTAssertEqual(
            try edit("- [ ] Older task", entry: "- [ ] New task", placement: .prepend),
            "- [ ] New task\n- [ ] Older task"
        )
        XCTAssertEqual(
            try edit("- [ ] Older task", entry: "- [ ] New task", placement: .append),
            "- [ ] Older task\n- [ ] New task"
        )
    }

    func test_repeatedPrependsDoNotAddBlankLinesOrChangeTaskOrder() throws {
        var document = ""
        for task in ["First", "Second", "Third"] {
            document = try edit(document, entry: "- [ ] \(task)", placement: .prepend)
        }
        XCTAssertEqual(document, "- [ ] Third\n- [ ] Second\n- [ ] First")
    }

    func test_prefixAndSuffixTasksUseTheSameSpacingWithoutReformattingContent() throws {
        let result = try edit(
            "- [x] Older task",
            entry: "Buy milk",
            placement: .prepend,
            prefix: "- [ ] ",
            suffix: " #inbox"
        )
        XCTAssertEqual(result, "- [ ] Buy milk #inbox\n- [x] Older task")
    }

    func test_checkedTasksAndMatchingBulletStylesStayCompact() throws {
        for indentation in ["", " ", "  ", "   "] {
            for bullet in ["-", "*", "+"] {
                for status in [" ", "x", "X"] {
                    let old = "\(indentation)\(bullet) [\(status)] Old"
                    let new = "\(indentation)\(bullet) [ ] New"
                    XCTAssertEqual(try edit(old, entry: new, placement: .prepend), new + "\n" + old)
                }
            }
        }
    }

    func test_taskWhitespaceAndEmptyCheckboxesAreRecognized() throws {
        for task in ["- [ ]", "- [X]", "-  [ ] Two spaces", "-    [ ] Four spaces", "-\t[ ] Tab"] {
            XCTAssertEqual(
                try edit(task, entry: "- [ ] New", placement: .prepend),
                "- [ ] New\n" + task
            )
        }
    }

    func test_multilineTasksAndUserAuthoredInternalBlankLinesArePreserved() throws {
        let entry = "- [ ] First\n- [ ] Second\n\n- [ ] Third"
        let document = "- [ ] Older\n\n- [ ] Oldest"
        XCTAssertEqual(
            try edit(document, entry: entry, placement: .prepend),
            entry + "\n" + document
        )
    }

    func test_boundaryNewlinesNormalizeButHardBreakSpacesArePreserved() throws {
        XCTAssertEqual(
            try edit("\r\n- [ ] Older\r\n", entry: "\r\n- [ ] New  \r\n\r\n", placement: .prepend),
            "- [ ] New  \n- [ ] Older"
        )
    }

    func test_taskInsertionBeneathHeadingHasNoAutomaticBlankLines() throws {
        let result = try edit(
            "# Inbox\n\n## Tasks\n\n- [ ] Older\n\n## Notes\n\nKeep this paragraph.",
            entry: "- [ ] New",
            placement: .beneathHeading(.init(title: "Tasks", level: 2), missingHeadingBehavior: .fail)
        )
        XCTAssertEqual(
            result,
            "# Inbox\n\n## Tasks\n- [ ] New\n- [ ] Older\n\n## Notes\n\nKeep this paragraph."
        )
    }

    func test_createdHeadingHasNoAutomaticBlankLineBeforeItsFirstTask() throws {
        XCTAssertEqual(
            try edit(
                "Intro.",
                entry: "- [ ] New",
                placement: .beneathHeading(.init(title: "Tasks", level: 2), missingHeadingBehavior: .create)
            ),
            "Intro.\n\n## Tasks\n- [ ] New"
        )
    }

    func test_prependedTaskFollowsFrontmatterWithoutAnAutomaticBlankLine() throws {
        let result = try edit(
            "---\ntitle: Tasks\n---\n\n- [ ] Older",
            entry: "- [ ] New",
            placement: .prepend
        )
        XCTAssertEqual(result, "---\ntitle: Tasks\n---\n- [ ] New\n- [ ] Older")
        XCTAssertEqual(
            try edit(result, entry: "- [ ] Last", placement: .append),
            result + "\n- [ ] Last",
            "Later appends must not reintroduce a blank line after the frontmatter."
        )
    }

    func test_firstTaskInFrontmatterOnlyNoteIsCompact() throws {
        XCTAssertEqual(
            try edit("---\ntitle: Tasks\n---", entry: "- [ ] New", placement: .append),
            "---\ntitle: Tasks\n---\n- [ ] New"
        )
    }

    func test_appendingDoesNotRewriteExistingFrontmatterSpacing() throws {
        let document = "---\ntitle: Tasks\n---\n\n- [ ] Older"
        XCTAssertEqual(
            try edit(document, entry: "- [ ] New", placement: .append),
            document + "\n- [ ] New"
        )
    }

    func test_emptyPrependDoesNotRemoveExistingFrontmatterSpacing() throws {
        let document = "---\ntitle: Tasks\n---\n\n- [ ] Older"
        XCTAssertEqual(try edit(document, entry: "", placement: .prepend), document)
    }

    func test_taskSpacingHonorsTheFinalNewlineWritePolicy() throws {
        for finalNewline in [false, true] {
            let result = try MarkdownDocumentEditor().applying(
                .init(
                    requestID: requestID,
                    entry: "- [ ] New\n\n",
                    placement: .prepend,
                    finalNewline: finalNewline
                ),
                to: "- [ ] Older\n"
            )
            XCTAssertEqual(result, "- [ ] New\n- [ ] Older" + (finalNewline ? "\n" : ""))
        }
    }

    func test_paragraphAndOtherMarkdownBoundariesKeepTheirBlankLines() throws {
        for document in [
            "Paragraph.", "- Ordinary bullet", "1. Ordered item", "> - [ ] Quoted task",
            "    - [ ] Code", "    # Indented code", "\t# Indented code",
            "-     [ ] List code", "-\t\t[ ] List code", "- [x](link)",
            "* [ ] Different list", "  - [ ] Nested task",
        ] {
            XCTAssertEqual(
                try edit(document, entry: "- [ ] New", placement: .prepend),
                "- [ ] New\n\n" + document,
                document
            )
            XCTAssertEqual(
                try edit(document, entry: "- [ ] New", placement: .append),
                document + "\n\n- [ ] New",
                document
            )
        }
        XCTAssertEqual(try edit("# Heading", entry: "Prose.", placement: .append), "# Heading\n\nProse.")
        XCTAssertEqual(try edit("Paragraph.", entry: "More prose.", placement: .prepend), "More prose.\n\nParagraph.")
    }

    func test_taskLikeLinesInsideUnclosedCodeFencesOrCommentsAreNotListBoundaries() throws {
        for document in [
            "```markdown\n- [ ] Example", "~~~\n- [ ] Example", "<!--\n- [ ] Example",
            "<div>\n- [ ] Example", "<!-- closed --> <!-- open\n- [ ] Example",
        ] {
            XCTAssertEqual(
                try edit(document, entry: "- [ ] New", placement: .append),
                document + "\n\n- [ ] New"
            )
        }
        let closedFence = "```markdown\n- [ ] Example\n```\n\n- [ ] Older"
        XCTAssertEqual(try edit(closedFence, entry: "- [ ] New", placement: .append), closedFence + "\n- [ ] New")
    }

    func test_retryMarkerStaysInlineAndDoesNotSplitTheTaskList() throws {
        let marker = CaptureRequestMarker.text(for: requestID)
        for placement in [CapturePlacement.prepend, .append] {
            let result = try edit("- [ ] Older", entry: "- [ ] New", placement: placement, retryProtection: true)
            let expected = placement == .prepend
                ? "- [ ] New \(marker)\n- [ ] Older"
                : "- [ ] Older\n- [ ] New \(marker)"
            XCTAssertEqual(result, expected)
            XCTAssertEqual(
                try edit(result, entry: "- [ ] New", placement: placement, retryProtection: true),
                result,
                "The unchanged marker syntax must still prevent duplicate writes."
            )
        }
    }

    func test_repeatedProtectedTasksStayCompact() throws {
        let firstID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let firstMarker = CaptureRequestMarker.text(for: firstID)
        let secondMarker = CaptureRequestMarker.text(for: requestID)
        let document = try MarkdownDocumentEditor().applying(
            .init(requestID: firstID, entry: "- [ ] First", placement: .prepend, retryProtectionEnabled: true),
            to: ""
        )
        XCTAssertEqual(
            try edit(document, entry: "- [ ] Second", placement: .prepend, retryProtection: true),
            "- [ ] Second \(secondMarker)\n- [ ] First \(firstMarker)"
        )
        XCTAssertEqual(
            try edit(document, entry: "- [ ] Second", placement: .append, retryProtection: true),
            "- [ ] First \(firstMarker)\n- [ ] Second \(secondMarker)"
        )
    }

    func test_inlineMarkerPreservesTaskHardBreakSpaces() throws {
        XCTAssertEqual(
            try edit("", entry: "- [ ] Task  ", placement: .prepend, retryProtection: true),
            "- [ ] Task \(CaptureRequestMarker.text(for: requestID))  "
        )
    }

    func test_legacyStandaloneMarkersRemainDetectableAndUserOwned() throws {
        let legacy = "- [ ] Already saved\n\n\(CaptureRequestMarker.text(for: requestID))"
        XCTAssertEqual(
            try edit(legacy, entry: "- [ ] Already saved", placement: .prepend, retryProtection: true),
            legacy
        )
        let otherID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let result = try MarkdownDocumentEditor().applying(
            .init(requestID: otherID, entry: "- [ ] New", placement: .prepend, retryProtectionEnabled: true),
            to: legacy
        )
        XCTAssertEqual(result, "- [ ] New \(CaptureRequestMarker.text(for: otherID))\n" + legacy)
    }

    func test_taskLikeCodeDoesNotReceiveAnInlineRetryMarker() throws {
        for entry in [
            "    - [ ] Code", "\t- [ ] Code", "-     [ ] List code", "-\t\t[ ] List code",
            "```markdown\n- [ ] Example", "<!--\n- [ ] Example", "<div>\n- [ ] Example",
        ] {
            XCTAssertEqual(
                try edit("", entry: entry, placement: .prepend, retryProtection: true),
                entry + "\n\n" + CaptureRequestMarker.text(for: requestID)
            )
        }
    }

    func test_retryProtectionForNonTasksRetainsEstablishedBlockSpacing() throws {
        let marker = CaptureRequestMarker.text(for: requestID)
        XCTAssertEqual(
            try edit("Existing.", entry: "New.", placement: .prepend, retryProtection: true),
            "New.\n\n\(marker)\n\nExisting."
        )
        XCTAssertEqual(try edit("", entry: "", placement: .prepend, retryProtection: true), marker)
    }

    private func edit(
        _ document: String,
        entry: String,
        placement: CapturePlacement,
        prefix: String = "",
        suffix: String = "",
        retryProtection: Bool = false
    ) throws -> String {
        try MarkdownDocumentEditor().applying(
            .init(
                requestID: requestID,
                entry: entry,
                placement: placement,
                entryPrefix: prefix,
                entrySuffix: suffix,
                retryProtectionEnabled: retryProtection
            ),
            to: document
        )
    }
}
