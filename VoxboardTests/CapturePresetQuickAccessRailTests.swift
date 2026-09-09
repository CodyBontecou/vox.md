import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CapturePresetQuickAccessRailTests: XCTestCase {
    func testRailUsesStoredResolvedOrderWithoutACapAndLeavesEmptyOrSinglePinsUsable() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let order = Array(f.presets.map(\.id).reversed())
        XCTAssertTrue(f.preferences.setOrderedIDs(order))
        XCTAssertEqual(f.rail.profiles.map(\.id), order)
        XCTAssertEqual(f.rail.alternateProfiles.map(\.id), order.filter { $0 != "journal" })
        XCTAssertGreaterThan(f.rail.alternateProfiles.count, 5)
        XCTAssertTrue(f.preferences.setOrderedIDs([]))
        XCTAssertTrue(f.rail.alternateProfiles.isEmpty)
        XCTAssertFalse(f.rail.activatePreset(id: "inbox"))
        XCTAssertTrue(f.preferences.setOrderedIDs(["journal"]))
        XCTAssertTrue(f.rail.alternateProfiles.isEmpty, "The selector already represents the selected preset")
        var toggledSelectedOnlyRail = false
        XCTAssertFalse(
            f.selector(isRailExpanded: false) { toggledSelectedOnlyRail = true }
                .toggleRailIfAvailable()
        )
        XCTAssertFalse(toggledSelectedOnlyRail)
        XCTAssertTrue(f.preferences.setOrderedIDs(["inbox"]))
        XCTAssertEqual(f.rail.alternateProfiles.map(\.id), ["inbox"])
        XCTAssertTrue(f.rail.activatePreset(id: "inbox"))
    }

    func testSamePresetAndDisabledRailDoNotInvokeCallbackOrResetOverrides() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let before = f.vm.draft
        var invocations = 0
        let callback: (String) -> Bool = { id in
            invocations += 1
            return f.vm.selectVox(id)
        }
        let rail = CapturePresetQuickAccessRail(profiles: f.preferences.resolvedProfiles,
            selectedID: f.vm.draft.voxID, isExpanded: true,
            canChangeCaptureRoute: true, selectPreset: callback)
        XCTAssertFalse(rail.activatePreset(id: "journal"))
        XCTAssertFalse(rail.activatePreset(id: "unlisted"))
        let disabled = CapturePresetQuickAccessRail(profiles: rail.profiles,
            selectedID: rail.selectedID, isExpanded: true,
            canChangeCaptureRoute: false, selectPreset: callback)
        XCTAssertFalse(disabled.activatePreset(id: "inbox"))
        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertEqual(f.defaults.string(forKey: CapturePresetProfileStore.selectedProfileIDKey), "keyboard-sentinel")
    }

    func testPreviouslyRenderedRailAndSelectorRevalidateBusyAndUnavailableInputsInRealViewModel() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let staleRail = f.rail
        let staleSelector = f.selector(isRailExpanded: true, toggleRail: {})
        let before = f.vm.draft
        f.vm.isProcessingMedia = true
        XCTAssertFalse(staleRail.activatePreset(id: "inbox"))
        XCTAssertFalse(staleSelector.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft, before)
        f.vm.isProcessingMedia = false
        var changed = f.presets
        changed[1].isEnabled = false
        f.defaults.set(try JSONEncoder().encode(changed), forKey: CapturePresetProfileStore.profilesKey)
        XCTAssertFalse(staleRail.activatePreset(id: "inbox"))
        XCTAssertFalse(staleSelector.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft, before)
        f.preferences.reload()
        XCTAssertFalse(f.rail.profiles.contains(where: { $0.id == "inbox" }))
        XCTAssertTrue(f.preferences.orderedIDs.contains("inbox"), "Disabled pins keep their saved placement")
        changed.remove(at: 1)
        f.defaults.set(try JSONEncoder().encode(changed), forKey: CapturePresetProfileStore.profilesKey)
        XCTAssertFalse(staleRail.activatePreset(id: "inbox"))
        XCTAssertFalse(staleSelector.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft, before)
    }

    func testCollapsedRailAndUnavailableSelectorToggleCannotChangeTheDraft() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let before = f.vm.draft
        var toggleCount = 0
        let collapsed = CapturePresetQuickAccessRail(
            profiles: f.preferences.resolvedProfiles,
            selectedID: f.vm.draft.voxID,
            isExpanded: false,
            canChangeCaptureRoute: true,
            selectPreset: f.vm.selectVox
        )
        XCTAssertFalse(collapsed.activatePreset(id: "inbox"))

        let noPins = CapturePresetQuickAccessSelector(
            profiles: f.presets.map(\.captureProfile),
            selectedProfile: f.presets[0].captureProfile,
            hasQuickAccessProfiles: false,
            isRailExpanded: false,
            canChangeCaptureRoute: true,
            toggleRail: { toggleCount += 1 },
            selectPreset: f.vm.selectVox
        )
        XCTAssertFalse(noPins.toggleRailIfAvailable())

        let disabled = CapturePresetQuickAccessSelector(
            profiles: f.presets.map(\.captureProfile),
            selectedProfile: f.presets[0].captureProfile,
            hasQuickAccessProfiles: true,
            isRailExpanded: false,
            canChangeCaptureRoute: false,
            toggleRail: { toggleCount += 1 },
            selectPreset: f.vm.selectVox
        )
        XCTAssertFalse(disabled.toggleRailIfAvailable())
        XCTAssertEqual(toggleCount, 0)
        XCTAssertEqual(f.vm.draft, before)
    }

    func testEmptySelectedOnlyAndOneAlternativeSelectorsKeepEveryPresetActionAvailable() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let states: [([String], Bool)] = [
            ([], false),
            (["journal"], false),
            (["inbox"], true),
        ]

        for (orderedIDs, expectsDisclosure) in states {
            if f.vm.draft.voxID != "journal" {
                XCTAssertTrue(f.vm.selectVox("journal"))
            }
            XCTAssertTrue(f.preferences.setOrderedIDs(orderedIDs))
            var didToggle = false
            let selector = f.selector(isRailExpanded: false) { didToggle = true }

            XCTAssertEqual(selector.toggleRailIfAvailable(), expectsDisclosure)
            XCTAssertEqual(didToggle, expectsDisclosure)
            XCTAssertTrue(
                selector.activatePreset(id: "work"),
                "The complete menu action set must include unpinned presets for \(orderedIDs)"
            )
            XCTAssertEqual(f.vm.draft.voxID, "work")
        }
    }

    func testSelectorAndRailButtonExposeAccurateSelectionAndRoutingSemantics() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let collapsed = f.selector(isRailExpanded: false, toggleRail: {})
        XCTAssertTrue(collapsed.accessibilitySelectionTraits.contains(.isSelected))
        XCTAssertEqual(
            collapsed.accessibilityHint,
            String(localized: "Expand pinned Capture Presets. Use the Show Menu action for all Capture Presets.")
        )
        XCTAssertEqual(collapsed.accessibilityValue, String(localized: "Collapsed"))

        let expanded = f.selector(isRailExpanded: true, toggleRail: {})
        XCTAssertEqual(
            expanded.accessibilityHint,
            String(localized: "Collapse pinned Capture Presets. Use the Show Menu action for all Capture Presets.")
        )
        XCTAssertEqual(expanded.accessibilityValue, String(localized: "Expanded"))

        let alternative = CapturePresetQuickAccessButton(
            profile: f.presets[1].captureProfile,
            isSelected: false,
            action: {}
        )
        XCTAssertEqual(
            alternative.accessibilityHint,
            String(localized: "Use this preset for the current draft. Text and attachments stay in place; one-off route overrides reset.")
        )
    }

    func testSelectorPrimaryActionOnlyTogglesRailAndRetainsAllPresetSelectionFallback() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let before = f.vm.draft
        var isExpanded = false
        let selector = CapturePresetQuickAccessSelector(
            profiles: f.presets.map(\.captureProfile),
            selectedProfile: f.presets[0].captureProfile,
            hasQuickAccessProfiles: true,
            isRailExpanded: false,
            canChangeCaptureRoute: true,
            toggleRail: { isExpanded.toggle() },
            selectPreset: f.vm.selectVox
        )

        XCTAssertTrue(selector.toggleRailIfAvailable())
        XCTAssertTrue(isExpanded)
        XCTAssertTrue(selector.accessibilitySelectionTraits.contains(.isSelected))
        XCTAssertEqual(f.vm.draft, before, "Expanding the rail must not select or reroute a preset")
        XCTAssertFalse(selector.activatePreset(id: "journal"))
        XCTAssertTrue(selector.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft.voxID, "inbox")
    }

    func testImmutableBackgroundPresetRunLeavesTheNextPresetControlsUsable() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        f.vm.configureCaptureRouteOwnership(
            { true },
            presetSelectionIsBlocked: { false }
        )

        XCTAssertFalse(f.vm.canChangeCaptureRoute)
        XCTAssertTrue(f.vm.canSelectCapturePreset)
        XCTAssertTrue(f.rail.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft.voxID, "inbox")

        var didToggle = false
        XCTAssertTrue(
            f.selector(isRailExpanded: false) { didToggle = true }
                .toggleRailIfAvailable()
        )
        XCTAssertTrue(didToggle)
        XCTAssertNil(f.vm.beginCaptureRouteOperation())
    }

    func testRailExpansionPreferenceDefaultsCollapsedAndSurvivesDefaultsReload() throws {
        XCTAssertEqual(
            CapturePreferenceKeys.presetQuickAccessRailExpanded,
            "capture.presets.quickAccess.railExpanded.v1"
        )
        let suite = "CapturePresetRailExpansionPreference-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertNil(defaults.object(forKey: CapturePreferenceKeys.presetQuickAccessRailExpanded))
        XCTAssertFalse(defaults.bool(forKey: CapturePreferenceKeys.presetQuickAccessRailExpanded))
        defaults.set(true, forKey: CapturePreferenceKeys.presetQuickAccessRailExpanded)

        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertTrue(reopened.bool(forKey: CapturePreferenceKeys.presetQuickAccessRailExpanded))
        CaptureToolbarPreferences(defaults: reopened).reset()
        XCTAssertTrue(
            reopened.bool(forKey: CapturePreferenceKeys.presetQuickAccessRailExpanded),
            "Resetting toolbar actions must not discard the independent rail preference"
        )
    }

    func testChangedRailSelectionUsesRealViewModelAndReportsOnlyActualChange() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let before = f.vm.draft
        XCTAssertTrue(f.rail.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft.voxID, "inbox")
        XCTAssertEqual(f.vm.draft.text, before.text)
        XCTAssertEqual(f.vm.draft.additionalPayloads, before.additionalPayloads)
        XCTAssertEqual(f.vm.draft.id, before.id)
        XCTAssertNil(f.vm.draft.relativeNotePathOverride)
        XCTAssertNil(f.vm.draft.voxProfileSnapshot)
        let changed = f.vm.draft
        XCTAssertFalse(f.rail.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft, changed)
        XCTAssertEqual(f.defaults.string(forKey: CapturePresetProfileStore.selectedProfileIDKey), "keyboard-sentinel")
    }
}

