import AppIntents
import UniformTypeIdentifiers
import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CaptureIntentTargetTests: XCTestCase {
    func testHTTPShortcutRejectsInactiveDirectoryAndLegacyOverride() async throws {
        let fixture = try await makeFixture(http: true)
        for override in [nil, CaptureDestinationEntity(destination: fixture.destination)] {
            do {
                try await CaptureIntentSupport.enqueue(payloads: [.text("Synthetic shortcut text")],
                    presetEntity: CaptureVoxEntity(profile: fixture.preset.captureProfile), legacyDestinationEntity: override,
                    captureRootURL: fixture.root, defaults: fixture.defaults)
                XCTFail("An HTTP-only preset must not enter the Directory inbox")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("HTTP"))
            }
        }
        let items = try await CaptureInbox(rootDirectoryURL: fixture.root).requestIDs(in: .pending)
        XCTAssertTrue(items.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.vault.path).isEmpty)
    }

    func testShortcutWithoutExplicitPresetRejectsSelectedHTTPTarget() async throws {
        let fixture = try await makeFixture(http: true)
        XCTAssertTrue(CapturePresetProfileStore.selectCaptureProfile(id: fixture.preset.id, defaults: fixture.defaults))
        let link = try XCTUnwrap(URL(string: "https://example.invalid/link"))
        do {
            try await CaptureIntentSupport.enqueue(payloads: [.url(link, title: nil)],
                presetEntity: nil, captureRootURL: fixture.root, defaults: fixture.defaults)
            XCTFail("The selected HTTP preset must not fall back to a default directory")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("HTTP"))
        }
        let items = try await CaptureInbox(rootDirectoryURL: fixture.root).requestIDs(in: .pending)
        XCTAssertTrue(items.isEmpty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.vault.path).isEmpty)
    }

    func testHTTPFileShortcutRejectsBeforeStagingFiles() async throws {
        let fixture = try await makeFixture(http: true)
        let file = IntentFile(data: Data("Synthetic attachment".utf8), filename: "synthetic.txt", type: .plainText)
        do {
            try await CaptureIntentSupport.enqueue(file: file, presetEntity: CaptureVoxEntity(profile: fixture.preset.captureProfile),
                captureRootURL: fixture.root, defaults: fixture.defaults)
            XCTFail("HTTP file shortcuts must fail closed")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("HTTP"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("inbox-staging").path))
        let items = try await CaptureInbox(rootDirectoryURL: fixture.root).requestIDs(in: .pending)
        XCTAssertTrue(items.isEmpty)
    }

    func testHTTPShortcutExplainsBoundaryWithoutDirectorySetup() async throws {
        let fixture = try await makeFixture(http: true)
        do {
            try await CaptureIntentSupport.enqueue(payloads: [.text("Synthetic HTTP text")],
                presetEntity: CaptureVoxEntity(profile: fixture.preset.captureProfile), captureRootURL: nil, defaults: fixture.defaults)
            XCTFail("HTTP shortcuts must explain the supported Capture path")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("HTTP"))
        }
    }

    func testDirectoryShortcutStillEnqueuesAndDeliversItsNote() async throws {
        let fixture = try await makeFixture(http: false)
        try await CaptureIntentSupport.enqueue(payloads: [.text("Synthetic Directory text")],
            presetEntity: CaptureVoxEntity(profile: fixture.preset.captureProfile), captureRootURL: fixture.root, defaults: fixture.defaults)
        let result = await CaptureInboxDeliveryService.drain(captureRootURL: fixture.root, defaults: fixture.defaults, pipeline: CapturePipeline())
        XCTAssertNil(result.setupError)
        XCTAssertEqual(result.receipts.count, 1)
        XCTAssertTrue(try String(contentsOf: fixture.vault.appendingPathComponent("Inbox.md"), encoding: .utf8).contains("Synthetic Directory text"))
    }

    private struct Fixture {
        let root: URL
        let vault: URL
        let defaults: UserDefaults
        let preset: CapturePreset
        let destination: CaptureDestination
    }

    private func makeFixture(http: Bool) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CaptureIntentTarget-\(UUID())")
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        let suite = "CaptureIntentTarget-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let destination = CaptureDestination(name: "Synthetic", rootBookmark: try vault.bookmarkData(), rootName: "Synthetic",
            noteTarget: .existingNote(relativePath: "Inbox.md"), retryProtectionEnabled: true)
        var preset = CapturePresetStore.makeCustomFlow()
        preset.captureDestinationID = destination.id
        preset.exportSettings.urlDelivery = .init(enabled: http, urlString: "https://example.invalid/shortcut")
        CapturePresetStore.saveFlows([preset], defaults: defaults, widgetRefresh: .disabled)
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destination.id))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        return Fixture(root: root, vault: vault, defaults: defaults, preset: preset, destination: destination)
    }
}
