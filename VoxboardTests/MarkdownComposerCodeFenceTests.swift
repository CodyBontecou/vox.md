import UIKit
import XCTest
@testable import Voxboard

@MainActor
final class MarkdownComposerCodeFenceTests: XCTestCase {
    private func blocks(_ text: String) -> [String] {
        let string = text as NSString
        return MarkdownComposerStyler.fencedCodeBlocks(in: string).map { string.substring(with: $0) }
    }

    func testClosedFenceIsOneBlockIncludingFences() {
        XCTAssertEqual(
            blocks("Intro\n```bash\n# install deps\n- [ ] not a task\n```\nAfter"),
            ["```bash\n# install deps\n- [ ] not a task\n```\n"]
        )
    }

    func testUnclosedFenceRunsToTheEnd() {
        XCTAssertEqual(blocks("Before\n~~~\ncode\nmore"), ["~~~\ncode\nmore"])
    }

    func testFenceClosesOnlyOnMatchingRunWithoutInfoString() {
        XCTAssertEqual(blocks("````\n```\n~~~\n```` \nafter"), ["````\n```\n~~~\n```` \n"])
    }

    func testInlineTripleBacktickSpanIsNotAFence() {
        XCTAssertEqual(blocks("```inline``` text\n- [ ] real task"), [])
    }

    func testTasksInsideCodeAreNotCheckboxesButTasksOutsideAre() {
        let storage = NSTextStorage(string: "- [ ] real task\n```\n- [ ] in code\n```\n- [x] done")
        let markers = MarkdownComposerStyler.apply(to: storage)
        let string = storage.string as NSString

        XCTAssertEqual(markers.count, 2)
        XCTAssertEqual(markers.map { string.substring(with: $0.range) }, ["- [ ]", "- [x]"])
        XCTAssertEqual(markers.map(\.isChecked), [false, true])
    }

    func testHeadingInsideCodeKeepsTheCodeFont() {
        let storage = NSTextStorage(string: "```\n# comment\n```\n# Heading")
        MarkdownComposerStyler.apply(to: storage)
        let string = storage.string as NSString
        let commentFont = storage.attribute(.font, at: string.range(of: "comment").location, effectiveRange: nil) as? UIFont
        let headingFont = storage.attribute(.font, at: string.range(of: "Heading").location, effectiveRange: nil) as? UIFont

        XCTAssertEqual(commentFont?.fontName.contains("Mono"), true)
        XCTAssertNotEqual(commentFont?.pointSize, headingFont?.pointSize)
    }
}

final class CaptureRoutePillNameTests: XCTestCase {
    func testShortNamesAreUnchanged() {
        XCTAssertEqual(CaptureRoutePillsRow.pillName("Inbox"), "Inbox")
        XCTAssertEqual(CaptureRoutePillsRow.pillName(String(repeating: "a", count: 24)), String(repeating: "a", count: 24))
    }

    func testLongNamesAreShortenedOnGraphemeBoundaries() {
        let name = String(repeating: "👩‍👩‍👧", count: 40)
        let shortened = CaptureRoutePillsRow.pillName(name)

        XCTAssertEqual(shortened.count, 24)
        XCTAssertTrue(shortened.hasSuffix("…"))
        XCTAssertTrue(shortened.hasPrefix("👩‍👩‍👧"))
    }
}
