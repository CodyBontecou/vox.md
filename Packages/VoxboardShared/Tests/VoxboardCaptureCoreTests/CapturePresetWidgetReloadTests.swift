import XCTest
@testable import VoxboardCaptureCore

final class CapturePresetWidgetReloadTests: XCTestCase {
    func testProfileChangesOnlyTrackIdentityAvailabilityAndOrder() throws {
        let a = CapturePresetProfile(id: "a", name: "A", symbolName: "waveform")
        let b = CapturePresetProfile(id: "b", name: "B", symbolName: "book")
        let before = try JSONEncoder().encode([a, b])
        XCTAssertFalse(CapturePresetWidgetReload.profilesChanged(before: before, after: before))
        var irrelevant = a
        irrelevant.capturePrompt = "New prompt"
        irrelevant.captureDestinationID = UUID()
        irrelevant.locationPolicy.isEnabled = true
        XCTAssertFalse(CapturePresetWidgetReload.profilesChanged(before: before, after: try JSONEncoder().encode([irrelevant, b])))
        for changed in [
            CapturePresetProfile(id: "a", name: "Rename", symbolName: "waveform"),
            CapturePresetProfile(id: "a", name: "A", symbolName: "book"),
            CapturePresetProfile(id: "a", name: "A", symbolName: "waveform", emoji: "🇯🇵"),
            CapturePresetProfile(id: "a", name: "A", symbolName: "waveform", isEnabled: false),
        ] {
            XCTAssertTrue(CapturePresetWidgetReload.profilesChanged(before: before, after: try JSONEncoder().encode([changed, b])))
        }
        XCTAssertTrue(CapturePresetWidgetReload.profilesChanged(before: before, after: try JSONEncoder().encode([b, a])))
        XCTAssertTrue(CapturePresetWidgetReload.profilesChanged(before: before, after: try JSONEncoder().encode([a])))
        XCTAssertTrue(CapturePresetWidgetReload.profilesChanged(before: nil, after: before))
        XCTAssertFalse(CapturePresetWidgetReload.profilesChanged(before: before, after: Data("bad".utf8)))
    }

    func testPinSeedEmptyReorderNoopAndFailure() {
        XCTAssertTrue(CapturePresetWidgetReload.pinsChanged(before: .absent, after: .stored([]), succeeded: true))
        XCTAssertTrue(CapturePresetWidgetReload.pinsChanged(before: .stored(["a", "b"]), after: .stored(["b", "a"]), succeeded: true))
        XCTAssertTrue(CapturePresetWidgetReload.pinsChanged(before: .stored(["a"]), after: .stored([]), succeeded: true))
        XCTAssertFalse(CapturePresetWidgetReload.pinsChanged(before: .stored(["a"]), after: .stored(["a"]), succeeded: true))
        XCTAssertFalse(CapturePresetWidgetReload.pinsChanged(before: .absent, after: .absent, succeeded: true))
        XCTAssertFalse(CapturePresetWidgetReload.pinsChanged(before: .absent, after: .stored(["a"]), succeeded: false))
        XCTAssertFalse(CapturePresetWidgetReload.pinsChanged(before: .absent, after: .malformed, succeeded: true))
    }

    @MainActor
    func testDebounceCancelsAndIgnoresStaleCallbacksAndReloadsOnlyNewKind() {
        var actions: [@MainActor () -> Void] = []
        var cancellations = 0
        var kinds: [String] = []
        let debouncer = CapturePresetWidgetReloadDebouncer(schedule: { action in
            actions.append(action)
            return { cancellations += 1 }
        }, reload: { kinds.append($0) })
        debouncer.request()
        debouncer.request()
        debouncer.request()
        XCTAssertEqual(cancellations, 2)
        actions[0]()
        actions[1]()
        XCTAssertEqual(kinds, [])
        actions[2]()
        actions[2]()
        XCTAssertEqual(kinds, ["VoxboardCapturePresetsWidget"])
        debouncer.request()
        actions[3]()
        XCTAssertEqual(kinds, ["VoxboardCapturePresetsWidget", "VoxboardCapturePresetsWidget"])
    }
}
