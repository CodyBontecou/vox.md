import AppIntents
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import VoxboardShared

/// Manage reusable Capture Presets across text, links, media, scans, files,
/// and voice recordings. A preset owns its processing, metadata, and complete
/// Markdown destination.
struct CapturePresetSettingsView: View {
    @State private var flows: [CapturePreset] = CapturePresetStore.loadFlows()
    @State private var pins = CapturePresetSettingsPins()
    @State private var watchStatePublishTask: Task<Void, Never>?
    @State private var deletionError: String?
    @State private var destinations: [UUID: CaptureDestination] = [:]
    @State private var surfacePinRevision = 0
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            introSection
            routeListSection
            routeToolsSection
        }
        .listStyle(.grouped)
        .navigationTitle("Routes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // The large in-content title replaces the bar title.
                Text(verbatim: "").accessibilityHidden(true)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    persistedFlows.wrappedValue.append(CapturePresetStore.makeCustomFlow())
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                        Text("New")
                            .font(.custom("Geist-SemiBold", size: 15, relativeTo: .body))
                    }
                    .foregroundStyle(Geist.bg)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 36)
                    .background(Geist.text, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add Route")
                .accessibilityIdentifier("capture_preset_add")
            }
        }
        .font(Geist.body())
        .tint(Geist.accent)
        .scrollContentBackground(.hidden)
        .background(Geist.bg.ignoresSafeArea())
        .toolbarBackground(Geist.bg, for: .navigationBar)
        .task { await migrateRoutesAndReload() }
        .onAppear { pins.reload() }
        .alert("Route Could Not Be Deleted", isPresented: Binding(
            get: { deletionError != nil }, set: { if !$0 { deletionError = nil } }
        )) { Button("OK", role: .cancel) {} } message: { Text(deletionError ?? "") }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { pins.reload() }
        }
        .onDisappear {
            watchStatePublishTask?.cancel()
            WatchRecordingController.shared.publishState()
        }
    }

    /// Save at the edit boundary: the list's onChange is not guaranteed to run
    /// while its navigation destination is covering it.
    private var persistedFlows: Binding<[CapturePreset]> {
        Binding(
            get: { flows },
            set: { updated in
                flows = updated
                CapturePresetStore.saveFlows(updated)
                // Read the actual saved full profiles, never the list's possible
                // loadFlows fallback, before updating pin identity/availability.
                pins.reload()
                if #available(iOS 18.0, *) {
                    VoxboardShortcutsProvider.updateAppShortcutParameters()
                }
                scheduleWatchStatePublish()
            }
        )
    }

    private func scheduleWatchStatePublish() {
        watchStatePublishTask?.cancel()
        watchStatePublishTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            WatchRecordingController.shared.publishState()
        }
    }

    private func migrateRoutesAndReload() async {
        if let url = AppConstants.captureLibraryURL {
            let store = CaptureLibraryStore(fileURL: url)
            if let library = try? await CapturePresetRouteLibrary.load(from: store) {
                destinations = Dictionary(
                    library.destinations.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )
            }
        }
        flows = CapturePresetStore.loadFlows()
        pins.reload()
    }

    /// One flat list of route cards, as on the Routes board. Capture Bar
    /// pinning lives in each card's long-press menu; its order and any
    /// unavailable pins are managed from "Capture Bar Order" below.
    private var routeListSection: some View {
        Section {
            ForEach(flows.map(\.id), id: \.self) { id in
                if let flow = persistedFlowBinding(for: id) {
                    presetSettingsRow(flow: flow)
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Long-press a route to pin it to widgets, Control Center, the keyboard and Apple Watch.")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = pins.errorMessage ?? pins.storageMessage {
                    Text(message)
                        .font(Geist.caption())
                        .foregroundStyle(Geist.error)
                        .accessibilityIdentifier("capture_preset_pins_error")
                    Button("Reload") { pins.reload() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("capture_preset_pins_reload")
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
    }

    /// Capture Bar order and the shared entry templates, at the end of the list.
    private var routeToolsSection: some View {
        Section {
            NavigationLink {
                CaptureBarPinOrderView(
                    pins: pins,
                    flows: flows,
                    isDefault: isDefault
                )
            } label: {
                routeToolLabel(
                    systemImage: "pin",
                    title: "Capture Bar Order",
                    detail: pins.orderedIDs.isEmpty
                        ? String(localized: "No pinned routes")
                        : String(localized: "\(pins.orderedIDs.count) pinned")
                )
            }
            .accessibilityIdentifier("capture_preset_pins_order")
            .presetCardRow()

            NavigationLink {
                CaptureEntryTemplateLibraryView()
            } label: {
                routeToolLabel(
                    systemImage: "doc.text",
                    title: "Entry Templates",
                    detail: String(localized: "Shared Formatting")
                )
            }
            .presetCardRow()
        }
    }

    private func routeToolLabel(systemImage: String, title: LocalizedStringKey, detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Geist.text)
                .frame(width: 40, height: 40)
                .background(Geist.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Geist-SemiBold", size: 17, relativeTo: .body))
                    .foregroundStyle(Geist.text)
                Text(detail)
                    .font(Geist.mono(size: 11.5, relativeTo: .caption))
                    .foregroundStyle(Geist.muted)
            }
        }
    }

    private func persistedFlowBinding(for id: String) -> Binding<CapturePreset>? {
        guard let fallback = flows.first(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                persistedFlows.wrappedValue.first(where: { $0.id == id }) ?? fallback
            },
            set: { updatedFlow in
                var updatedFlows = persistedFlows.wrappedValue
                guard let index = updatedFlows.firstIndex(where: { $0.id == id }) else { return }
                updatedFlows[index] = updatedFlow
                persistedFlows.wrappedValue = updatedFlows
            }
        )
    }

    private func presetSettingsRow(flow: Binding<CapturePreset>) -> some View {
        let preset = flow.wrappedValue
        return NavigationLink {
            CapturePresetEditorView(preset: flow)
        } label: {
            CapturePresetSettingsListLabel(
                preset: preset,
                badge: badge(for: preset),
                isDefault: isDefault(preset),
                path: routePath(for: preset),
                steps: routeSteps(for: preset)
            )
        }
        .accessibilityIdentifier("capture_preset_edit_\(preset.id)")
        .accessibilityValue(pins.preferences.isPinned(id: preset.id)
            ? String(localized: "Pinned to Capture Bar")
            : "")
        .swipeActions(edge: .trailing) {
            if !preset.isBuiltIn {
                Button("Delete", role: .destructive) {
                    delete(preset)
                }
            }
        }
        .contextMenu {
            let _ = surfacePinRevision
            Section("Pin to") {
                ForEach(CapturePresetPinSurface.allCases) { surface in
                    let pinned = RouteSurfacePins.isPinned(surface, id: preset.id)
                    Button {
                        RouteSurfacePins.set(!pinned, surface: surface, id: preset.id)
                        surfacePinRevision &+= 1
                    } label: {
                        Label(surface.displayName, systemImage: pinned ? "checkmark" : surface.systemImage)
                    }
                    .accessibilityValue(pinned ? String(localized: "Pinned") : String(localized: "Not pinned"))
                }
            }
            Button {
                pins.setPinned(!pins.preferences.isPinned(id: preset.id), id: preset.id)
            } label: {
                Label(pins.preferences.isPinned(id: preset.id)
                      ? String(localized: "Unpin from Capture Bar")
                      : String(localized: "Pin to Capture Bar"),
                      systemImage: pins.preferences.isPinned(id: preset.id) ? "pin.slash" : "pin")
            }
        }
        .presetCardRow()
    }

    private func isDefault(_ flow: CapturePreset) -> Bool {
        flow.id == CapturePresetProfileStore.selectedProfileID(defaults: AppConstants.sharedDefaults)
    }

    private func routeDestination(for flow: CapturePreset) -> CaptureDestination? {
        flow.captureDestinationID.flatMap { destinations[$0] }
    }

    /// Mono path line: `Vox Notes / Meetings / {date}.md`,
    /// `Vox Notes / Tasks.md › ## Today`, or the Watch recording folder.
    private func routePath(for flow: CapturePreset) -> String? {
        if flow.watchOutputMode == .recordingOnly {
            let folder = flow.watchRecordingSettings.folderName
            return folder.isEmpty ? nil : folder
        }
        guard let destination = routeDestination(for: flow) else { return nil }
        return RouteDestinationFormatter.listPath(destination)
    }

    /// `process → deliver` chips built only from stored preset state.
    private func routeSteps(for flow: CapturePreset) -> [String] {
        if flow.watchOutputMode == .recordingOnly {
            return [String(localized: "Recording Only (Watch)")]
        }
        var steps = [routeInputLabel(flow), flow.postProcessingMode.displayName]
        if let destination = routeDestination(for: flow) {
            steps.append(captureDeliverLabel(destination))
        }
        return steps
    }

    private func badge(for flow: CapturePreset) -> String? {
        if flow.id == CapturePresetProfileStore.selectedProfileID(defaults: AppConstants.sharedDefaults) {
            return String(localized: "Default")
        }
        if flow.id == CapturePresetStore.selectedFlowId() {
            return String(localized: "Keyboard")
        }
        return nil
    }

    private var introSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Routes")
                    .font(.custom("Geist-SemiBold", size: 34, relativeTo: .largeTitle))
                    .tracking(-0.8)
                    .foregroundStyle(Geist.text)
                    .accessibilityAddTraits(.isHeader)
                Text("Where a capture goes, and what happens on the way.")
                    .font(Geist.body(.callout))
                    .foregroundStyle(Geist.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
        }
    }

    private func delete(_ flow: CapturePreset) {
        do {
            try URLDeliveryKeychain.deleteCredentials(for: flow.exportSettings.urlDelivery)
        } catch {
            deletionError = String(localized: "Saved URL credentials could not be removed. Unlock your device and try again. The route has not been deleted.")
            return
        }
        CapturePresetStore.retirePreset(
            id: flow.id,
            ownedRouteID: flow.captureDestinationID
        )
        CapturePresetSurfacePinStore.remove(id: flow.id, defaults: AppConstants.sharedDefaults)
        persistedFlows.wrappedValue.removeAll { $0.id == flow.id }
        pins.pruneAfterPersistedDeletion(id: flow.id)
        let fallbackID = flows.first?.id ?? CapturePresetStore.generalId
        if CapturePresetStore.selectedFlowId() == flow.id {
            CapturePresetStore.selectFlow(id: fallbackID)
        }
        if CapturePresetProfileStore.selectedProfileID(defaults: AppConstants.sharedDefaults) == flow.id {
            CapturePresetProfileStore.selectCaptureProfile(
                id: fallbackID,
                defaults: AppConstants.sharedDefaults
            )
        }
    }
}

