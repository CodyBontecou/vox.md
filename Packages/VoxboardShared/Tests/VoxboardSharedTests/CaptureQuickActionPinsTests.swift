import Foundation
import Testing
@testable import VoxboardShared

@Suite("Per-route quick-action pins")
struct CaptureQuickActionPinsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "CaptureQuickActionPinsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func routeWithoutOverrideFallsBackToDefaultRow() {
        let pins = CaptureQuickActionPins(
            defaultPins: [.checklist, .tag],
            routePins: ["tasks": [.dueDate]]
        )
        #expect(pins.pins(forRoute: "tasks") == [.dueDate])
        #expect(pins.pins(forRoute: "journal") == [.checklist, .tag])
        #expect(pins.pins(forRoute: nil) == [.checklist, .tag])
        #expect(pins.hasCustomPins(forRoute: "tasks"))
        #expect(!pins.hasCustomPins(forRoute: "journal"))
    }

    @Test func otherSurfacesFollowRoutePinsOnlyWhileSyncing() {
        var pins = CaptureQuickActionPins(defaultPins: [.tag], routePins: ["tasks": [.checklist]])
        #expect(pins.pinsForOtherSurface(route: "tasks") == [.checklist])
        pins.syncsAcrossSurfaces = false
        #expect(pins.pinsForOtherSurface(route: "tasks") == nil)
    }

    @Test func saveAndLoadRoundTrip() {
        let defaults = makeDefaults()
        let pins = CaptureQuickActionPins(
            defaultPins: [.timestamp, .checklist],
            routePins: ["tasks": [.checklist, .dueDate], "journal": [.date, .currentLocation]],
            syncsAcrossSurfaces: false
        )
        pins.save(to: defaults)
        #expect(CaptureQuickActionPins.load(from: defaults) == pins)
    }

    @Test func loadWithoutDefaultsOrDataUsesBuiltInDefault() {
        #expect(CaptureQuickActionPins.load(from: nil) == CaptureQuickActionPins())
        let loaded = CaptureQuickActionPins.load(from: makeDefaults())
        #expect(loaded.defaultPins == CaptureQuickActionPins.builtInDefault)
        #expect(loaded.routePins.isEmpty)
        #expect(loaded.syncsAcrossSurfaces)
    }

    @Test func loadDropsUnknownAndDuplicateActions() throws {
        let defaults = makeDefaults()
        let routes = try JSONEncoder().encode(["tasks": ["checklist", "retired", "checklist", "tag"]])
        defaults.set(routes, forKey: CaptureQuickActionPins.routePinsKey)
        let loaded = CaptureQuickActionPins.load(from: defaults)
        #expect(loaded.routePins["tasks"] == [.checklist, .tag])
        #expect(CaptureQuickActionPins.sanitized(["bold", "bold", "nope", "italic"]) == [.bold, .italic])
    }

    @Test func sharedTimestampFormatReadsMirroredRawValue() {
        let defaults = makeDefaults()
        #expect(CaptureQuickActionPins.sharedTimestampFormat(from: defaults) == nil)
        defaults.set("24-hour", forKey: CaptureQuickActionPins.sharedTimestampFormatKey)
        #expect(CaptureQuickActionPins.sharedTimestampFormat(from: defaults) == .twentyFourHour)
        defaults.set("bogus", forKey: CaptureQuickActionPins.sharedTimestampFormatKey)
        #expect(CaptureQuickActionPins.sharedTimestampFormat(from: defaults) == nil)
    }
}
