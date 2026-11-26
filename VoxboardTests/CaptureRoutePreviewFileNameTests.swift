import XCTest
@testable import Voxboard
import VoxboardShared

/// Issue #116: the composer's route label names the exact file a capture will
/// be written to, including the `-N` suffix delivery adds for same-day notes.
@MainActor
final class CaptureRoutePreviewFileNameTests: XCTestCase {
    func test_previewNamesNextSuffixedFileAndDeliveryWritesThatFile() async throws {
        let fixture = try await makeFixture()
        let today = dateName(fixture.model.draft.effectiveCreatedAt)
        let first = fixture.vault.appendingPathComponent("\(today).md")
        try "first capture".write(to: first, atomically: true, encoding: .utf8)
        try "second capture".write(
            to: fixture.vault.appendingPathComponent("\(today)-2.md"), atomically: true, encoding: .utf8
        )

        fixture.model.draft.text = "Third capture"
        let preview = try XCTUnwrap(fixture.model.resolvedDestinationPreview)
        XCTAssertEqual(preview, "Synthetic Vault / \(today)-3.md")

        await fixture.model.submit()

        let receipt = try XCTUnwrap(fixture.model.lastReceipt, fixture.model.errorMessage ?? "Send did not deliver")
        XCTAssertEqual(receipt.noteURL.lastPathComponent, "\(today)-3.md")
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "first capture")
    }

    func test_previewUsesBaseNameWhenNoCaptureExistsToday() async throws {
        let fixture = try await makeFixture()
        let today = dateName(fixture.model.draft.effectiveCreatedAt)
        fixture.model.draft.text = "Only capture"

        XCTAssertEqual(fixture.model.resolvedDestinationPreview, "Synthetic Vault / \(today).md")
    }

    private struct Fixture {
        let model: QuickCaptureViewModel
        let vault: URL
    }

    private func dateName(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
    }

    private func makeFixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoutePreviewFileName-\(UUID().uuidString)")
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let destination = CaptureDestination(
            name: "Synthetic", rootBookmark: try vault.bookmarkData(), rootName: "Synthetic Vault",
            noteTarget: .newNote(pathTemplate: "{date}.md")
        )
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        let suite = "RoutePreviewFileName-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        var preset = CapturePresetStore.makeCustomFlow()
        preset.name = "Synthetic Notes"
        preset.captureDestinationID = destination.id
        preset.postProcessingMode = .none
        CapturePresetStore.saveFlows([preset], defaults: defaults, widgetRefresh: .disabled)
        let model = QuickCaptureViewModel(
            captureRootURL: root, defaults: defaults, pipeline: CapturePipeline(),
            hasPaidCaptureAccess: { true }
        )
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        await model.load()
        model.draft.voxID = preset.id
        return Fixture(model: model, vault: vault)
    }
}