/// Note target and placement wording shared by the route list and editor:
/// `Meetings / {date}.md` and "append" / "under ## Today".
private func captureDestinationParts(_ destination: CaptureDestination) -> (target: String, placement: String) {
    let target = RouteDestinationFormatter.displayPath(destination, includesRoot: false, includesHeading: false)
    let placement: String
    switch destination.placement {
    case .append: placement = String(localized: "append")
    case .prepend: placement = String(localized: "prepend")
    case .beneathHeading(let heading, _, let position):
        placement = position == .bottom
            ? String(localized: "end of \(heading.title)")
            : String(localized: "under \(heading.title)")
    }
    return (target, placement)
}

/// Input chip, from the Routes board: a route that keeps the original is a
/// voice route ("Voice"); Clean prose tidies anything you send it
/// ("Anything"); structured modes (Meeting summary, Checklist, custom) shape
/// the modalities their processing scope covers ("Voice + text", "Voice",
/// "Text").
private func routeInputLabel(_ flow: CapturePreset) -> String {
    switch flow.postProcessingMode {
    case .none:
        return String(localized: "Voice")
    case .clean where flow.captureProcessingScope == .both:
        return String(localized: "Anything")
    default:
        switch flow.captureProcessingScope {
        case .both: return String(localized: "Voice + text")
        case .voiceOnly: return String(localized: "Voice")
        case .textOnly: return String(localized: "Text")
        }
    }
}

/// Deliver chip: "New note", "Daily · append", "Weekly · prepend",
/// "Under heading"…
private func captureDeliverLabel(_ destination: CaptureDestination) -> String {
    switch destination.noteTarget {
    case .newNote: return String(localized: "New note")
    case .rollingNote(_, let period):
        let periodName: String = switch period {
        case .daily: String(localized: "Daily")
        case .weekly: String(localized: "Weekly")
        case .monthly: String(localized: "Monthly")
        case .quarterly: String(localized: "Quarterly")
        case .yearly: String(localized: "Yearly")
        }
        return "\(periodName) · \(RouteDestinationFormatter.placementWord(destination))"
    case .existingNote:
        switch destination.placement {
        case .append: return String(localized: "Append")
        case .prepend: return String(localized: "Prepend")
        case .beneathHeading: return String(localized: "Under heading")
        }
    }
}

/// Capture Bar pins in their order, with drag-to-reorder, unpin, and
/// recovery rows for pins whose route is unavailable. Pinning itself is in
/// each route card's long-press menu.
private struct CaptureBarPinOrderView: View {
    let pins: CapturePresetSettingsPins
    let flows: [CapturePreset]
    let isDefault: (CapturePreset) -> Bool

    var body: some View {
        List {
            Section {
                if pins.orderedIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("No Pinned Routes", systemImage: "pin.slash")
                            .font(Geist.label(.body))
                            .foregroundStyle(Geist.text)
                        Text("Long-press a route on the Routes screen and choose Pin to Capture Bar.")
                            .font(Geist.caption())
                            .foregroundStyle(Geist.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("capture_preset_pins_empty")
                    .presetCardRow()
                }
                ForEach(pins.orderedIDs, id: \.self) { id in
                    if let preset = flows.first(where: { $0.id == id }) {
                        HStack(spacing: 12) {
                            CapturePresetSettingsListLabel(
                                preset: preset,
                                badge: isDefault(preset) ? String(localized: "Default") : nil
                            )
                            CapturePresetSettingsPinButton(
                                accessibilityID: "capture_preset_list_pin_\(preset.id)",
                                name: preset.accessibilityName,
                                isPinned: true
                            ) {
                                pins.setPinned(false, id: preset.id)
                            }
                        }
                        .presetCardRow()
                    } else {
                        CapturePresetSettingsPinnedRow(id: id, profile: pins.profile(id: id)) {
                            pins.setPinned(false, id: id)
                        }
                        .presetCardRow()
                    }
                }
                .onMove { offsets, destination in
                    pins.move(fromOffsets: offsets, toOffset: destination)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(footer)
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                    if let message = pins.errorMessage ?? pins.storageMessage {
                        Text(message)
                            .font(Geist.caption())
                            .foregroundStyle(Geist.error)
                        Button("Reload") { pins.reload() }
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .listStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Geist.bg.ignoresSafeArea())
        .font(Geist.body())
        .tint(Geist.accent)
        .navigationTitle("Capture Bar Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if pins.orderedIDs.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                        .font(Geist.label(.body))
                        .accessibilityIdentifier("capture_preset_pins_edit")
                }
            }
        }
    }

    private var footer: LocalizedStringResource {
        switch pins.orderedIDs.count {
        case 0:
            "Pinning adds Capture Bar quick actions without changing your default or keyboard route."
        case 1:
            "Pin another route to arrange their order. Disabled routes keep their position and reappear when enabled. Pinning does not change your default or keyboard route."
        default:
            "Pinned routes appear in this order in the Capture Bar. Tap Edit to drag them. Disabled routes keep their position and reappear when enabled. Pinning does not change your default or keyboard route."
        }
    }
}

/// Mono uppercase Signal section label for the preset list.
private struct PresetListSectionHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(Geist.mono(size: 11, relativeTo: .caption))
            .tracking(0.66)
            .foregroundStyle(Geist.muted)
            .accessibilityAddTraits(.isHeader)
    }
}

private extension View {
    /// Draws a List row as a white, bordered 18pt Signal card while keeping
    /// native List behaviors (swipe, reorder, navigation) intact.
    func presetCardRow() -> some View {
        self
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 19, leading: 30, bottom: 19, trailing: 24))
            .listRowBackground(
                RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                    .fill(Geist.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                            .stroke(Geist.border, lineWidth: 1)
                    )
                    .padding(.vertical, 5)
                    .padding(.horizontal, 16)
            )
    }
}

