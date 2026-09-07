import XCTest
import VoxboardShared
@testable import Voxboard

@MainActor
final class CapturePresetLaunchSafetyTests: XCTestCase {
    func testSamePresetDoesNotSaveOrWriteEitherSelectionKey() async throws {
        let f = try await fixture()
        f.defaults.set("inbox", forKey: CapturePresetProfileStore.selectedCaptureProfileIDKey)
        let before = f.vm.draft
        let storedBefore = try await f.store.load(id: before.id)
        XCTAssertFalse(f.vm.selectVox("journal"))
        // Observe beyond the production debounce: an accidental scheduled save
        // would alter updatedAt even though the immediate value looked equal.
        try await Task.sleep(for: .milliseconds(400))
        let storedAfter = try await f.store.load(id: before.id)
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertEqual(storedAfter, storedBefore)
        XCTAssertEqual(f.defaults.string(forKey: CapturePresetProfileStore.selectedCaptureProfileIDKey), "inbox")
        XCTAssertEqual(f.defaults.string(forKey: CapturePresetProfileStore.selectedProfileIDKey), "keyboard-sentinel")
        f.vm.isSubmitting = true
        f.vm.errorMessage = "Keep existing error"
        XCTAssertFalse(f.vm.selectVox("journal"))
        XCTAssertEqual(f.vm.errorMessage, "Keep existing error")
        XCTAssertEqual(f.vm.draft, before)
        f.vm.isSubmitting = false
    }

    func testDifferentSelectionKeepsContentAssetsAndIdentityButClearsRouteAndPrivacy() async throws {
        let f = try await fixture()
        let before = f.vm.draft
        XCTAssertTrue(f.vm.selectVox("inbox"))
        XCTAssertEqual(f.vm.draft.id, before.id)
        XCTAssertEqual(f.vm.draft.requestID, before.requestID)
        XCTAssertEqual(f.vm.draft.text, before.text)
        XCTAssertEqual(f.vm.draft.additionalPayloads, before.additionalPayloads)
        XCTAssertEqual(f.vm.draft.captureStartedAt, before.captureStartedAt)
        XCTAssertNil(f.vm.draft.destinationID)
        XCTAssertNil(f.vm.draft.relativeNotePathOverride)
        XCTAssertNil(f.vm.draft.entryTemplateID)
        XCTAssertNil(f.vm.draft.placementOverride)
        XCTAssertNil(f.vm.draft.voxProfileSnapshot)
        XCTAssertNil(f.vm.draft.locationOutcome)
        XCTAssertNil(f.vm.draft.locationDecisionOverride)
        XCTAssertEqual(f.defaults.string(forKey: CapturePresetProfileStore.selectedProfileIDKey), "keyboard-sentinel")
    }

    func testSamePresetDoesNotReplaceExplicitDefaultsOperation() async throws {
        let f = try await fixture()
        let profile = f.vm.draft.voxProfileSnapshot
        XCTAssertFalse(f.vm.selectVox("journal"))
        XCTAssertTrue(f.vm.hasAnyRouteOverride)
        f.vm.useVoxRouteDefaults()
        XCTAssertFalse(f.vm.hasAnyRouteOverride)
        XCTAssertEqual(f.vm.draft.voxProfileSnapshot, profile)
    }

    func testStaleMenuSelectionRechecksDefaultsRatherThanCachedProfiles() async throws {
        let f = try await fixture()
        let before = f.vm.draft
        try f.disableInbox()
        XCTAssertTrue(f.vm.voxProfiles.contains(where: { $0.id == "inbox" }))
        XCTAssertFalse(f.vm.selectVox("inbox"))
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertNotNil(f.vm.errorMessage)
        f.defaults.set(Data("[]".utf8), forKey: CapturePresetProfileStore.profilesKey)
        f.vm.refreshVoxProfiles()
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertNil(f.vm.selectedVoxProfile)
        XCTAssertFalse(f.vm.canSubmit)
    }

