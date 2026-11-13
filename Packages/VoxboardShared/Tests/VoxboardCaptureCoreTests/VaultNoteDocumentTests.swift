import XCTest
@testable import VoxboardCaptureCore

final class VaultNoteDocumentTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("vault-note-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_replace_createsMissingNoteWhenExpectingNil() throws {
        let document = try VaultNoteDocument(rootURL: root, relativePath: "Inbox/Radiator.md")
        XCTAssertNil(try document.read())
        let version = try document.replace(with: "# Radiator", expecting: nil)
        let snapshot = try XCTUnwrap(document.read())
        XCTAssertEqual(snapshot.text, "# Radiator")
        XCTAssertEqual(snapshot.version, version)
        XCTAssertEqual(version, VaultNoteVersion(text: "# Radiator"))
    }

    func test_replace_overwritesWhenVersionMatches() throws {
        let document = try VaultNoteDocument(rootURL: root, relativePath: "Note.md")
        let first = try document.replace(with: "one", expecting: nil)
        let second = try document.replace(with: "one two", expecting: first)
        XCTAssertEqual(try document.read()?.text, "one two")
        XCTAssertEqual(try document.read()?.version, second)
    }

    func test_replace_refusesWhenAnotherAppChangedTheFile() throws {
        let document = try VaultNoteDocument(rootURL: root, relativePath: "Note.md")
        let saved = try document.replace(with: "mine", expecting: nil)
        try "theirs".write(to: document.fileURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try document.replace(with: "mine, edited", expecting: saved)) { error in
            guard case VaultNoteDocumentError.changedOnDisk(let current?) = error else {
                return XCTFail("expected changedOnDisk with the disk text, got \(error)")
            }
            XCTAssertEqual(current.text, "theirs")
        }
        XCTAssertEqual(try document.read()?.text, "theirs", "nothing is written on a mismatch")
    }

    func test_replace_refusesToCreateOverAnExistingFile() throws {
        let document = try VaultNoteDocument(rootURL: root, relativePath: "Note.md")
        try "already here".write(to: document.fileURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try document.replace(with: "new", expecting: nil))
    }

    func test_replace_reportsDeletedFile() throws {
        let document = try VaultNoteDocument(rootURL: root, relativePath: "Note.md")
        let saved = try document.replace(with: "text", expecting: nil)
        try FileManager.default.removeItem(at: document.fileURL)
        XCTAssertThrowsError(try document.replace(with: "text 2", expecting: saved)) { error in
            XCTAssertEqual(error as? VaultNoteDocumentError, .changedOnDisk(current: nil))
        }
    }

    func test_writeCopy_picksAnUnusedVoxName() throws {
        let document = try VaultNoteDocument(rootURL: root, relativePath: "Inbox/Book ideas.md")
        try document.replace(with: "original", expecting: nil)
        XCTAssertEqual(try document.writeCopy("mine"), "Inbox/Book ideas (Vox).md")
        XCTAssertEqual(try document.writeCopy("mine again"), "Inbox/Book ideas (Vox 2).md")
        let copy = try VaultNoteDocument(rootURL: root, relativePath: "Inbox/Book ideas (Vox).md")
        XCTAssertEqual(try copy.read()?.text, "mine")
    }

    func test_init_rejectsNonMarkdownAndEscapingPaths() {
        XCTAssertThrowsError(try VaultNoteDocument(rootURL: root, relativePath: "photo.jpg"))
        XCTAssertThrowsError(try VaultNoteDocument(rootURL: root, relativePath: "../outside.md"))
        XCTAssertThrowsError(try VaultNoteDocument(rootURL: root, relativePath: "/abs.md"))
    }

    // MARK: Reconciliation

    func test_reconcile_allBranches() {
        let saved = VaultNoteVersion(text: "base")
        let same = VaultNoteSnapshot(text: "base", version: saved)
        let theirs = VaultNoteSnapshot(text: "theirs", version: VaultNoteVersion(text: "theirs"))

        XCTAssertEqual(VaultNoteReconciliation.decide(lastSaved: saved, editorText: "base", disk: same), .inSync)
        XCTAssertEqual(VaultNoteReconciliation.decide(lastSaved: saved, editorText: "mine", disk: same), .save)
        XCTAssertEqual(VaultNoteReconciliation.decide(lastSaved: saved, editorText: "base", disk: theirs), .reload(theirs))
        XCTAssertEqual(VaultNoteReconciliation.decide(lastSaved: saved, editorText: "mine", disk: theirs), .conflict(theirs))
        XCTAssertEqual(VaultNoteReconciliation.decide(lastSaved: saved, editorText: "theirs", disk: theirs), .inSync)
        XCTAssertEqual(VaultNoteReconciliation.decide(lastSaved: saved, editorText: "mine", disk: nil), .missing)
    }

    // MARK: File index

    func test_index_listsFoldersFirstThenNotesNewestFirst_skippingHiddenAndNonMarkdown() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Daily"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try "a".write(to: root.appendingPathComponent("Daily/2026-11-12.md"), atomically: true, encoding: .utf8)
        try "b".write(to: root.appendingPathComponent("Daily/2026-11-13.md"), atomically: true, encoding: .utf8)
        try "old".write(to: root.appendingPathComponent("Old.md"), atomically: true, encoding: .utf8)
        try "new".write(to: root.appendingPathComponent("New.md"), atomically: true, encoding: .utf8)
        try "img".write(to: root.appendingPathComponent("photo.png"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000)], ofItemAtPath: root.appendingPathComponent("Old.md").path)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 2_000)], ofItemAtPath: root.appendingPathComponent("New.md").path)

        let entries = try VaultFileIndex.children(of: "", rootURL: root)
        XCTAssertEqual(entries.map(\.name), ["Daily", "New.md", "Old.md"])
        XCTAssertEqual(entries.first?.childCount, 2)
        XCTAssertEqual(try VaultFileIndex.children(of: "Daily", rootURL: root).map(\.relativePath).sorted(),
                       ["Daily/2026-11-12.md", "Daily/2026-11-13.md"])
    }

    func test_folderForTarget_usesStaticDirectoryPrefix() {
        XCTAssertEqual(VaultFileIndex.folder(for: .newNote(pathTemplate: "Inbox/{title}.md")), "Inbox")
        XCTAssertEqual(VaultFileIndex.folder(for: .rollingNote(pathTemplate: "Journal/Daily/{date}.md", period: .daily)), "Journal/Daily")
        XCTAssertEqual(VaultFileIndex.folder(for: .newNote(pathTemplate: "{date}.md")), "")
        XCTAssertEqual(VaultFileIndex.folder(for: .newNote(pathTemplate: "Log/{year}/{date}.md")), "Log")
        XCTAssertEqual(VaultFileIndex.folder(for: .existingNote(relativePath: "Tasks.md")), "")
        XCTAssertEqual(VaultFileIndex.fixedNote(for: .existingNote(relativePath: "Tasks.md")), "Tasks.md")
    }
}
