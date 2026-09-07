import Observation
import XCTest
@testable import VoxboardShared

@MainActor
final class CapturePresetQuickAccessPreferencesTests: XCTestCase {
    func test_injectedFullProfilesSeedAndExposeDisabledPinSeparatelyFromResolvedProfiles() throws {
        try withDefaults { defaults in
            let profiles = [profile("b"), profile("a", enabled: false), profile("c")]
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults, authoritativeProfiles: profiles)
            XCTAssertEqual(preferences.state, .stored(["b", "c"]))
            XCTAssertEqual(preferences.resolvedProfiles.map(\.id), ["b", "c"])

            XCTAssertTrue(preferences.setOrderedIDs(["c", "a", "b"], authoritativeProfiles: profiles))
            XCTAssertTrue(preferences.isPinned(id: "a"))
            XCTAssertFalse(preferences.isPinned(id: "missing"))
            XCTAssertEqual(preferences.orderedIDs, ["c", "a", "b"])
            XCTAssertEqual(preferences.resolvedProfiles.map(\.id), ["c", "b"])
        }
    }

    func test_missingPersistedProfilesDeferSeedingUntilExplicitReload() throws {
        try withDefaults { defaults in
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults)
            XCTAssertEqual(preferences.state, .absent)
            XCTAssertEqual(preferences.resolvedProfiles, [])
            XCTAssertNil(defaults.object(forKey: CapturePresetQuickAccessStore.storageKey))

            try saveProfiles([profile("b"), profile("a")], defaults: defaults)
            preferences.reload()
            XCTAssertEqual(preferences.orderedIDs, ["b", "a"])
        }
    }

    func test_explicitUnknownProfileSnapshotDoesNotUsePersistedFallbackForSeeding() throws {
        try withDefaults { defaults in
            try saveProfiles([profile("a")], defaults: defaults)
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults, authoritativeProfiles: nil)
            XCTAssertEqual(preferences.state, .absent)
            XCTAssertEqual(preferences.resolvedProfiles, [])
            preferences.reload()
            XCTAssertEqual(preferences.state, .stored(["a"]))
        }
    }

    func test_unavailableDefaultsDoNotPretendToSaveOrOfferLaunches() {
        let preferences = CapturePresetQuickAccessPreferences(defaults: nil, authoritativeProfiles: [profile("a")])
        XCTAssertEqual(preferences.state, .unavailable)
        XCTAssertEqual(preferences.orderedIDs, [])
        XCTAssertEqual(preferences.resolvedProfiles, [])
        XCTAssertFalse(preferences.setOrderedIDs(["a"], authoritativeProfiles: [profile("a")]))
        XCTAssertEqual(preferences.state, .unavailable)
    }

    func test_explicitEmptySurvivesNewInstanceReloadAndReenable() throws {
        try withDefaults { defaults in
            try saveProfiles([profile("a", enabled: false), profile("b")], defaults: defaults)
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults)
            XCTAssertTrue(preferences.setOrderedIDs([]))

            try saveProfiles([profile("b"), profile("a"), profile("c")], defaults: defaults)
            let reloaded = CapturePresetQuickAccessPreferences(defaults: defaults)
            reloaded.reload()
            XCTAssertEqual(reloaded.state, .stored([]))
            XCTAssertEqual(reloaded.resolvedProfiles, [])
        }
    }

    func test_reloadRefreshesIdentityAndAvailabilityWithoutReorderingOrPruning() throws {
        try withDefaults { defaults in
            let preferences = CapturePresetQuickAccessPreferences(
                defaults: defaults, authoritativeProfiles: [profile("b"), profile("a"), profile("deleted")]
            )
            var renamed = profile("a")
            renamed.name = "Renamed"
            renamed.symbolName = "book"
            preferences.reload(authoritativeProfiles: [renamed, profile("b", enabled: false), profile("new")])
            XCTAssertEqual(preferences.orderedIDs, ["b", "a", "deleted"])
            XCTAssertEqual(preferences.resolvedProfiles, [renamed])

            preferences.reload(authoritativeProfiles: [renamed, profile("b")])
            XCTAssertEqual(preferences.resolvedProfiles.map(\.id), ["b", "a"])
            XCTAssertEqual(preferences.orderedIDs, ["b", "a", "deleted"])
        }
    }

    func test_explicitReloadObservesExternalDefaultsOrderAndEmptyWithoutAutomaticObservers() throws {
        try withDefaults { defaults in
            try saveProfiles([profile("a"), profile("b")], defaults: defaults)
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults)
            defaults.set(["b", "a"], forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertEqual(preferences.orderedIDs, ["a", "b"], "State is a snapshot until the host reloads")
            preferences.reload()
            XCTAssertEqual(preferences.orderedIDs, ["b", "a"])
            XCTAssertEqual(preferences.resolvedProfiles.map(\.id), ["b", "a"])

            defaults.set([String](), forKey: CapturePresetQuickAccessStore.storageKey)
            preferences.reload()
            XCTAssertEqual(preferences.state, .stored([]))
            XCTAssertEqual(preferences.resolvedProfiles, [])
        }
    }

    func test_writeReadsFreshAuthoritativeProfilesPrunesDeletedAndKeepsDisabled() throws {
        try withDefaults { defaults in
            try saveProfiles([profile("a"), profile("b"), profile("deleted")], defaults: defaults)
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults)
            try saveProfiles([profile("a"), profile("b", enabled: false)], defaults: defaults)
            XCTAssertTrue(preferences.setOrderedIDs(["deleted", "b", "b", "a"]))
            XCTAssertEqual(preferences.orderedIDs, ["b", "a"])
            XCTAssertEqual(preferences.resolvedProfiles.map(\.id), ["a"])
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults).map(\.id), ["a"])
        }
    }

    func test_failedProfileReadDoesNotErasePinsAndRecoveryDoesNotReseed() throws {
        try withDefaults { defaults in
            try saveProfiles([profile("a"), profile("b")], defaults: defaults)
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults)
            defaults.set(Data("malformed".utf8), forKey: CapturePresetProfileStore.profilesKey)
            XCTAssertFalse(preferences.setOrderedIDs([]))
            XCTAssertEqual(preferences.orderedIDs, ["a", "b"])
            XCTAssertEqual(preferences.resolvedProfiles, [])
            preferences.reload()
            XCTAssertEqual(preferences.orderedIDs, ["a", "b"])

            try saveProfiles([profile("b"), profile("a"), profile("new")], defaults: defaults)
            preferences.reload()
            XCTAssertEqual(preferences.resolvedProfiles.map(\.id), ["a", "b"])
        }
    }

    func test_malformedPinsFailClosedUntilDeliberateWrite() throws {
        try withDefaults { defaults in
            try saveProfiles([profile("a")], defaults: defaults)
            defaults.set(42, forKey: CapturePresetQuickAccessStore.storageKey)
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults)
            preferences.reload()
            XCTAssertEqual(preferences.state, .malformed)
            XCTAssertEqual(preferences.resolvedProfiles, [])
            XCTAssertEqual(defaults.integer(forKey: CapturePresetQuickAccessStore.storageKey), 42)
            XCTAssertTrue(preferences.setOrderedIDs([]))
            XCTAssertEqual(preferences.state, .stored([]))
        }
    }

    func test_reorderingInvalidatesObservableOrderedIDs() throws {
        try withDefaults { defaults in
            let profiles = [profile("a"), profile("b")]
            let preferences = CapturePresetQuickAccessPreferences(defaults: defaults, authoritativeProfiles: profiles)
            let changed = expectation(description: "ordered IDs observation invalidated")
            withObservationTracking {
                _ = preferences.orderedIDs
            } onChange: {
                changed.fulfill()
            }
            XCTAssertTrue(preferences.setOrderedIDs(["b", "a"], authoritativeProfiles: profiles))
            wait(for: [changed], timeout: 1)
            XCTAssertEqual(preferences.orderedIDs, ["b", "a"])
        }
    }

    private func profile(_ id: String, enabled: Bool = true) -> CapturePresetProfile {
        CapturePresetProfile(id: id, name: id, symbolName: "waveform", isEnabled: enabled)
    }

    private func saveProfiles(_ profiles: [CapturePresetProfile], defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(profiles), forKey: CapturePresetProfileStore.profilesKey)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "capture-preset-quick-access-preferences.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
