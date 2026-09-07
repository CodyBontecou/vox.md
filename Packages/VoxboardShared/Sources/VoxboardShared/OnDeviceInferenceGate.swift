import Foundation

/// An expired model call owns its slot until it actually returns. Optional new
/// work fails promptly instead of queueing behind it or creating runaway sessions.
public actor OnDeviceInferenceGate {
    public static let shared = OnDeviceInferenceGate()
    private var isRunning = false

    public init() {}

    public func run<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard !isRunning else { throw LLMBackendFailure.busy }
        isRunning = true
        defer { isRunning = false }
        return try await operation()
    }
}
