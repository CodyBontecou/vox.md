import XCTest
@testable import Voxboard

final class MarkdownRichBlocksTests: XCTestCase {
    func testFrontmatterBecomesProperties() throws {
        let note = "---\ntitle: \"Embeds demo\"\ntags: [meeting, design]\nstatus: draft\npeople:\n  - Sam\n  - 'Priya'\n---\n\n# Body"
        let frontmatter = try XCTUnwrap(MarkdownRichBlocks.frontmatter(in: note as NSString))
        XCTAssertEqual(frontmatter.properties, [
            .init(key: "title", values: ["Embeds demo"]),
            .init(key: "tags", values: ["meeting", "design"]),
            .init(key: "status", values: ["draft"]),
            .init(key: "people", values: ["Sam", "Priya"]),
        ])
        XCTAssertEqual((note as NSString).substring(with: frontmatter.range).hasSuffix("---"), true)
        XCTAssertEqual((note as NSString).substring(with: frontmatter.closingLineRange), "---")
    }

    func testNoFrontmatterWithoutAClosingFenceOrNotAtTheTop() {
        XCTAssertNil(MarkdownRichBlocks.frontmatter(in: "---\ntitle: open" as NSString))
        XCTAssertNil(MarkdownRichBlocks.frontmatter(in: "# Title\n---\na: b\n---" as NSString))
    }

    func testEmbedLinesAreDetectedAndClassified() {
        let note = """
        Intro ![[inline.wav]] stays text
        ![[standup-clip.wav]]
          ![[whiteboard.png|300]]
        ![photo](attachments/My%20Photo.jpg)
        ![[demo.mp4]]
        ![[notes.md]]
        """
        let embeds = MarkdownRichBlocks.embeds(in: note as NSString)
        XCTAssertEqual(embeds.map(\.target), ["standup-clip.wav", "whiteboard.png", "attachments/My Photo.jpg", "demo.mp4"])
        XCTAssertEqual(embeds.map(\.kind), [.audio, .image, .image, .video])
        XCTAssertEqual((note as NSString).substring(with: embeds[0].range), "![[standup-clip.wav]]")
    }

    func testABlockShowsItsSourceOnlyWhileTheCaretIsInside() {
        let block = NSRange(location: 10, length: 20)
        XCTAssertTrue(MarkdownRichBlocks.isRevealed(block, by: NSRange(location: 15, length: 0)))
        XCTAssertTrue(MarkdownRichBlocks.isRevealed(block, by: NSRange(location: 30, length: 0)), "caret at line end")
        XCTAssertFalse(MarkdownRichBlocks.isRevealed(block, by: NSRange(location: 31, length: 0)))
        XCTAssertFalse(MarkdownRichBlocks.isRevealed(block, by: NSRange(location: 0, length: 5)))
        XCTAssertTrue(MarkdownRichBlocks.isRevealed(block, by: NSRange(location: 0, length: 12)))
    }

    func testEmbedsResolveLikeObsidian() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("attachments"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Inbox"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Deep/Media"), withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("attachments/clip.wav"))
        try Data([1]).write(to: root.appendingPathComponent("Inbox/clip.wav"))
        try Data([1]).write(to: root.appendingPathComponent("Inbox/local.png"))
        try Data([1]).write(to: root.appendingPathComponent("Deep/Media/far.mp4"))

        func resolve(_ target: String) -> String? {
            QuickCaptureViewModel.resolveEmbed(target, noteRelativePath: "Inbox/Note.md", rootURL: root, attachmentsFolder: "attachments")?
                .path.replacingOccurrences(of: root.path + "/", with: "")
        }
        XCTAssertEqual(resolve("clip.wav"), "attachments/clip.wav", "the attachments folder wins")
        XCTAssertEqual(resolve("local.png"), "Inbox/local.png", "then the note's folder")
        XCTAssertEqual(resolve("far.mp4"), "Deep/Media/far.mp4", "then anywhere in the vault by name")
        XCTAssertNil(resolve("missing.wav"))
        XCTAssertNil(resolve("../outside.wav"))
    }
}
