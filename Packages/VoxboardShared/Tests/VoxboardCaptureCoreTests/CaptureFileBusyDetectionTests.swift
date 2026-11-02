import XCTest
@testable import VoxboardCaptureCore

final class CaptureFileBusyDetectionTests: XCTestCase {
    func test_detector_reportsVimSwapFileAsUnsavedChanges() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Tasks.md")
        try "# Tasks".write(to: note, atomically: true, encoding: .utf8)
        XCTAssertNil(CaptureFileBusyDetector.busyReason(for: note))

        try "swap".write(to: folder.appendingPathComponent(".Tasks.md.swp"), atomically: true, encoding: .utf8)
        XCTAssertEqual(CaptureFileBusyDetector.busyReason(for: note), .unsavedChanges)
    }

    func test_detector_reportsDanglingEmacsLockAsUnsavedChanges() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Tasks.md")
        try "# Tasks".write(to: note, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            atPath: folder.appendingPathComponent(".#Tasks.md").path,
            withDestinationPath: "user@host.1234"
        )
        XCTAssertEqual(CaptureFileBusyDetector.busyReason(for: note), .unsavedChanges)
    }

    func test_detector_reportsExclusiveFlockAsLocked() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Tasks.md")
        try "# Tasks".write(to: note, atomically: true, encoding: .utf8)
        let descriptor = open(note.path, O_RDONLY)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        XCTAssertEqual(flock(descriptor, LOCK_EX | LOCK_NB), 0)
        XCTAssertEqual(CaptureFileBusyDetector.busyReason(for: note), .locked)
        flock(descriptor, LOCK_UN)
        XCTAssertNil(CaptureFileBusyDetector.busyReason(for: note))
    }

    func test_missingNoteIsNeverBusy() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        XCTAssertNil(CaptureFileBusyDetector.busyReason(for: folder.appendingPathComponent("New.md")))
    }

    func test_writer_waitsInsteadOfOverwritingBusyNote() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Tasks.md")
        try "# Tasks".write(to: note, atomically: true, encoding: .utf8)
        try "swap".write(to: folder.appendingPathComponent(".Tasks.md.swp"), atomically: true, encoding: .utf8)
        let monitor = CaptureFileBusyMonitor()
        monitor.isDetectionEnabled = true
        let writer = CoordinatedCaptureWriter(
            coordinator: ProcessLocalCaptureFileCoordinator.shared,
            busyMonitor: monitor
        )
        let requestID = UUID()

        do {
            _ = try await writer.write(mutation(requestID, entry: "- [ ] Buy milk"), to: note)
            XCTFail("Expected a busy-file error")
        } catch let error as CaptureFileBusyError {
            XCTAssertEqual(error.reason, .unsavedChanges)
            XCTAssertEqual(error.fileName, "Tasks.md")
        }
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "# Tasks")
        XCTAssertEqual(monitor.entry(for: requestID)?.markdown, "- [ ] Buy milk")

        try FileManager.default.removeItem(at: folder.appendingPathComponent(".Tasks.md.swp"))
        _ = try await writer.write(mutation(requestID, entry: "- [ ] Buy milk"), to: note)
        XCTAssertTrue(try String(contentsOf: note, encoding: .utf8).contains("Buy milk"))
        XCTAssertNil(monitor.entry(for: requestID))
    }

    func test_writer_writesNewNoteWhenPolicyAsks() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Tasks.md")
        try "# Tasks".write(to: note, atomically: true, encoding: .utf8)
        try "swap".write(to: folder.appendingPathComponent(".Tasks.md.swp"), atomically: true, encoding: .utf8)
        let monitor = CaptureFileBusyMonitor()
        monitor.isDetectionEnabled = true
        monitor.policy = .writeNewNote
        let writer = CoordinatedCaptureWriter(
            coordinator: ProcessLocalCaptureFileCoordinator.shared,
            busyMonitor: monitor
        )

        let receipt = try await writer.write(mutation(UUID(), entry: "Captured"), to: note)

        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "# Tasks")
        XCTAssertNotEqual(receipt.fileURL, note)
        XCTAssertTrue(receipt.fileURL.lastPathComponent.hasPrefix("Tasks (Vox.md "))
        XCTAssertTrue(try String(contentsOf: receipt.fileURL, encoding: .utf8).contains("Captured"))
    }

    func test_requestedNewNoteBypassesWaitPolicy() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let note = folder.appendingPathComponent("Tasks.md")
        try "# Tasks".write(to: note, atomically: true, encoding: .utf8)
        let monitor = CaptureFileBusyMonitor()
        monitor.isDetectionEnabled = true
        let requestID = UUID()
        monitor.requestNewNote(for: requestID)
        let writer = CoordinatedCaptureWriter(
            coordinator: ProcessLocalCaptureFileCoordinator.shared,
            busyMonitor: monitor
        )

        let receipt = try await writer.write(mutation(requestID, entry: "Captured"), to: note)

        XCTAssertNotEqual(receipt.fileURL, note)
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "# Tasks")
    }

    func test_pipelineReceiptNamesSiblingNoteWhenWritingNewNote() async throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Lists", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let note = folder.appendingPathComponent("Tasks.md")
        try "# Tasks".write(to: note, atomically: true, encoding: .utf8)
        let monitor = CaptureFileBusyMonitor()
        monitor.isDetectionEnabled = true
        let writer = CoordinatedCaptureWriter(
            coordinator: ProcessLocalCaptureFileCoordinator.shared,
            busyMonitor: monitor
        )
        let destination = CaptureDestination(
            name: "Tasks",
            rootBookmark: Data([1]),
            rootName: "Vault",
            noteTarget: .existingNote(relativePath: "Lists/Tasks.md"),
            placement: .append
        )
        let request = CaptureRequest(source: .app, destinationID: destination.id, payloads: [.text("Captured")])
        monitor.requestNewNote(for: request.id)

        let receipt = try await CapturePipeline(writer: writer).capture(
            request,
            destination: destination,
            rootURL: root
        )

        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "# Tasks")
        XCTAssertEqual(receipt.noteURL.lastPathComponent, receipt.writeReceipt.fileURL.lastPathComponent)
        let relative = try XCTUnwrap(CaptureHistoryRecord.relativeNotePath(noteURL: receipt.noteURL, rootURL: root))
        XCTAssertTrue(relative.hasPrefix("Lists/Tasks (Vox.md "), relative)
        XCTAssertTrue(try String(contentsOf: receipt.noteURL, encoding: .utf8).contains("Captured"))
    }

    func test_previewEntryMarkdownRendersWithoutWriting() throws {
        let root = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        var destination = CaptureDestination(
            name: "Inbox",
            rootBookmark: Data([1]),
            rootName: "Vault",
            noteTarget: .existingNote(relativePath: "Inbox.md"),
            placement: .append
        )
        destination.entryPrefix = "### {source}\n"
        let request = CaptureRequest(source: .app, destinationID: destination.id, payloads: [.text("Buy milk")])

        let markdown = try CapturePipeline().previewEntryMarkdown(for: request, destination: destination)

        XCTAssertTrue(markdown.contains("Buy milk"), markdown)
        XCTAssertTrue(markdown.hasPrefix("### "), markdown)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("Inbox.md").path))
    }

    func test_newNoteRelativePath_keepsFolderAndAvoidsCollisions() {
        let date = Date(timeIntervalSince1970: 0)
        var taken: Set<String> = []
        let first = CaptureFileBusyDetector.newNoteRelativePath(for: "Lists/Tasks.md", at: date) { taken.contains($0) }
        taken.insert(first)
        let second = CaptureFileBusyDetector.newNoteRelativePath(for: "Lists/Tasks.md", at: date) { taken.contains($0) }
        XCTAssertTrue(first.hasPrefix("Lists/Tasks (Vox.md "))
        XCTAssertTrue(first.hasSuffix(").md"))
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(second.hasSuffix(" 2.md"))
    }

    private func mutation(_ requestID: UUID, entry: String) -> MarkdownCaptureMutation {
        MarkdownCaptureMutation(requestID: requestID, entry: entry, placement: .append)
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