    func testUnavailableExplicitLinksDoNotPartiallyMutateSourceOrInput() async throws {
        let f = try await fixture()
        for incoming in [
            CaptureDeepLinkDraft(text: "Incoming", voxID: "deleted", requestedInput: .voice, source: .widget),
            CaptureDeepLinkDraft(text: "Incoming", destinationID: UUID(), voxID: "inbox", requestedInput: .camera, source: .widget),
        ] {
            let before = f.vm.draft
            let input = f.vm.requestedInput
            await f.vm.handleDeepLink(.openComposer(incoming))
            XCTAssertEqual(f.vm.draft, before)
            XCTAssertEqual(f.vm.requestedInput, input)
            XCTAssertNil(f.vm.pendingPresetSwitch)
            XCTAssertNotNil(f.vm.errorMessage)
        }
        try f.disableInbox()
        let before = f.vm.draft
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertEqual(f.vm.requestedInput, .files)
        XCTAssertNil(f.vm.pendingPresetSwitch)
    }

    func testNonemptyWidgetLaunchKeepsWholeValuePendingAndCancelPreservesDraftAndInput() async throws {
        let f = try await fixture()
        let before = f.vm.draft
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        let pending = try XCTUnwrap(f.vm.pendingPresetSwitch)
        XCTAssertEqual(pending.incoming, f.incoming)
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertEqual(f.vm.requestedInput, .files)
        XCTAssertEqual(f.defaults.string(forKey: CapturePresetProfileStore.selectedCaptureProfileIDKey), "journal")
        f.vm.cancelPresetSwitch(id: pending.id)
        XCTAssertNil(f.vm.pendingPresetSwitch)
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertEqual(f.vm.requestedInput, .files)
        let persisted = try await f.store.load(id: before.id)
        XCTAssertEqual(persisted, before)
        let didApply = await f.vm.confirmPresetSwitch(id: pending.id)
        XCTAssertFalse(didApply)
    }

    func testAcceptanceAppliesOnceWithIncomingProvenanceAndInputAfterDurableSave() async throws {
        let f = try await fixture()
        let before = f.vm.draft
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        let pending = try XCTUnwrap(f.vm.pendingPresetSwitch)
        let vm = f.vm
        async let first = vm.confirmPresetSwitch(id: pending.id)
        async let duplicate = vm.confirmPresetSwitch(id: pending.id)
        let results = await [first, duplicate]
        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertNil(f.vm.pendingPresetSwitch)
        XCTAssertEqual(f.vm.draft.id, before.id)
        XCTAssertEqual(f.vm.draft.requestID, before.requestID)
        XCTAssertEqual(f.vm.draft.text, before.text + "\n\nIncoming")
        XCTAssertEqual(f.vm.draft.additionalPayloads, before.additionalPayloads + [.url(f.incoming.url!, title: nil)])
        XCTAssertEqual(f.vm.draft.voxID, "inbox")
        XCTAssertEqual(f.vm.draft.destinationID, f.destinationID)
        XCTAssertEqual(f.vm.requestedInput, .camera)
        XCTAssertEqual(f.vm.draft.captureSource, .widget)
        XCTAssertNil(f.vm.draft.locationOutcome)
        XCTAssertNil(f.vm.draft.voxProfileSnapshot)
        let persisted = try await f.store.load(id: f.vm.draft.id)
        XCTAssertEqual(persisted, f.vm.draft)
        XCTAssertEqual(try f.vm.draft.makeRequest(source: .app).source, .widget)
        XCTAssertEqual(f.defaults.string(forKey: CapturePresetProfileStore.selectedProfileIDKey), "keyboard-sentinel")
    }

    func testTypingAndAutosaveWhileDecidingKeepLatestContent() async throws {
        let f = try await fixture()
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        let pending = try XCTUnwrap(f.vm.pendingPresetSwitch)
        f.vm.draft.text += "\nTyped later"
        f.vm.draft.additionalPayloads.append(.text("Added later"))
        await f.vm.saveDraftNow()
        let before = f.vm.draft
        let didApply = await f.vm.confirmPresetSwitch(id: pending.id)
        XCTAssertTrue(didApply)
        XCTAssertEqual(f.vm.draft.text, before.text + "\n\nIncoming")
        XCTAssertEqual(f.vm.draft.additionalPayloads.count, before.additionalPayloads.count + 1)
    }