/// Internal so the iPad route inspector can open it for the current route.
struct CapturePresetEditorView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @Environment(ModelManager.self) private var modelManager
    @State private var pinnedSurfaces: [CapturePresetPinSurface] = []
    @Binding var flow: CapturePreset
    @State private var frontmatterText: String
    @State private var showBookmarkPicker = false
    @State private var bookmarkPickerKind: BookmarkKind = .exportFolder
    @State private var captureDestinations: [CaptureDestination] = []
    @State private var captureEntryTemplates: [CaptureEntryTemplate] = []
    @State private var captureDestinationLoadError: String?
    @State private var isEditingDestination = false
    @State private var isCaptureProcessingInfoPresented = false
    @State private var recordingDeliveryNotificationsDenied = false
    /// The route's latest delivered entry from the Library, when one exists.
    @State private var lastCapturePreview: RoutePreviewContent?

    private enum BookmarkKind {
        case exportFolder
        case audioFolder
        case markdownTemplate
        case watchRecordingFolder

        var allowedContentTypes: [UTType] {
            switch self {
            case .exportFolder, .audioFolder, .watchRecordingFolder:
                return [.folder]
            case .markdownTemplate:
                return [.init(filenameExtension: "md") ?? .plainText, .plainText]
            }
        }
    }

    init(preset: Binding<CapturePreset>) {
        self._flow = preset
        self._frontmatterText = State(initialValue: Self.renderFrontmatter(preset.wrappedValue.staticFrontmatter))
    }

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            editorHeader
            if flow.watchOutputMode != .recordingOnly {
                routeOverviewSection(proxy: proxy)
                routePreviewSection
                quickActionsSection
                quickTogglesSection
            }
            Group {
                identitySection
                watchOutputSection
                if flow.watchOutputMode != .recordingOnly {
                    voiceProcessingSection
                    postProcessingSection
                    ownedDestinationSection
                    if flow.captureDestinationID == nil {
                        fileExportSection
                    }
                    urlDeliverySection
                    if showsFrontmatterSection {
                        frontmatterSection
                        locationMetadataSection
                    }
                    audioExportSection
                }
            }
            .listRowBackground(Geist.card)
        }
        .scrollContentBackground(.hidden)
        .background(Geist.bg.ignoresSafeArea())
        .tint(Geist.accent)
        .navigationTitle(flow.visibleName ?? String(localized: "Route"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                // The route header in the form replaces the bar title.
                Text(verbatim: "").accessibilityHidden(true)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    flow.staticFrontmatter = Self.parseFrontmatter(frontmatterText)
                    dismiss()
                } label: {
                    Text("Done")
                        .font(.custom("Geist-SemiBold", size: 15, relativeTo: .body))
                        .foregroundStyle(Geist.bg)
                        .padding(.horizontal, 16)
                        .frame(minHeight: 36)
                        .background(Geist.text, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("capture_preset_editor_done")
            }
        }
        .toolbarBackground(Geist.bg, for: .navigationBar)
        .onAppear {
            // Effective pins: Watch and the keyboard list every enabled route
            // until configured, so the editor matches what those surfaces show.
            pinnedSurfaces = CapturePresetPinSurface.allCases.filter { surface in
                RouteSurfacePins.isUnconfiguredFallback(surface)
                    ? flow.isEnabled
                    : RouteSurfacePins.isPinned(surface, id: flow.id)
            }
        }
        .task {
            await loadCaptureDestinations()
            await refreshRecordingDeliveryNotificationStatus()
        }
        .task(id: flow.captureDestinationID) {
            lastCapturePreview = await Self.loadLastCapturePreview(
                routeID: flow.id,
                destinationID: flow.captureDestinationID
            )
        }
        .onAppear {
            // File export now lives on each flow. Mark old flow records as
            // per-flow when the user opens them so later edits do not fall back
            // to the legacy app-wide Files tab settings.
            flow.exportSettings.usesCustomExportSettings = true
        }
        .sheet(isPresented: $isEditingDestination) {
            NavigationStack {
                CaptureDestinationEditorView(
                    existing: ownedDestination,
                    templates: captureEntryTemplates,
                    fixedName: flow.visibleName ?? String(localized: "Icon-only route")
                ) { destination in
                    try await saveOwnedDestination(destination)
                }
            }
        }
        .sheet(isPresented: $isCaptureProcessingInfoPresented) {
            CaptureTextProcessingInfoView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fileImporter(
            isPresented: $showBookmarkPicker,
            allowedContentTypes: bookmarkPickerKind.allowedContentTypes,
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            saveBookmark(url: url, kind: bookmarkPickerKind)
        }
        .onDisappear {
            flow.staticFrontmatter = Self.parseFrontmatter(frontmatterText)
        }
        }
    }

    private var showsFrontmatterSection: Bool { true }

    // MARK: Signal route header and overview

    private var isDefaultPreset: Bool {
        flow.id == CapturePresetProfileStore.selectedProfileID(defaults: AppConstants.sharedDefaults)
    }

    private var editorHeaderSubtitle: String {
        var parts: [String] = []
        if isDefaultPreset {
            parts.append(String(localized: "Default route"))
        } else if flow.id == CapturePresetStore.selectedFlowId() {
            parts.append(String(localized: "Keyboard route"))
        }
        if !flow.isEnabled {
            parts.append(String(localized: "Disabled"))
        }
        if !pinnedSurfaces.isEmpty {
            let names = ListFormatter.localizedString(byJoining: pinnedSurfaces.map(\.inlineName))
            parts.append(String(localized: "pinned to \(names)"))
        }
        if parts.isEmpty {
            parts.append(String(localized: "Route"))
        }
        let joined = parts.joined(separator: " · ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }

    private var editorHeader: some View {
        Section {
            HStack(spacing: 14) {
                CapturePresetSettingsRouteTile(preset: flow, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(flow.visibleName ?? String(localized: "Icon-only route"))
                        .font(.custom("Geist-SemiBold", size: 28, relativeTo: .title))
                        .tracking(-0.56)
                        .foregroundStyle(flow.visibleName == nil ? Geist.muted : Geist.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(editorHeaderSubtitle)
                        .font(Geist.body(.callout))
                        .foregroundStyle(Geist.muted)
                }
                Spacer(minLength: 0)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }
    }

    private struct RouteStep: Identifiable {
        let id: Int
        let kind: String
        let title: String
        let detail: String?
    }

    private var routeSteps: [RouteStep] {
        let prompt = flow.capturePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let processDetail: String = {
            guard flow.captureProcessingEnabled else {
                return String(localized: "Apple Intelligence off · kept as captured")
            }
            var parts = [String(localized: "On-device Apple Intelligence")]
            if flow.captureProcessingScope != .both {
                parts.append(flow.captureProcessingScope.displayName)
            }
            parts.append(String(localized: "falls back to the raw transcript offline"))
            return parts.joined(separator: " · ")
        }()
        let shape = shapeStep
        let deliverTitle: String
        let deliverDetail: String?
        if let destination = ownedDestination {
            deliverTitle = RouteDestinationFormatter.deliverTitle(destination)
            deliverDetail = RouteDestinationFormatter.deliverDetail(destination)
        } else if flow.exportSettings.exportEnabled, !flow.exportSettings.folderName.isEmpty {
            deliverTitle = flow.exportSettings.folderName
            deliverDetail = nil
        } else {
            deliverTitle = String(localized: "Destination Not Configured")
            deliverDetail = nil
        }
        return [
            RouteStep(
                id: 1,
                kind: String(localized: "Capture"),
                title: String(localized: "Voice, text, photos, scans"),
                detail: prompt.isEmpty ? nil : String(localized: "Empty prompt: “\(prompt)”")
            ),
            RouteStep(id: 2, kind: String(localized: "Process"), title: flow.postProcessingMode.displayName, detail: processDetail),
            RouteStep(id: 3, kind: String(localized: "Shape"), title: shape.title, detail: shape.detail),
            RouteStep(id: 4, kind: String(localized: "Deliver"), title: deliverTitle, detail: deliverDetail),
        ]
    }

    /// The entry template this route renders with: the route's own template,
    /// else its destination's template, else the destination's inline
    /// prefix and suffix.
    private var effectiveEntryFormatting: (name: String?, prefix: String, suffix: String) {
        let templateID = flow.captureEntryTemplateID ?? ownedDestination?.entryTemplateID
        if let templateID, let template = captureEntryTemplates.first(where: { $0.id == templateID }) {
            return (template.name, template.entryPrefix, template.entrySuffix)
        }
        return (nil, ownedDestination?.entryPrefix ?? "", ownedDestination?.entrySuffix ?? "")
    }

    /// SHAPE step: "Timestamped entry" / `### {time} · {title}, then body and
    /// attachments`, derived from the route's entry template.
    private var shapeStep: (title: String, detail: String?) {
        let formatting = effectiveEntryFormatting
        let firstLine = formatting.prefix
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let derivedTitle: String
        if let firstLine {
            let timeTokens = ["{time}", "{timestamp}", "{hour}", "{minute}"]
            if timeTokens.contains(where: { firstLine.contains($0) }) {
                derivedTitle = String(localized: "Timestamped entry")
            } else if firstLine.contains("{date}") {
                derivedTitle = String(localized: "Dated entry")
            } else {
                derivedTitle = String(localized: "Formatted entry")
            }
        } else {
            derivedTitle = String(localized: "Plain entry")
        }
        let templateName = formatting.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let title = templateName.isEmpty ? derivedTitle : templateName
        let detail: String
        if let firstLine {
            detail = String(localized: "\(firstLine), then body and attachments")
        } else {
            detail = String(localized: "Body and attachments")
        }
        return (title, detail)
    }

    /// CAPTURE → PROCESS → SHAPE → DELIVER rail. Each card jumps to the
    /// section that edits it; Deliver opens the destination editor.
    private func openStep(_ id: Int, proxy: ScrollViewProxy) {
        let target: String
        switch id {
        case 1: target = "step-capture"
        case 2: target = "step-process"
        case 3: target = "step-shape"
        default:
            isEditingDestination = true
            return
        }
        withAnimation { proxy.scrollTo(target, anchor: .top) }
    }

    private func routeOverviewSection(proxy: ScrollViewProxy) -> some View {
        let steps = routeSteps
        return Section {
            VStack(spacing: 0) {
                ForEach(steps) { step in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 4) {
                            Text(verbatim: "\(step.id)")
                                .font(Geist.mono(size: 12, relativeTo: .caption, medium: true))
                                .foregroundStyle(Geist.bg)
                                .frame(width: 28, height: 28)
                                .background(Geist.text, in: Circle())
                                .padding(.top, 14)
                            Rectangle()
                                .fill(step.id == steps.count ? Color.clear : Geist.borderHi)
                                .frame(width: 2)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: 28)
                        .accessibilityHidden(true)

                        Button { openStep(step.id, proxy: proxy) } label: {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(step.kind)
                                    .textCase(.uppercase)
                                    .font(Geist.mono(size: 11, relativeTo: .caption))
                                    .tracking(0.66)
                                    .foregroundStyle(Geist.muted)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Geist.faint)
                                    .accessibilityHidden(true)
                            }
                            Text(step.title)
                                .font(.custom("Geist-SemiBold", size: 17, relativeTo: .body))
                                .foregroundStyle(Geist.text)
                                .fixedSize(horizontal: false, vertical: true)
                            if let detail = step.detail {
                                Text(detail)
                                    .font(Geist.body(.callout))
                                    .foregroundStyle(Geist.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Geist.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Geist.border, lineWidth: 1)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 12)
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(step.id == 4
                            ? Text("Opens the destination editor")
                            : Text("Shows the settings for this step"))
                        .accessibilityIdentifier("route_step_\(step.id)")
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        }
    }

    // MARK: Preview and quick actions

    /// Sample capture shaped like this route's processing mode.
    private var previewSampleText: String {
        switch flow.postProcessingMode {
        case .meetingNotes:
            return "### 10:42 · Project sync\n- [ ] Review final designs\n- [ ] Loop in design before Friday\nDecision: ship routing first."
        case .todoList:
            return "- [ ] Book flights for Lisbon"
        case .none:
            return "Walked along the river after lunch. Felt clearer about the plan."
        default:
            return "Remind me to book flights for Lisbon before Friday."
        }
    }

    /// The route's real last capture when the Library has one, otherwise the
    /// rendered sample.
    private var routePreview: RoutePreviewContent? {
        if let lastCapturePreview { return lastCapturePreview }
        return sampleRoutePreview.map { RoutePreviewContent(path: $0.path, markdown: $0.markdown, isLastCapture: false) }
    }

    /// Latest delivered Library entry for the route (matched by route ID, or
    /// by its owned destination), with its Markdown exactly as delivered.
    static func loadLastCapturePreview(routeID: String, destinationID: UUID?) async -> RoutePreviewContent? {
        guard let store = LibraryContentLoader.historyStore else { return nil }
        let records = (try? await store.list()) ?? []
        let candidates = records
            .filter { record in
                guard record.outcome == .delivered else { return false }
                if let voxID = record.voxID { return voxID == routeID }
                return destinationID != nil && record.destinationID == destinationID
            }
            .sorted { ($0.deliveredAt ?? $0.createdAt) > ($1.deliveredAt ?? $1.createdAt) }
        guard !candidates.isEmpty else { return nil }
        let content = await store.allContent()
        for record in candidates {
            guard let entry = content[record.requestID] else { continue }
            let markdown = (entry.renderedMarkdown ?? entry.text ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !markdown.isEmpty else { continue }
            return RoutePreviewContent(
                path: record.relativeNotePath ?? record.destinationNameSnapshot,
                markdown: markdown,
                isLastCapture: true
            )
        }
        return nil
    }

    /// Path and Markdown this route would write, rendered with the same
    /// renderer, entry template and path planner used for delivery.
    private var sampleRoutePreview: (path: String, markdown: String)? {
        guard let destination = ownedDestination else { return nil }
        let request = CaptureRequest(
            source: .app,
            destinationID: destination.id,
            payloads: [.text(previewSampleText)],
            frontmatter: flow.staticFrontmatter,
            voxProfile: flow.captureProfile
        )
        guard let body = try? CaptureMarkdownRenderer().render(request, for: destination) else { return nil }
        let templates = CaptureEntryTemplateRenderer()
        var prefix = destination.entryPrefix
        var suffix = destination.entrySuffix
        if let templateID = destination.entryTemplateID,
           let template = captureEntryTemplates.first(where: { $0.id == templateID }) {
            prefix = template.entryPrefix
            suffix = template.entrySuffix
        }
        var markdown = templates.render(prefix, for: request) + body + templates.render(suffix, for: request)
        if case .beneathHeading(let heading, _, _) = destination.placement {
            let level = String(repeating: "#", count: max(1, min(6, heading.level ?? 2)))
            markdown = "\(level) \(heading.title)\n\n" + markdown
        }
        let path = (try? CapturePathPlanner().relativePath(for: request, destination: destination))
            ?? captureDestinationParts(destination).target
        return (path, markdown.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    @ViewBuilder
    private var routePreviewSection: some View {
        if let preview = routePreview {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            previewTitle(preview.path)
                            Spacer(minLength: 8)
                            previewSource(isLastCapture: preview.isLastCapture)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            previewTitle(preview.path)
                            previewSource(isLastCapture: preview.isLastCapture)
                        }
                    }
                    Text(verbatim: preview.markdown)
                        .font(Geist.mono(size: 12.5, relativeTo: .footnote))
                        .lineSpacing(4)
                        .foregroundStyle(Color(white: 0.91))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(16)
                .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .accessibilityElement(children: .combine)
                .accessibilityLabel(Text("Preview of \(preview.path)"))
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }
        }
    }

    private func previewTitle(_ path: String) -> some View {
        Text(verbatim: "PREVIEW · \(path)")
            .font(Geist.mono(size: 11, relativeTo: .caption))
            .tracking(0.66)
            .foregroundStyle(Color(white: 0.6))
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private func previewSource(isLastCapture: Bool) -> some View {
        (isLastCapture ? Text("from your last capture") : Text("from a sample capture"))
            .font(Geist.caption(.caption))
            .foregroundStyle(Color(white: 0.6))
    }

    private var quickActionsSection: some View {
        let actions = CaptureToolbarPreferences.shared.pinnedActions(forRoute: flow.id)
        return Section {
            NavigationLink {
                RouteQuickActionsView(presetID: flow.id)
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick actions while typing")
                        .textCase(.uppercase)
                        .font(Geist.mono(size: 11, relativeTo: .caption))
                        .tracking(0.66)
                        .foregroundStyle(Geist.muted)
                    HStack(spacing: 6) {
                        if actions.isEmpty {
                            Text("None pinned")
                                .font(Geist.caption())
                                .foregroundStyle(Geist.muted)
                        }
                        ForEach(actions.prefix(4)) { action in
                            Group {
                                if let glyph = action.textIcon {
                                    Text(verbatim: glyph).font(Geist.mono(size: 12, relativeTo: .caption))
                                } else {
                                    Image(systemName: action.systemImage ?? "circle").font(.system(size: 12, weight: .medium))
                                }
                            }
                            .foregroundStyle(Geist.text)
                            .padding(.horizontal, 8)
                            .frame(minWidth: 30, minHeight: 30)
                            .background(Geist.Palette.gray100, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Geist.border, lineWidth: 1))
                        }
                        if actions.count > 4 {
                            Text(verbatim: "+\(actions.count - 4)")
                                .font(Geist.caption())
                                .foregroundStyle(Geist.muted)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .padding(.vertical, 4)
            }
            .accessibilityLabel(Text("Quick actions while typing, \(actions.count) pinned"))
            .accessibilityIdentifier("route_quick_actions")
        }
        .listRowBackground(Geist.card)
    }

    /// Short toggle card from the Route editor board. Both bind the same
    /// settings as Voice Processing › Identify Speakers and Location › Use
    /// Current Location below.
    private var quickTogglesSection: some View {
        Section {
            Toggle("Speaker labels", isOn: $flow.speakerDiarizationEnabled)
                .tint(Geist.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("route_quick_speaker_labels")
            Toggle("Attach location", isOn: $flow.locationPolicy.isEnabled)
                .tint(Geist.accent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("route_quick_attach_location")
        }
        .listRowBackground(Geist.card)
    }

    private var identitySection: some View {
        CapturePresetSettingsIdentitySection(preset: $flow)
    }

    private var watchOutputSection: some View {
        Section {
            Picker("Output", selection: $flow.watchOutputMode) {
                ForEach(CapturePresetWatchOutputMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .onChange(of: flow.watchOutputMode) { _, mode in
                guard mode == .recordingOnly else { return }
                requestRecordingDeliveryNotificationsIfNeeded()
            }

            if flow.watchOutputMode == .recordingOnly {
                Button {
                    openBookmarkPicker(.watchRecordingFolder)
                } label: {
                    folderRow(
                        title: "Recording Folder",
                        value: flow.watchRecordingSettings.folderName
                    )
                }
                .buttonStyle(.plain)

                if !flow.watchRecordingSettings.folderName.isEmpty {
                    Button("Clear Recording Folder", role: .destructive) {
                        flow.watchRecordingSettings.folderBookmark = nil
                        flow.watchRecordingSettings.folderName = ""
                    }
                }

                TextField(
                    "Filename Template",
                    text: $flow.watchRecordingSettings.filenameTemplate
                )
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)

                Text("Tokens: {timestamp}, {date}, {time}, {YR} (2-digit year), {id8}, {id}, {preset}, {original}")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)

                if flow.watchRecordingSettings.folderBookmark == nil {
                    Label("Choose a Files folder before using this route from Apple Watch.", systemImage: "exclamationmark.triangle")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.error)
                }

                if recordingDeliveryNotificationsDenied {
                    Label("Notifications are off. Vox.md cannot alert you if an unattended Files delivery needs attention.", systemImage: "bell.slash")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.error)
                    Button("Open Notification Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        openURL(url)
                    }
                }
            }
        } header: {
            PresetListSectionHeader(title: "Apple Watch Output")
        } footer: {
            if flow.watchOutputMode == .recordingOnly {
                Text("Watch recordings are copied as M4A files to this user-visible Files folder. Transcription, AI processing, and transcription usage are skipped. After one-time folder setup, Vox.md normally saves in the background. iOS may delay delivery, and force-quitting Vox.md prevents background delivery until you reopen it. Recordings remain safely queued for retry.")
            } else {
                Text("Watch recordings use this route's normal on-device transcription and Capture destination workflow.")
            }
        }
    }

    /// Per-route model override. Only Automatic and installed local models
    /// are offered; an override whose model is later removed falls back to
    /// the app-wide model at transcription time.
    private var transcriptionModelOverride: Binding<String> {
        Binding(
            get: { flow.transcriptionModelID ?? "" },
            set: { flow.transcriptionModelID = $0.isEmpty ? nil : $0 }
        )
    }

    private var appDefaultModelName: String {
        modelManager.isAutomaticSelection
            ? String(localized: "Automatic")
            : (modelManager.selectedModel?.name ?? String(localized: "Automatic"))
    }

    private var voiceProcessingSection: some View {
        Section {
            Picker("Transcription Model", selection: transcriptionModelOverride) {
                Text("App Default (\(appDefaultModelName))").tag("")
                Text("Automatic").tag(TranscriptionBackendID.automatic)
                ForEach(modelManager.downloadedModels, id: \.id) { model in
                    Text(model.name).tag(model.id)
                }
                if let id = flow.transcriptionModelID, id != TranscriptionBackendID.automatic,
                   !modelManager.downloadedModels.contains(where: { $0.id == id }) {
                    Text("Not Installed — Uses App Default").tag(id)
                }
            }
            .accessibilityIdentifier("route_transcription_model")

            Toggle("Identify Speakers", isOn: $flow.speakerDiarizationEnabled)
                .tint(Geist.accent)

            if flow.speakerDiarizationEnabled {
                Label("Speaker labels are added after transcription.", systemImage: "person.2.wave.2")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
            }
        } header: {
            PresetListSectionHeader(title: "Voice Processing")
        } footer: {
            Text("The model overrides Settings › Models for this route’s recordings. Identify Speakers detects and labels multiple voices entirely on device. The speaker model downloads the first time this route uses it. Speaker identification is best-effort; if it cannot run, Vox.md keeps the normal transcript.")
        }
    }

    private var postProcessingSection: some View {
        Section {
            HStack(spacing: 12) {
                Toggle("Use Apple Intelligence", isOn: $flow.captureProcessingEnabled)
                    .accessibilityIdentifier("capture_processing_enabled")
                    .tint(Geist.accent)

                Button {
                    isCaptureProcessingInfoPresented = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Geist.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("About Apple Intelligence Processing")
            }
            .id("step-process")

            ImageAltTextSettings(
                generateImageAltText: $flow.generateImageAltText,
                processingEnabled: flow.captureProcessingEnabled
            )

            Picker("Mode", selection: $flow.postProcessingMode) {
                ForEach(CapturePresetProcessingMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            if flow.captureProcessingEnabled {
                Picker("Apply To", selection: $flow.captureProcessingScope) {
                    ForEach(CapturePresetProcessingScope.allCases) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(flow.postProcessingMode.helpTitle, systemImage: "info.circle")
                    .font(Geist.label(.caption))
                Text(flow.postProcessingMode.helpText)
                    .font(Geist.caption())
                if flow.postProcessingMode != .none {
                    if flow.captureProcessingEnabled {
                        switch flow.captureProcessingScope {
                        case .both:
                            Label("Voice transcriptions and typed Capture text are processed on device using this mode.", systemImage: "waveform")
                                .font(Geist.caption())
                        case .voiceOnly:
                            Label("Only voice transcriptions are processed; typed Capture text stays exactly as captured.", systemImage: "waveform")
                                .font(Geist.caption())
                        case .textOnly:
                            Label("Only typed Capture text is processed; voice transcriptions stay exactly as captured.", systemImage: "waveform")
                                .font(Geist.caption())
                        }
                    } else {
                        Label("Apple Intelligence is off — turn it on above to apply this mode to voice transcriptions and Capture text.", systemImage: "waveform")
                            .font(Geist.caption())
                    }
                }
            }
            .foregroundStyle(Geist.muted)

            if flow.postProcessingMode == .custom {
                TextEditor(text: $flow.customPostProcessingInstruction)
                    .frame(minHeight: 90)
                Text("Describe exactly how Vox.md should shape captured text. Leave blank to preserve the original when AI enrichment is unavailable.")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
            }

            TextField("Empty Capture Prompt", text: $flow.capturePrompt, axis: .vertical)
                .lineLimit(2...4)
                .id("step-capture")
            Text("Example: What do you want to remember?")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
        } header: {
            PresetListSectionHeader(title: "Capture Processing")
        } footer: {
            Text("\"Use Apple Intelligence\" applies the selected mode to the modalities chosen under \"Apply To\" — voice transcriptions, typed Capture text, or both. Turn it off to keep everything exactly as captured. Processing runs on device and falls back to deterministic or original text.")
        }
    }

    private var ownedDestinationSection: some View {
        Section {
            if let destination = ownedDestination {
                LabeledContent("Vault / Folder", value: destination.rootName)
                Text(captureDestinationSummary(destination))
                    .font(Geist.mono(.caption))
                    .foregroundStyle(Geist.muted)
                Button {
                    isEditingDestination = true
                } label: {
                    Label("Edit Destination", systemImage: "square.and.pencil")
                }
            } else {
                ContentUnavailableView(
                    "Destination Not Configured",
                    systemImage: "folder.badge.plus",
                    description: Text("Choose a vault or folder and define where this route writes Markdown.")
                )
                Button {
                    isEditingDestination = true
                } label: {
                    Label("Set Up Destination", systemImage: "folder.badge.plus")
                }
            }

            if let captureDestinationLoadError {
                Text(captureDestinationLoadError)
                    .font(Geist.caption())
                    .foregroundStyle(Geist.error)
            }
        } header: {
            PresetListSectionHeader(title: "Destination")
        } footer: {
            Text("This destination belongs to this route. It includes the note target, placement, entry formatting, attachments folder, and retry behavior.")
        }
    }

    private var frontmatterSection: some View {
        Section(header: PresetListSectionHeader(title: "Metadata")) {
            Picker("Scope", selection: $flow.metadataScope) {
                ForEach(CapturePresetMetadataScope.allCases) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .id("step-shape")
            Text(flow.metadataScope == .document
                 ? "Note Frontmatter is best for one note per capture. On rolling notes, later captures may update the note-wide values."
                 : "Inline Entry Fields writes queryable `key:: value` lines with each entry, keeping rolling-note metadata separate.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
            Text("One `key: value` per line. Example: `tags: [journal, idea]`.")
                .font(Geist.caption())
                .foregroundStyle(Geist.muted)
            TextEditor(text: $frontmatterText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .onChange(of: frontmatterText) { _, value in
                    flow.staticFrontmatter = Self.parseFrontmatter(value)
                }
        }
    }

    private var locationMetadataSection: some View {
        Section {
            Toggle("Use Current Location", isOn: $flow.locationPolicy.isEnabled)
                .tint(Geist.accent)
                .accessibilityIdentifier("preset_location_enabled")

            if flow.locationPolicy.isEnabled {
                Text("Entry formatting can use {location} without writing additional metadata.")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)

                Picker("Precision", selection: $flow.locationPolicy.precision) {
                    Text("Exact").tag(CaptureLocationPrecision.exact)
                    Text("City").tag(CaptureLocationPrecision.city)
                }
                .accessibilityIdentifier("preset_location_precision")

                Picker("When Location Is Unavailable", selection: $flow.locationPolicy.unavailableBehavior) {
                    Text("Ask").tag(CaptureLocationUnavailableBehavior.ask)
                    Text("Send Without Location").tag(CaptureLocationUnavailableBehavior.sendWithoutLocation)
                    Text("Cancel Capture").tag(CaptureLocationUnavailableBehavior.cancel)
                }
                .accessibilityIdentifier("preset_location_unavailable_behavior")

                Toggle("Write Location Metadata", isOn: $flow.locationPolicy.metadataOutputEnabled)
                    .tint(Geist.accent)
                    .accessibilityIdentifier("preset_location_metadata_output_enabled")

                if flow.locationPolicy.metadataOutputEnabled {
                    Picker("Configuration", selection: $flow.locationPolicy.outputMode) {
                        Text("Structured Fields").tag(CaptureLocationOutputMode.structured)
                        Text("Advanced YAML Template")
                            .tag(CaptureLocationOutputMode.advancedTemplate)
                            .disabled(flow.metadataScope == .entry)
                    }
                    .accessibilityIdentifier("preset_location_output_mode")

                    if flow.locationPolicy.outputMode == .advancedTemplate,
                       flow.metadataScope == .entry {
                        Label(
                            String(localized: "Advanced YAML Template") + " · " + String(localized: "Use Note Frontmatter Scope"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(Geist.caption())
                        .foregroundStyle(Geist.error)
                        .accessibilityIdentifier("preset_location_scope_error")
                        Button("Use Note Frontmatter Scope") {
                            flow.metadataScope = .document
                        }
                    }

                    if flow.metadataScope == .document {
                        TextField("Name", text: $flow.locationPolicy.collectionKey)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                            .font(.system(.body, design: .monospaced))
                            .accessibilityIdentifier("preset_location_collection_key")
                        Text("Each Capture is appended to this collection by Capture ID, so a note can retain multiple locations without replacing earlier ones.")
                            .font(Geist.caption())
                            .foregroundStyle(Geist.muted)
                    } else {
                        Text("Inline Entry Fields writes the selected `key:: value` fields beside each captured entry. No frontmatter collection is written.")
                            .font(Geist.caption())
                            .foregroundStyle(Geist.muted)
                    }

                    if flow.locationPolicy.outputMode == .structured {
                        ForEach(CaptureLocationField.allCases, id: \.self) { field in
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle(field.configurationDisplayName, isOn: locationFieldSelection(field))
                                    .tint(Geist.accent)
                                if flow.locationPolicy.structuredFields.contains(where: { $0.field == field }) {
                                    TextField("Output", text: locationOutputKey(field))
                                        .textInputAutocapitalization(.never)
                                        .disableAutocorrection(true)
                                        .font(.system(.body, design: .monospaced))
                                        .accessibilityLabel(
                                            String(localized: "Output") + " · " + field.configurationDisplayName
                                        )
                                        .accessibilityIdentifier("preset_location_key_\(field.rawValue)")
                                }
                            }
                        }
                    } else {
                        TextEditor(text: $flow.locationPolicy.advancedTemplate)
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 160)
                            .accessibilityLabel("Advanced YAML Template")
                            .accessibilityIdentifier("preset_location_advanced_template")
                        Text("Nested mappings and list items are supported. Use placeholders such as `{{coordinates}}`, `{{city}}`, `{{timestamp}}`, and `{{id}}`.")
                            .font(Geist.caption())
                            .foregroundStyle(Geist.muted)
                    }

                    locationPolicyPreview

                    Text("Place, city, region, and country use Apple's system reverse geocoder only when selected and may make a network request.")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                } else {
                    Text("No frontmatter collection or inline location fields will be written. The {location} template token still works.")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                }

                Text("Provider links disclose the privacy-adjusted coordinates to Apple, Google, or OpenStreetMap only when you open a link.")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
            }

            Button("Reset Location Unavailable Choice") {
                flow.locationPolicy.unavailableBehavior = .ask
            }
            .disabled(flow.locationPolicy.unavailableBehavior == .ask)
            .accessibilityIdentifier("preset_location_reset_unavailable")

            Button("Reset Location Configuration", role: .destructive) {
                flow.locationPolicy = CapturePresetLocationPolicy()
            }
            .accessibilityIdentifier("preset_location_reset_configuration")
        } header: {
            PresetListSectionHeader(title: "Location")
        } footer: {
            Text("Location is requested once at Capture send or recording stop. Exact keeps the origin fix; City rounds coordinates and omits a point-of-interest label. Vox.md does not track location in the background.")
        }
    }

    private func locationFieldSelection(_ field: CaptureLocationField) -> Binding<Bool> {
        Binding(
            get: { flow.locationPolicy.structuredFields.contains(where: { $0.field == field }) },
            set: { isSelected in
                flow.locationPolicy.structuredFields.removeAll { $0.field == field }
                if isSelected {
                    flow.locationPolicy.structuredFields.append(CaptureLocationStructuredField(field: field))
                }
            }
        )
    }

    private func locationOutputKey(_ field: CaptureLocationField) -> Binding<String> {
        Binding(
            get: {
                flow.locationPolicy.structuredFields.first(where: { $0.field == field })?.outputKey
                    ?? field.rawValue
            },
            set: { value in
                guard let index = flow.locationPolicy.structuredFields.firstIndex(where: { $0.field == field }) else {
                    return
                }
                flow.locationPolicy.structuredFields[index].outputKey = value
            }
        )
    }

    @ViewBuilder
    private var locationPolicyPreview: some View {
        switch CaptureLocationConfigurationPreview.result(
            profile: flow.captureProfile,
            source: .app
        ) {
        case .success(let preview):
            VStack(alignment: .leading, spacing: 8) {
                Label("Delivery Preview", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Geist.success)
                ScrollView(.horizontal) {
                    Text(preview)
                        .font(Geist.mono(.caption))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("preset_location_preview")
        case .failure(let error):
            Label(error.message, systemImage: "exclamationmark.triangle.fill")
                .font(Geist.caption())
                .foregroundStyle(Geist.error)
                .accessibilityIdentifier("preset_location_validation_error")
        }
    }

    private var fileExportSection: some View {
        Section {
            Toggle("Save Notes to Files", isOn: $flow.exportSettings.exportEnabled)
                .tint(Geist.accent)
                .onChange(of: flow.exportSettings.exportEnabled) { _, _ in markPerFlow() }

            if flow.exportSettings.exportEnabled {
                Button {
                    openBookmarkPicker(.exportFolder)
                } label: {
                    folderRow(title: "Export Directory", value: flow.exportSettings.folderName)
                }
                .buttonStyle(.plain)

                if !flow.exportSettings.folderName.isEmpty {
                    Button("Clear Export Directory", role: .destructive) {
                        markPerFlow()
                        flow.exportSettings.folderBookmark = nil
                        flow.exportSettings.folderName = ""
                    }
                }

                Picker("Format", selection: $flow.exportSettings.format) {
                    Text("TXT").tag(ExportFileFormat.txt)
                    Text("MD").tag(ExportFileFormat.md)
                    Text("JSON").tag(ExportFileFormat.json)
                    Text("YAML").tag(ExportFileFormat.yaml)
                }
                .onChange(of: flow.exportSettings.format) { _, _ in markPerFlow() }

                if flow.exportSettings.format == .md {
                    Toggle("Obsidian Bases", isOn: $flow.exportSettings.mdObsidianEnabled)
                        .tint(Geist.accent)
                        .onChange(of: flow.exportSettings.mdObsidianEnabled) { _, _ in markPerFlow() }
                }

                if flow.exportSettings.format == .yaml {
                    Toggle("Use .md Extension", isOn: $flow.exportSettings.yamlUsesMarkdownExtension)
                        .tint(Geist.accent)
                        .onChange(of: flow.exportSettings.yamlUsesMarkdownExtension) { _, _ in markPerFlow() }
                    yamlPropertiesPicker
                }

                Picker("Mode", selection: $flow.exportSettings.mode) {
                    Text("New File").tag(ExportFileMode.newFile)
                    Text("Append").tag(ExportFileMode.append)
                }
                .onChange(of: flow.exportSettings.mode) { _, _ in markPerFlow() }

                if flow.exportSettings.mode == .newFile {
                    TextField("Filename Template", text: $flow.exportSettings.newFileNameTemplate)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: flow.exportSettings.newFileNameTemplate) { _, _ in markPerFlow() }
                    Text("Tokens: {timestamp}, {date}, {time}, {YR} (2-digit year), {id8}, {id}, {model}, {language}")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                } else {
                    TextField("Append Filename", text: $flow.exportSettings.appendFileName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .onChange(of: flow.exportSettings.appendFileName) { _, _ in markPerFlow() }
                }

                Toggle("Use Markdown Template", isOn: $flow.exportSettings.markdownTemplateEnabled)
                    .tint(Geist.accent)
                    .onChange(of: flow.exportSettings.markdownTemplateEnabled) { _, _ in markPerFlow() }
                if flow.exportSettings.markdownTemplateEnabled {
                    Button {
                        openBookmarkPicker(.markdownTemplate)
                    } label: {
                        folderRow(title: "Markdown Template", value: flow.exportSettings.markdownTemplateName, systemImage: "doc.text")
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            PresetListSectionHeader(title: "Legacy Voice File Export")
        } footer: {
            Text("These compatibility settings apply to direct voice runs only when no unified Capture route is selected.")
        }
    }

    private var urlDeliverySection: some View {
        URLDeliverySettingsSection(settings: $flow.exportSettings.urlDelivery)
    }

    private var audioExportSection: some View {
        Section {
            Picker("Save Audio", selection: $flow.audioSaveMode) {
                ForEach(CapturePresetAudioSaveMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .onChange(of: flow.audioSaveMode) { _, newMode in
                markPerFlow()
                if newMode == .alongsideTranscript {
                    flow.exportSettings.audioFolderBookmark = nil
                    flow.exportSettings.audioFolderName = ""
                }
            }

            if flow.audioSaveMode == .attachmentsFolder {
                if flow.captureDestinationID != nil {
                    TextField("Attachments Folder", text: $flow.attachmentsFolderName)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                    Text("Relative to the unified Markdown destination. Leave blank to use that destination’s default attachment folder.")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                } else {
                    Button {
                        openBookmarkPicker(.audioFolder)
                    } label: {
                        folderRow(title: "Audio Export Directory", value: flow.exportSettings.audioFolderName)
                    }
                    .buttonStyle(.plain)

                    if !flow.exportSettings.audioFolderName.isEmpty {
                        Button("Clear Audio Directory", role: .destructive) {
                            flow.exportSettings.audioFolderBookmark = nil
                            flow.exportSettings.audioFolderName = ""
                        }
                    }

                    if flow.exportSettings.audioFolderName.isEmpty {
                        TextField("Attachments Folder", text: $flow.attachmentsFolderName)
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                }
            }

            if flow.audioSaveMode != .off {
                CapturePresetAudioFilenameSettings(preset: $flow)

                Toggle("Embed Audio in Markdown", isOn: $flow.exportSettings.embedAudioInMarkdown)
                    .tint(Geist.accent)
                    .disabled(!markdownAudioEmbedAvailable)
                    .onChange(of: flow.exportSettings.embedAudioInMarkdown) { _, _ in markPerFlow() }

                if flow.exportSettings.embedAudioInMarkdown && markdownAudioEmbedAvailable {
                    Picker("Embed Position", selection: $flow.exportSettings.audioEmbedPlacement) {
                        ForEach(CapturePresetAudioEmbedPlacement.allCases) { placement in
                            Text(placement.displayName).tag(placement)
                        }
                    }
                    .onChange(of: flow.exportSettings.audioEmbedPlacement) { _, _ in markPerFlow() }
                }

                Text(markdownAudioEmbedHelpText)
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
            }
        } header: {
            PresetListSectionHeader(title: "Voice Audio")
        } footer: {
            Text(audioExportFooterText)
        }
    }

    private var audioExportFooterText: String {
        switch flow.audioSaveMode {
        case .off:
            return String(localized: "Turn this on to save a copy of the recorded audio when a note is exported.")
        case .alongsideTranscript:
            return flow.captureDestinationID == nil
                ? String(localized: "Saved audio uses the same legacy export directory and base filename as the note.")
                : String(localized: "Saved audio is placed alongside the unified Markdown note.")
        case .attachmentsFolder:
            return flow.captureDestinationID == nil
                ? String(localized: "When no audio export directory is set, saved audio uses this route’s legacy note export folder.")
                : String(localized: "Saved audio uses a subfolder inside the unified Markdown destination, and that route survives deferred retries.")
        }
    }

    private var markdownAudioEmbedAvailable: Bool {
        if flow.captureDestinationID != nil { return true }
        guard flow.exportSettings.exportEnabled else { return false }
        if flow.exportSettings.markdownTemplateEnabled { return true }
        if flow.exportSettings.format == .md { return true }
        return flow.exportSettings.format == .yaml && flow.exportSettings.yamlUsesMarkdownExtension
    }

    private var markdownAudioEmbedHelpText: String {
        if flow.captureDestinationID != nil {
            return String(localized: "Adds an Obsidian-style audio link to the unified Markdown note at the selected position.")
        }
        guard markdownAudioEmbedAvailable else {
            return String(localized: "Audio embeds require a Markdown note export. Switch this route to MD, a Markdown template, or YAML with the .md extension.")
        }
        return String(localized: "Adds an Obsidian-style `![[recording.m4a]]` link to the note so you can replay the recording while reviewing the transcript.")
    }

    private var yamlPropertiesPicker: some View {
        ForEach(ExportYAMLProperty.allCases, id: \.rawValue) { property in
            Toggle(
                property.displayName,
                isOn: Binding(
                    get: { flow.exportSettings.yamlProperties.contains(property) },
                    set: { enabled in toggleYAMLProperty(property, enabled: enabled) }
                )
            )
            .tint(Geist.accent)
            .disabled(flow.exportSettings.yamlProperties.count == 1 && flow.exportSettings.yamlProperties.contains(property))
        }
    }

    private var ownedDestination: CaptureDestination? {
        guard let id = flow.captureDestinationID else { return nil }
        return captureDestinations.first(where: { $0.id == id })
    }

    private func saveOwnedDestination(_ submittedDestination: CaptureDestination) async throws {
        guard let url = AppConstants.captureLibraryURL else {
            throw CapturePresetDestinationError.storageUnavailable
        }
        let destination = CapturePresetStore.migratingLegacyMarkdownTemplate(
            into: submittedDestination,
            from: flow.exportSettings
        )
        let store = CaptureLibraryStore(fileURL: url)
        let library = try await store.update { library in
            if let index = library.destinations.firstIndex(where: { $0.id == destination.id }) {
                library.destinations[index] = destination
            } else {
                library.destinations.append(destination)
            }
            if library.defaultDestinationID == nil {
                library.defaultDestinationID = destination.id
            }
        }
        flow.captureDestinationID = destination.id
        flow.captureEntryTemplateID = nil
        flow.capturePlacementOverride = nil
        if destination.markdownTemplatePath != nil {
            flow.exportSettings.markdownTemplateEnabled = false
            flow.exportSettings.markdownTemplateBookmark = nil
            flow.exportSettings.markdownTemplateName = ""
        }
        captureDestinations = library.destinations
        captureEntryTemplates = library.entryTemplates
        captureDestinationLoadError = nil
    }

    private func loadCaptureDestinations() async {
        guard let url = AppConstants.captureLibraryURL else {
            captureDestinationLoadError = String(localized: "Shared capture storage is unavailable.")
            return
        }
        do {
            let store = CaptureLibraryStore(fileURL: url)
            let library = try await CapturePresetRouteLibrary.load(from: store)
            captureDestinations = library.destinations
            captureEntryTemplates = library.entryTemplates
            if let refreshed = CapturePresetStore.flow(id: flow.id) {
                // Route migration may have assigned ownership while this editor
                // was open. Merge only those migration-owned fields so a task
                // restart cannot overwrite in-progress identity or policy edits.
                flow.captureDestinationID = refreshed.captureDestinationID
                flow.captureEntryTemplateID = refreshed.captureEntryTemplateID
                flow.capturePlacementOverride = refreshed.capturePlacementOverride
                if let routeID = refreshed.captureDestinationID,
                   library.destinations.first(where: { $0.id == routeID })?.markdownTemplatePath != nil {
                    flow.exportSettings.markdownTemplateEnabled = false
                    flow.exportSettings.markdownTemplateBookmark = nil
                    flow.exportSettings.markdownTemplateName = ""
                }
            }
            captureDestinationLoadError = nil
        } catch {
            captureDestinationLoadError = error.localizedDescription
        }
    }

    private func captureDestinationSummary(_ destination: CaptureDestination) -> String {
        let parts = captureDestinationParts(destination)
        return "\(parts.target) · \(parts.placement)"
    }

    private func folderRow(title: LocalizedStringKey, value: String, systemImage: String = "folder") -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.isEmpty ? String(localized: "Not set") : value)
                .foregroundStyle(Geist.muted)
                .lineLimit(1)
            Image(systemName: systemImage)
                .foregroundStyle(Geist.muted)
        }
        .contentShape(Rectangle())
    }

    private func openBookmarkPicker(_ kind: BookmarkKind) {
        switch kind {
        case .watchRecordingFolder:
            break
        default:
            markPerFlow()
        }
        bookmarkPickerKind = kind
        showBookmarkPicker = true
    }

    private func markPerFlow() {
        flow.exportSettings.usesCustomExportSettings = true
    }

    private func toggleYAMLProperty(_ property: ExportYAMLProperty, enabled: Bool) {
        markPerFlow()
        if enabled {
            flow.exportSettings.yamlProperties.insert(property)
        } else {
            guard flow.exportSettings.yamlProperties.count > 1 else { return }
            flow.exportSettings.yamlProperties.remove(property)
        }
    }

    private func saveBookmark(url: URL, kind: BookmarkKind) {
        let didScope = url.startAccessingSecurityScopedResource()
        defer { if didScope { url.stopAccessingSecurityScopedResource() } }
        guard let bookmark = try? url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else { return }
        switch kind {
        case .watchRecordingFolder:
            break
        default:
            markPerFlow()
        }
        switch kind {
        case .exportFolder:
            flow.exportSettings.folderBookmark = bookmark
            flow.exportSettings.folderName = url.lastPathComponent
        case .audioFolder:
            flow.exportSettings.audioFolderBookmark = bookmark
            flow.exportSettings.audioFolderName = url.lastPathComponent
        case .markdownTemplate:
            flow.exportSettings.markdownTemplateBookmark = bookmark
            flow.exportSettings.markdownTemplateName = url.lastPathComponent
        case .watchRecordingFolder:
            flow.watchRecordingSettings.folderBookmark = bookmark
            flow.watchRecordingSettings.folderName = url.lastPathComponent
            requestRecordingDeliveryNotificationsIfNeeded()
        }
    }

    private func requestRecordingDeliveryNotificationsIfNeeded() {
        Task { @MainActor in
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            switch settings.authorizationStatus {
            case .notDetermined:
                let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) == true
                recordingDeliveryNotificationsDenied = !granted
            case .denied:
                recordingDeliveryNotificationsDenied = true
            case .authorized, .provisional, .ephemeral:
                recordingDeliveryNotificationsDenied = false
            @unknown default:
                recordingDeliveryNotificationsDenied = true
            }
        }
    }

    private func refreshRecordingDeliveryNotificationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        recordingDeliveryNotificationsDenied = settings.authorizationStatus == .denied
    }

    private static func renderFrontmatter(_ frontmatter: [String: String]) -> String {
        frontmatter
            .sorted(by: { $0.key < $1.key })
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private static func parseFrontmatter(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, !value.isEmpty else { continue }
            result[key] = value
        }
        return result
    }
}

private struct CaptureTextProcessingInfoView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(Geist.Palette.gray1000)
                        .accessibilityHidden(true)

                    Text("When this setting is on, Vox.md uses on-device Apple Intelligence to edit captured text using the selected mode and the “Apply To” scope you choose — voice transcriptions, typed Capture text, or both — before updating your Markdown file.")

                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(
                            icon: "slider.horizontal.3",
                            title: "Applies where you choose",
                            detail: "Process voice transcriptions, typed Capture text, or both via “Apply To.”"
                        )
                        infoRow(
                            icon: "checkmark.circle",
                            title: "Follows the selected mode",
                            detail: "Clean prose, create a todo checklist, format meeting notes, or follow your custom instruction."
                        )
                        infoRow(
                            icon: "lock.shield",
                            title: "Runs on device",
                            detail: "Your captured text is processed locally and is not sent to a cloud AI service."
                        )
                        infoRow(
                            icon: "doc.text",
                            title: "Keeps capture reliable",
                            detail: "If Apple Intelligence is unavailable, Vox.md uses a local fallback when possible or keeps the original text."
                        )
                    }

                    Text("Keep Original and Apply To control text only. Image descriptions are optional.")
                        .font(Geist.caption())
                        .foregroundStyle(Geist.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
            .navigationTitle("Apple Intelligence Processing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .font(Geist.body())
        .tint(Geist.accent)
    }

    private func infoRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundStyle(Geist.muted)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(Geist.muted)
            }
        }
    }
}

private enum CapturePresetDestinationError: Error, LocalizedError {
    case storageUnavailable

    var errorDescription: String? {
        "Shared capture storage is unavailable."
    }
}

struct FlowIconPickerView: View {
    @Binding var preset: CapturePreset
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private let columns = [GridItem(.adaptive(minimum: 78), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                selectedIconPreview

                if filteredCategories.isEmpty {
                    Text("No matching icons")
                        .font(.callout)
                        .foregroundStyle(Geist.muted)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    ForEach(filteredCategories) { category in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(category.title)
                                .font(Geist.label(.caption))
                                .foregroundStyle(Geist.muted)
                                .textCase(nil)

                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(category.options) { option in
                                    iconButton(option)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Icon")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search icons")
        .tint(Geist.accent)
    }

    private var filteredCategories: [FlowIconCategory] {
        Self.filteredCategories(matching: searchText)
    }

    private var selectedIconPreview: some View {
        HStack(spacing: 12) {
            CapturePresetIconView(symbolName: preset.symbolName, emoji: preset.emoji)
                .font(.title2)
                .frame(minWidth: 44, minHeight: 44)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Geist.well))
            VStack(alignment: .leading, spacing: 3) {
                Text("Selected Icon")
                    .font(Geist.caption())
                    .foregroundStyle(Geist.muted)
                Text(preset.visibleName ?? String(localized: "Icon-only route"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(preset.visibleName == nil ? Geist.muted : Geist.text)
            }
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous).fill(Geist.card))
        .overlay(
            RoundedRectangle(cornerRadius: Geist.Radius.large, style: .continuous)
                .stroke(Geist.border, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(preset.accessibilityName)
        .accessibilityValue(Text("Selected Icon"))
        .accessibilityIdentifier("capture_preset_symbol_preview")
    }

    private func iconButton(_ option: FlowIconOption) -> some View {
        let selected = preset.emoji == nil && option.symbolName == Self.iconName(for: preset.symbolName)
        return Button {
            preset = CapturePresetEmojiEditorInput.selectingSymbol(option.symbolName, for: preset)
            dismiss()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: option.symbolName)
                    .font(.title2)
                Text(option.title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            .foregroundColor(selected ? Geist.accentText : Geist.text)
            .frame(maxWidth: .infinity, minHeight: 78)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous)
                    .fill(selected ? Geist.accentSoft : Geist.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Geist.Radius.medium, style: .continuous)
                    .stroke(selected ? Geist.accent : Geist.border, lineWidth: selected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(option.symbolName)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("capture_preset_symbol_\(option.symbolName)")
    }

    static func iconName(for symbolName: String) -> String {
        let trimmed = symbolName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "waveform" : trimmed
    }

    static func title(for symbolName: String) -> String {
        let iconName = iconName(for: symbolName)
        let title = allOptions.first(where: { $0.symbolName == iconName })?.title ?? iconName
        return title == "Waveform"
            ? String(localized: "Waveform", bundle: .main)
            : title
    }

    private static func filteredCategories(matching query: String) -> [FlowIconCategory] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return iconCategories }

        return iconCategories.compactMap { category in
            let matches = category.options.filter { $0.matches(trimmed) }
            guard !matches.isEmpty else { return nil }
            return FlowIconCategory(title: category.title, options: matches)
        }
    }

    private static let allOptions = iconCategories.flatMap(\.options)

    private static let iconCategories: [FlowIconCategory] = [
        FlowIconCategory(
            title: "Writing",
            options: [
                FlowIconOption("text.alignleft", "Text"),
                FlowIconOption("note.text", "Note"),
                FlowIconOption("doc.text", "Document"),
                FlowIconOption("doc.text.magnifyingglass", "Research"),
                FlowIconOption("list.bullet", "List"),
                FlowIconOption("quote.bubble", "Quote"),
                FlowIconOption("books.vertical", "Books"),
                FlowIconOption("bookmark", "Bookmark"),
                FlowIconOption("newspaper", "Article"),
                FlowIconOption("pencil", "Draft"),
            ]
        ),
        FlowIconCategory(
            title: "Voice",
            options: [
                FlowIconOption("mic", "Mic"),
                FlowIconOption("waveform", "Waveform"),
                FlowIconOption("wave.3.right", "Audio"),
                FlowIconOption("record.circle", "Record"),
                FlowIconOption("headphones", "Listen"),
                FlowIconOption("speaker.wave.2", "Speaker"),
                FlowIconOption("message", "Message"),
                FlowIconOption("bubble.left.and.text.bubble.right", "Chat"),
                FlowIconOption("phone", "Call"),
                FlowIconOption("video", "Video"),
            ]
        ),
        FlowIconCategory(
            title: "Tasks",
            options: [
                FlowIconOption("checkmark.circle", "Done"),
                FlowIconOption("checklist", "Checklist"),
                FlowIconOption("calendar", "Calendar"),
                FlowIconOption("bell", "Reminder"),
                FlowIconOption("flag", "Flag"),
                FlowIconOption("target", "Goal"),
                FlowIconOption("tray.and.arrow.down", "Inbox"),
                FlowIconOption("paperplane", "Send"),
                FlowIconOption("wand.and.stars", "Magic"),
                FlowIconOption("timer", "Timer"),
            ]
        ),
        FlowIconCategory(
            title: "Personal",
            options: [
                FlowIconOption("person", "Person"),
                FlowIconOption("person.crop.circle", "Profile"),
                FlowIconOption("brain.head.profile", "Thought"),
                FlowIconOption("heart", "Heart"),
                FlowIconOption("moon.stars", "Dream"),
                FlowIconOption("lightbulb", "Idea"),
                FlowIconOption("sparkles", "Sparkles"),
                FlowIconOption("house", "Home"),
                FlowIconOption("leaf", "Nature"),
                FlowIconOption("figure.walk", "Walk"),
            ]
        ),
        FlowIconCategory(
            title: "Work",
            options: [
                FlowIconOption("briefcase", "Work"),
                FlowIconOption("person.2", "People"),
                FlowIconOption("person.2.wave.2", "Meeting"),
                FlowIconOption("building.2", "Company"),
                FlowIconOption("chart.bar", "Stats"),
                FlowIconOption("rectangle.on.rectangle.angled", "Slides"),
                FlowIconOption("folder", "Folder"),
                FlowIconOption("archivebox", "Archive"),
                FlowIconOption("hammer", "Build"),
                FlowIconOption("gearshape", "Settings"),
            ]
        ),
    ]
}

private extension CapturePresetProcessingMode {
    var helpTitle: String {
        switch self {
        case .none:
            return String(localized: "Preserves captured text")
        case .clean:
            return String(localized: "Cleans prose without changing intent")
        case .todoList:
            return String(localized: "Creates a Markdown checklist")
        case .meetingNotes:
            return String(localized: "Formats notes and action items")
        case .custom:
            return String(localized: "Uses your custom instruction")
        }
    }

    var helpText: String {
        switch self {
        case .none:
            return String(localized: "Keeps typed Markdown, OCR, and voice text exactly as captured. Static frontmatter and route settings still apply.")
        case .clean:
            return String(localized: "Fixes casing and punctuation while preserving meaning and Markdown structure. Without on-device enrichment, the original text is retained.")
        case .todoList:
            return String(localized: "Turns captured tasks into `- [ ]` Markdown items without inventing new work. A deterministic local fallback is always available.")
        case .meetingNotes:
            return String(localized: "Builds Markdown meeting notes with useful sections and grounded action items from typed text, OCR, or voice.")
        case .custom:
            return String(localized: "When on-device AI is available, Vox.md follows your instruction for captured text. Use it for standups, journal prompts, summaries, or call follow-ups.")
        }
    }
}

private struct FlowIconCategory: Identifiable {
    let title: String
    let options: [FlowIconOption]

    var id: String { title }
}

private struct FlowIconOption: Identifiable {
    let symbolName: String
    let title: String
    let keywords: [String]

    var id: String { symbolName }

    init(_ symbolName: String, _ title: String, keywords: [String] = []) {
        self.symbolName = symbolName
        self.title = title
        self.keywords = keywords
    }

    func matches(_ query: String) -> Bool {
        let haystack = ([symbolName, title] + keywords).joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(query)
    }
}

/// What the route editor's preview card shows.
struct RoutePreviewContent: Equatable {
    var path: String
    var markdown: String
    /// True when taken from the route's latest delivered capture.
    var isLastCapture: Bool
}
