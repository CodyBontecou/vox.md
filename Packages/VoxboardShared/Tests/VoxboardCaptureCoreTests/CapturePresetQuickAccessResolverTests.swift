import XCTest
@testable import VoxboardCaptureCore

final class CapturePresetQuickAccessResolverTests: XCTestCase {
    func test_normalizationIsStableFirstWithoutChangingOpaqueIDs() {
        XCTAssertEqual(
            CapturePresetQuickAccessResolver.normalizedIDs(["B", "a", "B", " a ", "A", "a", ""]),
            ["B", "a", " a ", "A", ""]
        )
    }

    func test_resolutionPreservesRequestedOrderAndFiltersUnknownDisabledAndDuplicates() {
        let profiles = [profile("a"), profile("disabled", enabled: false), profile("b"), profile("c")]
        XCTAssertEqual(
            CapturePresetQuickAccessResolver.resolve(
                orderedIDs: ["c", "deleted", "b", "disabled", "c", "a"], profiles: profiles
            ).map(\.id),
            ["c", "b", "a"]
        )
    }

    func test_emptyOrUnknownIDsNeverFallBackToDefaultOrAnotherPreset() {
        let profiles = [profile(CapturePresetProfileStore.defaultProfileID), profile("a")]
        for ids in [[String](), ["deleted"], [" a ", "A", ""]] {
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(orderedIDs: ids, profiles: profiles), [])
        }
        XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(orderedIDs: ["a"], profiles: []), [])
    }

    func test_duplicateProfileIDsUseFirstRecordIncludingDisabledState() {
        var renamed = profile("a")
        renamed.name = "Later duplicate"
        XCTAssertEqual(
            CapturePresetQuickAccessResolver.resolve(orderedIDs: ["a"], profiles: [profile("a"), renamed]),
            [profile("a")]
        )
        XCTAssertEqual(
            CapturePresetQuickAccessResolver.resolve(
                orderedIDs: ["a"], profiles: [profile("a", enabled: false), renamed]
            ),
            []
        )
    }

    func test_resolutionReturnsCurrentIdentityAndPolicyNotCopiedWorkflows() {
        var current = profile("a")
        current.name = "Renamed"
        current.symbolName = "book"
        current.captureDestinationID = UUID()
        current.capturePrompt = "New prompt"
        XCTAssertEqual(
            CapturePresetQuickAccessResolver.resolve(orderedIDs: ["a"], profiles: [current]),
            [current]
        )
    }

    func test_readOnlyDefaultsResolutionDoesNotSeedOrFabricateProfiles() throws {
        XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: nil), [])
        try withDefaults { defaults in
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults), [])
            try saveProfiles([profile("a")], defaults: defaults)
            defaults.set("a", forKey: CapturePresetProfileStore.selectedProfileIDKey)
            defaults.set("a", forKey: CapturePresetProfileStore.selectedCaptureProfileIDKey)

            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults), [])
            XCTAssertNil(defaults.object(forKey: CapturePresetQuickAccessStore.storageKey))
            defaults.set(["a"], forKey: CapturePresetQuickAccessStore.storageKey)
            defaults.removeObject(forKey: CapturePresetProfileStore.profilesKey)
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults), [])
            defaults.set(Data("malformed".utf8), forKey: CapturePresetProfileStore.profilesKey)
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults), [])
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey), ["a"])
        }
    }

    func test_readOnlyDefaultsResolutionDoesNotRepairMalformedPins() throws {
        try withDefaults { defaults in
            try saveProfiles([profile("a")], defaults: defaults)
            let invalid = Data("[\"a\"]".utf8)
            defaults.set(invalid, forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults), [])
            XCTAssertEqual(defaults.data(forKey: CapturePresetQuickAccessStore.storageKey), invalid)
        }
    }

    func test_disableAndReenableRestoreSavedPositionWithoutReadWrites() throws {
        try withDefaults { defaults in
            let ids = ["b", "a", "b", "c"]
            defaults.set(ids, forKey: CapturePresetQuickAccessStore.storageKey)
            try saveProfiles([profile("a"), profile("b", enabled: false), profile("c")], defaults: defaults)
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults).map(\.id), ["a", "c"])
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey), ids)

            try saveProfiles([profile("c"), profile("a"), profile("b")], defaults: defaults)
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults).map(\.id), ["b", "a", "c"])
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey), ids)
        }
    }

    func test_deletedIDCannotLaunchOrReturnAfterAuthoritativePruning() throws {
        try withDefaults { defaults in
            defaults.set(["deleted", "a"], forKey: CapturePresetQuickAccessStore.storageKey)
            try saveProfiles([profile("new"), profile("a")], defaults: defaults)
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults).map(\.id), ["a"])
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey), ["deleted", "a"])

            XCTAssertTrue(CapturePresetQuickAccessStore.save(
                orderedIDs: CapturePresetQuickAccessStore.load(defaults: defaults).orderedIDs,
                authoritativeProfiles: CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults),
                defaults: defaults
            ))
            // Even an attempted recreation of that ID cannot resurrect its pin
            // once a deliberate write with authoritative profiles pruned it.
            try saveProfiles([profile("deleted"), profile("a")], defaults: defaults)
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults).map(\.id), ["a"])
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey), ["a"])
        }
    }

    func test_explicitEmptyRemainsEmptyInReadOnlyClients() throws {
        try withDefaults { defaults in
            defaults.set([String](), forKey: CapturePresetQuickAccessStore.storageKey)
            try saveProfiles([profile("a"), profile("b")], defaults: defaults)
            XCTAssertEqual(CapturePresetQuickAccessResolver.resolve(defaults: defaults), [])
            XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .stored([]))
        }
    }

    private func profile(_ id: String, enabled: Bool = true) -> CapturePresetProfile {
        CapturePresetProfile(id: id, name: id, symbolName: "waveform", isEnabled: enabled)
    }

    private func saveProfiles(_ profiles: [CapturePresetProfile], defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(profiles), forKey: CapturePresetProfileStore.profilesKey)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "capture-preset-quick-access-resolver.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
