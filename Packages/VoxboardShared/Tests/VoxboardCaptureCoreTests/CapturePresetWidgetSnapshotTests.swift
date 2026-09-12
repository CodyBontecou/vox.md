import XCTest
@testable import VoxboardCaptureCore

final class CapturePresetWidgetSnapshotTests: XCTestCase {
    func testFollowUsesPinsWhileCustomPreservesPositionsAndDuplicates() {
        let profiles = [profile("a"), profile("b"), profile("c")]
        let follow = snapshot(.followCaptureBar, pins: .stored(["c", "a", "c"]), profiles: profiles)
        XCTAssertEqual(follow.tiles.map(\.presetID), ["c", "a"])
        let custom = snapshot(.custom(slots: ["b", nil, "a", "b", nil]), profiles: profiles)
        XCTAssertEqual(custom.tiles.map(\.presetID), ["b", nil, "a", "b"])
        XCTAssertEqual(custom.tiles.map(\.id), ["slot:0", "slot:1", "slot:2", "slot:3"])
        XCTAssertEqual(custom.tiles[1].availability, .unconfigured)
        XCTAssertNil(custom.tiles[1].captureURL)
    }

    func testIconOnlyProfileSnapshotsKeepVisibleNameBlank() {
        var unnamed = profile("icon")
        unnamed.name = "  \n"
        let value = snapshot(.custom(slots: ["icon"]), profiles: [unnamed])
        XCTAssertEqual(value.tiles.first?.identity?.name, "")
        XCTAssertEqual(value.tiles.first?.identity?.accessibilityName, "Icon-only Capture Preset")
    }

