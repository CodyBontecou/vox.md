import Foundation

/// Bridges cancellation across an asynchronous handoff without an unowned
/// MainActor hop. Registration is race-safe: cancellation before registration
/// immediately cancels the newly registered work. Normal source completion
/// does not cancel the HTTP task now owned by URLDeliveryCoordinator.
public final class URLDeliveryCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false
    private var actions: [@Sendable () -> Void] = []

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return canceled
    }

    public func register(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        if canceled {
            lock.unlock()
            action()
        } else {
            actions.append(action)
            lock.unlock()
        }
    }

    /// Owns a host's MainActor-created delivery task through completion. The
    /// handler is installed before hopping to MainActor, so a late factory
    /// cannot launch uncancelled HTTP after its source queue has been paused.
    public func valueOfMainActorTask<Value: Sendable>(
        _ makeTask: @MainActor @Sendable () throws -> Task<Value, Never>?
    ) async throws -> Value? {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            let task = try await makeTask()
            if let task { register { task.cancel() } }
            return await task?.value
        } onCancel: { self.cancel() }
    }

    public func runDetached<Value: Sendable>(
        priority: TaskPriority, operation: @escaping @Sendable () async -> Value
    ) async -> Value {
        await withTaskCancellationHandler {
            let task = Task.detached(priority: priority, operation: operation)
            register { task.cancel() }
            return await task.value
        } onCancel: { self.cancel() }
    }

    public func cancel() {
        lock.lock()
        canceled = true
        let pending = actions
        actions.removeAll()
        lock.unlock()
        pending.forEach { $0() }
    }
}
