import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class LiveNoteSessionTests: XCTestCase {
    private var root: URL!
    private let destinationID = UUID()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("live-note-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Inbox"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeSession(initial: String = "# Note\n") throws -> (LiveNoteSession, URL) {
        let fileURL = root.appendingPathComponent("Inbox/Note.md")
        try initial.write(to: fileURL, atomically: true, encoding: .utf8)
        let binding = LiveNoteBinding(
            destinationID: destinationID,
            relativePath: "Inbox/Note.md",
            savedVersion: VaultNoteVersion(text: initial),
            entryRequestID: nil,
            presetID: nil
        )
        let root = self.root!
        let session = LiveNoteSession(binding: binding, text: initial) { _ in root }
        return (session, fileURL)
    }

    func testEditsAreWrittenToTheBoundFile() async throws {
        let (session, fileURL) = try makeSession()
        session.textDidChange("# Note\nRadiator Tuesday\n")
        XCTAssertEqual(session.status, .saving)
        await session.flush()
        XCTAssertEqual(session.status, .saved)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Note\nRadiator Tuesday\n")
        XCTAssertFalse(session.hasUnsavedChanges)
    }

    func testOnlyTheFileChanged_reloadsQuietly() async throws {
        let (session, fileURL) = try makeSession()
        var applied: String?
        session.applyExternalText = { applied = $0 }
        try "# Note\nfrom Obsidian\n".write(to: fileURL, atomically: true, encoding: .utf8)

        await session.checkDisk()

        XCTAssertEqual(applied, "# Note\nfrom Obsidian\n")
        XCTAssertEqual(session.status, .saved)
        XCTAssertEqual(session.text, "# Note\nfrom Obsidian\n")
    }

    func testBothChanged_pausesAsConflictAndKeepMineOverwrites() async throws {
        let (session, fileURL) = try makeSession()
        try "# Note\ntheirs\n".write(to: fileURL, atomically: true, encoding: .utf8)
        session.textDidChange("# Note\nmine\n")
        await session.flush()
        // The rejected save reconciles asynchronously.
        for _ in 0..<50 where session.status == .saving { try await Task.sleep(for: .milliseconds(20)) }

        guard case .conflict(let disk) = session.status else {
            return XCTFail("expected a conflict, got \(session.status)")
        }
        XCTAssertEqual(disk.text, "# Note\ntheirs\n")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Note\ntheirs\n", "nothing overwritten yet")

        await session.resolveConflict(.keepMine)
        XCTAssertEqual(session.status, .saved)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Note\nmine\n")
    }

    func testSaveACopyLeavesTheOriginalAndRebindsToTheCopy() async throws {
        let (session, fileURL) = try makeSession()
        try "# Note\ntheirs\n".write(to: fileURL, atomically: true, encoding: .utf8)
        session.textDidChange("# Note\nmine\n")
        await session.flush()
        for _ in 0..<50 where session.status == .saving { try await Task.sleep(for: .milliseconds(20)) }

        await session.resolveConflict(.saveCopy)

        XCTAssertEqual(session.binding.relativePath, "Inbox/Note (Vox).md")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Note\ntheirs\n")
        XCTAssertEqual(
            try String(contentsOf: root.appendingPathComponent("Inbox/Note (Vox).md"), encoding: .utf8),
            "# Note\nmine\n"
        )
    }

    func testUnreachableVaultKeepsTextAndReportsIt() async throws {
        let binding = LiveNoteBinding(
            destinationID: destinationID,
            relativePath: "Inbox/Note.md",
            savedVersion: VaultNoteVersion(text: "a"),
            entryRequestID: nil,
            presetID: nil
        )
        let session = LiveNoteSession(binding: binding, text: "a") { _ in nil }
        session.textDidChange("ab")
        await session.flush()
        XCTAssertEqual(session.status, .unreachable)
        XCTAssertEqual(session.text, "ab")
        XCTAssertTrue(session.hasUnsavedChanges)
    }

    func testDeletedFileIsReportedAsMissing() async throws {
        let (session, fileURL) = try makeSession()
        try FileManager.default.removeItem(at: fileURL)
        await session.checkDisk()
        XCTAssertEqual(session.status, .missing)
        await session.recreateMissingFile()
        XCTAssertEqual(session.status, .saved)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "# Note\n")
    }

    func testPreviewLineSkipsFrontmatterAndMarkdownMarks() {
        XCTAssertEqual(
            QuickCaptureViewModel.previewLine(from: "---\ntags: [a]\n---\n\n# Project sync\n- [ ] Review"),
            "Project sync"
        )
        XCTAssertEqual(QuickCaptureViewModel.previewLine(from: "- [ ] Move bookshelf"), "Move bookshelf")
        XCTAssertNil(QuickCaptureViewModel.previewLine(from: "\n\n"))
    }
}

