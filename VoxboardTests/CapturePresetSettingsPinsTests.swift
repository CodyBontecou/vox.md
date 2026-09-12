import SwiftUI
import UIKit
import VoxboardShared
import XCTest
@testable import Voxboard

@MainActor
final class CapturePresetSettingsPinsTests: XCTestCase {
    func testManualPinsHaveNoCapAndDoNotChangeEnabledOrSelectionPreferences() throws {
        try withDefaults { defaults in
            let profiles = (0..<8).map { profile("preset-\($0)", enabled: $0 != 2) }
            try save(profiles, to: defaults)
            let profileBytes = defaults.data(forKey: CapturePresetStore.flowsKey)
            defaults.set("keyboard", forKey: CapturePresetProfileStore.selectedProfileIDKey)
            defaults.set("draft", forKey: CapturePresetProfileStore.selectedCaptureProfileIDKey)
            let pins = CapturePresetSettingsPins(defaults: defaults)
            XCTAssertEqual(pins.orderedIDs, ["preset-0", "preset-1", "preset-3", "preset-4", "preset-5"])

            for profile in profiles { XCTAssertTrue(pins.setPinned(true, id: profile.id)) }
            XCTAssertEqual(pins.orderedIDs.count, 8)
            XCTAssertTrue(pins.preferences.isPinned(id: "preset-2"))
            XCTAssertFalse(pins.preferences.resolvedProfiles.contains { $0.id == "preset-2" })
            XCTAssertEqual(defaults.data(forKey: CapturePresetStore.flowsKey), profileBytes)
            XCTAssertEqual(defaults.string(forKey: CapturePresetProfileStore.selectedProfileIDKey), "keyboard")
            XCTAssertEqual(defaults.string(forKey: CapturePresetProfileStore.selectedCaptureProfileIDKey), "draft")
            let before = pins.orderedIDs
            XCTAssertTrue(pins.setPinned(true, id: before[0]))
            XCTAssertEqual(pins.orderedIDs, before, "Already pinned must not move to the end")
            XCTAssertTrue(pins.move(fromOffsets: IndexSet(integer: 0), toOffset: before.count))
            XCTAssertTrue(pins.setPinned(false, id: before[1]))
            XCTAssertEqual(defaults.data(forKey: CapturePresetStore.flowsKey), profileBytes)
            XCTAssertEqual(defaults.string(forKey: CapturePresetProfileStore.selectedProfileIDKey), "keyboard")
            XCTAssertEqual(defaults.string(forKey: CapturePresetProfileStore.selectedCaptureProfileIDKey), "draft")
        }
    }

    func testUnifiedSettingsSectionsPartitionPresetsWithoutDuplicates() throws {
        try withDefaults { defaults in
            try save([profile("a"), profile("b"), profile("c", enabled: false)], to: defaults)
            defaults.set(["c", "a", "missing"], forKey: CapturePresetQuickAccessStore.storageKey)
            let pins = CapturePresetSettingsPins(defaults: defaults)

            XCTAssertEqual(pins.orderedIDs, ["c", "a", "missing"])
            XCTAssertEqual(pins.unpinnedIDs(in: ["a", "b", "c"]), ["b"])
            XCTAssertTrue(Set(pins.orderedIDs).isDisjoint(with: pins.unpinnedIDs(in: ["a", "b", "c"])))

            XCTAssertTrue(pins.setPinned(false, id: "a"))
            XCTAssertEqual(pins.unpinnedIDs(in: ["a", "b", "c"]), ["a", "b"])
            XCTAssertTrue(pins.setPinned(true, id: "b"))
            XCTAssertEqual(pins.orderedIDs, ["c", "b"])
            XCTAssertEqual(pins.unpinnedIDs(in: ["a", "b", "c"]), ["a"])
        }
    }

