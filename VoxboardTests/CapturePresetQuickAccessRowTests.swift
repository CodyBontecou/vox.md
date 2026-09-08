import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CapturePresetQuickAccessRowTests: XCTestCase {
    func testRowUsesStoredResolvedOrderWithoutACapAndLeavesEmptyOrSinglePinsUsable() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let order = Array(f.presets.map(\.id).reversed())
        XCTAssertTrue(f.preferences.setOrderedIDs(order))
        XCTAssertEqual(f.row.profiles.map(\.id), order)
        XCTAssertGreaterThan(f.row.profiles.count, 5)
        XCTAssertTrue(f.preferences.setOrderedIDs([]))
        XCTAssertTrue(f.row.profiles.isEmpty)
        XCTAssertFalse(f.row.activatePreset(id: "inbox"))
        XCTAssertTrue(f.preferences.setOrderedIDs(["inbox"]))
        XCTAssertEqual(f.row.profiles.map(\.id), ["inbox"])
        XCTAssertTrue(f.row.activatePreset(id: "inbox"))
    }

    func testSamePresetAndDisabledRowDoNotInvokeCallbackOrResetOverrides() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let before = f.vm.draft
        var invocations = 0
        let callback: (String) -> Bool = { id in
            invocations += 1
            return f.vm.selectVox(id)
        }
        let row = CapturePresetQuickAccessRow(profiles: f.preferences.resolvedProfiles,
            selectedID: f.vm.draft.voxID, canChangeCaptureRoute: true, selectPreset: callback)
        XCTAssertFalse(row.activatePreset(id: "journal"))
        XCTAssertFalse(row.activatePreset(id: "unlisted"))
        let disabled = CapturePresetQuickAccessRow(profiles: row.profiles,
            selectedID: row.selectedID, canChangeCaptureRoute: false, selectPreset: callback)
        XCTAssertFalse(disabled.activatePreset(id: "inbox"))
        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertEqual(f.defaults.string(forKey: CapturePresetProfileStore.selectedProfileIDKey), "keyboard-sentinel")
    }

    func testPreviouslyRenderedRowRevalidatesBusyAndUnavailableInputsInRealViewModel() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let staleRow = f.row
        let before = f.vm.draft
        f.vm.isProcessingMedia = true
        XCTAssertFalse(staleRow.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft, before)
        f.vm.isProcessingMedia = false
        var changed = f.presets
        changed[1].isEnabled = false
        f.defaults.set(try JSONEncoder().encode(changed), forKey: CapturePresetProfileStore.profilesKey)
        XCTAssertFalse(staleRow.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft, before)
        f.preferences.reload()
        XCTAssertFalse(f.row.profiles.contains(where: { $0.id == "inbox" }))
        XCTAssertTrue(f.preferences.orderedIDs.contains("inbox"), "Disabled pins keep their saved placement")
        changed.remove(at: 1)
        f.defaults.set(try JSONEncoder().encode(changed), forKey: CapturePresetProfileStore.profilesKey)
        XCTAssertFalse(staleRow.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft, before)
    }

    func testChangedRowSelectionUsesRealViewModelAndReportsOnlyActualChange() async throws {
        let f = try await QuickCapturePresetFixture.make(in: self)
        let before = f.vm.draft
        XCTAssertTrue(f.row.activatePreset(id: "inbox"))
        XCTAssertEqual(f.vm.draft.voxID, "inbox")
        XCTAssertEqual(f.vm.draft.text, before.text)
        XCTAssertEqual(f.vm.draft.additionalPayloads, before.additionalPayloads)
        XCTAssertEqual(f.vm.draft.id, before.id)
        XCTAssertNil(f.vm.draft.relativeNotePathOverride)
        XCTAssertNil(f.vm.draft.voxProfileSnapshot)
        let changed = f.vm.draft
        XCTAssertFalse(f.row.activatePreset(id: "inbox"))
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

    var row: CapturePresetQuickAccessRow {
        CapturePresetQuickAccessRow(profiles: preferences.resolvedProfiles, selectedID: vm.draft.voxID,
            canChangeCaptureRoute: vm.canChangeCaptureRoute, selectPreset: vm.selectVox)
    }

    static func make(in test: XCTestCase) async throws -> Self {
        let suite = "CapturePresetQuickAccessRowTests-\(UUID().uuidString)"
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