    func testInterveningDraftRequestRouteOrInputInvalidatesAcceptance() async throws {
        let f = try await fixture()
        let original = f.vm.draft
        let changes: [(QuickCaptureViewModel) -> Void] = [
            { $0.draft.id = UUID() }, { $0.draft.requestID = UUID() },
            { $0.draft.selectVox("inbox") }, { $0.requestedInput = .scan },
        ]
        for change in changes {
            f.vm.draft = original
            f.vm.requestedInput = .files
            await f.vm.handleDeepLink(.openComposer(f.incoming))
            let pending = try XCTUnwrap(f.vm.pendingPresetSwitch)
            change(f.vm)
            let changed = f.vm.draft
            let input = f.vm.requestedInput
            let didApply = await f.vm.confirmPresetSwitch(id: pending.id)
            XCTAssertFalse(didApply)
            XCTAssertEqual(f.vm.draft, changed)
            XCTAssertEqual(f.vm.requestedInput, input)
            XCTAssertNil(f.vm.pendingPresetSwitch)
        }
    }

    func testAcceptanceRevalidatesDisabledDeletedPresetAndDestination() async throws {
        for mutation in 0..<3 {
            let f = try await fixture()
            let before = f.vm.draft
            await f.vm.handleDeepLink(.openComposer(f.incoming))
            let pending = try XCTUnwrap(f.vm.pendingPresetSwitch)
            if mutation == 0 {
                try f.disableInbox()
            } else if mutation == 1 {
                f.defaults.set(try JSONEncoder().encode([f.presets[0]]), forKey: CapturePresetProfileStore.profilesKey)
            } else {
                try await CaptureLibraryStore(fileURL: f.libraryURL).save(CaptureLibraryEnvelope())
            }
            let didApply = await f.vm.confirmPresetSwitch(id: pending.id)
            XCTAssertFalse(didApply)
            XCTAssertEqual(f.vm.draft, before)
            XCTAssertEqual(f.vm.requestedInput, .files)
            XCTAssertNotNil(f.vm.errorMessage)
        }
    }

    func testEmptyDraftLaunchIsOneTapAndSamePresetDoesNotResetOneOffOverrides() async throws {
        let f = try await fixture()
        f.vm.draft.text = " \n"
        f.vm.draft.additionalPayloads = []
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        XCTAssertNil(f.vm.pendingPresetSwitch)
        XCTAssertEqual(f.vm.draft.voxID, "inbox")
        XCTAssertEqual(f.vm.requestedInput, .camera)
        f.vm.draft.relativeNotePathOverride = "Same.md"
        f.vm.draft.placementOverride = .prepend
        f.vm.draft.voxProfileSnapshot = f.presets[1].captureProfile
        let before = f.vm.draft
        await f.vm.handleDeepLink(.openComposer(CaptureDeepLinkDraft(voxID: "inbox", source: .widget)))
        XCTAssertNil(f.vm.pendingPresetSwitch)
        XCTAssertEqual(f.vm.draft.relativeNotePathOverride, before.relativeNotePathOverride)
        XCTAssertEqual(f.vm.draft.placementOverride, before.placementOverride)
        XCTAssertEqual(f.vm.draft.voxProfileSnapshot, before.voxProfileSnapshot)
        XCTAssertEqual(f.vm.draft.text, before.text)
    }

