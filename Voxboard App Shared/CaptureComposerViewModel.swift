import Foundation
import Observation
import UniformTypeIdentifiers
import VoxboardShared
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
@Observable
final class QuickCaptureViewModel {
    var draft = CaptureDraft()
    var destinations: [CaptureDestination] = []
    var entryTemplates: [CaptureEntryTemplate] = []
    var voxProfiles: [CapturePresetProfile]
    var defaultDestinationID: UUID?
    var isLoading = false
    var isSubmitting = false
    var isDescribingImages = false
    var isResolvingLocation = false
    /// Host media work writes this synchronously, not through a view onChange.
    /// It remains visible to App-level launches even while Capture is unmounted.
    var isProcessingMedia = false
    private(set) var pendingPresetSwitch: CapturePresetSwitchConfirmation?
    private var routeOperationIDs = Set<UUID>()
    private var hostOwnsCaptureRoute: @MainActor () -> Bool = { false }
    private var hostBlocksCapturePresetSelection: @MainActor () -> Bool = { false }
    /// Queued Capture retries and inbox deliveries require paid access
    /// (docs/launch/hard-paywall). Read once per drain from the shared
    /// entitlement mirror; injectable for tests.
    @ObservationIgnored private let hasPaidCaptureAccess: @MainActor () -> Bool
    var errorMessage: String?
    var lastReceipt: CaptureReceipt?
    /// Set when Send held the capture because its vault was unreachable.
    var lastHeldForVaultRequestID: UUID?
    var failedInboxCount = 0
    var historyRecords: [CaptureHistoryRecord] = []
    /// Live Notes: the vault file this composer is editing once its first
    /// words were saved. `nil` while the composer holds an unsaved note.
    var liveNote: LiveNoteSession?
    /// The note New note just closed; drives the Reopen toast.
    var lastClosedNote: ClosedLiveNote?
    /// When on, the composer saves into the preset's file by itself and
    /// keeps editing it (iOS). Off keeps the classic Send-and-clear flow.
    var liveNotesEnabled = false
    /// The first save is waiting because the vault folder is unreachable.
    var liveNoteFirstSaveBlocked = false
    /// Append presets: the entry this capture added inside the whole file,
    /// highlighted with "JUST ADDED" until the note is closed.
    var liveNoteHighlightedEntry: String?
    @ObservationIgnored private var autoFirstSaveTask: Task<Void, Never>?
    /// Live preview embeds: the open note's vault, kept in security scope
    /// while the note is open, and resolved embed files by target.
    @ObservationIgnored private var embedScopedRoot: (destinationID: UUID, url: URL)?
    @ObservationIgnored private var embedURLCache: [String: URL?] = [:]
    /// Optional Library origin detail per request ID (for example the Mac
    /// Quick Capture panel). Stored on the history record as `sourceDetail`.
    @ObservationIgnored var historySourceDetails: [UUID: String] = [:]
    var requestedInput: CaptureRequestedInput?
    var needsCaptureUnlock = false
    /// Non-nil keeps the draft intact while the foreground UI asks how to
    /// handle this origin-time unavailable result.
    var locationDecision: CaptureLocationDecision?
    var inboxLocationDecision: CaptureInboxLocationDecision?

    private let captureRootURL: URL?
    private let defaults: UserDefaults?
    private let defaultCaptureSource: CaptureSource
    private let libraryStore: CaptureLibraryStore?
    private let draftStore: CaptureDraftStore?
    private let historyStore: CaptureHistoryStore?
    private let pipeline: CapturePipeline
    private let urlDeliveryCoordinator: URLDeliveryCoordinator
    private let requestProcessor: CapturePresetRequestProcessor
    private let locationProvider: any CaptureLocationOutcomeProviding
    private var pendingDraftSave: Task<Void, Never>?
    private var initialLoadTask: Task<Bool, Never>?
    private var hasLoaded = false
    private var liveRecordedTranscriptPreview: LiveTranscriptDraftPreview?
    private var liveRecordedTranscriptSessionID: UUID?
    /// UTF-16 offset of the writer's cursor when the current recording
    /// started; its transcript is inserted there instead of at the end.
    private var recordedTranscriptInsertionOffset: Int?
    /// Where the composer caret belongs after the latest transcript render or
    /// commit (just past the spoken words). Observed by the iOS composer.
    private(set) var recordedTranscriptCaretOffset: Int?
    private var invalidatedLiveTranscriptSessionIDs = Set<UUID>()
    private var pendingSendWithoutLocationOutcome: CaptureLocationOutcome?

    init(
        captureRootURL: URL? = AppConstants.captureDirectoryURL,
        defaultCaptureSource: CaptureSource = .app,
        defaults: UserDefaults? = AppConstants.sharedDefaults,
        pipeline: CapturePipeline = AppCapturePipeline.shared,
        requestProcessor: CapturePresetRequestProcessor = CapturePresetRequestProcessor(),
        locationProvider: (any CaptureLocationOutcomeProviding)? = nil,
        urlDeliveryCoordinator: URLDeliveryCoordinator? = nil,
        hasPaidCaptureAccess: @escaping @MainActor () -> Bool = { !UsageTracker.staticIsAtLimit }
    ) {
        self.hasPaidCaptureAccess = hasPaidCaptureAccess
        self.captureRootURL = captureRootURL
        self.defaults = defaults
        self.voxProfiles = CapturePresetProfileStore.enabledProfiles(defaults: defaults)
        self.defaultCaptureSource = defaultCaptureSource
        if let captureRootURL {
            self.libraryStore = CaptureLibraryStore(
                fileURL: captureRootURL.appendingPathComponent(AppConstants.captureLibraryFilename)
            )
            self.draftStore = CaptureDraftStore(rootDirectoryURL: captureRootURL)
            self.historyStore = CaptureHistoryStore(
                fileURL: captureRootURL.appendingPathComponent(AppConstants.captureHistoryFilename)
            )
        } else {
            self.libraryStore = nil
            self.draftStore = nil
            self.historyStore = nil
        }
        self.pipeline = pipeline
        self.urlDeliveryCoordinator = urlDeliveryCoordinator ?? URLDeliveryRuntime.coordinator
        self.requestProcessor = requestProcessor
        self.locationProvider = locationProvider ?? CaptureLocationService()
    }

    var selectedVoxProfile: CapturePresetProfile? {
        let enabled = voxProfiles.filter(\.isEnabled)
        if let voxID = draft.voxID {
            // A stale explicit selection must not silently deliver elsewhere.
            return enabled.first(where: { $0.id == voxID })
        }
        let selectedID = CapturePresetProfileStore.selectedProfileID(defaults: defaults)
        return enabled.first(where: { $0.id == selectedID }) ?? enabled.first
    }

    var effectiveDestinationID: UUID? {
        CapturePresetRouteResolver.destinationID(
            selectionMode: draft.destinationSelectionMode,
            explicitDestinationID: draft.destinationID,
            profile: selectedVoxProfile,
            destinations: destinations,
            libraryDefaultDestinationID: defaultDestinationID,
            allowsLegacyFallback: !CapturePresetProfileStore.hasOwnedRouteMigration(
                defaults: defaults
            )
        )
    }

    var selectedDestination: CaptureDestination? {
        guard let id = effectiveDestinationID else { return nil }
        return destinations.first { $0.id == id }
    }

    var selectedPresetDestination: CaptureDestination? {
        guard let id = selectedVoxProfile?.captureDestinationID else { return nil }
        return destinations.first { $0.id == id }
    }

    var hasExplicitDestinationOverride: Bool {
        draft.destinationSelectionMode == .explicit && draft.destinationID != nil
    }

    var resolvedDestinationPreview: String? {
        guard var destination = selectedDestination,
              let destinationID = effectiveDestinationID,
              let request = try? draft.makeRequest(
                source: defaultCaptureSource,
                resolvedDestinationID: destinationID,
                voxProfile: selectedVoxProfile
              ) else { return nil }
        if let override = draft.relativeNotePathOverride {
            destination.noteTarget = .existingNote(relativePath: override)
        }
        guard let relativePath = try? CapturePathPlanner().relativePath(
            for: request,
            destination: destination
        ) else { return nil }
        return destination.rootName + " / " + relativePath
    }

    var effectivePlacementLabel: String {
        switch draft.placementOverride
            ?? selectedVoxProfile?.capturePlacementOverride
            ?? selectedDestination?.placement {
        case .prepend: return String(localized: "Top")
        case .append: return String(localized: "Bottom")
        case .beneathHeading: return String(localized: "Heading")
        case nil: return String(localized: "Default")
        }
    }

    /// The placement that delivery will use for this capture.
    var effectivePlacement: CapturePlacement? {
        draft.placementOverride
            ?? selectedVoxProfile?.capturePlacementOverride
            ?? selectedDestination?.placement
    }

    /// Path-line suffix for the effective placement: the Markdown heading for
    /// a beneath-heading placement (for example `## Notes`), nil otherwise.
    var effectivePlacementDisplay: String? {
        guard case .beneathHeading(let selector, _, _) = effectivePlacement else { return nil }
        let title = selector.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        return String(repeating: "#", count: max(1, min(6, selector.level ?? 2))) + " " + title
    }

    /// True when the capture lands in one fixed existing note rather than a
    /// note created from a path template.
    var targetsExistingNote: Bool {
        if draft.relativeNotePathOverride != nil { return true }
        if case .existingNote = selectedDestination?.noteTarget { return true }
        return false
    }

    /// Spaced destination path plus the effective heading, as shown under the
    /// route pill: `Vox Notes / Meetings / 2026-11-01.md · ## Notes` or
    /// `Vox Notes / Tasks.md › ## Today`.
    var resolvedDestinationDisplayLine: String? {
        guard let preview = resolvedDestinationPreview else { return nil }
        let spaced = preview
            .components(separatedBy: " / ")
            .map { $0.split(separator: "/", omittingEmptySubsequences: true).joined(separator: " / ") }
            .joined(separator: " / ")
        guard let heading = effectivePlacementDisplay else { return spaced }
        return spaced + (targetsExistingNote ? " › " : " · ") + heading
    }

    var canSubmit: Bool {
        canChangeCaptureRoute
            && selectedVoxProfile != nil
            && selectedDestination != nil
            && draft.hasCaptureContent
    }

    struct EntryLocationTokenHint: Equatable {
        let presetDisplayName: String
    }

    /// Non-blocking hint state: the resolved entry formatting references the
    /// `{location}` token, but the preset that will deliver this capture has
    /// Current Location disabled, so the token would render empty.
    var entryLocationTokenHint: EntryLocationTokenHint? {
        let profile = draft.voxProfileSnapshot ?? selectedVoxProfile
        guard let profile,
              CaptureEntryLocationTokenSupport.needsPresetOptIn(
                library: CaptureLibraryEnvelope(
                    destinations: destinations,
                    defaultDestinationID: defaultDestinationID,
                    entryTemplates: entryTemplates
                ),
                destinationID: effectiveDestinationID,
                oneOffTemplateID: draft.entryTemplateID,
                preset: profile
              ) else { return nil }
        return EntryLocationTokenHint(presetDisplayName: profile.accessibilityName)
    }

    /// One-tap fix for `entryLocationTokenHint`: turns on origin-time location
    /// capture for the delivering preset without enabling metadata output. A
    /// journaled preset snapshot without a location outcome is updated too, so
    /// the very next Send resolves the token without changing note metadata.
    func enableEntryLocationTokenForPreset() async {
        guard requireCaptureRouteAvailable() else { return }
        let profile = draft.voxProfileSnapshot ?? selectedVoxProfile
        guard let presetID = profile?.id else { return }
        CapturePresetStore.setLocationEnabled(
            true,
            metadataOutputEnabled: false,
            presetID: presetID
        )
        refreshVoxProfiles()
        if draft.voxProfileSnapshot?.id == presetID, draft.locationOutcome == nil {
            draft.voxProfileSnapshot?.locationPolicy.isEnabled = true
            draft.voxProfileSnapshot?.locationPolicy.metadataOutputEnabled = false
            await saveDraftNow()
        }
    }

    func load() async {
        if hasLoaded { return }
        if let initialLoadTask {
            // Any waiter may resume first. Publish the barrier result here too,
            // rather than relying on the task creator's continuation ordering.
            hasLoaded = await initialLoadTask.value
            return
        }
        let task = Task { @MainActor [self] in
            await performInitialLoad()
        }
        initialLoadTask = task
        let didLoad = await task.value
        hasLoaded = didLoad
        initialLoadTask = nil
    }

