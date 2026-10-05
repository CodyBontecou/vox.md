import Foundation
import XCTest
@testable import Voxboard

/// #22's retained freeing frames share isolated deinit's task-local stop marker,
/// not an audio/cache operation. Exercise both allocation contexts explicitly.
@MainActor
final class Issue22AllocatorDeinitTests: XCTestCase {
    func testIsolatedDeinitOutsideTaskPreservesThreadLocalBindings() async {
        let finished = expectation(description: "Task-free main-thread deinitialization")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertTrue(withUnsafeCurrentTask { $0 == nil })
                var deinitValues: [String] = []
                AllocatorProbeLocal.$value.withValue("thread-bound") {
                    for _ in 0..<64 {
                        var object: AllocatorProbeState? = AllocatorProbeState {
                            deinitValues.append($0)
                        }
                        weak var released = object
                        object = nil
                        XCTAssertNil(released)
                        XCTAssertEqual(AllocatorProbeLocal.value, "thread-bound")
                    }
                }
                XCTAssertEqual(deinitValues, Array(repeating: "unset", count: 64))
                XCTAssertEqual(AllocatorProbeLocal.value, "unset")
                finished.fulfill()
            }
        }
        await fulfillment(of: [finished], timeout: 5)
    }

    func testIsolatedDeinitInsideTaskPreservesTaskLocalBindings() async {
        XCTAssertTrue(withUnsafeCurrentTask { $0 != nil })
        var deinitValues: [String] = []
        AllocatorProbeLocal.$value.withValue("task-bound") {
            for _ in 0..<64 {
                var object: AllocatorProbeState? = AllocatorProbeState {
                    deinitValues.append($0)
                }
                weak var released = object
                object = nil
                XCTAssertNil(released)
                XCTAssertEqual(AllocatorProbeLocal.value, "task-bound")
            }
        }
        XCTAssertEqual(deinitValues, Array(repeating: "unset", count: 64))
        XCTAssertEqual(AllocatorProbeLocal.value, "unset")
    }

    func testProductionSessionDeinitOutsideTaskWithThreadLocalBinding() async {
        let finished = expectation(description: "Production isolated-deinit call site")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                XCTAssertTrue(withUnsafeCurrentTask { $0 == nil })
                AllocatorProbeLocal.$value.withValue("production-thread-bound") {
                    for _ in 0..<64 {
                        var session: ContinuousDictationSession? = ContinuousDictationSession(
                            startedAt: 1_000
                        )
                        weak var released = session
                        XCTAssertEqual(session?.sessionLimit, 600)
                        session = nil
                        XCTAssertNil(released)
                        XCTAssertEqual(AllocatorProbeLocal.value, "production-thread-bound")
                    }
                }
                XCTAssertEqual(AllocatorProbeLocal.value, "unset")
                finished.fulfill()
            }
        }
        await fulfillment(of: [finished], timeout: 5)
    }
}

private nonisolated enum AllocatorProbeLocal {
    @TaskLocal static var value = "unset"
}

@MainActor
private final class AllocatorProbeState {
    private let didDeinit: @MainActor (String) -> Void

    init(didDeinit: @escaping @MainActor (String) -> Void) {
        self.didDeinit = didDeinit
    }

    isolated deinit {
        // Isolated deinit must hide the caller's task/thread-local bindings.
        didDeinit(AllocatorProbeLocal.value)
    }
}
