import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CaptureRouteSelectorTests: XCTestCase {
    func testSelectorMenuSelectsAnyEnabledRouteWithoutTouchingDraftContent() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let before = f.vm.draft
        XCTAssertTrue(f.selector.activatePreset(id: "work"))
        XCTAssertEqual(f.vm.draft.voxID, "work")
        XCTAssertEqual(f.vm.draft.text, before.text)
        XCTAssertEqual(f.vm.draft.additionalPayloads, before.additionalPayloads)
        XCTAssertEqual(f.vm.draft.id, before.id)
        XCTAssertNil(f.vm.draft.relativeNotePathOverride)
        let changed = f.vm.draft
        XCTAssertFalse(f.selector.activatePreset(id: "work"), "Reselecting the current Route is a no-op")
        XCTAssertEqual(f.vm.draft, changed)
        XCTAssertEqual(f.defaults.string(forKey: CapturePresetProfileStore.selectedProfileIDKey), "keyboard-sentinel")
    }

    func testDisabledSelectorAndUnknownRoutesDoNotInvokeCallback() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let before = f.vm.draft
        var invocations = 0
        let callback: (String) -> Bool = { id in
            invocations += 1
            return f.vm.selectVox(id)
        }
        let enabled = CaptureRouteSelector(
            profiles: f.presets.map(\.captureProfile),
            selectedProfile: f.presets[0].captureProfile,
            canChangeCaptureRoute: true,
            selectPreset: callback
        )
        XCTAssertFalse(enabled.activatePreset(id: "journal"))
        XCTAssertFalse(enabled.activatePreset(id: "unlisted"))
        let disabled = CaptureRouteSelector(
            profiles: enabled.profiles,
            selectedProfile: enabled.selectedProfile,
            canChangeCaptureRoute: false,
            selectPreset: callback
        )
        XCTAssertFalse(disabled.activatePreset(id: "inbox"))
        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(f.vm.draft, before)
    }

    func testPreviouslyRenderedSelectorRevalidatesBusyAndUnavailableInputsInRealViewModel() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let staleSelector = f.selector
        let before = f.vm.draft
        f.vm.isProcessingMedia = true
        XCTAssertFalse(staleSelector.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft, before)
        f.vm.isProcessingMedia = false
        var changed = f.presets
        changed[1].isEnabled = false
        f.defaults.set(try JSONEncoder().encode(changed), forKey: CapturePresetProfileStore.profilesKey)
        XCTAssertFalse(staleSelector.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft, before)
    }

    func testImmutableBackgroundPresetRunLeavesTheSelectorUsable() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        f.vm.configureCaptureRouteOwnership(
            { true },
            presetSelectionIsBlocked: { false }
        )
        XCTAssertFalse(f.vm.canChangeCaptureRoute)
        XCTAssertTrue(f.vm.canSelectCapturePreset)
        XCTAssertTrue(f.selector.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft.voxID, "inbox")
        XCTAssertNil(f.vm.beginCaptureRouteOperation())
    }

    func testRoutePillsTruncateLongNamesForTheTopBar() {
        XCTAssertEqual(CaptureRoutePillsRow.pillName("Work"), "Work")
        let long = CaptureRoutePillsRow.pillName("Reading notes with a much longer name")
        XCTAssertEqual(long.count, CaptureRoutePillsRow.pillNameLimit)
        XCTAssertTrue(long.hasSuffix("…"))
    }
}

/// Isolated real VM/store fixture shared with hosted rendering tests. No live
/// microphone, app-group writes, bookmark access, queue, or service is used.
@MainActor
struct QuickCapturePresetFixture {
    let vm: QuickCaptureViewModel
    let defaults: UserDefaults
    let presets: [CapturePreset]

    var selector: CaptureRouteSelector {
        CaptureRouteSelector(
            profiles: presets.map(\.captureProfile),
            selectedProfile: vm.selectedVoxProfile ?? presets[0].captureProfile,
            canChangeCaptureRoute: vm.canSelectCapturePreset,
            selectPreset: vm.selectVox
        )
    }

    static func make(in test: XCTestCase) async throws -> Self {
        let suite = "CaptureRouteSelectorTests-\(UUID().uuidString)"
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
        return Self(
            vm: vm,
            defaults: defaults,
            presets: presets
        )
    }
}
