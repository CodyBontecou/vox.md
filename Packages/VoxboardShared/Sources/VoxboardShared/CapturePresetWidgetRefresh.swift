import Foundation
import VoxboardCaptureCore
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Write-boundary adapter. Injection uses the caller's defaults/readback only;
/// it never falls back to another suite, seeds pins, or changes selection state.
/// Tests can supply a recorder (or .disabled) without invoking WidgetCenter.
public struct CapturePresetWidgetRefresh: Sendable {
    private let requestReload: @Sendable () -> Void

    public init(requestReload: @escaping @Sendable () -> Void) {
        self.requestReload = requestReload
    }

    public static let disabled = Self(requestReload: {})
    public static let live = Self {
        Task { @MainActor in scheduler.request() }
    }

    public func profilesDidWrite(before: Data?, written: Data, defaults: UserDefaults) {
        guard defaults.data(forKey: CapturePresetProfileStore.profilesKey) == written,
              CapturePresetWidgetReload.profilesChanged(before: before, after: written) else { return }
        requestReload()
    }

    public func pinsDidWrite(
        before: CapturePresetQuickAccessState,
        after: CapturePresetQuickAccessState,
        succeeded: Bool
    ) {
        guard CapturePresetWidgetReload.pinsChanged(before: before, after: after, succeeded: succeeded) else { return }
        requestReload()
    }

    @MainActor
    private static let scheduler = CapturePresetWidgetReloadDebouncer(schedule: { action in
        let task = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(250)) }
            catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
        return { task.cancel() }
    }, reload: { kind in
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        #endif
    })
}
