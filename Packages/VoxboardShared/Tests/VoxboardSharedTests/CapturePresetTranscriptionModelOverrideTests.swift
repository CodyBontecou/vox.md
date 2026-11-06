import XCTest
@testable import VoxboardShared

final class CapturePresetTranscriptionModelOverrideTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        CapturePresetTestLock.install()
    }

    func test_legacyPayloadDecodesWithoutOverrideAndOmitsKey() throws {
        let data = Data(#"{"id":"journal","name":"Journal","symbolName":"book"}"#.utf8)
        let preset = try JSONDecoder().decode(CapturePreset.self, from: data)
        XCTAssertNil(preset.transcriptionModelID)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as? [String: Any]
        XCTAssertNil(object?["transcriptionModelID"])
    }

    func test_overrideRoundTripsAndResolves() throws {
        let suite = "CapturePresetTranscriptionModelOverrideTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Not "meeting": loadFlows strips that retired built-in ID.
        var preset = CapturePreset(id: "meeting-notes", name: "Meeting", symbolName: "person.2")
        preset.transcriptionModelID = TranscriptionBackendID.automatic
        let decoded = try JSONDecoder().decode(CapturePreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(decoded.transcriptionModelID, TranscriptionBackendID.automatic)

        defaults.set("some-global-model", forKey: AppConstants.selectedModelKey)
        CapturePresetStore.saveFlows([preset, CapturePreset(id: "plain", name: "Plain", symbolName: "doc")], defaults: defaults)
        XCTAssertEqual(
            CapturePresetStore.resolvedTranscriptionModelID(flowID: "meeting-notes", defaults: defaults),
            TranscriptionBackendID.automatic
        )
        XCTAssertEqual(
            CapturePresetStore.resolvedTranscriptionModelID(flowID: "plain", defaults: defaults),
            "some-global-model"
        )

        // An override naming a model that is not installed falls back to the global choice.
        var missing = preset
        missing.transcriptionModelID = "not-a-real-model"
        CapturePresetStore.saveFlows([missing], defaults: defaults)
        XCTAssertEqual(
            CapturePresetStore.resolvedTranscriptionModelID(flowID: "meeting-notes", defaults: defaults),
            "some-global-model"
        )
    }
}
