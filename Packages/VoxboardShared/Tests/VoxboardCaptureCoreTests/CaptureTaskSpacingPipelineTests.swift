import XCTest
@testable import VoxboardCaptureCore

final class CaptureTaskSpacingPipelineTests: XCTestCase {
    func test_taskPresetsWriteCompactListsWithProcessingOnOrOffAndRetryProtection() async throws {
        for processingEnabled in [false, true] {
            for retryProtection in [false, true] {
                for placement in [CapturePlacement.prepend, .append] {
                    let root = FileManager.default.temporaryDirectory
                        .appendingPathComponent("capture-task-spacing.\(UUID().uuidString)", isDirectory: true)
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: root) }
                    let note = root.appendingPathComponent("Tasks.md")
                    let header = "---\ntitle: Tasks\n---"
                    try header.write(to: note, atomically: true, encoding: .utf8)
                    let destination = CaptureDestination(
                        name: "Tasks",
                        rootBookmark: Data(),
                        rootName: "Test vault",
                        noteTarget: .existingNote(relativePath: "Tasks.md"),
                        placement: placement,
                        // With processing off, deterministic entry formatting
                        // owns the checkbox; no AI opt-out semantics change.
                        entryPrefix: processingEnabled ? "" : "- [ ] ",
                        retryProtectionEnabled: retryProtection
                    )
                    let profile = CapturePresetProfile(
                        id: "tasks",
                        name: "Tasks",
                        symbolName: "checklist",
                        postProcessingMode: .todoList,
                        captureProcessingEnabled: processingEnabled,
                        captureDestinationID: destination.id
                    )
                    let pipeline = CapturePipeline()
                    var expectedEntries: [String] = []
                    for text in ["Buy milk", "Call Sam", "Post letter"] {
                        let request = try CaptureDraft(text: text, voxID: profile.id).makeRequest(
                            source: .app,
                            resolvedDestinationID: destination.id,
                            voxProfile: profile
                        )
                        // Exercise the real deterministic fallback, not a live
                        // model: spacing must not depend on model availability.
                        let processed = await CapturePresetRequestProcessor().process(request)
                        XCTAssertEqual(processed.payloads, [.text(processingEnabled ? "- [ ] " + text : text)])
                        let receipt = try await pipeline.capture(processed, destination: destination, rootURL: root)
                        XCTAssertFalse(receipt.writeReceipt.wasAlreadyApplied)
                        let marker = retryProtection ? " " + CaptureRequestMarker.text(for: request.id) : ""
                        let entry = "- [ ] " + text + marker
                        if placement == .prepend {
                            expectedEntries.insert(entry, at: 0)
                        } else {
                            expectedEntries.append(entry)
                        }
                        let expected = header + "\n" + expectedEntries.joined(separator: "\n")
                        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), expected)
                        if retryProtection {
                            let retry = try await pipeline.capture(processed, destination: destination, rootURL: root)
                            XCTAssertTrue(retry.writeReceipt.wasAlreadyApplied)
                            XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), expected)
                        }
                    }
                }
            }
        }
    }

    func test_disablingProcessingStillPreservesRawTextWithoutAnEntryPrefix() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-task-spacing.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let note = root.appendingPathComponent("Tasks.md")
        try "- [ ] Older".write(to: note, atomically: true, encoding: .utf8)
        let destination = CaptureDestination(
            name: "Tasks",
            rootBookmark: Data(),
            rootName: "Test vault",
            noteTarget: .existingNote(relativePath: "Tasks.md"),
            placement: .prepend
        )
        let profile = CapturePresetProfile(
            id: "tasks",
            name: "Tasks",
            symbolName: "checklist",
            postProcessingMode: .todoList,
            captureProcessingEnabled: false
        )
        let request = try CaptureDraft(text: "buy milk").makeRequest(
            source: .app,
            resolvedDestinationID: destination.id,
            voxProfile: profile
        )
        let processed = await CapturePresetRequestProcessor().process(request)
        _ = try await CapturePipeline().capture(processed, destination: destination, rootURL: root)

        XCTAssertEqual(processed.payloads, [.text("buy milk")])
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "buy milk\n\n- [ ] Older")
    }
}