    func testNativeMoveOffsetsUseStoredOrderIncludingDisabledPins() throws {
        try withDefaults { defaults in
            var profiles = [profile("a"), profile("disabled", enabled: false), profile("c")]
            try save(profiles, to: defaults)
            defaults.set(["a", "disabled", "c"], forKey: CapturePresetQuickAccessStore.storageKey)
            let pins = CapturePresetSettingsPins(defaults: defaults)
            XCTAssertTrue(pins.move(fromOffsets: IndexSet(integer: 2), toOffset: 0))
            XCTAssertEqual(pins.orderedIDs, ["c", "a", "disabled"])
            XCTAssertTrue(pins.move(fromOffsets: IndexSet(integer: 2), toOffset: 1))
            XCTAssertEqual(pins.orderedIDs, ["c", "disabled", "a"])
            XCTAssertEqual(pins.preferences.resolvedProfiles.map(\.id), ["c", "a"])
            XCTAssertEqual(pins.profile(id: "disabled")?.isEnabled, false)
            let reloaded = CapturePresetSettingsPins(defaults: defaults)
            XCTAssertEqual(reloaded.orderedIDs, ["c", "disabled", "a"])

            profiles[1].isEnabled = true
            try save(profiles, to: defaults)
            reloaded.reload()
            XCTAssertEqual(reloaded.preferences.resolvedProfiles.map(\.id), ["c", "disabled", "a"])
        }
    }