    func testColdSamePresetLaunchKeepsOneOffRouteAndPrivacy() async throws {
        let f = try await fixture(load: false)
        let savedDrafts = try await f.store.loadAll()
        let stored = try XCTUnwrap(savedDrafts.first)
        await f.vm.handleDeepLink(.openComposer(CaptureDeepLinkDraft(voxID: "journal", source: .widget)))
        XCTAssertNil(f.vm.pendingPresetSwitch)
        XCTAssertEqual(f.vm.draft.id, stored.id)
        XCTAssertEqual(f.vm.draft.requestID, stored.requestID)
        XCTAssertEqual(f.vm.draft.destinationSelectionMode, .explicit)
        XCTAssertEqual(f.vm.draft.destinationID, stored.destinationID)
        XCTAssertEqual(f.vm.draft.relativeNotePathOverride, stored.relativeNotePathOverride)
        XCTAssertEqual(f.vm.draft.entryTemplateID, stored.entryTemplateID)
        XCTAssertEqual(f.vm.draft.placementOverride, stored.placementOverride)
        XCTAssertEqual(f.vm.draft.voxProfileSnapshot, stored.voxProfileSnapshot)
        XCTAssertEqual(f.vm.draft.locationOutcome, stored.locationOutcome)
        XCTAssertEqual(f.vm.draft.captureSource, .widget)
    }

    func testColdLoadRaceRestoresDraftBeforeDecidingAndNeverLosesIncomingValue() async throws {
        let f = try await fixture(load: false)
        let vm = f.vm
        let incoming = f.incoming
        async let load: Void = vm.load()
        async let launch: Void = vm.handleDeepLink(.openComposer(incoming))
        _ = await (load, launch)
        XCTAssertEqual(f.vm.draft.text, "Original")
        XCTAssertEqual(f.vm.draft.relativeNotePathOverride, "One-off.md")
        XCTAssertEqual(f.vm.draft.destinationSelectionMode, .explicit)
        XCTAssertEqual(f.vm.pendingPresetSwitch?.incoming, f.incoming)
        XCTAssertEqual(f.vm.draft.captureSource, .fileImport)
        XCTAssertNil(f.vm.requestedInput)
    }

    func testBusyFlagsBlockEveryRouteMutationAndLaunchWithoutMountedUI() async throws {
        let f = try await fixture()
        let host = HostOwnership()
        f.vm.configureCaptureRouteOwnership { host.busy }
        let flags: [(Bool) -> Void] = [
            { f.vm.isSubmitting = $0 }, { f.vm.isDescribingImages = $0 },
            { f.vm.isResolvingLocation = $0 }, { f.vm.isProcessingMedia = $0 },
            { host.busy = $0 },
        ]
        for setBusy in flags {
            setBusy(true)
            let before = f.vm.draft
            XCTAssertFalse(f.vm.canChangeCaptureRoute)
            XCTAssertFalse(f.vm.selectVox("inbox"))
            f.vm.selectDestination(f.secondDestinationID)
            f.vm.useVoxRouteDefaults()
            f.vm.clearRouteOverrides()
            f.vm.setPlacementOverride(.append)
            f.vm.setEntryTemplateOverride(nil)
            await f.vm.setOneOffNote(url: f.root.appendingPathComponent("Other.md"))
            await f.vm.clearDraft()
            await f.vm.submit()
            await f.vm.handleDeepLink(.openComposer(f.incoming))
            XCTAssertEqual(f.vm.draft, before)
            XCTAssertEqual(f.vm.requestedInput, .files)
            XCTAssertNil(f.vm.pendingPresetSwitch)
            XCTAssertNil(f.vm.beginCaptureRouteOperation())
            setBusy(false)
        }
        XCTAssertTrue(f.vm.canChangeCaptureRoute)
    }

    func testLiveTranscriptAndLocationDecisionOwnTheRoute() async throws {
        let f = try await fixture()
        await f.vm.updateLiveRecordedTranscript(finalizedText: "", volatileText: "Recording")
        let preview = f.vm.draft
        XCTAssertFalse(f.vm.canChangeCaptureRoute)
        XCTAssertFalse(f.vm.selectVox("inbox"))
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        XCTAssertEqual(f.vm.draft, preview)
        XCTAssertEqual(f.vm.requestedInput, .files)
        await f.vm.cancelLiveRecordedTranscript()
        f.vm.locationDecision = CaptureLocationDecision(reason: .timeout, attemptedAt: Date(), presetID: "journal")
        XCTAssertFalse(f.vm.canChangeCaptureRoute)
        XCTAssertNil(f.vm.beginCaptureRouteOperation())
        XCTAssertFalse(f.vm.selectVox("inbox"))
    }

