import Foundation
import Observation

/// A host-owned opportunity to execute HTTP. iOS supplies a finite background
/// lease; Mac supplies an unrestricted foreground opportunity. Expiration must
/// cancel the task, not start a second retry worker.
public struct URLDeliveryExecutionLease: Sendable {
    private let endBody: @MainActor @Sendable () -> Void

    public init(end: @escaping @MainActor @Sendable () -> Void = {}) { endBody = end }

    @MainActor public func end() { endBody() }
}

@MainActor
@Observable
public final class URLDeliveryCoordinator {
    public typealias BeginExecution = @MainActor (
        _ onExpiration: @escaping @MainActor @Sendable () -> Void
    ) -> URLDeliveryExecutionLease?

    public private(set) var receipts: [URLDeliveryReceipt] = []
    public private(set) var activeIDs: Set<UUID> = []
    public private(set) var lastError: String?

    @ObservationIgnored private let deliverer: TranscriptURLDeliverer
    @ObservationIgnored private let beginExecution: BeginExecution
    @ObservationIgnored private var tasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var finishObservers: [UUID: @MainActor (_ id: UUID, _ result: URLDeliveryEvent.Result) -> Bool] = [:]

    public init(deliverer: TranscriptURLDeliverer, beginExecution: @escaping BeginExecution = { _ in .init() }) {
        self.deliverer = deliverer
        self.beginExecution = beginExecution
    }

    /// Reading recovery state never sends. Failed/ambiguous work is retried only
    /// through the explicit Retry action, including after app relaunch.
    public func refresh() async { receipts = await deliverer.outstandingReceipts() }

    public func enqueueCapture(
        id: UUID, text: String, date: Date, settings: CapturePresetURLDeliverySettings
    ) async -> URLDeliveryEvent {
        let event = await deliverer.enqueueCapture(id: id, text: text, date: date, settings: settings)
        await refresh()
        return event
    }

    public func enqueueTranscript(_ transcript: Transcript, settings: CapturePresetURLDeliverySettings) async -> URLDeliveryEvent {
        let event = await deliverer.enqueueTranscript(transcript, settings: settings)
        await refresh()
        return event
    }

    /// Called only after a durable enqueue returned `.queued`. Network latency
    /// is owned here and cannot hold a note sink or composer submission open.
    public func dispatch(id: UUID, cancellation: URLDeliveryCancellation? = nil) {
        start(id: id, explicitRetry: false, cancellation: cancellation)
    }

    public func retry(id: UUID, authorization: CapturePresetURLDeliverySettings? = nil) async {
        start(id: id, explicitRetry: true, authorization: authorization)
        await tasks[id]?.value
    }

    public func cancel(id: UUID) async {
        let task = tasks[id]
        task?.cancel()
        await task?.value
        await refresh()
    }

    public func discard(id: UUID) async {
        await cancel(id: id)
        do {
            try await deliverer.discardDelivery(id: id)
            lastError = nil
        } catch {
            lastError = "URL delivery could not be discarded. Wait for any active sender to stop, then try again."
        }
        await refresh()
    }

    public func cancelAll() async {
        let running = Array(tasks.values)
        running.forEach { $0.cancel() }
        for task in running { await task.value }
        await refresh()
    }

    /// Called on the main actor with the delivery ID (the capture or
    /// transcript ID) after every send attempt, first dispatch or explicit
    /// retry, finishes. Return `false` to stop observing, for example
    /// once the observer's owner has been released.
    @discardableResult
    public func addFinishObserver(
        _ observer: @escaping @MainActor (_ id: UUID, _ result: URLDeliveryEvent.Result) -> Bool
    ) -> UUID {
        let token = UUID()
        finishObservers[token] = observer
        return token
    }

    public func removeFinishObserver(_ token: UUID) { finishObservers[token] = nil }

    private func notifyFinished(id: UUID, result: URLDeliveryEvent.Result) {
        for (token, observer) in finishObservers where !observer(id, result) {
            finishObservers[token] = nil
        }
    }

    private func start(
        id: UUID, explicitRetry: Bool, authorization: CapturePresetURLDeliverySettings? = nil,
        cancellation: URLDeliveryCancellation? = nil
    ) {
        guard tasks[id] == nil, cancellation?.isCancelled != true else { return }
        activeIDs.insert(id)
        lastError = nil
        let task = Task { [self] in
            defer {
                tasks[id] = nil
                activeIDs.remove(id)
            }
            guard !Task.isCancelled else { return }
            guard let lease = beginExecution({ [weak self] in self?.tasks[id]?.cancel() }) else {
                lastError = "URL delivery is saved locally. Open URL Deliveries to send it when background execution is available."
                await refresh()
                return
            }
            defer { lease.end() }
            guard !Task.isCancelled else {
                await refresh()
                return
            }
            let event = explicitRetry
                ? await deliverer.retryPendingDelivery(id: id, authorization: authorization)
                : await deliverer.sendQueuedDelivery(id: id)
            if case .failed(let message, _) = event.result { lastError = message }
            await refresh()
            notifyFinished(id: id, result: event.result)
        }
        tasks[id] = task
        cancellation?.register { task.cancel() }
    }
}
