import XCTest
@testable import VoxboardShared

final class CapturePresetDeletionFallbackTests: XCTestCase {
    private func route(_ id: String, enabled: Bool = true, destination: Bool = true) -> CapturePreset {
        var preset = CapturePresetStore.makeCustomFlow()
        preset.id = id
        preset.isEnabled = enabled
        preset.captureDestinationID = destination ? UUID() : nil
        return preset
    }

    func test_deletingActiveRouteSelectsAnotherDeliverableRoute() {
        let presets = [CapturePresetStore.defaultFlow, route("inbox"), route("journal")]

        XCTAssertEqual(CapturePresetStore.fallbackPresetID(afterDeleting: "inbox", from: presets), "journal")
    }

    func test_fallbackSkipsDisabledAndDestinationlessRoutes() {
        let presets = [
            CapturePresetStore.defaultFlow,
            route("inbox"),
            route("off", enabled: false),
            route("unrouted", destination: false),
            route("tasks"),
        ]

        XCTAssertEqual(CapturePresetStore.fallbackPresetID(afterDeleting: "inbox", from: presets), "tasks")
    }

    func test_fallbackUsesDefaultOnlyWhenNothingElseRemains() {
        let presets = [CapturePresetStore.defaultFlow, route("inbox")]

        XCTAssertEqual(
            CapturePresetStore.fallbackPresetID(afterDeleting: "inbox", from: presets),
            CapturePresetStore.generalId
        )
    }
}