    func testSnapshotsRetainIdentityOrderAndURLAfterStoreChanges() throws {
        try withDefaults { defaults in
            defaults.set(try JSONEncoder().encode([profile("a"), profile("b")]), forKey: CapturePresetProfileStore.profilesKey)
            defaults.set(["b", "a"], forKey: CapturePresetQuickAccessStore.storageKey)
            let old = CapturePresetWidgetSnapshot.load(selection: .followCaptureBar, defaults: defaults)
            var renamed = profile("b")
            renamed.name = "New name"
            renamed.emoji = "👨🏽‍💻"
            defaults.set(try JSONEncoder().encode([renamed, profile("a")]), forKey: CapturePresetProfileStore.profilesKey)
            defaults.set(["a", "b"], forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertEqual(old.tiles.map(\.presetID), ["b", "a"])
            XCTAssertEqual(old.tiles.first?.identity?.name, "b")
            XCTAssertNil(old.tiles.first?.identity?.emoji)
            let fresh = CapturePresetWidgetSnapshot.load(selection: .followCaptureBar, defaults: defaults)
            XCTAssertEqual(fresh.tiles.map(\.presetID), ["a", "b"])
            XCTAssertEqual(fresh.tiles.last?.identity?.emoji, "👨🏽‍💻")
            XCTAssertEqual(old.tiles.first?.captureURL, fresh.tiles.last?.captureURL)
        }
    }

    func testReadOnlyAbsentEmptyAndMalformedNeverSeedOrFallback() throws {
        try withDefaults { defaults in
            defaults.set(try JSONEncoder().encode([profile("a")]), forKey: CapturePresetProfileStore.profilesKey)
            defaults.set("a", forKey: CapturePresetProfileStore.selectedProfileIDKey)
            let absent = CapturePresetWidgetSnapshot.load(selection: .followCaptureBar, defaults: defaults)
            XCTAssertEqual(absent.emptyState, .needsCaptureBarSetup)
            XCTAssertTrue(absent.tiles.isEmpty)
            XCTAssertNil(defaults.object(forKey: CapturePresetQuickAccessStore.storageKey))
            defaults.set([String](), forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertEqual(CapturePresetWidgetSnapshot.load(selection: .followCaptureBar, defaults: defaults).emptyState, .emptyCaptureBar)
            defaults.set(42, forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertEqual(CapturePresetWidgetSnapshot.load(selection: .followCaptureBar, defaults: defaults).emptyState, .unavailableCaptureBar)
            XCTAssertEqual(defaults.integer(forKey: CapturePresetQuickAccessStore.storageKey), 42)
        }
        XCTAssertEqual(CapturePresetWidgetSnapshot.load(selection: .followCaptureBar, defaults: nil).emptyState, .unavailableCaptureBar)
    }

    func testDisabledDeletedAndUnreadableCustomTargetsKeepExactIDs() {
        let selection = CapturePresetWidgetSelection.custom(slots: ["disabled", "deleted", "enabled"])
        let value = snapshot(selection, profiles: [profile("disabled", enabled: false), profile("enabled")])
        XCTAssertEqual(value.tiles.map(\.availability), [.disabled, .missing, .available])
        XCTAssertEqual(value.tiles.map(\.presetID), ["disabled", "deleted", "enabled"])
        XCTAssertTrue(value.tiles.allSatisfy { $0.captureURL != nil })
        let missingStore = snapshot(selection, profiles: nil)
        XCTAssertEqual(missingStore.tiles.map(\.availability), [.storageUnavailable, .storageUnavailable, .storageUnavailable])
        let follow = snapshot(.followCaptureBar, pins: .stored(["disabled", "deleted", "enabled"]), profiles: [profile("disabled", enabled: false), profile("enabled")])
        XCTAssertEqual(follow.tiles.map(\.presetID), ["enabled"])
    }

    func testEmptyCustomAndFirstHoleDoNotBorrowSecondPreset() {
        XCTAssertEqual(snapshot(.custom(slots: []), profiles: []).tiles.map(\.availability), [.unconfigured])
        let value = snapshot(.custom(slots: [nil, "a"]), profiles: [profile("a")])
        XCTAssertNil(value.tiles.first?.presetID)
        XCTAssertEqual(value.tiles.last?.presetID, "a")
    }

    func testSpecialCharacterURLsRoundTripThroughActualLaunchParser() throws {
        for id in ["custom-a&b?c=d#e/%+", "👨🏽‍💻-旅-書", "a b", "a\"b"] {
            let value = snapshot(.custom(slots: [id]), profiles: [profile(id)])
            let url = try XCTUnwrap(value.tiles.first?.captureURL)
            let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
            XCTAssertEqual(items.first { $0.name == "preset" }?.value, id)
            XCTAssertEqual(items.first { $0.name == "source" }?.value, "widget")
            guard case .openComposer(let incoming) = try CaptureDeepLinkParser().parse(url) else {
                return XCTFail("Must open composer, never run/record")
            }
            XCTAssertEqual(incoming.voxID, id)
            XCTAssertEqual(incoming.source, .widget)
            XCTAssertNil(incoming.requestedInput)
        }
    }

    func testNonRoundtrippableIDsCannotAliasAnotherPreset() {
        for id in ["", " a ", "\na", String(repeating: "a", count: 161)] {
            XCTAssertNil(snapshot(.custom(slots: [id]), profiles: [profile(id), profile("a")]).tiles.first?.captureURL)
        }
    }

    func testCatalogRequestedOrderMissingAndStableFirstDuplicateProfiles() {
        let identities = CapturePresetWidgetCatalog.identities(profiles: [profile("a", enabled: false), profile("b"), profile("a")])
        let requested = CapturePresetWidgetCatalog.requested(identifiers: ["b", "missing", "a", "b"], identities: identities)
        XCTAssertEqual(requested.map(\.id), ["b", "missing", "a"])
        XCTAssertNil(requested[1].identity)
        XCTAssertEqual(requested[2].identity?.isEnabled, false)
    }

    private func profile(_ id: String, enabled: Bool = true) -> CapturePresetProfile {
        CapturePresetProfile(id: id, name: id, symbolName: "waveform", isEnabled: enabled)
    }

    private func snapshot(_ selection: CapturePresetWidgetSelection, pins: CapturePresetQuickAccessState = .stored([]), profiles: [CapturePresetProfile]?) -> CapturePresetWidgetSnapshot {
        CapturePresetWidgetSnapshot(selection: selection, pins: pins, profiles: profiles)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "capture-preset-widget.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
