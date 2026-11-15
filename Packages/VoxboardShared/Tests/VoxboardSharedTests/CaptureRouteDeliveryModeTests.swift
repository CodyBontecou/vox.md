import XCTest
@testable import VoxboardShared

/// Synthetic inputs only.
final class CaptureRouteDeliveryModeTests: XCTestCase {
    private let endpoint = "https://example.invalid/api/vox?mode=memory"

    func testSettingsWithoutRemoteOnlyFieldDecodeAsTodaysBehaviour() throws {
        let enabled = try JSONDecoder().decode(
            CapturePresetURLDeliverySettings.self,
            from: Data(#"{"enabled":true,"urlString":"https://example.invalid/ingest"}"#.utf8)
        )
        XCTAssertFalse(enabled.remoteOnly)
        XCTAssertFalse(enabled.isRemoteOnly)
        XCTAssertEqual(enabled.deliveryMode, .localAndRemote)

        let disabled = try JSONDecoder().decode(CapturePresetURLDeliverySettings.self, from: Data("{}".utf8))
        XCTAssertEqual(disabled.deliveryMode, .localOnly)
    }

    func testRouteWithoutDeliveryModeDecodesUnchanged() throws {
        var preset = CapturePresetStore.makeCustomFlow()
        preset.exportSettings.urlDelivery = .init(enabled: true, urlString: endpoint)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(preset)) as? [String: Any]
        )
        var export = try XCTUnwrap(object["exportSettings"] as? [String: Any])
        var urlDelivery = try XCTUnwrap(export["urlDelivery"] as? [String: Any])
        urlDelivery.removeValue(forKey: "remoteOnly")
        export["urlDelivery"] = urlDelivery
        object["exportSettings"] = export
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(CapturePreset.self, from: legacy)

        XCTAssertEqual(decoded, preset)
        XCTAssertEqual(decoded.exportSettings.urlDelivery.deliveryMode, .localAndRemote)
    }

    func testRemoteOnlyRoundTrips() throws {
        var settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint)
        try settings.setDeliveryMode(.remoteOnly)
        let decoded = try JSONDecoder().decode(
            CapturePresetURLDeliverySettings.self, from: JSONEncoder().encode(settings)
        )
        XCTAssertEqual(decoded.deliveryMode, .remoteOnly)
        XCTAssertTrue(decoded.isRemoteOnly)
        XCTAssertEqual(decoded.endpointHost, "example.invalid")
    }

    func testRemoteOnlyIsRejectedWhileURLDeliveryIsOff() {
        var settings = CapturePresetURLDeliverySettings(enabled: false, urlString: endpoint)
        XCTAssertFalse(settings.canSelectRemoteOnly)
        XCTAssertThrowsError(try settings.setDeliveryMode(.remoteOnly)) { error in
            XCTAssertEqual(error as? CaptureRouteDeliveryModeError, .remoteOnlyRequiresEndpoint)
        }
        XCTAssertEqual(settings.deliveryMode, .localOnly)
        XCTAssertFalse(settings.remoteOnly)
    }

    func testRemoteOnlyIsRejectedWithoutASavedEndpoint() {
        var settings = CapturePresetURLDeliverySettings(enabled: true, urlString: "")
        XCTAssertThrowsError(try settings.setDeliveryMode(.remoteOnly))
        XCTAssertEqual(settings.deliveryMode, .localAndRemote)

        // A stored flag without a valid endpoint never skips the vault.
        settings.remoteOnly = true
        XCTAssertFalse(settings.isRemoteOnly)
        settings.urlString = "http://example.invalid/insecure"
        XCTAssertFalse(settings.isRemoteOnly)
    }

    func testModeTransitions() throws {
        var settings = CapturePresetURLDeliverySettings(enabled: true, urlString: endpoint)
        try settings.setDeliveryMode(.remoteOnly)
        XCTAssertEqual(settings.deliveryMode, .remoteOnly)
        try settings.setDeliveryMode(.localAndRemote)
        XCTAssertEqual(settings.deliveryMode, .localAndRemote)
        XCTAssertFalse(settings.remoteOnly)
        try settings.setDeliveryMode(.localOnly)
        XCTAssertEqual(settings.deliveryMode, .localOnly)
        XCTAssertFalse(settings.enabled)
        try settings.setDeliveryMode(.localAndRemote)
        XCTAssertTrue(settings.enabled)
    }
}
