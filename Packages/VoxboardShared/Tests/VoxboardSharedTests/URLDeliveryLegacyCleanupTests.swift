import Foundation
import Security
import XCTest
@testable import VoxboardShared

final class URLDeliveryLegacyCleanupTests: XCTestCase {
    func testReadingLegacyQueuedPresetScrubsHeadersWithoutChangingJobOrUnknownFields() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let items = root.appendingPathComponent("items")
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        var preset = CapturePreset(id: "legacy", name: "Synthetic", symbolName: "mic")
        preset.exportSettings.urlDelivery = .init(enabled: true, urlString: "https://example.invalid/ingest")
        let job = RecordingJob(audioFilename: "legacy.wav", duration: 1, source: .importedAudio,
            delivery: .preset(preset), modelID: "automatic", language: "auto",
            retentionPolicy: .permanent, processingPolicy: .manual)
        let url = items.appendingPathComponent(job.id.uuidString.lowercased()).appendingPathExtension("json")
        try legacyArchive(job).write(to: url)
        let loaded = try await RecordingJobStore(rootDirectoryURL: root).job(id: job.id)
        XCTAssertEqual(loaded?.id, job.id)
        XCTAssertEqual(loaded?.phase, job.phase)
        guard case .preset(let migrated)? = loaded?.delivery else { return XCTFail("Missing preset") }
        XCTAssertTrue(migrated.exportSettings.urlDelivery.requiresCredentialMigration)
        try assertScrubbed(url)
        let first = try Data(contentsOf: url)
        _ = try await RecordingJobStore(rootDirectoryURL: root).job(id: job.id)
        XCTAssertEqual(try Data(contentsOf: url), first, "A second read must not rewrite the archive")
    }

    func testReadingLegacyHandoffScrubsHeadersAndKeepsRecoveryIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let preset = CapturePreset(id: "legacy", name: "Synthetic", symbolName: "mic")
        let intent = RecordingJobHandoffIntent(audioFilename: "legacy.wav", duration: 1,
            source: .importedAudio, delivery: .preset(preset), modelID: "automatic", language: "auto", configuration: .default)
        let store = RecordingJobHandoffIntentStore(recordingsDirectoryURL: root)
        try store.save(intent)
        let url = RecordingJobHandoffIntentStore.url(for: intent.jobID, in: RecordingJobHandoffIntentStore.directoryURL(in: root))
        try legacyArchive(intent).write(to: url)
        let loaded = try XCTUnwrap(store.load(jobID: intent.jobID))
        XCTAssertEqual(loaded.jobID, intent.jobID)
        XCTAssertEqual(loaded.audioFilename, intent.audioFilename)
        XCTAssertEqual(loaded.readiness, intent.readiness)
        try assertScrubbed(url)
    }

    func testLegacyRemovalDeletesOnlyItsReferencedHostWithoutReadingToken() throws {
        var deleted: [String] = []
        let store = keychain { deleted.append($0); return errSecSuccess }
        let settings = CapturePresetURLDeliverySettings(urlString: "https://example.invalid/legacy", hasBearerToken: true,
            requiresCredentialMigration: true)
        try store.delete(settings: settings)
        XCTAssertEqual(deleted, ["example.invalid"])
        XCTAssertTrue(settings.hasBearerToken, "Caller must clear flags only after successful removal")
    }

    func testModernRemovalNeverDeletesSharedHostAccount() throws {
        var deleted: [String] = []
        let store = keychain { deleted.append($0); return errSecItemNotFound }
        let id = UUID().uuidString
        let settings = CapturePresetURLDeliverySettings(urlString: "https://example.invalid/ingest", hasBearerToken: true,
            credentialID: id, credentialURLString: "https://example.invalid/ingest")
        try store.delete(settings: settings)
        XCTAssertEqual(deleted, [id])
    }

    func testDeniedLegacyRemovalThrowsWithoutClearingMigrationFlags() {
        let store = keychain { _ in errSecInteractionNotAllowed }
        let settings = CapturePresetURLDeliverySettings(urlString: "https://example.invalid/legacy", hasBearerToken: true,
            requiresCredentialMigration: true)
        XCTAssertThrowsError(try store.delete(settings: settings)) {
            XCTAssertEqual($0 as? URLDeliveryKeychain.StorageError, .unavailable(errSecInteractionNotAllowed))
        }
        XCTAssertTrue(settings.requiresCredentialMigration)
        XCTAssertTrue(settings.hasBearerToken)
    }

    func testLegacyUUIDHostCannotDeleteAnOpaqueModernAccount() {
        var deleted: [String] = []
        let store = keychain { deleted.append($0); return errSecSuccess }
        let settings = CapturePresetURLDeliverySettings(urlString: "https://\(UUID().uuidString)/legacy", hasBearerToken: true,
            requiresCredentialMigration: true)
        XCTAssertThrowsError(try store.delete(settings: settings))
        XCTAssertTrue(deleted.isEmpty)
    }

    func testFutureQueueSchemaIsPreservedWithoutRedaction() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let items = root.appendingPathComponent("items")
        try FileManager.default.createDirectory(at: items, withIntermediateDirectories: true)
        let job = RecordingJob(audioFilename: "future.wav", duration: 1, source: .importedAudio,
            delivery: .preset(CapturePreset(id: "legacy", name: "Synthetic", symbolName: "mic")),
            modelID: "automatic", language: "auto", retentionPolicy: .permanent, processingPolicy: .manual)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: legacyArchive(job)) as? [String: Any])
        object["schemaVersion"] = RecordingJob.currentSchemaVersion + 1
        let data = try JSONSerialization.data(withJSONObject: object)
        let url = items.appendingPathComponent(job.id.uuidString.lowercased()).appendingPathExtension("json")
        try data.write(to: url)
        do {
            _ = try await RecordingJobStore(rootDirectoryURL: root).job(id: job.id)
            XCTFail("Future schema must not be admitted")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    private func keychain(delete: @escaping (String) -> OSStatus) -> URLDeliveryKeychain.Store {
        .init(client: .init(load: { _ in XCTFail("Cleanup must not read a legacy token"); return (errSecAuthFailed, nil) },
            update: { _, _ in XCTFail("Unexpected update"); return errSecAuthFailed },
            add: { _, _ in XCTFail("Unexpected add"); return errSecAuthFailed }, delete: delete))
    }

    private func legacyArchive<T: Encodable>(_ value: T) throws -> Data {
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        var delivery = try XCTUnwrap(object["delivery"] as? [String: Any])
        var associated = try XCTUnwrap(delivery["preset"] as? [String: Any])
        var preset = try XCTUnwrap(associated["_0"] as? [String: Any])
        var export = try XCTUnwrap(preset["exportSettings"] as? [String: Any])
        var settings = try XCTUnwrap(export["urlDelivery"] as? [String: Any])
        settings["customHeaders"] = ["X-API-Key": "synthetic-legacy-secret"]
        settings.removeValue(forKey: "hasCustomHeaders")
        export["urlDelivery"] = settings
        preset["exportSettings"] = export
        associated["_0"] = preset
        delivery["preset"] = associated
        object["delivery"] = delivery
        object["unknownMetadata"] = ["keep": "unchanged"]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func assertScrubbed(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("synthetic-legacy-secret"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((object["unknownMetadata"] as? [String: String])?["keep"], "unchanged")
    }
}