    /// Performs the only destructive restoration of the observable draft.
    /// `load()` serializes all cold-launch callers around this operation so a
    /// deep link cannot race the view task and have its incoming content
    /// replaced by a second disk load.
    private func performInitialLoad() async -> Bool {
        guard let libraryStore, let draftStore else {
            errorMessage = String(localized: "Shared capture storage is unavailable. Reinstall Vox.md or verify its App Group entitlement.")
            return false
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let library = try await CapturePresetRouteLibrary.load(from: libraryStore, defaults: defaults)
            destinations = library.destinations
            entryTemplates = library.entryTemplates
            defaultDestinationID = library.defaultDestinationID
            refreshVoxProfiles()
            if let savedDraft = try await draftStore.loadAll().first {
                draft = savedDraft
            } else {
                draft = CaptureDraft(
                    voxID: CapturePresetProfileStore.selectedProfileID(defaults: defaults),
                    destinationSelectionMode: .inherited
                )
            }
            if draft.voxID == nil {
                draft.voxID = CapturePresetProfileStore.selectedProfileID(defaults: defaults)
            }
            moveDraftOffDeletedRoute()
            if draft.destinationSelectionMode == .explicit {
                if draft.destinationID == nil || !destinations.contains(where: { $0.id == draft.destinationID }) {
                    draft.useInheritedDestination()
                }
            }
            if let templateID = draft.entryTemplateID,
               !entryTemplates.contains(where: { $0.id == templateID }) {
                draft.entryTemplateID = nil
            }
            let persistedDraft = try await draftStore.save(draft)
            draft.preserveCaptureStart(from: persistedDraft)
            historyRecords = (try? await historyStore?.list()) ?? []
            errorMessage = nil
            await restoreLiveNoteIfNeeded()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refreshLibrary() async {
        guard let libraryStore else { return }
        do {
            let library = try await CapturePresetRouteLibrary.load(from: libraryStore, defaults: defaults)
            destinations = library.destinations
            entryTemplates = library.entryTemplates
            defaultDestinationID = library.defaultDestinationID
            refreshVoxProfiles()
            // A window's appearance refresh must not dismiss a rejected launch
            // error before the user sees why its explicit preset did not open.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshHistory() async {
        historyRecords = (try? await historyStore?.list()) ?? []
    }

    /// The Lock Screen "Route Today" widget reads the snapshot the history
    /// store keeps; refresh it after a delivery or a Library clear.
    nonisolated static func reloadRouteTodayWidget() {
        #if canImport(WidgetKit) && os(iOS)
        WidgetCenter.shared.reloadTimelines(ofKind: VoxboardRouteWidgetKinds.today)
        #endif
    }

    func clearHistory() async {
        do {
            try await historyStore?.clear()
            historyRecords = []
            Self.reloadRouteTodayWidget()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteHistory(requestID: UUID) async {
        do {
            try await historyStore?.remove(requestIDs: [requestID])
            historyRecords.removeAll { $0.requestID == requestID }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearDraft() async {
        guard let operation = beginCaptureRouteOperation() else { return }
        defer { endCaptureRouteOperation(operation) }
        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        liveRecordedTranscriptPreview = nil
        liveRecordedTranscriptSessionID = nil
        recordedTranscriptInsertionOffset = nil
        do {
            try await draftStore?.complete(draftID: draft.id)
            draft = CaptureDraft(
                voxID: selectedVoxProfile?.id
                    ?? CapturePresetProfileStore.selectedProfileID(defaults: defaults),
                destinationSelectionMode: .inherited
            )
            try await draftStore?.save(draft)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshVoxProfiles() {
        // Refreshing availability is not an implicit draft-selection operation.
        voxProfiles = CapturePresetProfileStore.enabledProfiles(defaults: defaults)
        moveDraftOffDeletedRoute()
    }

    /// A draft stays on its route while that route is merely disabled, so it is
    /// never silently delivered elsewhere. A route the user deleted can never
    /// deliver again, though, so the draft moves to the route Settings fell back
    /// to instead of stranding Send behind "Destination Not Configured".
    private func moveDraftOffDeletedRoute() {
        guard let voxID = draft.voxID,
              CapturePresetStore.isRetiredPreset(id: voxID, defaults: defaults) else { return }
        let selectedID = CapturePresetProfileStore.selectedProfileID(defaults: defaults)
        guard let fallback = voxProfiles.first(where: { $0.id == selectedID })?.id ?? voxProfiles.first?.id,
              fallback != voxID else { return }
        draft.selectVox(fallback)
        scheduleDraftSave()
    }

    /// App installs live readers once, before any external launch. A recorder
    /// can remain broadly busy while an immutable Preset job processes without
    /// still owning the open composer's preset selection.
    func configureCaptureRouteOwnership(
        _ isOwned: @escaping @MainActor () -> Bool,
        presetSelectionIsBlocked: (@MainActor () -> Bool)? = nil
    ) {
        hostOwnsCaptureRoute = isOwned
        hostBlocksCapturePresetSelection = presetSelectionIsBlocked ?? isOwned
    }

    private var localCaptureRouteIsOwned: Bool {
        isLoading || isSubmitting || isDescribingImages || isResolvingLocation
            || isProcessingMedia || hasLiveRecordedTranscriptPreview
            || locationDecision != nil || !routeOperationIDs.isEmpty
    }

    var isCaptureRouteOwned: Bool {
        localCaptureRouteIsOwned || hostOwnsCaptureRoute()
    }

    var canChangeCaptureRoute: Bool {
        hasLoaded && !isCaptureRouteOwned && pendingPresetSwitch == nil
    }

    /// Unlike destination overrides and Send, selecting the next preset is safe
    /// while an unrelated job processes from its immutable preset snapshot.
    var canSelectCapturePreset: Bool {
        hasLoaded && !localCaptureRouteIsOwned
            && !hostBlocksCapturePresetSelection()
            && pendingPresetSwitch == nil
    }

    @discardableResult
    func requireCaptureRouteAvailable() -> Bool {
        guard canChangeCaptureRoute else {
            errorMessage = QuickCaptureViewModelError.captureRouteBusy.localizedDescription
            return false
        }
        return true
    }

    /// Acquire before an async permission/import/start boundary. Release with
    /// defer; tokens cannot accidentally release another operation's ownership.
    func beginCaptureRouteOperation() -> UUID? {
        guard requireCaptureRouteAvailable() else { return nil }
        return holdCaptureRoute()
    }

    func endCaptureRouteOperation(_ id: UUID) {
        routeOperationIDs.remove(id)
    }

    private func holdCaptureRoute() -> UUID {
        let id = UUID()
        routeOperationIDs.insert(id)
        return id
    }

    /// Returns true only for a real change. Same-ID taps do not save, publish,
    /// reset overrides or write either global selection preference.
    @discardableResult
    func selectVox(_ id: String) -> Bool {
        let profiles = CapturePresetProfileStore.enabledProfiles(defaults: defaults)
        guard profiles.contains(where: { $0.id == id }) else {
            errorMessage = QuickCaptureViewModelError.unknownVox.localizedDescription
            return false
        }
        guard draft.voxID != id else { return false }
        guard canSelectCapturePreset else {
            errorMessage = QuickCaptureViewModelError.captureRouteBusy.localizedDescription
            return false
        }
        voxProfiles = profiles
        // The open Live Note belongs to the previous preset: close it and
        // start a blank note in the new one.
        closeLiveNoteForPresetSwitch()
        draft.selectVox(id)
        CapturePresetProfileStore.selectCaptureProfile(id: id, defaults: defaults)
        scheduleDraftSave()
        return true
    }

    func selectDestination(_ id: UUID) {
        guard requireCaptureRouteAvailable(), destinations.contains(where: { $0.id == id }) else { return }
        guard draft.destinationID != id || draft.destinationSelectionMode != .explicit else { return }
        draft.selectDestination(id)
        scheduleDraftSave()
    }

    /// Saves the reusable destination owned by the active Capture Preset and
    /// refreshes routing for the current capture without discarding one-off overrides.
    func saveSelectedPresetDestination(_ destination: CaptureDestination) async throws {
        guard let operation = beginCaptureRouteOperation() else {
            throw QuickCaptureViewModelError.captureRouteBusy
        }
        defer { endCaptureRouteOperation(operation) }
        guard let libraryStore,
              let defaults = defaults,
              let presetID = selectedVoxProfile?.id else {
            throw QuickCaptureViewModelError.storageUnavailable
        }

        var presets = CapturePresetStore.loadFlows(defaults: defaults)
        guard let presetIndex = presets.firstIndex(where: { $0.id == presetID }) else {
            throw QuickCaptureViewModelError.unknownVox
        }

        let library = try await libraryStore.update { library in
            if let index = library.destinations.firstIndex(where: { $0.id == destination.id }) {
                library.destinations[index] = destination
            } else {
                library.destinations.append(destination)
            }
            if library.defaultDestinationID == nil {
                library.defaultDestinationID = destination.id
            }
        }

        let previousDestinationID = presets[presetIndex].captureDestinationID
        if previousDestinationID != destination.id {
            CapturePresetStore.retireOwnedRoute(previousDestinationID, defaults: defaults)
        }
        presets[presetIndex].captureDestinationID = destination.id
        presets[presetIndex].captureEntryTemplateID = nil
        presets[presetIndex].capturePlacementOverride = nil
        CapturePresetStore.saveFlows(presets, defaults: defaults)

        destinations = library.destinations
        entryTemplates = library.entryTemplates
        defaultDestinationID = library.defaultDestinationID
        refreshVoxProfiles()
        errorMessage = nil
    }

    /// The first-note shortcut uses the same durable preset route as the full
    /// editor. Choosing a folder never writes a note or changes the user's draft.
    func setUpFirstNoteFolder(_ url: URL) async throws {
        guard selectedDestination == nil else { return }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = .withSecurityScope
        #else
        let options: URL.BookmarkCreationOptions = .minimalBookmark
        #endif
        let bookmark = try url.bookmarkData(options: options,
                                           includingResourceValuesForKeys: nil, relativeTo: nil)
        try await saveSelectedPresetDestination(CaptureDestination(
            name: selectedVoxProfile?.accessibilityName ?? url.lastPathComponent,
            rootBookmark: bookmark, rootName: url.lastPathComponent,
            noteTarget: .newNote(pathTemplate: "{date}.md")
        ))
    }

    func useVoxRouteDefaults() {
        guard requireCaptureRouteAvailable(), hasAnyRouteOverride else { return }
        draft.useInheritedDestination()
        draft.placementOverride = nil
        draft.entryTemplateID = nil
        scheduleDraftSave()
    }

    func setEntryTemplateOverride(_ id: UUID?) {
        guard requireCaptureRouteAvailable(), draft.entryTemplateID != id,
              id == nil || entryTemplates.contains(where: { $0.id == id }) else { return }
        draft.entryTemplateID = id
        scheduleDraftSave()
    }

    func setPlacementOverride(_ placement: CapturePlacement?) {
        guard requireCaptureRouteAvailable(), draft.placementOverride != placement else { return }
        draft.placementOverride = placement
        scheduleDraftSave()
    }

    func clearRouteOverrides() {
        guard requireCaptureRouteAvailable(), hasAnyRouteOverride else { return }
        draft.relativeNotePathOverride = nil
        draft.placementOverride = nil
        draft.entryTemplateID = nil
        scheduleDraftSave()
    }

    var hasAnyRouteOverride: Bool {
        hasExplicitDestinationOverride
            || draft.relativeNotePathOverride != nil
            || draft.placementOverride != nil
            || draft.entryTemplateID != nil
    }

    func selectedRootURL() -> URL? {
        guard let destination = selectedDestination else { return nil }
        return try? Self.resolveRootURL(for: destination)
    }

    func setOneOffNote(url: URL) async {
        guard let operation = beginCaptureRouteOperation() else { return }
        defer { endCaptureRouteOperation(operation) }
        guard let destination = selectedDestination else {
            errorMessage = QuickCaptureViewModelError.unknownDestination.localizedDescription
            return
        }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            guard url.pathExtension.lowercased() == "md" else {
                throw QuickCaptureViewModelError.noteMustBeMarkdown
            }
            let rootURL = try Self.resolveRootURL(for: destination)
            let didAccessRoot = rootURL.startAccessingSecurityScopedResource()
            defer { if didAccessRoot { rootURL.stopAccessingSecurityScopedResource() } }
            let relativePath: String
            do {
                relativePath = try CapturePathValidation.relativePath(
                    for: url,
                    containedIn: rootURL
                )
            } catch {
                throw QuickCaptureViewModelError.noteOutsideDestination
            }
            draft.relativeNotePathOverride = relativePath
            try await persistDurableDraft()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func scheduleDraftSave() {
        pendingDraftSave?.cancel()
        pendingDraftSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let self else { return }
            await self.saveDraftNow()
        }
        liveNoteTextDidChange()
    }

    func saveDraftNow() async {
        do {
            try await persistDurableDraft()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Flushes the current durable state before macOS termination. Unlike the
    /// regular UI save helper, failure is returned to the app delegate so quit
    /// can be cancelled instead of silently discarding final edits.
    func flushDraftForTermination() async -> Bool {
        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        do {
            try await persistDurableDraft()
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func persistDurableDraft() async throws {
        guard let draftStore else {
            throw QuickCaptureViewModelError.storageUnavailable
        }
        try await saveDurableDraft(using: draftStore)
    }

    private func saveDurableDraft(using draftStore: CaptureDraftStore) async throws {
        let savedAt = Date()
        var durableDraft = draft
        if var preview = liveRecordedTranscriptPreview {
            // Volatile Speech text is UI-only until the full transcription is
            // committed. Any route, attachment, window, deep-link, or quit save
            // must omit it until the final transcript is committed.
            durableDraft.text = preview.cancel(in: durableDraft.text)
        }
        durableDraft.updatedAt = savedAt
        durableDraft.beginCaptureIfNeeded(at: savedAt)
        let persistedDraft = try await draftStore.save(durableDraft, now: savedAt)
        draft.preserveCaptureStart(from: persistedDraft)
        draft.updatedAt = savedAt
    }

    var hasLiveRecordedTranscriptPreview: Bool {
        liveRecordedTranscriptPreview != nil
    }

    /// Call when a recording starts: its transcript lands at this UTF-16
    /// offset (the composer cursor) joined with a space, not a new paragraph.
    /// `nil` appends to the end of the draft.
    func beginRecordedTranscriptInsertion(atUTF16Offset offset: Int?) {
        guard liveRecordedTranscriptPreview == nil else { return }
        recordedTranscriptInsertionOffset = offset
        // Seed the caret where the words will land, so a cursor already
        // sitting there rides along to the end of the first spoken words.
        recordedTranscriptCaretOffset = offset ?? (draft.text as NSString).length
    }

    /// The writer typed or moved the cursor while recording. Words already
    /// spoken stay where they are as ordinary text; the next words land at
    /// `offset` (UTF-16, in the current draft), so speech follows the cursor.
    func moveRecordedTranscriptInsertion(toUTF16Offset offset: Int) {
        if var preview = liveRecordedTranscriptPreview {
            preview.moveInsertion(toUTF16Offset: offset, in: draft.text)
            liveRecordedTranscriptPreview = preview
            recordedTranscriptCaretOffset = preview.caretOffset
        } else {
            recordedTranscriptInsertionOffset = offset
            recordedTranscriptCaretOffset = offset
        }
    }

    func updateLiveRecordedTranscript(
        sessionID: UUID? = nil,
        finalizedText: String,
        volatileText: String?
    ) async {
        if let sessionID {
            guard !invalidatedLiveTranscriptSessionIDs.contains(sessionID) else { return }
            if let activeSessionID = liveRecordedTranscriptSessionID,
               activeSessionID != sessionID { return }
        }
        await load()
        // Loading may suspend while the recorder is stopped. Revalidate before
        // mutating so a stale Speech callback cannot enter a later session.
        if let sessionID {
            guard !invalidatedLiveTranscriptSessionIDs.contains(sessionID) else { return }
            if let activeSessionID = liveRecordedTranscriptSessionID,
               activeSessionID != sessionID { return }
            liveRecordedTranscriptSessionID = sessionID
        }
        var preview = liveRecordedTranscriptPreview
            ?? LiveTranscriptDraftPreview(insertionOffset: recordedTranscriptInsertionOffset)
        let updatedText = preview.render(
            finalizedText: finalizedText,
            volatileText: volatileText,
            in: draft.text
        )
        guard updatedText.count <= CaptureInputLimits.maximumTextCharacters else {
            errorMessage = QuickCaptureViewModelError.textTooLarge.localizedDescription
            return
        }

        // Keep volatile recognition in memory. The durable draft is saved only
        // when Apple Speech finalizes, so a crash cannot persist tentative words.
        liveRecordedTranscriptPreview = preview
        draft.text = updatedText
        draft.updatedAt = Date()
        recordedTranscriptCaretOffset = preview.caretOffset
        // Live Notes: spoken words reach the open file as they arrive; the
        // durable draft still waits for the final transcript.
        liveNoteTextDidChange()
    }

    /// Adds a recording-action line (timestamp marker, empty task) to the
    /// draft. While a live transcript preview is rendering, the line goes just
    /// ahead of the volatile Speech block so the preview can still be replaced.
    func insertRecordingActionLine(_ line: String) {
        let updated: String
        if var preview = liveRecordedTranscriptPreview {
            updated = preview.insertLine(line, in: draft.text)
            guard updated.count <= CaptureInputLimits.maximumTextCharacters else {
                errorMessage = QuickCaptureViewModelError.textTooLarge.localizedDescription
                return
            }
            liveRecordedTranscriptPreview = preview
            recordedTranscriptCaretOffset = preview.caretOffset
        } else {
            // No speech yet: the line goes where this recording's words will.
            var preview = LiveTranscriptDraftPreview(insertionOffset: recordedTranscriptInsertionOffset)
            updated = preview.insertLine(line, in: draft.text)
            guard updated.count <= CaptureInputLimits.maximumTextCharacters else {
                errorMessage = QuickCaptureViewModelError.textTooLarge.localizedDescription
                return
            }
            recordedTranscriptInsertionOffset = preview.insertionOffset
        }
        draft.text = updated
        draft.updatedAt = Date()
        scheduleDraftSave()
    }

    func invalidateLiveRecordedTranscriptSession(_ sessionID: UUID) {
        invalidatedLiveTranscriptSessionIDs.insert(sessionID)
    }

    func cancelLiveRecordedTranscript(sessionID: UUID? = nil) async {
        if let sessionID {
            invalidatedLiveTranscriptSessionIDs.insert(sessionID)
            guard liveRecordedTranscriptSessionID == sessionID else { return }
        }
        guard var preview = liveRecordedTranscriptPreview else {
            liveRecordedTranscriptSessionID = nil
            return
        }
        let restoredText = preview.cancel(in: draft.text)
        liveRecordedTranscriptPreview = nil
        liveRecordedTranscriptSessionID = nil
        recordedTranscriptInsertionOffset = nil
        recordedTranscriptCaretOffset = nil
        draft.text = restoredText
        // A cancelled recording takes its words back out of the open file.
        liveNoteTextDidChange()
        await saveDraftNow()
    }

    /// Persists an imported recording's source, origin result, and immutable
    /// Preset policy before audio conversion/transcription can continue.
    @discardableResult
    func journalRecordedOrigin(
        source: CaptureSource,
        outcome: CaptureLocationOutcome?,
        profileSnapshot: CapturePresetProfile
    ) async -> Bool {
        await load()
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        guard let draftStore else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return false
        }
        guard draft.voxID == profileSnapshot.id else { return false }
        let journaledDraftID = draft.id
        let journaledRequestID = draft.requestID
        do {
            let journaled = try await draftStore.journalLocation(
                draftID: draft.id,
                requestID: draft.requestID,
                outcome: outcome,
                decisionOverride: draft.locationDecisionOverride,
                profileSnapshot: profileSnapshot,
                captureSource: source,
                expectedVoxID: profileSnapshot.id
            )
            guard draft.id == journaledDraftID,
                  draft.requestID == journaledRequestID,
                  draft.voxID == profileSnapshot.id else {
                // Preset selection is debounced. If it changed while the actor
                // write was suspended, immediately restore the newer in-memory
                // draft so the stale import snapshot cannot win on disk.
                try? await draftStore.save(draft)
                return false
            }
            draft.captureSource = source
            draft.locationOutcome = outcome
            draft.voxProfileSnapshot = profileSnapshot
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func clearRecordedOrigin(profileID: String) async -> Bool {
        await load()
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        guard let draftStore else { return false }
        guard draft.voxID == profileID,
              draft.voxProfileSnapshot?.id == profileID else { return true }
        let clearedDraftID = draft.id
        let clearedRequestID = draft.requestID
        do {
            let cleared = try await draftStore.clearLocationJournal(
                draftID: draft.id,
                requestID: draft.requestID,
                captureSource: .fileImport,
                expectedProfileID: profileID
            )
            guard draft.id == clearedDraftID,
                  draft.requestID == clearedRequestID,
                  draft.voxID == profileID else {
                try? await draftStore.save(draft)
                return true
            }
            draft.captureSource = cleared.captureSource
            draft.locationOutcome = cleared.locationOutcome
            draft.locationDecisionOverride = cleared.locationDecisionOverride
            draft.voxProfileSnapshot = cleared.voxProfileSnapshot
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func appendRecordedTranscript(
        _ text: String,
        sessionID: UUID? = nil,
        deliveryID: UUID? = nil
    ) async -> Bool {
        await load()
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        if let deliveryID,
           draft.appliedRecordingTranscriptIDs?.contains(deliveryID) == true {
            return true
        }
        if let sessionID,
           let activeSessionID = liveRecordedTranscriptSessionID,
           activeSessionID != sessionID {
            errorMessage = String(localized: "Another recording is still updating this Capture. Retry the queued recording after it finishes.")
            return false
        }
        guard let draftStore else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return false
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let previousDraft = draft
        let previousPreview = liveRecordedTranscriptPreview
        let previousPreviewSessionID = liveRecordedTranscriptSessionID
        let updatedText: String
        let caretOffset: Int?
        if var preview = liveRecordedTranscriptPreview {
            updatedText = preview.commit(normalized, in: draft.text)
            caretOffset = preview.caretOffset
        } else {
            let inserted = LiveTranscriptDraftPreview.inserting(
                normalized,
                into: draft.text,
                atUTF16Offset: recordedTranscriptInsertionOffset
            )
            updatedText = inserted.text
            caretOffset = inserted.caretOffset
        }
        guard updatedText.count <= CaptureInputLimits.maximumTextCharacters else {
            errorMessage = QuickCaptureViewModelError.textTooLarge.localizedDescription
            return false
        }

        liveRecordedTranscriptPreview = nil
        liveRecordedTranscriptSessionID = nil
        let previousInsertionOffset = recordedTranscriptInsertionOffset
        recordedTranscriptInsertionOffset = nil
        draft.text = updatedText
        recordedTranscriptCaretOffset = caretOffset
        // The recorder adds transcription seconds only after a successful
        // result. Mark this durable request so sending it does not consume a
        // second, independent Capture allowance.
        draft.deliveryKind = .meteredVoiceTranscript
        let savedAt = Date()
        draft.updatedAt = savedAt
        draft.beginCaptureIfNeeded(at: savedAt)
        if let deliveryID {
            var appliedIDs = draft.appliedRecordingTranscriptIDs ?? []
            if !appliedIDs.contains(deliveryID) { appliedIDs.append(deliveryID) }
            draft.appliedRecordingTranscriptIDs = appliedIDs
        }
        do {
            let persistedDraft = try await draftStore.save(draft, now: savedAt)
            draft.preserveCaptureStart(from: persistedDraft)
            errorMessage = nil
            return true
        } catch {
            draft = previousDraft
            liveRecordedTranscriptPreview = previousPreview
            liveRecordedTranscriptSessionID = previousPreviewSessionID
            recordedTranscriptInsertionOffset = previousInsertionOffset
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func stageRecordedAudio(
        at sourceURL: URL,
        deliveryID: UUID? = nil
    ) async -> CaptureAssetReference? {
        await load()
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        guard let stagingDirectory = stagingDirectoryURL else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return nil
        }
        let receiptKey = deliveryID?.uuidString.lowercased()
        var staleAsset: CaptureAssetReference?
        if let receiptKey,
           let asset = draft.stagedRecordingAudioReceipts?[receiptKey],
           draft.additionalPayloads.flatMap(Self.assets(in:)).contains(asset) {
            let stagedURL = stagingDirectory.appendingPathComponent(asset.relativePath)
            if FileManager.default.fileExists(atPath: stagedURL.path) {
                return asset
            }
            staleAsset = asset
        }
        let stager = CaptureAssetStager(directoryURL: stagingDirectory)
        var stagedAsset: CaptureAssetReference?
        let previousDraft = draft
        do {
            let sourceExtension = sourceURL.pathExtension.isEmpty ? "wav" : sourceURL.pathExtension.lowercased()
            let contentType = UTType(filenameExtension: sourceExtension)?.identifier ?? UTType.audio.identifier
            let asset = try await stager.stageCopy(
                from: sourceURL,
                preferredFilename: deliveryID.map { "Recording-\($0.uuidString.lowercased()).\(sourceExtension)" }
                    ?? "Recording-\(Self.captureFilenameTimestamp()).\(sourceExtension)",
                contentTypeIdentifier: contentType
            )
            stagedAsset = asset
            if let staleAsset {
                draft.additionalPayloads.removeAll { payload in
                    Self.assets(in: payload).contains(staleAsset)
                }
                if let receiptKey {
                    draft.stagedRecordingAudioReceipts?.removeValue(forKey: receiptKey)
                }
            }
            try await appendStagedPayload(
                .audio(asset, transcript: nil),
                using: stager,
                recordingAudioDeliveryID: deliveryID
            )
            errorMessage = nil
            return asset
        } catch {
            draft = previousDraft
            if let stagedAsset { try? await stager.remove(stagedAsset) }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    /// Atomically restores a sent value/audio snapshot into the active draft.
    /// Cached files are copied into this draft's own staging directory before
    /// the durable draft references them.
    @discardableResult
    func restoreSentCapture(
        text: String,
        valuePayloads: [CapturePayload],
        cachedAudioPayloads: [CapturePayload],
        audioCacheDirectoryURL: URL?
    ) async -> Bool {
        await load()
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        guard liveRecordedTranscriptPreview == nil else { return false }
        guard let draftStore, let stagingDirectory = stagingDirectoryURL else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return false
        }
        guard valuePayloads.allSatisfy({ payload in
            switch payload {
            case .text, .url: return true
            case .audio, .retainedAudio, .image, .file, .scannedDocument, .sketch: return false
            }
        }), cachedAudioPayloads.allSatisfy({ payload in
            switch payload {
            case .audio, .retainedAudio: return true
            case .text, .url, .image, .file, .scannedDocument, .sketch: return false
            }
        }) else { return false }
        guard cachedAudioPayloads.isEmpty || audioCacheDirectoryURL != nil else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return false
        }

        let restoredText = text.trimmingCharacters(in: .newlines)
        let updatedText: String
        if restoredText.isEmpty {
            updatedText = draft.text
        } else if draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updatedText = restoredText
        } else {
            updatedText = draft.text + "\n\n" + restoredText
        }
        guard updatedText.count <= CaptureInputLimits.maximumTextCharacters else {
            errorMessage = QuickCaptureViewModelError.textTooLarge.localizedDescription
            return false
        }
        guard attachmentsFitInputBudget(
            draft.additionalPayloads + valuePayloads + cachedAudioPayloads
        ) else {
            errorMessage = QuickCaptureViewModelError.assetsTooLarge.localizedDescription
            return false
        }

        pendingDraftSave?.cancel()
        pendingDraftSave = nil
        let previousDraft = draft
        let stager = CaptureAssetStager(directoryURL: stagingDirectory)
        var stagedAssets: [CaptureAssetReference] = []
        do {
            var restoredAudioPayloads: [CapturePayload] = []
            for payload in cachedAudioPayloads {
                let sourceAsset: CaptureAssetReference
                switch payload {
                case .audio(let asset, _), .retainedAudio(let asset, _):
                    sourceAsset = asset
                case .text, .url, .image, .file, .scannedDocument, .sketch:
                    continue
                }
                guard let audioCacheDirectoryURL else {
                    throw QuickCaptureViewModelError.storageUnavailable
                }
                let sourceURL = try CapturePathValidation.containedFileURL(
                    relativePath: sourceAsset.relativePath,
                    rootURL: audioCacheDirectoryURL
                )
                let restoredAsset = try await stager.stageCopy(
                    from: sourceURL,
                    preferredFilename: sourceAsset.originalFilename,
                    contentTypeIdentifier: sourceAsset.contentTypeIdentifier
                )
                stagedAssets.append(restoredAsset)
                switch payload {
                case .audio(_, let transcript):
                    restoredAudioPayloads.append(.audio(restoredAsset, transcript: transcript))
                case .retainedAudio(_, let embedPlacement):
                    restoredAudioPayloads.append(.retainedAudio(restoredAsset, embedPlacement: embedPlacement))
                case .text, .url, .image, .file, .scannedDocument, .sketch:
                    break
                }
            }

            draft.text = updatedText
            draft.additionalPayloads.append(contentsOf: valuePayloads + restoredAudioPayloads)
            try await saveDurableDraft(using: draftStore)
            errorMessage = nil
            return true
        } catch {
            draft = previousDraft
            for asset in stagedAssets {
                try? await stager.remove(asset)
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func appendRecognizedText(_ text: String) async -> Bool {
        await load()
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        guard liveRecordedTranscriptPreview == nil else {
            errorMessage = String(localized: "Finish the current recording before extracting text from images.")
            return false
        }
        guard let draftStore else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return false
        }

        let normalized = CaptureOCRMarkdownFormatter().render(pageTexts: [text])
        guard !normalized.isEmpty else { return false }
        let separator = draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
        let updatedText = draft.text + separator + normalized
        guard updatedText.count <= CaptureInputLimits.maximumTextCharacters else {
            errorMessage = QuickCaptureViewModelError.textTooLarge.localizedDescription
            return false
        }

        let previousDraft = draft
        let savedAt = Date()
        draft.text = updatedText
        draft.updatedAt = savedAt
        draft.beginCaptureIfNeeded(at: savedAt)
        let candidateDraft = draft
        do {
            let persistedDraft = try await draftStore.save(candidateDraft, now: savedAt)
            draft.preserveCaptureStart(from: persistedDraft)
            errorMessage = nil
            return true
        } catch {
            // The main actor can accept typing or attachment changes while the
            // actor-backed save is suspended. Roll back only if nothing newer
            // has replaced the OCR candidate; otherwise preserve and resave it.
            if draft == candidateDraft {
                draft = previousDraft
            } else {
                scheduleDraftSave()
            }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func setDescribingImages(_ value: Bool) { isDescribingImages = value }

    func describeStagedImagesIfNeeded(from startIndex: Int) async {
        let lowerBound = max(0, min(startIndex, draft.additionalPayloads.count))
        let payloads = Array(draft.additionalPayloads[lowerBound...])
        await describeStagedImagesIfNeeded(payloads: payloads)
    }

    private func describeStagedImagesIfNeeded(payloads: [CapturePayload]) async {
        guard payloads.contains(where: Self.imagePayloadNeedsDescription) else { return }
        let routeOperation = holdCaptureRoute()
        defer {
            isDescribingImages = false
            endCaptureRouteOperation(routeOperation)
        }
        guard let profile = draft.voxProfileSnapshot ?? selectedVoxProfile,
              profile.processesImages,
              let stagingDirectory = stagingDirectoryURL,
              let draftStore else { return }

        let processedPayloads = await requestProcessor.processImagePayloads(
            payloads,
            profile: profile,
            assetRootURL: stagingDirectory,
            localeIdentifier: Locale.current.identifier
        ) { [weak self] in
            await self?.setDescribingImages(true)
        }
        guard !Task.isCancelled else { return }

        let replacements = processedPayloads.compactMap(Self.generatedImageReplacement)
        guard !replacements.isEmpty else { return }

        let previousDraft = draft
        var didChange = false
        for replacement in replacements {
            guard let index = draft.additionalPayloads.firstIndex(where: { current in
                Self.matchesImageDescriptionTarget(current, target: replacement.target)
                    && Self.imagePayloadNeedsDescription(current)
            }) else { continue }
            draft.additionalPayloads[index] = replacement.payload
            didChange = true
        }
        guard didChange else { return }

        let candidateDraft = draft
        do {
            try await saveDurableDraft(using: draftStore)
            errorMessage = nil
        } catch {
            if draft == candidateDraft {
                draft = previousDraft
            } else {
                scheduleDraftSave()
            }
            errorMessage = error.localizedDescription
        }
    }

    private struct ImageDescriptionReplacement {
        var target: CaptureAssetReference
        var payload: CapturePayload
    }

    private static func imagePayloadNeedsDescription(_ payload: CapturePayload) -> Bool {
        switch payload {
        case .image(_, let text, let origin), .sketch(_, _, let text, let origin):
            return CaptureAltTextOrigin.needsDescription(text: text, origin: origin)
        case .text, .url, .audio, .retainedAudio, .file, .scannedDocument:
            return false
        }
    }

    private static func generatedImageReplacement(_ payload: CapturePayload) -> ImageDescriptionReplacement? {
        switch payload {
        case .image(let asset, let text, let origin):
            guard origin == .generated, CaptureImageDescription.validated(text) != nil else { return nil }
            return ImageDescriptionReplacement(target: asset, payload: payload)
        case .sketch(_, let preview, let text, let origin):
            guard origin == .generated, CaptureImageDescription.validated(text) != nil else { return nil }
            return ImageDescriptionReplacement(target: preview, payload: payload)
        case .text, .url, .audio, .retainedAudio, .file, .scannedDocument:
            return nil
        }
    }

    private static func matchesImageDescriptionTarget(_ payload: CapturePayload, target: CaptureAssetReference) -> Bool {
        switch payload {
        case .image(let asset, _, _):
            return asset == target
        case .sketch(_, let preview, _, _):
            return preview == target
        case .text, .url, .audio, .retainedAudio, .file, .scannedDocument:
            return false
        }
    }

    @discardableResult
    func stageImage(
        data: Data,
        filename: String,
        contentTypeIdentifier: String,
        altText: String? = nil,
        altTextOrigin: CaptureAltTextOrigin? = nil,
        describeImmediately: Bool = true
    ) async -> CapturePayload? {
        let payload = await stageAsset { stager in
            let asset = try await stager.stage(
                data: data,
                preferredFilename: filename,
                contentTypeIdentifier: contentTypeIdentifier
            )
            return .image(asset, altText: altText, altTextOrigin: altTextOrigin ?? (altText == nil ? nil : .provided))
        }
        if describeImmediately, let payload {
            await describeStagedImagesIfNeeded(payloads: [payload])
        }
        return payload
    }

    @discardableResult
    func stageFile(
        at sourceURL: URL,
        filename: String? = nil,
        contentTypeIdentifier: String,
        embedAsImage: Bool = false,
        embedAsAudio: Bool = false,
        describeImageImmediately: Bool = true
    ) async -> CapturePayload? {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
        let payload = await stageAsset { stager in
            let asset = try await stager.stageCopy(
                from: sourceURL,
                preferredFilename: filename,
                contentTypeIdentifier: contentTypeIdentifier
            )
            if embedAsImage { return .image(asset, altText: nil) }
            if embedAsAudio { return .audio(asset, transcript: nil) }
            return .file(asset)
        }
        if embedAsImage, describeImageImmediately, let payload {
            await describeStagedImagesIfNeeded(payloads: [payload])
        }
        return payload
    }

    @discardableResult
    func stageVoiceRecording(at sourceURL: URL, transcript: String?) async -> CaptureAssetReference? {
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        guard let stagingDirectory = stagingDirectoryURL else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return nil
        }
        let stager = CaptureAssetStager(directoryURL: stagingDirectory)
        var stagedAsset: CaptureAssetReference?
        do {
            try Task.checkCancellation()
            let filename = "Recording-\(Self.captureFilenameTimestamp()).m4a"
            let asset = try await stager.stageCopy(
                from: sourceURL,
                preferredFilename: filename,
                contentTypeIdentifier: "public.mpeg-4-audio"
            )
            stagedAsset = asset
            try Task.checkCancellation()
            try await appendStagedPayload(.audio(asset, transcript: transcript), using: stager)
            errorMessage = nil
            return asset
        } catch is CancellationError {
            if let stagedAsset { try? await stager.remove(stagedAsset) }
            return nil
        } catch {
            if let stagedAsset { try? await stager.remove(stagedAsset) }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func updateStagedVoiceRecording(
        _ asset: CaptureAssetReference,
        transcript: String?
    ) async -> Bool {
        guard let index = draft.additionalPayloads.firstIndex(where: { payload in
            guard case .audio(let candidate, _) = payload else { return false }
            return candidate == asset
        }) else { return false }
        let previous = draft.additionalPayloads[index]
        draft.additionalPayloads[index] = .audio(asset, transcript: transcript)
        do {
            try await persistDurableDraft()
            errorMessage = nil
            return true
        } catch {
            draft.additionalPayloads[index] = previous
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func removeStagedVoiceRecording(_ asset: CaptureAssetReference) async -> Bool {
        guard let index = draft.additionalPayloads.firstIndex(where: { payload in
            guard case .audio(let candidate, _) = payload else { return false }
            return candidate == asset
        }) else { return true }
        await removePayload(at: index)
        return !draft.additionalPayloads.contains { payload in
            guard case .audio(let candidate, _) = payload else { return false }
            return candidate == asset
        }
    }

    func stageScan(pageImages: [Data], pdfData: Data?, extractedText: String?) async {
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        guard let stagingDirectory = stagingDirectoryURL else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return
        }
        let stager = CaptureAssetStager(directoryURL: stagingDirectory)
        var newlyStaged: [CaptureAssetReference] = []
        do {
            var pages: [CaptureAssetReference] = []
            for (index, data) in pageImages.enumerated() {
                let page = try await stager.stage(
                    data: data,
                    preferredFilename: "scan-page-\(index + 1).jpg",
                    contentTypeIdentifier: "public.jpeg"
                )
                pages.append(page)
                newlyStaged.append(page)
            }
            let pdf: CaptureAssetReference?
            if let pdfData {
                let stagedPDF = try await stager.stage(
                    data: pdfData,
                    preferredFilename: "scan.pdf",
                    contentTypeIdentifier: "com.adobe.pdf"
                )
                pdf = stagedPDF
                newlyStaged.append(stagedPDF)
            } else {
                pdf = nil
            }
            try await appendStagedPayload(
                .scannedDocument(pages: pages, pdf: pdf, extractedText: extractedText),
                using: stager
            )
            errorMessage = nil
        } catch {
            for asset in newlyStaged { try? await stager.remove(asset) }
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func stageSketch(
        drawingData: Data,
        previewData: Data,
        altText: String? = nil,
        altTextOrigin: CaptureAltTextOrigin? = nil,
        drawingFilename: String = "sketch.drawing",
        drawingContentTypeIdentifier: String = "com.apple.pencilkit.drawing",
        describeImmediately: Bool = true
    ) async -> CapturePayload? {
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        guard let stagingDirectory = stagingDirectoryURL else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return nil
        }
        let stager = CaptureAssetStager(directoryURL: stagingDirectory)
        var newlyStaged: [CaptureAssetReference] = []
        do {
            let drawing = try await stager.stage(
                data: drawingData,
                preferredFilename: drawingFilename,
                contentTypeIdentifier: drawingContentTypeIdentifier
            )
            newlyStaged.append(drawing)
            let preview = try await stager.stage(
                data: previewData,
                preferredFilename: "sketch.png",
                contentTypeIdentifier: "public.png"
            )
            newlyStaged.append(preview)
            let payload = CapturePayload.sketch(
                drawing: drawing,
                preview: preview,
                altText: altText,
                altTextOrigin: altTextOrigin ?? (altText == nil ? nil : .provided)
            )
            try await appendStagedPayload(payload, using: stager)
            errorMessage = nil
            if describeImmediately {
                await describeStagedImagesIfNeeded(payloads: [payload])
            }
            return payload
        } catch {
            for asset in newlyStaged { try? await stager.remove(asset) }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func addURL(_ url: URL, title: String? = nil) async {
        guard CaptureWebLink.isValid(url) else {
            errorMessage = String(localized: "Enter a complete http:// or https:// link.")
            return
        }
        draft.additionalPayloads.append(.url(url, title: title))
        await saveDraftNow()
        await embedPendingAttachmentsInLiveNote()
    }

    func removePayload(at index: Int) async {
        guard draft.additionalPayloads.indices.contains(index), let draftStore else { return }
        let pendingSave = pendingDraftSave
        pendingDraftSave = nil
        pendingSave?.cancel()
        await pendingSave?.value

        let payload = draft.additionalPayloads.remove(at: index)
        draft.updatedAt = Date()
        do {
            // Persist the removed reference before deleting bytes. If saving
            // fails, the durable draft still points at a valid staged file.
            try await saveDurableDraft(using: draftStore)
        } catch {
            draft.additionalPayloads.insert(payload, at: index)
            errorMessage = error.localizedDescription
            return
        }

        if let stagingDirectory = stagingDirectoryURL {
            let stager = CaptureAssetStager(directoryURL: stagingDirectory)
            for asset in Self.assets(in: payload) {
                do {
                    try await stager.remove(asset)
                } catch {
                    // The draft no longer references this file. Keep the
                    // capture valid and surface cleanup failure for retry via
                    // normal draft completion directory cleanup.
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func submit() async {
        // A bound Live Note saves itself; it is never re-sent as a capture.
        guard liveNote == nil else { return }
        guard liveRecordedTranscriptPreview == nil else {
            errorMessage = String(localized: "Finish the current recording before sending this Capture.")
            return
        }
        guard draft.text.count <= CaptureInputLimits.maximumTextCharacters else {
            errorMessage = QuickCaptureViewModelError.textTooLarge.localizedDescription
            return
        }
        guard attachmentsFitInputBudget(draft.additionalPayloads) else {
            errorMessage = QuickCaptureViewModelError.assetsTooLarge.localizedDescription
            return
        }
        guard let captureRootURL, let libraryStore, let draftStore else {
            errorMessage = String(localized: "Shared capture storage is unavailable.")
            return
        }
        guard canSubmit else { return }

        isSubmitting = true
        isDescribingImages = false
        defer { isDescribingImages = false }
        errorMessage = nil
        let pendingSave = pendingDraftSave
        pendingDraftSave = nil
        pendingSave?.cancel()
        await pendingSave?.value
        let submittedAt = Date()
        draft.beginCaptureIfNeeded(at: submittedAt)
        var submittedDraft = draft
        // A journaled origin result owns the exact Preset policy that produced
        // it. Do not combine that outcome with later edits to the same Preset.
        let submittedVoxProfile = submittedDraft.voxProfileSnapshot ?? selectedVoxProfile
        // Freeze the opt-in destination before any asynchronous processing.
        let submittedURLDeliverySettings = submittedVoxProfile.flatMap {
            CapturePresetStore.flow(id: $0.id, defaults: defaults)?.exportSettings.urlDelivery
        }
        guard let submittedDestinationID = effectiveDestinationID else {
            isSubmitting = false
            errorMessage = CaptureDraftError.destinationRequired.localizedDescription
            return
        }
        do {
            submittedDraft = try await draftStore.save(submittedDraft, now: submittedAt)
            draft.preserveCaptureStart(from: submittedDraft)
            let submittedDraftID = submittedDraft.id
            let preparedCandidate = try await draftStore.loadPreparedRequest(draftID: submittedDraftID)
            let reusablePrepared = preparedCandidate.flatMap { prepared -> CaptureRequest? in
                CapturePreparedRequestReuse.matches(
                    prepared,
                    draft: submittedDraft,
                    destinationID: submittedDestinationID,
                    presetID: submittedVoxProfile?.id
                ) ? prepared : nil
            }
            if submittedVoxProfile?.locationPolicy.isEnabled == true, reusablePrepared == nil {
                let policy = submittedVoxProfile!.locationPolicy
                let usedExplicitSendWithout = pendingSendWithoutLocationOutcome != nil
                let outcome: CaptureLocationOutcome
                if let pendingSendWithoutLocationOutcome {
                    outcome = pendingSendWithoutLocationOutcome
                } else if let durableOutcome = submittedDraft.locationOutcome {
                    // A suspended/relaunched Send reuses the exact origin result.
                    outcome = durableOutcome
                } else {
                    isResolvingLocation = true
                    outcome = await locationProvider.resolveLocation(
                        policy: policy,
                        source: submittedDraft.captureSource ?? defaultCaptureSource
                    )
                    isResolvingLocation = false
                }
                pendingSendWithoutLocationOutcome = nil
                let decisionOverride: CaptureLocationDecisionOverride? = usedExplicitSendWithout
                    ? .sendWithoutLocation
                    : submittedDraft.locationDecisionOverride
                // Journal before showing a decision or starting asynchronous
                // preset processing. This merge preserves concurrent draft edits.
                submittedDraft = try await draftStore.journalLocation(
                    draftID: submittedDraft.id,
                    requestID: submittedDraft.requestID,
                    outcome: outcome,
                    decisionOverride: decisionOverride,
                    profileSnapshot: submittedVoxProfile
                )
                if draft.id == submittedDraft.id, draft.requestID == submittedDraft.requestID {
                    draft.locationOutcome = outcome
                    draft.locationDecisionOverride = decisionOverride
                    draft.voxProfileSnapshot = submittedVoxProfile
                }
                if case .unavailable(let reason, let attemptedAt) = outcome,
                   decisionOverride != .sendWithoutLocation {
                    switch policy.unavailableBehavior {
                    case .ask:
                        locationDecision = CaptureLocationDecision(
                            reason: reason,
                            attemptedAt: attemptedAt,
                            presetID: submittedVoxProfile!.id
                        )
                        isSubmitting = false
                        return
                    case .cancel:
                        isSubmitting = false
                        return
                    case .sendWithoutLocation:
                        break
                    }
                }
            }
            locationDecision = nil
            let pipeline = self.pipeline
            let requestProcessor = self.requestProcessor
            let outcome = try await draftStore.submit(draftID: submittedDraftID) { draft in
                let library = try await libraryStore.load()
                guard let storedDestination = library.destinations.first(where: {
                    $0.id == submittedDestinationID
                }) else {
                    throw CaptureDraftError.destinationRequired
                }
                var destination = library.resolvedDestination(
                    storedDestination,
                    overrideEntryTemplateID: draft.entryTemplateID
                        ?? submittedVoxProfile?.captureEntryTemplateID
                )
                if let override = draft.placementOverride
                    ?? submittedVoxProfile?.capturePlacementOverride {
                    destination.placement = override
                }
                if let noteOverride = draft.relativeNotePathOverride {
                    try CapturePathValidation.validateRelativePath(noteOverride)
                    guard noteOverride.lowercased().hasSuffix(".md") else {
                        throw QuickCaptureViewModelError.noteMustBeMarkdown
                    }
                    destination.noteTarget = .existingNote(relativePath: noteOverride)
                }
                let request: CaptureRequest
                if let reusablePrepared {
                    request = reusablePrepared
                } else {
                    let unresolved = try draft.makeRequest(
                        source: defaultCaptureSource,
                        resolvedDestinationID: submittedDestinationID,
                        voxProfile: submittedVoxProfile
                    )
                    let assetRoot = captureRootURL
                        .appendingPathComponent("staging", isDirectory: true)
                        .appendingPathComponent(draft.id.uuidString.lowercased(), isDirectory: true)
                    let processed = await requestProcessor.process(unresolved, assetRootURL: assetRoot) { [weak self] in
                        await self?.setDescribingImages(true)
                    }
                    await self.setDescribingImages(false)
                    try Task.checkCancellation()
                    try await draftStore.savePreparedRequest(processed, draftID: draft.id)
                    request = processed
                }
                let stagingURL = captureRootURL
                    .appendingPathComponent("staging", isDirectory: true)
                    .appendingPathComponent(draft.id.uuidString.lowercased(), isDirectory: true)
                // Vault unreachable (stale bookmark, revoked access, folder
                // gone): hold the capture in the inbox with its attachments,
                // as the "Vault folder access expired" card promises. It shows
                // in Activity and delivers after Re-grant access.
                guard let rootURL = Self.reachableRootURL(for: destination) else {
                    let heldID = try await CaptureInboxVaultHold.hold(
                        request,
                        stagedAssetRootURL: stagingURL,
                        destinationName: destination.name,
                        captureRootURL: captureRootURL
                    )
                    return ComposerSubmitOutcome.heldForVault(heldID)
                }
                let didAccess = rootURL.startAccessingSecurityScopedResource()
                defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
                let cancellation = URLDeliveryCancellation()
                return try await withTaskCancellationHandler {
                    // Explicit Send freezes processed bytes before a note
                    // mutation, without contacting the endpoint.
                    let urlEvent = try await self.enqueueCaptureToURLIfConfigured(
                        request: request, settings: submittedURLDeliverySettings
                    )
                    try Task.checkCancellation()
                    let receipt = try await pipeline.capture(
                        request,
                        destination: destination,
                        rootURL: rootURL,
                        assetRootURL: stagingURL
                    )
                    if case .queued? = urlEvent?.result {
                        await self.dispatchCaptureURLDelivery(id: request.id, cancellation: cancellation)
                    }
                    return ComposerSubmitOutcome.delivered(receipt)
                } onCancel: { cancellation.cancel() }
            }

            guard case .delivered(let receipt) = outcome else {
                // Held for an unreachable vault: the draft is cleared like a
                // send; the capture now waits in the inbox (Activity).
                try? await draftStore.removePreparedRequest(draftID: submittedDraftID)
                if let concurrentlyEdited = try await draftStore.load(id: submittedDraftID),
                   case let rebased = concurrentlyEdited.rebased(afterSubmitting: submittedDraft),
                   rebased.hasCaptureContent {
                    draft = rebased
                    try await draftStore.save(rebased)
                } else {
                    try? await draftStore.complete(draftID: submittedDraftID)
                    draft = CaptureDraft(
                        voxID: submittedVoxProfile?.id,
                        destinationSelectionMode: .inherited
                    )
                    try await draftStore.save(draft)
                }
                if case .heldForVault(let heldID) = outcome { lastHeldForVaultRequestID = heldID }
                failedInboxCount = (try? await CaptureInbox(rootDirectoryURL: captureRootURL)
                    .requestIDs(in: .failed).count) ?? failedInboxCount
                isSubmitting = false
                return
            }
            lastReceipt = receipt
            needsCaptureUnlock = false
            try? await draftStore.removePreparedRequest(draftID: submittedDraftID)
            let library = try await libraryStore.load()
            if let request = try? submittedDraft.makeRequest(
                source: defaultCaptureSource,
                resolvedDestinationID: submittedDestinationID,
                voxProfile: submittedVoxProfile
            ) {
                await recordHistory(
                    request: request,
                    destinationName: library.destinations.first(where: { $0.id == request.destinationID })?.name
                        ?? String(localized: "Deleted destination"),
                    // The receipt names the note actually written, which is a
                    // sibling note when "Write a new note instead" was used.
                    relativeNotePath: historyRelativeNotePath(for: receipt, destinationID: request.destinationID)
                        ?? submittedDraft.relativeNotePathOverride,
                    attachmentCount: receipt.attachmentURLs.count,
                    outcome: .delivered,
                    failureCategory: nil,
                    receipt: receipt
                )
            }
            if liveNotesEnabled {
                try await bindDeliveredNote(
                    receipt: receipt,
                    destinationID: submittedDestinationID,
                    submittedDraft: submittedDraft,
                    presetID: submittedVoxProfile?.id,
                    draftStore: draftStore
                )
                destinations = library.destinations
                entryTemplates = library.entryTemplates
                isSubmitting = false
                return
            }
            if let concurrentlyEdited = try await draftStore.load(id: submittedDraftID) {
                let rebased = concurrentlyEdited.rebased(afterSubmitting: submittedDraft)
                if rebased.hasCaptureContent {
                    draft = rebased
                    try await draftStore.save(rebased)
                } else {
                    try await draftStore.complete(draftID: submittedDraftID)
                    draft = CaptureDraft(
                        voxID: submittedVoxProfile?.id,
                        destinationSelectionMode: .inherited
                    )
                    try await draftStore.save(draft)
                }
            } else {
                draft = CaptureDraft(
                    voxID: submittedVoxProfile?.id,
                    destinationSelectionMode: .inherited
                )
                try await draftStore.save(draft)
            }
            destinations = library.destinations
            entryTemplates = library.entryTemplates
        } catch is CancellationError {
            // The draft and its staged attachments remain available for another Send.
        } catch let error as CaptureDeliveryQuotaError {
            if case .limitReached = error {
                needsCaptureUnlock = true
                errorMessage = nil
            }
        } catch {
            if let request = try? submittedDraft.makeRequest(
                source: defaultCaptureSource,
                resolvedDestinationID: submittedDestinationID,
                voxProfile: submittedVoxProfile
            ) {
                await recordHistory(
                    request: request,
                    destinationName: destinations.first(where: { $0.id == request.destinationID })?.name
                        ?? String(localized: "Unavailable destination"),
                    relativeNotePath: submittedDraft.relativeNotePathOverride,
                    attachmentCount: request.payloads.flatMap(Self.assets(in:)).count,
                    outcome: .failed,
                    failureCategory: Self.historyFailureCategory(for: error),
                    error: error
                )
            }
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }

    func retryUnavailableLocation() async {
        guard !isSubmitting, !hostOwnsCaptureRoute(), !isProcessingMedia,
              routeOperationIDs.isEmpty, pendingPresetSwitch == nil,
              let decision = locationDecision, decision.presetID == draft.voxID else { return }
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        locationDecision = nil
        pendingSendWithoutLocationOutcome = nil
        do {
            draft = try await draftStore?.journalLocation(
                draftID: draft.id,
                requestID: draft.requestID,
                outcome: nil,
                decisionOverride: nil
            ) ?? draft
            endCaptureRouteOperation(operation)
            await submit()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func sendWithoutUnavailableLocation(alwaysForPreset: Bool) async {
        guard !isSubmitting, !hostOwnsCaptureRoute(), !isProcessingMedia,
              routeOperationIDs.isEmpty, pendingPresetSwitch == nil,
              let decision = locationDecision, decision.presetID == draft.voxID else { return }
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        let outcome = CaptureLocationOutcome.unavailable(
            decision.reason,
            attemptedAt: decision.attemptedAt
        )
        pendingSendWithoutLocationOutcome = outcome
        do {
            draft = try await draftStore?.journalLocation(
                draftID: draft.id,
                requestID: draft.requestID,
                outcome: outcome,
                decisionOverride: .sendWithoutLocation
            ) ?? draft
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        if alwaysForPreset {
            CapturePresetStore.setLocationUnavailableBehavior(
                .sendWithoutLocation,
                presetID: decision.presetID,
                defaults: defaults
            )
            refreshVoxProfiles()
        }
        locationDecision = nil
        endCaptureRouteOperation(operation)
        await submit()
    }

    func cancelUnavailableLocation() async {
        guard locationDecision != nil, !isSubmitting, !hostOwnsCaptureRoute(),
              routeOperationIDs.isEmpty else { return }
        let operation = holdCaptureRoute()
        defer { endCaptureRouteOperation(operation) }
        locationDecision = nil
        pendingSendWithoutLocationOutcome = nil
        do {
            draft = try await draftStore?.clearLocationJournal(
                draftID: draft.id,
                requestID: draft.requestID
            ) ?? draft
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func handleDeepLink(_ action: CaptureDeepLinkAction) async {
        do {
            await load()
            guard hasLoaded else { return }
            switch action {
            case .openComposer(let incoming):
                try await openComposer(incoming)

            case .processInboxRequest(let requestID):
                try await processInboxRequest(id: requestID)
            }
            errorMessage = nil
        } catch is CancellationError {
            errorMessage = nil
        } catch let error as CaptureDeliveryQuotaError {
            if case .limitReached = error {
                needsCaptureUnlock = true
                errorMessage = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openComposer(_ incoming: CaptureDeepLinkDraft) async throws {
        guard requireCaptureRouteAvailable() else { throw QuickCaptureViewModelError.captureRouteBusy }
        let profiles = try await validateComposerLaunch(incoming)
        guard requireCaptureRouteAvailable() else { throw QuickCaptureViewModelError.captureRouteBusy }
        if incoming.source == .widget, let id = incoming.voxID,
           id != draft.voxID, draft.hasCaptureContent {
            pendingPresetSwitch = CapturePresetSwitchConfirmation(
                incoming: incoming,
                presetName: profiles.first(where: { $0.id == id })!.accessibilityName,
                draft: draft,
                requestedInput: requestedInput
            )
            return
        }
        try await applyComposerLaunch(incoming, profiles: profiles)
    }

    func cancelPresetSwitch(id: UUID) {
        guard pendingPresetSwitch?.id == id else { return }
        pendingPresetSwitch = nil
    }

    @discardableResult
    func confirmPresetSwitch(id: UUID) async -> Bool {
        guard let pending = pendingPresetSwitch, pending.id == id else { return false }
        var consumed = false
        do {
            let profiles = try await validateComposerLaunch(pending.incoming)
            // Recheck after the disk await, including cancellation/replacement of
            // this decision. A duplicate acceptance never applies twice.
            guard pendingPresetSwitch?.id == id else { return false }
            guard !isCaptureRouteOwned,
                  pending.matches(draft: draft, requestedInput: requestedInput) else {
                throw QuickCaptureViewModelError.stalePresetSwitch
            }
            pendingPresetSwitch = nil
            consumed = true
            try await applyComposerLaunch(pending.incoming, profiles: profiles)
            errorMessage = nil
            return true
        } catch {
            guard consumed || pendingPresetSwitch?.id == id else { return false }
            if pendingPresetSwitch?.id == id { pendingPresetSwitch = nil }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func validateComposerLaunch(_ incoming: CaptureDeepLinkDraft) async throws -> [CapturePresetProfile] {
        guard let libraryStore else { throw QuickCaptureViewModelError.storageUnavailable }
        let library = try await libraryStore.load()
        let profiles = CapturePresetProfileStore.enabledProfiles(defaults: defaults)
        if let id = incoming.voxID, !profiles.contains(where: { $0.id == id }) {
            throw QuickCaptureViewModelError.unknownVox
        }
        if let id = incoming.destinationID, !library.destinations.contains(where: { $0.id == id }) {
            throw QuickCaptureViewModelError.unknownDestination
        }
        if let url = incoming.url, !CaptureWebLink.isValid(url) {
            throw CaptureDeepLinkError.invalidURL
        }
        // Check the combined draft, not just the parser's incoming text budget.
        guard composerDraft(applying: incoming).text.count <= CaptureInputLimits.maximumTextCharacters else {
            throw QuickCaptureViewModelError.textTooLarge
        }
        return profiles
    }

    private func composerDraft(applying incoming: CaptureDeepLinkDraft) -> CaptureDraft {
        var candidate = draft
        if let id = incoming.voxID { candidate.selectVox(id) }
        if let id = incoming.destinationID { candidate.selectDestination(id) }
        candidate.captureSource = incoming.source ?? .deepLink
        if let text = incoming.text, !text.isEmpty {
            let separator = candidate.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : "\n\n"
            candidate.text += separator + text
        }
        if let url = incoming.url { candidate.additionalPayloads.append(.url(url, title: nil)) }
        return candidate
    }

    private func applyComposerLaunch(_ incoming: CaptureDeepLinkDraft, profiles: [CapturePresetProfile]) async throws {
        guard let operation = beginCaptureRouteOperation() else { throw QuickCaptureViewModelError.captureRouteBusy }
        defer { endCaptureRouteOperation(operation) }
        let previous = draft
        let candidate = composerDraft(applying: incoming)
        // Publish the complete validated value together, not source/input first.
        draft = candidate
        voxProfiles = profiles
        do {
            try await persistDurableDraft()
        } catch {
            if draft == candidate { draft = previous }
            throw error
        }
        if let id = incoming.voxID, id != previous.voxID {
            CapturePresetProfileStore.selectCaptureProfile(id: id, defaults: defaults)
        }
        // Input consumers may start work only after the durable commit and lease.
        endCaptureRouteOperation(operation)
        requestedInput = incoming.requestedInput
    }

    func processPendingInbox() async {
        guard let captureRootURL else { return }
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        guard hasPaidCaptureAccess() else {
            // Read-only (trial or subscription ended): queued Captures stay
            // safely queued and are not delivered — including metered voice
            // transcripts the delivery quota would otherwise let through.
            // Waiting work asks for a plan instead of failing silently; the
            // app drains again as soon as access returns.
            let pendingCount = (try? await inbox.requestIDs(in: .pending).count) ?? 0
            if pendingCount > 0 { needsCaptureUnlock = true }
            failedInboxCount = (try? await inbox.requestIDs(in: .failed).count) ?? failedInboxCount
            return
        }
        let result = await CaptureInboxDeliveryService.drain(
            captureRootURL: captureRootURL,
            defaults: defaults,
            pipeline: pipeline,
            requestProcessor: requestProcessor
        )
        if !result.quotaBlockedRequestIDs.isEmpty {
            needsCaptureUnlock = true
        }
        if let decision = result.decisionsRequired.first {
            inboxLocationDecision = CaptureInboxLocationDecision(
                requestID: decision.requestID,
                reason: decision.reason,
                source: decision.source,
                presetID: decision.presetID,
                presetName: decision.presetName
            )
        }
        failedInboxCount = (try? await inbox.requestIDs(in: .failed).count) ?? failedInboxCount
        if let detail = result.latestFailureDescription ?? result.setupError {
            errorMessage = String(localized: "A shared capture could not be delivered and is queued for retry. \(detail)")
        }
    }

    func sendInboxRequestWithoutLocation(alwaysForPreset: Bool = false) async {
        guard hasPaidCaptureAccess() else {
            needsCaptureUnlock = true
            return
        }
        guard let decision = inboxLocationDecision,
              let captureRootURL else { return }
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        do {
            guard try await inbox.sendWithoutLocation(requestID: decision.requestID) else {
                throw QuickCaptureViewModelError.inboxRequestUnavailable
            }
            if alwaysForPreset, let presetID = decision.presetID {
                CapturePresetStore.setLocationUnavailableBehavior(
                    .sendWithoutLocation,
                    presetID: presetID,
                    defaults: defaults
                )
                refreshVoxProfiles()
            }
            inboxLocationDecision = nil
            try await processInboxRequest(id: decision.requestID)
            NotificationCenter.default.post(
                name: .captureInboxDecisionResolved,
                object: decision.requestID,
                userInfo: ["discarded": false]
            )
            errorMessage = nil
            await processPendingInbox()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discardInboxLocationRequest() async {
        guard let decision = inboxLocationDecision,
              let captureRootURL else { return }
        do {
            let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
            guard try await inbox.discard(requestID: decision.requestID) else {
                throw QuickCaptureViewModelError.inboxRequestUnavailable
            }
            inboxLocationDecision = nil
            NotificationCenter.default.post(
                name: .captureInboxDecisionResolved,
                object: decision.requestID,
                userInfo: ["discarded": true]
            )
            errorMessage = nil
            await processPendingInbox()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func retryFailedInbox() async {
        guard hasPaidCaptureAccess() else {
            needsCaptureUnlock = true
            return
        }
        guard let captureRootURL, let libraryStore else { return }
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        do {
            let library = try await libraryStore.load()
            let replacementID = library.defaultDestinationID.flatMap { defaultID in
                library.destinations.contains(where: { $0.id == defaultID }) ? defaultID : nil
            } ?? library.destinations.first?.id
            if let replacementID {
                _ = try await inbox.rerouteOrphanedRequests(
                    validDestinationIDs: Set(library.destinations.map(\.id)),
                    to: replacementID,
                    states: [.failed]
                )
            }
            _ = try await inbox.retryAllFailed()
            failedInboxCount = 0
            await processPendingInbox()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Retries only the given inbox requests (for example captures waiting on
    /// a busy note), leaving unrelated failed requests for the person to
    /// decide on. Returns the IDs that are still queued afterwards.
    @discardableResult
    func retryInboxRequests(_ requestIDs: Set<UUID>) async -> Set<UUID> {
        guard let captureRootURL else { return [] }
        guard hasPaidCaptureAccess() else {
            needsCaptureUnlock = true
            return requestIDs
        }
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        for requestID in requestIDs {
            // Captures held by older builds were parked in `failed`.
            _ = try? await inbox.retryFailed(requestID: requestID)
        }
        await processPendingInbox()
        let queued = Set((try? await inbox.requestIDs(in: .pending)) ?? [])
            .union((try? await inbox.requestIDs(in: .failed)) ?? [])
            .union((try? await inbox.requestIDs(in: .processing)) ?? [])
        return requestIDs.intersection(queued)
    }

    /// Failed inbox requests for foreground recovery UI, oldest first, each
    /// with the Markdown entry its route would write. Nothing here is copied
    /// into history or Activity storage; it is read on demand only.
    func failedInboxEntries() async -> [CaptureFailedInboxEntry] {
        guard let captureRootURL, let libraryStore else { return [] }
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        guard let requests = try? await inbox.failedRequests() else { return [] }
        let library = try? await libraryStore.load()
        return requests.map { request in
            var markdown: String?
            var destinationName: String?
            if let library,
               let stored = library.destinations.first(where: { $0.id == request.destinationID }) {
                // Resolve the route exactly as inbox delivery does.
                var destination = library.resolvedDestination(
                    stored,
                    overrideEntryTemplateID: request.entryTemplateIDOverride
                        ?? request.voxProfile?.captureEntryTemplateID
                )
                if let relativePath = request.relativeNotePathOverride {
                    destination.noteTarget = .existingNote(relativePath: relativePath)
                }
                if let placement = request.placementOverride ?? request.voxProfile?.capturePlacementOverride {
                    destination.placement = placement
                }
                destinationName = destination.name
                // The vault may be unreachable (that is often why the capture
                // failed); the preview then leaves out the template header.
                let rootURL = (try? CaptureBookmarkResolver.resolve(destination.rootBookmark))?.url
                let didAccess = rootURL?.startAccessingSecurityScopedResource() ?? false
                markdown = try? pipeline.previewEntryMarkdown(for: request, destination: destination, rootURL: rootURL)
                if didAccess { rootURL?.stopAccessingSecurityScopedResource() }
                if let entry = markdown, let heading = CaptureHistoryRecord.placementHeading(for: destination.placement) {
                    let level: Int
                    if case .beneathHeading(let selector, _, _) = destination.placement {
                        level = max(1, min(6, selector.level ?? 2))
                    } else {
                        level = 2
                    }
                    markdown = String(repeating: "#", count: level) + " " + heading + "\n" + entry
                }
            }
            return CaptureFailedInboxEntry(
                requestID: request.id,
                createdAt: request.createdAt,
                source: request.source,
                routeName: request.voxReference?.name ?? destinationName,
                markdown: markdown ?? CaptureLibraryContent.plainText(of: request)
            )
        }
    }

    var sentCaptureUndoSourceDirectoryURL: URL? {
        stagingDirectoryURL
    }

    var sentCaptureUndoCacheRootURL: URL? {
        captureRootURL?.appendingPathComponent("sent-undo-audio", isDirectory: true)
    }

    private var stagingDirectoryURL: URL? {
        captureRootURL?
            .appendingPathComponent("staging", isDirectory: true)
            .appendingPathComponent(draft.id.uuidString.lowercased(), isDirectory: true)
    }

    private func stageAsset(
        _ operation: (CaptureAssetStager) async throws -> CapturePayload
    ) async -> CapturePayload? {
        let routeOperation = holdCaptureRoute()
        defer { endCaptureRouteOperation(routeOperation) }
        guard let stagingDirectory = stagingDirectoryURL else {
            errorMessage = QuickCaptureViewModelError.storageUnavailable.localizedDescription
            return nil
        }
        do {
            let stager = CaptureAssetStager(directoryURL: stagingDirectory)
            let payload = try await operation(stager)
            try await appendStagedPayload(payload, using: stager)
            errorMessage = nil
            return payload
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func appendStagedPayload(
        _ payload: CapturePayload,
        using stager: CaptureAssetStager,
        recordingAudioDeliveryID: UUID? = nil
    ) async throws {
        let proposed = draft.additionalPayloads + [payload]
        guard attachmentsFitInputBudget(proposed) else {
            for asset in Self.assets(in: payload) {
                try? await stager.remove(asset)
            }
            throw QuickCaptureViewModelError.assetsTooLarge
        }
        guard let draftStore else {
            for asset in Self.assets(in: payload) {
                try? await stager.remove(asset)
            }
            throw QuickCaptureViewModelError.storageUnavailable
        }
        draft.additionalPayloads.append(payload)
        let receiptKey = recordingAudioDeliveryID?.uuidString.lowercased()
        let previousReceipt = receiptKey.flatMap { draft.stagedRecordingAudioReceipts?[$0] }
        if let receiptKey, let asset = Self.assets(in: payload).first {
            var receipts = draft.stagedRecordingAudioReceipts ?? [:]
            receipts[receiptKey] = asset
            draft.stagedRecordingAudioReceipts = receipts
        }
        do {
            try await saveDurableDraft(using: draftStore)
        } catch {
            _ = draft.additionalPayloads.popLast()
            if let receiptKey {
                if let previousReceipt {
                    draft.stagedRecordingAudioReceipts?[receiptKey] = previousReceipt
                } else {
                    draft.stagedRecordingAudioReceipts?.removeValue(forKey: receiptKey)
                }
            }
            for asset in Self.assets(in: payload) {
                try? await stager.remove(asset)
            }
            throw error
        }
        // Live Notes: an open note takes attachments straight into the vault.
        await embedPendingAttachmentsInLiveNote()
    }

    private func attachmentsFitInputBudget(_ payloads: [CapturePayload]) -> Bool {
        var budget = CaptureInputBudget()
        do {
            for byteCount in payloads.flatMap(Self.assets(in:)).compactMap(\.byteCount) {
                try budget.reserveAsset(bytes: byteCount)
            }
            return true
        } catch {
            return false
        }
    }

    private func historyRelativeNotePath(
        for receipt: CaptureReceipt,
        destinationID: UUID
    ) -> String? {
        guard let destination = destinations.first(where: { $0.id == destinationID }),
              let rootURL = try? Self.resolveRootURL(for: destination) else {
            return receipt.noteURL.lastPathComponent
        }
        return CaptureHistoryRecord.relativeNotePath(noteURL: receipt.noteURL, rootURL: rootURL)
    }

    private func recordHistory(
        request: CaptureRequest,
        destinationName: String,
        relativeNotePath: String?,
        attachmentCount: Int,
        outcome: CaptureHistoryOutcome,
        failureCategory: CaptureHistoryFailureCategory?,
        receipt: CaptureReceipt? = nil,
        error: Error? = nil
    ) async {
        guard let historyStore,
              let record = try? CaptureHistoryRecord(
                requestID: request.id,
                createdAt: request.createdAt,
                deliveredAt: Date(),
                source: request.source,
                outcome: outcome,
                destinationID: request.destinationID,
                destinationName: destinationName,
                voxID: request.voxReference?.id,
                voxName: request.voxReference?.name,
                relativeNotePath: relativeNotePath,
                attachmentCount: attachmentCount,
                failureCategory: failureCategory,
                sourceDetail: historySourceDetails[request.id]
              ) else { return }
        // Library detail: status-only route log plus the delivered entry.
        let destination = destinations.first(where: { $0.id == request.destinationID })
        let placement = request.placementOverride
            ?? request.voxProfile?.capturePlacementOverride
            ?? destination?.placement
        let detailed = record.withDeliveryDetails(request: request, placement: placement, error: error)
        var content: CaptureLibraryContent?
        if let receipt, let destination, let rootURL = try? Self.resolveRootURL(for: destination) {
            var routed = destination
            if let placement { routed.placement = placement }
            content = CaptureLibraryContent.make(
                request: request,
                receipt: receipt,
                destination: routed,
                rootURL: rootURL
            )
        }
        _ = await historyStore.upsertBestEffort(detailed, content: content)
        historyRecords = (try? await historyStore.list()) ?? historyRecords
        if outcome == .delivered { Self.reloadRouteTodayWidget() }
    }

    /// Called only inside explicit Send. A preparation failure preserves the
    /// draft before any note mutation; a POST failure belongs to HTTP recovery.
    private func enqueueCaptureToURLIfConfigured(
        request: CaptureRequest, settings: CapturePresetURLDeliverySettings?
    ) async throws -> URLDeliveryEvent? {
        guard let settings, settings.enabled, !request.urlDeliveryText.isEmpty else { return nil }
        let event = await urlDeliveryCoordinator.enqueueCapture(
            id: request.id, text: request.urlDeliveryText, date: request.createdAt, settings: settings
        )
        if case .failed(let message, _) = event.result {
            throw QuickCaptureViewModelError.urlDeliveryHandoffFailed(message)
        }
        return event
    }

    private func dispatchCaptureURLDelivery(id: UUID, cancellation: URLDeliveryCancellation) {
        guard !Task.isCancelled else { return }
        urlDeliveryCoordinator.dispatch(id: id, cancellation: cancellation)
    }

    nonisolated private static func historyFailureCategory(for error: Error) -> CaptureHistoryFailureCategory {
        switch error {
        case is CaptureDraftError:
            return .invalidRequest
        case is CaptureVaultMarkdownTemplateError:
            return .destinationUnavailable
        case is CaptureAttachmentError:
            return .attachment
        case is CaptureModelError, is CapturePipelineError:
            return .invalidRequest
        case is QuickCaptureViewModelError:
            return .destinationUnavailable
        default:
            return .fileWrite
        }
    }

    nonisolated private static func captureFilenameTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    nonisolated private static func assets(in payload: CapturePayload) -> [CaptureAssetReference] {
        switch payload {
        case .text, .url:
            return []
        case .audio(let asset, _), .retainedAudio(let asset, _), .image(let asset, _, _), .file(let asset):
            return [asset]
        case .scannedDocument(let pages, let pdf, _):
            return pages + (pdf.map { [$0] } ?? [])
        case .sketch(let drawing, let preview, _, _):
            return [drawing, preview]
        }
    }

    private func recoverOrphanedInboxRequests(in inbox: CaptureInbox) async throws {
        guard let libraryStore else { return }
        let library = try await libraryStore.load()
        guard let replacementID = library.defaultDestinationID.flatMap({ defaultID in
            library.destinations.contains(where: { $0.id == defaultID }) ? defaultID : nil
        }) ?? library.destinations.first?.id else { return }
        let rerouted = try await inbox.rerouteOrphanedRequests(
            validDestinationIDs: Set(library.destinations.map(\.id)),
            to: replacementID,
            states: [.pending, .failed]
        )
        for requestID in rerouted {
            _ = try await inbox.retryFailed(requestID: requestID)
        }
    }

    private func processInboxRequest(id: UUID) async throws {
        guard let captureRootURL else { throw QuickCaptureViewModelError.storageUnavailable }
        let inbox = CaptureInbox(rootDirectoryURL: captureRootURL)
        try await recoverOrphanedInboxRequests(in: inbox)
        if let request = try await inbox.claim(requestID: id) {
            try await processClaimedInboxRequest(request, inbox: inbox)
            return
        }
        switch try await inbox.state(of: id) {
        case .completed, .processing:
            // The app-wide inbox drain may have won the race with this deep link.
            return
        case .failed:
            _ = try await inbox.retryFailed(requestID: id)
            guard let request = try await inbox.claim(requestID: id) else { return }
            try await processClaimedInboxRequest(request, inbox: inbox)
        case .pending:
            guard let request = try await inbox.claim(requestID: id) else { return }
            try await processClaimedInboxRequest(request, inbox: inbox)
        case nil:
            throw QuickCaptureViewModelError.inboxRequestUnavailable
        }
    }

    private func processClaimedInboxRequest(
        _ claimedRequest: CaptureRequest,
        inbox: CaptureInbox
    ) async throws {
        var request = claimedRequest
        guard let captureRootURL, let libraryStore else {
            throw QuickCaptureViewModelError.storageUnavailable
        }
        do {
            if request.voxProcessingState == .pending {
                request = await requestProcessor.process(request, assetRootURL: captureRootURL)
                try Task.checkCancellation()
                try await inbox.replaceProcessingRequest(request)
            }
            let library = try await libraryStore.load()
            guard let storedDestination = library.destinations.first(where: { $0.id == request.destinationID }) else {
                throw QuickCaptureViewModelError.unknownDestination
            }
            var destination = library.resolvedDestination(
                storedDestination,
                overrideEntryTemplateID: request.voxProfile?.captureEntryTemplateID
            )
            if let placement = request.voxProfile?.capturePlacementOverride {
                destination.placement = placement
            }
            let rootURL = try Self.resolveRootURL(for: destination)
            let didAccess = rootURL.startAccessingSecurityScopedResource()
            defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
            let receipt = try await pipeline.capture(
                request,
                destination: destination,
                rootURL: rootURL,
                assetRootURL: captureRootURL
            )
            try await inbox.complete(requestID: request.id)
            lastReceipt = receipt
            needsCaptureUnlock = false
            await recordHistory(
                request: request,
                destinationName: destination.name,
                relativeNotePath: CaptureHistoryRecord.relativeNotePath(
                    noteURL: receipt.noteURL,
                    rootURL: rootURL
                ),
                attachmentCount: receipt.attachmentURLs.count,
                outcome: .delivered,
                failureCategory: nil,
                receipt: receipt
            )
        } catch is CancellationError {
            try? await inbox.returnToPending(requestID: request.id)
            throw CancellationError()
        } catch let error as CaptureDeliveryQuotaError {
            try? await inbox.returnToPending(requestID: request.id)
            if case .limitReached = error {
                needsCaptureUnlock = true
            }
            throw error
        } catch let error as CapturePipelineError {
            if case .locationDecisionRequired(let reason) = error {
                // Preserve the exact processed request and origin outcome in a
                // pending state. This is a user decision, not delivery failure.
                try? await inbox.replaceProcessingRequest(request)
                try? await inbox.returnToPending(requestID: request.id)
                inboxLocationDecision = CaptureInboxLocationDecision(
                    requestID: request.id,
                    reason: reason,
                    source: request.source,
                    presetID: request.voxProfile?.id,
                    presetName: request.voxProfile?.accessibilityName
                )
                throw error
            }
            await recordHistory(
                request: request,
                destinationName: destinations.first(where: { $0.id == request.destinationID })?.name
                    ?? String(localized: "Unavailable destination"),
                relativeNotePath: nil,
                attachmentCount: request.payloads.flatMap(Self.assets(in:)).count,
                outcome: .failed,
                failureCategory: Self.historyFailureCategory(for: error),
                error: error
            )
            try? await inbox.fail(requestID: request.id)
            throw error
        } catch {
            await recordHistory(
                request: request,
                destinationName: destinations.first(where: { $0.id == request.destinationID })?.name
                    ?? String(localized: "Unavailable destination"),
                relativeNotePath: nil,
                attachmentCount: request.payloads.flatMap(Self.assets(in:)).count,
                outcome: .failed,
                failureCategory: Self.historyFailureCategory(for: error),
                error: error
            )
            try? await inbox.fail(requestID: request.id)
            throw error
        }
    }

    /// The destination's folder when it can be opened right now; nil for a
    /// stale or unresolvable bookmark, or a folder that no longer exists.
    nonisolated private static func reachableRootURL(for destination: CaptureDestination) -> URL? {
        guard let url = try? resolveRootURL(for: destination) else { return nil }
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return url
    }

    nonisolated private static func resolveRootURL(for destination: CaptureDestination) throws -> URL {
        let resolution = try CaptureBookmarkResolver.resolve(destination.rootBookmark)
        guard !resolution.isStale else {
            throw QuickCaptureViewModelError.staleDestination(destination.name)
        }
        return resolution.url
    }
}

/// What a composer Send did with the capture.
enum ComposerSubmitOutcome: Sendable {
    case delivered(CaptureReceipt)
    /// Held in the inbox because the vault folder couldn't be reached.
    case heldForVault(UUID)
}

struct CaptureInboxLocationDecision: Equatable {
    var requestID: UUID
    var reason: CaptureLocationUnavailableReason?
    var source: CaptureSource
    var presetID: String?
    var presetName: String?
}

struct CaptureLocationDecision: Equatable {
    var reason: CaptureLocationUnavailableReason
    var attemptedAt: Date
    var presetID: String
}

enum QuickCaptureViewModelError: Error, LocalizedError {
    case storageUnavailable
    case staleDestination(String)
    case unknownDestination
    case unknownVox
    case inboxRequestUnavailable
    case noteMustBeMarkdown
    case noteOutsideDestination
    case textTooLarge
    case assetsTooLarge
    case captureRouteBusy
    case stalePresetSwitch
    case urlDeliveryHandoffFailed(String)

    var errorDescription: String? {
        switch self {
        case .urlDeliveryHandoffFailed(let message):
            return String(localized: "URL delivery could not be saved. Your draft is preserved. \(message)")
        case .storageUnavailable:
            return String(localized: "Shared capture storage is unavailable.")
        case .staleDestination(let name):
            return String(localized: "The Files permission for ‘\(name)’ expired. Edit the destination and choose its folder again.")
        case .unknownDestination:
            return String(localized: "The requested capture destination no longer exists.")
        case .unknownVox:
            return String(localized: "The requested Route no longer exists or is disabled.")
        case .inboxRequestUnavailable:
            return String(localized: "The shared capture request is no longer pending.")
        case .noteMustBeMarkdown:
            return String(localized: "Choose a Markdown (.md) note.")
        case .noteOutsideDestination:
            return String(localized: "Choose a note inside the selected destination folder.")
        case .textTooLarge:
            return String(localized: "Capture text is above the 100,000-character safety limit.")
        case .assetsTooLarge:
            return String(localized: "Capture attachments exceed the 250 MB total safety limit.")
        case .captureRouteBusy:
            return String(localized: "Finish the current recording, import, send or route decision before changing this Capture’s route.")
        case .stalePresetSwitch:
            return String(localized: "This Capture changed or became busy. Open the route again to switch safely.")
        }
    }
}

/// One failed inbox request as shown by recovery UI.
struct CaptureFailedInboxEntry: Identifiable, Equatable {
    let requestID: UUID
    let createdAt: Date
    let source: CaptureSource
    let routeName: String?
    /// The rendered entry, or the plain captured text when it cannot render.
    let markdown: String?

    var id: UUID { requestID }
}

// MARK: - Live Notes

/// The composer as an editor of a real vault file: the first words are saved
/// through the regular capture pipeline (presets, processing, location,
/// attachments, history), then the composer stays bound to the written file
/// and every edit autosaves to it. New note releases the binding.
extension QuickCaptureViewModel {
    private var liveNoteBindingStore: LiveNoteBindingStore? {
        captureRootURL.map {
            LiveNoteBindingStore(fileURL: $0.appendingPathComponent("live-note-binding.json"))
        }
    }

    /// The vault root for a destination, if its folder is reachable now.
    func vaultRootURL(destinationID: UUID) -> URL? {
        guard let destination = destinations.first(where: { $0.id == destinationID }) else { return nil }
        return Self.reachableRootURL(for: destination)
    }

    /// Composer text without volatile live-transcript words.
    private var durableDraftText: String {
        var text = draft.text
        if var preview = liveRecordedTranscriptPreview {
            text = preview.cancel(in: text)
        }
        return text
    }

    /// What the save pill under the preset shows.
    var liveNoteStatus: LiveNoteStatus {
        if let liveNote { return liveNote.status }
        if liveNoteFirstSaveBlocked { return .unreachable }
        if isSubmitting, draft.hasCaptureContent { return .saving }
        return .idle
    }

    /// The recording dock's line: where the words are going right now.
    var liveNoteRecordingLine: (text: String, isLive: Bool)? {
        guard liveNotesEnabled else { return nil }
        if let liveNote {
            return (String(localized: "Writing to \(liveNote.binding.relativePath) as you talk"), true)
        }
        let target = resolvedDestinationPreview ?? selectedVoxProfile?.name ?? ""
        return (String(localized: "Saves to \(target) when you stop"), false)
    }

    /// The vault-relative file the composer is writing, for the breadcrumb.
    var liveNoteRelativePath: String? {
        liveNote?.binding.relativePath
    }

    func liveNoteTextDidChange() {
        guard liveNotesEnabled else { return }
        if let liveNote {
            // Words appear in the file as they are spoken; a cancelled
            // recording removes them again on the next save.
            liveNote.textDidChange(draft.text)
        } else {
            scheduleAutoFirstSave()
        }
    }

    /// Presets that rewrite text with on-device AI wait for a longer pause,
    /// so they process a thought rather than half a sentence.
    private var firstSaveDelay: Duration {
        guard let profile = selectedVoxProfile,
              profile.captureProcessingEnabled,
              profile.postProcessingMode != .none else { return .milliseconds(1500) }
        return .seconds(4)
    }

    func scheduleAutoFirstSave() {
        autoFirstSaveTask?.cancel()
        autoFirstSaveTask = nil
        guard liveNotesEnabled, liveNote == nil, draft.hasCaptureContent else {
            liveNoteFirstSaveBlocked = false
            return
        }
        let delay = firstSaveDelay
        autoFirstSaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            await self.performAutoFirstSave()
        }
    }

    private func performAutoFirstSave() async {
        autoFirstSaveTask = nil
        guard liveNotesEnabled, liveNote == nil, !isSubmitting,
              liveRecordedTranscriptPreview == nil, canSubmit else { return }
        guard let destination = selectedDestination,
              Self.reachableRootURL(for: destination) != nil else {
            // Keep the words in the durable draft; retry when the app becomes
            // active or the folder is reconnected.
            liveNoteFirstSaveBlocked = true
            return
        }
        liveNoteFirstSaveBlocked = false
        await submit()
    }

    /// Called from `submit()` after the first save wrote the note: load the
    /// whole file into the composer and keep editing it.
    private func bindDeliveredNote(
        receipt: CaptureReceipt,
        destinationID: UUID,
        submittedDraft: CaptureDraft,
        presetID: String?,
        draftStore: CaptureDraftStore
    ) async throws {
        let relativePath = historyRelativeNotePath(for: receipt, destinationID: destinationID)
            ?? receipt.noteURL.lastPathComponent
        // Words typed or dictated while the first save was running.
        let rebased = draft.rebased(afterSubmitting: submittedDraft)
        let remainder = rebased.hasCaptureContent ? rebased.text : ""
        try? await draftStore.complete(draftID: submittedDraft.id)

        var snapshot: VaultNoteSnapshot?
        if let rootURL = vaultRootURL(destinationID: destinationID) {
            snapshot = await Self.readVaultNote(rootURL: rootURL, relativePath: relativePath)
        }
        let fileText = snapshot?.text ?? receipt.renderedEntry ?? submittedDraft.text
        var editorText = fileText
        if !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            editorText += (editorText.hasSuffix("\n") ? "\n" : "\n\n") + remainder
        }
        var next = CaptureDraft(voxID: presetID, destinationSelectionMode: .inherited)
        next.text = editorText
        draft = next
        try await draftStore.save(draft)
        // Highlight the entry only when the file holds more than it (daily
        // notes, fixed notes): a new note *is* the entry.
        let entry = receipt.renderedEntry?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let whole = fileText.trimmingCharacters(in: .whitespacesAndNewlines)
        // A new-note preset's file *is* the entry; only appends get the card.
        let appendsIntoSharedFile: Bool = {
            guard let destination = destinations.first(where: { $0.id == destinationID }) else { return false }
            if case .newNote = destination.noteTarget { return submittedDraft.relativeNotePathOverride != nil }
            return true
        }()
        liveNoteHighlightedEntry = appendsIntoSharedFile && !entry.isEmpty && whole.count > entry.count + 8 ? entry : nil
        attachLiveNote(
            binding: LiveNoteBinding(
                destinationID: destinationID,
                relativePath: relativePath,
                savedVersion: snapshot?.version ?? VaultNoteVersion(text: fileText),
                entryRequestID: receipt.requestID,
                presetID: presetID
            ),
            text: editorText
        )
    }

    private func attachLiveNote(binding: LiveNoteBinding, text: String) {
        let session = LiveNoteSession(binding: binding, text: text) { [weak self] destinationID in
            self?.vaultRootURL(destinationID: destinationID)
        }
        session.applyExternalText = { [weak self] text in
            guard let self else { return }
            self.draft.text = text
            Task { try? await self.persistDurableDraft() }
        }
        let store = liveNoteBindingStore
        session.bindingDidChange = { binding in store?.save(binding) }
        store?.save(binding)
        liveNoteFirstSaveBlocked = false
        liveNote = session
        session.saveIfNeeded()
    }

    /// Reattaches the file the composer was editing before a relaunch.
    func restoreLiveNoteIfNeeded() async {
        guard liveNotesEnabled, liveNote == nil, let binding = liveNoteBindingStore?.load() else { return }
        attachLiveNote(binding: binding, text: draft.text)
        await liveNote?.checkDisk()
    }

    /// New note: save and close the open file, then start a blank note.
    func startNewNote() async {
        autoFirstSaveTask?.cancel()
        autoFirstSaveTask = nil
        if liveNote == nil, draft.hasCaptureContent {
            await submit()
            guard liveNote != nil else { return }
        }
        guard let session = liveNote else { return }
        await session.flush()
        lastClosedNote = ClosedLiveNote(
            binding: session.binding,
            presetName: selectedVoxProfile?.name ?? "",
            closedAt: Date()
        )
        liveNote = nil
        liveNoteHighlightedEntry = nil
        releaseEmbedScope()
        liveNoteBindingStore?.save(nil)
        let presetID = draft.voxID
        if let draftStore {
            try? await draftStore.complete(draftID: draft.id)
        }
        draft = CaptureDraft(voxID: presetID, destinationSelectionMode: .inherited)
        try? await persistDurableDraft()
    }

    /// Switching presets while a file is open closes that file first.
    func closeLiveNoteForPresetSwitch() {
        guard let session = liveNote else { return }
        lastClosedNote = ClosedLiveNote(
            binding: session.binding,
            presetName: selectedVoxProfile?.name ?? "",
            closedAt: Date()
        )
        liveNote = nil
        liveNoteHighlightedEntry = nil
        releaseEmbedScope()
        liveNoteBindingStore?.save(nil)
        let closedDraftID = draft.id
        let draftStore = self.draftStore
        Task {
            await session.flush()
            try? await draftStore?.complete(draftID: closedDraftID)
        }
        draft = CaptureDraft(voxID: draft.voxID, destinationSelectionMode: .inherited)
    }

    /// Reopens the note New note just closed (the toast's Reopen).
    func reopenClosedNote() async {
        guard let closed = lastClosedNote, liveNote == nil else { return }
        lastClosedNote = nil
        if draft.hasCaptureContent { return }
        await openLiveNote(binding: closed.binding)
    }

    /// Opens any vault note in the composer (Files → a note).
    func openLiveNote(binding: LiveNoteBinding) async {
        if let liveNote, liveNote.binding.relativePath == binding.relativePath,
           liveNote.binding.destinationID == binding.destinationID { return }
        if liveNote != nil { await startNewNote(); lastClosedNote = nil }
        guard let rootURL = vaultRootURL(destinationID: binding.destinationID),
              let snapshot = await Self.readVaultNote(rootURL: rootURL, relativePath: binding.relativePath) else {
            errorMessage = String(localized: "Vox.md can't open that file right now.")
            return
        }
        var opened = binding
        opened.savedVersion = snapshot.version
        liveNoteHighlightedEntry = nil
        if let draftStore {
            try? await draftStore.complete(draftID: draft.id)
        }
        var next = CaptureDraft(voxID: binding.presetID ?? draft.voxID, destinationSelectionMode: .inherited)
        next.text = snapshot.text
        draft = next
        try? await persistDurableDraft()
        attachLiveNote(binding: opened, text: snapshot.text)
    }

    func liveNoteSceneDidEnterBackground() async {
        await liveNote?.flush()
    }

    func liveNoteSceneDidBecomeActive() async {
        if let liveNote {
            await liveNote.checkDisk()
        } else if liveNoteFirstSaveBlocked || draft.hasCaptureContent {
            scheduleAutoFirstSave()
        }
    }

    nonisolated static func readVaultNote(rootURL: URL, relativePath: String) async -> VaultNoteSnapshot? {
        await Task.detached(priority: .userInitiated) {
            let didAccess = rootURL.startAccessingSecurityScopedResource()
            defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
            return try? VaultNoteDocument(rootURL: rootURL, relativePath: relativePath).read()
        }.value
    }
}

// MARK: - Files (vault tree)

/// One vault root shown in Files. Destinations that share a folder share a vault.
struct VaultRoot: Identifiable, Equatable {
    var destinationID: UUID
    var name: String
    var id: UUID { destinationID }
}

/// A preset shown as a badge on the folder or file it writes to.
struct VaultPresetBadge: Identifiable, Equatable, Hashable {
    var presetID: String
    var name: String
    var isSelected: Bool
    var id: String { presetID }

    var initial: String {
        name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "•"
    }
}

extension QuickCaptureViewModel {
    /// Distinct vault folders behind the configured destinations.
    var vaultRoots: [VaultRoot] {
        var seen = Set<Data>()
        var roots: [VaultRoot] = []
        for destination in destinations where seen.insert(destination.rootBookmark).inserted {
            roots.append(VaultRoot(destinationID: destination.id, name: destination.rootName))
        }
        return roots
    }

    /// Preset badges keyed by vault-relative folder or fixed note path, for
    /// the vault that `rootDestinationID` belongs to.
    func presetBadges(inVaultOf rootDestinationID: UUID) -> [String: [VaultPresetBadge]] {
        guard let root = destinations.first(where: { $0.id == rootDestinationID }) else { return [:] }
        let allowsLegacyFallback = !CapturePresetProfileStore.hasOwnedRouteMigration(defaults: defaults)
        let selectedID = selectedVoxProfile?.id
        var badges: [String: [VaultPresetBadge]] = [:]
        for profile in voxProfiles where profile.isEnabled {
            guard let destinationID = CapturePresetRouteResolver.destinationID(
                selectionMode: .inherited,
                explicitDestinationID: nil,
                profile: profile,
                destinations: destinations,
                libraryDefaultDestinationID: defaultDestinationID,
                allowsLegacyFallback: allowsLegacyFallback
            ),
                  let destination = destinations.first(where: { $0.id == destinationID }),
                  destination.rootBookmark == root.rootBookmark else { continue }
            let key = VaultFileIndex.fixedNote(for: destination.noteTarget)
                ?? VaultFileIndex.folder(for: destination.noteTarget)
            badges[key, default: []].append(VaultPresetBadge(
                presetID: profile.id,
                name: profile.name,
                isSelected: profile.id == selectedID
            ))
        }
        return badges
    }

    /// Lists one folder level of a vault off the main actor.
    func vaultChildren(rootDestinationID: UUID, relativeDirectory: String) async -> [VaultFileEntry]? {
        guard let rootURL = vaultRootURL(destinationID: rootDestinationID) else { return nil }
        return await Task.detached(priority: .userInitiated) {
            let didAccess = rootURL.startAccessingSecurityScopedResource()
            defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
            return try? VaultFileIndex.children(of: relativeDirectory, rootURL: rootURL)
        }.value
    }

    /// First line of real text in a note, for list previews.
    func vaultNotePreview(rootDestinationID: UUID, relativePath: String) async -> String? {
        guard let rootURL = vaultRootURL(destinationID: rootDestinationID) else { return nil }
        return await Task.detached(priority: .utility) {
            let didAccess = rootURL.startAccessingSecurityScopedResource()
            defer { if didAccess { rootURL.stopAccessingSecurityScopedResource() } }
            let url = rootURL.appendingPathComponent(relativePath)
            guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
            defer { try? handle.close() }
            let data = (try? handle.read(upToCount: 2048)) ?? Data()
            let text = String(decoding: data, as: UTF8.self)
            return Self.previewLine(from: text)
        }.value
    }

    nonisolated static func previewLine(from markdown: String) -> String? {
        var lines = markdown.components(separatedBy: .newlines)[...]
        if lines.first?.trimmingCharacters(in: .whitespaces) == "---" {
            lines = lines.dropFirst()
            if let end = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) {
                lines = lines[lines.index(after: end)...]
            }
        }
        for line in lines {
            var trimmed = line.trimmingCharacters(in: .whitespaces)
            while let first = trimmed.first, "#->*".contains(first) {
                trimmed.removeFirst()
                trimmed = trimmed.trimmingCharacters(in: .whitespaces)
            }
            if trimmed.hasPrefix("[ ]") || trimmed.hasPrefix("[x]") {
                trimmed = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            }
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }
}

// MARK: - Live preview embeds

extension QuickCaptureViewModel {
    /// The file an embed in the open note points to (`![[clip.wav]]`), found
    /// the way Obsidian does: attachments folder, the note's folder, the vault
    /// root, then anywhere in the vault by name.
    func liveNoteEmbedURL(_ target: String) -> URL? {
        guard let liveNote else { return nil }
        let binding = liveNote.binding
        let cacheKey = "\(binding.destinationID.uuidString)|\(binding.relativePath)|\(target)"
        if let cached = embedURLCache[cacheKey] { return cached }
        guard let root = scopedEmbedRoot(for: binding.destinationID) else { return nil }
        let attachments = destinations.first(where: { $0.id == binding.destinationID })?
            .attachmentsFolderName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "attachments"
        let resolved = Self.resolveEmbed(
            target,
            noteRelativePath: binding.relativePath,
            rootURL: root,
            attachmentsFolder: attachments.isEmpty ? "attachments" : attachments
        )
        embedURLCache[cacheKey] = resolved
        return resolved
    }

    private func scopedEmbedRoot(for destinationID: UUID) -> URL? {
        if let scoped = embedScopedRoot, scoped.destinationID == destinationID { return scoped.url }
        releaseEmbedScope()
        guard let destination = destinations.first(where: { $0.id == destinationID }),
              let url = try? CaptureBookmarkResolver.resolve(destination.rootBookmark).url else { return nil }
        // Players read the file after this returns; keep access until the note closes.
        _ = url.startAccessingSecurityScopedResource()
        embedScopedRoot = (destinationID, url)
        return url
    }

    func releaseEmbedScope() {
        embedScopedRoot?.url.stopAccessingSecurityScopedResource()
        embedScopedRoot = nil
        embedURLCache = [:]
    }

    nonisolated static func resolveEmbed(
        _ target: String,
        noteRelativePath: String,
        rootURL: URL,
        attachmentsFolder: String,
        fileManager: FileManager = .default
    ) -> URL? {
        let cleaned = target.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, !cleaned.hasPrefix("/"), !cleaned.contains("..") else { return nil }
        if let url = URL(string: cleaned), url.scheme != nil { return url.isFileURL ? url : nil }
        let noteFolder = (noteRelativePath as NSString).deletingLastPathComponent
        let candidates = [
            "\(attachmentsFolder)/\(cleaned)",
            noteFolder.isEmpty ? cleaned : "\(noteFolder)/\(cleaned)",
            noteFolder.isEmpty ? "\(attachmentsFolder)/\(cleaned)" : "\(noteFolder)/\(attachmentsFolder)/\(cleaned)",
            cleaned,
        ]
        for candidate in candidates {
            let url = rootURL.appendingPathComponent(candidate)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        // Obsidian resolves a bare name anywhere in the vault.
        let name = (cleaned as NSString).lastPathComponent
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 20_000 { break }
            if url.lastPathComponent == name { return url }
        }
        return nil
    }
}

// MARK: - Attachments in an open note

extension QuickCaptureViewModel {
    /// With a note open, attachments can't wait for a first save that
    /// already happened: copy each staged file into the vault's attachments
    /// folder and add an embed (`![[photo.jpg]]`) to the note, which then
    /// autosaves. Links become Markdown links.
    func embedPendingAttachmentsInLiveNote() async {
        guard let liveNote, !draft.additionalPayloads.isEmpty,
              let stagingDirectory = stagingDirectoryURL else { return }
        let binding = liveNote.binding
        guard let root = scopedEmbedRoot(for: binding.destinationID) else {
            // Vault unreachable: keep them staged; they embed on the next try.
            return
        }
        let folder = destinations.first(where: { $0.id == binding.destinationID })?
            .attachmentsFolderName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "attachments"
        let attachmentsFolder = folder.isEmpty ? "attachments" : folder
        var lines: [String] = []
        var embedded: [CapturePayload] = []
        for payload in draft.additionalPayloads {
            switch payload {
            case .url(let url, let title):
                lines.append(title.map { "[\($0)](\(url.absoluteString))" } ?? "<\(url.absoluteString)>")
                embedded.append(payload)
            case .text(let text):
                lines.append(text)
                embedded.append(payload)
            default:
                let assets = Self.assets(in: payload)
                let names = await Self.copyIntoVault(
                    assets,
                    from: stagingDirectory,
                    to: root.appendingPathComponent(attachmentsFolder, isDirectory: true)
                )
                guard names.count == assets.count else { continue }
                lines += names.map { "![[\($0)]]" }
                if case .scannedDocument(_, _, let extracted?) = payload, !extracted.isEmpty {
                    lines.append(extracted)
                }
                embedded.append(payload)
            }
        }
        guard !embedded.isEmpty else { return }
        draft.additionalPayloads.removeAll { embedded.contains($0) }
        let stager = CaptureAssetStager(directoryURL: stagingDirectory)
        for asset in embedded.flatMap(Self.assets(in:)) {
            try? await stager.remove(asset)
        }
        var text = draft.text
        if !text.isEmpty, !text.hasSuffix("\n") { text += "\n" }
        if !text.isEmpty { text += "\n" }
        text += lines.joined(separator: "\n\n") + "\n"
        draft.text = text
        embedURLCache = [:]
        scheduleDraftSave()
    }

    /// Copies staged files into the vault, never overwriting: a taken name
    /// becomes "name 2.ext". Returns the names written, in order.
    nonisolated private static func copyIntoVault(
        _ assets: [CaptureAssetReference],
        from stagingDirectory: URL,
        to folder: URL
    ) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            var names: [String] = []
            for asset in assets {
                let source = stagingDirectory.appendingPathComponent(asset.relativePath)
                let original = (asset.originalFilename as NSString).lastPathComponent
                let stem = (original as NSString).deletingPathExtension
                let ext = (original as NSString).pathExtension
                var name = original.isEmpty ? (asset.relativePath as NSString).lastPathComponent : original
                var index = 2
                while fm.fileExists(atPath: folder.appendingPathComponent(name).path) {
                    name = ext.isEmpty ? "\(stem) \(index)" : "\(stem) \(index).\(ext)"
                    index += 1
                }
                do {
                    try fm.copyItem(at: source, to: folder.appendingPathComponent(name))
                    names.append(name)
                } catch {
                    break
                }
            }
            return names
        }.value
    }
}
