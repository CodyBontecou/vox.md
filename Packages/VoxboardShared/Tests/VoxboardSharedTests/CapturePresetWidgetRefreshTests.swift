import XCTest
@testable import VoxboardShared

final class CapturePresetWidgetRefreshTests: XCTestCase {
    func testActualAdapterRequiresMatchingReadbackAndRelevantChange() throws {
        let counter = WidgetRefreshCounter()
        let refresh = CapturePresetWidgetRefresh { counter.increment() }
        let suite = "capture-widget-refresh.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let a = CapturePresetProfile(id: "a", name: "A", symbolName: "waveform")
        let before = try JSONEncoder().encode([a])
        var b = a
        b.name = "Renamed"
        let after = try JSONEncoder().encode([b])
        defaults.set(before, forKey: CapturePresetProfileStore.profilesKey)
        refresh.profilesDidWrite(before: before, written: after, defaults: defaults)
        XCTAssertEqual(counter.count, 0, "A failed/replaced write cannot reload")
        defaults.set(after, forKey: CapturePresetProfileStore.profilesKey)
        refresh.profilesDidWrite(before: before, written: after, defaults: defaults)
        XCTAssertEqual(counter.count, 1)
        refresh.profilesDidWrite(before: after, written: after, defaults: defaults)
        XCTAssertEqual(counter.count, 1)
        b.capturePrompt = "Unrelated edit"
        let unrelated = try JSONEncoder().encode([b])
        defaults.set(unrelated, forKey: CapturePresetProfileStore.profilesKey)
        refresh.profilesDidWrite(before: after, written: unrelated, defaults: defaults)
        XCTAssertEqual(counter.count, 1)
        XCTAssertNil(defaults.object(forKey: CapturePresetQuickAccessStore.storageKey))
        XCTAssertNil(defaults.object(forKey: CapturePresetProfileStore.selectedProfileIDKey))
    }

    func testIsolatedDomainsDoNotBorrowEachOthersSuccessfulReadback() throws {
        let counter = WidgetRefreshCounter()
        let refresh = CapturePresetWidgetRefresh { counter.increment() }
        let firstSuite = "capture-widget-first.\(UUID().uuidString)"
        let secondSuite = "capture-widget-second.\(UUID().uuidString)"
        let first = try XCTUnwrap(UserDefaults(suiteName: firstSuite))
        let second = try XCTUnwrap(UserDefaults(suiteName: secondSuite))
        defer {
            first.removePersistentDomain(forName: firstSuite)
            second.removePersistentDomain(forName: secondSuite)
        }
        let data = try JSONEncoder().encode([CapturePresetProfile(id: "a", name: "A", symbolName: "waveform")])
        first.set(data, forKey: CapturePresetProfileStore.profilesKey)
        refresh.profilesDidWrite(before: nil, written: data, defaults: second)
        XCTAssertEqual(counter.count, 0)
        refresh.profilesDidWrite(before: nil, written: data, defaults: first)
        XCTAssertEqual(counter.count, 1)
        XCTAssertNil(second.object(forKey: CapturePresetProfileStore.profilesKey))
    }

    func testActualAdapterDoesNotReloadFailedOrNoopPins() {
        let counter = WidgetRefreshCounter()
        let refresh = CapturePresetWidgetRefresh { counter.increment() }
        refresh.pinsDidWrite(before: .absent, after: .stored([]), succeeded: false)
        refresh.pinsDidWrite(before: .stored([]), after: .stored([]), succeeded: true)
        XCTAssertEqual(counter.count, 0)
        refresh.pinsDidWrite(before: .absent, after: .stored([]), succeeded: true)
        refresh.pinsDidWrite(before: .stored([]), after: .stored(["b", "a"]), succeeded: true)
        XCTAssertEqual(counter.count, 2)
    }
}

/// All test requests above are synchronous. Never invokes the live WidgetCenter sink.
private final class WidgetRefreshCounter: @unchecked Sendable {
    var count = 0
    func increment() { count += 1 }
}
