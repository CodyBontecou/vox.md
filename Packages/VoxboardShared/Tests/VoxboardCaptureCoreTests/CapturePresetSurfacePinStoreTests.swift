import XCTest
@testable import VoxboardCaptureCore

final class CapturePresetSurfacePinStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "CapturePresetSurfacePinStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func test_unconfiguredSurfaceOffersEveryRoute() {
        XCTAssertFalse(CapturePresetSurfacePinStore.isConfigured(.watch, defaults: defaults))
        XCTAssertEqual(
            CapturePresetSurfacePinStore.effectivePinnedIDs(for: .watch, allIDs: ["a", "b"], defaults: defaults),
            ["a", "b"]
        )
        XCTAssertEqual(CapturePresetSurfacePinStore.pinnedIDs(for: .watch, defaults: defaults), [])
    }

    func test_pinOrderUnpinAndRemove() {
        CapturePresetSurfacePinStore.setPinned(true, id: "b", to: .keyboard, defaults: defaults)
        CapturePresetSurfacePinStore.setPinned(true, id: "a", to: .keyboard, defaults: defaults)
        CapturePresetSurfacePinStore.setPinned(true, id: "a", to: .watch, defaults: defaults)
        XCTAssertEqual(CapturePresetSurfacePinStore.pinnedIDs(for: .keyboard, defaults: defaults), ["b", "a"])
        XCTAssertEqual(CapturePresetSurfacePinStore.surfaces(for: "a", defaults: defaults), [.keyboard, .watch])
        XCTAssertEqual(
            CapturePresetSurfacePinStore.effectivePinnedIDs(for: .keyboard, allIDs: ["a"], defaults: defaults),
            ["a"]
        )

        CapturePresetSurfacePinStore.setPinned(false, id: "b", to: .keyboard, defaults: defaults)
        XCTAssertEqual(CapturePresetSurfacePinStore.pinnedIDs(for: .keyboard, defaults: defaults), ["a"])

        CapturePresetSurfacePinStore.setActionButtonRouteID("a", defaults: defaults)
        CapturePresetSurfacePinStore.remove(id: "a", defaults: defaults)
        XCTAssertEqual(CapturePresetSurfacePinStore.surfaces(for: "a", defaults: defaults), [])
        XCTAssertNil(CapturePresetSurfacePinStore.actionButtonRouteID(defaults: defaults))
        // Configured-but-empty Watch pins stay configured.
        XCTAssertTrue(CapturePresetSurfacePinStore.isConfigured(.watch, defaults: defaults))
    }
}
