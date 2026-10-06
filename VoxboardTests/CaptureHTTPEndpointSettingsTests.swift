import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CaptureHTTPEndpointSettingsTests: XCTestCase {
    func testEditorLoadsRequestedHTTPPresetWithoutChangingSelection() throws {
        let (defaults, preset, other) = try fixture()
        CapturePresetProfileStore.selectCaptureProfile(id: other.id, defaults: defaults)
        let model = CaptureHTTPEndpointSettingsModel(presetID: preset.id, defaults: defaults, widgetRefresh: .disabled)
        XCTAssertEqual(model.preset?.id, preset.id)
        XCTAssertEqual(model.settings.urlString, preset.exportSettings.urlDelivery.urlString)
        XCTAssertEqual(CapturePresetProfileStore.selectedProfileID(defaults: defaults), other.id)
    }

    func testEditorMergesIntoLatestPresetAndPreservesOtherSettingsAndCredentials() throws {
        let (defaults, preset, other) = try fixture()
        let model = CaptureHTTPEndpointSettingsModel(presetID: preset.id, defaults: defaults, widgetRefresh: .disabled)
        var latest = preset
        latest.name = "Renamed while editor is open"
        latest.exportSettings.folderName = "remembered-directory"
        CapturePresetStore.saveFlows([latest, other], defaults: defaults, widgetRefresh: .disabled)
        var settings = model.settings
        settings.urlString = "https://example.invalid/edited"
        model.settings = settings
        let saved = try XCTUnwrap(CapturePresetStore.flow(id: preset.id, defaults: defaults))
        XCTAssertEqual(saved.name, latest.name)
        XCTAssertEqual(saved.exportSettings.folderName, "remembered-directory")
        XCTAssertEqual(saved.exportSettings.urlDelivery.urlString, settings.urlString)
        XCTAssertEqual(saved.exportSettings.urlDelivery.credentialID, preset.exportSettings.urlDelivery.credentialID)
        XCTAssertEqual(saved.exportSettings.urlDelivery.credentialURLString, preset.exportSettings.urlDelivery.credentialURLString)
        XCTAssertTrue(saved.exportSettings.urlDelivery.hasBearerToken)
        XCTAssertTrue(saved.exportSettings.urlDelivery.hasCustomHeaders)
        XCTAssertEqual(CapturePresetStore.flow(id: other.id, defaults: defaults), other)
    }

    func testDeletedPresetIsNotResurrectedByOpenEditor() throws {
        let (defaults, preset, other) = try fixture()
        let model = CaptureHTTPEndpointSettingsModel(presetID: preset.id, defaults: defaults, widgetRefresh: .disabled)
        CapturePresetStore.saveFlows([other], defaults: defaults, widgetRefresh: .disabled)
        var settings = model.settings
        settings.urlString = "https://example.invalid/do-not-save"
        model.settings = settings
        XCTAssertNil(model.preset)
        XCTAssertNil(CapturePresetStore.flow(id: preset.id, defaults: defaults))
        XCTAssertEqual(CapturePresetStore.flow(id: other.id, defaults: defaults), other)
    }

    func testDirectorySwitchIsNotOverwrittenByOpenEditor() throws {
        let (defaults, preset, other) = try fixture()
        let model = CaptureHTTPEndpointSettingsModel(presetID: preset.id, defaults: defaults, widgetRefresh: .disabled)
        var directory = preset
        directory.deliveryTarget = .directory
        CapturePresetStore.saveFlows([directory, other], defaults: defaults, widgetRefresh: .disabled)
        model.settings = model.settings
        XCTAssertNil(model.preset)
        XCTAssertEqual(CapturePresetStore.flow(id: preset.id, defaults: defaults), directory)
        let directoryEditor = CaptureHTTPEndpointSettingsModel(presetID: preset.id, defaults: defaults, widgetRefresh: .disabled)
        XCTAssertNil(directoryEditor.preset)
    }

    private func fixture() throws -> (UserDefaults, CapturePreset, CapturePreset) {
        let suite = "CaptureHTTPEndpointSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        var preset = try XCTUnwrap(CapturePresetStore.loadFlows(defaults: defaults).first)
        preset.id = "synthetic-http"
        preset.isBuiltIn = false
        preset.name = "Synthetic HTTP"
        preset.deliveryTarget = .http
        preset.exportSettings.urlDelivery.urlString = "https://example.invalid/original"
        preset.exportSettings.urlDelivery.credentialID = "opaque-synthetic-account"
        preset.exportSettings.urlDelivery.credentialURLString = preset.exportSettings.urlDelivery.urlString
        preset.exportSettings.urlDelivery.hasBearerToken = true
        preset.exportSettings.urlDelivery.hasCustomHeaders = true
        var other = preset
        other.id = "synthetic-other"
        other.name = "Other preset"
        other.deliveryTarget = .directory
        CapturePresetStore.saveFlows([preset, other], defaults: defaults, widgetRefresh: .disabled)
        return (defaults, preset, other)
    }
}