    func testRemovingAllPinsPersistsExplicitEmptyAcrossReloadAndNewPresets() throws {
        try withDefaults { defaults in
            try save([profile("a"), profile("b", enabled: false)], to: defaults)
            let pins = CapturePresetSettingsPins(defaults: defaults)
            XCTAssertTrue(pins.setPinned(true, id: "b"))
            XCTAssertTrue(pins.setPinned(false, id: "a"))
            XCTAssertTrue(pins.setPinned(false, id: "b"))
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey), [])
            try save([profile("b"), profile("a"), profile("new")], to: defaults)
            let reloaded = CapturePresetSettingsPins(defaults: defaults)
            reloaded.reload()
            XCTAssertEqual(reloaded.preferences.state, .stored([]))
            XCTAssertEqual(reloaded.preferences.resolvedProfiles, [])
        }
    }

    func testReloadUpdatesSavedIdentityAndAvailabilityWithoutReorderingOrPruning() throws {
        try withDefaults { defaults in
            try save([profile("a"), profile("b"), profile("deleted")], to: defaults)
            let pins = CapturePresetSettingsPins(defaults: defaults)
            var renamed = profile("b", enabled: false)
            renamed.name = "Renamed"
            renamed.emoji = "👩🏽‍💻"
            try save([renamed, profile("a")], to: defaults)
            pins.reload()
            XCTAssertEqual(pins.orderedIDs, ["a", "b", "deleted"])
            XCTAssertEqual(pins.profile(id: "b"), renamed)
            XCTAssertNil(pins.profile(id: "deleted"), "Unavailable row must never show a fallback preset")
            XCTAssertEqual(pins.preferences.resolvedProfiles.map(\.id), ["a"])
        }
    }

    func testPruningRequiresConfirmedPersistedDeletionAndKeepsDisabledPins() throws {
        try withDefaults { defaults in
            try save([profile("a"), profile("disabled", enabled: false), profile("deleted")], to: defaults)
            defaults.set(["deleted", "disabled", "a"], forKey: CapturePresetQuickAccessStore.storageKey)
            let pins = CapturePresetSettingsPins(defaults: defaults)
            XCTAssertFalse(pins.pruneAfterPersistedDeletion(id: "deleted"))
            XCTAssertEqual(pins.orderedIDs, ["deleted", "disabled", "a"])
            XCTAssertNotNil(pins.errorMessage)

            // Model the host's completed deletion boundary, not an unsaved UI array.
            try save([profile("a"), profile("disabled", enabled: false)], to: defaults)
            pins.reload()
            XCTAssertEqual(pins.orderedIDs, ["deleted", "disabled", "a"], "Reload alone does not prune")
            XCTAssertTrue(pins.pruneAfterPersistedDeletion(id: "deleted"))
            XCTAssertEqual(pins.orderedIDs, ["disabled", "a"])
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey), ["disabled", "a"])
            XCTAssertNil(pins.errorMessage)
        }
    }

    func testMissingAndUnreadableProfilesRefuseWritesWithoutFallbackOrErasingPins() throws {
        let unavailable = CapturePresetSettingsPins(defaults: nil)
        XCTAssertFalse(unavailable.setPinned(true, id: "general"))
        XCTAssertNotNil(unavailable.errorMessage)
        try withDefaults { defaults in
            let absent = CapturePresetSettingsPins(defaults: defaults)
            XCTAssertEqual(absent.preferences.state, .absent)
            XCTAssertFalse(absent.setPinned(true, id: "general"))
            XCTAssertNil(defaults.object(forKey: CapturePresetQuickAccessStore.storageKey))
            try save([profile("a"), profile("disabled", enabled: false)], to: defaults)
            defaults.set(["disabled", "a"], forKey: CapturePresetQuickAccessStore.storageKey)
            absent.reload()
            defaults.set(Data("unreadable".utf8), forKey: CapturePresetStore.flowsKey)
            XCTAssertFalse(absent.setPinned(false, id: "a"))
            XCTAssertNotNil(absent.errorMessage)
            XCTAssertFalse(absent.pruneAfterPersistedDeletion(id: "a"))
            XCTAssertEqual(absent.orderedIDs, ["disabled", "a"])
            XCTAssertNil(absent.profiles)
            XCTAssertEqual(absent.preferences.resolvedProfiles, [])
        }
    }

    func testStaleMoveAndOutOfRangeOffsetsRefuseWithoutReinterpretingRows() throws {
        try withDefaults { defaults in
            try save([profile("a"), profile("b"), profile("c")], to: defaults)
            let pins = CapturePresetSettingsPins(defaults: defaults)
            defaults.set(["c", "a", "b"], forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertFalse(pins.move(fromOffsets: IndexSet(integer: 0), toOffset: 3))
            XCTAssertEqual(pins.orderedIDs, ["c", "a", "b"])
            XCTAssertNotNil(pins.errorMessage)
            XCTAssertFalse(pins.move(fromOffsets: IndexSet(integer: 4), toOffset: 0))
            XCTAssertFalse(pins.move(fromOffsets: IndexSet(integer: 0), toOffset: -1))
            XCTAssertFalse(pins.move(fromOffsets: [], toOffset: 0))
            XCTAssertEqual(defaults.stringArray(forKey: CapturePresetQuickAccessStore.storageKey), ["c", "a", "b"])
        }
    }

    func testPinReadsFreshOrderAndMovePrunesUnavailableIDsWithoutOffsetDrift() throws {
        try withDefaults { defaults in
            try save([profile("a"), profile("b"), profile("c", enabled: false)], to: defaults)
            let pins = CapturePresetSettingsPins(defaults: defaults)
            defaults.set(["deleted", "b", "a"], forKey: CapturePresetQuickAccessStore.storageKey)
            XCTAssertTrue(pins.setPinned(true, id: "c"))
            XCTAssertEqual(pins.orderedIDs, ["b", "a", "c"])
            defaults.set(["deleted", "b", "a", "c"], forKey: CapturePresetQuickAccessStore.storageKey)
            pins.reload()
            XCTAssertTrue(pins.move(fromOffsets: IndexSet(integer: 3), toOffset: 0))
            XCTAssertEqual(pins.orderedIDs, ["c", "b", "a"])
            XCTAssertEqual(pins.preferences.resolvedProfiles.map(\.id), ["b", "a"])
            XCTAssertFalse(pins.setPinned(true, id: "missing"))
            XCTAssertEqual(pins.orderedIDs, ["c", "b", "a"])
        }
    }

    func testMalformedOrderIsNotReseededAndCanBeDeliberatelyReplaced() throws {
        try withDefaults { defaults in
            try save([profile("a"), profile("disabled", enabled: false)], to: defaults)
            defaults.set(42, forKey: CapturePresetQuickAccessStore.storageKey)
            let pins = CapturePresetSettingsPins(defaults: defaults)
            XCTAssertEqual(pins.preferences.state, .malformed)
            XCTAssertNotNil(pins.storageMessage)
            pins.reload()
            XCTAssertEqual(defaults.integer(forKey: CapturePresetQuickAccessStore.storageKey), 42)
            XCTAssertTrue(pins.setPinned(true, id: "disabled"))
            XCTAssertEqual(pins.orderedIDs, ["disabled"])
            XCTAssertEqual(pins.preferences.resolvedProfiles, [])
        }
    }

    func testPinnedSettingsMountAndUpdateInNarrowLargeTextRTLAndEditMode() async throws {
        let suite = "CapturePresetSettingsRendering.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try save([profile("journal"), profile("disabled", enabled: false)], to: defaults)
        let variants: [(CGFloat, DynamicTypeSize, LayoutDirection, EditMode)] = [
            (320, .large, .leftToRight, .inactive),
            (390, .accessibility3, .leftToRight, .active),
            (320, .large, .rightToLeft, .active),
        ]
        for (width, typeSize, direction, mode) in variants {
            defaults.set(["disabled", "journal", "unavailable"], forKey: CapturePresetQuickAccessStore.storageKey)
            let pins = CapturePresetSettingsPins(defaults: defaults)
            let appeared = expectation(description: "Pinned settings mounted")
            let content = NavigationStack {
                List {
                    Section("Pinned to Capture Bar") {
                        ForEach(pins.orderedIDs, id: \.self) { id in
                            if let profile = pins.profile(id: id) {
                                HStack(spacing: 12) {
                                    CapturePresetSettingsListLabel(
                                        preset: self.preset(profile),
                                        badge: id == "journal" ? "Default" : nil
                                    )
                                    CapturePresetSettingsPinButton(
                                        accessibilityID: "test_pin_\(id)",
                                        name: profile.accessibilityName,
                                        isPinned: true
                                    ) { pins.setPinned(false, id: id) }
                                }
                            } else {
                                CapturePresetSettingsPinnedRow(id: id, profile: nil) {
                                    pins.setPinned(false, id: id)
                                }
                            }
                        }
                        .onMove { offsets, destination in
                            pins.move(fromOffsets: offsets, toOffset: destination)
                        }
                    }
                    Section("Other Presets") {
                        ForEach(pins.unpinnedIDs(in: ["journal", "disabled"]), id: \.self) { id in
                            if let profile = pins.profile(id: id) {
                                HStack(spacing: 12) {
                                    CapturePresetSettingsListLabel(preset: self.preset(profile), badge: nil)
                                    CapturePresetSettingsPinButton(
                                        accessibilityID: "test_unpinned_\(id)",
                                        name: profile.accessibilityName,
                                        isPinned: false
                                    ) { pins.setPinned(true, id: id) }
                                }
                            }
                        }
                    }
                }
                .environment(\.editMode, .constant(mode))
                .navigationTitle("Capture Presets")
                .toolbar { EditButton() }
                .onAppear { appeared.fulfill() }
            }
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\.layoutDirection, direction)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 760))
            window.rootViewController = host
            window.isHidden = false
            host.loadViewIfNeeded()
            await fulfillment(of: [appeared], timeout: 3)
            try await settle(window)
            attach(host.view, name: "Pins disabled-missing \(width) \(typeSize) \(direction) \(mode)")
            XCTAssertEqual(pins.orderedIDs, ["disabled", "journal", "unavailable"])

            // Exercise the real observed action seam while its section is mounted.
            XCTAssertTrue(pins.move(fromOffsets: IndexSet(integer: 1), toOffset: 0))
            try await settle(window)
            XCTAssertEqual(pins.orderedIDs, ["journal", "disabled"])
            for id in pins.orderedIDs { XCTAssertTrue(pins.setPinned(false, id: id)) }
            try await settle(window)
            XCTAssertEqual(pins.preferences.state, .stored([]))
            attach(host.view, name: "Pins intentional-empty \(width) \(typeSize) \(direction)")
            defaults.set(Data("unreadable".utf8), forKey: CapturePresetStore.flowsKey)
            XCTAssertFalse(pins.setPinned(true, id: "journal"))
            try await settle(window)
            attach(host.view, name: "Pins refusal \(width) \(typeSize) \(direction)")
            try save([profile("journal"), profile("disabled", enabled: false)], to: defaults)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    private func profile(_ id: String, enabled: Bool = true) -> CapturePresetProfile {
        CapturePresetProfile(id: id, name: id == "disabled" ? "Disabled / مخفي — a longer preset name" : id,
                             symbolName: "book", emoji: "📔", isEnabled: enabled)
    }

    private func preset(_ profile: CapturePresetProfile) -> CapturePreset {
        CapturePreset(
            id: profile.id,
            name: profile.name,
            symbolName: profile.symbolName,
            emoji: profile.emoji,
            isEnabled: profile.isEnabled
        )
    }

    private func save(_ profiles: [CapturePresetProfile], to defaults: UserDefaults) throws {
        defaults.set(try JSONEncoder().encode(profiles), forKey: CapturePresetStore.flowsKey)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "CapturePresetSettingsPinsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func settle(_ window: UIWindow) async throws {
        window.rootViewController?.view.setNeedsLayout()
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        window.rootViewController?.view.layoutIfNeeded()
    }

    private func attach(_ view: UIView, name: String) {
        XCTAssertGreaterThan(view.bounds.width, 0)
        XCTAssertGreaterThan(view.bounds.height, 0)
        let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
