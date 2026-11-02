import AppIntents
import Foundation
import VoxboardCaptureCore

/// Kept separate from the app's composer/automation intents. The extension reads
/// only the existing App Group identity records; it never migrates or seeds them.
struct CapturePresetWidgetEntity: AppEntity, Identifiable, Hashable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Route"
    static let defaultQuery = CapturePresetWidgetEntityQuery()

    let id: String
    let identity: CapturePresetWidgetIdentity?

    var displayRepresentation: DisplayRepresentation {
        let name = identity?.name ?? String(localized: "Unavailable route")
        let symbol = identity?.symbolName.trimmingCharacters(in: .whitespacesAndNewlines) ?? "exclamationmark.triangle"
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: identity?.isEnabled == true ? nil : "Unavailable — choose another route",
            image: .init(systemName: symbol.isEmpty ? "waveform" : symbol)
        )
    }
}

struct CapturePresetWidgetEntityQuery: EntityQuery, EnumerableEntityQuery {
    private let readProfiles: @Sendable () -> [CapturePresetProfile]?

    init() {
        readProfiles = {
            CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: Self.sharedDefaults())
        }
    }

    init(readProfiles: @escaping @Sendable () -> [CapturePresetProfile]?) {
        self.readProfiles = readProfiles
    }

    // Matches the existing extension entitlement and Quick Record reader. There
    // is deliberately no standard-defaults or globally selected-preset fallback.
    static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: "group.bontecou.Voxboard")
    }

    func entities(for identifiers: [String]) async throws -> [CapturePresetWidgetEntity] {
        CapturePresetWidgetCatalog.requested(
            identifiers: identifiers,
            identities: CapturePresetWidgetCatalog.identities(profiles: readProfiles() ?? [])
        ).map { CapturePresetWidgetEntity(id: $0.id, identity: $0.identity) }
    }

    func suggestedEntities() async throws -> [CapturePresetWidgetEntity] { availableEntities() }
    func allEntities() async throws -> [CapturePresetWidgetEntity] { availableEntities() }

    /// Optional slots must stay empty until explicitly chosen by the user.
    func defaultResult() async -> CapturePresetWidgetEntity? { nil }

    private func availableEntities() -> [CapturePresetWidgetEntity] {
        let entities = CapturePresetWidgetCatalog.identities(profiles: readProfiles() ?? [])
            .filter(\.isEnabled)
            .map { CapturePresetWidgetEntity(id: $0.id, identity: $0) }
        // Routes pinned to widgets (Routes long-press menu) are offered first.
        let pinned = CapturePresetSurfacePinStore.pinnedIDs(for: .widgets, defaults: Self.sharedDefaults())
        let first = pinned.compactMap { id in entities.first { $0.id == id } }
        return first + entities.filter { !pinned.contains($0.id) }
    }
}