/// The composer's Live Notes wiring: open a vault file, speak into it, cancel.
@MainActor
final class LiveNoteComposerTests: XCTestCase {
    func testSpokenWordsReachTheOpenFileAndLeaveItOnCancel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Daily"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let note = vault.appendingPathComponent("Daily/2026-11-13.md")
        try "## Log\n".write(to: note, atomically: true, encoding: .utf8)
        let destination = CaptureDestination(
            name: "Daily", rootBookmark: try vault.bookmarkData(), rootName: "Vault",
            noteTarget: .rollingNote(pathTemplate: "Daily/{date}.md", period: .daily)
        )
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let suite = "LiveNoteQA." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline())
        model.liveNotesEnabled = true
        await model.load()

        await model.openLiveNote(binding: LiveNoteBinding(
            destinationID: destination.id,
            relativePath: "Daily/2026-11-13.md",
            savedVersion: VaultNoteVersion(sha256: ""),
            entryRequestID: nil,
            presetID: nil
        ))
        XCTAssertNotNil(model.liveNote)
        XCTAssertEqual(model.draft.text, "## Log\n")
        XCTAssertEqual(model.liveNoteRecordingLine?.isLive, true)

        model.beginRecordedTranscriptInsertion(atUTF16Offset: nil)
        await model.updateLiveRecordedTranscript(finalizedText: "Radiator visit Tuesday", volatileText: nil)
        await model.liveNote?.flush()
        let whileTalking = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(whileTalking.contains("Radiator visit Tuesday"), "words are written while talking: \(whileTalking)")

        await model.cancelLiveRecordedTranscript()
        await model.liveNote?.flush()
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "## Log\n", "a cancelled recording leaves the file as it was")

        await model.startNewNote()
        XCTAssertNil(model.liveNote)
        XCTAssertEqual(model.lastClosedNote?.binding.relativePath, "Daily/2026-11-13.md")
        XCTAssertEqual(model.liveNoteRecordingLine?.isLive, false)
    }
}

/// "JUST ADDED": the card wraps exactly the new entry inside the whole file.
@MainActor
final class LiveNoteEntryHighlightTests: XCTestCase {
    private func makeTextView(_ text: String, entry: String?) -> MarkdownComposerUITextView {
        let textView = MarkdownComposerUITextView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        textView.font = MarkdownComposerStyler.baseFont
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 20, bottom: 24, right: 20)
        textView.text = text
        textView.highlightedEntry = entry
        textView.restyleMarkdown()
        textView.setNeedsLayout()
        textView.layoutIfNeeded()
        return textView
    }

    private func caretRect(_ textView: UITextView, _ offset: Int) -> CGRect {
        let position = textView.position(from: textView.beginningOfDocument, offset: offset)!
        return textView.caretRect(for: position)
    }

    func testCardWrapsTheNewEntryAndNotTheRestOfTheFile() throws {
        let file = "## Notes\n\n- 09:12 Standup moved\n\n### 14:55 · Project sync\n- [ ] Review final designs\n\nAfter"
        let entry = "### 14:55 · Project sync\n- [ ] Review final designs"
        let textView = makeTextView(file, entry: entry)

        let range = try XCTUnwrap(textView.entryHighlightRange)
        XCTAssertEqual((file as NSString).substring(with: range), entry)
        let card = try XCTUnwrap(textView.entryHighlightFrame)
        let entryTop = caretRect(textView, range.location)
        let entryEnd = caretRect(textView, NSMaxRange(range))
        let before = caretRect(textView, (file as NSString).range(of: "Standup").location)
        let after = caretRect(textView, (file as NSString).range(of: "After").location)

        XCTAssertLessThan(card.minY, entryTop.minY, "label room above the entry")
        XCTAssertGreaterThanOrEqual(card.maxY, entryEnd.maxY, "covers the last entry line")
        XCTAssertGreaterThan(card.minY, before.maxY, "starts below earlier log lines")
        XCTAssertLessThanOrEqual(card.maxY, after.minY, "ends above later text")
    }

    func testNoCardWithoutAnEntryOrWhenTheEntryWasEditedAway() {
        XCTAssertNil(makeTextView("# Note\n", entry: nil).entryHighlightFrame)
        XCTAssertNil(makeTextView("# Note\nsomething else\n", entry: "- 14:05 gone").entryHighlightFrame)
    }
}

/// Attaching while a note is open puts the file in the vault and an embed in the note.
@MainActor
final class LiveNoteAttachmentTests: XCTestCase {
    func testAttachingIntoAnOpenNoteCopiesToAttachmentsAndEmbeds() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault.appendingPathComponent("Inbox"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let note = vault.appendingPathComponent("Inbox/Note.md")
        try "# Note\n".write(to: note, atomically: true, encoding: .utf8)
        let destination = CaptureDestination(
            name: "Inbox", rootBookmark: try vault.bookmarkData(), rootName: "Vault",
            noteTarget: .newNote(pathTemplate: "Inbox/{title}.md")
        )
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let suite = "LiveNoteAttach." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline())
        model.liveNotesEnabled = true
        await model.load()
        await model.openLiveNote(binding: LiveNoteBinding(
            destinationID: destination.id, relativePath: "Inbox/Note.md",
            savedVersion: VaultNoteVersion(sha256: ""), entryRequestID: nil, presetID: nil
        ))
        XCTAssertNotNil(model.liveNote)

        let photo = root.appendingPathComponent("whiteboard.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: photo)
        _ = await model.stageFile(at: photo, contentTypeIdentifier: "public.png", embedAsImage: true, describeImageImmediately: false)
        _ = await model.stageFile(at: photo, contentTypeIdentifier: "public.png", embedAsImage: true, describeImageImmediately: false)
        await model.liveNote?.flush()

        XCTAssertTrue(model.draft.additionalPayloads.isEmpty, "nothing left waiting for a send")
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("attachments/whiteboard.png").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: vault.appendingPathComponent("attachments/whiteboard 2.png").path), "never overwrites")
        let saved = try String(contentsOf: note, encoding: .utf8)
        XCTAssertTrue(saved.contains("![[whiteboard.png]]"), saved)
        XCTAssertTrue(saved.contains("![[whiteboard 2.png]]"), saved)
    }
}
