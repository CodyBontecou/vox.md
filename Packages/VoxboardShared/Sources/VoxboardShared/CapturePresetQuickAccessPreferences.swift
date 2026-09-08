import Foundation
import Observation
import VoxboardCaptureCore

/// Main-actor settings/capture integration. Uses AppConstants.sharedDefaults,
/// never an independent standard-defaults preference. It owns no defaults
/// observers: hosts call reload on appearance/foregrounding and after
/// profile or cross-process defaults changes. Widget timelines use the core
/// read-only resolver instead of instantiating these seeding preferences.
@MainActor
@Observable
public final class CapturePresetQuickAccessPreferences {
    private let defaults: UserDefaults?
    private let widgetRefresh: CapturePresetWidgetRefresh

    public private(set) var state: CapturePresetQuickAccessState = .unavailable
    public private(set) var resolvedProfiles: [CapturePresetProfile] = []
    public var orderedIDs: [String] { state.orderedIDs }

    // Match capture preferences' nonisolated teardown; there are no resources
    // that require main-actor destruction.
    nonisolated deinit {}

    /// The strict persisted-profile reader does not fabricate a default when
    /// first launch has not yet written the authoritative profile store.
    public convenience init(
        defaults: UserDefaults? = AppConstants.sharedDefaults,
        widgetRefresh: CapturePresetWidgetRefresh = .live
    ) {
        self.init(
            defaults: defaults,
            authoritativeProfiles: CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults),
            widgetRefresh: widgetRefresh
        )
    }

    /// Injection path for hosts/tests with a full current profile snapshot.
    /// nil defers seeding; [] is authoritative empty. Include disabled profiles,
    /// exclude deleted/retired profiles, and never supply a fallback-only list.
    public init(
        defaults: UserDefaults?,
        authoritativeProfiles: [CapturePresetProfile]?,
        widgetRefresh: CapturePresetWidgetRefresh = .live
    ) {
        self.defaults = defaults
        self.widgetRefresh = widgetRefresh
        reload(authoritativeProfiles: authoritativeProfiles)
    }

    /// Reloads both IDs and full profiles from the same defaults domain.
    public func reload() {
        reload(authoritativeProfiles: CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults))
    }

    /// Refreshes availability/identity without pruning saved order. Only an
    /// absent preference can seed; no subsequent usage changes pin ranking.
    public func reload(authoritativeProfiles: [CapturePresetProfile]?) {
        let previous = CapturePresetQuickAccessStore.load(defaults: defaults)
        state = CapturePresetQuickAccessStore.seedIfNeeded(
            authoritativeProfiles: authoritativeProfiles,
            defaults: defaults
        )
        if previous == .absent, let authoritativeProfiles {
            let expected = Array(CapturePresetQuickAccessResolver.resolve(
                orderedIDs: authoritativeProfiles.map(\.id), profiles: authoritativeProfiles
            ).prefix(CapturePresetQuickAccessStore.initialSeedLimit).map(\.id))
            widgetRefresh.pinsDidWrite(before: previous, after: state, succeeded: state == .stored(expected))
        }
        updateResolvedProfiles(authoritativeProfiles)
    }

    /// Includes disabled saved pins; use resolvedProfiles for launch controls.
    public func isPinned(id: String) -> Bool {
        orderedIDs.contains(id)
    }

    /// Reads fresh full profiles before pruning. Fails without an authoritative
    /// read instead of erasing pins during temporary storage unavailability.
    @discardableResult
    public func setOrderedIDs(_ orderedIDs: [String]) -> Bool {
        setOrderedIDs(
            orderedIDs,
            authoritativeProfiles: CapturePresetQuickAccessStore.loadAuthoritativeProfiles(defaults: defaults)
        )
    }

    /// Settings can construct a reordered/pin/unpin array and commit once.
    /// Requires the full current set, NOT the filtered launch-control list.
    /// Failed writes refresh visible state without seeding or pretending success.
    @discardableResult
    public func setOrderedIDs(
        _ orderedIDs: [String],
        authoritativeProfiles: [CapturePresetProfile]?
    ) -> Bool {
        let previous = CapturePresetQuickAccessStore.load(defaults: defaults)
        let saved = CapturePresetQuickAccessStore.save(
            orderedIDs: orderedIDs,
            authoritativeProfiles: authoritativeProfiles,
            defaults: defaults
        )
        state = CapturePresetQuickAccessStore.load(defaults: defaults)
        widgetRefresh.pinsDidWrite(before: previous, after: state, succeeded: saved)
        updateResolvedProfiles(authoritativeProfiles)
        return saved
    }

    private func updateResolvedProfiles(_ profiles: [CapturePresetProfile]?) {
        resolvedProfiles = CapturePresetQuickAccessResolver.resolve(
            orderedIDs: orderedIDs,
            profiles: profiles ?? []
        )
    }
}
