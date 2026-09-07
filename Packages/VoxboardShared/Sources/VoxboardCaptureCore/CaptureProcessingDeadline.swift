import Foundation

public struct CaptureProcessingTimeout: Error, Sendable {
    public init() {}
}

/// Returns at the deadline even if an optional processor ignores cancellation.
/// Operations must only return values: they must never publish or persist results.
public func withCaptureProcessingDeadline<T: Sendable>(
    timeout: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try Task.checkCancellation()
    guard timeout.isFinite, timeout > 0 else { throw CaptureProcessingTimeout() }
    let race = CaptureDeadlineRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            guard race.install(continuation) else { return }
            let work = Task.detached {
                do {
                    try Task.checkCancellation()
                    guard !race.isFinished else { return }
                    race.finish(.success(try await operation()))
                } catch {
                    race.finish(.failure(error))
                }
            }
            let timer = Task.detached {
                do {
                    try await Task.sleep(nanoseconds: UInt64(min(timeout, 86_400) * 1_000_000_000))
                    race.finish(.failure(CaptureProcessingTimeout()))
                } catch { /* The operation or parent already completed. */ }
            }
            race.install(tasks: [work, timer])
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

/// The lock protects completion and handles cancellation before task installation.
private final class CaptureDeadlineRace<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<T, Error>?
    private var continuation: CheckedContinuation<T, Error>?
    private var tasks: [Task<Void, Never>] = []

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return result != nil
    }

    func install(_ continuation: CheckedContinuation<T, Error>) -> Bool {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func install(tasks: [Task<Void, Never>]) {
        lock.lock()
        let finished = result != nil
        if !finished { self.tasks = tasks }
        lock.unlock()
        if finished { tasks.forEach { $0.cancel() } }
    }

    func finish(_ result: Result<T, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        let tasks = self.tasks
        self.continuation = nil
        self.tasks = []
        lock.unlock()
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