/// Isolated real VM/store fixture shared with hosted rendering tests. No live
/// microphone, app-group writes, bookmark access, queue, or service is used.
@MainActor
struct QuickCapturePresetFixture {
    let vm: QuickCaptureViewModel
    let preferences: CapturePresetQuickAccessPreferences
    let defaults: UserDefaults
    let presets: [CapturePreset]

    var rail: CapturePresetQuickAccessRail { rail(isExpanded: true) }

    func rail(isExpanded: Bool) -> CapturePresetQuickAccessRail {
        CapturePresetQuickAccessRail(
            profiles: preferences.resolvedProfiles,
            selectedID: vm.draft.voxID,
            isExpanded: isExpanded,
            canChangeCaptureRoute: vm.canSelectCapturePreset,
            selectPreset: vm.selectVox
        )
    }

    func selector(
        isRailExpanded: Bool,
        toggleRail: @escaping () -> Void
    ) -> CapturePresetQuickAccessSelector {
        CapturePresetQuickAccessSelector(
            profiles: presets.map(\.captureProfile),
            selectedProfile: vm.selectedVoxProfile ?? presets[0].captureProfile,
            hasQuickAccessProfiles: preferences.resolvedProfiles.contains {
                $0.id != vm.draft.voxID
            },
            isRailExpanded: isRailExpanded,
            canChangeCaptureRoute: vm.canSelectCapturePreset,
            toggleRail: toggleRail,
            selectPreset: vm.selectVox
        )
    }