    func testImportCaptureLeaseGuardsAppLaunchBeforeTranscriptionStarts() async throws {
        let f = try await fixture()
        let queue = RecordingJobQueue(store: RecordingJobStore(
            rootDirectoryURL: f.root.appendingPathComponent("queue"),
            coordinator: ProcessLocalCaptureFileCoordinator()
        )) { _, _, _ in RecordingJobExecutionResult() }
        f.vm.configureCaptureRouteOwnership { queue.isCaptureActive || queue.isProcessing }
        let lease = queue.beginCaptureLease()
        XCTAssertFalse(queue.isProcessing)
        XCTAssertNil(queue.activeJobID)
        let before = f.vm.draft
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertEqual(f.vm.requestedInput, .files)
        XCTAssertFalse(f.vm.selectVox("inbox"))
        XCTAssertNil(f.vm.pendingPresetSwitch)
        queue.endCaptureLease(lease)
    }

    func testHostBecomingBusyAfterConfirmationRejectsAcceptance() async throws {
        let f = try await fixture()
        let host = HostOwnership()
        f.vm.configureCaptureRouteOwnership { host.busy }
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        let pending = try XCTUnwrap(f.vm.pendingPresetSwitch)
        let before = f.vm.draft
        host.busy = true
        let didApply = await f.vm.confirmPresetSwitch(id: pending.id)
        XCTAssertFalse(didApply)
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertEqual(f.vm.requestedInput, .files)
    }

    func testAsyncStartLeaseAndPendingDecisionBlockNewStarts() async throws {
        let f = try await fixture()
        let token = try XCTUnwrap(f.vm.beginCaptureRouteOperation())
        XCTAssertNil(f.vm.beginCaptureRouteOperation())
        f.vm.endCaptureRouteOperation(UUID())
        XCTAssertFalse(f.vm.canChangeCaptureRoute)
        let before = f.vm.draft
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        XCTAssertEqual(f.vm.draft, before)
        f.vm.endCaptureRouteOperation(token)
        XCTAssertTrue(f.vm.canChangeCaptureRoute)
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        XCTAssertNotNil(f.vm.pendingPresetSwitch)
        XCTAssertNil(f.vm.beginCaptureRouteOperation())
        XCTAssertFalse(f.vm.selectVox("inbox"))
    }

    func testSecondLaunchDoesNotReplacePendingIncomingValue() async throws {
        let f = try await fixture()
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        let pending = f.vm.pendingPresetSwitch
        await f.vm.handleDeepLink(.openComposer(CaptureDeepLinkDraft(text: "Second", voxID: "journal")))
        XCTAssertEqual(f.vm.pendingPresetSwitch, pending)
        XCTAssertEqual(f.vm.draft.text, "Original")
        XCTAssertEqual(f.vm.requestedInput, .files)
    }

    func testCombinedTextBudgetRejectsBeforeSourceRouteOrInputMutation() async throws {
        let f = try await fixture()
        f.vm.draft.text = String(repeating: "x", count: CaptureInputLimits.maximumTextCharacters)
        let before = f.vm.draft
        await f.vm.handleDeepLink(.openComposer(f.incoming))
        XCTAssertEqual(f.vm.draft, before)
        XCTAssertEqual(f.vm.requestedInput, .files)
        XCTAssertNil(f.vm.pendingPresetSwitch)
        XCTAssertNotNil(f.vm.errorMessage)
    }

