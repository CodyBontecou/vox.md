import XCTest
@testable import VoxboardShared

@MainActor
final class CapturePresetWidgetStoreRefreshTests: XCTestCase {
    func testPreferencesSuccessfulSeedPinOrderEmptyNoopAndRefusal() throws {
        try withDefaults { defaults in
            let counter = WidgetStoreRefreshCounter()
            let refresh = CapturePresetWidgetRefresh { counter.count += 1 }
            let profiles = [profile("a"), profile("b", enabled: false), profile("c")]
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults, authoritativeProfiles: nil, widgetRefresh: refresh)
            XCTAssertEqual(counter.count, 0)
            preferences.reload(authoritativeProfiles: profiles)
            XCTAssertEqual(counter.count, 1)
            preferences.reload(authoritativeProfiles: Array(profiles.reversed()))
            XCTAssertEqual(counter.count, 1, "Read/reload without seeding isn't a write")
            XCTAssertTrue(preferences.setOrderedIDs(["c", "b", "a"], authoritativeProfiles: profiles))
            XCTAssertEqual(counter.count, 2)
            XCTAssertTrue(preferences.setOrderedIDs(["c", "b", "a", "c"], authoritativeProfiles: profiles))
            XCTAssertEqual(counter.count, 2, "Normalized noop cannot reload")
            XCTAssertFalse(preferences.setOrderedIDs([], authoritativeProfiles: nil))
            XCTAssertEqual(counter.count, 2)
            XCTAssertTrue(preferences.setOrderedIDs([], authoritativeProfiles: profiles))
            XCTAssertEqual(counter.count, 3)
            preferences.reload(authoritativeProfiles: profiles)
            XCTAssertEqual(counter.count, 3)
        }
    }

    func testFailedPreferenceReadbackAndUnavailableDefaultsDoNotReload() throws {
        let counter = WidgetStoreRefreshCounter()
        let refresh = CapturePresetWidgetRefresh { counter.count += 1 }
        let suite = "capture-widget-dropping.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(WidgetDroppingDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let profiles = [profile("a")]
        let preferences = CapturePresetQuickAccessPreferences(defaults: defaults, authoritativeProfiles: profiles, widgetRefresh: refresh)
        XCTAssertEqual(preferences.state, .absent)
        XCTAssertFalse(preferences.setOrderedIDs(["a"], authoritativeProfiles: profiles))
        let unavailable = CapturePresetQuickAccessPreferences(defaults: nil, authoritativeProfiles: profiles, widgetRefresh: refresh)
        XCTAssertFalse(unavailable.setOrderedIDs(["a"], authoritativeProfiles: profiles))
        XCTAssertEqual(counter.count, 0)
    }

    func testRealPresetSaveBoundaryTracksIdentityAvailabilityAndOrderOnly() throws {
        try withDefaults { defaults in
            let counter = WidgetStoreRefreshCounter()
            let refresh = CapturePresetWidgetRefresh { counter.count += 1 }
            let a = CapturePreset(id: "a", name: "A", symbolName: "waveform")
            let b = CapturePreset(id: "b", name: "B", symbolName: "book")
            CapturePresetStore.saveFlows([a, b], defaults: defaults, widgetRefresh: refresh)
            XCTAssertEqual(counter.count, 1)
            CapturePresetStore.saveFlows([a, b], defaults: defaults, widgetRefresh: refresh)
            XCTAssertEqual(counter.count, 1)
            var changed = a
            changed.capturePrompt = "Prompt-only"
            CapturePresetStore.saveFlows([changed, b], defaults: defaults, widgetRefresh: refresh)
            XCTAssertEqual(counter.count, 1)
            changed.emoji = "👨🏽‍💻"
            CapturePresetStore.saveFlows([changed, b], defaults: defaults, widgetRefresh: refresh)
            XCTAssertEqual(counter.count, 2)
            changed.name = "Renamed"
            CapturePresetStore.saveFlows([changed, b], defaults: defaults, widgetRefresh: refresh)
            XCTAssertEqual(counter.count, 3)
            changed.isEnabled = false
            CapturePresetStore.saveFlows([b, changed], defaults: defaults, widgetRefresh: refresh)
            XCTAssertEqual(counter.count, 4)
            CapturePresetStore.saveFlows([b], defaults: defaults, widgetRefresh: refresh)
            XCTAssertEqual(counter.count, 5)
            CapturePresetStore.saveFlows([a], defaults: nil, widgetRefresh: refresh)
            XCTAssertEqual(counter.count, 5)
        }
    }

    func testRealPresetSaveReadbackFailureDoesNotReload() throws {
        let counter = WidgetStoreRefreshCounter()
        let refresh = CapturePresetWidgetRefresh { counter.count += 1 }
        let suite = "capture-widget-profile-dropping.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(WidgetDroppingDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        CapturePresetStore.saveFlows([CapturePresetStore.defaultFlow], defaults: defaults, widgetRefresh: refresh)
        XCTAssertNil(defaults.data(forKey: CapturePresetStore.flowsKey))
        XCTAssertEqual(counter.count, 0)
    }

    private func profile(_ id: String, enabled: Bool = true) -> CapturePresetProfile {
        CapturePresetProfile(id: id, name: id, symbolName: "waveform", isEnabled: enabled)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "capture-widget-store.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}

private final class WidgetStoreRefreshCounter: @unchecked Sendable {
    var count = 0
}

/// Storage-failure test double, not a substituted production model/module.
private final class WidgetDroppingDefaults: UserDefaults {
    override func set(_ value: Any?, forKey defaultName: String) {}
}