    static func make(in test: XCTestCase) async throws -> Self {
        let suite = "CapturePresetQuickAccessRailTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destinationID = UUID()
        let ids = ["journal", "inbox", "tasks", "ideas", "travel", "reading", "work"]
        let names = ["Journal", "Inbox", "Tasks", "أفكار", "Travel", "Reading notes with a long name", "Work"]
        let emojis: [String?] = ["📓", "📥", nil, "💡", "🇯🇵", "👩🏽‍💻", "👨‍👩‍👧‍👦"]
        let presets = ids.indices.map { index in
            CapturePreset(id: ids[index], name: names[index], symbolName: "tray", emoji: emojis[index],
                          captureDestinationID: destinationID)
        }
        defaults.set(try JSONEncoder().encode(presets), forKey: CapturePresetProfileStore.profilesKey)
        defaults.set(1, forKey: CapturePresetProfileStore.ownedRouteMigrationVersionKey)
        defaults.set("journal", forKey: CapturePresetProfileStore.selectedCaptureProfileIDKey)
        defaults.set("keyboard-sentinel", forKey: CapturePresetProfileStore.selectedProfileIDKey)
        defaults.set(ids, forKey: CapturePresetQuickAccessStore.storageKey)
        let destination = CaptureDestination(id: destinationID, name: "Notes", rootBookmark: Data([1]),
            rootName: "Vault", noteTarget: .newNote(pathTemplate: "{date}.md"))
        try await CaptureLibraryStore(fileURL: root.appendingPathComponent(AppConstants.captureLibraryFilename))
            .save(CaptureLibraryEnvelope(destinations: [destination], defaultDestinationID: destinationID))
        let asset = try CaptureAssetReference(relativePath: "image.jpg", originalFilename: "image.jpg",
                                             contentTypeIdentifier: "public.jpeg")
        let draft = CaptureDraft(text: "Keep **Markdown**, 👩🏽‍💻, and this selection.", voxID: "journal",
            voxProfileSnapshot: presets[0].captureProfile, destinationID: destinationID,
            placementOverride: .prepend, relativeNotePathOverride: "One-off.md",
            additionalPayloads: [.image(asset, altText: "Keep attachment")])
        try await CaptureDraftStore(rootDirectoryURL: root).save(draft)
        let vm = QuickCaptureViewModel(captureRootURL: root, defaults: defaults)
        test.addTeardownBlock { @MainActor in
            _ = await vm.flushDraftForTermination()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        await vm.load()
        XCTAssertNil(vm.errorMessage)
        return Self(vm: vm, preferences: CapturePresetQuickAccessPreferences(defaults: defaults),
                    defaults: defaults, presets: presets)
    }
}