    func testStorageUnavailableDoesNotApplyIncomingToAllocatedDraft() async {
        let vm = QuickCaptureViewModel(captureRootURL: nil, defaults: nil)
        let before = vm.draft
        await vm.handleDeepLink(.openComposer(CaptureDeepLinkDraft(text: "Incoming", voxID: "missing", source: .widget)))
        XCTAssertEqual(vm.draft, before)
        XCTAssertNil(vm.requestedInput)
        XCTAssertNotNil(vm.errorMessage)
    }

    private func fixture(load: Bool = true) async throws -> Fixture {
        let suiteName = "CapturePresetLaunchSafetyTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destinationID = UUID()
        let secondDestinationID = UUID()
        let template = CaptureEntryTemplate(name: "One-off")
        var journal = CapturePresetStore.makeCustomFlow()
        journal.id = "journal"
        journal.name = "Journal"
        journal.captureDestinationID = destinationID
        var inbox = CapturePresetStore.makeCustomFlow()
        inbox.id = "inbox"
        inbox.name = "Inbox"
        inbox.captureDestinationID = secondDestinationID
        let presets = [journal, inbox]
        defaults.set(try JSONEncoder().encode(presets), forKey: CapturePresetProfileStore.profilesKey)
        defaults.set(1, forKey: CapturePresetProfileStore.ownedRouteMigrationVersionKey)
        defaults.set("journal", forKey: CapturePresetProfileStore.selectedCaptureProfileIDKey)
        defaults.set("keyboard-sentinel", forKey: CapturePresetProfileStore.selectedProfileIDKey)
        let libraryURL = root.appendingPathComponent(AppConstants.captureLibraryFilename)
        let destinations = [destinationID, secondDestinationID].map { id in
            CaptureDestination(id: id, name: id.uuidString, rootBookmark: Data([1]), rootName: "Vault", noteTarget: .newNote(pathTemplate: "{date}.md"))
        }
        try await CaptureLibraryStore(fileURL: libraryURL).save(CaptureLibraryEnvelope(
            destinations: destinations, defaultDestinationID: destinationID, entryTemplates: [template]
        ))
        let asset = try CaptureAssetReference(relativePath: "image.jpg", originalFilename: "image.jpg", contentTypeIdentifier: "public.jpeg")
        let draft = CaptureDraft(
            text: "Original", voxID: "journal", voxProfileSnapshot: journal.captureProfile,
            destinationID: destinationID, captureSource: .fileImport,
            locationOutcome: .unavailable(.timeout, attemptedAt: Date(timeIntervalSince1970: 100)),
            locationDecisionOverride: .sendWithoutLocation,
            placementOverride: .prepend, relativeNotePathOverride: "One-off.md", entryTemplateID: template.id,
            additionalPayloads: [.image(asset, altText: "Keep")]
        )
        let store = CaptureDraftStore(rootDirectoryURL: root)
        try await store.save(draft)
        let vm = QuickCaptureViewModel(captureRootURL: root, defaults: defaults)
        addTeardownBlock { @MainActor in
            _ = await vm.flushDraftForTermination()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: root)
        }
        if load {
            await vm.load()
            vm.requestedInput = .files
            XCTAssertNil(vm.errorMessage)
        }
        return Fixture(vm: vm, store: store, defaults: defaults, root: root, libraryURL: libraryURL,
                       presets: presets, destinationID: destinationID, secondDestinationID: secondDestinationID)
    }

    private final class HostOwnership { var busy = false }

    private struct Fixture {
        let vm: QuickCaptureViewModel
        let store: CaptureDraftStore
        let defaults: UserDefaults
        let root: URL
        let libraryURL: URL
        let presets: [CapturePreset]
        let destinationID: UUID
        let secondDestinationID: UUID
        var incoming: CaptureDeepLinkDraft {
            CaptureDeepLinkDraft(text: "Incoming", url: URL(string: "https://example.com/incoming"),
                                 destinationID: destinationID, voxID: "inbox", requestedInput: .camera, source: .widget)
        }
        func disableInbox() throws {
            var changed = presets
            changed[1].isEnabled = false
            defaults.set(try JSONEncoder().encode(changed), forKey: CapturePresetProfileStore.profilesKey)
        }
    }
}
