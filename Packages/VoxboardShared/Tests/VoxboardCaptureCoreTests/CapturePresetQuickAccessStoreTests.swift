import XCTest
@testable import VoxboardCaptureCore

final class CapturePresetQuickAccessStoreTests: XCTestCase {
    func test_storageKeyIsVersionedAndIndependent() {
        XCTAssertEqual(CapturePresetQuickAccessStore.storageKey, "capture.presets.quickAccess.orderedIDs.v1")
        XCTAssertNotEqual(CapturePresetQuickAccessStore.storageKey, CapturePresetProfileStore.profilesKey)
        XCTAssertNotEqual(CapturePresetQuickAccessStore.storageKey, CapturePresetProfileStore.selectedProfileIDKey)
        XCTAssertNotEqual(CapturePresetQuickAccessStore.storageKey, CapturePresetProfileStore.selectedCaptureProfileIDKey)
    }

    func test_loadDistinguishesUnavailableAbsentAndExplicitEmpty() throws {
        XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: nil), .unavailable)
        try withDefaults { defaults in
            XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .absent)
            defaults.set([String](), forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .stored([]))
        }
    }

    func test_loadNormalizesDuplicatesWithoutWritingOrFilteringUnavailableIDs() throws {
        try withDefaults { defaults in
            let rawIDs = ["second", "deleted", "first", "second", "disabled", "first"]
            defaults.set(rawIDs, forKey: CapturePresetQuickAccessStore.storageKey)

            XCTAssertEqual(
                CapturePresetQuickAccessStore.load(defaults: defaults),
                .stored(["second", "deleted", "first", "disabled"])
            )
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey), rawIDs)
        }
    }

    func test_malformedValuesFailClosedAndAreNotReseededOrRepairedOnRead() throws {
        try withDefaults { defaults in
            let malformed: [Any] = [
                "first", 1, true, ["order": ["first"]],
                ["first", 7] as [Any], Data("[\"first\"]".utf8),
            ]
            for value in malformed {
                defaults.set(value, forKey: CapturePresetQuickAccessStore.storageKey)
                let before = defaults.object(forKey: CapturePresetQuickAccessStore.storageKey) as? NSObject

                XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .malformed)
                XCTAssertEqual(
                    CapturePresetQuickAccessStore.seedIfNeeded(
                        authoritativeProfiles: [profile("first")], defaults: defaults
                    ),
                    .malformed
                )
                XCTAssertEqual(
                    defaults.object(forKey: CapturePresetQuickAccessStore.storageKey) as? NSObject,
                    before
                )
            }
        }
    }

    func test_seedUsesFirstFiveUniqueEnabledProfilesInAuthoritativeOrder() throws {
        try withDefaults { defaults in
            let profiles = [
                profile("disabled", enabled: false), profile("c"), profile("c"),
                profile("a"), profile("f"), profile("b"), profile("e"), profile("d"),
            ]
            XCTAssertEqual(
                CapturePresetQuickAccessStore.seedIfNeeded(authoritativeProfiles: profiles, defaults: defaults),
                .stored(["c", "a", "f", "b", "e"])
            )
            XCTAssertEqual(CapturePresetQuickAccessStore.initialSeedLimit, 5)
        }
    }

    func test_seedNeverRanksOrReseedsAfterProfilesChange() throws {
        try withDefaults { defaults in
            CapturePresetQuickAccessStore.seedIfNeeded(
                authoritativeProfiles: [profile("b"), profile("a")], defaults: defaults
            )
            XCTAssertEqual(
                CapturePresetQuickAccessStore.seedIfNeeded(
                    authoritativeProfiles: [profile("c"), profile("a"), profile("b", enabled: false)],
                    defaults: defaults
                ),
                .stored(["b", "a"])
            )
        }
    }

    func test_seedDefersWhenFullProfilesOrDefaultsAreUnavailable() throws {
        XCTAssertEqual(
            CapturePresetQuickAccessStore.seedIfNeeded(authoritativeProfiles: [profile("a")], defaults: nil),
            .unavailable
        )
        try withDefaults { defaults in
            XCTAssertEqual(
                CapturePresetQuickAccessStore.seedIfNeeded(authoritativeProfiles: nil, defaults: defaults),
                .absent
            )
            XCTAssertNil(defaults.object(forKey: CapturePresetQuickAccessStore.storageKey))
            XCTAssertEqual(
                CapturePresetQuickAccessStore.seedIfNeeded(authoritativeProfiles: [profile("a")], defaults: defaults),
                .stored(["a"])
            )
        }
    }

    func test_authoritativeEmptyAndAllDisabledSeedEmptyOnlyOnce() throws {
        for profiles in [[CapturePresetProfile](), [profile("a", enabled: false)]] {
            try withDefaults { defaults in
                XCTAssertEqual(
                    CapturePresetQuickAccessStore.seedIfNeeded(authoritativeProfiles: profiles, defaults: defaults),
                    .stored([])
                )
                XCTAssertEqual(
                    CapturePresetQuickAccessStore.seedIfNeeded(
                        authoritativeProfiles: [profile("a"), profile("new")], defaults: defaults
                    ),
                    .stored([])
                )
            }
        }
    }

    func test_authoritativeReaderDistinguishesMissingMalformedAndDecodedEmpty() throws {
        XCTAssertNil(CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: nil))
        try withDefaults { defaults in
            XCTAssertNil(CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults))
            for value in ["not-data", Data("broken".utf8), Data("{}".utf8), Data("[{\"id\":\"a\"}]".utf8)] as [Any] {
                defaults.set(value, forKey: CapturePresetProfileStore.profilesKey)
                let profiles = CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults)
                XCTAssertNil(profiles)
                XCTAssertEqual(
                    CapturePresetQuickAccessStore.seedIfNeeded(authoritativeProfiles: profiles, defaults: defaults),
                    .absent
                )
            }
            defaults.set(Data("[]".utf8), forKey: CapturePresetProfileStore.profilesKey)
            XCTAssertEqual(CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults), [])
        }
    }

    func test_authoritativeReaderIncludesDisabledProfilesAndIgnoresUnknownFields() throws {
        try withDefaults { defaults in
            let data = Data("""
            [{"id":"disabled","name":"Disabled","isEnabled":false,"futureField":42},
             {"id":"enabled","name":"Enabled"}]
            """.utf8)
            defaults.set(data, forKey: CapturePresetProfileStore.profilesKey)

            let profiles = try XCTUnwrap(CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults))
            XCTAssertEqual(profiles.map(\.id), ["disabled", "enabled"])
            XCTAssertEqual(profiles.map(\.isEnabled), [false, true])
            XCTAssertEqual(defaults.data(forKey: CapturePresetProfileStore.profilesKey), data)
        }
    }

    func test_saveNormalizesPrunesDeletedAndKeepsDisabledWithNoFiveItemCap() throws {
        try withDefaults { defaults in
            let ids = (1...8).map { "preset-\($0)" }
            let profiles = ids.map { profile($0, enabled: $0 != "preset-4") }
            let requested = ["deleted"] + ids.reversed() + ["preset-4", "retired"]

            XCTAssertTrue(CapturePresetQuickAccessStore.save(
                orderedIDs: requested, authoritativeProfiles: profiles, defaults: defaults
            ))
            XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .stored(Array(ids.reversed())))
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey)?.count, 8)
        }
    }

    func test_deliberateEmptySurvivesReloadSeedingAndReenable() throws {
        try withDefaults { defaults in
            let profiles = [profile("a"), profile("b", enabled: false)]
            CapturePresetQuickAccessStore.seedIfNeeded(authoritativeProfiles: profiles, defaults: defaults)
            XCTAssertTrue(CapturePresetQuickAccessStore.save(
                orderedIDs: [], authoritativeProfiles: profiles, defaults: defaults
            ))
            XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .stored([]))
            XCTAssertEqual(
                CapturePresetQuickAccessStore.seedIfNeeded(
                    authoritativeProfiles: [profile("b"), profile("a"), profile("c")], defaults: defaults
                ),
                .stored([])
            )
        }
    }

    func test_saveRefusesUnavailableFullProfilesWithoutChangingStorage() throws {
        XCTAssertFalse(CapturePresetQuickAccessStore.save(
            orderedIDs: ["a"], authoritativeProfiles: [profile("a")], defaults: nil
        ))
        try withDefaults { defaults in
            XCTAssertFalse(CapturePresetQuickAccessStore.save(
                orderedIDs: [], authoritativeProfiles: nil, defaults: defaults
            ))
            XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .absent)
            defaults.set(["a"], forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertFalse(CapturePresetQuickAccessStore.save(
                orderedIDs: [], authoritativeProfiles: nil, defaults: defaults
            ))
            XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .stored(["a"]))
        }
    }

    func test_deliberateWriteCanRepairMalformedPreference() throws {
        try withDefaults { defaults in
            defaults.set(17, forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertTrue(CapturePresetQuickAccessStore.save(
                orderedIDs: ["b", "a", "b"],
                authoritativeProfiles: [profile("a"), profile("b")], defaults: defaults
            ))
            XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .stored(["b", "a"]))
        }
    }

    func test_deliberateWriteWithAuthoritativeEmptyPrunesEverything() throws {
        try withDefaults { defaults in
            defaults.set(["deleted"], forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertTrue(CapturePresetQuickAccessStore.save(
                orderedIDs: ["deleted"], authoritativeProfiles: [], defaults: defaults
            ))
            XCTAssertEqual(CapturePresetQuickAccessStore.load(defaults: defaults), .stored([]))
        }
    }

    func test_pinsDoNotWriteProfilesSelectionsOrOtherPreferences() throws {
        try withDefaults { defaults in
            let profiles = [profile("a"), profile("b", enabled: false)]
            let data = try JSONEncoder().encode(profiles)
            defaults.set(data, forKey: CapturePresetProfileStore.profilesKey)
            let sentinels = [
                CapturePresetProfileStore.selectedProfileIDKey: "keyboard",
                CapturePresetProfileStore.selectedCaptureProfileIDKey: "capture",
                "capture.toolbar.configuration.v1": "toolbar",
                "capture.voice.defaultResult.v1": "draft",
                "retiredCapturePresetIDs": "retired",
            ]
            for (key, value) in sentinels { defaults.set(value, forKey: key) }

            CapturePresetQuickAccessStore.seedIfNeeded(authoritativeProfiles: profiles, defaults: defaults)
            XCTAssertTrue(CapturePresetQuickAccessStore.save(
                orderedIDs: ["b", "a"], authoritativeProfiles: profiles, defaults: defaults
            ))
            XCTAssertEqual(defaults.data(forKey: CapturePresetProfileStore.profilesKey), data)
            for (key, value) in sentinels { XCTAssertEqual(defaults.string(forKey: key), value) }
        }
    }

    private func profile(_ id: String, enabled: Bool = true) -> CapturePresetProfile {
        CapturePresetProfile(id: id, name: id, symbolName: "waveform", isEnabled: enabled)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "capture-preset-quick-access-store.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
