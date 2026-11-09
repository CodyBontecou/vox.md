import Foundation

enum LLMBackendFailure: Error { case busy }

@main struct Reproduction {
    static func main() async throws {
        let gate = OnDeviceInferenceGate()
        do {
            _ = try await withCaptureProcessingDeadline(timeout: 0.03) {
                try await gate.run {
                    await withCheckedContinuation { continuation in
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.65) { continuation.resume(returning: 7) }
                    }
                }
            }
            fatalError("expected timeout")
        } catch is CaptureProcessingTimeout { print("deadline returned while work retained its slot") }
        do { _ = try await gate.run { 9 }; fatalError("expected busy") }
        catch LLMBackendFailure.busy { print("busy guard correctly retained the slot") }
        try await Task.sleep(nanoseconds: 300_000_000)
        do { _ = try await gate.run { 11 }; fatalError("late completion should reproduce busy") }
        catch LLMBackendFailure.busy { print("REPRODUCED: original test's 300ms recovery assumption throws busy") }
        try await Task.sleep(nanoseconds: 450_000_000)
        let recovered = try await gate.run { 11 }
        precondition(recovered == 11)
        print("production gate releases normally after the actual operation returns")
    }
}
