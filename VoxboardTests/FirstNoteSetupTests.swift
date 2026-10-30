import Foundation
import Testing
import VoxboardShared
@testable import Voxboard

@MainActor
struct FirstNoteSetupTests {
    @Test func choosingFolderPreservesDraftAndOnlySendWritesTheNote() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("My Notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "FirstNoteSetup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        // Isolated, unmetered writer tests routing. HardPaywallStoreKitTests
        // separately verifies that real paid-access guards stay locked.
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline())
        await model.load()
        model.draft.text = "My first saved thought"
        let draft = model.draft
        #expect(!model.canSubmit)
        try await model.setUpFirstNoteFolder(folder)
        #expect(model.draft == draft)
        #expect(model.canSubmit)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        let destination = try #require(model.selectedDestination)
        #expect(destination.rootName == "My Notes")
        #expect(destination.noteTarget == .newNote(pathTemplate: "{date}.md"))
        await model.submit()
        let receipt = try #require(model.lastReceipt)
        #expect(receipt.noteURL.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(try String(contentsOf: receipt.noteURL, encoding: .utf8).contains("My first saved thought"))
        #expect(model.historyRecords.contains { $0.outcome == .delivered && $0.requestID == receipt.requestID })
        #expect(model.draft.text.isEmpty)
    }

    @Test func repeatedFolderSelectionKeepsAnExistingRouteAndDraft() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = root.appendingPathComponent("My Notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "FirstNoteSetup-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = QuickCaptureViewModel(captureRootURL: root, defaults: defaults, pipeline: CapturePipeline())
        await model.load()
        try await model.setUpFirstNoteFolder(folder)
        let destination = model.selectedDestination
        model.draft.text = "Keep this draft"
        let draft = model.draft
        try await model.setUpFirstNoteFolder(root)
        #expect(model.selectedDestination == destination)
        #expect(model.draft == draft)
    }
}
