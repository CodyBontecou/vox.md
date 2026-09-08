import Foundation

public enum CapturePresetWidgetReload {
    public static let kind = "VoxboardCapturePresetsWidget"

    /// Compare only persisted widget identity/availability/order, not routing,
    /// processing, selection, or incidental JSON encoder byte ordering.
    public static func profilesChanged(before: Data?, after: Data) -> Bool {
        let decoder = JSONDecoder()
        guard let current = try? decoder.decode([CapturePresetProfile].self, from: after) else { return false }
        let previous = before.flatMap { try? decoder.decode([CapturePresetProfile].self, from: $0) }
        return previous.map(CapturePresetWidgetCatalog.identities) != CapturePresetWidgetCatalog.identities(profiles: current)
    }

    public static func pinsChanged(
        before: CapturePresetQuickAccessState,
        after: CapturePresetQuickAccessState,
        succeeded: Bool
    ) -> Bool {
        guard succeeded, case .stored = after else { return false }
        return before != after
    }
}

/// Main-actor scheduling only; no new store locks, threads or persisted markers.
/// The injected scheduler makes cancellation/debounce deterministic in tests.
@MainActor
public final class CapturePresetWidgetReloadDebouncer {
    public typealias Schedule = (_ action: @escaping @MainActor () -> Void) -> (() -> Void)
    private let schedule: Schedule
    private let reload: (String) -> Void
    private var cancel: (() -> Void)?
    private var generation: UUID?

    public init(schedule: @escaping Schedule, reload: @escaping (String) -> Void) {
        self.schedule = schedule
        self.reload = reload
    }

    public func request() {
        cancel?()
        let token = UUID()
        generation = token
        cancel = schedule { [weak self] in
            guard let self, self.generation == token else { return }
            self.generation = nil
            self.cancel = nil
            self.reload(CapturePresetWidgetReload.kind)
        }
    }
}
